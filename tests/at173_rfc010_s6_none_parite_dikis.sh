#!/usr/bin/env bash
# AT-173: RFC-010-§6.3-ÜÇ-MOD-PARİTESİ — none-modu-hiç-ölçülmedi
#
# §6.2'nin-3-modundan: equals ( AT-128/156), derived ( AT-167) ölçüldü — AMA
# **none**-modu-hiç-ölçülmedi. §6.3: "none / yok: head-receiptHash'e-BAĞLI-
# DEĞİL ( farklı-zincirlerin-farklı-kökleri-olabilir); AMA-BOŞ-head-yine-RED."
#
# Bu-test-o-sözleşmenin-gerçekleştiğini-ölçer + 3-modun-birlikte-paritesi:
# 1) none-keyfi-head → GREEN ( RFC-sözleşmesi; farklı-kökler-geçer)
# 2) none-BOŞ-head → RED rc8 ( boş-kök-sahte-zincir-işaretidir)
# 3) equals-sözleşmesi-uygulanır ( head=receipt; aksi-RED)
# 4) derived-sözleşmesi-uygulanır ( head=sha256( receipt); aksi-RED)
# 5) MOD-LAR-BİRBİRİNİ-TUTARLI-şekilde-ayırt-eder ( aynı-head-3-modda-3-sonuç)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/.evidence/RFC010-S6-NONE/$(date +%F)/at173.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }

python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, hashlib
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
from eth_account import Account
import settlement_bind_verify as SB

acct = Account.create()
receipt = "a" * 64
derived = hashlib.sha256(bytes.fromhex(receipt)).hexdigest()

def make(link, head):
    return {"seq": 173, "prev": "0"*64, "h": "b"*64,
            "delivery_hash": {"alg": "sha256", "hex": receipt},
            "settlement_bind": {"scheme": "x402/v1", "payment_id": "AT-173",
                "claim_evidence_hash": {"alg": "sha256", "hex": receipt},
                "payer": acct.address, "payee": "0x"+"2"*40,
                "verified_at": "2026-09-23T00:00:00Z"},
            "foreign_chain_proof": {"chain": "swarmax", "head_hex": head,
                "entries": 1, "evidence_link": link,
                "verify_cmd": "at173-none-parity"}}

govde = {"buyerAddress": acct.address, "sellerAddress": "0x"+"2"*40,
         "settlementRef": "AT-173", "evidenceHash": {"alg": "sha256", "hex": receipt}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
_s = Account.unsafe_sign_hash(bytes.fromhex(d), acct.key)
_v = _s.v if _s.v >= 27 else _s.v + 27
sig = "0x" + _s.r.to_bytes(32,"big").hex() + _s.s.to_bytes(32,"big").hex() \
      + bytes([_v]).hex()
claim = dict(govde); claim["signature"] = sig

def verdict(link, head):
    return SB.verify(make(link, head), claim)

# --- 1) none-modu-keyfi-head → GREEN ( RFC-§6.3-sözleşmesi-GERÇEK)
r = verdict("none", "c"*64)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"none-keyfi-head-GREEN-beklendi ( §6.3): {r}"
print("  1) none + keyfi-head → GREEN ( RFC-sözleşmesi: farklı-zincirler-farklı-"
      "kökler-taşıyabilir; head-receipt'e-bağlı-değil)")

# --- 2) none-modu-BOŞ-head → RED rc8 ( §6.3'ün-tek-kısıtı)
r = verdict("none", "")
assert r["verdict"] == "RED" and r["reason_code"] == 8, \
    f"none-boş-head-RED-beklendi ( §6.3): {r}"
print("  2) none + BOŞ-head → RED rc8 ( boş-kök-sahte-zincir-işaretidir — "
      "none-bağsızlık-boşluğu-açmaz)")

# --- 3) equals-modu-sözleşmesini-uygular
r_eq_ok = verdict("equals", receipt)         # head=receipt → GREEN
r_eq_bad = verdict("equals", "d"*64)         # head≠receipt → RED
assert r_eq_ok["reason_code"] == 0 and r_eq_bad["reason_code"] == 8, \
    f"equals-sözleşmesi-bozuk: {r_eq_ok} / {r_eq_bad}"
print("  3) equals + head=receipt → GREEN; equals + head≠receipt → RED rc8 "
      "( sözleşme-uygulanır)")

# --- 4) derived-modu-sözleşmesini-uygular
r_de_ok = verdict("derived", derived)
r_de_bad = verdict("derived", receipt)       # derived-değil → RED
assert r_de_ok["reason_code"] == 0 and r_de_bad["reason_code"] == 8, \
    f"derived-sözleşmesi-bozuk: {r_de_ok} / {r_de_bad}"
print("  4) derived + head=sha256( receipt) → GREEN; derived + receipt-kendisi "
      "→ RED rc8 ( türetme-gerçek)")

# --- 5) MOD-PARİTESİ: aynı-head-3-modda-3-farklı-sonuç ( modlar-ayrı-davranır)
same_head = receipt
v_none = verdict("none", same_head)["reason_code"]
v_eq = verdict("equals", same_head)["reason_code"]
v_de = verdict("derived", same_head)["reason_code"]
print(f"  5) MOD-PARİTESİ: head={same_head[:8]}… → none=rc{v_none}, "
      f"equals=rc{v_eq}, derived=rc{v_de}")
# receipt-hem-none-hem-equals-için-geçerli-AMA-derived-değil ( sha256(receipt)≠
# receipt) — 3-mod-aynı-head'i-farklı-değerlendirir ( gerçek-mod-ayrımı)
assert v_none == 0 and v_eq == 0 and v_de == 8, \
    f"3-mod-ayrımı-bozuk: {v_none}/{v_eq}/{v_de}"
print("     → 3-mod-aynı-head'i-farklı-değerlendirir: none/equals-geçerli, "
      "derived-reddeder ( modlar-BAĞIMSIZ-davranır)")
PYEOF
kontrol $? "AT-173: RFC010-§6.3-none-parite ( 5-kanıt)"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-173: §6.3-none-modu + 3-mod-paritesi ( equals/derived/none)"
[ "$FAIL" = "0" ]
