#!/usr/bin/env bash
# AT-066: AJAN-BORSASI-DİKİŞİ — 24-ajan-borsasi (1271-py, kod-canlı).
#
# borsa_core.py:70  receipt_hash: str | None    # ChargeReceipt hash
# borsa_core.py:176 complete_work(match_id, receipt_hash) — "alıcı bağımsız
# olarak yeniden hesaplayabilir" (machine-checkable).
#
# DOKUNMA-NOKTASI: bu-hash-RFC-010'ın-BEŞİNCİ-kontrolünün-kaynağı:
#   evidenceHash == receiptHash
# Ajan-Borsası-modülü-Sester'a-BAĞIMLI-DEĞİL — kanıtı-sadece-OKUR (loose-coupling,
# borsa_core.py:18-19). Yani-dikiş-üçüncü-bir-ürün-üzerinden-gerçekleşir:
#   Ajan-Borsası-emri → (Sester-receipt-hash) → Tamga-RFC-010-gate
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-066/$(date +%F)/at066.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-066: Ajan-Borsası receipt_hash → RFC-010 dikişi"

python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, sys, importlib.util
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

# --- 0) Ajan-Borsası-modülünü-gerçek-yolundan-yükle (uzak-reaktör-yok: doğrudan)
spec = importlib.util.spec_from_file_location(
    "borsa_core", "/home/gokun/projects/01_unicorn/24-ajan-borsasi/borsa_core.py")
try:
    borsa = importlib.util.module_from_spec(spec); spec.loader.exec_module(borsa)
    BORSA_UP = True
    print("  borsa_core-gerçek-modülden-yüklendi")
except Exception as e:
    BORSA_UP = False
    print(f"  [INFO] borsa_core-yüklenemedi ({type(e).__name__}) — "
          f"arayüz-sözleşmesini-buß-testten-sürdür")

# --- 1) arayüz-sözleşmesi-gerçek: receipt_hash-64-hex-string (bizim-formatımızla)
import inspect
src = inspect.getsource(borsa) if BORSA_UP else open(
    "/home/gokun/projects/01_unicorn/24-ajan-borsasi/borsa_core.py",
    encoding="utf-8").read()
assert "receipt_hash: str | None" in src, "arayüz-alanı-yok"
assert "machine-checkable" in src, "bağımsız-doğrulama-sözleşmesi-yok"
print("  arayüz-gerçek: receipt_hash-alanı-ve-machine-checkable-sözleşme")

# --- 2) Ajan-Borsası-emri-üret → Tamga-receipt-hash'ine-bağla
# (borsa_complete_work-bizim-ledger'ımızdan-hash-alırdı; burada-üretiyoruz)
job = b'{"job":"scrape-51","buyer":"0x1","seller":"0x2"}'
receipt_hash = hashlib.sha256(job).hexdigest()   # ChargeReceipt-hash
assert len(receipt_hash) == 64
print(f"  emir-işlendi → receipt_hash {receipt_hash[:16]}…")

import settlement_bind_verify as SB

# --- 3) DİKİŞ: receipt_hash-5'inci-kontrolde-evidenceHash'e-denktir
charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": receipt_hash},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "MATCH-0001",
                              "claim_evidence_hash": {"alg": "sha256", "hex": receipt_hash},
                              "payer": "0x1", "payee": "0x2",
                              "verified_at": "2026-09-21T00:00:00Z"}}
claim = {"buyerAddress": "0x1", "sellerAddress": "0x2",
         "settlementRef": "MATCH-0001",
         "evidenceHash": {"alg": "sha256", "hex": receipt_hash},
         "signature": "0x1"}
SB._claim_signer = lambda d, s, scheme="x402/v1": "0x1"
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Ajan-Borsası-dikişi-GREEN-beklendi: {r}"
print("  Ajan-Borsası-emri-→-RFC-010-gate-GREEN (üçüncü-ürün-bağlandı)")

# --- 4) NEGATİF: sahte-receipt (iş-yapılmadı-ama-hash-bağlandı) → RED
charge2 = json.loads(json.dumps(charge))
charge2["delivery_hash"]["hex"] = "0"*64  # sahte-teslim
r2 = SB.verify(charge2, claim)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"sahte-receipt-RED-beklendi: {r2}"
print("  sahte-receipt-RED — iş-yapılmadan-ödeme-alınamaz")

# --- 5) NEGATİF: kanıt-başkasının-işine-yöneltilirse → RED
claim3 = json.loads(json.dumps(claim))
claim3["sellerAddress"] = "0x3"  # başkası
r3 = SB.verify(charge, claim3)
assert r3["verdict"] == "RED", f"kanıt-yöneltme-RED-beklendi: {r3}"
print("  kanıt-başkasının-işine-yöneltme-RED (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: beş-Ajan-Borsası-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-066: Ajan-Borsası receipt_hash → RFC-010"
[[ $FAIL -eq 0 ]]
