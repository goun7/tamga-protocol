#!/usr/bin/env python3
"""Konsol-sürümleri ↔ runner-dispatch drift kontrolü.

Keşif-2026-09-18: `python3 tamga_runner.py` 9-komut-için "unknown command"-veriyordu
(doctor, liveness-probe, attest-verify, verify-cr, verify-mini, bundle, epoch-verify,
project-head, explain) — çünkü-onlar tamga_bootstrap-console-script-içinde-görevlendiriliyor,
runner'da-değil. İki-giriş-noktası-tutarlı-değildi; "unknown" mesajı onların-var-olduğunu
söylemiyordu. Bu-test-iki-yüzeyi-de-sunar.

Kullanım: python3 tools/konsol_drift_kontrol.py
Çıkış: rc=0-tutarlı · rc=1-drift-bulundu (gerçek-drift = USAGE'da-olup-hiçbir-
giriş-noktasında-olmayan-komut, VEYA-çalışan-ama-USAGE'da-reklam-edilmeyen).
"""
from __future__ import annotations

import ast
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def runner_dispatch(path: pathlib.Path) -> set[str]:
    """tamga_runner.py'nin `cmds = {...}` sözlüğü + ENGINE_FREE yönlendirme-listesi."""
    t = path.read_text()
    out = set(re.findall(r'"([a-z][a-z0-9-]+)": cmd_', t))
    out |= set(re.findall(r'\{"([a-z][a-z0-9-]+)", ?', t[t.find("ENGINE_FREE"):t.find("}", t.find("ENGINE_FREE"))]))
    return out


def runner_usage(path: pathlib.Path) -> set[str]:
    """USAGE-bloğunda-reklam-edilen-komutlar (girintili-satır-başı)."""
    t = path.read_text()
    start = t.find("USAGE")
    stop = t.find('if __name__')
    block = t[start:stop]
    return {m for m in re.findall(r'^  ([a-z][a-z0-9-]+) ', block, re.M)}


def bootstrap_dispatch(path: pathlib.Path) -> set[str]:
    """tamga_bootstrap.py'de `argv[0] == "…"` ile-görevlendirilen-komutlar."""
    t = path.read_text()
    return set(re.findall(r'argv\[0\]\s*==\s*"([a-z][a-z0-9-]+)"', t))


def main() -> int:
    runner = ROOT / "tamga_runner.py"
    boot = ROOT / "tamga_bootstrap.py"
    if not runner.exists() or not boot.exists():
        print("SKIP: modüller-bulunamadı")
        return 0

    dispatch = runner_dispatch(runner)
    usage = runner_usage(runner)
    bootd = bootstrap_dispatch(boot)

    # İki-giriş-noktasının-birliği: runner-+ bootstrap-bildiği-komutlar
    known = dispatch | bootd

    drift = usage - known            # USAGE-reklam-ediyor-hiçbiri-yok
    hidden = (dispatch | bootd) - usage  # çalışıyor-ama-USAGE'da-yok

    print(f"runner-dispatch : {len(dispatch)} komut")
    print(f"bootstrap       : {len(bootd)} komut")
    print(f"USAGE-reklam    : {len(usage)} komut")
    print()
    if drift:
        print(f"DRIFT — USAGE'da-var-ama-HİÇBİR-giriş-noktasında-değil: {sorted(drift)}")
        return 1
    if hidden:
        print(f"DRIFT — çalışıyor-ama-USAGE'da-reklam-edilmiyor: {sorted(hidden)}")
        return 1
    print(f"TUTARLI: {len(usage)} komut — USAGE, runner-ve-bootstrap-giriş-noktalarını-birebilir")
    return 0


if __name__ == "__main__":
    sys.exit(main())
