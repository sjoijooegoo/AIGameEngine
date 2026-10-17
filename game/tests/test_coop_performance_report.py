"""Measurement semantics only; no Godot scene or legacy sandbox is launched."""
import copy,unittest
from game.tests.benchmark_coop_combat import summary

class PerformanceReportContract(unittest.TestCase):
    def raw(self,headless=False):
        frame={'frame_ms':20,'physics_ms':3,'process_ms':5,'draw_calls':100,'primitives':1000,'video_memory_mb':10,'static_memory_mb':20,'viewport_gpu_ms':{'world':0},'viewport_render_cpu_ms':{'world':2}}
        return {'frames':[copy.deepcopy(frame) for _ in range(10)],'ticks':[{'elapsed_ms':3,'scopes_ms':{'pose':1},'counts':{'active':32}} for _ in range(10)],
            'wall_seconds':.2,'environment':{'headless':headless},'telemetry':[{'time':0,'world_tick':1,'world_age_ms':0,'prediction_error':0},{'time':.05,'world_tick':1,'world_age_ms':50,'prediction_error':0},{'time':.1,'world_tick':7,'world_age_ms':0,'prediction_error':0}],
            'network':{'sent_bytes':1024,'received_bytes':512},'dropped_samples':0,'start':{},'finish':{},'phase_states':[]}
    def test_headless_loop_is_not_rendered_fps(self):
        result=summary(self.raw(True),[])
        self.assertIsNone(result['fps_average']);self.assertIsNone(result['frame_ms']);self.assertEqual(result['gpu_ms'],{})
        self.assertEqual(result['tick_hz'],50)
    def test_zero_gpu_is_unavailable_not_free_rendering(self):
        result=summary(self.raw(),[])
        self.assertIsNone(result['gpu_ms']['world']);self.assertEqual(result['fps_average'],50)
        self.assertEqual(result['fps_1pct_low'],50)
    def test_delivery_rate_counts_new_worlds_not_render_frames(self):
        result=summary(self.raw(),[])
        self.assertEqual(result['world_delivery_hz'],10)
        self.assertEqual(result['network_kib_s']['sent_bytes'],5)
        self.assertIsNone(result['os_cpu_one_core_pct'])
    def test_cpu_percent_uses_one_core_convention(self):
        rows=[{'time':0,'cpu_seconds':2,'rss_mb':100,'private_mb':200},{'time':1,'cpu_seconds':3.5,'rss_mb':101,'private_mb':201}]
        result=summary(self.raw(),rows)
        self.assertEqual(result['os_cpu_one_core_pct']['mean'],150)

if __name__=='__main__':unittest.main()
