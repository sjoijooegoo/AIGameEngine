import tempfile
from pathlib import Path
import unittest
import zipfile

from engine.tools.addons import payload, sha, validate_deployed, validate_expansion


class AddonDeploymentTests(unittest.TestCase):
    def test_limbo_generated_editor_flag_does_not_hide_import_setting_edits(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            name = "limboai/icons/BTAction.svg.import"
            path = target / name
            path.parent.mkdir(parents=True)
            original = b'metadata={\n"vram_texture": false\n}\n[params]\nscale=1\n'
            generated = original.replace(b'metadata={\n', b'metadata={\n"has_editor_variant": true,\n')
            path.write_bytes(generated)
            validate_deployed(target, {name: sha(original)})
            path.write_bytes(generated.replace(b'scale=1', b'scale=2'))
            with self.assertRaisesRegex(ValueError, 'modified'):
                validate_deployed(target, {name: sha(original)})

    def test_expansion_preserves_existing_packages(self):
        old = {"id": "old", "sha256": "aaa"}
        previous = {"packages": [old], "files": {"old/a.gd": "abc"}}
        validate_expansion(previous, {"old/a.gd": "abc", "new/b.gd": "def"}, [old, {"id": "new"}])
        for hashes, packages in [({}, []), ({"old/a.gd": "changed"}, [old]),
                                 ({"old/a.gd": "abc"}, [{"id": "old", "sha256": "bbb"}])]:
            with self.assertRaisesRegex(ValueError, "explicit migration"):
                validate_expansion(previous, hashes, packages)

    def archive(self, root, member):
        path = root / "package.zip"
        with zipfile.ZipFile(path, "w") as z:
            z.writestr(member, b"plugin")
        return path, {"id": "example", "prefix": "root/addons/example/", "sha256": sha(path.read_bytes())}

    def test_archive_integrity_precedes_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            path, package = self.archive(Path(directory), "root/addons/example/a.gd")
            path.write_bytes(path.read_bytes() + b"tamper")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                payload(package, path)

    def test_archive_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path, package = self.archive(Path(directory), "root/addons/example/../outside.gd")
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                payload(package, path)

    def test_binary_resources_preserved_and_local_edits_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, package = self.archive(root, "root/addons/example/libs/native.dll")
            files = payload(package, path)
            self.assertEqual(files, {"example/libs/native.dll": b"plugin"})
            target = root / "addons"
            for name, data in files.items():
                (target / name).parent.mkdir(parents=True, exist_ok=True)
                (target / name).write_bytes(data)
            known = {name: sha(data) for name, data in files.items()}
            validate_deployed(target, known)
            (target / "example/libs/native.dll").write_bytes(b"local fix")
            with self.assertRaisesRegex(ValueError, "modified"):
                validate_deployed(target, known)
            self.assertEqual((target / "example/libs/native.dll").read_bytes(), b"local fix")


if __name__ == "__main__":
    unittest.main()
