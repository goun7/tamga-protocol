#!/usr/bin/env python3
"""tests/quiet_host_round.py — sessiz-host onay-turu bekleyici (kurucu-delegasyonu,
2026-09-06). loadavg(1m) eşiğin altına inene dek her POLL_S saniyede bir kontrol
eder; kapı açılınca sırayla op-bench + run-edge koşar, kanıtları
.evidence/BENCH/<tarih>/ altına bırakır. Bekleyen-tur: E-4 Faz-2 çıkış-kriteri.

Ortam-değişkenleri: QHR_MAX_HOURS (varsayılan 10), QHR_POLL_S (varsayılan 300).
Çıkış: 0 = iki-bench de-başarılı; 1/2 = bench-RED; 3 = süre-aşımı.
"""
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POLL_S = int(os.environ.get("QHR_POLL_S", "300"))
MAX_HOURS = float(os.environ.get("QHR_MAX_HOURS", "10"))
THRESH = 0.35  # bench'lerin iç-kapısıyla aynı: 0.35 * nproc


def load1():
    return float(open("/proc/loadavg").read().split()[0])


def main():
    nproc = os.cpu_count() or 1
    deadline = time.monotonic() + MAX_HOURS * 3600
    while time.monotonic() < deadline:
        la = load1()
        if la <= THRESH * nproc:
            print(f"[{time.strftime('%H:%M:%S')}] kapı-açık (loadavg1={la:.2f} "
                  f"<= {THRESH * nproc:.2f}) — op-bench başlıyor", flush=True)
            r1 = subprocess.run(["python3", str(ROOT / "tests/bench_runner_overhead.py")],
                                cwd=ROOT)
            if r1.returncode != 0:
                print(f"op-bench rc={r1.returncode} — tur-iptal", flush=True)
                return 1
            print(f"[{time.strftime('%H:%M:%S')}] op-bench OK — run-edge başlıyor "
                  "(c30 dahil ~3 dk)", flush=True)
            r2 = subprocess.run(["python3", str(ROOT / "tests/bench_run_edge.py")], cwd=ROOT)
            print(f"run-edge rc={r2.returncode}", flush=True)
            return 0 if r2.returncode == 0 else 2
        print(f"[{time.strftime('%H:%M:%S')}] meşgul (loadavg1={la:.2f} > "
              f"{THRESH * nproc:.2f}) — {POLL_S}s sonra tekrar", flush=True)
        time.sleep(POLL_S)
    print("süre-aşımı: sessiz-pencere-açılmadı", flush=True)
    return 3


if __name__ == "__main__":
    sys.exit(main())
