"""Verify exported EXE startup and that release builds refuse to activate the AI bridge."""
import json
import os
from pathlib import Path
import subprocess
import uuid
from lab import ROOT, SESSIONS, atomic_json


def main():
    exe = ROOT / "build/BankCrisisLab.exe"
    if not exe.exists():
        raise SystemExit("Run tools/build.ps1 first")
    evidence = []
    for headless in (True, False):
        session = SESSIONS / ("release-smoke-" + uuid.uuid4().hex[:8])
        session.mkdir(parents=True)
        log = session / "release.log"
        command = [str(exe), "--quit-after", "30", "--log-file", str(log)]
        if headless:
            command.append("--headless")
        command += ["--", "--ai-session=" + session.as_posix()]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=45, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else result.stdout + result.stderr
        assert result.returncode == 0, text
        assert not any(marker in text for marker in ("ERROR:", "SCRIPT ERROR", "Parse Error")), text
        assert not (session / "ready.json").exists(), "Release unexpectedly activated AI bridge"
        evidence.append({"headless": headless, "exit_code": result.returncode, "bridge_disabled": True, "log": str(log)})
    atomic_json(ROOT / "build/smoke-report.json", {"checks": evidence})
    print(json.dumps(evidence, indent=2))


if __name__ == "__main__":
    main()
