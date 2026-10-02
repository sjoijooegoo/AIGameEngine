"""Bounded background jobs for asset MCP calls. Each job owns its child processes."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import threading
import time
import uuid

from lab import ROOT, atomic_json


class Cancelled(RuntimeError):
    pass


class Job:
    def __init__(self, kind):
        self.id = uuid.uuid4().hex
        self.directory = ROOT / "artifacts/asset_jobs" / self.id
        self.directory.mkdir(parents=True)
        self.cancelled = threading.Event()
        self.state = {"id": self.id, "kind": kind, "status": "queued", "progress": "Queued"}
        self.persist()

    def persist(self):
        atomic_json(self.directory / "job.json", self.state)

    def check(self):
        if self.cancelled.is_set():
            raise Cancelled("Job cancelled; partial evidence preserved")

    def progress(self, message):
        self.check()
        self.state["progress"] = message
        self.persist()

    def run(self, command, label, timeout=180):
        self.progress(label)
        path = self.directory / (label.replace(" ", "_") + ".log")
        with path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW if __import__("os").name == "nt" else 0)
            start = time.monotonic()
            try:
                while process.poll() is None:
                    self.check()
                    if time.monotonic() - start > timeout:
                        raise TimeoutError(f"{label} exceeded {timeout}s; see {path}")
                    time.sleep(0.05)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
        text = path.read_text(encoding="utf-8", errors="replace")
        if process.returncode or "SCRIPT ERROR" in text or "Parse Error" in text or "\nERROR:" in text:
            raise RuntimeError(f"{label} failed: {text[-2500:]}")
        return text


class Jobs:
    def __init__(self):
        # Godot imports mutate the shared import cache. Never import concurrently.
        self.pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="asset-worker")
        self.jobs = {}

    def submit(self, kind, fn, args):
        if sum(j.state["status"] in ("queued", "running") for j in self.jobs.values()) >= 8:
            raise RuntimeError("Asset queue is full (8 jobs maximum)")
        job = Job(kind)
        self.jobs[job.id] = job

        def execute():
            try:
                job.check()
                job.state["status"] = "running"
                job.persist()
                result = fn(job=job, **args)
                job.state.update(status="completed", result=result, progress="Completed")
            except Cancelled as error:
                job.state.update(status="cancelled", error=str(error))
            except Exception as error:
                job.state.update(status="failed", error=str(error))
            finally:
                job.persist()
        self.pool.submit(execute)
        return {"job_id": job.id, "status": "queued"}

    def status(self, job_id):
        if job_id not in self.jobs:
            raise ValueError("Unknown job in this MCP server session")
        return dict(self.jobs[job_id].state)

    def cancel(self, job_id):
        self.status(job_id)
        self.jobs[job_id].cancelled.set()
        return {"job_id": job_id, "cancellation_requested": True}

    def close(self):
        for job in self.jobs.values():
            if job.state["status"] in ("queued", "running"):
                job.cancelled.set()
        self.pool.shutdown(wait=True)
