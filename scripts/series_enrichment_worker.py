#!/usr/bin/env python3
"""Bounded series copy/artwork bridge plus a batched AnimeThemes theme pass. Manual only.

No daemon, no schedule, no credentials printed, no name matching.
Explicit --apply is required; hosted writes additionally require --allow-hosted and separate
deployment/operator approval. Default invocation only describes the contract and makes no request.

Job mode (default with --apply): source row triggers enqueue work; lease/revision checks in SQL
reject superseded results. Backfill is optional, PK-paged <=250, and the run processes <=20 jobs.
Jobs carry copy and artwork only; themes are no longer coupled to artwork (p_themes is omitted,
which keeps last-good themes).

Theme mode (--themes): AnimeThemes GraphQL findAnimeByExternalSite(site: ANILIST, id: [...]) in
batches of <=25 AniList ids, at most 90 requests/minute (Retry-After honoured), exact external-id
match only (an id claimed by two AnimeThemes entries is skipped), one row per theme entry
(version, episodes, spoiler, nsfw) written through upsert_theme_links_v1. Not-found titles and
titles without themes write nothing. AnimeThemes commercial use needs owner endorsement
(decision D11); this pass is not scheduled anywhere.

Apple mode (--apple, 2026-11-03): for theme_links rows not checked in the last 30 days, the iTunes
Search API (https://itunes.apple.com/search?term=...&entity=song&limit=10, storefront JP first,
then US) at most 20 requests/minute (one every 3 s, Retry-After honoured, User-Agent Kuro-Intake).
Strict matching: the normalised title AND artist must both match (NFKC, case, macrons and
Hepburn long vowels folded, "wo"/"o"; artist sets split on feat./&/,/x; family-name order
tolerated); karaoke/instrumental/off-vocal/remix/cover variants are rejected; confidence >= 0.8 or
no match. A row without an artist is recorded as checked with no match (it cannot be verified)
without any request. Results go through upsert_theme_apple_matches_v1 (prepared migration
20261103100200); --dry-run prints the proposed matches and writes nothing. Not scheduled.
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
import unicodedata
from difflib import SequenceMatcher
import urllib.error
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

THEMES_GRAPHQL = 'https://graphql.animethemes.moe/'
THEMES_HOSTS = {'graphql.animethemes.moe'}
THEMES_BATCH = 25
THEMES_MIN_INTERVAL = 60.0 / 90  # AnimeThemes: 90 requests/minute
THEMES_QUERY = """query ($ids: [Int!]) {
  findAnimeByExternalSite(site: ANILIST, id: $ids) {
    id slug
    resources { edges { node { site externalId } } }
    animethemes {
      id type sequence
      song { title { romaji native } performances { as alias artist { __typename ... on Artist { name { main } } } } }
      animethemeentries { id episodes nsfw spoiler version }
    }
  }
}"""
MAX_THEME_ROWS_PER_ANIME = 60
WRITER_BATCH = 500

class Pacer:
    """Minimum spacing between provider requests (injected clock/sleep for tests)."""
    def __init__(self, interval, clock=time.monotonic, pause=time.sleep):
        self.interval, self.clock, self.pause, self.next_at = interval, clock, pause, 0.0
    def wait(self):
        delay = self.next_at - self.clock()
        if delay > 0:
            self.pause(delay)
        self.next_at = self.clock() + self.interval

def bounded_post_json(url, payload, max_bytes, allowed_hosts):
    class SameHosts(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, fp, code, message, headers, target):
            raise ValueError('provider redirects are not followed')
    check_url(url, allowed_hosts)
    request = urllib.request.Request(url, data=json.dumps(payload).encode(), method='POST', headers={
        'Content-Type':'application/json', 'Accept':'application/json', 'User-Agent':'Kuro-series-enrichment/1.1'})
    with urllib.request.build_opener(SameHosts()).open(request, timeout=25) as response:
        body = response.read(max_bytes + 1)
    if len(body) > max_bytes:
        raise ValueError('provider response exceeds byte limit')
    return json.loads(body)

def fetch_theme_batch(anilist_ids, poster=bounded_post_json, pacer=None, pause=time.sleep):
    """One GraphQL request for <=25 AniList ids. GraphQL errors raise; 429 waits Retry-After (<=65 s)."""
    ids = [int(i) for i in anilist_ids]
    if not ids or len(ids) > THEMES_BATCH:
        raise ValueError('theme batch must hold 1..25 ids')
    for attempt in range(3):
        if pacer:
            pacer.wait()
        try:
            document = poster(THEMES_GRAPHQL, {'query': THEMES_QUERY, 'variables': {'ids': ids}},
                              4*1024*1024, THEMES_HOSTS)
        except urllib.error.HTTPError as error:
            if error.code == 429 and attempt < 2:
                retry = error.headers.get('Retry-After') if error.headers else None
                pause(min(65.0, float(retry)) if retry and re.fullmatch(r'\d+(\.\d+)?', retry) else 60.0)
                continue
            raise
        if document.get('errors'):
            raise ValueError('AnimeThemes GraphQL error')
        rows = (document.get('data') or {}).get('findAnimeByExternalSite')
        if not isinstance(rows, list):
            raise ValueError('unrecognized AnimeThemes response')
        return rows
    raise ValueError('AnimeThemes rate limit persisted')

def match_by_anilist_id(anime_rows, requested):
    """Exact external-id match. An id claimed by more than one AnimeThemes anime is dropped."""
    wanted = {int(i) for i in requested}
    claims = {}
    for anime in anime_rows:
        edges = ((anime.get('resources') or {}).get('edges')) or []
        ids = {int(edge['node']['externalId']) for edge in edges
               if isinstance(edge, dict) and isinstance(edge.get('node'), dict)
               and edge['node'].get('site') == 'ANILIST' and isinstance(edge['node'].get('externalId'), int)}
        for anilist_id in ids & wanted:
            claims.setdefault(anilist_id, []).append(anime)
    matched = {k: v[0] for k, v in claims.items() if len(v) == 1}
    ambiguous = sorted(k for k, v in claims.items() if len(v) > 1)
    return matched, ambiguous

def _artist_names(song):
    names = []
    for performance in song.get('performances') or []:
        artist = (performance or {}).get('artist') or {}
        name = ((artist.get('name') or {}).get('main') or '').strip()
        if name and name not in names:
            names.append(name)
    return ', '.join(names)[:500] or None

def theme_rows(anime_id, anime):
    """upsert_theme_links_v1 rows for one AnimeThemes anime: one row per theme entry (version).

    source_id is the theme id for the first entry (the key finish_series_enrichment_v1 already
    used, so both producers converge) and '<theme>.v<version>' / '<theme>.e<entry>' for others.
    """
    slug = anime.get('slug') if isinstance(anime.get('slug'), str) and re.fullmatch(r'[a-z0-9_]{1,120}', anime.get('slug')) else None
    source_url = f'https://animethemes.moe/anime/{slug}' if slug else None
    rows = []
    for theme in anime.get('animethemes') or []:
        kind = theme.get('type')
        song = theme.get('song') or {}
        title_obj = song.get('title') or {}
        title = (title_obj.get('romaji') or title_obj.get('native') or '').strip() if isinstance(title_obj, dict) else ''
        if kind not in ('OP', 'ED', 'IN') or not title or not isinstance(theme.get('id'), int):
            continue
        sequence = theme.get('sequence') if isinstance(theme.get('sequence'), int) and 1 <= theme.get('sequence') <= 99 else 1
        entries = sorted([e for e in theme.get('animethemeentries') or [] if isinstance(e, dict) and isinstance(e.get('id'), int)],
                         key=lambda e: (e.get('version') or 1, e['id'])) or [None]
        used = set()
        for index, entry in enumerate(entries):
            version = entry.get('version') if entry and isinstance(entry.get('version'), int) and 1 <= entry.get('version') <= 99 else None
            if index == 0:
                source_id = str(theme['id'])
            elif version and f"{theme['id']}.v{version}" not in used:
                source_id = f"{theme['id']}.v{version}"
            else:
                source_id = f"{theme['id']}.e{entry['id']}"
            used.add(source_id)
            episodes = (entry.get('episodes') or '').strip() if entry and isinstance(entry.get('episodes'), str) else ''
            rows.append({'anime_id': anime_id, 'source_id': source_id, 'kind': kind, 'sequence': sequence,
                         'version': version, 'title': title[:300], 'artist': _artist_names(song),
                         'episodes': episodes[:64] or None,
                         'is_spoiler': bool(entry and entry.get('spoiler') is True),
                         'is_nsfw': bool(entry and entry.get('nsfw') is True),
                         'source': 'animethemes', 'source_url': source_url})
    if len(rows) > MAX_THEME_ROWS_PER_ANIME:
        raise ValueError('theme count exceeds bounded contract')
    return rows

def run_theme_pass(client, candidates, fetch=fetch_theme_batch, pacer=None):
    """candidates: [{'id': kuro anime id, 'anilist_id': int}]. Returns a summary dict (no secrets)."""
    by_anilist = {}
    for row in candidates:
        if isinstance(row.get('anilist_id'), int) and isinstance(row.get('id'), int):
            by_anilist.setdefault(row['anilist_id'], row['id'])
    ids = list(by_anilist)
    summary = {'requested': len(ids), 'requests': 0, 'matched': 0, 'not_found': 0, 'ambiguous': 0,
               'rows': 0, 'inserted': 0, 'updated': 0, 'unchanged': 0, 'oversized': 0}
    pending = []
    def flush():
        while pending:
            chunk, pending[:] = pending[:WRITER_BATCH], pending[WRITER_BATCH:]
            result = client.call('upsert_theme_links_v1', {'p_rows': chunk}) or {}
            for key in ('inserted', 'updated', 'unchanged'):
                summary[key] += int(result.get(key, 0) or 0)
    for start in range(0, len(ids), THEMES_BATCH):
        batch = ids[start:start+THEMES_BATCH]
        anime_rows = fetch(batch, pacer=pacer)
        summary['requests'] += 1
        matched, ambiguous = match_by_anilist_id(anime_rows, batch)
        summary['ambiguous'] += len(ambiguous)
        summary['not_found'] += len([i for i in batch if i not in matched and i not in ambiguous])
        for anilist_id, anime in matched.items():
            try:
                rows = theme_rows(by_anilist[anilist_id], anime)
            except ValueError:
                # Over the per-title row bound: skip this title (last-good kept), not the whole pass.
                summary['oversized'] += 1
                continue
            if not rows:
                continue  # Unknown; retain last-good themes, never write an empty set.
            summary['matched'] += 1
            summary['rows'] += len(rows)
            pending.extend(rows)
        if len(pending) >= WRITER_BATCH:
            flush()
    flush()
    return summary

# ---------------------------------------------------------------------------------------------
# Apple pass (--apple): iTunes Search API artwork + 30-second preview + Apple Music link.
# ---------------------------------------------------------------------------------------------
ITUNES_SEARCH = 'https://itunes.apple.com/search'
ITUNES_HOSTS = {'itunes.apple.com'}
APPLE_COUNTRIES = ('JP', 'US')
APPLE_MIN_INTERVAL = 3.0  # <= 20 requests/minute
APPLE_USER_AGENT = 'Kuro-Intake/1.0'
APPLE_MIN_CONFIDENCE = 0.8
APPLE_TITLE_MIN_RATIO = 0.9
APPLE_RECHECK_DAYS = 30
APPLE_MAX_ROWS_PER_RUN = 200
APPLE_ARTWORK_RE = re.compile(r'^https://[a-z0-9-]+\.mzstatic\.com/\S+$')
APPLE_PREVIEW_RE = re.compile(r'^https://(audio-ssl\.itunes\.apple\.com|[a-z0-9-]+\.mzstatic\.com)/\S+$')
APPLE_MUSIC_RE = re.compile(r'^https://(music|itunes)\.apple\.com/\S+$')
# A result naming one of these (when the theme title does not) is a different recording.
APPLE_VARIANT_WORDS = ('instrumental', 'karaoke', 'off vocal', 'offvocal', 'off-vocal', 'remix', 'cover',
                       'acoustic', 'piano ver', 'music box', 'orgel', 'inst.', 'backing track', '8-bit', 'lofi', 'lo-fi')
# Size/edit tags that keep the same recording (stripped before comparing; the full version wins ties).
APPLE_SIZE_TAG_RE = re.compile(
    r'[\(\[\-~～－]\s*(tv\s*size|tv\s*ver(sion|\.)?|tv\s*edit|anime\s*(ver(sion|\.)?|edit|size)|short\s*ver(sion|\.)?|op\s*ver(sion|\.)?|ed\s*ver(sion|\.)?)\s*[\)\]\-~～－]?',
    re.IGNORECASE)
# Credit separators. " x " / "vs." only between spaces, so "X JAPAN" stays one name; "and"/"with"
# are not separators (band names use them).
ARTIST_SPLIT_RE = re.compile(r'\s*(?:,|&|＆|/|、|×|\bfeat\.?(?=\s)|\bft\.?(?=\s)|\bfeaturing\b|(?<=\s)(?:x|vs\.?)(?=\s))\s*',
                             re.IGNORECASE)

def _fold(text):
    """NFKC, case-folded, macrons stripped, Hepburn long vowels and the particle wo folded."""
    t = unicodedata.normalize('NFKC', text or '').casefold()
    t = ''.join(c for c in unicodedata.normalize('NFKD', t) if not unicodedata.combining(c))
    t = unicodedata.normalize('NFKC', t)
    t = re.sub(r'\bwo\b', 'o', t)
    for long_vowel, short in (('ou', 'o'), ('oo', 'o'), ('uu', 'u'), ('aa', 'a'), ('ii', 'i'), ('ee', 'e')):
        t = t.replace(long_vowel, short)
    return t

def normalise_title(text):
    """Comparable title: size/edit tags removed, folded, punctuation and spaces dropped."""
    t = APPLE_SIZE_TAG_RE.sub(' ', unicodedata.normalize('NFKC', text or ''))
    return re.sub(r'[\W_]+', '', _fold(t))

def artist_names(text):
    names = []
    for part in ARTIST_SPLIT_RE.split(unicodedata.normalize('NFKC', text or '')):
        name = re.sub(r'\(cv[.:]?[^)]*\)', '', part or '', flags=re.IGNORECASE)
        name = re.sub(r'[\W_]+', ' ', _fold(name)).strip()
        if name and name not in names:
            names.append(name)
    return names

def _same_person(a, b):
    """Equal names, or the same tokens in another order (family-name first)."""
    return a == b or sorted(a.split()) == sorted(b.split()) or a.replace(' ', '') == b.replace(' ', '')

def artist_score(theme_artist, apple_artist):
    """1.0 same artist set, 0.9 the theme's artists are all credited by Apple (Apple adds a guest), else 0."""
    mine, theirs = artist_names(theme_artist), artist_names(apple_artist)
    if not mine or not theirs:
        return 0.0
    covered = [any(_same_person(m, t) for t in theirs) for m in mine]
    back = [any(_same_person(t, m) for m in mine) for t in theirs]
    if all(covered) and all(back):
        return 1.0
    if all(covered):
        return 0.9
    return 0.0

def title_score(theme_title, apple_title):
    a, b = normalise_title(theme_title), normalise_title(apple_title)
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    ratio = SequenceMatcher(None, a, b).ratio()
    return round(ratio, 3) if ratio >= APPLE_TITLE_MIN_RATIO else 0.0

def _is_variant(theme_title, apple_title):
    mine, theirs = (theme_title or '').casefold(), (apple_title or '').casefold()
    return any(word in theirs and word not in mine for word in APPLE_VARIANT_WORDS)

def _https(value, pattern):
    return value if isinstance(value, str) and len(value) <= 2048 and pattern.match(value) else None

def score_itunes_result(theme_title, theme_artist, result):
    """A candidate dict (confidence, track id, Apple URLs) or None. Never guesses."""
    if not isinstance(result, dict) or result.get('wrapperType') != 'track' or result.get('kind') != 'song':
        return None
    track_id = result.get('trackId')
    if not isinstance(track_id, int) or track_id <= 0 or track_id > 999999999999:
        return None
    apple_title = result.get('trackName') or ''
    if _is_variant(theme_title, apple_title):
        return None
    music_url = _https(result.get('trackViewUrl'), APPLE_MUSIC_RE)
    if not music_url:
        return None
    t = title_score(theme_title, apple_title)
    a = artist_score(theme_artist, result.get('artistName') or '')
    confidence = min(t, a)
    resized = APPLE_SIZE_TAG_RE.search(apple_title) and not APPLE_SIZE_TAG_RE.search(theme_title or '')
    if resized:
        confidence -= 0.02  # same recording, edited: the full version wins a tie
    confidence = round(confidence, 3)
    if confidence < APPLE_MIN_CONFIDENCE:
        return None
    artwork = result.get('artworkUrl100')
    if isinstance(artwork, str):
        artwork = artwork.replace('100x100bb', '600x600bb')
    return {'apple_track_id': track_id, 'confidence': confidence,
            'apple_artwork_url': _https(artwork, APPLE_ARTWORK_RE),
            'apple_preview_url': _https(result.get('previewUrl'), APPLE_PREVIEW_RE),
            'apple_music_url': music_url}

def best_itunes_match(theme_title, theme_artist, results):
    candidates = [c for c in (score_itunes_result(theme_title, theme_artist, r) for r in results or []) if c]
    if not candidates:
        return None
    return sorted(candidates, key=lambda c: (-c['confidence'], c['apple_track_id']))[0]

def bounded_get_json(url, max_bytes, allowed_hosts, user_agent=APPLE_USER_AGENT):
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, fp, code, message, headers, target):
            raise ValueError('provider redirects are not followed')
    check_url(url, allowed_hosts)
    request = urllib.request.Request(url, method='GET', headers={'Accept': 'application/json', 'User-Agent': user_agent})
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=20) as response:
        body = response.read(max_bytes + 1)
    if len(body) > max_bytes:
        raise ValueError('provider response exceeds byte limit')
    return json.loads(body)

def itunes_search_url(term, country):
    query = urllib.parse.urlencode({'term': term, 'entity': 'song', 'limit': 10, 'country': country, 'media': 'music'})
    return f'{ITUNES_SEARCH}?{query}'

def fetch_itunes(term, country, getter=bounded_get_json, pacer=None, pause=time.sleep):
    """One iTunes Search request. 403/429 wait Retry-After (<= 65 s) and retry twice; other errors raise."""
    url = itunes_search_url(term, country)
    for attempt in range(3):
        if pacer:
            pacer.wait()
        try:
            document = getter(url, 1024*1024, ITUNES_HOSTS)
        except urllib.error.HTTPError as error:
            if error.code in (403, 429) and attempt < 2:
                retry = error.headers.get('Retry-After') if error.headers else None
                pause(min(65.0, float(retry)) if retry and re.fullmatch(r'\d+(\.\d+)?', retry) else 60.0)
                continue
            raise
        results = document.get('results') if isinstance(document, dict) else None
        if not isinstance(results, list):
            raise ValueError('unrecognized iTunes Search response')
        return results
    raise ValueError('iTunes Search rate limit persisted')

def apple_match_for(title, artist, fetch=fetch_itunes, pacer=None):
    """(match or None, requests made). JP storefront first, then US; no artist = no request, no match."""
    names = artist_names(artist)
    if not (title or '').strip() or not names:
        return None, 0
    raw_first = next((p.strip() for p in ARTIST_SPLIT_RE.split(unicodedata.normalize('NFKC', artist)) if p and p.strip()), '')
    term = f'{title.strip()} {raw_first}'[:200]
    requests = 0
    for country in APPLE_COUNTRIES:
        requests += 1
        match = best_itunes_match(title, artist, fetch(term, country, pacer=pacer))
        if match:
            return match, requests
    return None, requests

def apple_candidates_path(limit, now=None):
    cutoff = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime((now or time.time()) - APPLE_RECHECK_DAYS*86400))
    return ('theme_links?select=id,song_title,artist&match_state=neq.unmatched&song_title=not.is.null'
            f'&or=(apple_checked_at.is.null,apple_checked_at.lt.%22{cutoff}%22)'
            f'&order=apple_checked_at.asc.nullsfirst,id.asc&limit={max(1, min(APPLE_MAX_ROWS_PER_RUN, limit))}')

def run_apple_pass(client, rows, fetch=fetch_itunes, pacer=None, dry_run=False):
    """rows: [{'id': theme uuid, 'song_title': str, 'artist': str|None}]. Returns a summary (no secrets)."""
    summary = {'checked': 0, 'requests': 0, 'matched': 0, 'no_match': 0, 'unverifiable': 0, 'errors': 0,
               'written': {'matched': 0, 'cleared': 0, 'stale': 0}, 'dry_run': dry_run, 'samples': []}
    pending = []
    def flush():
        while pending:
            chunk, pending[:] = pending[:WRITER_BATCH], pending[WRITER_BATCH:]
            if dry_run:
                continue
            result = client.call('upsert_theme_apple_matches_v1', {'p_rows': chunk}) or {}
            for key in ('matched', 'cleared', 'stale'):
                summary['written'][key] += int(result.get(key, 0) or 0)
    for row in rows:
        theme_id, title, artist = row.get('id'), row.get('song_title'), row.get('artist')
        if not isinstance(theme_id, str) or not isinstance(title, str) or not title.strip():
            continue
        summary['checked'] += 1
        try:
            match, requests = apple_match_for(title, artist, fetch=fetch, pacer=pacer)
        except Exception:
            # Transient provider failure: write nothing for this row (it is retried next run).
            summary['errors'] += 1
            continue
        summary['requests'] += requests
        out = {'theme_id': theme_id, 'expected_title': title, 'expected_artist': artist}
        if match:
            summary['matched'] += 1
            out.update(match)
            if len(summary['samples']) < 10:
                summary['samples'].append({'title': title, 'artist': artist, 'apple_track_id': match['apple_track_id'],
                                           'confidence': match['confidence']})
        elif requests == 0:
            summary['unverifiable'] += 1
            out['apple_track_id'] = None
        else:
            summary['no_match'] += 1
            out['apple_track_id'] = None
        pending.append(out)
        if len(pending) >= WRITER_BATCH:
            flush()
    flush()
    return summary

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

    def select(self, path):
        """Service-role REST read (GET /rest/v1/<path>), same redirect/byte guards as call()."""
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, message, headers, target):
                raise ValueError('authenticated REST redirects are forbidden')
        request = urllib.request.Request(self.url+'/rest/v1/'+path, method='GET', headers={
            'Accept':'application/json', 'apikey':self.key, 'Authorization':'Bearer '+self.key})
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=25) as response:
            body = response.read(2*1024*1024+1)
        if len(body) > 2*1024*1024:
            raise ValueError('REST response exceeds byte limit')
        return json.loads(body)

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
    parser.add_argument('--themes', action='store_true', help='batched AnimeThemes pass instead of jobs')
    parser.add_argument('--anilist-ids', default='', help='comma-separated AniList ids for --themes')
    parser.add_argument('--apple', action='store_true', help='iTunes Search pass for theme songs instead of jobs')
    parser.add_argument('--dry-run', action='store_true', help='--apple: query and print matches, write nothing')
    args = parser.parse_args()
    if not args.apply:
        print('DRY CONTRACT: catalogue change -> leased bounded worker -> last-good copy/artwork; '
              '--themes: AnimeThemes GraphQL (<=25 ids/request, <=90/min) -> upsert_theme_links_v1; '
              '--apple: iTunes Search (JP then US, <=20/min, strict title+artist, confidence >= 0.8) '
              '-> upsert_theme_apple_matches_v1. No requests made.')
        return
    client = RPC(args.allow_hosted)
    if args.apple:
        rows = client.select(apple_candidates_path(args.limit))
        summary = run_apple_pass(client, rows if isinstance(rows, list) else [],
                                 pacer=Pacer(APPLE_MIN_INTERVAL), dry_run=args.dry_run)
        print(json.dumps(summary, ensure_ascii=False))
        return
    if args.themes:
        limit = max(1, min(500, args.limit))
        ids = [int(x) for x in args.anilist_ids.split(',') if x.strip().isdigit()][:500]
        if ids:
            path = 'anime?select=id,anilist_id&anilist_id=in.(' + ','.join(str(i) for i in ids) + ')'
        else:
            path = f'anime?select=id,anilist_id&anilist_id=not.is.null&id=gt.{max(0, args.after_id)}&order=id.asc&limit={limit}'
        candidates = client.select(path)
        summary = run_theme_pass(client, candidates, pacer=Pacer(THEMES_MIN_INTERVAL))
        if candidates:
            summary['next_after_id'] = max(row['id'] for row in candidates if isinstance(row.get('id'), int))
        print(json.dumps(summary))
        return
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
            # Themes are written by the --themes pass; omitting p_themes keeps last-good themes.
            params.update(p_copy=plain_copy(job['payload'].get('description')),
                          p_material=artwork(job['payload'].get('image_url'), banner=job['medium']=='anime'))
        except Exception as error:
            # Never include response bodies/URLs/credentials or erase last-good data on failure.
            params = {key:params[key] for key in ('p_medium','p_media_id','p_source_revision','p_lease_token')}
            params['p_error'] = type(error).__name__
        result = client.call('finish_series_enrichment_v1', params)
        print(json.dumps({'medium':job['medium'],'media_id':job['media_id'],'outcome':result['outcome']}))
        time.sleep(1)

if __name__ == '__main__':
    main()
