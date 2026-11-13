#!/usr/bin/env python3
"""Prepare the current independent scene assets."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name('prepare-living-assets.py')), run_name='__main__')
