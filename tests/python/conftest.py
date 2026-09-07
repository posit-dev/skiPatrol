import sys
from pathlib import Path

INST_PYTHON = Path(__file__).resolve().parents[2] / "inst" / "python"
if str(INST_PYTHON) not in sys.path:
    sys.path.insert(0, str(INST_PYTHON))
