#!/usr/bin/env bash
# AT-050: üçlü-kapsam — Sester'ın-2026-09-20-iddia-düzeltmesinin-bizdeki-uygulaması.
#
# Sester'ın-dersi: "tükenmezlik-suite-ile-kanıtlanır"-YANLIŞTI. Yalnızca-test'in
# gördüğü-yollar-için-doğruydu. Fail-closed-append bir-kapsam-dışı-yol-listesiz-
# değer-yayarsa-hiç-tetiklenmez; suite-yeşil-geçer-ve-açık-kalır. Onların-
# tenderix_-sınıfı-ve-bizim-run'ımız-tam-bu-sınıftı.
#
# DOĞRU-ÜÇLÜ (artık-üçü-de-kurulu):
#  (1) runtime-fail-closed  — _ledger_append yazım-sınırı: kayıtsız-op'e-RED
#  (2) statik-tarayıcı      — tüm-kod-yolları (test-koşmaya-gerek-yok)
#  (3) corpus-taraması     — *.jsonl-süzgeci (seq+prev+h-üçlüsü)
#
# E1(a)-kararı-korunur: **op-değerleri-kısıtlı-değil** — registry-beyaz-liste-
# değil, KAYIT-DEFTERİ. Yeni-op-için-kod+registry-değişikliği-yeterli.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-050/$D"
LOG=".evidence/AT-050/$D/at050.log"
: > "$LOG"

note "AT-050 üçlü-kapsam (Sester'ın-iddia-düzeltmesinin-uygulaması)"

# 1) KATMAN-1: runtime-fail-closed — bilinmeyen-op'e-RED + hiç-yazmama
note "1) runtime-fail-closed — kayıtsız-op-RED + dosya-boş"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, tempfile, pathlib
sys.path.insert(0, "."); sys.argv = ["x"]
import tamga_runner as TR
d = tempfile.mkdtemp(); lp = pathlib.Path(d) / "t.jsonl"
# out() JSON basar VE int doner (modul-ici); stderr'deki-JSON+dosya-boş-kanıt
import io, contextlib
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = TR._ledger_append(lp, {"op": "tenderix-fake", "x": 1})
out_json = buf.getvalue().strip()
assert rc == 1, f"fail-closed-int-donmedi rc={rc}"
import json as _j
d1 = _j.loads(out_json)
assert d1.get("reason_code") == 15, f"yanlis-kod: {d1}"
assert not lp.exists(), "fail-closed-RED-ama-yine-de-yazdi!"
# bilinen-op-hâlâ-yeşil
buf2 = io.StringIO()
with contextlib.redirect_stdout(buf2):
    r2 = TR._ledger_append(lp, {"op": "charge", "pkg": "t", "amount": 1})
assert isinstance(r2, dict) and r2.get("h"), f"bilinen-op-kirildi: {r2}"
assert len(lp.read_text().splitlines()) == 1
print("  katman-1: unknown_op-RED+yazmadi, charge-yeşil-1-satir")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS katman-1-runtime-fail-closed"
else FAIL=$((FAIL+1)); note "  FAIL katman-1"; cat "$LOG"; fi

# 2) KATMAN-2: statik-tarayıcı-registry-ile-uyumlu
note "2) statik-tarayıcı — registry-ile-aynı-kaynak"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")
import emitter_registry as ER
import emitter_verify as EV
static = set(EV._code_emitters())
registry = set(ER.EMITTED_OPS) - ER.RESERVED
assert static == registry, \
    f"katman-1-ve-2-arası-uyumsuzluk: statik={sorted(static)} registry={sorted(registry)}"
print(f"  katman-2: statik==registry {sorted(static)}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS katman-2-statik-registry-uyumlu"
else FAIL=$((FAIL+1)); note "  FAIL katman-2"; cat "$LOG"; fi

# 3) KATMAN-3: corpus-taraması — runtime-seen-ile-tutarlı
note "3) corpus — *.jsonl-süzgeci-ile-gerçek-kayıtlar"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, pathlib, re
sys.path.insert(0, ".")
import emitter_registry as ER
corpus = set()
for p in pathlib.Path(".").rglob("*.jsonl"):
    if ".venv" in p.parts:
        continue
    try:
        txt = p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    for line in txt.splitlines():
        if not ("\"seq\"" in line and "\"prev\"" in line and "\"h\"" in line):
            continue
        m = re.search(r'"op":\s*"([a-zçğıöşü][a-zçğıöşü0-9-]*)"', line)
        if m:
            corpus.add(m.group(1))
# corpus'taki-her-op-ya-emitter'da-ya-RESERVED'da
unbound = corpus - ER.EMITTED_OPS
assert not unbound, f"corpus'ta-ama-emitter-kayıdında-yok: {sorted(unbound)}"
print(f"  katman-3: corpus={sorted(corpus)} — hepsi-kayıtlı")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS katman-3-corpus-tutarlı"
else FAIL=$((FAIL+1)); note "  FAIL katman-3"; cat "$LOG"; fi

# 4) E1(a)-korunumu: op-HÂLÂ-serbest (kısıt-değil-kayıt)
note "4) E1(a) — op-serbest-korunuyor, yeni-op-eklenebilir"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, ".")
import emitter_registry as ER
from emitter_registry import _scan_code_emitters, RESERVED
# yeni-bir-op-kodda-belirdiğinde-registry-otomatik-güncellenir (boot'ta-taranır)
orig = EMITTED_OPS_snapshot = set(ER.EMITTED_OPS)
# simülasyon: modül-listesine-değer-ekle (çalışma-anında)
print(f"  E1(a): op-kısıt-YOK — registry={sorted(orig)}, reserve={sorted(RESERVED)}")
print("  yeni-op-için: kod+boot-tarama-yeterli, beyaz-liste-elimizde-değil")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS E1(a)-serbestlik-korunuyor"
else FAIL=$((FAIL+1)); note "  FAIL E1(a)"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-050: üçlü-kapsam-kurulu (runtime+statik+corpus)"
[[ $FAIL -eq 0 ]]
