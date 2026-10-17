"""One project selection per process, shared by CLI, MCP and workers."""
from __future__ import annotations

import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = json.loads((ROOT / "workspace.json").read_text(encoding="utf-8"))
if CONFIG.get("version") != 1:
    raise ValueError("Unsupported workspace configuration")


def workspace_path(value: str) -> Path:
    path = (ROOT / value).resolve()
    if not path.is_relative_to(ROOT) or path == ROOT:
        raise ValueError("Configured path must stay inside the workspace")
    return path


PROJECT_ID = os.environ.get("AIGE_PROJECT", CONFIG["default_project"])
if PROJECT_ID not in CONFIG["projects"]:
    raise ValueError("Unknown project: " + PROJECT_ID)
PROJECT = CONFIG["projects"][PROJECT_ID]
PROJECT_ROOT = workspace_path(PROJECT["root"])
TESTS = workspace_path(PROJECT["tests"])
SOURCES = workspace_path(PROJECT["sources"])
CATALOG = workspace_path(PROJECT["catalog"])
RECIPES = workspace_path(PROJECT["recipes"])
LIBRARY = PROJECT_ROOT / "assets/library"
GENERATED = PROJECT_ROOT / "generated"
RUNTIME_SOURCE = workspace_path(CONFIG["runtime_source"])
RUNTIME = PROJECT_ROOT / "addons/ai_engine"
LOGS = workspace_path(CONFIG["logs"])
SESSIONS = LOGS / "sessions"
JOBS = LOGS / "jobs"
LATEST = LOGS / "latest"
CACHE = workspace_path(CONFIG["cache"]) / PROJECT_ID
BUILD = workspace_path(CONFIG["build"])
TEMPLATES = workspace_path(CONFIG["templates"])


def require_project() -> Path:
    if not (PROJECT_ROOT / "project.godot").is_file():
        raise RuntimeError(f"Project {PROJECT_ID!r} is reserved but not implemented: {PROJECT_ROOT}")
    return PROJECT_ROOT


def godot_path() -> Path:
    configured = os.environ.get("GODOT_BIN")
    path = Path(configured) if configured else workspace_path(CONFIG["godot"])
    if not path.is_file():
        raise RuntimeError("Godot not found. Run engine/tools/setup.ps1 or set GODOT_BIN.")
    return path.resolve()


def resource_path(value: str) -> Path:
    if not value.startswith("res://"):
        raise ValueError("Expected a res:// resource")
    result = (PROJECT_ROOT / value[6:]).resolve()
    if not result.is_relative_to(PROJECT_ROOT):
        raise ValueError("Resource escapes project")
    return result
