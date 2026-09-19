#!/usr/bin/env bash
# AT-002d: Tamga-makbuz-uyumluluğu — keşfedilen-node'un charge-kaydını
# bağımsız doğrular (Faz-3-ön-iş, P9'suz, stdlib-only).
#
# Node "bu-charge-kaydını-ürettim" der. Bu-test üç-şeyi-ölçer:
#   1) üyelik: charge node-ledger'ında-giriş-olarak-bulunmalı
#   2) zincir: node-ledger'ı-verify-mini-ile-bağımsız-doğrulanmalı (stdlib-only)
#   3) parite: kaydın-h'-değeri-bizim-bağımsız-hesabımızla-aynı-olmalı
# Bu, x402/ERC-8004'nin-sorduğu "bu-node-gerçekten-iş-yaptı-mı" sorusunun
# Tamga-cevabıdır: offline, anahtar-yok, uzak-sunucu-yok.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-002d/$D"
LOG=".evidence/AT-002d/$D/at002d.log"
: > "$LOG"

note "AT-002d Tamga-makbuz-uyumluluğu (charge-kayıt-bağımsız-doğrulama)"

W=$(mktemp -d /tmp/at002d-XXXX)
trap 'rm -rf "$W"' EXIT

# 3-kayıt-gerçek-ledger-üret (verify-mini'nin-beklediği-biçimde)
python3 - "$W" <<'PY' >> "$LOG" 2>&1
import sys, json, hashlib
sys.path.insert(0, ".")
from tamga_verify_mini import jcs
W = sys.argv[1]
prev = "0"*64
lines = []
for seq in (1, 2, 3):
    rec = {"seq": seq, "op": "charge", "amount": seq*5, "agent_id": "node-A",
           "note": "faz3"}
    if seq == 2: rec["extra"] = "uye-isaret"
    rec["prev"] = prev
    no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
    rec["h"] = hashlib.sha256((prev + jcs(no_h).decode()).encode()).hexdigest()
    lines.append(json.dumps(rec)); prev = rec["h"]
open(f"{W}/ledger.jsonl", "w").write("\n".join(lines) + "\n")
charge = {"seq": 2, "op": "charge", "amount": 10, "agent_id": "node-A",
          "note": "faz3", "extra": "uye-isaret"}
json.dump(charge, open(f"{W}/charge.json", "w"))
print("  ledger-üretildi")
PY

# 1) check-iyi: GREEN + üyelik + parite
note "1) check-iyi — charge-üyelik+parite GREEN"
if python3 tools/node_receipt_compat.py check "$W/charge.json" "$W/ledger.jsonl" \
     >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS check-iyi GREEN"
else FAIL=$((FAIL+1)); note "  FAIL check-iyi RED"; cat "$LOG"; fi

# 2) membership-RED: charge-ledger'da-yok
note "2) membership-RED — charge-ledger'da-değil"
python3 -c "
import json; c=json.load(open('$W/charge.json')); c['note']='YANLIS'
json.dump(c, open('$W/charge-yok.json','w'))" >> "$LOG" 2>&1
if python3 tools/node_receipt_compat.py check "$W/charge-yok.json" \
     "$W/ledger.jsonl" >> "$LOG" 2>&1; then
  FAIL=$((FAIL+1)); note "  FAIL membership-yakalanmadı (GREEN-üretti)"; cat "$LOG"
else PASS=$((PASS+1)); note "  PASS membership-RED-yakalandı"; fi

# 3) kırık-zincir-RED: node-amount-üzerinde-yalan-söylüyor
note "3) kırık-zincir-RED — node-kurcalama-yakala"
python3 -c "
lines=[l for l in open('$W/ledger.jsonl') if l.strip()]
lines[1]=lines[1].replace('\"amount\": 10','\"amount\": 999')
open('$W/ledger-kirik.jsonl','w').writelines(lines)" >> "$LOG" 2>&1
if python3 tools/node_receipt_compat.py ledger "$W/ledger-kirik.jsonl" \
     >> "$LOG" 2>&1; then
  FAIL=$((FAIL+1)); note "  FAIL kırık-zincir-yakalanmadı"; cat "$LOG"
else PASS=$((PASS+1)); note "  PASS kırık-zincir-RED-yakalandı"; fi

# 4) digest-parite-RED: kaydın-h'-üzerinde-yanlış
note "4) digest-parite-RED — kayıt-h-yanlış"
python3 -c "
import json
lines=[l for l in open('$W/ledger.jsonl') if l.strip()]
r=json.loads(lines[2]); r['h']='0'*64; lines[2]=json.dumps(r)+'\n'
open('$W/ledger-h-yok.jsonl','w').writelines(lines)" >> "$LOG" 2>&1
if python3 tools/node_receipt_compat.py check "$W/charge.json" \
     "$W/ledger-h-yok.jsonl" >> "$LOG" 2>&1; then
  FAIL=$((FAIL+1)); note "  FAIL parite-yakalanmadı"; cat "$LOG"
else PASS=$((PASS+1)); note "  PASS digest-parite-RED-yakalandı"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-002d-kapısı: charge-kayıt-bağımsız-doğrulama (P9'suz-ön-iş)"
[[ $FAIL -eq 0 ]]
