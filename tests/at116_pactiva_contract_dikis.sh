#!/usr/bin/env bash
# AT-116: PACTIVA BEŞİNCİ-YÜZ — tripartite-contract → RFC-010 (x402/v1).
#
# task-32. Pactiva'nın-dört-yüzü-bağlandı (AT-079-audit-ledger, AT-084/087-
# arbitration, AT-094-peer-attestation). Kalan-kripto-yüz:
#   pactiva_core/contracts.py — Yasal-Üçlü-Sözleşme-Motoru:
#     - generate_tripartite_contract: 6-kanonik-madde (4857/4904/GVK-94/KVKK)
#       → contract_sha256_hash = sha256(canonical-clauses)
#     - verify_contract_integrity: imza-sonrası-tahriratı-doğrular
#
# DİKİŞ-kanalı: x402/v1 (gerçek-EIP-191-ham-digest; erc8004/v1-YOK — onun
# keccak256(digest)-çıktısı sha256-buyer'la-doğal-uyuşmaz, double-ister).
# Contract-hash → hem-delivery_hash hem-evidenceHash hem-§6-head'i
# (evidence_link=equals: sözleşme-içerikten-ödeme-kanalına-bağlı).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/PACTIVA-5"
LOG="$EVDIR/$(date +%F)/at116.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

PA=/home/gokun/projects/01_unicorn/22-37-Pactiva
if [ ! -f "$PA/pactiva_core/contracts.py" ]; then
  note "[SKIP] AT-116: Pactiva-contracts-kodu-bu-makinede-değil (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
for mod in eth_keys; do
  if ! python3 -c "import $mod" 2>/dev/null; then
    note "[SKIP] AT-116: $mod-yok (İNDETERMİNE)."
    echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
    exit 0
  fi
done

# Gerçek-EIP-191-üretimi-için-sandbox-anahtarı (UNPUMP-BRIDGE-ile-aynı-disiplin)
SK_HEX="${UNPUMP_BIND_SK:-0x110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857}"

python3 - "$PA" "$SK_HEX" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, sys
sys.path.insert(0, sys.argv[1])                 # 22-37-Pactiva
sys.path.insert(0, "."); sys.path.insert(0, "tools")

from decimal import Decimal
from eth_keys import keys
from pactiva_core.contracts import (
    generate_tripartite_contract, verify_contract_integrity)
import settlement_bind_verify as SB

SK = keys.PrivateKey(bytes.fromhex(sys.argv[2][2:] if sys.argv[2].startswith("0x")
                                   else sys.argv[2]))
BUYER = SK.public_key.to_checksum_address().lower()
PAYEE = "0x" + "2" * 40

def imzala(claim):
    govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                       sort_keys=True)
    _d = hashlib.sha256(govde.encode()).hexdigest()
    return SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()

def kanal(ch, pid="PACT-CONTRACT-1"):
    """Contract-hash → RFC-010 x402/v1 dikişi."""
    claim = {"buyerAddress": BUYER, "sellerAddress": PAYEE,
             "settlementRef": pid, "evidenceHash": {"alg": "sha256", "hex": ch},
             "signature": "_"}
    claim["signature"] = imzala(claim)
    charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
              "delivery_hash": {"alg": "sha256", "hex": ch},
              "settlement_bind": {"scheme": "x402/v1", "payment_id": pid,
                                  "claim_evidence_hash": {"alg": "sha256",
                                                          "hex": ch},
                                  "payer": BUYER, "payee": PAYEE,
                                  "verified_at": "2026-09-22T00:00:00Z"},
              "foreign_chain_proof": {
                  "chain": "tamga", "head_hex": ch, "entries": 1,
                  "evidence_link": "equals",
                  "verify_cmd": "pactiva.contracts.verify_contract_integrity"}}
    return charge, claim

# --- 1) gerçek-üçlü-sözleşme-üretimi: 6-kanonik-madde + sha256
c = generate_tripartite_contract(employer_id="EMP-1", worker_id="W-1",
                                 job_id="JOB-1", job_title="Tesis Bakım",
                                 base_hourly_rate=Decimal("500.00"),
                                 expected_hours=Decimal("8"), category="Teknik")
ch = c["contract_sha256_hash"]
clauses = c["canonical_clauses"]
assert len(clauses) == 6 and len(ch) == 64
assert all(k in c["statutory_compliance"] for k in
           ("is_4857_isolated", "is_4904_zero_commission_worker",
            "is_gvk_94_tax_handled", "is_kvkk_6_compliant"))
print("  generate_tripartite_contract: 6-kanonik-madde (4857/4904/GVK/KVKK)"
      " → sha256-hash üretildi")

# --- 2) verify_contract_integrity: doğru-metin → True
assert verify_contract_integrity(clauses, ch) is True
# MADDE-3-bütçe-kilidi: 500×8 = 4000.00
assert c["estimated_total_payout"] == Decimal("4000.00")
print(f"  verify_contract_integrity: True | bütçe-kilidi 500×8="
      f"{c['estimated_total_payout']} TL (MADDE-3)")

# --- 3) kanonik-hash-jcs-ailesi: sha256(clause-metni)
beklenen = hashlib.sha256("\n\n".join(clauses).encode("utf-8")).hexdigest()
assert beklenen == ch, "kanonik-hash-bağımsız-hesaplamayla-aynı-değil"
print("  kanonik-hash bağımsız-doğrulandı (sha256 — tamga-jcs-ailesi)")

# --- 4) DİKİŞ: x402/v1 GREEN (gerçek-EIP-191, double-YOK)
charge, claim = kanal(ch)
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"contract-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["2_claim_sig"] is True   # gerçek-ecrecover
print("  DİKİŞ: contract-hash → x402/v1 GREEN rc0 (gerçek-EIP-191,"
      " imza-modülün-kendisi, double-YOK)")

# --- 5) §6-foreign_chain: head=contract-hash, evidence_link=equals
assert r["checks"]["6_foreign_chain"] is True
# içerik-bağı: head-zaten-delivery_hash'e-eşit (sözleşme↔ödeme)
assert charge["foreign_chain_proof"]["head_hex"] == \
    charge["delivery_hash"]["hex"] == claim["evidenceHash"]["hex"]
print("  §6-foreign_chain: head=contract-hash, evidence_link=equals →"
      " sözleşme-içerikten-ödeme-kanalına-bağlı")

# --- 6) NEG-1: sözleşme-tahriratı → verify-False + delivery-swap-rc7
bozuk = list(clauses)
bozuk[2] = bozuk[2].replace("emanet", "SAHTE-EKLENDI")
assert verify_contract_integrity(bozuk, ch) is False, "tahrir-tespit-edilmeli"
# RFC-010-tarafı: delivery-hash-değişirse-evidenceHash-uyumsuz → rc7
c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-1 clause-tahriratı: verify-False + RFC-010 RED rc7"
      " (evidenceHash-uyumsuz — imzalı-sözleşme-değiştirilemez)")

# --- 7) NEG-2: payer-swap → rc6 (üçlü-taraflar-bozulursa)
c6 = json.loads(json.dumps(charge))
c6["settlement_bind"]["payer"] = "0x" + "9" * 40
r6 = SB.verify(c6, claim)
assert r6["verdict"] == "RED" and r6["reason_code"] == 6, \
    f"rc6-beklendi: {r6}"
print("  NEG-2 payer-swap: RED rc6 (party-mismatch — üçlü-sözleşme"
      " tarafları ödeme-kanalına-sabitlenmiş)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: yedi-Pactiva-contract-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-116: Pactiva tripartite-contract → RFC-010 (x402/v1)"
[[ $FAIL -eq 0 ]]
