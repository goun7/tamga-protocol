#!/usr/bin/env bash
# AT-072: VERIDROME → RFC-010-DİKİŞİ (B-sınıfı — RFC-6962-CT-log + Ed25519-otorite).
#
# 73-Veridrome (42-py): src/veridrome/core/crypto.py —
#   VeridromeAuthoritySigner (Ed25519-otorite-imzası)
#   MerkleTreeAuditLog (RFC-6962-yürütme-izi: add_leaf/get_root_hex/generate_proof)
#   generate_challenge_nonce (güvenli-nonce)
#
# VERIDROME-ÖZELLİĞİ: get_root_hex-'0x'+64hex-ÜRETİR — RFC-009'ın-R9-3-kanonik-
# biçiminin-TAM-AYNISI (x402-#3377-disiplini). Yani-Veridrome'un-kökü-hiçbir
# dönüştürme-olmadan-RFC-010-gate'ine-girer. Ayrıca-generate_proof-ÜYELİK-kanıtı
# üretir — saf-kök-İLE-deĞIL, üyelikle-doğrular (PQHaven'dan-daha-güçlü).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-072/$(date +%F)/at072.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-072: Veridrome-RFC-6962 → RFC-010 dikişi"

VE="/home/gokun/projects/01_unicorn/73-Veridrome/src"
if [ ! -f "$VE/veridrome/core/crypto.py" ]; then
  note "[SKIP] AT-072: Veridrome-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$VE" <<'PYEOF' >> "$LOG" 2>&1
import json, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from veridrome.core.crypto import VeridromeAuthoritySigner, MerkleTreeAuditLog
import settlement_bind_verify as SB

# --- 1) RFC-6962-ağacı-üret + 0x-kanonik-kök
mt = MerkleTreeAuditLog()
mt.add_leaf(b'eval:agent-7:pass')
mt.add_leaf(b'eval:agent-9:fail')
mt.add_leaf(b'anti-gaming:sybil-check:ok')
kok = mt.get_root_hex()
assert kok.startswith("0x") and len(kok) == 66, \
    f"R9-3-kanonik-0x+64-beklendi: {kok[:8]}…len={len(kok)}"
print(f"  Veridrome-RFC-6962-kökü: {kok[:18]}… (0x-kanonik — R9-3-aynı-biçim)")

# --- 2) üyelik-kanıtı-gerçekten-çalışıyor-mu
proof = mt.generate_proof(0)
assert isinstance(proof, list) and len(proof) >= 1, "üyelik-kanıtı-boş"
print(f"  üyelik-kanıtı-üretildi: {len(proof)}-seviye (saf-kökten-farklı)")

# --- 3) Ed25519-otorite-imzası
signer = VeridromeAuthoritySigner()
sig = signer.sign(b'test-claim')
assert len(sig) == 64, f"ed25519-imza-64-byte-beklendi: {len(sig)}"
print("  VeridromeAuthoritySigner: Ed25519-imza-çalışıyor")

# --- 4) DİKİŞ: RFC-6962-kökü → RFC-010-gate'ine (koku-0x-siz-64-hex'e-soy)
kok_hex = kok[2:]   # '0x'-önekini-soy (delivery_hash-64-hex-bekler)
charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": kok_hex},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "CERT-0001",
                              "claim_evidence_hash": {"alg": "sha256", "hex": kok_hex},
                              "payer": "veridrome-arena", "payee": "0x2"*40,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "swarmax", "head_hex": kok_hex,
                                  "entries": 3, "verify_cmd": "RFC-6962-verify"}}
claim = {"buyerAddress": "veridrome-arena", "sellerAddress": "0x2"*40,
         "settlementRef": "CERT-0001",
         "evidenceHash": {"alg": "sha256", "hex": kok_hex}, "signature": "veridrome-arena"}
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    s if scheme == "tamga/native" else "0x1")
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Veridrome-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-çalışmadı"
print("  Veridrome-RFC-6962-kökü → RFC-010-GREEN (§6-ile)")

# --- 5) NEGATİF: 0x'li-kökü-doğrudan-vermek → RED (R9-3-ihlali-tutarsızlık)
charge2 = json.loads(json.dumps(charge))
charge2["delivery_hash"]["hex"] = kok    # 66-karakter — 64-beklenir
r2 = SB.verify(charge2, claim)
assert r2["verdict"] == "RED" and r2["reason_code"] == 3, \
    f"0x'li-kök-RED-beklendi: {r2}"
print("  '0x'+66-karakter-kök → RED rc3 (R9-3-biçim-zorunluluğu-tutuyor)")

# --- 6) NEGATİF: üyelik-kanıtı-olmayan-sahte-yaprak → RED
claim3 = json.loads(json.dumps(claim))
claim3["evidenceHash"]["hex"] = "7"*64
r3 = SB.verify(charge, claim3)
assert r3["verdict"] == "RED" and r3["reason_code"] == 7, f"sahte-RED: {r3}"
print("  ağaç-dışı-sahte-yaprak → RED rc7")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Veridrome-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-072: Veridrome-RFC-6962 → RFC-010"
[[ $FAIL -eq 0 ]]
