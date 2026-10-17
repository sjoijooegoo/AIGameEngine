"""Deploy pinned third-party packages to the isolated addon experiment only."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

from engine.core.io import atomic_json
from engine.core.paths import ROOT, PROJECT_ID, PROJECT_ROOT


def sha(data):
    return hashlib.sha256(data).hexdigest()


def payload(package, archive):
    if sha(archive.read_bytes()) != package["sha256"]:
        raise ValueError("Package hash mismatch: " + package["id"])
    files = {}
    with zipfile.ZipFile(archive) as z:
        for item in z.infolist():
            if item.is_dir() or not item.filename.startswith(package["prefix"]):
                continue
            relative = item.filename[len(package["prefix"]):]
            parts = relative.replace("\\", "/").split("/")
            if any(p in ("", ".", "..") or ":" in p for p in parts):
                raise ValueError("Unsafe package member")
            name = package["id"] + "/" + "/".join(parts)
            if name in files:
                raise ValueError("Duplicate package member")
            files[name] = z.read(item)
    if not files:
        raise ValueError("Package prefix is empty")
    return files


def validate_deployed(target, known):
    for name, expected in known.items():
        path = (target / name).resolve()
        if not path.is_relative_to(target.resolve()):
            raise ValueError("Unsafe manifest member")
        if not path.is_file() or sha(path.read_bytes()) != expected:
            raise ValueError("Deployed plugin modified; preserve/reconcile: " + str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "verify"])
    args = parser.parse_args()
    lock = json.loads((ROOT / "engine/vendor/addons.lock.json").read_text(encoding="utf-8"))
    if PROJECT_ID != lock["project"]:
        raise ValueError("Use --project addon_probe; production adoption is not configured")
    target = PROJECT_ROOT / "addons"
    manifest = target / "deployment.json"
    previous = json.loads(manifest.read_text(encoding="utf-8")) if manifest.exists() else {"files": {}}
    validate_deployed(target, previous["files"])
    desired = {}
    for package in lock["packages"]:
        archive = ROOT / "engine/vendor" / package["archive"]
        if not archive.exists():
            if args.action == "verify":
                raise ValueError("Missing locked archive")
            request = urllib.request.Request(package["url"], headers={"User-Agent": "AIGameEngine-addon-probe"})
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            if sha(data) != package["sha256"]:
                raise ValueError("Download hash mismatch")
            archive.write_bytes(data)
        desired.update(payload(package, archive))
        plugin_dir = target / package["id"]
        if plugin_dir.exists():
            for path in plugin_dir.rglob("*"):
                name = path.relative_to(target).as_posix()
                if path.is_file() and name not in previous["files"]:
                    # Godot may generate sidecars during import, never source or libraries.
                    if path.suffix not in (".uid", ".import"):
                        raise ValueError("Unmanaged deployed plugin file: " + str(path))
    hashes = {name: sha(data) for name, data in desired.items()}
    if previous["files"] and previous["files"] != hashes:
        raise ValueError("Plugin upgrade requires explicit migration; no silent overwrite")
    if args.action == "verify":
        if previous["files"] != hashes:
            raise ValueError("Plugins not installed")
    else:
        for name, data in desired.items():
            path = target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        atomic_json(manifest, {"version": 1, "packages": lock["packages"], "files": hashes})
    print(json.dumps({"project": PROJECT_ID, "action": args.action, "files": len(hashes)}))


if __name__ == "__main__":
    main()
