import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from visual import approve, check_image
from lab import ROOT, read_json_retry
from project import validate


class BaselineReviewTests(unittest.TestCase):
    def report_fixture(self, directory, fail_check=False):
        root = Path(directory)
        image = Image.new("RGB", (64, 64), "#183244")
        ImageDraw.Draw(image).rectangle((10, 10, 30, 30), fill="white")
        path = root / "scene.png"
        image.save(path)
        data = {"engine": {"godot": "test", "renderer": "test", "gpu": "test"}, "checks": [{"name": "logic", "status": "fail" if fail_check else "pass"}], "summary": {"failed": 2 if fail_check else 1}, "visuals": [{"name": "scene", "path": str(path), "image": check_image(path), "comparison": {"status": "fail"}}]}
        report = root / "report.json"
        report.write_text(json.dumps(data), encoding="utf-8")
        return report

    def test_expected_visual_change_can_be_reviewed(self):
        with tempfile.TemporaryDirectory() as directory:
            report = self.report_fixture(directory)
            baseline = Path(directory) / "baselines"
            with self.assertRaisesRegex(ValueError, "Visual changes"):
                approve(report, "reviewer", baseline_dir=baseline)
            approve(report, "reviewer", reason="Requested new lighting; inspected actual and difference", accept_visual_changes=True, baseline_dir=baseline)
            manifest = json.loads((baseline / "manifest.json").read_text())
            self.assertIn("scene", manifest["images"])
            self.assertEqual(manifest["reviews"][0]["reviewer"], "reviewer")

    def test_visual_change_flag_cannot_hide_logic_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            report = self.report_fixture(directory, fail_check=True)
            with self.assertRaisesRegex(ValueError, "executable"):
                approve(report, "reviewer", reason="new lighting", accept_visual_changes=True, baseline_dir=Path(directory) / "base")

    def test_modified_capture_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            report = self.report_fixture(directory)
            image = Image.open(Path(directory) / "scene.png").copy()
            image.putpixel((0, 0), (123, 45, 67))
            image.save(Path(directory) / "scene.png")
            with self.assertRaisesRegex(ValueError, "modified"):
                approve(report, "reviewer", reason="reviewed", accept_visual_changes=True, baseline_dir=Path(directory) / "base")

    def test_partial_update_preserves_other_baselines(self):
        with tempfile.TemporaryDirectory() as directory:
            report = self.report_fixture(directory)
            baseline = Path(directory) / "base"
            baseline.mkdir()
            (baseline / "manifest.json").write_text(json.dumps({"fingerprint": {"godot": "test", "renderer": "test", "gpu": "test"}, "images": {"existing": "keep-this-hash"}}))
            approve(report, "reviewer", reason="reviewed", names=["scene"], accept_visual_changes=True, baseline_dir=baseline)
            manifest = json.loads((baseline / "manifest.json").read_text())
            self.assertEqual(manifest["images"]["existing"], "keep-this-hash")


class HandoffTests(unittest.TestCase):
    def test_response_read_retries_sharing_violation_without_resending(self):
        with patch.object(Path, "read_text", side_effect=[PermissionError("sharing"), '{"ok": true}']) as read:
            self.assertEqual(read_json_retry(Path("response.json")), {"ok": True})
            self.assertEqual(read.call_count, 2)

    def test_malformed_response_is_not_hidden(self):
        with patch.object(Path, "read_text", return_value="not-json"):
            with self.assertRaises(json.JSONDecodeError):
                read_json_retry(Path("response.json"))

    def test_repository_task_contract(self):
        tasks, acceptance = validate()
        self.assertEqual(tasks["next_task"], "PORT-001")
        self.assertGreaterEqual(len(acceptance["criteria"]), 7)

    def test_cyclic_tasks_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tasks = json.loads((ROOT / "project/tasks.json").read_text(encoding="utf-8"))
            tasks["tasks"][0]["depends_on"] = [tasks["tasks"][0]["id"]]
            (root / "tasks.json").write_text(json.dumps(tasks))
            (root / "acceptance.json").write_bytes((ROOT / "project/acceptance.json").read_bytes())
            with self.assertRaisesRegex(ValueError, "cycle"):
                validate(root)


if __name__ == "__main__":
    unittest.main()
