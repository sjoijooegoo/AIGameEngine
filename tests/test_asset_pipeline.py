"""Real import and gameplay tests plus deliberate broken asset/scene cases."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from lab import ROOT, Client
from assets import demo
from asset_library import ingest, prepare, inspect_asset, digest, fs_path
from scene_pipeline import plan_scene, validate_plan, build_scene
from asset_jobs import Jobs
from mcp_server import Server


class AssetPipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert demo()['built']
        cls.recipe = json.loads((ROOT/'recipes/bank_room.json').read_text())

    def test_glb_png_measurements_and_cache(self):
        asset = inspect_asset('demo.counter')
        before = digest(ROOT/asset['source'])
        prepared = prepare('demo.counter')
        self.assertTrue(prepared['cache_hit'])
        measured = prepared['asset']['prepared']['measured']
        for actual, expected in zip(measured['size_m'], [2.2, 1.1, .7]):
            self.assertAlmostEqual(actual, expected, places=4)
        surfaces = [s for m in measured['meshes'] for s in m['surfaces']]
        self.assertTrue(all(s['vertices'] == s['normals'] == s['uv'] for s in surfaces))
        self.assertTrue(any('albedo' in s['textures'] for s in surfaces))
        self.assertEqual(before, digest(ROOT/asset['source']))
        self.assertEqual(inspect_asset('demo.wood')['measured']['size_px'], [128,128])

    def test_fbx_import_matches_glb_dimensions(self):
        ingest(ROOT/'tests/asset_fixtures/chair.fbx','qa.chair_fbx',usage='project_owned')
        fbx=prepare('qa.chair_fbx')['asset']['prepared']['measured']
        glb=inspect_asset('demo.chair')['prepared']['measured']
        for actual,expected in zip(fbx['size_m'],glb['size_m']):
            self.assertAlmostEqual(actual,expected,places=4)

    def test_explicit_scale_rotation_and_texture_role(self):
        ingest(ROOT/'tests/asset_fixtures/counter.glb','qa.transformed',usage='project_owned')
        result=prepare('qa.transformed',unit_scale=2,yaw_degrees=90,textures={'albedo':'demo.wood'})['asset']['prepared']
        for actual,expected in zip(result['measured']['size_m'],[1.4,2.2,4.4]):
            self.assertAlmostEqual(actual,expected,places=4)
        self.assertAlmostEqual(result['measured']['bounds_min'][1],0,places=4)
        self.assertEqual(result['options']['unit_scale'],2)
        self.assertIn('albedo',result['options']['texture_hashes'])

    def test_missing_texture_blocks_preparation(self):
        result=ingest(ROOT/'tests/asset_fixtures/missing_texture.gltf','qa.missing')
        self.assertEqual(result['status'],'blocked')
        with self.assertRaisesRegex(ValueError,'Missing dependencies'):
            prepare('qa.missing')

    def test_bad_glb_and_dependency_escape(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'bad.glb';path.write_bytes(b'invalid')
            with self.assertRaises(ValueError):ingest(path,'qa.bad')
            path=Path(folder)/'bad.gltf'
            path.write_text(json.dumps({'asset':{'version':'2.0'},'images':[{'uri':'../outside.png'}]}))
            with self.assertRaisesRegex(ValueError,'escapes'):ingest(path,'qa.bad')

    def test_tabletop_anchor_and_reject_cycles(self):
        plan=plan_scene(self.recipe)
        values={e['id']:e for e in plan['entities']}
        self.assertAlmostEqual(values['screen_left']['position'][1],values['counter_left']['size'][1])
        recipe=copy.deepcopy(self.recipe)
        recipe['entities'][1]['placement']={'on':'screen_left'}
        with self.assertRaisesRegex(ValueError,'cycle'):plan_scene(recipe)
        recipe=copy.deepcopy(self.recipe);recipe['entities'].append(recipe['entities'][0])
        with self.assertRaisesRegex(ValueError,'Duplicate'):plan_scene(recipe)

    def test_reject_float_wall_overlap_support_and_door_sweep(self):
        cases=[('unsupported_floating',5,{'position':[-2.1,.4,0]}),
               ('wall_intersection',5,{'position':[-4,0,0]}),
               ('asset_overlap',5,{'position':[2.1,0,0]}),
               ('door_sweep_blocked',5,{'position':[0,0,-4.2]}),
               ('support_height_mismatch',3,{'placement':{'on':'counter_left','offset':[0,.2,0]}}),
               ('outside_support_surface',3,{'placement':{'on':'counter_left','offset':[1.5,0,0]}})]
        for expected,index,change in cases:
            with self.subTest(expected=expected):
                recipe=copy.deepcopy(self.recipe);recipe['entities'][index].update(change)
                validation=validate_plan(plan_scene(recipe))
                self.assertIn(expected,{i['code'] for i in validation['issues']})

    def test_unreachable_route_and_invalid_build_preserve_scene(self):
        path=ROOT/'game/generated/bank_room/scene.tscn';before=digest(path)
        recipe=copy.deepcopy(self.recipe);recipe['spawn']=[-2.1,0,-1.4]
        result=build_scene(recipe)
        self.assertFalse(result['built'])
        self.assertIn('exit_unreachable_with_door_open',{i['code'] for i in result['validation']['issues']})
        self.assertEqual(before,digest(path))
        self.assertTrue(build_scene(self.recipe)['cache_hit'])

    def test_real_input_door_collision_and_exit(self):
        client=Client.launch(rendered=False,scene='assembly:bank_room')
        try:
            blocked=client.call('act',keys=['W'],frames=200)
            self.assertGreater(blocked['player']['position'][2],-5)
            self.assertFalse(blocked['objective_complete'])
            self.assertFalse(blocked['door_open'])
            opened=client.call('act',keys=['E'],frames=1)
            self.assertTrue(opened['door_open'])
            finished=client.call('act',keys=['W'],frames=45)
            self.assertTrue(finished['objective_complete'])
            self.assertLess(finished['player']['position'][2],-6)
            self.assertTrue(finished['player']['on_floor'])
        finally:client.close()

    def test_jobs_cancel_owned_process_and_queued_work(self):
        jobs=Jobs()
        try:
            def slow(job):return job.run([sys.executable,'-c','import time; time.sleep(30)'],'slow')
            first=jobs.submit('test',slow,{})['job_id']
            second=jobs.submit('queued',slow,{})['job_id']
            time.sleep(.2)
            jobs.cancel(second);jobs.cancel(first)
            until=time.monotonic()+5
            while time.monotonic()<until and any(jobs.status(i)['status'] in ('queued','running') for i in (first,second)):
                time.sleep(.05)
            for i in (first,second):self.assertEqual(jobs.status(i)['status'],'cancelled')
        finally:jobs.close()

    def test_mcp_async_prepare_and_inspect(self):
        server=Server()
        try:
            response=server.tool('asset_prepare',{'asset_id':'demo.chair'})
            self.assertFalse(response['isError'])
            job_id=json.loads(response['content'][0]['text'])['job_id']
            until=time.monotonic()+30
            while time.monotonic()<until:
                status=json.loads(server.tool('asset_job_status',{'job_id':job_id})['content'][0]['text'])
                if status['status'] not in ('queued','running'):break
                time.sleep(.05)
            self.assertEqual(status['status'],'completed',status)
            result=server.tool('asset_inspect',{'asset_id':'demo.chair'})
            self.assertFalse(result['isError'])
            self.assertEqual(json.loads(result['content'][0]['text'])['kind'],'model')
            preview=server.tool('asset_preview',{'asset_id':'demo.wood'})
            job_id=json.loads(preview['content'][0]['text'])['job_id']
            until=time.monotonic()+10
            while time.monotonic()<until:
                response=server.tool('asset_job_status',{'job_id':job_id})
                status=json.loads(response['content'][0]['text'])
                if status['status'] not in ('queued','running'):break
                time.sleep(.05)
            self.assertEqual(status['status'],'completed',status)
            self.assertEqual(response['content'][1]['type'],'image')
            self.assertEqual(response['content'][1]['mimeType'],'image/png')
        finally:server.asset_jobs.close();server.stop()


if __name__=='__main__':unittest.main()
