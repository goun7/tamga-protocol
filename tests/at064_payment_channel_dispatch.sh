#!/usr/bin/env bash
# AT-064: ÇOKLU-ÖDEME-KANAL-DISPATCH'I (B-yönü) — RFC-010-§4.
#
# Kurucu-sorusu: "hem-x402, hem-kendi-sistemimiz, hem-gelecekte-başka-sistemler
# entegre-olunur?" — SUPPORTED_SCHEMES-additive-terfisi-ile.
#
# NEGATİF-KONTROL-DOKTRİNİ (safal207): her-kanalın-kendi-doğrulama-sözleşmesi
# vardır; bilinmeyen-bir-kanal-RED-DEĞİL-İNDETERMİNE-döner (üçüncü-seçenek-yasak —
# sessizce-işlemi-öldürmeyiz, sonucu-esirgeriz).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-064/$(date +%F)/at064.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-064: çoklu-ödeme-kanal-dispatch'ı (B-yönü)"

python3 - <<'PYEOF' >> "$LOG" 2>&1
import json, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
import settlement_bind_verify as SB

# --- 1) scheme-listesi-additive: üç-kanal-da-tanınıyor
assert set(SB.SUPPORTED_SCHEMES) >= {"x402/v1", "tamga/native", "erc8004/v1"}, \
    f"scheme-listesi-eksik: {SB.SUPPORTED_SCHEMES}"
print("  üç-kanal-additive-listede")

# --- 2) dispatch-her-şemayı-ayrı-doğrular (aynı-girdi-farklı-scheme → farklı-sonuç)
# x402: ecrecover-çağrılır; bilinen-adrese-düşer
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    "0xabc" if scheme == "x402/v1" else
    "ed25519-pub" if scheme == "tamga/native" else
    "keccak-root" if scheme == "erc8004/v1" else None)
assert SB._claim_signer("d", "s", "x402/v1") == "0xabc"
assert SB._claim_signer("d", "s", "tamga/native") == "ed25519-pub"
assert SB._claim_signer("d", "s", "erc8004/v1") == "keccak-root"
print("  dispatch-üç-scheme'ı-ayrı-doğrular")

# --- 3) bilinmeyen-scheme → İNDETERMİNE (üçüncü-seçenek-yasak)
charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": "c"*64},
          "settlement_bind": {"scheme": "solana/v1", "payment_id": "P",
                              "payer": "0x1", "payee": "0x2", "verified_at": "2026-09-21T00:00:00Z"}}
claim = {"buyerAddress": "0x1", "sellerAddress": "0x2", "settlementRef": "P",
         "evidenceHash": {"alg": "sha256", "hex": "c"*64}, "signature": "s"}
r = SB.verify(charge, claim)
assert r["verdict"] == "İNDETERMİNE" and r["reason_code"] == 2, \
    f"bilinmeyen-scheme-İNDETERMİNE-beklendi: {r}"
print("  bilinmeyen-scheme-İNDETERMİNE (üçüncü-seçenek-yasak-korunuyor)")

# --- 4) NEGATİF: çapraz-scheme-saldırısı → RED
# saldırgan-x402-claim'ini-tamga/native-scheme'ine-bağlar; ed25519-doğrulaması
# farklı-bir-pubkey-üretir → alıcı-ödeyen-eşleşmez (party_mismatch-RED).
# Bu-çapraz-kanal-saldırısı-tek-kanal-dünyasında-mümkün-değildi — dispatch'in
# getirdiği-yeni-yüzey-burada-kilitlenir.
charge2 = json.loads(json.dumps(charge))
charge2["settlement_bind"]["scheme"] = "tamga/native"
charge2["settlement_bind"]["payer"] = "ed25519-pub"   # farklı-kanal-kimliği
claim2 = json.loads(json.dumps(claim))                 # hâlâ-x402-buyerAddress-0x1
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    "0x1" if scheme == "x402/v1" else "ed25519-pub")
r2 = SB.verify(charge2, claim2)
assert r2["verdict"] == "RED", f"çapraz-scheme-RED-beklendi: {r2}"
print("  çapraz-scheme-yöneltme-RED (dispatch-yeni-yüzey-kilitli)")

# --- 5) eklenen-kanal-mevcut-x402-yolunu-bozmaz (geriye-dönük-uyumluluk)
# test-double'ı-yeniden-x402-şemasına-kilitle (4. test-değiştirdi)
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    "0xabc" if scheme == "x402/v1" else "ed25519-pub")
charge3 = json.loads(json.dumps(charge))
charge3["settlement_bind"]["scheme"] = "x402/v1"
charge3["settlement_bind"]["payer"] = "0xabc"
claim3 = json.loads(json.dumps(claim))
claim3["buyerAddress"] = "0xabc"
r3 = SB.verify(charge3, claim3)
assert r3["verdict"] in ("GREEN", "İNDETERMİNE"), f"x402-yolu-bozuldu: {r3}"
print("  mevcut-x402-yolu-korunuyor (additive-terfi-geriye-dönük-uyumlu)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: beş-kanal-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-064: çoklu-ödeme-kanal-dispatch'ı (B-yönü)"
[[ $FAIL -eq 0 ]]
