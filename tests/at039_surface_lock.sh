#!/usr/bin/env bash
# Yüzey-sabitleme (Veridict'in-önerisi): doğrulama-arayüzümüzü-testle-kilitle.
# "İyi-niyet-çürür, testler-çürmez" — sovereign_verify'un-çağırdığı-yüzeyler
# değişirse-kendi-CI'ımız-kırılır, wrapper-değil.
#
# Sabitlenenler (sözleşme):
#   1. tools/attest_verify_bagimsiz.py <claim.json>  → exit-0 + JSON({verdict,...})
#   2. tamga_verify_mini.verify(path) → (tip|"", reason)   [stdlib import]
#   3. tools/registration_v1.py produce|verify            [AT-002a]
#   4. tools/node_receipt_compat.py check|ledger          [AT-002d]
#   5. sovereign_verify'un çağırdığı sester yüzeyi: Ledger(path).verify_chain()
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-039/$D"
LOG=".evidence/AT-039/$D/at039.log"
: > "$LOG"

note "AT-039 yüzey-sabitleme (doğrulama-arayüzleri-testle-kilitli)"

# 1) attest_verify_bagimsiz: CLI-şekli-sabit — tek-argüman + JSON-çıkış
note "1) attest_verify_bagimsiz CLI-yüzeyi"
if python3 -c "
import subprocess, sys, json
# çağrı-şekli: tam-2-argüman (script + claim-yolu)
p = subprocess.run([sys.executable, 'tools/attest_verify_bagimsiz.py',
                    '.evidence/AT-030/2026-09-19/prod1.json'],
                   capture_output=True, text=True)
assert p.returncode == 0, f'red-çıkış: {p.returncode}'
d = json.loads(p.stdout)
# normatif-alanlar (wrapper-bunları-okur)
for k in ('verdict', 'reason', 'signer_recover'):
    assert k in d, f'normatif-alan-kayıp: {k}'
assert d['verdict'] == 'GREEN', f'beklenen-GREEN: {d[\"verdict\"]}'
print('  CLI: rc0 + GREEN + normatif-alanlar-mevcut')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS attest_verify_bagimsiz-yüzeyi"
else FAIL=$((FAIL+1)); note "  FAIL attest-CLI-yüzeyi"; cat "$LOG"; fi

# 2) argüman-sayısı-sözleşmesi: 2-dışında-RED-olmalı (kırılma-erken-uyarı)
note "2) argüman-sözleşmesi — yanlış-argüman-RED"
if python3 -c "
import subprocess, sys
p = subprocess.run([sys.executable, 'tools/attest_verify_bagimsiz.py'],
                   capture_output=True, text=True)
assert p.returncode != 0, 'argümansız-RED-üretmedi'
print('  argümansız: rc', p.returncode, '(RED-doğru)')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS argüman-sözleşmesi"
else FAIL=$((FAIL+1)); note "  FAIL argüman-sözleşmesi"; cat "$LOG"; fi

# 3) tamga_verify_mini: import-yüzeyi-sabit — verify(path) → (tip, reason)
note "3) tamga_verify_mini import-yüzeyi"
if python3 -c "
from tamga_verify_mini import verify
r = verify('.evidence/AT-002d/2026-09-19/at002d.log')  # herhangi-geçerli-dosya
assert isinstance(r, tuple) and len(r) == 2, f'dönüş-şekli-bozuk: {r!r}'
tip, reason = r
assert isinstance(tip, str) and isinstance(reason, str)
print('  verify(path) → (str, str):', tip[:12], '|', reason[:30])
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS verify-mini-import-yüzeyi"
else FAIL=$((FAIL+1)); note "  FAIL verify-mini-yüzeyi"; cat "$LOG"; fi

# 4) registration_v1: produce|verify-altkomut-yüzeyi
note "4) registration_v1 altkomut-yüzeyi"
if python3 -c "
import subprocess, sys, json, tempfile, os
# kendi-fixture'ını-üret (dış-temp'e-bağımlı-değil — AT-038-dersi)
W = tempfile.mkdtemp(prefix='at039-')
mf = os.path.join(W, 'manifest.json')
rf = os.path.join(W, 'reg.json')
open(mf, 'w').write(json.dumps({'package': {'name': 'yuzey-sabitle'},
                                'summary': 'sabitleme', 'runtime': {'min_proof_level': 1}}))
p = subprocess.run([sys.executable, 'tools/registration_v1.py', 'produce', mf],
                   capture_output=True, text=True)
assert p.returncode == 0, f'produce-RED: {p.stderr[:120]}'
open(rf, 'w').write(p.stdout)
d = json.loads(p.stdout)
assert d['type'] == 'agent' and 'x402Support' in d
v = subprocess.run([sys.executable, 'tools/registration_v1.py', 'verify', rf],
                   capture_output=True, text=True)
assert v.returncode == 0, f'verify-RED: {v.stderr[:120]}'
print('  produce|verify: rc0 + normatif-alanlar')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS registration-v1-yüzeyi"
else FAIL=$((FAIL+1)); note "  FAIL registration-yüzeyi"; cat "$LOG"; fi

# 5) node_receipt_compat: check|ledger-altkomut-yüzeyi
note "5) node_receipt_compat altkomut-yüzeyi"
if python3 -c "
import subprocess, sys, json, os
os.makedirs('/tmp/at039', exist_ok=True)
p = subprocess.run([sys.executable, 'tools/node_receipt_compat.py', 'ledger',
                    '/tmp/at002d-dbg/ledger.jsonl'], capture_output=True, text=True)
assert p.returncode == 0, f'ledger-RED: {p.stdout[:100]}'
d = json.loads(p.stdout)
assert 'ok' in d and 'ledger_tip' in d
print('  check|ledger: rc0 + normatif-alanlar')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS node-receipt-yüzeyi"
else FAIL=$((FAIL+1)); note "  FAIL node-receipt-yüzeyi"; cat "$LOG"; fi

# 6) sester-yüzeyi-sabit (sovereign_verify'un-çağırdığı)
note "6) sester-yüzeyi — Ledger(path).verify_chain()"
if python3 -c "
from sester.ledger import Ledger
lg = Ledger('/tmp/sg-sester.db')
try: ok = lg.verify_chain()
finally: lg.close()
assert isinstance(ok, bool)
print('  Ledger(path).verify_chain() → bool:', ok)
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS sester-yüzeyi-sabit"
else
  # Sester-kurulu-değilse-bu-yüzey-işaretlenir-ama-suite'i-kırmaz:
  # Tamga'nın-kendi-CI'ında-Sester-olmayabilir; sovereign_verify-zaten-bunu
  # "sester-kurulu-değil"-ile-eksik-halleder. Kırılma-ancak-Sester-kurulu-iken
  # ve-yüzey-değişmişse-bildirir.
  if grep -q "ImportError\|ModuleNotFound" "$LOG"; then
    note "  PASS sester-yüzey-işaretli (kurulu-değil — izole-geç)"
  else
    FAIL=$((FAIL+1)); note "  FAIL sester-yüzeyi-bozuk"; cat "$LOG"
  fi
fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-039-kapısı: doğrulama-yüzeyleri-testle-sabit"
[[ $FAIL -eq 0 ]]
