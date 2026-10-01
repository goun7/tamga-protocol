#!/bin/bash
# AT-227: FAIL-CLOSED DİKİŞİ — hatalı-state/anahtar → SystemExit (traceback-YOK)
#
# Görev-kaynağı (Lead): "fail-closed testi — hatalı anahtar/secret → SystemExit".
# AT-197 secret eksik/yanlış-değer yollarını RED-reason-code'larıyla-kapsar
# (K1 RED-24, K2/K3 RED-25). Bu-test SystemExit-çıkış-yolunun-KENDİSİNİ-diker:
#   K1  bozuk state.json (geçersiz-JSON) → SystemExit + reason_code=5
#   K2  graph_merkle hafıza-ile-uyumsuz → SystemExit + reason_code=5
#   K3  memory-yapısı-bozuk (dict-değil) → SystemExit + reason_code=5
#   K4  SystemExit-çıktısı structured-JSON (traceback/KeyError-YOK)
#   K5  temiz-paket → GREEN (regresyon-yok; fail-closed-aşırı-tetiklenmiyor)
#
# Doktrin: fail-closed = hata-yüzünden-yeşil-geçme-YOK-AMA-hata-sınıfı-da
# structured-olarak-raporlanmalı (kullanıcıya-traceback-değil-neden).
# Para-YOK. 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at227.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

PY=python3

run_probe() {  # $1=pkg → (rc, son-JSON-satırı) döner; seed quickstart'tan
  local pkg="$1"
  local seed out rc
  seed=$("$PY" -c "import json;print(json.loads(open('$QS_OUT').read())['seed_hex'])")
  out=$("$PY" tamga_runner.py run "$pkg" --seed "$seed" 2>&1)
  rc=$?
  echo "$out" | tail -1 > "$PROBE"
  return $rc
}

note "AT-227: fail-closed dikişi (SystemExit + structured-JSON)"

# K1 — bozuk state.json (geçersiz-JSON) → SystemExit
SB=$(mktemp -d); PROBE="$SB/probe.json"; QS_OUT="$SB/qs.json"
"$PY" tamga_runner.py quickstart "$SB/p1" --name "at226-1" > "$QS_OUT" 2>>"$LOG"
printf '{"memory": bu-geçerli-bir-json-değil\n' > "$SB/p1/state.json"
run_probe "$SB/p1" >> "$LOG" 2>&1; RC1=$?
J1=$("$PY" -c "import json;d=json.load(open('$PROBE'));print(d.get('reason_code'),'|',d.get('op'))" 2>/dev/null || echo "PARSE-FAIL")
[ "$RC1" != "0" ] && echo "$J1" | grep -q "5"
k $? "K1 bozuk state.json → SystemExit rc!=0 reason_code=5" "rc=$RC1 json=$J1"
note "    rc=$RC1 → $J1"

# K2 — graph_merkle hafıza-ile-uyumsuz → SystemExit
"$PY" tamga_runner.py quickstart "$SB/p2" --name "at226-2" > "$QS_OUT" 2>>"$LOG"
"$PY" - "$SB/p2/state.json" <<'PYEOF' >> "$LOG" 2>&1
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); st = json.loads(p.read_text())
st["graph_merkle"] = "0"*64   # sahte-merkle: gerçek-olanın-yerine
p.write_text(json.dumps(st))
PYEOF
run_probe "$SB/p2" >> "$LOG" 2>&1; RC2=$?
J2=$("$PY" -c "import json;d=json.load(open('$PROBE'));print(d.get('reason_code'),'|',d.get('reason','')[:40])" 2>/dev/null || echo "PARSE-FAIL")
[ "$RC2" != "0" ] && echo "$J2" | grep -q "5"
k $? "K2 graph_merkle-uyumsuz → SystemExit rc!=0 reason_code=5" "rc=$RC2 json=$J2"
note "    rc=$RC2 → $J2"

# K3 — graph_merkle yanlış-TÜR (string-değil) → merkle-uyumsuz → SystemExit
"$PY" tamga_runner.py quickstart "$SB/p3" --name "at226-3" > "$QS_OUT" 2>>"$LOG"
"$PY" - "$SB/p3/state.json" <<'PYEOF' >> "$LOG" 2>&1
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); st = json.loads(p.read_text())
st["graph_merkle"] = 12345   # hash-değil → yeniden-hesaplanan-merkle-ile-uyumsuz
p.write_text(json.dumps(st))
PYEOF
run_probe "$SB/p3" >> "$LOG" 2>&1; RC3=$?
J3=$("$PY" -c "import json;d=json.load(open('$PROBE'));print(d.get('reason_code'))" 2>/dev/null || echo "PARSE-FAIL")
[ "$RC3" != "0" ] && echo "$J3" | grep -q "5"
k $? "K3 graph_merkle-yanlış-tür → SystemExit rc!=0 reason_code=5" "rc=$RC3 json=$J3"
note "    rc=$RC3 → $J3"

# K4 — SystemExit-çıktısı structured (traceback-YOK): her-hata-çıktısında
#      'Traceback'-sözcüğü-YOK (kullanıcı-nedenini-okuyabilmeli)
TB=$(grep -ac "Traceback" "$LOG" || true)
[ "$TB" -eq 0 ]
k $? "K4 SystemExit-çıktısı structured (Traceback-YOK, $TB-adet)" "$TB-adet-traceback-bulundu"

# K5 — temiz-paket → GREEN (fail-closed-aşırı-tetiklenmiyor)
"$PY" tamga_runner.py quickstart "$SB/p4" --name "at226-4" > "$QS_OUT" 2>>"$LOG"
run_probe "$SB/p4" >> "$LOG" 2>&1; RC5=$?
J5=$("$PY" -c "import json;d=json.load(open('$PROBE'));print(d.get('ok'), d.get('op'))" 2>/dev/null || echo "PARSE-FAIL")
[ "$RC5" = "0" ] && echo "$J5" | grep -q "True"
k $? "K5 temiz-paket → GREEN rc=0 (regresyon-yok)" "rc=$RC5 json=$J5"
note "    rc=$RC5 → $J5"

rm -rf "$SB"
echo; echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1
