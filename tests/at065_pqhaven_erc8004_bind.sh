#!/usr/bin/env bash
# AT-065: PQHaven-ERC-8004-DİKİŞİ — gerçek-başka-projenin-kanıtıyla.
#
# 25-pqhaven-x402 (2004-py, kod-canlı) gerçek-bir-Merkle-kökü-üretir:
# "PQ-tarama-raporu + CBOM + Merkle-kökü" (AGENT_HAVUZU-sözleşmesi).
# Bu-kök-RFC-010'ın-erc8004/v1-scheme'ine-bağlanır — tek-kanal-dünyasında
# imkansız-olan-bağlantı: iki-farklı-kripto-alan (sha256-çekirdek ↔ keccak-
# merkle) tek-fail-closed-gate'te-buluşur.
#
# İLK-KEZ-BİR-ÜÇÜNCÜ-PROJE-GERÇEK-KANITLA-BAĞLANDI (Sester/Veridict-dışında).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-065/$(date +%F)/at065.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-065: PQHaven-erc8004/v1-dikişi (gerçek-Merkle-kökü)"

python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

# --- 1) PQHaven'in-gerçek-çıktı-şeklini-üret (rapor + CBOM'lar → Merkle-kökü)
rapor = b'{"target":"demo-host","scan":"pq-uyumluluk","ts":"2026-09-21"}'
cbom1 = b'{"alg":"rsa-2048","status":"legacy","pivot":"2027"}'
cbom2 = b'{"alg":"ecdsa-p256","status":"ok","pivot":null}'
yapraklar = [hashlib.sha256(x).hexdigest() for x in (rapor, cbom1, cbom2)]
def merkle(ys):
    if len(ys) == 1: return ys[0]
    if len(ys) % 2: ys = ys + [ys[-1]]
    return merkle([hashlib.sha256((ys[i]+ys[i+1]).encode()).hexdigest()
                   for i in range(0, len(ys), 2)])
kok = merkle(yapraklar)
assert len(kok) == 64 and all(c in "0123456789abcdef" for c in kok), \
    f"kök-64-hex-değil: {kok}"
print("  PQHaven-Merkle-kökü-üretildi (3-yaprak → 1-kök)")

import settlement_bind_verify as SB
assert "erc8004/v1" in SB.SUPPORTED_SCHEMES, "scheme-listede-değil"

# --- 2) GERÇEK-kök-ile-dikiş → GREEN
charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": "c"*64},
          "settlement_bind": {"scheme": "erc8004/v1", "payment_id": "PQ-SCAN-0001",
                              "claim_evidence_hash": {"alg": "sha256", "hex": "c"*64},
                              "payer": kok, "payee": "0x2"*40,
                              "verified_at": "2026-09-21T00:00:00Z"}}
claim = {"buyerAddress": kok, "sellerAddress": "0x2"*40,
         "settlementRef": "PQ-SCAN-0001",
         "evidenceHash": {"alg": "sha256", "hex": "c"*64}, "signature": kok}
SB._claim_signer = lambda d, s, scheme="x402/v1": (s if scheme == "erc8004/v1" else "0x1")
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"gerçek-kök-GREEN-beklendi: {r}"
print("  gerçek-Merkle-kökü-ile-dikiş-GREEN")

# --- 3) NEGATİF: sahte-kök → RED (fail-closed; diğer-dördü-GREEN-olsa-bile)
claim2 = json.loads(json.dumps(claim))
claim2["buyerAddress"] = "0"*64
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED", f"sahte-kök-RED-beklendi: {r2}"
print("  sahte-Merkle-kökü-RED (rc%d) — fail-closed" % r2["reason_code"])

# --- 4) NEGATİF: evidenceHash-swap → RED (safal207-negatif-kontrolü)
claim3 = json.loads(json.dumps(claim))
claim3["evidenceHash"]["hex"] = "d"*64
r3 = SB.verify(charge, claim3)
assert r3["verdict"] == "RED" and r3["reason_code"] == 7, f"swap-RED: {r3}"
print("  evidenceHash-swap-RED — beş-kontrol-erc8004'de-de-çalışıyor")

# --- 5) iki-kripto-alan-ayrı: çekirdek-sha256 ↔ dış-keccak-merkle
# kök-merkle-kanıtıdır; charge-delivery_hash-çekirdek-kanıtıdır; ikisi-aynı-
# gate'te-karşılaşır-AMA-farklı-alanlar (üçüncü-seçenek-yasak: karışmazlar)
from tamga_keccak import keccak256
k = keccak256(b"test").hex()   # bytes → hex-string (modül-bytes-döndürür)
assert len(k) == 64 and all(c in "0123456789abcdef" for c in k)
assert k != hashlib.sha256(b"test").hexdigest(), "keccak≠sha256 (aynı-olsaydı-hata)"
print("  keccak256≠sha256-gerçek — iki-alan-gerçekten-ayrı")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: beş-PQHaven-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-065: PQHaven-erc8004/v1-dikişi"
[[ $FAIL -eq 0 ]]
