#!/usr/bin/env python3
"""keccak256 — UYUMLULUK-ALİASI → tamga_keccak (kök-modül, tek-sahip).

2026-09-11 tek-sahip-düzenlemesi: algoritma kök-modül tamga_keccak.py'ye
taşındı (wheel-yüzeyi: RFC-007 R2 --delivery-alg keccak256 yolçapı kurulumda
da çözülür — 2026-09-11 bulgusu: _digest tools/ yolunu arıyordu, wheel'de
tools/ yok, yol kırılırdı). Bu dosya repo-içi araçların (verify_dx402_*,
make/verify_pairing_fixture, self_pilot) `from keccak256 import keccak256`
tools-path importlarını çalışır tutar.

Bilgi-kaynağı + KAT self-test: tamga_keccak.py.
"""
import sys
import pathlib

_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))
from tamga_keccak import keccak256  # noqa: F401

if __name__ == "__main__":
    # Self-test'i tek-sahipten koş (KAT'ler burada çoğaltılmaz):
    import subprocess
    raise SystemExit(subprocess.run(
        [sys.executable, str(_ROOT / "tamga_keccak.py")]).returncode)
