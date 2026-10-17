"""AI entry point: launch a Godot session and exchange recorded, bounded commands."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
import re

# PowerShell/CI pipe readers expect UTF-8, regardless of the Windows legacy code page.
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8")

from engine.core.paths import ROOT, PROJECT_ROOT, PROJECT_ID, PROJECT, SESSIONS, LATEST, LOGS, godot_path, resource_path
from engine.core.io import atomic_json, read_json_retry
from engine.core.runtime import require_synced
from engine.core.audit import Invocation, current_run
from engine.core.process import HIDDEN
SCENES = PROJECT["scenes"]


def source_fingerprint():
    digest = hashlib.sha256()
    for path in sorted((PROJECT_ROOT).rglob("*")):
        if path.is_file() and ".godot" not in path.parts and path.suffix not in (".uid", ".import"):
            digest.update(path.relative_to(ROOT).as_posix().encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def validate_session(value: str | Path) -> Path:
    path = Path(value).resolve()
    if path.parent != SESSIONS.resolve() or not path.is_dir():
        raise ValueError("Session must be a direct child of logs/sessions")
    return path


def scene_resource(scene):
    resource = SCENES.get(scene)
    if PROJECT.get("assembly", False) and scene.startswith("assembly:") and re.fullmatch(r"[a-z][a-z0-9_.-]{0,63}", scene[9:]) and ".." not in scene[9:]:
        resource = "res://generated/" + scene[9:] + "/scene.tscn"
        if not (PROJECT_ROOT / resource[6:]).is_file():
            raise ValueError("Build the assembled scene first")
    if resource is None:
        raise ValueError(f"Unknown scene: {scene}")
    if not resource_path(resource).is_file():
        raise ValueError("Scene is not implemented: " + resource)
    return resource


class Client:
    def __init__(self, session: str | Path, process=None):
        self.session = validate_session(session)
        self.process = process

    @classmethod
    def launch(cls, rendered=True, timeout=45, scene=None):
        require_synced()
        scene = scene or PROJECT["default_scene"]
        resource = scene_resource(scene)
        session = SESSIONS / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
        session.mkdir(parents=True)
        atomic_json(session / "context.json", {"build_id": source_fingerprint(), "scene": scene, "project": PROJECT_ID, "run_id": current_run()})
        command = [str(godot_path()), "--path", str(PROJECT_ROOT), "--fixed-fps", "60", "--max-fps", "60", "--resolution", "1280x720", "--position", "40,40"]
        command.extend(["--scene", resource])
        if not rendered:
            command.append("--headless")
        command.extend(["--", "--ai-session=" + session.as_posix()])
        with (session / "engine.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, creationflags=HIDDEN)
        atomic_json(session / "launch.json", {"command": command, "pid": process.pid})
        client = cls(session, process)
        deadline = time.monotonic() + timeout
        while not (session / "ready.json").exists():
            if process.poll() is not None:
                raise RuntimeError(f"Godot exited ({process.returncode}). See {session / 'engine.log'}")
            if time.monotonic() > deadline:
                process.terminate()
                process.wait(timeout=10)
                raise TimeoutError(f"Bridge did not start. See {session / 'engine.log'}")
            time.sleep(0.05)
        atomic_json(LATEST / "session.json", {"session": str(session)})
        return client

    def call(self, command: str, timeout=30, **args):
        invocation = Invocation(command, kind="game", arguments=args)
        invocation.update(session=str(self.session))
        try:
            result = self._call(command, timeout=timeout, **args)
        except BaseException as error:
            invocation.finish("failed", 1, error=str(error))
            raise
        invocation.finish()
        return result

    def _call(self, command: str, timeout=30, **args):
        if command == "sequence":
            timeout = max(timeout, min(120, args.get("count", 12) * (args.get("interval", 5) / 60 + 0.5) + 10))
        if (self.session / "timed-out.json").exists() and command != "quit":
            raise RuntimeError("This session timed out; restart it before sending more commands")
        lock = self.session / ".command-lock"
        try:
            lock.mkdir()
        except FileExistsError:
            raise RuntimeError("Another client is using this session; commands must be sequential") from None
        try:
            if (self.session / "request.json").exists():
                raise RuntimeError("Previous request is pending. Restart the session after a timeout.")
            request_id = str(time.time_ns())
            request = {"id": request_id, "command": command, "args": args}
            response = self.session / f"response_{request_id}.json"
            with (self.session / "trace.jsonl").open("a", encoding="utf-8") as trace:
                trace.write(json.dumps(request, ensure_ascii=False) + "\n")
            atomic_json(self.session / "request.json", request)
            deadline = time.monotonic() + timeout
            while not response.exists():
                if self.process and self.process.poll() is not None:
                    raise RuntimeError("Godot exited during command")
                if time.monotonic() > deadline:
                    atomic_json(self.session / "timed-out.json", request)
                    raise TimeoutError(f"Timed out on {command}. See {self.session / 'engine.log'}")
                time.sleep(0.01)
            result = read_json_retry(response)
            if str(result.get("id")) != request_id:
                raise RuntimeError("Mismatched protocol response")
            if not result["ok"]:
                raise RuntimeError(result["error"])
            return result["result"]
        finally:
            lock.rmdir()

    def close(self):
        try:
            self.call("quit", timeout=5)
        finally:
            if self.process:
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.terminate()
                    self.process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="mode", required=True)
    start = subs.add_parser("start")
    start.add_argument("--headless", action="store_true")
    start.add_argument("--scene", default=PROJECT["default_scene"], help="Configured scene alias, or assembly:<scene_id> when enabled")
    call = subs.add_parser("call")
    call.add_argument("command")
    call.add_argument("--session", required=True)
    call.add_argument("--args", default="{}")
    call.add_argument("--args-file", type=Path)
    subs.add_parser("play").add_argument("--scene", default=PROJECT["default_scene"], help="Configured scene alias, or assembly:<scene_id> when enabled")
    subs.add_parser("editor")
    subs.add_parser("import")
    replay = subs.add_parser("replay")
    replay.add_argument("trace", type=Path)
    replay.add_argument("--headless", action="store_true")
    replay.add_argument("--allow-source-change", action="store_true")
    args = parser.parse_args()
    if args.mode == "start":
        client = Client.launch(rendered=not args.headless, scene=args.scene)
        print(json.dumps({"session": str(client.session), "ready": json.loads((client.session / "ready.json").read_text())}, ensure_ascii=False))
    elif args.mode == "call":
        payload = json.loads(args.args_file.read_text(encoding="utf-8")) if args.args_file else json.loads(args.args)
        print(json.dumps(Client(args.session).call(args.command, **payload), ensure_ascii=False, indent=2))
    elif args.mode == "replay":
        context = json.loads((args.trace.parent / "context.json").read_text(encoding="utf-8"))
        if context.get("project", PROJECT_ID) != PROJECT_ID:
            raise RuntimeError("Replay belongs to another project; select it with --project")
        if context["build_id"] != source_fingerprint() and not args.allow_source_change:
            raise RuntimeError("Source changed. Use --allow-source-change only for intentional regression replay.")
        client = Client.launch(rendered=not args.headless, scene=context["scene"])
        try:
            for line in args.trace.read_text(encoding="utf-8").splitlines():
                request = json.loads(line)
                if request["command"] != "quit":
                    client.call(request["command"], **request["args"])
            print(client.session)
        finally:
            client.close()
    else:
        require_synced()
        command = [str(godot_path()), "--path", str(PROJECT_ROOT)]
        if args.mode == "import":
            command.extend(["--headless", "--editor", "--import"])
        elif args.mode == "editor":
            command.append("--editor")
        elif args.mode == "play":
            command.extend(["--scene", scene_resource(args.scene)])
        run = LOGS / "runs" / (args.mode + "-" + uuid.uuid4().hex[:8])
        run.mkdir(parents=True)
        command.extend(["--log-file", str(run / "engine.log")])
        metadata = {"project": PROJECT_ID, "command": command, "run_id": current_run(), "status": "running"}
        atomic_json(run / "run.json", metadata)
        with (run / "process.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, creationflags=HIDDEN)
        output = (run / "process.log").read_text(encoding="utf-8", errors="replace")
        code = result.returncode
        if args.mode == "import" and re.search(r"SCRIPT ERROR|^ERROR:|Parse Error", output, re.M):
            code = code or 1
        metadata.update(status="failed" if code else "completed", exit_code=code)
        atomic_json(run / "run.json", metadata)
        print(str(run / "engine.log"))
        if code:
            print(output[-4000:], file=sys.stderr)
        sys.exit(code)


if __name__ == "__main__":
    main()
