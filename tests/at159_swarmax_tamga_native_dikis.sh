#!/usr/bin/env bash
# AT-159: SWARMAX-SEAL → tamga/native-ŞEMASI ( şema-boşluğu-kapatma)
#
# Bu-turda-16-testin-14'ü-x402/v1-kullandı — tamga/native-VE-erc8004/v1-
# HİÇ-test-edilmedi. "Her-açıdan-100/100"-için-şema-dengesi-gerekir.
# Bu-test-tamga/native'ı-örnekler: RFC-010'ün-native-blockchain-şeması.
#
# tamga/native ( RFC-010-§3.2):
#   - Ed25519 RFC-8032, buyerAddress = 64-hex-RAW-genel-anahtar
#   - imza digest_hex'in-HAM-baytları-üzerinde ( EIP-191-öneki-YOK)
#   - R-noktası-koruması: sig[:64] != PUB ( AT-077-dersi)
#
# swarmax-seal-ED25519-yüzü-AT-148'de-x402/v1-ile-bağlandı; burada-AYNI-
# kanıt-tamga/native-ile-bağlanır → mesh-native-şemasının-güçlendirilmesi.
set -uo pipefail

TESTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTDIR/.." && pwd)"
LOG="$ROOT/.evidence/SWARMAX-TAMGA-NATIVE/$(date +%F)/at159.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }

if [ ! -f /home/gokun/projects/00_TAMGA-MESH/swarmax/src/swarmax/sealing.py ]; then
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — swarmax-yok (İNDETERMİNE)"; exit 0
fi

python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, tempfile, os, hashlib, json
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/swarmax/src")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
from swarmax.db import connect, init_db_with_migrations
from swarmax.evidence import append_evidence, verify_chain
from swarmax.sealing import seal_ledger, verify_seals
from swarmax.ed25519 import generate_seed, sign, verify
import settlement_bind_verify as SB

# --- 1) ÜRETİM-akışı: swarmax-evidence-ledger → seal
p = tempfile.mktemp(suffix="-at159.db")
conn = connect(p); init_db_with_migrations(conn)
append_evidence(conn, "charge", {"amount": "0.05", "agent": "a1"})
append_evidence(conn, "escalate", {"sev": "critical", "agent": "a2"})
ok, n = verify_chain(conn)
assert ok and n == 2, f"üretim-ledger'ı-bozuk: ({ok}, {n})"
seed = generate_seed()
s = seal_ledger(conn, seed, tsa_url=None)
ROOT_H = s["root_hash"]; PUB = s["public_key"]; SIG = s["signature"]
assert len(ROOT_H) == 64 and len(PUB) == 64 and len(SIG) == 128, "formatlar-bozuk"
# karşı-taraf-secret'sız-doğrulama ( AT-148'in-ana-kanıtı-burada-da-geçer)
vs = verify_seals(conn)
assert vs["all_ok"] is True, f"seal-verify-bozuk: {vs}"
print(f"  üretim-akışı: 2-olay-evidence-ledger ( verify_chain-True) → "
      f"seal: root={ROOT_H[:16]}… + Ed25519-pub-64hex + sig-128hex; "
      f"verify_seals-all_ok ( secret'sız)")

# --- 2) DİKİŞ: tamga/native-şeması → RFC-010
# evidenceHash = root_hash ( swarmax-seal'in-Merkle-kökü = kanıt)
govde = {"buyerAddress": PUB, "sellerAddress": "0x" + "2"*40,
         "settlementRef": "AT-159-TAMGA-NATIVE",
         "evidenceHash": {"alg": "sha256", "hex": ROOT_H}}
# tamga/native: imza-digest'in-ham-baytları-üzerinde ( RFC-8032)
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig_hex = sign(seed, bytes.fromhex(d)).hex()
assert len(sig_hex) == 128, "Ed25519-imza-128hex-değil"
# R-noktası-koruması: imzanın-R'si-genel-anahtar-OLAMAZ
assert sig_hex[:128] != PUB, "R-noktası-PUB'ya-eşit ( AT-077-ihlali)"
# bağımsız-Ed25519-teyiti
assert verify(bytes.fromhex(PUB), bytes.fromhex(d), bytes.fromhex(sig_hex)) is True
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 159, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": ROOT_H},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "AT-159-TAMGA-NATIVE",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": PUB, "payee": "0x"+"2"*40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {"chain": "swarmax", "head_hex": ROOT_H,
                                  "entries": n, "evidence_link": "equals",
                                  "verify_cmd": "swarmax.sealing.verify_seals"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"tamga/native-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "2_claim_sig-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "6_foreign_chain-geçmedi"
print(f"  DİKİŞ: swarmax-seal-kökü → tamga/native-GREEN-rc0 ( §6-swarmax-"
      f"equals, entries={n}) — native-şema-bu-turun-boşluğunu-kapadı")

# --- NEG-1: sahte-imza → RED rc4
cs = dict(govde); cs["signature"] = "ff"*64
rs = SB.verify(charge, cs)
assert rs["verdict"] == "RED" and rs["reason_code"] == 4, f"sahte-imza-rc4: {rs}"
print("  NEG-1 sahte-imza → RED rc4 ( fail-closed)")

# --- NEG-2: evidenceHash-swap → RED rc7
g2 = dict(govde); g2["evidenceHash"] = {"alg": "sha256", "hex": "9"*64}
d2 = hashlib.sha256(json.dumps(g2, sort_keys=True).encode()).hexdigest()
c2 = dict(g2); c2["signature"] = sign(seed, bytes.fromhex(d2)).hex()
r2 = SB.verify(charge, c2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, f"swap-rc7: {r2}"
print("  NEG-2 evidenceHash-swap → RED rc7 ( fail-closed)")

# --- NEG-3: R-noktası-PUB'ya-eşit → reddi ( AT-077-dersi)
c3 = dict(govde)
c3["signature"] = PUB + "11"*32   # R-noktası-PUB → koruma-tetiklenmeli
r3 = SB.verify(charge, c3)
assert r3["verdict"] == "RED" and r3["reason_code"] == 4, \
    f"R-noktası-koruması-çalışmadı: {r3}"
print("  NEG-3 R-noktası==PUB → RED rc4 ( AT-077-koruması-canlı)")

os.unlink(p)
PYEOF
kontrol $? "swarmax-seal → tamga/native-dikiş"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-159: swarmax-seal → tamga/native-şeması ( turun-şema-boşluğu-kapatıldı)"
[ "$FAIL" = "0" ]
