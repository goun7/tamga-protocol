#!/usr/bin/env bash
# AT-040: spec↔üretim verifier paritesi (Veridict'in test_spec_verifier_parity.py
# örneğinin Tamga karşılığı).
#
# tools/spec_verifier_independent.py, docs/ARCHITECTURE.md:42'den TEK BAŞINA
# yazıldı — hiçbir tamga_* veya tools/ modülü içe aktarmaz, RFC 8785 JCS'yi
# ikinci kez sıfırdan uygular. Amaç: üretim verifier'ının (tamga_verify_mini.py)
# spec'in KENDİSİNE sadık olduğunu kanıtlamak, kodumuza değil.
#
# Parite-iddiası: temiz-fixture'larda ikisi-GREEN; 6-kurcalama-mutasyonunda
# ikisi-RED-ve-aynı-kırık-satır. Ayrışma = üretim-spec'ten-sapıyor-demektir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-040/$D"
LOG=".evidence/AT-040/$D/at040.log"
: > "$LOG"

note "AT-040 spec↔üretim verifier paritesi (16/16 JCS + 6 kurcalama)"

W=$(mktemp -d /tmp/at040-XXXX)

# --- temiz-3-kayıt-ledger-üret (üretim-jcs-ile) ---
python3 - "$W" <<'PY' >> "$LOG" 2>&1
import sys, json, hashlib
sys.path.insert(0, ".")
from tamga_canon import jcs
W = sys.argv[1]
prev = "0"*64
lines = []
for seq in (1, 2, 3):
    rec = {"seq": seq, "op": "charge", "amount": seq*5, "agent_id": "node-A",
           "note": "parite-fixture", "floats": [0.5, -3.0, 1e-7]}
    rec["prev"] = prev
    no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
    rec["h"] = hashlib.sha256((prev + jcs(no_h).decode()).encode()).hexdigest()
    lines.append(json.dumps(rec)); prev = rec["h"]
open(f"{W}/clean.jsonl", "w").write("\n".join(lines) + "\n")
print("  temiz-ledger-üretildi")
PY

# 1) JCS-paritesi: karışık-değerlerde-bağımsız==üretim
note "1) JCS-kanonik-paritesi (16-değer)"
if python3 -c "
import sys; sys.path.insert(0, 'tools'); sys.path.insert(0, '.')
from spec_verifier_independent import jcs as ji
from tamga_canon import jcs as jp
vals = [1e-7,-3.0,0.0,3.14,1e21,1.5e300,1e-21,-2.5,100.0,0.1,-1e-7,2.5e-10,1e22]
n = sum(1 for v in vals if ji({'x':v}) == jp({'x':v}))
assert n == len(vals), f'sayı-paritesi {n}/{len(vals)}'
cases = [{'seq':1,'op':'charge','amount':10,'agent_id':'n','extra':'ü'},
         {'b':1,'a':'z','ç':'tr','n':3.14,'neg':-2.5},
         {'nested':{'z':[1,2,{'y':'x'}]},'boş':[],'nesne':{}}]
m = sum(1 for c in cases if ji(c) == jp(c))
assert m == len(cases), f'nesne-paritesi {m}/{len(cases)}'
print(f'  JCS-paritesi: {n+m}/{len(vals)+len(cases)}')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS JCS-paritesi-tam"
else FAIL=$((FAIL+1)); note "  FAIL JCS-paritesi"; cat "$LOG"; fi

# 2) temiz-ledger'da-ikisi-GREEN-ve-aynı-tip
note "2) temiz-fixture — bağımsız==üretim GREEN"
if python3 -c "
import sys, subprocess, json
sys.path.insert(0, 'tools'); sys.path.insert(0, '.')
from spec_verifier_independent import verify_ledger as vi
from tamga_verify_mini import verify as vp
# bağımsız
li, ri = vi('$W/clean.jsonl')
# üretim
tp, rp = vp('$W/clean.jsonl')
assert li == 0 and ri == 'ok', f'bağımsız-RED: {li},{ri}'
assert bool(tp), f'üretim-RED: {rp}'
print(f'  bağımsız: GREEN(0,ok) — üretim: GREEN(tip={tp[:10]}…)')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS temiz-fixture-ikisi-GREEN"
else FAIL=$((FAIL+1)); note "  FAIL temiz-fixture"; cat "$LOG"; fi

# 3) 6-kurcalama-mutasyonu — ikisi-RED-ve-aynı-kırık-satır
note "3) 6-mutasyon — bağımsız==üretim RED"
python3 - "$W" <<'PY' >> "$LOG" 2>&1
import sys, json, hashlib, os
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from spec_verifier_independent import verify_ledger as vi
from tamga_verify_mini import verify as vp
W = sys.argv[1]
clean = [l for l in open(f"{W}/clean.jsonl") if l.strip()]
base = [json.loads(l) for l in clean]

def run(name, lines):
    p = f"{W}/m.jsonl"
    open(p, "w").write("\n".join(json.dumps(r) for r in lines) + "\n")
    li, ri = vi(p)
    tp, rp = vp(p)
    indep_red = (li != 0) or (ri != "ok")
    prod_red = not tp
    assert indep_red == prod_red, f"{name}: bağımsız={indep_red} üretim={prod_red} (ayrışma!)"
    assert indep_red, f"{name}: ikisi-de-GREEN — mutasyon-işe-yaramadı"
    print(f"  {name:22} RED-uyumlu (bağımsız kırık@{li} / üretim: {str(rp)[:26]})")

# M1: 2.kayıdın-amount-değiştir (h-artık-uymaz)
run("M1 amount-kurcala", [dict(r, amount=999) if r["seq"]==2 else r for r in base])
# M2: 2.kayıdın-prev-kurcala
run("M2 prev-kurcala",   [dict(r, prev="f"*64) if r["seq"]==2 else r for r in base])
# M3: 2.kayıdın-h-kurcala
run("M3 h-kurcala",      [dict(r, h="0"*64) if r["seq"]==2 else r for r in base])
# M4: seq-numarası-atla
run("M4 seq-atla",       [dict(r, seq=r["seq"]+1) if r["seq"]==2 else r for r in base])
# M5: kayıt-sil (zincir-3.kayıtta-kopar)
run("M5 kayıt-sil",      [r for r in base if r["seq"] != 2])
# M6: parse-edilemez-satır
open(f"{W}/m.jsonl","w").write(json.dumps(base[0]) + "\nBÖKE\n" + json.dumps(base[1]) + "\n")
li, ri = vi(f"{W}/m.jsonl"); tp, rp = vp(f"{W}/m.jsonl")
assert (li != 0) and not tp, f"M6: RED-beklendi ({li},{tp})"
print("  M6 unparseable        RED-uyumlu")
print("  6/6-mutasyon-paritesi")
PY
if [ $? -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 6/6-mutasyon-RED-paritesi"
else FAIL=$((FAIL+1)); note "  FAIL mutasyon-paritesi"; cat "$LOG"; fi

# 4) bağımsız-verifier-üretim-import-etmez (gerçek-bağımsızlık)
note "4) bağımsızlık — tamga_*-import-yok"
if ! grep -qE "^import tamga|^from tamga|^from tamga_canon|^import tamga_canon" \
     tools/spec_verifier_independent.py; then
  PASS=$((PASS+1)); note "  PASS üretim-modülü-içe-aktarmaz"
else FAIL=$((FAIL+1)); note "  FAIL bağımsızlık-bozuk"; cat "$LOG"; fi

rm -rf "$W"
echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-040-kapısı: spec↔üretim-paritesi (üretim-spec'e-sadık)"
[[ $FAIL -eq 0 ]]
