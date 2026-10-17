"""Explicit, hash-checked deployment of the shared Godot addon."""
import hashlib
import json
import os
from pathlib import Path

from engine.core.io import atomic_json
from engine.core.paths import PROJECT_ROOT, RUNTIME, RUNTIME_SOURCE, SESSIONS, require_project


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_files():
    return {p.relative_to(RUNTIME_SOURCE).as_posix(): p for p in sorted(RUNTIME_SOURCE.rglob("*"))
            if p.is_file() and p.suffix in (".gd", ".uid")}


def desired_files(project_root=PROJECT_ROOT):
    files = {name: p.read_bytes() for name, p in source_files().items()}
    config = {"version": 1, "session_root": os.path.relpath(SESSIONS, project_root).replace("\\", "/")}
    files["runtime.json"] = (json.dumps(config, indent=2) + "\n").encode("utf-8")
    return files


def _safe_member(target, name):
    path = (target / name).resolve()
    if path == target.resolve() or not path.is_relative_to(target.resolve()):
        raise ValueError("Invalid runtime manifest path")
    return path


def sync(project_root=PROJECT_ROOT, source=None):
    """Validate the entire old copy before replacing any file; no force bypass."""
    project_root = Path(project_root).resolve()
    if not (project_root / "project.godot").is_file():
        raise RuntimeError("Cannot sync to a missing Godot project")
    target = project_root / "addons/ai_engine"
    desired = desired_files(project_root) if source is None else source
    manifest = target / "deployment.json"
    previous = json.loads(manifest.read_text(encoding="utf-8")) if manifest.exists() else {"files": {}}
    known = previous["files"]
    for name, expected in known.items():
        path = _safe_member(target, name)
        if not path.is_file() or digest(path) != expected:
            raise RuntimeError("Deployed runtime modified; preserve/reconcile it before syncing: " + str(path))
    if target.exists():
        extra = {p.relative_to(target).as_posix() for p in target.rglob("*") if p.is_file()} - set(known) - {"deployment.json"}
        if extra:
            raise RuntimeError("Unmanaged runtime files: " + ", ".join(sorted(extra)))
    # Resolve all manifest members before any write.
    targets = {name: _safe_member(target, name) for name in set(known) | set(desired)}
    for name, data in desired.items():
        path = targets[name]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    for name in set(known) - set(desired):
        targets[name].unlink()
    result = {"version": 1, "files": {name: hashlib.sha256(data).hexdigest() for name, data in desired.items()}}
    atomic_json(manifest, result)
    return result


def require_synced():
    require_project()
    expected = desired_files()
    manifest = RUNTIME / "deployment.json"
    if not manifest.is_file():
        raise RuntimeError("Runtime is not deployed. Run python engine/run.py sync")
    deployed = json.loads(manifest.read_text(encoding="utf-8"))
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in expected.items()}
    if deployed.get("files") != hashes:
        raise RuntimeError("Shared runtime changed. Run python engine/run.py sync, then import")
    actual = {p.relative_to(RUNTIME).as_posix() for p in RUNTIME.rglob("*") if p.is_file()} - {"deployment.json"}
    if actual != set(hashes):
        raise RuntimeError("Unexpected deployed runtime files")
    for name, sha in hashes.items():
        path = RUNTIME / name
        if not path.is_file() or digest(path) != sha:
            raise RuntimeError("Deployed runtime modified: " + str(path))
