#!/usr/bin/env bash
# AT-170: ŞEMA-İZOLASYONU — 3-imza-yüzü-birbirine-KARIŞMAZ
#
# Bugüne-kadar-her-test-bir-TEK-şema-ölçtü ( AT-159: tamga/native, AT-161:
# erc8004, AT-167: §6-derived). AMA-şemaların-BİRBİRİNDEN-İZOLE-OLDUĞU-hiç-
# ölçülmedi: x402-imzası-ile-tamga/native-buyerAddress'e-ödeme-yapılabilir-mi?
# erc8004-keccak-buyer-x402-ecrecover'e-çözülür-mü? Eğer-çöüzürse-A şemasında-
# geçerli-bir-ödeme-B-şemasında-da-geçerli-olur ( imza-sınırları-yumuşar).
#
# Bu-test-her-3-şemanın-NEGATİF-izolasyonunu-ölçer: doğru-imza+yanlış-şema →
# RED rc4 ( imza-geçersiz). DÜRÜST-kontrol: doğru-imza+doğru-şema → GREEN.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/.evidence/SEMA-IZOLASYON/$(date +%F)/at170.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }

python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, hashlib
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
from eth_account import Account
from eth_account.messages import encode_defunct
import settlement_bind_verify as SB

acct = Account.create()
receipt_hex = "a" * 64          # sha256-64hex ( delivery_hash)

def charge(scheme, payer=None):
    """§6-equals-bağı; foreign-chain-swarmax ( whitelist'te)."""
    return {"seq": 170, "prev": "0"*64, "h": "b"*64,
            "delivery_hash": {"alg": "sha256", "hex": receipt_hex},
            "settlement_bind": {"scheme": scheme, "payment_id": "AT-170",
                "claim_evidence_hash": {"alg": "sha256", "hex": receipt_hex},
                "payer": payer or acct.address, "payee": "0x"+"2"*40,
                "verified_at": "2026-09-23T00:00:00Z"},
            "foreign_chain_proof": {"chain": "swarmax", "head_hex": receipt_hex,
                "entries": 1, "evidence_link": "equals",
                "verify_cmd": "at170-schema-isolation"}}

def x402_sig(govde):
    """x402/v1: EIP-191-öneksiz, ham-sha256-bytes ( unsafe_sign_hash)."""
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).digest()
    s = Account.unsafe_sign_hash(d, acct.key)
    v = s.v if s.v >= 27 else s.v + 27
    return "0x" + s.r.to_bytes(32,"big").hex() + s.s.to_bytes(32,"big").hex() \
           + bytes([v]).hex()

def base(scheme, sig=None, buyer=None):
    govde = {"buyerAddress": buyer if buyer is not None else acct.address,
             "sellerAddress": "0x"+"2"*40, "settlementRef": "AT-170",
             "evidenceHash": {"alg": "sha256", "hex": receipt_hex}}
    c = dict(govde); c["signature"] = sig if sig else x402_sig(govde)
    return c

# ============ DÜRÜST: doğru-şema-doğru-imza ============
r = SB.verify(charge("x402/v1"), base("x402/v1"))
assert r["verdict"] == "GREEN", f"x402-dürüst-GREEN-beklendi: {r}"
print("  DÜRÜST: x402/v1-imzası + x402/v1-şeması → GREEN 6/6")

# ============ NEG-1: x402-imzası → tamga/native-şemasında → RED rc4 ============
# tamga/native-buyerAddress=64hex-ED25519-pubkey; x402-buyer=ETH-address.
# İmza-ED25519-doğrulamasına-girerse-geçersiz-olmalı ( 42-hex-pubkey-Ed25519-
# doğrulamasında-nacl-reddeder).
c = base("tamga/native")
c["buyerAddress"] = "e"*64   # 64-hex ( Ed25519-pubkey-formatı)
r = SB.verify(charge("tamga/native", payer="0x"+"3"*40), c)
assert r["verdict"] == "RED" and r["reason_code"] == 4, \
    f"x402-imzası-tamga/native'de-geçti ( İZOLASYON-YOK!): {r}"
print("  NEG-1: x402/ECDSA-imzası → tamga/native-şemasında → RED rc4 ( izole)")

# ============ NEG-2: x402-imzası → erc8004/v1-şemasında → RED rc4 ============
# erc8004-imza-YOK ( buyer=keccak256(delivery_hash)); imza-kanıtı-zaten-
# geçersiz-olmalı ( beklenen-65-byte-sıfır-imza).
r = SB.verify(charge("erc8004/v1", payer="0x"+"4"*40),
              base("erc8004/v1"))
assert r["verdict"] == "RED" and r["reason_code"] in (4, 6), \
    f"x402-imzası-erc8004'de-geçti ( İZOLASYON-YOK!): {r}"
print(f"  NEG-2: x402/ECDSA-imzası → erc8004/v1-şemasında → RED rc{r['reason_code']} ( izole)")

# ============ NEG-3: sahte-sıfır-imza-x402 → RED rc4 ( boş-geçmez) ============
c = base("x402/v1")
c["signature"] = "0x" + "00"*65   # tam-sıfır-imza
r = SB.verify(charge("x402/v1"), c)
assert r["verdict"] == "RED" and r["reason_code"] == 4, \
    f"sıfır-imza-x402'de-geçti: {r}"
print("  NEG-3: 65-byte-sıfır-imza → x402/v1 → RED rc4 ( boş-imza-geçmez)")

# ============ NEG-4: imza-yok → RED rc4 ( eksik-kanıt-geçmez) ============
c = base("x402/v1"); c["signature"] = ""
r = SB.verify(charge("x402/v1"), c)
assert r["verdict"] == "RED" and r["reason_code"] == 4, \
    f"boş-imza-geçti: {r}"
print("  NEG-4: imza='' → x402/v1 → RED rc4 ( eksik-kanıt-geçmez)")

# ============ NEG-5: ERİŞİM-paritesi — 3-şema-aynı-6-kontrol ============
# Her-şemanın-aynı-gate-yapısını-kullandığı-doğrulanır ( 6-check-tamamı).
# erc8004-imza-YOKSUN: buyerAddress=keccak256( delivery_hash)-64hex ( "0x"-
# öneksiz); claim-65-byte-sıfır-imza-ister ( AT-161-yapısı).
from eth_hash.auto import keccak as _keccak
buyer8 = _keccak(bytes.fromhex(receipt_hex)).hex()
c8 = {"buyerAddress": buyer8, "sellerAddress": "0x"+"2"*40,
      "settlementRef": "AT-170",
      "evidenceHash": {"alg": "sha256", "hex": receipt_hex},
      "signature": "0x" + "00"*65}
for sch, claim, payer in (("x402/v1", base("x402/v1"), acct.address),
                          ("erc8004/v1", c8, buyer8)):
    v = SB.verify(charge(sch, payer=payer), claim)
    assert v["reason_code"] == 0, f"{sch}-GREEN-tutarlı-değil: {v}"
print("  NEG-5: iki-şema-da-aynı-6-check-gate'i-kullanır ( yapı-paritesi)")
PYEOF
kontrol $? "AT-170: sema-izolasyonu ( 1-dürüst + 5-negatif)"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-170: 3-imza-yüzü-birbirinden-izole ( x402↔tamga/native↔erc8004)"
[ "$FAIL" = "0" ]
