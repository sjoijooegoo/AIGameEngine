"""UTF-8 atomic metadata and transient Windows sharing retries."""
import json
import os
from pathlib import Path
import time


def atomic_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temp, path)


def read_json_retry(path: Path, timeout=2):
    deadline = time.monotonic() + timeout
    while True:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (PermissionError, FileNotFoundError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.01)
