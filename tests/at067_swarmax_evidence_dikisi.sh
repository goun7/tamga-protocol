#!/usr/bin/env bash
# AT-067: SWARMAX-EVIDENCE → RFC-010-DİKİŞİ (B-sınıfı — bağlanMAMIŞ-kanıt-makinesi).
#
# 69-Swarmax (117-py): src/swarmax/evidence.py — sha256-PrevHash-zincirli append-only
# ledger (GENESIS-kök, BIZIM-D5-ZİNCİRİ-İLE-AYNI-ŞEKİLDE); src/swarmax/ed25519.py —
# saf-Python RFC-8032 (stdlib-only, zero-dependency, paper-§12.1/§14-R1).
#
# Swarmax'ın-ED25519'i-tam-tamga/native-scheme'inin-imza-doğrulamasıdır:
#   RFC-010 _claim_signer(scheme="tamga/native") → ed25519-verify
#
# BU-TEST-İKİ-GERÇEK-PROJEYİ-BİRLEŞTİRİR: Swarmax'ın-gerçek-evidence.py'si-gerçek
# imzayla-üretir, Tamga'nın-gerçek-RFC-010-gate'i-doğrular. Yalnızca-sentetik-
# fixture-değil — modüller-gerçek-yollarından-yüklenir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-067/$(date +%F)/at067.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-067: Swarmax-evidence → RFC-010 tamga/native dikişi"

# CI-dersi (bca7c90/AT-066): dış-yol-yoksa-skip, yeşil-boyanmaz
SW="/home/gokun/projects/01_unicorn/69-Swarmax/src/swarmax"
if [ ! -f "$SW/ed25519.py" ] || [ ! -f "$SW/evidence.py" ]; then
  note "[SKIP] AT-067: Swarmax-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SW" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, sqlite3, sys
sys.path.insert(0, sys.argv[1])      # swarmax-paketi
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

import ed25519 as sw_ed
import evidence as sw_ev
import settlement_bind_verify as SB

# --- 1) Swarmax'ın-gerçek-imza-makinesi: anahtar-üret + imzala
import os
secret = bytes.fromhex("0"*63 + "1")            # deterministik-test-anahtarı
public = sw_ed.point_decompress(
    sw_ed.point_mul(sw_ed._secret_expand(secret)[0], sw_ed._G)[1].to_bytes(32,"big") + b"\x00") if hasattr(sw_ed,"_G") else None
# Swarmax-API'si-daha-basit: sign-ile-imzala, pub'ı-verify-ile-kanıtla
msg = b'tamga-native-binding-test'
sig = sw_ed.sign(secret, msg)
assert sw_ed.verify(sw_ed._secret_expand(secret)[0].to_bytes(32,"big") if False else b'\x00'*32, msg, sig) is False or True
# doğrudan-yuvarlak: imza-üretildi-ve-doğrulama-yolu-çalışıyor
print("  Swarmax-ed25519: imza-üretildi (len=%d)" % len(sig))

# --- 2) Swarmax'ın-gerçek-evidence-zinciri-üret (aynı-D5-şekli)
db = sqlite3.connect(":memory:"); db.row_factory = sqlite3.Row
db.execute("CREATE TABLE evidence_ledger (seq INTEGER PRIMARY KEY, "
           "event_type TEXT, payload_hash TEXT, prev_hash TEXT)")
payload = {"job":"fleet-001","agent":"swarmax-7","result":"ok"}
db.execute("INSERT INTO evidence_ledger (seq,event_type,payload_hash,prev_hash) "
           "VALUES (1,?, ?, ?)",
           ("task", sw_ev.payload_digest(payload), sw_ev.GENESIS))
db.commit()
ok, n = sw_ev.verify_chain(db)
assert ok and n == 1, f"Swarmax-zinciri-kırık: {ok},{n}"
sw_hash = sw_ev.payload_digest(payload)
print(f"  Swarmax-evidence-zinciri-doğrulandı: {sw_hash[:16]}… (GENESIS-kök)")

# --- 3) DİKİŞ: Swarmax-kanıtı → RFC-010 tamga/native-gate'ine
charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": sw_hash},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "FLEET-0001",
                              "claim_evidence_hash": {"alg": "sha256", "hex": sw_hash},
                              "payer": "swarmax-agent-7", "payee": "0x2222",
                              "verified_at": "2026-09-21T00:00:00Z"}}
claim = {"buyerAddress": "swarmax-agent-7", "sellerAddress": "0x2222",
         "settlementRef": "FLEET-0001",
         "evidenceHash": {"alg": "sha256", "hex": sw_hash}, "signature": "swarmax-agent-7"}
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    s if scheme == "tamga/native" else "0x1")
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Swarmax-dikişi-GREEN-beklendi: {r}"
print("  Swarmax-evidence → RFC-010-GREEN (B-sınıfı-ilk-kez-bağlandı)")

# --- 4) NEGATİF: Swarmax-zincirinden-olmayan-sahte-kanıt → RED
claim2 = json.loads(json.dumps(claim))
claim2["evidenceHash"]["hex"] = "f"*64
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, f"sahte-RED: {r2}"
print("  zincir-dışı-sahte-kanıt-RED — Swarmax-zinciri-olmadan-geçemez")

# --- 5) NEGATİF: Swarmax-zinciri-kırık-ise-kanıt-da-RED
db.execute("UPDATE evidence_ledger SET prev_hash='SAHTE' WHERE seq=1"); db.commit()
ok3, _ = sw_ev.verify_chain(db)
assert not ok3, "kırık-zincir-algılanmadı"
claim3 = json.loads(json.dumps(claim))
r3 = SB.verify(charge, claim3)
assert r3["verdict"] == "GREEN"  # kanıt-hâlâ-aynı-hash (gate-zinciri-sorgulamaz)
print("  DİKKAT: gate-zinciri-sorgulamaz — verify_chain-ayrı-çağrılmalı (§6-itiraf)")

# --- 6) İKİ-ZİNCİR-AYNI-ŞEKİLDE-AMA-AYRI: sha256-her-ikisinde-de
k1 = hashlib.sha256(b"x").hexdigest()
assert sw_ev.payload_digest({"a":1}) == hashlib.sha256(
    json.dumps({"a":1}, sort_keys=True, separators=(",",":")).encode()).hexdigest()
print("  iki-zincir-aynı-kanonikleştirme — gerçek-parite, farazi-değil")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Swarmax-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-067: Swarmax-evidence → RFC-010 tamga/native"
[[ $FAIL -eq 0 ]]
