#!/usr/bin/env bash
# AT-069: §6-BORCUNU-KAPANIŞI — yabancı-zincir-sorgulaması.
#
# AT-067-§6-itirafı: "gate-kendisi-yabancı-zinciri-sorgulamaz — Swarmax-zinciri
# kırık-olsa-dahi-GREEN-geçiyordu." Bu-test-o-açığı-kapattığını-kanıtlar:
# foreign_chain_proof-verildiyse-ve-çürüksе-RED; verilmediyse-GERİ-UYUMLU-GREEN
# (eski-dikişler-kırılmaz — üçüncü-seçenek-yasak'a-uygun).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-069/$(date +%F)/at069.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-069: §6-borcu-kapanışı (yabancı-zincir-sorgulaması)"

python3 - <<'PYEOF' >> "$LOG" 2>&1
import json, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
import settlement_bind_verify as SB

# --- ortak-şekiller
def base_charge(fcp=None):
    c = {"seq": 1, "prev": "0"*64, "h": "a"*64,
         "delivery_hash": {"alg": "sha256", "hex": "c"*64},
         "settlement_bind": {"scheme": "tamga/native", "payment_id": "P1",
                             "claim_evidence_hash": {"alg": "sha256", "hex": "c"*64},
                             "payer": "agent-7", "payee": "0x2"*40,
                             "verified_at": "2026-09-21T00:00:00Z"}}
    if fcp is not None:
        c["foreign_chain_proof"] = fcp
    return c
claim = {"buyerAddress": "agent-7", "sellerAddress": "0x2"*40,
         "settlementRef": "P1",
         "evidenceHash": {"alg": "sha256", "hex": "c"*64}, "signature": "agent-7"}
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    s if scheme == "tamga/native" else "0x1")

# --- 1) GERİ-UYUMLULUK: kanıt-yok → GREEN (eski-dikişler-kırılmaz)
r = SB.verify(base_charge(None), claim)
assert r["verdict"] == "GREEN", f"kanıt-yok-GREEN-beklendi: {r}"
assert "6_foreign_chain" not in r["checks"], "kanıt-yokken-6-çalışmamalı"
print("  kanıt-yok → GREEN (geri-uyumlu; eski-dikişler-korunur)")

# --- 2) GEÇERLİ-kanıt → GREEN
okp = {"chain": "swarmax", "head_hex": "d"*64, "entries": 3, "verify_cmd": "n/a"}
r2 = SB.verify(base_charge(okp), claim)
assert r2["verdict"] == "GREEN" and r2["checks"].get("6_foreign_chain") is True, \
    f"geçerli-kanıt-GREEN-beklendi: {r2}"
print("  geçerli-foreign_chain_proof → GREEN (6.kontrol-doğru)")

# --- 3) NEGATİF: kırık-zincir-kanıtı → RED (§6-açığı-kapandı)
bad = {"chain": "swarmax", "head_hex": "", "entries": 3}
r3 = SB.verify(base_charge(bad), claim)
assert r3["verdict"] == "RED" and r3["reason_code"] == 8, \
    f"kırık-zincir-RED-beklendi: {r3}"
print("  kırık-zincir-kanıtı → RED rc8 (§6-itirafı-kapatıldı)")

# --- 4) NEGATİF: entries-sıfır → RED (boş-zincir-sahte-işaretidir)
bad2 = {"chain": "swarmax", "head_hex": "d"*64, "entries": 0}
r4 = SB.verify(base_charge(bad2), claim)
assert r4["verdict"] == "RED", f"boş-zincir-RED-beklendi: {r4}"
print("  entries=0 → RED (boş-zincir-sahte)")

# --- 5) NEGATİF: bilinmeyen-zincir-adı → RED
bad3 = {"chain": "bilinmeyen", "head_hex": "d"*64, "entries": 1}
r5 = SB.verify(base_charge(bad3), claim)
assert r5["verdict"] == "RED", f"bilinmeyen-zincir-RED-beklendi: {r5}"
print("  bilinmeyen-zincir-adı → RED (additive-liste)")

# --- 6) üçüncü-seçenek-yasak: kanıt-eksikliği-RED-değil
# (1-no-kanıt-GREEN-ile-aynı-ilke) — kanıt-verilmemişse-sonuç-esirgenmez
r6 = SB.verify(base_charge(None), claim)
assert r6["verdict"] != "İNDETERMİNE", f"eksiklik-İNDETERMİNE-olmamalı: {r6}"
print("  kanıt-eksikliği-İnDETERMİNE-değil — üçüncü-seçenek-yasak-korunuyor")

# --- 7) Swarmax-gerçek-zinciri-ile-çapraz (kod-yolu-açıksa)
try:
    import sqlite3, os
    SW = "/home/gokun/projects/01_unicorn/69-Swarmax/src/swarmax"
    if os.path.isfile(os.path.join(SW, "evidence.py")):
        sys.path.insert(0, SW)
        import evidence as sw_ev
        db = sqlite3.connect(":memory:"); db.row_factory = sqlite3.Row
        db.execute("CREATE TABLE evidence_ledger (seq INTEGER PRIMARY KEY, "
                   "event_type TEXT, payload_hash TEXT, prev_hash TEXT)")
        db.execute("INSERT INTO evidence_ledger VALUES (1,'t',?,?)",
                   (sw_ev.payload_digest({"j":1}), sw_ev.GENESIS)); db.commit()
        ok, n = sw_ev.verify_chain(db)
        r7 = SB.verify(base_charge(
            {"chain": "swarmax", "head_hex": sw_ev.payload_digest({"j":1}),
             "entries": n}), claim)
        assert ok and r7["verdict"] == "GREEN"
        print("  Swarmax-gerçek-zinciri-ile-çapraz-GREEN")
    else:
        print("  [INFO] Swarmax-yok — çapraz-adım-atlandı (CI-skip)")
except ImportError:
    print("  [INFO] Swarmax-modülü-yok — çapraz-adım-atlandı")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-§6-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-069: §6-borcu-kapanışı"
[[ $FAIL -eq 0 ]]
