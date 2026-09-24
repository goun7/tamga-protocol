#!/usr/bin/env bash

# AT-186-BULGU-2: run_all-disinda-calistirmada-AT-162-korumasi-kirilmasin
export SYNTROPION_SECRET_KEY="${SYNTROPION_SECRET_KEY:-simnet-syntropion-test-key-32b}"

# AT-078: SYNTROPION → RFC-010-DİKİŞİ (C-sınıfı — 18-Syntropion).
#
# 18-Syntropion: syntropion_core/security.py — generate_fsek_clickwrap_hash
# (FSEK-5846-anlaşma-hash'i; sha256) + verify_fsek_clickwrap_hash
# (hmac.compare_digest-ile-sabit-zamanlı-doğrulama). syntropion_core/
# stake_gate.py — StakeGate.hold_stake_in_escrow ($10-Decimal-escrow).
#
# SYNTROPION-ÖZELLİĞİ: FSEK-clickwrap-hash'i-bir-ANLAŞMA-KANITIDIR —
# "bu-uzman-bu-şartları-kabul-etti"-der. RFC-010'ın-ödediği-işin-KİM-
# TARAFINDAN-istendiğini-kanıtlar (attribution-x402#2887'nin-"who"-yüzü).
# Stake-escrow-ise-FİNANSAL-TAAHHÜTTÜR (ciddiyet-filtresi).
#
# İKİ-KANAL-BİRLEŞİMİ (bu-testin-asıl-kanıtı): Syntropion'un-FSEK-hash'i
# evidenceHash-olarak-girer-VE-x402/v1-gerçek-ecrecover-imzası-claim'i-
# doğrular. Bu-x402/v1-scheme'inin-gerçek-yoldan-üçüncü-keç-koşmasıdır
# (AT-075-sonrası-stub-YOK-disiplini).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-078/$(date +%F)/at078.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-078: Syntropion-FSEK-escrow → RFC-010 x402/v1 dikişi"

SY="/home/gokun/projects/01_unicorn/18-Syntropion"
if [ ! -f "$SY/syntropion_core/security.py" ] || [ ! -f "$SY/syntropion_core/stake_gate.py" ]; then
  note "[SKIP] AT-078: Syntropion-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys/eth_utils-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-078: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SY" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from syntropion_core.security import (generate_fsek_clickwrap_hash,
                                      verify_fsek_clickwrap_hash)
import settlement_bind_verify as SB
import tamga_attest_verify as TAV

# --- 1) GERÇEK-FSEK-hash-üretimi (sha256, 64-hex)
EPOSTA = "uzman@syntropion.demo"
ZD = "2026-09-21T00:00:00+03:00"
fsek = generate_fsek_clickwrap_hash(EPOSTA, ZD)
assert isinstance(fsek, str) and len(fsek) == 64, f"FSEK-hash-64-hex-değil: {fsek!r}"
assert all(c in "0123456789abcdef" for c in fsek)
print(f"  Syntropion-FSEK-clickwrap-hash'i-üretildi: {fsek[:24]}… (sha256)")

# --- 2) Üretici-tarafı-sağlam: sabit-zamanlı-doğrulama (hmac.compare_digest)
assert verify_fsek_clickwrap_hash(fsek, EPOSTA, ZD) is True, "gerçek-hash-doğrulanmalı"
assert verify_fsek_clickwrap_hash("f"*64, EPOSTA, ZD) is False, "sahte-hash-False"
assert verify_fsek_clickwrap_hash(fsek, "baska@x.demo", ZD) is False, \
    "farklı-e-posta-False (taşınmaz-hash)"
assert verify_fsek_clickwrap_hash(fsek, EPOSTA, "2026-01-01T00:00:00+03:00") is False, \
    "farklı-zaman-False"
# e-posta-zamana-duyarlı: hash-in-farklı-parçalarını-içerdiği-için-
# herhangi-biri-değişince-tamamen-farklı-hash-üretir
fsek2 = generate_fsek_clickwrap_hash(EPOSTA, "2026-09-22T00:00:00+03:00")
assert fsek != fsek2, "zaman-değişince-hash-değişmeli (deterministik-ama-zamana-duyarlı)"
print("  verify_fsek: doğru-True; sahte/farklı-e-posta/farklı-zaman → False")

# --- 3) GERÇEK-x402/v1-imzası-ile-dikiş (stub-YOK — AT-075-disiplini)
# Kaynak-inceleme: _claim_signer-gerçek-ecrecover'ı-çağırıyor-mu
src = inspect.getsource(SB._claim_signer)
assert "ecrecover_to_pub" in src, "_claim_signer-gerçek-ecrecover'ı-çağırmıyor"
print("  STUB-YOK: _claim_signer-gerçek-ecrecover'ı-çağırır")

from eth_keys import keys
pk = keys.PrivateKey(bytes.fromhex("11"*32))
buyer_addr = pk.public_key.to_checksum_address().lower()
# RFC-010-§3b-x402/v1: imza-digest'ın-ham-baytları-üzerine (z=raw-sha256;
# EIP-191-öneksiz — AT-075'in-dersi)
PID = "SYN-STAKE-0001"
govde = {"buyerAddress": buyer_addr,
         "sellerAddress": "0x71c8a18174415cc92067749eb3544dffd3f87884",
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": fsek}}
digest = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
# RFC-010-§3b-x402/v1: imza-digest'ın-ham-baytları-üzerine (z=raw-sha256;
# EIP-191-öneksiz — AT-075'in-dersi). sign_msg-DEĞİL-sign_msg_hash: ilki
# personal_sign-ÖNEK'le-hash'ler ("\x19Ethereum Signed Message:\n32"), bizim
# gate-ise-ham-özüt-üzerinden-çözer (ecrecover_to_pub-ile-aynı-kural).
sig = pk.sign_msg_hash(bytes.fromhex(digest))
sig_hex = "0x" + sig.to_bytes().hex()
assert len(bytes.fromhex(sig_hex[2:])) == 65
claim = dict(govde); claim["signature"] = sig_hex

# ecrecover-gerçek-çalışıyor-mu (bağımsız-ölçüm)
coz = TAV.ecrecover_to_pub(digest, sig_hex)
assert coz is not None and coz.lower() == buyer_addr, \
    f"ecrecover-çözümü-yanlış: {coz} != {buyer_addr}"
print(f"  gerçek-ecrecover-imzası-üretildi+çözüldü: buyer={buyer_addr[:14]}…")

# --- 4) DİKİŞ: FSEK-hash'i-evidenceHash + gerçek-imza → GREEN
charge = {"seq": 11, "prev": "0"*64, "h": "b"*64,
          "delivery_hash": {"alg": "sha256", "hex": fsek},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": fsek},
                              "payer": buyer_addr,
                              "payee": "0x71c8a18174415cc92067749eb3544dffd3f87884",
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": fsek,
                                  "entries": 1, "verify_cmd": "syntropion.security"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Syntropion-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "imza-kontrolü-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  FSEK-hash'i + gerçek-x402/v1-imza → RFC-010-GREEN")

# --- 5) NEGATİF-1: sahte-imza-gerçek-ecrecover'da → RED rc4
claim2 = dict(govde); claim2["signature"] = "0x" + "11"*65
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 4, \
    f"sahte-imza-RED-rc4-beklendi: {r2}"
print("  sahte-imza-gerçek-ecrecover'da → RED rc4 (stub-olsaydı-GREEN-sanılırdı)")

# --- 6) NEGATİF-2: FSEK-hash'ine-tahriz → evidenceHash-swap-RED rc7
# FSEK-hash'ini-değiştiren-bir-saldırgan "anlaşmayı-çözüp-başkasını-koymuş"-
# olur; delivery_hash-ile-uyumsuzluk-fail-closed-tetikler
claim3 = json.loads(json.dumps(claim))
claim3["evidenceHash"]["hex"] = "9"*64
govde3 = {k: v for k, v in claim3.items() if k != "signature"}
d3 = hashlib.sha256(json.dumps(govde3, sort_keys=True).encode()).hexdigest()
claim3["signature"] = "0x" + pk.sign_msg_hash(bytes.fromhex(d3)).to_bytes().hex()
r3 = SB.verify(charge, claim3)
assert r3["verdict"] == "RED" and r3["reason_code"] == 7, \
    f"FSEK-tahrizi-RED-rc7-beklendi: {r3}"
print("  FSEK-hash'ine-tahriz (yeni-imzalı) → RED rc7 — anlaşma-kanıtı-taşınmaz")

# --- BONUS: escrow-Decimal-duyarlılık (stake_gate-$10)
from syntropion_core.stake_gate import StakeGate
from decimal import Decimal
assert StakeGate.DEFAULT_STAKE_USD == Decimal("10.00"), "varsayılan-stake-$10.00"
print("  StakeGate.DEFAULT_STAKE_USD=$10.00-Decimal-duyarlı (escrow-ciddiyet-filtresi)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Syntropion-FSEK-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-078: Syntropion-FSEK-escrow → RFC-010"
[[ $FAIL -eq 0 ]]
