"""Keep setup teleports and previous actions out of reported response latency."""
import unittest
from game.tests.verify_network_resilience import first_time

class PhaseLatency(unittest.TestCase):
    def test_no_movement_is_not_the_next_fixture_teleport(self):
        rows=[{'time_ms':1000,'moved':False},{'time_ms':3999,'moved':False},{'time_ms':4000,'moved':True}]
        self.assertIsNone(first_time(rows,1000,4000,lambda row:row['moved']))

    def test_previous_event_excluded_and_first_response_kept(self):
        rows=[{'time_ms':999,'moved':True},{'time_ms':1000,'moved':False},{'time_ms':1120,'moved':True},{'time_ms':1200,'moved':True}]
        self.assertEqual(first_time(rows,1000,4000,lambda row:row['moved']),120)

if __name__=='__main__':unittest.main()
