"""Invocation metadata; never prints on the MCP protocol channel."""
from datetime import datetime, timezone
from contextvars import ContextVar
import os
import time
import uuid

from engine.core.io import atomic_json
from engine.core.paths import LOGS, PROJECT_ID

CURRENT_RUN = ContextVar("aige_run_id", default=None)


def current_run():
    return CURRENT_RUN.get() or os.environ.get("AIGE_RUN_ID")


class Invocation:
    def __init__(self, command, kind="cli", arguments=None):
        self.id = uuid.uuid4().hex
        self.path = LOGS / "calls" / (self.id + ".json")
        self.started = time.monotonic()
        self.data = {"run_id": self.id, "kind": kind, "command": command,
                     "project": PROJECT_ID, "parent_run_id": current_run(),
                     "started_at": datetime.now(timezone.utc).isoformat(), "status": "running"}
        if arguments is not None:
            self.data["arguments"] = arguments
        self.update()

    def update(self, **values):
        self.data.update(values)
        atomic_json(self.path, self.data)

    def finish(self, status="completed", exit_code=0, **values):
        self.update(status=status, exit_code=exit_code,
                    ended_at=datetime.now(timezone.utc).isoformat(),
                    seconds=time.monotonic() - self.started, **values)
