#!/usr/bin/env python3
"""tamga_pugio_receiver — K0 §5 external_anchor alıcısı (K1 köprüsü, Tamga tarafı).

PUGIO metering katmanının ürettiği kanıt-bundle'ının Tamga-çıpasını
(`external_anchor` JSONL satırı) alır ve **yalnız sha256** ile doğrular:

    anchor_id = SHA256(head|merkle_root|event_count)[:32]

İlk-adım ilkesi (K0 §7): PUGIO çekirdeğine/şemasına dokunmaz, bağımlılık
eklemez; standart-kütüphane yeter. Tamga-node bu satırı kendi ledger'ına
"alınan-iş kanıtı" olarak yazabilir.

Kullanım:
    python tamga_pugio_receiver.py cıpa.jsonl            # doğrula (exit 0/1)
    python tamga_pugio_receiver.py --selftest            # kendi-kanıtı: temiz→PASS, bozuk→RED
    python tamga_pugio_receiver.py cıpa.jsonl --write    # doğrula + kabul-edilenleri stdout'a yaz

Her satır bağımsız doğrulanır; TEK bir satır bile RED ise süreç exit 1 verir
(fail-loud — sessiz-geçiş doktrini, Veridict ile ortak).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys

BRIDGE_VERSION = 1


def verify_anchor_line(line: str) -> tuple[bool, str]:
    """Tek JSONL-satırını K0 §5 bağı-formülüyle doğrula (pür sha256)."""
    try:
        a = json.loads(line)
    except json.JSONDecodeError as e:
        return False, f"FAIL: JSON bozuk ({e})"
    if not isinstance(a, dict):
        return False, "FAIL: satır nesne değil"
    if a.get("type") != "external_anchor" or a.get("source") != "pugio":
        return False, "FAIL: zarf-tipi/kaynak uyuşmuyor"
    if a.get("bridge_version") != BRIDGE_VERSION:
        return False, f"FAIL: bilinmeyen bridge_version ({a.get('bridge_version')})"
    try:
        head = str(a["head"])
        merkle = str(a["merkle_root"])
        ec = a["event_count"]
        # tam-sayı-sıkılığı (taze-göz D5): float-kesme ve dizgi-kodlama-hoşgörüsü
        # kapatılır — yalnız gerçek tam-sayı INT kabul; 3.9 → RED, "3" → RED.
        if not isinstance(ec, int) or isinstance(ec, bool):
            return False, "FAIL: event_count tam-sayı olmalı (float/str değil)"
        count = ec
    except (KeyError, TypeError, ValueError) as e:
        return False, f"FAIL: zorunlu-alan eksik/bozuk ({e})"
    if len(head) != 64 or len(merkle) != 64:
        return False, "FAIL: head/merkle_root 64-hex olmalı"
    expect = hashlib.sha256(f"{head}|{merkle}|{count}".encode()).hexdigest()[:32]
    if expect != a.get("anchor_id"):
        return False, "FAIL: anchor_id bağı kopuk (veri-değişikliği)"
    return True, f"PASS: anchor_id={a['anchor_id']} · head={head[:16]}… · {count} olay"


def run(path: str, write: bool) -> int:
    ok_all = True
    accepted: list[str] = []
    with open(path, encoding="utf-8") as fh:
        for no, raw in enumerate(fh, start=1):
            line = raw.strip()
            if not line:
                continue
            ok, msg = verify_anchor_line(line)
            print(f"[{no:03d}] {msg}")
            if ok:
                accepted.append(line)
            else:
                ok_all = False
    if write and ok_all:
        for line in accepted:
            print(line)
    print("SONUÇ:", "SAĞLAM" if ok_all else "RED")
    return 0 if ok_all else 1


def selftest() -> int:
    """Kendi-kanıtı: sentetik-çıpa temiz→PASS, tek-bayt bozulma→RED."""
    head = hashlib.sha256(b"pugio-chain-head").hexdigest()
    merkle = hashlib.sha256(b"pugio-merkle-root").hexdigest()
    anchor = {
        "type": "external_anchor", "bridge_version": BRIDGE_VERSION,
        "source": "pugio", "agent": "selftest",
        "anchor_id": hashlib.sha256(f"{head}|{merkle}|3".encode()).hexdigest()[:32],
        "head": head, "merkle_root": merkle, "event_count": 3,
    }
    line = json.dumps(anchor, sort_keys=True, separators=(",", ":"))
    ok, msg = verify_anchor_line(line)
    print("temiz-çıpa:", msg)
    if not ok:
        return 1

    bad = dict(anchor)
    bad["event_count"] = 4  # tek-sayı bozulma — bağ kopmalı
    bad_line = json.dumps(bad, sort_keys=True, separators=(",", ":"))
    ok, msg = verify_anchor_line(bad_line)
    print("bozuk-çıpa:", msg)
    if ok:
        print("SONUÇ: RED (bozulma yakalanamadı — ALARM)")
        return 1
    print("SONUÇ: SAĞLAM (selftest)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="K0 §5 external_anchor doğrulayıcı (Tamga tarafı)")
    ap.add_argument("path", nargs="?", help="çıpa-JSONL dosyası")
    ap.add_argument("--write", action="store_true", help="kabul-edilen satırları yeniden yazdır")
    ap.add_argument("--selftest", action="store_true", help="dahili tutarlılık-kanıtı")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.path:
        ap.error("path gerekli (--selftest ile başlayanlar için değil)")
    return run(args.path, args.write)


if __name__ == "__main__":
    sys.exit(main())
