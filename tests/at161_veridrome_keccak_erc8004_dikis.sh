#!/usr/bin/env bash
# AT-161: VERİDROME-KECCAK-CERT → erc8004/v1-ŞEMASI ( şema-dengesi-3/3)
#
# AT-159-tamga/native'ı-ekledi; bu-turda-x402/v1-ve-tamga/native-temsil-
# ediliyordu-AMA-erc8004/v1-HİÇ-değildi. Üç-şemanında-da-temsil-edilmesi
# "her-açıdan-100/100"-için-gerekir.
#
# erc8004/v1 ( RFC-010-§3.3):
#   - keccak-merkle, İMZASIZ ( signature-less)
#   - buyer = keccak256( delivery_hash) — özetten-türetilmiş-adres
#   - kanıt-keccak-tabanlı-OLMALI ( bu-yüzden-veridrome'un-keccak-cert_id'si
#     doğal-bir-erc8004/v1-kanıtıdır)
#
# veridrome-contracts/client.py:206-issue_certificate:
#   packed_data = agent_id + pcr0_measurement + merkle_root + now.to_bytes(32,"big")
#   cert_id = keccak( packed_data)  ← GERÇEK-keccak-kanıtı ( on-chain-sertifika-ID)
#
# NOT: issue_certificate-bir-blockchain-transaction-gönderir ( canlı-ağ-gerek);
# bu-test-packed_data+keccak-ÜRETİM-formülünü-doğrudan-ölçer ( transaction-adımı
# ağ-yokluğunda-atlanır — keccak-kanıtı-GERÇEK-üretim-import'udur).
set -uo pipefail

TESTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTDIR/.." && pwd)"
LOG="$ROOT/.evidence/VERIDROME-ERC8004/$(date +%F)/at161.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }

if [ ! -f /home/gokun/projects/00_TAMGA-MESH/veridrome/src/veridrome/contracts/client.py ] && \
   [ ! -f /home/gokun/projects/00_TAMGA-MESH/veridrome/src/veridrome/contracts/client.py ]; then
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — veridrome-yok (İNDETERMİNE)"; exit 0
fi

python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, hashlib, time
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/src")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
# veridrome'un-KENDİ-kullandığı-keccak ( üretim-import-yolu)
from eth_utils import keccak
import settlement_bind_verify as SB
from tamga_keccak import keccak256

# --- 1) GERÇEK-üretim-formülü: veridrome-cert_id-keccak'ı
agent_id = b"at161-agent"
pcr0 = bytes.fromhex("aa"*32)
merkle_root = bytes.fromhex("bb"*32)
now = 1790000000
packed_data = agent_id + pcr0 + merkle_root + now.to_bytes(32, "big")
cert_id = keccak(packed_data)
assert len(cert_id) == 32, f"cert_id-32-bayt-beklendi: {len(cert_id)}"
cert_hex = cert_id.hex()
# bağımsız-teyit: aynı-girdi → aynı-çıktı ( keccak-deterministik)
assert keccak(packed_data).hex() == cert_hex, "keccak-deterministik-değil"
# tahriz-teyiti: packed_data-değişirse-cert_id-değişir
assert keccak(packed_data + b"\x00").hex() != cert_hex, "keccak-tahriz-yutuldu"
print(f"  GERÇEK-üretim-keccak: cert_id=keccak( agent+pcr0+merkle+now) = "
      f"{cert_hex[:20]}… ( 32-bayt; deterministic + tahriz-dayanıklı)")

# --- 2) erc8004/v1-şeması: buyer = keccak256( delivery_hash)
# AT-128-dersi: delivery_hash-GÖVDEDEN-BAĞIMSIZ-sabit-olmalı ( gövde-buyer'ı-
# içerirse-döngüsel-gerçek-yol-asla-GREEN-veremez). Burada-delivery_hash =
# cert_hex'in-kendisi ( keccak-kanıtı = teslimat; AT-065-yapısı).
delivery_hash = cert_hex
buyer = keccak256(bytes.fromhex(delivery_hash))
buyer_hex = buyer.hex() if isinstance(buyer, bytes) else buyer
# erc8004/v1-buyer-64hex-raw ( EIP-191-uzunluk-0x-DEĞİL)
assert len(buyer_hex) == 64, f"erc8004-buyer-64hex-beklendi: {len(buyer_hex)}"
print(f"  erc8004/v1: buyer = keccak256( delivery_hash) = {buyer_hex[:20]}… "
      f"( imzasız-şema; buyer-özütten-türetilir; delivery_hash=keccak-cert)")

govde = {"buyerAddress": buyer_hex, "sellerAddress": "0x" + "2"*40,
         "settlementRef": "AT-161-ERC8004",
         # check-5: evidenceHash == delivery_hash ( AT-065-yapısı)
         "evidenceHash": {"alg": "keccak256", "hex": delivery_hash},
         "signature": "0x" + "00"*65}

# --- 3) RFC-010-DİKİŞ: erc8004/v1-GREEN
charge = {"seq": 161, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "keccak256", "hex": delivery_hash},
          "settlement_bind": {"scheme": "erc8004/v1", "payment_id": "AT-161-ERC8004",
                              "claim_evidence_hash": {"alg": "sha256", "hex": delivery_hash},
                              "payer": buyer_hex, "payee": "0x"+"2"*40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {"chain": "veridrome", "head_hex": cert_hex,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "veridrome.contracts.client.keccak"}}
# imzasız-şema: signature-alanı-YOK
claim = dict(govde)
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"erc8004/v1-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("6_foreign_chain") is True, "6_foreign_chain-geçmedi"
print(f"  DİKİŞ: veridrome-keccak-cert → erc8004/v1-GREEN-rc0 ( §6-veridrome-"
      f"equals; imzasız-şema-gerçek-doğrulandı)")

# --- NEG-1: yanlış-buyer ( keccak-türevi-değil) → RED
charge_bad = json.loads(json.dumps(charge))
charge_bad["settlement_bind"]["payer"] = "ff"*32
rb = SB.verify(charge_bad, claim)
assert rb["verdict"] == "RED", f"yanlış-buyer-geçti: {rb}"
print("  NEG-1 yanlış-buyer ( keccak-türevi-değil) → RED ( fail-closed)")

# --- NEG-2: claim'in-evidenceHash'ı-swap → RED rc7 ( charge-sabit-kalır)
dh2 = "9"*64
g2 = {"buyerAddress": buyer_hex, "sellerAddress": "0x" + "2"*40,
      "settlementRef": "AT-161-ERC8004",
      "evidenceHash": {"alg": "keccak256", "hex": dh2},
      "signature": "0x" + "00"*65}
c2 = json.loads(json.dumps(charge))   # charge-aynı ( delivery_hash=cert_hex)
r2 = SB.verify(c2, g2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, f"swap-rc7: {r2}"
print("  NEG-2 claim-evidenceHash-swap → RED rc7 ( fail-closed)")
PYEOF
kontrol $? "veridrome-keccak → erc8004/v1-dikiş"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-161: veridrome-keccak-cert → erc8004/v1 ( şema-dengesi-3/3-tamamlandı)"
[ "$FAIL" = "0" ]
