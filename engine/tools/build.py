"""Export a configured project into an immutable, versioned Windows package."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import time
import uuid

from engine.core.io import atomic_json
from engine.core.paths import ROOT, PROJECT, PROJECT_ID, PROJECT_ROOT, BUILD, LOGS, LATEST, TEMPLATES, godot_path
from engine.core.process import HIDDEN
from engine.core.runtime import require_synced
from engine.tools.lab import source_fingerprint


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--version")
    parser.add_argument("--preset", help="Explicit Godot export preset; defaults to the selected project's preset")
    args = parser.parse_args()
    require_synced()
    addon_manifest = PROJECT_ROOT / "addons/deployment.json"
    if addon_manifest.is_file():
        from engine.tools.addons import validate_deployed
        validate_deployed(PROJECT_ROOT / "addons", json.loads(addon_manifest.read_text(encoding="utf-8"))["files"])
    version = args.version or time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}", version) or ".." in version:
        raise ValueError("Invalid build version")
    configuration = "debug" if args.debug else "release"
    template = TEMPLATES / ("windows_" + configuration + "_x86_64.exe")
    if not template.is_file():
        raise RuntimeError("Run engine/tools/setup.ps1 -ExportTemplates first")
    directory = BUILD / PROJECT_ID / "windows" / configuration / version
    directory.mkdir(parents=True, exist_ok=False)
    evidence = LOGS / "builds" / (PROJECT_ID + "-" + configuration + "-" + version)
    evidence.mkdir(parents=True, exist_ok=False)
    exe = directory / PROJECT["executable"]
    command = [str(godot_path()), "--headless", "--path", str(PROJECT_ROOT),
               "--export-" + configuration, args.preset or PROJECT["export_preset"], str(exe)]
    metadata = {"project": PROJECT_ID, "configuration": configuration, "version": version,
                "build_id": source_fingerprint(), "command": command, "directory": str(directory),
                "executable": str(exe), "log": str(evidence / "engine.log"), "status": "running"}
    atomic_json(evidence / "build.json", metadata)
    with (evidence / "engine.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, creationflags=HIDDEN)
    text = (evidence / "engine.log").read_text(encoding="utf-8", errors="replace")
    failed = result.returncode != 0 or not exe.is_file() or bool(re.search(r"SCRIPT ERROR|^ERROR:|Parse Error", text, re.M))
    metadata.update(status="failed" if failed else "completed", exit_code=result.returncode)
    atomic_json(evidence / "build.json", metadata)
    if failed:
        raise RuntimeError("Export failed; see " + str(evidence / "engine.log"))
    shutil.copyfile(ROOT / "third_party/GODOT-LICENSE.txt", directory / "GODOT-LICENSE.txt")
    # Non-resource license files are not guaranteed to enter Godot's PCK.
    # Ship explicit notices next to the executable, including optional editor tools.
    for plugin in (PROJECT_ROOT / "addons").iterdir():
        if plugin.is_dir():
            for notice in plugin.glob("*LICENSE*"):
                if notice.is_file():
                    destination = directory / "licenses" / plugin.name / notice.name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(notice, destination)
    metadata["files"] = {p.relative_to(directory).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in directory.rglob("*") if p.is_file()}
    atomic_json(directory / "manifest.json", metadata)
    atomic_json(evidence / "build.json", metadata)
    atomic_json(LATEST / ("build-" + PROJECT_ID + "-" + configuration + ".json"), metadata)
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
