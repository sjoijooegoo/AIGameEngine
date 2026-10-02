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

# PowerShell/CI pipe readers expect UTF-8, regardless of the Windows legacy code page.
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
SESSIONS = ROOT / "artifacts/sessions"
SCENES = {"lab": "res://scenes/lab.tscn", "probe": "res://scenes/adapter_probe.tscn"}


def source_fingerprint():
    digest = hashlib.sha256()
    for path in sorted((ROOT / "game").rglob("*")):
        if path.is_file() and ".godot" not in path.parts and path.suffix not in (".uid", ".import"):
            digest.update(path.relative_to(ROOT).as_posix().encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def godot_path() -> Path:
    configured = os.environ.get("GODOT_BIN")
    path = Path(configured) if configured else ROOT / ".tools/Godot_v4.7.2-stable_win64_console.exe"
    if not path.is_file():
        raise RuntimeError("Godot not found. Run tools/setup.ps1 or set GODOT_BIN.")
    return path.resolve()


def atomic_json(path: Path, data):
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temp, path)


def read_json_retry(path: Path, timeout=2):
    """Retry only transient Windows file-sharing failures, never resend a game command."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (PermissionError, FileNotFoundError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.01)


def validate_session(value: str | Path) -> Path:
    path = Path(value).resolve()
    if path.parent != SESSIONS.resolve() or not path.is_dir():
        raise ValueError("Session must be a direct child of artifacts/sessions")
    return path


class Client:
    def __init__(self, session: str | Path, process=None):
        self.session = validate_session(session)
        self.process = process

    @classmethod
    def launch(cls, rendered=True, timeout=45, scene="lab"):
        if scene not in SCENES:
            raise ValueError(f"Unknown scene: {scene}")
        session = SESSIONS / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
        session.mkdir(parents=True)
        atomic_json(session / "context.json", {"build_id": source_fingerprint(), "scene": scene})
        command = [str(godot_path()), "--path", str(ROOT / "game"), "--fixed-fps", "60", "--max-fps", "60", "--resolution", "1280x720", "--position", "40,40"]
        command.extend(["--scene", SCENES[scene]])
        if not rendered:
            command.append("--headless")
        command.extend(["--", "--ai-session=" + session.as_posix()])
        with (session / "engine.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
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
        atomic_json(ROOT / "artifacts/latest-session.json", {"session": str(session)})
        return client

    def call(self, command: str, timeout=30, **args):
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
    start.add_argument("--scene", choices=SCENES, default="lab")
    call = subs.add_parser("call")
    call.add_argument("command")
    call.add_argument("--session", required=True)
    call.add_argument("--args", default="{}")
    call.add_argument("--args-file", type=Path)
    subs.add_parser("play")
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
        command = [str(godot_path()), "--path", str(ROOT / "game")]
        if args.mode == "import":
            command.extend(["--headless", "--editor", "--import"])
        elif args.mode == "editor":
            command.append("--editor")
        sys.exit(subprocess.call(command))


if __name__ == "__main__":
    main()
