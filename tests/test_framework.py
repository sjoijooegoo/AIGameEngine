import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from qa import assert_state, check_ui
from visual import compare
from lab import ROOT, validate_session


class FrameworkTests(unittest.TestCase):
    def test_assertions_reject_broken_gameplay(self):
        with self.assertRaises(AssertionError):
            assert_state({"door_open": True}, {"path": "door_open", "value": False})
        with self.assertRaises(ValueError):
            assert_state({"hp": 100}, {"path": "hp", "value": 100, "op": "typo"})

    def test_layout_rejects_clipped_controls(self):
        with self.assertRaises(AssertionError):
            check_ui({"controls": {"save": {"visible": True, "inside_viewport": False, "rect": [100, 100, 10, 10]}}})

    def test_visual_diff_detects_regression_and_masks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            baseline, current, diff = (root / n for n in ("base.png", "current.png", "diff.png"))
            image = Image.new("RGB", (100, 100), "white")
            image.save(baseline)
            image.save(current)
            policy = {"pixel_threshold": 16, "max_changed_ratio": 0.005, "max_mean_absolute_error": 1.5}
            self.assertEqual(compare(current, baseline, diff, policy, "scene")["status"], "pass")
            ImageDraw.Draw(image).rectangle((0, 0, 19, 19), fill="red")
            image.save(current)
            self.assertEqual(compare(current, baseline, diff, policy, "scene")["status"], "fail")
            policy["masks"] = {"scene": [[0, 0, 20, 20]]}
            self.assertEqual(compare(current, baseline, diff, policy, "scene")["status"], "pass")
            self.assertEqual(compare(current, root / "missing.png", diff, policy, "scene")["status"], "needs_review")

    def test_session_scope(self):
        with self.assertRaises(ValueError):
            validate_session(ROOT)

    def test_mcp_handshake_and_gameplay(self):
        # Real subprocess, real Godot session; no fake engine or mocked test success.
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "game_start", "arguments": {"headless": True}}},
            {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "game_command", "arguments": {"command": "act", "args": {"keys": ["W"], "frames": 30}}}},
            {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "game_stop", "arguments": {}}},
        ]
        process = subprocess.run([sys.executable, str(ROOT / "tools/mcp_server.py")], input="\n".join(json.dumps(m) for m in messages) + "\n", text=True, encoding="utf-8", capture_output=True, timeout=60)
        self.assertEqual(process.returncode, 0, process.stderr)
        results = [json.loads(line) for line in process.stdout.splitlines()]
        self.assertEqual(len(results), 5)
        self.assertEqual(results[0]["result"]["protocolVersion"], "2025-06-18")
        self.assertEqual(len(results[1]["result"]["tools"]), 3)
        self.assertFalse(results[3]["result"]["isError"])
        state = json.loads(results[3]["result"]["content"][0]["text"])
        self.assertAlmostEqual(state["player"]["position"][2], 3.5, places=2)


if __name__ == "__main__":
    unittest.main()
