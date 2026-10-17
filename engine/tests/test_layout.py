"""Regression checks for the migration's actual failure boundaries."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from engine.core.paths import ROOT, SESSIONS, RUNTIME_SOURCE, PROJECT_ROOT, godot_path, workspace_path, resource_path
from engine.core.process import HIDDEN
from engine.core.runtime import sync
from engine.tools.lab import validate_session


class LayoutTests(unittest.TestCase):
    def test_config_and_resources_cannot_escape_workspace(self):
        for value in ("../outside", "."):
            with self.assertRaises(ValueError):
                workspace_path(value)
        with self.assertRaises(ValueError):
            resource_path("res://../../../../outside.gd")

    def test_runtime_tampering_rejects_entire_sync_before_writes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "project.godot").write_text("config_version=5\n")
            sync(root, {"a.gd": b"original", "b.gd": b"original"})
            target = root / "addons/ai_engine"
            (target / "b.gd").write_bytes(b"user change")
            before = (target / "deployment.json").read_bytes()
            with self.assertRaisesRegex(RuntimeError, "modified"):
                sync(root, {"a.gd": b"updated", "b.gd": b"updated"})
            self.assertEqual((target / "a.gd").read_bytes(), b"original")
            self.assertEqual((target / "b.gd").read_bytes(), b"user change")
            self.assertEqual((target / "deployment.json").read_bytes(), before)

    def test_runtime_update_and_unmanaged_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "project.godot").write_text("config_version=5\n")
            sync(root, {"a.gd": b"v1", "retired.gd": b"v1"})
            sync(root, {"a.gd": b"v2"})
            target = root / "addons/ai_engine"
            self.assertEqual((target / "a.gd").read_bytes(), b"v2")
            self.assertFalse((target / "retired.gd").exists())
            (target / "unexpected.gd").write_bytes(b"user owned")
            with self.assertRaisesRegex(RuntimeError, "Unmanaged"):
                sync(root, {"a.gd": b"v3"})
            self.assertEqual((target / "a.gd").read_bytes(), b"v2")

    def test_runtime_manifest_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "project.godot").write_text("config_version=5\n")
            with self.assertRaisesRegex(ValueError, "manifest path"):
                sync(root, {"../outside.gd": b"invalid"})
            self.assertFalse((root / "addons/outside.gd").exists())

    def test_legacy_entrypoint_works_from_unrelated_cwd(self):
        with tempfile.TemporaryDirectory() as folder:
            commands = ([sys.executable, str(ROOT / "tools/project.py")],
                        [sys.executable, str(ROOT / "engine/run.py"), "project"])
            outputs = []
            for command in commands:
                result = subprocess.run(command, cwd=folder, text=True, encoding="utf-8", capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                outputs.append(json.loads(result.stdout))
            self.assertEqual(outputs[0], outputs[1])

    def test_reserved_bank_never_launches_the_sandbox(self):
        result = subprocess.run([sys.executable, str(ROOT / "engine/run.py"), "--project", "bank", "lab", "start", "--headless"],
                                text=True, encoding="utf-8", capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reserved but not implemented", result.stderr)

    def test_session_requires_direct_child(self):
        SESSIONS.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=SESSIONS) as folder:
            direct = Path(folder)
            nested = direct / "nested"
            nested.mkdir()
            self.assertEqual(validate_session(direct), direct.resolve())
            with self.assertRaises(ValueError):
                validate_session(nested)

    def test_godot_bridge_rejects_session_outside_configured_root(self):
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run([str(godot_path()), "--headless", "--path", str(PROJECT_ROOT),
                                     "--scene", "res://scenes/adapter_probe.tscn", "--",
                                     "--ai-session=" + Path(folder).as_posix()],
                                    capture_output=True, text=True, encoding="utf-8", timeout=30, creationflags=HIDDEN)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("direct child of configured logs/sessions", result.stdout + result.stderr)
            self.assertFalse((Path(folder) / "ready.json").exists())

    def test_runtime_has_no_game_or_sandbox_script_dependency(self):
        for path in RUNTIME_SOURCE.rglob("*.gd"):
            text = path.read_text(encoding="utf-8")
            for forbidden in ('res://scripts/', 'res://testing/', 'res://scenes/', 'res://asset_pipeline/'):
                self.assertNotIn(forbidden, text, str(path))

    def test_cli_usage_error_is_not_visual_review(self):
        from engine.core.paths import LOGS
        before = set((LOGS / "calls").glob("*.json"))
        result = subprocess.run([sys.executable, str(ROOT / "engine/run.py"), "qa", "--invalid-option"],
                                capture_output=True, text=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 2)
        records = [json.loads(p.read_text(encoding="utf-8")) for p in set((LOGS / "calls").glob("*.json")) - before]
        record = next(r for r in records if r["kind"] == "cli" and r["command"] == "qa")
        self.assertEqual(record["status"], "failed")
        self.assertEqual(record["exit_code"], 2)


if __name__ == "__main__":
    unittest.main()
