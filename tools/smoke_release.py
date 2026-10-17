"""Compatibility entry; implementation lives in engine.tools.smoke_release."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
if __name__ == "__main__":
    from engine.run import main
    main(['smoke_release', *sys.argv[1:]])
else:
    from engine.tools.smoke_release import *
