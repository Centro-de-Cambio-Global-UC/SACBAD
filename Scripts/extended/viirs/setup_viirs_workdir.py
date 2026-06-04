#!/usr/bin/env python3
"""
Prepare Output/extended/viirs/ for the VIIRS notebooks and cut_20km.py.

Run from repository root:
  python Scripts/extended/viirs/setup_viirs_workdir.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from viirs_paths import WORK_ROOT, ensure_workdirs


def main() -> None:
    root = ensure_workdirs()
    print("VIIRS working directory ready:")
    print(f"  {root}")
    print()
    print("Next steps:")
    print("  1. cd Output/extended/viirs")
    print("  2. jupyter notebook ../../../../Scripts/extended/viirs/notebooks/0)VIIRS_download.ipynb")
    print("     (or open notebooks from Scripts/extended/viirs/notebooks/ with kernel cwd = Output/extended/viirs)")
    print("  3. Run notebooks 0 -> 1 -> 2 in order")
    print("  4. Optional annual clip: python Scripts/extended/viirs/python/cut_20km.py")


if __name__ == "__main__":
    main()
