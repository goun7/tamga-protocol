"""Pytest path bootstrap — tests/ sits one level below the flat module root,
so the package dir is prepended to sys.path for stdlib-only collection."""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
