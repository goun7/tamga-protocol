#!/usr/bin/env python3
"""explain — UYUMLULUK-ALİASI → tamga_explain (kök-modül).

2026-09-11 tek-sahip-düzenlemesi: mantık kök-modül tamga_explain.py'ye taşındı
(wheel-yüzeyi; `tamga explain` CLI'ye bağlanır). Bu dosya repo-checkout
yolçaplarını (AT-016, verify_lite, REPRODUCE örnekleri) çalışır tutar —
repo kökünden python3 tools/explain.py çağrıları aynen çalışmaya devam eder.

Usage (değişmedi):
  python3 tools/explain.py <receipt.json>            # dx402-receipt veya charge-kaydı (TR)
  python3 tools/explain.py --en <receipt.json>       # English rendering
  python3 tools/explain.py --charge <ledger.jsonl> 2  # zincir-N-kayıt (TR)
"""
import sys
import pathlib
import runpy

_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))
runpy.run_path(str(_ROOT / "tamga_explain.py"), run_name="__main__")
