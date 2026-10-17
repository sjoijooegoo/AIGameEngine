"""Recorded entry point: python engine/run.py [--project sandbox] <command> ..."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import runpy
import sys
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

COMMANDS = {name: "engine.tools." + name for name in (
    "lab", "qa", "assets", "asset_qa", "visual", "sequence", "project", "build",
    "smoke_release", "make_sample_assets", "make_asset_fixtures", "addons", "addon_qa", "addon_systems_qa")}
COMMANDS["mcp"] = "engine.mcp.server"


class Tee:
    def __init__(self, stream, log):
        self.stream, self.log = stream, log
    def write(self, text):
        self.log.write(text); self.log.flush()
        return self.stream.write(text)
    def flush(self):
        self.log.flush(); self.stream.flush()
    def __getattr__(self, name):
        return getattr(self.stream, name)


def review_exit(command, code, run_id):
    if command != "qa" or code != 2:
        return False
    from engine.core.paths import LATEST
    try:
        report = json.loads(Path(json.loads((LATEST / "report.json").read_text(encoding="utf-8"))["report"]).read_text(encoding="utf-8"))
        context = json.loads((Path(report["session"]) / "context.json").read_text(encoding="utf-8"))
        return context.get("run_id") == run_id and not report["summary"]["failed"] and report["summary"]["visual_needs_review"] > 0
    except (OSError, ValueError, KeyError):
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project")
    parser.add_argument("command", choices=[*COMMANDS, "sync"])
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.project:
        os.environ["AIGE_PROJECT"] = args.project
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    from engine.core.audit import Invocation
    invocation = Invocation(args.command, arguments=args.arguments)
    os.environ["AIGE_RUN_ID"] = invocation.id
    sys.argv = [args.command, *args.arguments]
    old_out, old_err = sys.stdout, sys.stderr
    # MCP carries base64 images: record each tool's metadata, not protocol payloads.
    log = None
    if args.command != "mcp":
        log = invocation.path.with_suffix(".log").open("w", encoding="utf-8")
        invocation.update(output_log=str(invocation.path.with_suffix(".log")))
        sys.stdout, sys.stderr = Tee(old_out, log), Tee(old_err, log)
    try:
        if args.command == "sync":
            from engine.core.runtime import sync
            result = sync()
            print(f"Synced {len(result['files'])} runtime files")
        else:
            runpy.run_module(COMMANDS[args.command], run_name="__main__")
    except SystemExit as error:
        code = error.code if isinstance(error.code, int) else 1 if error.code else 0
        status = "completed" if code == 0 else "needs_review" if review_exit(args.command, code, invocation.id) else "failed"
        invocation.finish(status, code)
        raise
    except BaseException as error:
        invocation.finish("failed", 1, error=str(error), traceback=traceback.format_exc())
        raise
    else:
        invocation.finish()
    finally:
        sys.stdout, sys.stderr = old_out, old_err
        if log:
            log.close()


if __name__ == "__main__":
    main()
