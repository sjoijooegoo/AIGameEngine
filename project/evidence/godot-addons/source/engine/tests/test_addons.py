import tempfile
from pathlib import Path
import unittest
import zipfile

from engine.tools.addons import payload, sha, validate_deployed


class AddonDeploymentTests(unittest.TestCase):
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
