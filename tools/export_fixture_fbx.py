"""Compatibility entry for the Blender background fixture generator."""
import sys
from pathlib import Path
import runpy
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
if __name__ == "__main__":
    runpy.run_module("engine.tools.export_fixture_fbx", run_name="__main__")
