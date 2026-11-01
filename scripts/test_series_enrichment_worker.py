#!/usr/bin/env python3
"""Offline worker contracts. Uses real palette extraction when PIL is installed; no network or credentials.

The AnimeThemes fixture is a trimmed live GraphQL response (findAnimeByExternalSite, AniList 16498,
read 2026-11-01).
"""
import importlib.util
import io
import json
import unittest
import urllib.error
from unittest.mock import patch
import series_enrichment_worker as worker

HAS_PIL = importlib.util.find_spec('PIL') is not None

AOT = {"id": 2611, "slug": "shingeki_no_kyojin", "resources": {"edges": [
    {"node": {"site": "MAL", "externalId": 16498}}, {"node": {"site": "ANILIST", "externalId": 16498}}]},
  "animethemes": [
    {"id": 5279, "type": "OP", "sequence": 1, "song": {"title": {"romaji": "Guren no Yumiya", "native": None},
      "performances": [{"as": None, "alias": None, "artist": {"__typename": "Artist", "name": {"main": "Linked Horizon"}}}]},
     "animethemeentries": [{"id": 6043, "episodes": "1-13", "nsfw": False, "spoiler": False, "version": 1}]},
    {"id": 5281, "type": "ED", "sequence": 1, "song": {"title": {"romaji": "Utsukushiki Zankoku na Sekai", "native": None},
      "performances": [{"as": None, "alias": None, "artist": {"__typename": "Artist", "name": {"main": "Youko Hikasa"}}}]},
     "animethemeentries": [{"id": 6045, "episodes": "1-13", "nsfw": False, "spoiler": False, "version": 1}]}]}

ONE_PIECE_OP1 = {"id": 2144, "slug": "one_piece", "resources": {"edges": [{"node": {"site": "ANILIST", "externalId": 21}}]},
  "animethemes": [{"id": 950, "type": "OP", "sequence": 1, "song": {"title": {"romaji": "We Are!", "native": None},
      "performances": [{"as": None, "alias": None, "artist": {"__typename": "Artist", "name": {"main": "Hiroshi Kitadani"}}}]},
    "animethemeentries": [{"id": 1058, "episodes": "1-47", "nsfw": False, "spoiler": False, "version": 1},
                          {"id": 12731, "episodes": "1000", "nsfw": False, "spoiler": True, "version": 2}]},
    {"id": 999, "type": "XX", "sequence": 1, "song": {"title": {"romaji": "Unknown kind"}}, "animethemeentries": []}]}


class EnrichmentContracts(unittest.TestCase):
    def test_copy_preserves_story_without_inventing_hook(self):
        copy = worker.plain_copy('<p>Two friends cross the sea.</p> They &amp; their crew face storms.')
        self.assertEqual(copy['premise'], 'Two friends cross the sea.')
        self.assertIn('They & their crew', copy['synopsis'])
        self.assertNotIn('hook', copy)
        self.assertIsNone(worker.plain_copy('   '))
        self.assertIsNone(worker.plain_copy('x'*250)['premise'])

    @unittest.skipUnless(HAS_PIL, 'PIL is not installed; palette extraction not exercised')
    def test_artwork_uses_real_palette_and_url_plus_content_identity(self):
        from PIL import Image
        body=io.BytesIO(); Image.new('RGB',(325,100),(20,160,100)).save(body,format='PNG')
        getter=lambda *args:body.getvalue()
        one=worker.artwork('https://s4.anilist.co/a.png',getter=getter,banner=True)
        two=worker.artwork('https://s4.anilist.co/b.png',getter=getter,banner=True)
        self.assertEqual(len(one['digest']),64)
        self.assertNotEqual(one['digest'],two['digest'])
        self.assertEqual(one['base'],two['base'])
        self.assertGreaterEqual(one['contrast'],7)
        self.assertEqual(one['method'],'art-hue-v1')

    def test_artwork_destination_validation(self):
        for url in ['http://s4.anilist.co/x','https://s4.anilist.co.attacker.test/x',
                    'https://secret@s4.anilist.co/x','https://s4.anilist.co:8443/x','https://127.0.0.1/x']:
            with self.assertRaises(ValueError):worker.check_url(url,worker.ART_HOSTS)

    def test_default_invocation_does_not_access_services(self):
        with patch('sys.argv',['worker']),patch.object(worker,'RPC',side_effect=AssertionError('RPC constructed')):
            worker.main()

    def test_claims_only_next_job_and_retains_failure_identity(self):
        calls=[]
        class Client:
            def call(self,name,payload):
                calls.append((name,payload))
                if name.startswith('claim'):
                    return [{'medium':'anime','media_id':1,'source_revision':'r','lease_token':'t',
                             'payload':{'description':'Source story.','image_url':'x'}}] if len(calls)==1 else []
                return {'outcome':'retry'}
        with patch('sys.argv',['worker','--apply','--limit','20']),patch.object(worker,'RPC',return_value=Client()),\
             patch.object(worker,'artwork',side_effect=TimeoutError('do not print secrets')),patch.object(worker.time,'sleep'):
            worker.main()
        self.assertEqual(calls[0][1],{'p_limit':1})
        self.assertEqual(calls[1][1]['p_error'],'TimeoutError')
        self.assertNotIn('p_material',calls[1][1])
        self.assertNotIn('p_themes',calls[1][1])
        self.assertEqual(calls[1][1]['p_lease_token'],'t')
        self.assertEqual(len(calls),3)


    def test_job_success_omits_themes_so_last_good_themes_are_kept(self):
        calls=[]
        class Client:
            def call(self,name,payload):
                calls.append((name,payload))
                if name.startswith('claim'):
                    return [{'medium':'anime','media_id':1,'source_revision':'r','lease_token':'t',
                             'payload':{'description':'Source story.','image_url':None}}] if len(calls)==1 else []
                return {'outcome':'done'}
        with patch('sys.argv',['worker','--apply']),patch.object(worker,'RPC',return_value=Client()),\
             patch.object(worker.time,'sleep'):
            worker.main()
        self.assertEqual(calls[1][0],'finish_series_enrichment_v1')
        self.assertNotIn('p_themes',calls[1][1])
        self.assertEqual(calls[1][1]['p_copy']['premise'],'Source story.')


class ThemePassContracts(unittest.TestCase):
    def test_batched_request_shape_and_host(self):
        seen=[]
        def poster(url,payload,max_bytes,hosts):
            seen.append((url,payload,hosts))
            return {'data':{'findAnimeByExternalSite':[AOT]}}
        rows=worker.fetch_theme_batch([16498,21],poster=poster)
        self.assertEqual(rows[0]['slug'],'shingeki_no_kyojin')
        url,payload,hosts=seen[0]
        self.assertEqual(url,'https://graphql.animethemes.moe/')
        self.assertEqual(hosts,{'graphql.animethemes.moe'})
        self.assertEqual(payload['variables'],{'ids':[16498,21]})
        self.assertIn('findAnimeByExternalSite(site: ANILIST, id: $ids)',payload['query'])
        with self.assertRaisesRegex(ValueError,'1..25'):
            worker.fetch_theme_batch(list(range(26)),poster=poster)

    def test_graphql_errors_raise_and_429_waits_retry_after(self):
        with self.assertRaisesRegex(ValueError,'GraphQL error'):
            worker.fetch_theme_batch([1],poster=lambda *a:{'errors':[{'message':'x'}],'data':None})
        attempts=[]; pauses=[]
        def poster(*args):
            attempts.append(1)
            if len(attempts)==1:
                raise urllib.error.HTTPError('https://graphql.animethemes.moe/',429,'Too Many',{'Retry-After':'7'},None)
            return {'data':{'findAnimeByExternalSite':[]}}
        self.assertEqual(worker.fetch_theme_batch([1],poster=poster,pause=pauses.append),[])
        self.assertEqual(pauses,[7.0])

    def test_pacer_keeps_90_per_minute(self):
        now=[0.0]; pauses=[]
        def pause(seconds):
            pauses.append(seconds); now[0]+=seconds
        pacer=worker.Pacer(worker.THEMES_MIN_INTERVAL,clock=lambda:now[0],pause=pause)
        for _ in range(3): pacer.wait()
        self.assertEqual(len(pauses),2)
        self.assertAlmostEqual(pauses[0],60/90,places=6)

    def test_exact_anilist_match_and_ambiguity(self):
        other={**AOT,'id':1,'slug':'dup'}
        matched,ambiguous=worker.match_by_anilist_id([AOT,ONE_PIECE_OP1],[16498,21,5])
        self.assertEqual(set(matched),{16498,21})
        self.assertEqual(ambiguous,[])
        # MAL id 16498 alone must not match AniList 16498.
        mal_only={**AOT,'resources':{'edges':[{'node':{'site':'MAL','externalId':16498}}]}}
        self.assertEqual(worker.match_by_anilist_id([mal_only],[16498]),({},[]))
        matched,ambiguous=worker.match_by_anilist_id([AOT,other],[16498])
        self.assertEqual((matched,ambiguous),({},[16498]))

    def test_rows_carry_entry_version_episodes_flags_and_credit(self):
        rows=worker.theme_rows(7,ONE_PIECE_OP1)
        self.assertEqual(len(rows),2)  # unknown kind skipped
        self.assertEqual(rows[0],{'anime_id':7,'source_id':'950','kind':'OP','sequence':1,'version':1,
            'title':'We Are!','artist':'Hiroshi Kitadani','episodes':'1-47','is_spoiler':False,'is_nsfw':False,
            'source':'animethemes','source_url':'https://animethemes.moe/anime/one_piece'})
        self.assertEqual(rows[1]['source_id'],'950.v2')
        self.assertEqual(rows[1]['episodes'],'1000')
        self.assertTrue(rows[1]['is_spoiler'])
        for row in rows:
            self.assertRegex(row['source_id'],r'^[A-Za-z0-9._-]{1,64}$')

    def test_theme_pass_writes_only_matched_titles_with_themes(self):
        calls=[]
        class Client:
            def call(self,name,payload):
                calls.append((name,payload))
                return {'inserted':len(payload['p_rows']),'updated':0,'unchanged':0}
        no_themes={'id':3,'slug':'empty','resources':{'edges':[{'node':{'site':'ANILIST','externalId':30}}]},'animethemes':[]}
        fetched=[]
        def fetch(ids,pacer=None):
            fetched.append(list(ids))
            return [AOT,no_themes]
        candidates=[{'id':101,'anilist_id':16498},{'id':102,'anilist_id':30},{'id':103,'anilist_id':40}]
        summary=worker.run_theme_pass(Client(),candidates,fetch=fetch)
        self.assertEqual(fetched,[[16498,30,40]])
        self.assertEqual(summary['matched'],1)
        self.assertEqual(summary['not_found'],1)
        self.assertEqual(summary['rows'],2)
        self.assertEqual(summary['inserted'],2)
        self.assertEqual([c[0] for c in calls],['upsert_theme_links_v1'])
        self.assertEqual({r['anime_id'] for r in calls[0][1]['p_rows']},{101})

    def test_theme_pass_batches_25_ids_per_request(self):
        sizes=[]
        def fetch(ids,pacer=None):
            sizes.append(len(ids)); return []
        class Client:
            def call(self,*a): raise AssertionError('nothing to write')
        summary=worker.run_theme_pass(Client(),[{'id':i,'anilist_id':1000+i} for i in range(60)],fetch=fetch)
        self.assertEqual(sizes,[25,25,10])
        self.assertEqual(summary['not_found'],60)

    def test_themes_mode_requires_apply_and_reads_candidates(self):
        with patch('sys.argv',['worker','--themes']),patch.object(worker,'RPC',side_effect=AssertionError('RPC constructed')):
            worker.main()
        paths=[]
        class Client:
            def select(self,path):
                paths.append(path); return []
            def call(self,*a): raise AssertionError('no write without candidates')
        with patch('sys.argv',['worker','--themes','--apply','--allow-hosted','--anilist-ids','16498,21']),\
             patch.object(worker,'RPC',return_value=Client()):
            worker.main()
        self.assertEqual(paths,['anime?select=id,anilist_id&anilist_id=in.(16498,21)'])


if __name__=='__main__':unittest.main()
