#!/usr/bin/env python3
"""Offline worker contracts. Uses real palette extraction; no network or credentials."""
import io
import json
import unittest
from unittest.mock import patch
import series_enrichment_worker as worker


class EnrichmentContracts(unittest.TestCase):
    def test_copy_preserves_story_without_inventing_hook(self):
        copy = worker.plain_copy('<p>Two friends cross the sea.</p> They &amp; their crew face storms.')
        self.assertEqual(copy['premise'], 'Two friends cross the sea.')
        self.assertIn('They & their crew', copy['synopsis'])
        self.assertNotIn('hook', copy)
        self.assertIsNone(worker.plain_copy('   '))
        self.assertIsNone(worker.plain_copy('x'*250)['premise'])

    def test_external_namespaces_and_ambiguity(self):
        def row(pk, site, external):
            return {'id':pk,'resources':[{'site':site,'external_id':external}],
                    'animethemes':[{'id':71,'type':'OP','song':{'title':'Opening','artists':[{'name':'Artist'}]}}]}
        def get(url, *args):
            self.assertIn('filter%5Bsite%5D=AniList', url)
            return json.dumps({'anime':[row(1,'MyAnimeList',42),row(2,'AniList',42)]}).encode()
        result = worker.exact_themes({'medium':'anime','anilist_id':42}, getter=get)
        self.assertEqual(result[0]['song_title'],'Opening')
        self.assertNotIn('external_url',result[0])  # Spotify search is not a verified track.
        with self.assertRaisesRegex(ValueError,'ambiguous'):
            worker.exact_themes({'medium':'anime','anilist_id':42}, getter=lambda *args:
                json.dumps({'anime':[row(1,'AniList',42),row(2,'AniList',42)]}).encode())

    def test_provider_paging_is_bounded_and_fails_without_partial_commit(self):
        calls=[]
        def get(url,*args):
            calls.append(url)
            return b'{"anime":[],"links":{"next":"untrusted-url"}}'
        with self.assertRaisesRegex(ValueError,'pagination'):
            worker.exact_themes({'medium':'anime','mal_id':42},getter=get,pause=lambda _:None)
        self.assertEqual(len(calls),4)
        self.assertIn('filter%5Bsite%5D=MyAnimeList',calls[0])
        self.assertTrue(all('api.animethemes.moe' in url for url in calls))

    def test_unknown_and_wrong_media_do_not_make_up_matches(self):
        getter=lambda *args: b'{"anime":[{"id":1,"resources":[]}]}'
        self.assertIsNone(worker.exact_themes({'medium':'anime','anilist_id':1},getter=getter))
        self.assertIsNone(worker.exact_themes({'medium':'manga'},getter=lambda *args:self.fail('manga theme request')))
        self.assertIsNone(worker.exact_themes({'medium':'anime'},getter=lambda *args:self.fail('missing ID request')))

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
        self.assertEqual(calls[1][1]['p_lease_token'],'t')
        self.assertEqual(len(calls),3)


if __name__=='__main__':unittest.main()
