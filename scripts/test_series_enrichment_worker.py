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
import urllib.parse
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

    def test_theme_pass_skips_title_over_row_bound_and_keeps_going(self):
        many={'id':9,'slug':'detective_conan','resources':{'edges':[{'node':{'site':'ANILIST','externalId':235}}]},
              'animethemes':[{'id':10000+i,'type':'OP','sequence':1+(i%99),'song':{'title':{'romaji':f'Song {i}'}},
                              'animethemeentries':[{'id':20000+i,'episodes':'1','nsfw':False,'spoiler':False,'version':1}]}
                             for i in range(worker.MAX_THEME_ROWS_PER_ANIME+1)]}
        calls=[]
        class Client:
            def call(self,name,payload):
                calls.append(payload); return {'inserted':len(payload['p_rows']),'updated':0,'unchanged':0}
        summary=worker.run_theme_pass(Client(),[{'id':1,'anilist_id':235},{'id':2,'anilist_id':16498}],
                                      fetch=lambda ids,pacer=None:[many,AOT])
        self.assertEqual(summary['oversized'],1)
        self.assertEqual(summary['matched'],1)
        self.assertEqual({r['anime_id'] for r in calls[0]['p_rows']},{2})

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


def itunes(track_id, name, artist, preview=True, view=None, art=True, kind='song'):
    """An iTunes Search result in the documented shape (fields trimmed)."""
    row = {'wrapperType': 'track', 'kind': kind, 'trackId': track_id, 'trackName': name, 'artistName': artist,
           'trackViewUrl': view or f'https://music.apple.com/us/album/x/{track_id + 1}?i={track_id}&uo=4'}
    if preview:
        row['previewUrl'] = f'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview/{track_id}.m4a'
    if art:
        row['artworkUrl100'] = f'https://is1-ssl.mzstatic.com/image/thumb/Music/{track_id}/100x100bb.jpg'
    return row


class ApplePassContracts(unittest.TestCase):
    def test_normalisation_is_romanisation_aware(self):
        self.assertEqual(worker.normalise_title('Kimi wo Nosete'), worker.normalise_title('Kimi o Nosete'))
        self.assertEqual(worker.normalise_title('Shinzou wo Sasageyo!'), worker.normalise_title('Shinzō o Sasageyo'))
        self.assertEqual(worker.normalise_title('Gurenge (TV Size)'), worker.normalise_title('Gurenge'))
        self.assertEqual(worker.normalise_title('ＧＵＲＥＮＧＥ'), worker.normalise_title('gurenge'))
        self.assertEqual(worker.artist_score('Youko Hikasa', 'Yoko Hikasa'), 1.0)
        self.assertEqual(worker.artist_score('Youko Hikasa', 'Hikasa Yoko'), 1.0, 'family-name order')
        self.assertEqual(worker.artist_score('FictionJunction feat. LiSA', 'FictionJunction & LiSA'), 1.0)
        self.assertEqual(worker.artist_score('Aimer', 'Aimer & chelmico'), 0.9, 'Apple credits a guest')
        self.assertEqual(worker.artist_score('Aimer & chelmico', 'Aimer'), 0.0, 'a credited artist is missing')
        self.assertEqual(worker.artist_score('LiSA', 'Lisa Ono'), 0.0)
        self.assertEqual(worker.artist_names('X JAPAN'), ['x japan'])
        self.assertEqual(worker.artist_names('Kenshi Yonezu x Daoko'), ['kenshi yonezu', 'daoko'])
        self.assertEqual(worker.artist_names('Ling tosite sigure'), ['ling tosite sigure'])

    def test_exact_match_is_confident_and_carries_apple_urls_only(self):
        match = worker.best_itunes_match('Gurenge', 'LiSA', [itunes(1488408568, 'Gurenge', 'LiSA')])
        self.assertEqual(match['apple_track_id'], 1488408568)
        self.assertEqual(match['confidence'], 1.0)
        self.assertTrue(match['apple_artwork_url'].endswith('/600x600bb.jpg'))
        self.assertTrue(match['apple_preview_url'].startswith('https://audio-ssl.itunes.apple.com/'))
        self.assertTrue(match['apple_music_url'].startswith('https://music.apple.com/'))

    def test_same_title_by_another_artist_is_not_a_match(self):
        self.assertIsNone(worker.best_itunes_match('Gurenge', 'LiSA', [itunes(1, 'Gurenge', 'Some Cover Singer')]))

    def test_karaoke_instrumental_off_vocal_and_covers_are_rejected(self):
        for name in ('Gurenge (Instrumental)', 'Gurenge (Karaoke)', 'Gurenge -Off Vocal-', 'Gurenge (Piano Ver.)',
                     'Gurenge (Cover)', 'Gurenge (Remix)'):
            self.assertIsNone(worker.best_itunes_match('Gurenge', 'LiSA', [itunes(2, name, 'LiSA')]), name)
        # ...unless the theme itself is that variant.
        self.assertIsNotNone(worker.best_itunes_match('Theme (Acoustic)', 'Band', [itunes(3, 'Theme (Acoustic)', 'Band')]))

    def test_full_version_wins_over_tv_size_and_tv_size_alone_still_matches(self):
        both = [itunes(10, 'Gurenge (TV Size)', 'LiSA'), itunes(11, 'Gurenge', 'LiSA')]
        self.assertEqual(worker.best_itunes_match('Gurenge', 'LiSA', both)['apple_track_id'], 11)
        only_tv = worker.best_itunes_match('Gurenge', 'LiSA', [itunes(10, 'Gurenge (TV Size)', 'LiSA')])
        self.assertEqual((only_tv['apple_track_id'], only_tv['confidence']), (10, 0.98))

    def test_native_script_title_does_not_match_a_romaji_theme(self):
        self.assertIsNone(worker.best_itunes_match('Gurenge', 'LiSA', [itunes(4, '紅蓮華', 'LiSA')]))

    def test_near_titles_below_threshold_and_bad_urls(self):
        self.assertIsNone(worker.best_itunes_match('Unravel', 'TK from Ling tosite sigure', [itunes(5, 'Unlimited', 'TK from Ling tosite sigure')]))
        self.assertIsNone(worker.best_itunes_match('Gurenge', 'LiSA', [itunes(6, 'Gurenge', 'LiSA', view='https://evil.invalid/x')]),
                          'no Apple Music link, no match')
        self.assertIsNone(worker.best_itunes_match('Gurenge', 'LiSA', [itunes(6, 'Gurenge', 'LiSA', kind='music-video')]))
        odd = itunes(7, 'Gurenge', 'LiSA')
        odd['previewUrl'] = 'http://audio-ssl.itunes.apple.com/a.m4a'
        odd['artworkUrl100'] = 'https://cdn.invalid/a.jpg'
        match = worker.best_itunes_match('Gurenge', 'LiSA', [odd])
        self.assertIsNone(match['apple_preview_url'])
        self.assertIsNone(match['apple_artwork_url'])

    def test_request_shape_host_user_agent_and_storefront_order(self):
        seen = []
        def getter(url, max_bytes, hosts):
            seen.append(url)
            self.assertEqual(hosts, {'itunes.apple.com'})
            return {'resultCount': 0, 'results': []}
        def fetch(term, country, pacer=None):
            return worker.fetch_itunes(term, country, getter=getter, pacer=pacer)
        match, requests = worker.apple_match_for('Gurenge', 'LiSA', fetch=fetch)
        self.assertIsNone(match)
        self.assertEqual(requests, 2)
        self.assertEqual([urllib.parse.parse_qs(urllib.parse.urlsplit(u).query)['country'][0] for u in seen], ['JP', 'US'])
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(seen[0]).query)
        self.assertEqual((query['term'][0], query['entity'][0], query['limit'][0]), ('Gurenge LiSA', 'song', '10'))
        self.assertTrue(seen[0].startswith('https://itunes.apple.com/search?'))
        self.assertTrue(worker.APPLE_USER_AGENT.startswith('Kuro-Intake'))

    def test_us_storefront_is_tried_when_jp_has_no_confident_match(self):
        answers = {'JP': [itunes(20, '日笠陽子の歌', '日笠陽子')], 'US': [itunes(21, 'Utsukushiki Zankoku na Sekai', 'Yoko Hikasa')]}
        match, requests = worker.apple_match_for('Utsukushiki Zankoku na Sekai', 'Youko Hikasa',
                                                 fetch=lambda term, country, pacer=None: answers[country])
        self.assertEqual((match['apple_track_id'], requests), (21, 2))
        jp_hit, jp_requests = worker.apple_match_for('Gurenge', 'LiSA',
                                                     fetch=lambda term, country, pacer=None: [itunes(22, 'Gurenge', 'LiSA')])
        self.assertEqual((jp_hit['apple_track_id'], jp_requests), (22, 1), 'a JP hit stops the search')

    def test_no_artist_makes_no_request_and_is_recorded_unverifiable(self):
        def fetch(*a, **k):
            raise AssertionError('no request without an artist')
        self.assertEqual(worker.apple_match_for('Kamado Tanjiro no Uta', None, fetch=fetch), (None, 0))

    def test_rate_limit_waits_retry_after_and_pacer_keeps_20_per_minute(self):
        waits, calls = [], []
        def getter(url, max_bytes, hosts):
            calls.append(url)
            if len(calls) == 1:
                raise urllib.error.HTTPError(url, 403, 'Forbidden', {'Retry-After': '12'}, None)
            return {'results': []}
        self.assertEqual(worker.fetch_itunes('x', 'JP', getter=getter, pause=waits.append), [])
        self.assertEqual(waits, [12.0])
        with self.assertRaises(ValueError):
            worker.fetch_itunes('x', 'JP', getter=lambda *a: {'unexpected': True})
        now = [0.0]; sleeps = []
        pacer = worker.Pacer(worker.APPLE_MIN_INTERVAL, clock=lambda: now[0], pause=lambda d: (sleeps.append(d), now.__setitem__(0, now[0] + d)))
        for _ in range(21):
            pacer.wait()
        self.assertGreaterEqual(now[0], 60.0, '21 requests take at least a minute')
        self.assertEqual(worker.APPLE_MIN_INTERVAL, 3.0)

    def test_pass_writes_matches_and_no_matches_and_skips_failures(self):
        writes = []
        class Client:
            def call(self, name, payload):
                writes.append((name, payload)); return {'matched': 1, 'cleared': 2, 'stale': 0}
        answers = {'Gurenge': [itunes(30, 'Gurenge', 'LiSA')], 'Nothing': [], 'Boom': None}
        def fetch(term, country, pacer=None):
            key = term.split(' ')[0]
            if answers[key] is None:
                raise urllib.error.URLError('offline')
            return answers[key]
        rows = [{'id': 'a', 'song_title': 'Gurenge', 'artist': 'LiSA'}, {'id': 'b', 'song_title': 'Nothing', 'artist': 'X'},
                {'id': 'c', 'song_title': 'Boom', 'artist': 'Y'}, {'id': 'd', 'song_title': 'Lonely', 'artist': None},
                {'id': None, 'song_title': 'bad row'}]
        summary = worker.run_apple_pass(Client(), rows, fetch=fetch)
        self.assertEqual((summary['checked'], summary['matched'], summary['no_match'], summary['unverifiable'], summary['errors']),
                         (4, 1, 1, 1, 1))
        self.assertEqual(len(writes), 1)
        name, payload = writes[0]
        self.assertEqual(name, 'upsert_theme_apple_matches_v1')
        by_id = {r['theme_id']: r for r in payload['p_rows']}
        self.assertEqual(sorted(by_id), ['a', 'b', 'd'], 'the failed row is not written')
        self.assertEqual(by_id['a']['apple_track_id'], 30)
        self.assertEqual((by_id['a']['expected_title'], by_id['a']['expected_artist']), ('Gurenge', 'LiSA'))
        self.assertIsNone(by_id['b']['apple_track_id'])
        self.assertIsNone(by_id['d']['apple_track_id'])
        self.assertEqual(summary['written'], {'matched': 1, 'cleared': 2, 'stale': 0})

    def test_live_takes_sequels_and_suffixes_are_not_matches(self):
        # Review 2026-11-03: these passed the old 0.9 fuzzy ratio.
        for theme, apple in (('Kimi no Shiranai Monogatari', 'Kimi no Shiranai Monogatari (Live)'),
                             ('Kimi no Shiranai Monogatari', 'Kimi no Shiranai Monogatari - Live at Budokan'),
                             ('Gurenge', 'Gurenge (ライブ)'),
                             ('COLORS', 'COLORS 2'), ('Brave Heart', 'Brave Heart 2'),
                             ('Unravel', 'Unravel (2023 Remaster)'), ('Again', 'Again (Ver. 2)')):
            self.assertIsNone(worker.best_itunes_match(theme, 'Artist', [itunes(40, apple, 'Artist')]), apple)
        # A live theme still matches its own live recording; "Alive" is not a live take.
        self.assertIsNotNone(worker.best_itunes_match('Song (Live)', 'Artist', [itunes(41, 'Song (Live)', 'Artist')]))
        self.assertIsNotNone(worker.best_itunes_match('Alive', 'Artist', [itunes(42, 'Alive', 'Artist')]))

    def test_long_vowel_folds_only_for_romanised_japanese(self):
        self.assertEqual(worker.title_score('Shout', 'Shot'), 0.0)
        self.assertEqual(worker.title_score('Good', 'God'), 0.0)
        self.assertIsNone(worker.best_itunes_match('Shout', 'Artist', [itunes(43, 'Shot', 'Artist')]))
        self.assertEqual(worker.title_score('Shinzou wo Sasageyo!', 'Shinzō o Sasageyo'), 1.0)
        self.assertEqual(worker.title_score('Kimi wo Nosete', 'Kimi o Nosete'), 1.0)
        self.assertTrue(worker.is_romaji('Gurenge'))
        self.assertTrue(worker.is_romaji('Gakkou Gurashi'))
        self.assertFalse(worker.is_romaji('Shout'))
        self.assertFalse(worker.is_romaji('紅蓮華'))

    def test_persistent_rate_limit_stops_the_pass(self):
        writes, fetched = [], []
        class Client:
            def call(self, name, payload):
                writes.append(payload); return {'matched': 1, 'cleared': 0, 'stale': 0}
        def fetch(term, country, pacer=None):
            fetched.append(term)
            if term.startswith('Gurenge'):
                return [itunes(50, 'Gurenge', 'LiSA')]
            raise worker.AppleRateLimited('iTunes Search rate limit persisted')
        rows = [{'id': 'a', 'song_title': 'Gurenge', 'artist': 'LiSA'},
                {'id': 'b', 'song_title': 'Two', 'artist': 'X'}, {'id': 'c', 'song_title': 'Three', 'artist': 'Y'}]
        summary = worker.run_apple_pass(Client(), rows, fetch=fetch)
        self.assertTrue(summary['rate_limited'])
        self.assertEqual(len(fetched), 2, 'the pass kept requesting after a persistent refusal')
        self.assertEqual([r['theme_id'] for r in writes[0]['p_rows']], ['a'], 'the matched row is still written')
        waits = []
        def refusing(url, max_bytes, hosts):
            raise urllib.error.HTTPError(url, 429, 'Too Many', {'Retry-After': '1'}, None)
        with self.assertRaises(worker.AppleRateLimited):
            worker.fetch_itunes('x', 'JP', getter=refusing, pause=waits.append)
        self.assertEqual(waits, [1.0, 1.0])

    def test_dry_run_never_writes(self):
        class Client:
            def call(self, *a):
                raise AssertionError('dry run wrote')
        summary = worker.run_apple_pass(Client(), [{'id': 'a', 'song_title': 'Gurenge', 'artist': 'LiSA'}],
                                        fetch=lambda term, country, pacer=None: [itunes(31, 'Gurenge', 'LiSA')], dry_run=True)
        self.assertEqual((summary['matched'], summary['dry_run'], summary['samples'][0]['apple_track_id']), (1, True, 31))

    def test_apple_mode_requires_apply_and_reads_bounded_candidates(self):
        with patch('sys.argv', ['worker', '--apple']), patch.object(worker, 'RPC', side_effect=AssertionError('RPC constructed')):
            worker.main()
        path = worker.apple_candidates_path(5000, now=86400*40)
        self.assertIn('limit=200', path)
        self.assertIn('or=(apple_checked_at.is.null,apple_checked_at.lt.%221970-01-11T00:00:00Z%22)', path, 'value quoted inside the logic tree')
        self.assertTrue(path.startswith('theme_links?select=id,song_title,artist&match_state=neq.unmatched'))


if __name__=='__main__':unittest.main()
