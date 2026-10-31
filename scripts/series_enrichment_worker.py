#!/usr/bin/env python3
"""Bounded series copy/artwork/theme bridge. No daemon, credentials printed or name matching.

Explicit --apply is required; hosted writes additionally require --allow-hosted and separate
deployment/operator approval. Default invocation only describes the contract. Source row
triggers enqueue work; lease/revision checks in SQL reject superseded results. Backfill is
optional, PK-paged <=250, and the run processes <=20 jobs before exiting.
"""
import argparse
import hashlib
import html
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import tempfile
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ART_HOSTS = {'s4.anilist.co', 'cdn.myanimelist.net', 'bkdifromsqxkndnllmdj.supabase.co'}

def plain_copy(description):
    """Extract source text, not an invented hook or an unreviewed story verdict."""
    text = html.unescape(re.sub(r'<[^>]*>', ' ', description or ''))
    text = re.sub(r'\s+', ' ', text).strip()
    if not text:
        return None
    first = re.split(r'(?<=[.!?])\s+', text, maxsplit=1)[0]
    # Never cut a sentence mid-word just to make a stronger claim than the source.
    premise = first if len(first) <= 240 else None
    return {'premise': premise, 'synopsis': text[:16000]}

def bounded_get(url, max_bytes, allowed_hosts):
    class SameHosts(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, fp, code, message, headers, target):
            check_url(target, allowed_hosts)
            return super().redirect_request(request, fp, code, message, headers, target)
    check_url(url, allowed_hosts)
    with urllib.request.build_opener(SameHosts()).open(
            urllib.request.Request(url, headers={'User-Agent':'Kuro-series-enrichment/1.0'}), timeout=20) as response:
        body = response.read(max_bytes + 1)
    if len(body) > max_bytes:
        raise ValueError('source exceeds byte limit')
    return body

def check_url(url, hosts):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or parsed.hostname not in hosts or parsed.username or parsed.password or parsed.port not in (None,443):
        raise ValueError('source URL is outside the allowed HTTPS hosts')

def artwork(image_url, getter=bounded_get, banner=False):
    if not image_url:
        return None
    data = getter(image_url, 8*1024*1024, ART_HOSTS)
    from PIL import Image
    with Image.open(io.BytesIO(data)) as image:
        if image.width*image.height > 20_000_000:
            raise ValueError('artwork exceeds pixel limit')
        image.verify()
    module_spec = importlib.util.spec_from_file_location('kuro_art', ROOT/'tools/design-directions/build_art_materials.py')
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='kuro-art-') as directory:
        path = Path(directory)/('image-banner.jpg' if banner else 'image.jpg'); path.write_bytes(data)
        # Reuse the approved extraction algorithm; provider artwork has no manual fixture override.
        module.ROOT = Path(directory)
        result = module.material(path)
    result.update(image_url=image_url, digest=hashlib.sha256(image_url.encode()+b'\0'+data).hexdigest())
    return result

def theme_query(site, external_id, page):
    return 'https://api.animethemes.moe/anime?' + urllib.parse.urlencode({
        'filter[has]':'resources', 'filter[site]':site, 'filter[external_id]':str(external_id),
        'include':'resources,animethemes.song,animethemes.song.artists',
        'page[size]':25, 'page[number]':page})

def exact_themes(payload, getter=bounded_get, pause=time.sleep):
    if payload['medium'] != 'anime':
        return None
    # The provider resource namespace and ID must match; translated titles are irrelevant.
    site, external_id = ('AniList', payload.get('anilist_id')) if payload.get('anilist_id') else ('MyAnimeList', payload.get('mal_id'))
    if not external_id:
        return None
    matches = {}
    for page in range(1, 5):
        document = json.loads(getter(theme_query(site, external_id, page), 2*1024*1024, {'api.animethemes.moe'}))
        rows = document.get('anime')
        if not isinstance(rows, list):
            raise ValueError('unrecognized AnimeThemes response')
        for anime in rows:
            if any(resource.get('site') == site and str(resource.get('external_id')) == str(external_id)
                   for resource in anime.get('resources', [])):
                matches[anime['id']] = anime
        if not document.get('links', {}).get('next'):
            break
        if page == 4:
            raise ValueError('theme match pagination requires review')
        pause(1)
    if len(matches) > 1:
        raise ValueError('ambiguous exact-ID theme resource')
    if not matches:
        return None  # Unknown; retain last-good themes, never invent a match.
    result = []
    for theme in next(iter(matches.values())).get('animethemes', []):
        role = {0:'op',1:'ed','OP':'op','ED':'ed'}.get(theme.get('type'))
        song = theme.get('song')
        if not role or not isinstance(song, dict) or not song.get('title'):
            continue
        result.append({'source_id':str(theme['id']), 'role':role,
            'sequence_order':theme.get('sequence') or 1, 'song_title':song['title'],
            'artist':', '.join(artist['name'] for artist in song.get('artists', []) if artist.get('name'))})
    if len(result) > 30:
        raise ValueError('theme count exceeds bounded contract')
    return result

class RPC:
    def __init__(self, allow_hosted):
        self.url = os.environ['SUPABASE_URL'].rstrip('/')
        self.key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
        parsed = urllib.parse.urlsplit(self.url)
        local = parsed.hostname in ('localhost','127.0.0.1','::1')
        if not local and not allow_hosted:
            raise ValueError('hosted writes require explicit --allow-hosted after operator approval')
        if parsed.username or parsed.password or (not local and parsed.scheme != 'https'):
            raise ValueError('invalid backend destination')

    def call(self, name, payload):
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, message, headers, target):
                raise ValueError('authenticated RPC redirects are forbidden')
        request = urllib.request.Request(self.url+'/rest/v1/rpc/'+name,
            data=json.dumps(payload).encode(), method='POST', headers={
            'Content-Type':'application/json', 'apikey':self.key, 'Authorization':'Bearer '+self.key})
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=25) as response:
            body = response.read(2*1024*1024+1)
        if len(body) > 2*1024*1024:
            raise ValueError('RPC exceeds byte limit')
        return json.loads(body)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--allow-hosted', action='store_true')
    parser.add_argument('--limit', type=int, default=10)
    parser.add_argument('--backfill-medium', choices=('anime','manga'))
    parser.add_argument('--after-id', type=int, default=0)
    args = parser.parse_args()
    if not args.apply:
        print('DRY CONTRACT: catalogue change -> leased bounded worker -> last-good copy/artwork/themes. No requests made.')
        return
    client = RPC(args.allow_hosted)
    if args.backfill_medium:
        print(json.dumps(client.call('backfill_series_enrichment_v1', {
            'p_medium':args.backfill_medium,'p_after_id':args.after_id,'p_limit':250})))
    # Claim immediately before each extraction. Reserving 20 sequential jobs with a
    # five-minute lease can expire the last jobs before work even starts.
    for _ in range(max(1,min(20,args.limit))):
        jobs = client.call('claim_series_enrichment_v1', {'p_limit':1})
        if not jobs:
            break
        job = jobs[0]
        params = {'p_medium':job['medium'], 'p_media_id':job['media_id'],
                  'p_source_revision':job['source_revision'], 'p_lease_token':job['lease_token']}
        try:
            params.update(p_copy=plain_copy(job['payload'].get('description')),
                          p_material=artwork(job['payload'].get('image_url'), banner=job['medium']=='anime'),
                          p_themes=exact_themes(job['payload']))
        except Exception as error:
            # Never include response bodies/URLs/credentials or erase last-good data on failure.
            params = {key:params[key] for key in ('p_medium','p_media_id','p_source_revision','p_lease_token')}
            params['p_error'] = type(error).__name__
        result = client.call('finish_series_enrichment_v1', params)
        print(json.dumps({'medium':job['medium'],'media_id':job['media_id'],'outcome':result['outcome']}))
        time.sleep(1)

if __name__ == '__main__':
    main()
