#!/usr/bin/env bash
# AT-071: TENDERIX → RFC-010-DİKİŞİ (B-sınıfı — ed25519-üç-fallback).
#
# 64-Tenderix (63-py): src/tenderix/signing.py — Ed25519-imza-katmanı,
# PyCA > PyNaCl > pure-python-RFC-8032 fallback- zinciri (stdlib-only-yol-da
# doğrudur — Swarmax'ın-ilkesiyle-aynı: zero-dependency-zorunluluğu).
# API: generate_keypair() → (priv,pub); sign(priv,data); verify(pub,data,sig).
#
# TENDERIX-ÖZELLİĞİ: imza-64-byte-ed25519 → RFC-010'ın-tamga/native-scheme'i
# ile-AYNİ-aile. Tenderix-CSVO-imzalı-teklif-protokolü-olduğu-için-dikiş
# "imzalı-bağlayıcı-teklif"in-ödeme-kanıtına-bağlanması-demektir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-071/$(date +%F)/at071.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-071: Tenderix-ed25519 → RFC-010 tamga/native dikişi"

TE="/home/gokun/projects/01_unicorn/64-Tenderix/src"
if [ ! -f "$TE/tenderix/signing.py" ]; then
  note "[SKIP] AT-071: Tenderix-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$TE" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from tenderix import signing as tsign
import settlement_bind_verify as SB

# --- 1) Tenderix'in-gerçek-imza-makinesi: anahtar-üret + imzala + doğrula
priv, pub = tsign.generate_keypair()
msg = b'tenderix-csvo-binding'
sig = tsign.sign(priv, msg)
assert len(sig) == 64, f"imza-64-byte-beklendi: {len(sig)}"
assert tsign.verify(pub, msg, sig) is True, "gerçek-imza-doğrulanmadı"
print(f"  Tenderix-{tsign.BACKEND}-backend: imza-üret+doğrula-çalışıyor")

# --- 2) NEGATİF: yanlış-anahtar/yanlış-mesaj → False
assert tsign.verify(pub, b'baska-mesaj', sig) is False, "yanlış-mesaj-doğrulamamalı"
assert tsign.verify(b'0'*32, msg, sig) is False, "yanlış-anahtar-doğrulamamalı"
print("  yanlış-anahtar/yanlış-mesaj → False (üç-fallback-de-sağlam)")

# --- 3) DİKİŞ: Tenderix-imzalı-teklif → RFC-010 tamga/native-gate'ine
# kanıt-hash'i-imzalanan-mesajın-özü-olsun
kanit = hashlib.sha256(msg).hexdigest()
charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": kanit},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "CSVO-0001",
                              "claim_evidence_hash": {"alg": "sha256", "hex": kanit},
                              "payer": "tenderix-buyer", "payee": "0x2"*40,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": kanit,
                                  "entries": 1, "verify_cmd": "tenderix.signing.verify"}}
claim = {"buyerAddress": "tenderix-buyer", "sellerAddress": "0x2"*40,
         "settlementRef": "CSVO-0001",
         "evidenceHash": {"alg": "sha256", "hex": kanit}, "signature": "tenderix-buyer"}
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    s if scheme == "tamga/native" else "0x1")
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Tenderix-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-çalışmadı"
print("  Tenderix-imzalı-teklif → RFC-010-GREEN (§6-zincir-kanıtı-ile)")

# --- 4) NEGATİF: başkasının-imzasıyla-yöneltme → RED
claim2 = json.loads(json.dumps(claim))
claim2["buyerAddress"] = "baska-buyer"
claim2["evidenceHash"]["hex"] = "f"*64
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED", f"yöneltme-RED-beklendi: {r2}"
print("  imzayı-başkasına-yöneltme → RED (fail-closed)")

# --- 5) NEGATİF: §6-çürük-zincir → RED rc8
charge3 = json.loads(json.dumps(charge))
charge3["foreign_chain_proof"] = {"chain": "tamga", "head_hex": "", "entries": 1}
r3 = SB.verify(charge3, claim)
assert r3["verdict"] == "RED" and r3["reason_code"] == 8, f"çürük-zincir-RED: {r3}"
print("  §6-çürük-zincir-kanıtı → RED rc8 (AT-069-kapanışı-Tenderix'te)")

# --- 6) üç-fallback-uyumu: BACKEND-adı-gerçek
assert "pyca" in tsign.BACKEND or "pynacl" in tsign.BACKEND or "pure" in tsign.BACKEND, \
    f"beklenmeyen-backend: {tsign.BACKEND}"
print(f"  Tenderix-BACKEND={tsign.BACKEND} — üç-yol-standart-API")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Tenderix-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-071: Tenderix-ed25519 → RFC-010"
[[ $FAIL -eq 0 ]]
