#!/usr/bin/env python3
"""tamga_pugio_ingest — 81-MERGEN-tarafı PUGIO K0-kanıt-bundle'ı okuyucu (S4-kapanış).

IS_PLANI §7 S4 kalan-adım: "81-MERGEN tarafının aynı şemayı okuması".
Bu araç PUGIO kanıt-bundle'ını (docs/K0_SHARED_ENVELOPE_SPEC.md §4) PUGIO
kütüphanesi ve secret'ı OLMADAN, pür stdlib ile doğrular ve Tamga-doktriniyle
**doğrulama-makbuzu** üretir:

  1) K0 §2 zincir:  sha256(canonical(prev_proof dahil)) == proof  (her olay)
  2) K0 §2 bağ:     events[i].prev_proof == events[i-1].proof (ilk: GENESIS)
  3) K0 §3 kök:     merkle(proof-listesi) == bundle.merkle_root
  4) K0 §4 başlık:  head == son proof, event_count == len(events)

Makbuz (JSONL, deterministik — Tamga external-anchor disiplini):
  { "type": "pugio_bundle_verification", "verifier": "81-mergen-ingest/v1",
    "verdict": "SAĞLAM", "bundle_head": …, "merkle_root": …, "event_count": N,
    "audit": {charge_total, receipts, decisions, agents},
    "receipt_id": sha256(verdict|head|merkle|count)[:32] }

audit: 81'in iş-gerçekleri — ücret-toplamı (₿-tahsilat fatura-eşi), makbuz ve
karar-sayıları, ajan-kümeleri.

Kullanım:
  python3 tamga_pugio_ingest.py <bundle.json>       → doğrula + makbuz yaz
  python3 tamga_pugio_ingest.py --selftest          → dahili temiz/bozuk koşu
Çıkış: 0 = SAĞLAM, 1 = RED (fail-loud — sessiz-geçiş yok).
"""

from __future__ import annotations

import hashlib
import json
import sys

GENESIS = "0" * 64
BUNDLE_VERSION = 1
VERIFIER = "81-mergen-ingest/v1"


# ------------------------------------------------------------------ K0 çekirdeği

def _canonical(ev: dict, prev_proof: str) -> str:
    return "|".join([
        f"{float(ev['ts']):.6f}", str(ev["event_type"]), str(ev["agent_id"]),
        str(ev["host"]), f"{float(ev['amount']):.6f}", str(ev["payload"]),
        prev_proof,
    ])


def _merkle(leaves: list[str]) -> str:
    if not leaves:
        return GENESIS
    layer = list(leaves)
    while len(layer) > 1:
        if len(layer) % 2 == 1:
            layer.append(layer[-1])
        layer = [hashlib.sha256((a + b).encode()).hexdigest()
                 for a, b in zip(layer[::2], layer[1::2])]
    return layer[0]


def verify_bundle(bundle: dict) -> tuple[bool, str, dict]:
    """K0 §2–§4 doğrulaması. Dönüş: (ok, mesaj, audit-özet)."""
    try:
        if int(bundle.get("pugio_bundle_version", 0)) != BUNDLE_VERSION:
            return False, "bundle-sürümü bilinmiyor", {}
        events = bundle.get("events")
        if not isinstance(events, list):
            return False, "events liste değil", {}
        prev = GENESIS
        proofs: list[str] = []
        expected_seq = None
        charge_total = 0.0
        receipts = decisions = 0
        agents: set[str] = set()
        for ev in events:
            if expected_seq is not None and ev["seq"] != expected_seq:
                return False, f"seq-atlaması: {expected_seq} beklenirken {ev['seq']}", {}
            expected_seq = ev["seq"] + 1
            if ev["prev_proof"] != prev:
                return False, f"zincir-kopması @seq={ev['seq']}", {}
            expect = hashlib.sha256(_canonical(ev, prev).encode()).hexdigest()
            if expect != ev["proof"]:
                return False, f"proof-uyuşmazlığı @seq={ev['seq']} (veri-değişikliği)", {}
            if ev["event_type"] == "charge_receipt":
                receipts += 1
                charge_total += float(ev.get("amount") or 0.0)
            elif ev["event_type"] == "permission_decision":
                decisions += 1
            agents.add(str(ev["agent_id"]))
            proofs.append(ev["proof"])
            prev = ev["proof"]
        if bundle.get("head") != prev:
            return False, "head uyuşmuyor", {}
        if bundle.get("merkle_root") != _merkle(proofs):
            return False, "merkle-kökü uyuşmuyor", {}
        count = int(bundle.get("event_count", -1))
        if count != len(events):
            return False, f"event_count uyuşmuyor: {count} ≠ {len(events)}", {}
        audit = {"charge_total": round(charge_total, 6), "receipts": receipts,
                 "decisions": decisions, "agents": sorted(agents)}
        return True, f"SAĞLAM: {len(events)} olay, head={prev[:12]}…", audit
    except (KeyError, TypeError, ValueError) as e:
        return False, f"bundle-bozuk: {e}", {}


def verification_receipt(bundle: dict, audit: dict) -> dict:
    """Deterministik Tamga-makbuzu: 81'in kendi ledger'ına yazabileceği satır."""
    head = str(bundle["head"])
    merkle = str(bundle["merkle_root"])
    count = int(bundle["event_count"])
    receipt_id = hashlib.sha256(
        f"SAĞLAM|{head}|{merkle}|{count}".encode()).hexdigest()[:32]
    return {
        "type": "pugio_bundle_verification",
        "verifier": VERIFIER,
        "verdict": "SAĞLAM",
        "bundle_head": head,
        "merkle_root": merkle,
        "event_count": count,
        "audit": audit,
        "receipt_id": receipt_id,
    }


def _selftest() -> int:
    """Dahili temiz/bozuk koşu — K0 §1–3 üretimini de bağımsız doğrular."""
    import time as _t

    # mini-bundle üret (pür stdlib, K0 §1–3)
    events, prev = [], GENESIS
    for i, (et, amount) in enumerate([("charge_receipt", 0.05),
                                      ("permission_decision", 0.0),
                                      ("charge_receipt", 0.05)]):
        ev = {"seq": i + 1, "ts": _t.time(), "event_type": et,
              "agent_id": "ag-selftest", "host": "/weather",
              "amount": amount, "payload": f'{{"i":{i}}}', "prev_proof": prev}
        ev["proof"] = hashlib.sha256(_canonical(ev, prev).encode()).hexdigest()
        events.append(ev)
        prev = ev["proof"]
    bundle = {"pugio_bundle_version": BUNDLE_VERSION, "generated": _t.time(),
              "agent": "ag-selftest", "head": prev,
              "merkle_root": _merkle([e["proof"] for e in events]),
              "event_count": len(events), "events": events}

    ok, msg, audit = verify_bundle(bundle)
    print(f"temiz-bundle  : {msg} — audit={audit}")
    if not ok:
        print("RED: temiz-bundle doğrulanmadı (kendi üretimimiz!)")
        return 1
    receipt = verification_receipt(bundle, audit)
    expect_id = hashlib.sha256(
        f"SAĞLAM|{bundle['head']}|{bundle['merkle_root']}|{bundle['event_count']}".encode()
    ).hexdigest()[:32]
    if receipt["receipt_id"] != expect_id:
        print("RED: makbuz-bağı tutarsız")
        return 1

    # kazıma: 0.05 → 0.01 (inkâr-saldırısı)
    bundle["events"][0]["amount"] = 0.01
    ok2, msg2, _ = verify_bundle(bundle)
    print(f"kazınmış-bundle: {msg2}")
    if ok2:
        print("RED: kazıma yakalanmadı — fail-loud bozuk")
        return 1
    print("selftest SAĞLAM: temiz→SAĞLAM, kazınmış→RED, makbuz-bağı OK")
    return 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return _selftest()
    if len(argv) != 2:
        print(__doc__)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as f:
            bundle = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"RED: bundle okunamadı: {e}")
        return 1
    ok, msg, audit = verify_bundle(bundle)
    print(f"doğrulama     : {msg}")
    print("audit         : " + json.dumps(audit, sort_keys=True,
                                            separators=(",", ":"),
                                            ensure_ascii=False))
    if not ok:
        print("RED: K0 zinciri/köğü bozuk — makbuz ÜRETİLMEZ (fail-closed)")
        return 1
    receipt = verification_receipt(bundle, audit)
    print("makbuz        : " + json.dumps(receipt, sort_keys=True,
                                          separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
