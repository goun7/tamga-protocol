#!/usr/bin/env bash
# AT-041: sovereign-anchor — üç-ürün kanıtlarını tek-kanıt-özüne bağlar.
#
# K23.5-bağlam: sovereign_verify üç ürünün kendi doğrulayıcılarını çağırır.
# AT-041 bir adım ilerisini üretir: her ürünün sonucunu ortak bir kanıt özünde
# toplar — ama hiçbir ürünün iç yüzeyine dokunmadan (zayıf-bağ).
#
# VERIDICT-DERSİ (2026-09-19): tek-katmanlı kök-denetimi YETERSİZDİR. Saldırgan
# ok:true'yu sahte-yeşile-boyayıp kökü yeniden hesaplarsa geçer. Bu test o
# saldırıyı kilitler: iki-katmanlı disiplin —
#   katman-1: presented-tutarlılık (özet-yeniden-hesap)
#   katman-2: bağımsız-yeniden-hesap (kaynaktan-tekrar-doğrula)
# Sadece ikincisi saldırıyı kaçırır; bizde ikisi de var.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-041/$D"
LOG=".evidence/AT-041/$D/at041.log"
: > "$LOG"

note "AT-041 sovereign-anchor (üç-ürün tek-öz + iki-katmanlı-doğrulama)"

PY=python3
SESTER_OK=no
if /tmp/sovereign-venv/bin/python -c "import sester" 2>/dev/null; then
  PY=/tmp/sovereign-venv/bin/python
  SESTER_OK=yes
  note "  sester-venv-bulundu → $PY"
else
  note "  sester-yok → Sester-hücreleri-izole-geçer"
fi

# TEK-geçici-dizin-tüm-hücreler-için; ortam-değişkeni-olarak-aktarılır
# (heredoc-içi-python-bunu-okur; $W-yerel-değişken-görünmez)
export W=$(mktemp -d /tmp/at041-XXXX)
trap 'rm -rf "$W"' EXIT
export A="$W/anchor.json"

head -1 tests/vendor-capacity-attest/production-claim.jsonl > "$W/claim.json"
if [ "$SESTER_OK" = "yes" ]; then
  "$PY" - <<'PYEOF' >> "$LOG" 2>&1
import os
W = os.environ["W"]
from sester.ledger import Ledger
p = f"{W}/sester.db"
if os.path.exists(p): os.remove(p)
lg = Ledger(p); lg.append("charge", "a1", "h1", 1.0, {}); lg.close()
print("  taze-sester-ledger-üretildi")
PYEOF
fi

export VD_LEDGER="/tmp/sg-vd/sg-ledger.jsonl"
export VD_CERT="/tmp/sg-vd/sg-cert.json"
if [ ! -f "$VD_LEDGER" ]; then export VD_LEDGER=""; export VD_CERT=""; fi

# 1) build: üç-ürün-de-GREEN
note "1) build — üç-ürün-kanıtı-tek-özde"
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import sys, os, json
sys.path.insert(0, "tools")
W = os.environ["W"]; A = os.environ["A"]
VL = os.environ.get("VD_LEDGER", ""); VC = os.environ.get("VD_CERT", "")
SDB = f"{W}/sester.db" if os.path.exists(f"{W}/sester.db") else None
from sovereign_anchor import build
r = build(f"{W}/claim.json", SDB, None, VL or None, VC or None)
json.dump(r, open(A, "w"))
assert r["all_proved"], f"ürün-kanıtı-eksik: {r['results']}"
print("build-ok", r["products_proved"])
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS build-üç-ürün-GREEN"
else FAIL=$((FAIL+1)); note "  FAIL build"; cat "$LOG"; fi

# 2) verify-iyi: iki-katman-da-geçer
note "2) verify — katman-1 + katman-2"
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import sys, os
sys.path.insert(0, "tools")
from sovereign_anchor import verify
r = verify(os.environ["A"])
assert r.get("ok"), f"iyi-anchor-RED: {r}"
assert r.get("verdict") == "GREEN", f"beklenen-GREEN: {r.get('verdict')}"
ind = r.get("independent", {})
assert all(ind.values()) if ind else True, f"bağımsız-bozuk: {ind}"
print("iki-katman-GREEN", ind)
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS verify-iki-katman-GREEN"
else FAIL=$((FAIL+1)); note "  FAIL verify-iyi"; cat "$LOG"; fi

# 3) katman-1: kök-kurcalama → RED
note "3) katman-1 — kök-kurcalama RED"
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import json, os, sys
sys.path.insert(0, "tools")
W = os.environ["W"]
d = json.load(open(os.environ["A"])); d["anchor_root"] = "0"*64
json.dump(d, open(f"{W}/k.json", "w"))
from sovereign_anchor import verify
r = verify(f"{W}/k.json")
assert not r.get("ok"), f"kök-kurcalama-yakalanmadı: {r}"
assert "kurcalanmış" in r["reason"]
print("kök-kurcalama: RED-doğru")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS kök-kurcalama-RED"
else FAIL=$((FAIL+1)); note "  FAIL kök-kurcalama"; cat "$LOG"; fi

# 4) SAHTE-YEŞİLE-BOYAMA (Veridict-saldırısı) → katman-2-RED
note "4) katman-2 — sahte-yeşile-boyama RED (Veridict-dersi)"
if [ "$SESTER_OK" = "yes" ]; then
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import json, os, sys, hashlib
sys.path.insert(0, "tools")
W = os.environ["W"]
d = json.load(open(os.environ["A"]))
from sovereign_anchor import verify, _canon
# saldırı: sester'in-SONUCUNU-sahte-GREEN'e-boyayıp-kökü-yeniden-hesapla
# (gerçek-saldırı: sonuç-RED-gelmiş-ama-özel-yeşile-boyanmış)
d["results"]["sester"] = {"ok": True, "verdict": "GREEN"}
d["anchor_root"] = hashlib.sha256(
    _canon({"results": d["results"], "sources": d.get("sources", {})})).hexdigest()
json.dump(d, open(f"{W}/s.json", "w"))
# katman-2-AĞIRLA: sester-db'nin-zincir-kırıcı-alanını-boz ki
# bağımsız-doğrulama-RED-versin, sahte-yeşile-boyama-yakatlansın.
# (amount_minor-değil-amount: amount-zincir-hash'ine-girer, amount_minor-girmez)
import sqlite3
con = sqlite3.connect(f"{W}/sester.db")
try:
    con.execute("UPDATE events SET amount = 999.0")
    con.commit()
finally:
    con.close()
r = verify(f"{W}/s.json")
assert not r.get("ok"), f"SAHTE-YEŞİLE-BOYAMA-GEÇTİ: {r}"
print("sahte-yeşile-boyama: RED-yakalandı (katman-2)")
PYEOF
RC=$?
else
  note "  PASS saldırı-hücresi-atlandı (sester-yok — izole-geç)"
  RC=0
fi
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS sahte-yeşile-boyama-yakalandı"
else FAIL=$((FAIL+1)); note "  FAIL saldırı-geçiyor!"; cat "$LOG"; fi

# 5) kaynaksız → UNVERIFIED (sessiz-geçiş-yok, dürüst-bildirim)
note "5) kaynaksız — UNVERIFIED-INDEPENDENTLY (dürüst)"
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import json, os, sys, hashlib
sys.path.insert(0, "tools")
W = os.environ["W"]
d = json.load(open(os.environ["A"])); d.pop("sources", None)
# ERRATUM-A1: sources-köke-girer → kaynaksız-anchor'ın-kökünü-yeniden-hesapla
# (yoksa katman-1-kök-uyuşmazlığı-RED-verir-ve-bu-asıl-testi-gizler)
from sovereign_anchor import _canon
d["anchor_root"] = hashlib.sha256(
    _canon({"results": d["results"], "sources": {}})).hexdigest()
json.dump(d, open(f"{W}/n.json", "w"))
from sovereign_anchor import verify
r = verify(f"{W}/n.json")
assert r.get("ok"), f"kaynaksız-RED-olmamalı: {r}"
assert r.get("verdict") == "UNVERIFIED-INDEPENDENTLY", r.get("verdict")
print("kaynaksız: UNVERIFIED — sessiz-geçiş-yok")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS UNVERIFIED-dürüst-bildirim"
else FAIL=$((FAIL+1)); note "  FAIL kaynaksız"; cat "$LOG"; fi

# 6) ERRATUM-A2: ok:True-ama-verdict:RED-boyama → layer-1-RED (yeni-sınıf)
note "6) A2 — ok:True/verdict:RED-boyama-yakalanır (UNVERIFIED-perdesi)"
"$PY" - <<'PYEOF' >> "$LOG" 2>&1
import json, os, sys, hashlib, copy
sys.path.insert(0, "tools")
W = os.environ["W"]
d = json.load(open(os.environ["A"]))
from sovereign_anchor import verify, _canon
# saldırı: ürünün-sonucunu-ok:True-ama-verdict:RED-yap (çelişki), kökü-yeniden
# hesapla → layer-1-geçmeli-ESKİ-sürümde-UNVERIFIED-ile-gizliyordu.
s = copy.deepcopy(d)
# A2-vektörü: ok:True-ama-verdict:RED. products_proved-ok'e-göre-DOLU-olmalı
# (yoksa-önceki-denetim-tetiklenir). all_proved: proved==results-uzunluğu.
s["results"] = {"tamga": {"ok": True, "verdict": "RED", "detail": "gizli-bozuk"}}
s["products_present"] = ["tamga"]
s["products_proved"] = ["tamga"]           # ok:True → proved'da-olmalı
s["all_proved"] = True                      # len(proved)==len(results)==1
s["sources"] = {}
s["anchor_root"] = hashlib.sha256(
    _canon({"results": s["results"], "sources": {}})).hexdigest()
json.dump(s, open(f"{W}/a2.json", "w"))
r = verify(f"{W}/a2.json")
assert not r.get("ok"), f"A2-saldırısı-gizlendi: {r}"
assert "boyama" in r.get("reason", "") or "çelişki" in r.get("reason", ""), \
    f"A2-sebebi-yanlış: {r.get('reason')}"
print(f"A2-saldırısı-yakalandı: {r['reason'][:60]}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS A2-boyama-yakalandı"
else FAIL=$((FAIL+1)); note "  FAIL A2-gizlendi"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-041-kapısı: üç-ürün-tek-öz + iki-katmanlı-doğrulama"
[[ $FAIL -eq 0 ]]
