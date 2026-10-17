"""Compatibility entry; implementation lives in engine.tools.make_sample_assets."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
if __name__ == "__main__":
    from engine.run import main
    main(['make_sample_assets', *sys.argv[1:]])
else:
    from engine.tools.make_sample_assets import *
