"""Capacity semantics only; does not launch WSL, Godot or legacy worlds."""
import unittest
from unittest.mock import patch
from game.tests.benchmark_wsl_coop import budget_result, capacity_metrics, read_result


class CapacityReportContract(unittest.TestCase):
    def test_transient_file_sharing_error_retries_only_the_read(self):
        with patch('game.tests.benchmark_wsl_coop.read',side_effect=[PermissionError('sharing'),{'ticks':[1]}]) as read, \
             patch('game.tests.benchmark_wsl_coop.time.sleep'):
            self.assertEqual(read_result('result.json'),{'ticks':[1]})
            self.assertEqual(read.call_count,2)

    def test_permanent_file_sharing_error_has_a_deadline(self):
        with patch('game.tests.benchmark_wsl_coop.read',side_effect=PermissionError('sharing')), \
             patch('game.tests.benchmark_wsl_coop.time.monotonic',side_effect=[0,4]):
            with self.assertRaises(PermissionError):read_result('result.json')

    def test_average_rate_cannot_hide_a_stalled_second(self):
        result={'tick_hz':60, 'script_tick_ms':{'p95':10}, 'monitors':{'physics_ms':{'p95':11}}}
        checks=budget_result(result, {'min_full_second_ticks':40})
        self.assertTrue(checks['average_tick_59_5hz'])
        self.assertFalse(checks['no_second_below_57ticks'])

    def test_physics_budget_is_independent_of_script_budget(self):
        result={'tick_hz':60, 'script_tick_ms':{'p95':10}, 'monitors':{'physics_ms':{'p95':20}}}
        checks=budget_result(result, {'min_full_second_ticks':60})
        self.assertTrue(checks['script_p95_16_67ms'])
        self.assertFalse(checks['physics_monitor_peak_p95_16_67ms'])

    def test_missing_whole_second_is_zero_not_omitted(self):
        raw={'ticks':[{'started_usec':0},{'started_usec':2500000}],'phase_states':[]}
        metrics=capacity_metrics(raw,[])
        self.assertEqual(metrics['full_second_tick_counts'],[1,0])
        self.assertEqual(metrics['min_full_second_ticks'],0)

    def test_partial_last_second_not_reported_as_stall(self):
        raw={'ticks':[{'started_usec':i*20000} for i in range(126)],
             'phase_states':[{'alive':24,'awake_corpses':8}]}
        metrics=capacity_metrics(raw, [])
        self.assertEqual(metrics['full_second_tick_counts'],[50,50])
        self.assertEqual(metrics['min_full_second_ticks'],50)
        self.assertEqual(metrics['tick_interval_ms']['p95'],20)
        self.assertEqual(metrics['alive']['mean'],24)

    def test_cpu_does_not_double_count_linux_guest_time(self):
        rows=[{'monotonic':0,'threads':{},'system_cpu':[0]*10,'mem_available_mb':3000,'swap_mb':0},
              {'monotonic':1,'threads':{},'system_cpu':[50,0,25,100,0,0,0,25,50,0],'mem_available_mb':2900,'swap_mb':0}]
        metrics=capacity_metrics({'ticks':[],'phase_states':[]},rows)
        self.assertEqual(metrics['system_busy_pct']['mean'],50)
        self.assertEqual(metrics['steal_pct']['mean'],12.5)


if __name__=='__main__':unittest.main()
