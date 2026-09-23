#!/usr/bin/env bash
# AT-167: RFC-010-§6.2-derived-link-KRIPTOGRAFİK-TÜRETME-DENETİMİ
#
# §6-whitelist-tamamlandı-AMA-evidence_link'in-3-modundan-sadece-'equals'
# test-edildi. AT-156'da-derived'in-keccak-Merkle-için-uyumsuz-olduğunu-
# bulduk; AMA-derived-KENDİSİ-hiç-ölçülmedi. RFC-010-§6.2:
#   derived: head_hex == sha256( bytes.fromhex( receipt_hash))
# Bu-test-o-türetmeyi-gerçek-olarak-ölçer + negatifleri.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/.evidence/RFC010-S6-DERIVED/$(date +%F)/at167.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }

python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, hashlib
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
from eth_account import Account
import settlement_bind_verify as SB

# §6.2-derived-türetme ( üretim-formülü): head = sha256( receipt-bytes)
receipt_hex = "c" * 64
derived_head = hashlib.sha256(bytes.fromhex(receipt_hex)).hexdigest()
assert len(derived_head) == 64, "türetilmiş-head-64hex-değil"
# türetme-tek-yönlü: receipt→head, head→receipt-GERİ-ALINAMAZ
assert derived_head != receipt_hex, "türetme-aynı-kaldı ( özet-değil)"
print(f"  §6.2-derived-formülü: sha256( bytes.fromhex( receipt)) = {derived_head[:20]}…")

acct = Account.create()
sig_hex = "0x" + "00"*65   # imza-2'de-gerçek-ECDSA-yapıyoruz

def make_charge(link, head):
    return {"seq": 167, "prev": "0"*64, "h": "a"*64,
            "delivery_hash": {"alg": "sha256", "hex": receipt_hex},
            "settlement_bind": {"scheme": "x402/v1", "payment_id": "AT-167",
                "claim_evidence_hash": {"alg": "sha256", "hex": receipt_hex},
                "payer": acct.address, "payee": "0x"+"2"*40,
                "verified_at": "2026-09-23T00:00:00Z"},
            "foreign_chain_proof": {"chain": "swarmax", "head_hex": head,
                "entries": 1, "evidence_link": link,
                "verify_cmd": "at167-derived-test"}}

def sign(govde):
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
    _s = Account.unsafe_sign_hash(bytes.fromhex(d), acct.key)
    _v = _s.v if _s.v >= 27 else _s.v + 27
    return "0x" + _s.r.to_bytes(32,"big").hex() + _s.s.to_bytes(32,"big").hex() \
           + bytes([_v]).hex()

govde = {"buyerAddress": acct.address, "sellerAddress": "0x"+"2"*40,
         "settlementRef": "AT-167", "evidenceHash": {"alg": "sha256", "hex": receipt_hex}}
claim = dict(govde); claim["signature"] = sign(govde)

# --- 1) derived-DOĞRU-türetilmiş-head → GREEN
r1 = SB.verify(make_charge("derived", derived_head), claim)
assert r1["verdict"] == "GREEN", f"derived-gerçek-bağ-GREEN-beklendi: {r1}"
assert r1["checks"]["6_foreign_chain"] is True, "6_foreign_chain-geçmedi"
print("  1) derived-link-DOĞRU-türev ( sha256( receipt)) → GREEN 6/6")

# --- 2) derived-YANLIŞ-türev → RED rc8 ( türetme-gerçek-doğrulanıyor)
r2 = SB.verify(make_charge("derived", "e"*64), claim)
assert r2["verdict"] == "RED" and r2["reason_code"] == 8, \
    f"derived-yanlış-türev-RED-beklendi: {r2}"
print("  2) derived-link-YANLIŞ-türev ( sha256-değil) → RED rc8 ( türetme-gerçek)")

# --- 3) derived-vs-equals-KARŞT: equals-head-derived-değil → rc8
# ( türetme-bağı-formülüne-uymalı; equals-head'i-derived-yerine-konamaz)
r3 = SB.verify(make_charge("derived", receipt_hex), claim)
assert r3["verdict"] == "RED" and r3["reason_code"] == 8, \
    f"derived-bağı-equals-head'i-reddetmeli: {r3}"
print("  3) derived-link-receipt-kendisini-reddeder ( sha256(receipt)≠receipt) → rc8")

# --- 4) equals-vs-derived-KARŞT: equals-BAĞINDA-derived-head → rc8
r4 = SB.verify(make_charge("equals", derived_head), claim)
assert r4["verdict"] == "RED" and r4["reason_code"] == 8, \
    f"equals-bağı-derived-head'i-reddetmeli: {r4}"
print("  4) equals-link-derived-head'i-reddeder ( head≠receipt) → rc8")

# --- 5) link-alanı-YOK ( none) → eski-davranış: herhangi-64hex-geçer
r5 = SB.verify(make_charge(None, "d"*64), claim)
assert r5["verdict"] == "GREEN", f"link-yok-GREEN-beklendi ( §6.2 geri-uyum): {r5}"
print("  5) evidence_link-alanı-YOK → GREEN ( §6.2-geri-uyum; head-receipt'e-bağlı-değil)")
PYEOF
kontrol $? "RFC-010-§6.2-derived-türetme-denetimi"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-167: §6.2-derived-link-kriptografik-türetme ( 5-kanıt + 4-negatif)"
[ "$FAIL" = "0" ]
