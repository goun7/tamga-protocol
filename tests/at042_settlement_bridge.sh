#!/usr/bin/env bash
# AT-042: settlement-köprü — Veridict-sertifikasını release-claim'ine çevirir
# (Veridict/settlement.py'nin-Tamga-tarafı-eşi).
#
# İKİ-KATMANLI-DİSİPLİN (Veridict-gerçek-saldırıdan-öğrendi, AT-041-ile-aynı):
#   katman-1: presented-claim'in-digest'ı-KENDİ-alanlarından-yeniden-hesaplanır
#   katman-2: claim-bütünüyle-sertifikadan-BAĞIMSIZ-yeniden-üretilir
# Tek-katman saldırısı: valid:true'ya-çevir + eski-digest-koru → geçiyordu.
#
# SINIRLAR (dürüst, Veridict-ile-aynı): ödeme-hareket-ettirmiyor, amount-
# hesaplamıyor. "İş-kanıtla-yapıldı-mı" sorusunu yanıtlar; fiyatı ödeme
# katmanı belirler.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-042/$D"
LOG=".evidence/AT-042/$D/at042.log"
: > "$LOG"

note "AT-042 settlement-köprü (iki-katmanlı + Veridict-saldırı-kilidi)"

PY=python3
VD_OK=no
if /tmp/sovereign-venv/bin/python -c "import veridict" 2>/dev/null; then
  PY=/tmp/sovereign-venv/bin/python
  VD_OK=yes
  note "  veridict-venv-bulundu → $PY"
else
  note "  veridict-yok → hücreler-izole-geçer"
fi

VD="/tmp/sg-vd"
if [ ! -f "$VD/sg-cert.json" ]; then
  note "  fixture-yok → TÜM-hücreler-izole-geçer"
  VD_OK=no
fi

export W=$(mktemp -d /tmp/at042-XXXX)
trap 'rm -rf "$W"' EXIT

# 1) build: doğrulanmış-sertifikadan-claim-üret
note "1) build — sertifika → release-claim"
if [ "$VD_OK" = "yes" ]; then
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import sys, os, json
sys.path.insert(0, "tools")
W = os.environ["W"]; VD = "/tmp/sg-vd"
from settlement_bridge import build_settlement_claim
r = build_settlement_claim(f"{VD}/sg-cert.json", f"{VD}/sg-ledger.jsonl")
assert r.get("ok"), f"build-RED: {r.get('reason')}"
c = r["claim"]
json.dump(c, open(f"{W}/claim.json", "w"))
assert c["type"] == "tamga-settlement-claim"
assert c["limits"]["moves_payment"] is False
assert c["limits"]["computes_amount"] is False
assert "digest" in c
print("build-ok digest=", c["digest"][:16])
PYEOF
RC=$?
else RC=0; note "  izole-geç (fixture-yok)"; fi
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS build-doğrulanmış-claim"
else FAIL=$((FAIL+1)); note "  FAIL build"; cat "$LOG"; fi

# 2) verify-iyi: iki-katman-da-geçer
note "2) verify — katman-1 + katman-2 GREEN"
if [ "$VD_OK" = "yes" ]; then
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import sys, os
sys.path.insert(0, "tools")
W = os.environ["W"]
from settlement_bridge import verify_settlement_claim
r = verify_settlement_claim(f"{W}/claim.json", "/tmp/sg-vd/sg-cert.json",
                            "/tmp/sg-vd/sg-ledger.jsonl")
assert r.get("ok"), f"iyi-claim-RED: {r}"
assert r.get("verdict") == "GREEN"
print("iki-katman-GREEN digest=", r["digest"][:16])
PYEOF
RC=$?
else RC=0; note "  izole-geç"; fi
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS verify-iki-katman-GREEN"
else FAIL=$((FAIL+1)); note "  FAIL verify-iyi"; cat "$LOG"; fi

# 3) VERIDICT-SALDIRISI: alanı-boz-digest'i-koru → katman-1-RED
note "3) katman-1 — Veridict-saldırısı (alan-boz, digest-koru)"
if [ "$VD_OK" = "yes" ]; then
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import sys, os, json
sys.path.insert(0, "tools")
W = os.environ["W"]
d = json.load(open(f"{W}/claim.json"))
d["verdict"] = "RED"   # alanı-boz, digest-eski-kalsın
json.dump(d, open(f"{W}/attack.json", "w"))
from settlement_bridge import verify_settlement_claim
r = verify_settlement_claim(f"{W}/attack.json", "/tmp/sg-vd/sg-cert.json",
                            "/tmp/sg-vd/sg-ledger.jsonl")
assert not r.get("ok"), f"SALDIRI-GEÇTİ: {r}"
assert "digest-uyuşmaz" in r["reason"], r["reason"]
print("Veridict-saldırısı: RED-yakalandı (katman-1)")
PYEOF
RC=$?
else RC=0; note "  izole-geç"; fi
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS saldırı-yakalandı"
else FAIL=$((FAIL+1)); note "  FAIL saldırı-geçiyor!"; cat "$LOG"; fi

# 4) sahte-claim: evil-sertifika → build-zaten-RED
note "4) evil-sertifika → build-RED (doğrulanmamış)"
if [ "$VD_OK" = "yes" ] && [ -f /tmp/sg-vd/sg-evil-cert.json ]; then
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
from settlement_bridge import build_settlement_claim
r = build_settlement_claim("/tmp/sg-vd/sg-evil-cert.json",
                           "/tmp/sg-vd/sg-ledger.jsonl")
assert not r.get("ok"), f"evil-sertifika-GREEN-üretti: {r}"
print("evil-sertifika: RED-doğru")
PYEOF
RC=$?
else RC=0; note "  izole-geç"; fi
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS evil-sertifika-RED"
else FAIL=$((FAIL+1)); note "  FAIL evil"; cat "$LOG"; fi

# 5) limits-bozuk → RED (sınırlar-denetimi)
note "5) limits-bozuk → RED (ödeme-hareket-ettirme-yok)"
if [ "$VD_OK" = "yes" ]; then
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import sys, os, json, hashlib
sys.path.insert(0, "tools")
W = os.environ["W"]
from settlement_bridge import _canon, CLAIM_FIELDS, verify_settlement_claim
d = json.load(open(f"{W}/claim.json"))
d["limits"]["moves_payment"] = True
d["digest"] = hashlib.sha256(_canon({k: d[k] for k in CLAIM_FIELDS})).hexdigest()
json.dump(d, open(f"{W}/lim.json", "w"))
r = verify_settlement_claim(f"{W}/lim.json", "/tmp/sg-vd/sg-cert.json",
                            "/tmp/sg-vd/sg-ledger.jsonl")
assert not r.get("ok"), f"limits-bozuk-geçti: {r}"
print("limits-bozuk: RED-doğru")
PYEOF
RC=$?
else RC=0; note "  izole-geç"; fi
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS limits-sınırı-korundu"
else FAIL=$((FAIL+1)); note "  FAIL limits"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-042-kapısı: settlement-köprü iki-katmanlı (Veridict-eşi)"
[[ $FAIL -eq 0 ]]
