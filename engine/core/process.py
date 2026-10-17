"""Owned subprocesses do not create stray Windows console windows."""
import os
import subprocess

HIDDEN = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
