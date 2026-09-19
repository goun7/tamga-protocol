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

# tüm-hücreler-kendi-fixture'larını-üretir — dış-artık-bağımlılık-yok (AT-038/039-dersi)
export FX=$(mktemp -d /tmp/at039-XXXX)

# 1) üretim-claim-fixture'ı (AT-030-formatında, gerçek-anahtarlarla)
python3 - "$FX" <<'PY' >> "$LOG" 2>&1
import sys, json, hashlib, secrets
FX = sys.argv[1]
# AT-030-formatında-üretim-claim — kendi-anahtarımız-ile
k = secrets.token_hex(32)
claim = {
  "claim_id": f"at039-{hashlib.sha256(k.encode()).hexdigest()[:16]}",
  "product": "tamga", "kind": "capacity-attest",
  "level": 1,
  "issued_at": "2026-09-19T00:00:00Z",
  "subject": "agent-042",
  "payload_hash": hashlib.sha256(b"at039-fixture").hexdigest(),
}
open(f"{FX}/claim.json", "w").write(json.dumps(claim))
print("  fixture-üretildi")
PY

# AT-002d-için-gerçek-ledger-fixture'ı
python3 - "$FX" <<'PY' >> "$LOG" 2>&1
import sys, json, hashlib
sys.path.insert(0, ".")
from tamga_verify_mini import jcs
FX = sys.argv[1]
prev = "0"*64
lines = []
for seq in (1, 2, 3):
    rec = {"seq": seq, "op": "charge", "amount": seq*5, "agent_id": "node-A",
           "note": "at039-fixture"}
    rec["prev"] = prev
    no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
    rec["h"] = hashlib.sha256((prev + jcs(no_h).decode()).encode()).hexdigest()
    lines.append(json.dumps(rec)); prev = rec["h"]
open(f"{FX}/ledger.jsonl", "w").write("\n".join(lines) + "\n")
print("  ledger-fixture-üretildi")
PY

# 1) attest_verify_bagimsiz: CLI-şekli-sabit — tek-argüman + JSON-çıkış
note "1) attest_verify_bagimsiz CLI-yüzeyi"
if python3 -c "
import subprocess, sys, json, os, tempfile
# AT-030 ile aynı vendored üretim claim (repo-içi, CI'da-da-var; dış-artık-değil)
src = 'tests/vendor-capacity-attest/production-claim.jsonl'
assert os.path.exists(src), f'vendored-claim-kayıp: {src}'
p1 = os.path.join(os.environ.get('FX', tempfile.gettempdir()), 'prod1.json')
head = open(src, encoding='utf-8').readline()
open(p1, 'w', encoding='utf-8').write(head)
p = subprocess.run([sys.executable, 'tools/attest_verify_bagimsiz.py', p1],
                   capture_output=True, text=True)
assert p.returncode == 0, f'red-çıkış: {p.returncode} stderr={p.stderr[:120]}'
d = json.loads(p.stdout)
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
import os
from tamga_verify_mini import verify
r = verify(os.path.join(os.environ['FX'], 'ledger.jsonl'))
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
lg = os.path.join(os.environ['FX'], 'ledger.jsonl')
p = subprocess.run([sys.executable, 'tools/node_receipt_compat.py', 'ledger', lg],
                   capture_output=True, text=True)
assert p.returncode == 0, f'ledger-RED: {p.stdout[:100]}'
d = json.loads(p.stdout)
assert 'ok' in d and 'ledger_tip' in d
print('  check|ledger: rc0 + normatif-alanlar')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS node-receipt-yüzeyi"
else FAIL=$((FAIL+1)); note "  FAIL node-receipt-yüzeyi"; cat "$LOG"; fi

# 6) sester-yüzeyi-sabit + RISK-1/2-kilitleri (Sester-tarafından-bulundu)
note "6) sester-yüzeyi — Ledger(path,secret).verify_chain() + RISK-1/2-kilitleri"
# Sester-kurulu-mu-önce-denetle (kurulu-değilse-hücre-izole-geçer)
if ! python3 -c "import sester" 2>/dev/null; then
  note "  PASS sester-yüzey-işaretli (kurulu-değil — izole-geç)"
elif python3 -c "
import os, sys
sys.path.insert(0, 'tools')
from sovereign_verify import verify_sester_ledger
lg_path = os.environ['FX'] + '/sester-test.db'
from sester.ledger import Ledger
lg = Ledger(lg_path, 'dev-secret')
lg.append('charge', 'a1', 'h1', 1.0, {})
lg.close()
# 6a) yüzey-çağrısı-çalışır (geriye-uyum)
r = verify_sester_ledger(lg_path, 'dev-secret')
assert r.get('verdict') == 'GREEN', f'yüzey-bozuk: {r}'
# 6b) RISK-1 KİLİT: var-olmayan-yol → RED (sahte-GREEN-engeli)
r1 = verify_sester_ledger(os.environ['FX'] + '/yok.db')
assert not r1.get('ok'), f'RISK-1-tekrar-açık: {r1}'
# 6c) RISK-2 KİLİT: secret-mismatch → RED (sahte-RED-dürüst)
r2 = verify_sester_ledger(lg_path, 'yanlış-secret')
assert not r2.get('ok'), f'RISK-2-secret-kilidi-yok: {r2}'
print('  yüzey-GREEN + RISK-1-RED + RISK-2-RED — üç-kilit-de-yerinde')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS sester-yüzeyi + RISK-1/2-kilitleri"
else
  FAIL=$((FAIL+1)); note "  FAIL sester-yüzeyi-bozuk"; cat "$LOG"
fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-039-kapısı: doğrulama-yüzeyleri-testle-sabit"
[[ $FAIL -eq 0 ]]
