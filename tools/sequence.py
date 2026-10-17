"""Compatibility entry; implementation lives in engine.tools.sequence."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
if __name__ == "__main__":
    from engine.run import main
    main(['sequence', *sys.argv[1:]])
else:
    from engine.tools.sequence import *
