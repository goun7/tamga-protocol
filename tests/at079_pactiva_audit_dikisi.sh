#!/usr/bin/env bash
# AT-079: PACTIVA → RFC-010/011-DİKİŞİ (C-sınıfı — 22-37-Pactiva).
#
# 22-37-Pactiva: pactiva_core/audit_ledger.py — GERÇEK-Merkle-hash-zinciri
# (GENESIS_PREV_HASH=64-sıfır; compute_block_hash; record_audit_event;
# verify_audit_ledger_integrity — üç-saldırı-sınıfı-tespit-eder:
# CHAIN_DISCONTINUITY, PAYLOAD_TAMPERED, BLOCK_HASH_INVALID).
# pactiva_core/arbitration.py — RFC-011'in-dış-yüzü (anlaşmazlık-çözümü).
#
# PACTİVA-ÖZELLİĞİ: audit-ledger-bir-D5-hint-zinciridir — Tamga'nın-kendi
# ledger'ıyla-AYNI-aile (prev-hash-zinciri + 64-sıfır-GENESIS). Ama-Pactiva
# o-zinciri-ÖDEME-kanalına-BAĞLAMAZ. RFC-010-dikiş-o-boşluğu-kapatır:
# zincirin-son-head'i-foreign_chain_proof-olarak-girince-artık-ödeme-kanalı
# "bu-emanet-kilitlendi"-der-ve-Tamga-gate'i-bunu-çürütürse-RED-verir.
#
# RFC-011-BAĞLANTISI: Pactiva'nın-arbitration-modülü-dispute-pointer'ın
# dış-çözüm-hedefidir (Pacta-§5.3-üzere).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-079/$(date +%F)/at079.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-079: Pactiva-audit-ledger → RFC-010/011 dikişi"

PA="/home/gokun/projects/01_unicorn/22-37-Pactiva"
if [ ! -f "$PA/pactiva_core/audit_ledger.py" ]; then
  note "[SKIP] AT-079: Pactiva-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$PA" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from pactiva_core import audit_ledger as AL
from pactiva_core.database import init_db
import settlement_bind_verify as SB

# --- 0) GEÇİCİ-DB (asıl-pactiva.db'yi-BOZMAYIZ — yazma-bölgesi-izole)
TMP = tempfile.mkdtemp(prefix="at079-")
DBP = os.path.join(TMP, "pactiva-at079.db")
init_db(DBP)

# --- 1) GERÇEK-zincir-üretimi: 3-olay → append-only-merkle-zinciri
r1 = AL.record_audit_event("escrow_lock", {"amount_usd": 10.0,
        "job_id": "JOB-1", "worker": "W-1"}, db_path=DBP)
r2 = AL.record_audit_event("shift_complete", {"hours": 8.0,
        "job_id": "JOB-1"}, db_path=DBP)
r3 = AL.record_audit_event("escrow_release", {"amount_usd": 10.0,
        "job_id": "JOB-1", "worker": "W-1"}, db_path=DBP)
head = r3["block_hash"]
assert isinstance(head, str) and len(head) == 64, f"head-64-hex-değil: {head!r}"
assert r2["prev_block_hash"] == r1["block_hash"], "zincir-prev-bağı-kırık"
assert r3["prev_block_hash"] == r2["block_hash"], "zincir-prev-bağı-kırık"
print(f"  Pactiva-audit-zinciri-üretildi: 3-blok, head={head[:24]}…")

# tam-doğrulama-üç-saldırı-sınıfı-ile-çalışıyor-mu
v = AL.verify_audit_ledger_integrity(db_path=DBP)
assert v["is_valid"] is True and v["total_blocks"] == 3, \
    f"geçerli-zincir-doğrulanmalı: {v}"
print(f"  verify_audit_ledger_integrity: is_valid=True ({v['total_blocks']}-blok)")

# GENESIS-64-sıfır-kuralı (Tamga'yla-aynı-aile)
assert AL.GENESIS_PREV_HASH == "0"*64, "GENESIS-64-sıfır-değil"
assert r1["prev_block_hash"] == AL.GENESIS_PREV_HASH, "ilk-blok-GENESIS'e-bağlı-değil"
print("  GENESIS_PREV_HASH=64-sıfır — Tamga-ledger'ıyla-aynı-aile (D5-hint)")

# --- 2) TAHRİF-tespiti (üretici-tarafı-sağlamlık)
import sqlite3
conn = sqlite3.connect(DBP)
conn.execute("UPDATE audit_blocks SET payload_json='{\"SALDIRGI\":1}' "
             "WHERE block_index=2")
conn.commit(); conn.close()
vt = AL.verify_audit_ledger_integrity(db_path=DBP)
assert vt["is_valid"] is False, "tahrif-tespit-edilmeli"
assert vt["error_code"] == "PAYLOAD_TAMPERED", \
    f"PAYLOAD_TAMPERED-beklendi: {vt['error_code']}"
print(f"  payload-tahrizi-tespit-edildi: {vt['error_code']} (blok-{vt['compromised_block_index']})")

# --- 3) erc8004/v1-GREEN-dikiş: head-foreign_chain_proof-olarak
# Önemli-kısıt: _foreign_chain_ok-chain-alanı ("swarmax","dumen","pqhaven",
# "tamga")-ile-sınırlı — "pactiva"-YOK. Yerel-ledger-kanıtı-olduğu-için-
# "tamga"-kullanırız (bu-gerçek-bir-kısıt-ve-test-onu-ölçer).
init_db(DBP)  # tahriz-sonrası-temiz-zincir
a1 = AL.record_audit_event("escrow_lock", {"amount": 10.0}, db_path=DBP)
head2 = a1["block_hash"]
charge = {"seq": 22, "prev": "0"*64, "h": "c"*64,
          "delivery_hash": {"alg": "sha256", "hex": head2},
          "settlement_bind": {"scheme": "erc8004/v1",
                              "payment_id": "PACT-ESCROW-0022",
                              "claim_evidence_hash": {"alg": "sha256", "hex": head2},
                              "payer": head2, "payee": "0x2"*40,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": head2,
                                  "entries": 1,
                                  "evidence_link": "equals",
                                  "verify_cmd": "pactiva.audit_ledger.verify_audit_ledger_integrity"}}
claim = {"buyerAddress": head2, "sellerAddress": "0x2"*40,
         "settlementRef": "PACT-ESCROW-0022",
         "evidenceHash": {"alg": "sha256", "hex": head2}, "signature": head2}
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    s if scheme == "erc8004/v1" else "0x1")
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Pactiva-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  gerçek-audit-head → erc8004/v1-GREEN (§6-tamga-zinciriyle)")
print("    evidence_link='equals': head-delivery_hash'e-içerikten-bağlı")

# --- 4) chain-alanı-kısıtının-gerçek-ölçümü: "pactiva"-scheme-listesinde-YOK
# Üçüncü-seçenek-yasak: bilinmeyen-chain-RED-değil-İNDETERMİNE-de-olmamalı-
# olduğu-için-_foreign_chain_ok-False-döner-ve-RED-rc8-verir (kanıtlı-çürüklük).
charge_x = json.loads(json.dumps(charge))
charge_x["foreign_chain_proof"]["chain"] = "pactiva"
rx = SB.verify(charge_x, claim)
assert rx["verdict"] == "RED" and rx["reason_code"] == 8, \
    f"bilinmeyen-chain-RED-rc8-beklendi: {rx}"
print("  chain='pactiva'-kısıt-dışı → RED rc8 (foreign_chain_broken)")
print("    (kısıt-gerçek: whitelist-swarmax/dumen/pqhaven/tamga — yerel-için-tamga)")

# --- 5) NEGATİF-1: sahte-head (defter-dışı) → RED rc8
# AT-079-BULGUSU: evidence_link-YOKKEN-sahte-head-GREEN-geçiyordu (biçim-yeterliydi);
# link='equals'-ile-artık-head-delivery_hash'e-eşit-olmalı → sahte-head-RED.
charge2 = json.loads(json.dumps(charge))
charge2["foreign_chain_proof"]["head_hex"] = "f"*64
r2 = SB.verify(charge2, claim)
assert r2["verdict"] == "RED" and r2["reason_code"] == 8, \
    f"sahte-head-RED-rc8-beklendi: {r2}"
print("  defter-dışı-sahte-head-RED rc8 (evidence_link=equals-ile-içerik-bağlı)")
# geri-uyum-kanıtı: link-OLMAYAN-eski-kanıt-hâlâ-biçim-kontrolü-ile-çalışır
charge_old = json.loads(json.dumps(charge))
del charge_old["foreign_chain_proof"]["evidence_link"]
r_old = SB.verify(charge_old, claim)
assert r_old["verdict"] == "GREEN", f"eski-biçim-kanıt-GREEN-kalmalı: {r_old}"
print("  geri-uyum: evidence_link-siz-eski-kanıt-hâlâ-GREEN (additive-korundu)")

# --- 6) NEGATİF-2: evidenceHash-swap → RED rc7 (safal207-negatif-kontrolü)
claim3 = json.loads(json.dumps(claim))
claim3["evidenceHash"]["hex"] = "9"*64
r3 = SB.verify(charge, claim3)
assert r3["verdict"] == "RED" and r3["reason_code"] == 7, f"swap-RED: {r3}"
print("  evidenceHash-swap-RED rc7 — beş-kontrol-audit-zincirinde-de-çalışıyor")

# --- BONUS: RFC-011-arbitration-bağlantısı (dış-yüz-var-mı)
try:
    from pactiva_core import arbitration
    assert hasattr(arbitration, "__name__")
    print("  pactiva_core.arbitration-modülü-yüklendi (RFC-011-dış-yüz-mevcut)")
except ImportError as e:
    print(f"  arbitration-modülü-yok (RFC-011-bağlantısı-SKIP): {e}")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Pactiva-audit-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-079: Pactiva-audit-ledger → RFC-010/011"
[[ $FAIL -eq 0 ]]
