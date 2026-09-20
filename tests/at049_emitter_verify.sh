#!/usr/bin/env bash
# AT-049: emitter-doğrulama — Sester'ın-'listeli-ama-yanlış-emitter'-sınıfının
# bizdeki-kilidi (AT-047'nin-dürüst-düzeltmesiyle-doğrulandı).
#
# Önceki-turda-yanlış-bulgu-yaptım (E1(c)-düzeltme-spec'te): `replace`-5-kez
# 'op'-eşleşmesi-`__pycache__/session.v3.jsonl`'de-göründü-ama-bunlar-DŞH-oturum
# araç-çıktılarıydı (tool/result), Tamga-ledger-kayıtları-değildi. Tam-Sester
# service.py:104-tuzağı: lines.append(f"...")-ilk-argümanını-olay-saymak.
#
# Bu-test-üç-şeyi-kanıtlar:
#  1) LEDGER-FİLTRESİ-çalışıyor: session.v3-gürültüsü-artık-yakalanmıyor
#  2) her-gerçek-op'un-üretim-emitter'ı-var (koddan-kanıtla)
#  3) AYAR-bilinen-cevap: sahte-oturum-gürültüsü-ekleyince-makine-karşı-
#     çıkmıyor (yanlış-emitter-tespiti-beklenir-gibi) — VE-gerçek-ledger-satırı
#     ekleyince-yeni-op-doğru-tanınır
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-049/$D"
LOG=".evidence/AT-049/$D/at049.log"
: > "$LOG"

note "AT-049 emitter-doğrulama (Sester-209-un-üretim-kodlu-karşılığı)"

# 1) üretim: her-op'un-emitter'ı-kanıtlandı
note "1) üretim-koşusu — emitter-tablosu"
python3 tools/emitter_verify.py >> "$LOG" 2>&1
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS emitter-tablosu-temiz"
else FAIL=$((FAIL+1)); note "  FAIL emitter-açığı"; cat "$LOG"; fi

# 2) LEDGER-FİLTRESİ: DSH-oturum-gürültüsü-tanılmıyor
note "2) session.v3-gürültüsü-filtrelendi-mi"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
from spec_needle_machine import check_op_coverage
undoc, found = check_op_coverage()
# replace-gerçek-ledger'da-YOK-tool/RESULT-gürültüsü-idi
assert "replace" not in found, \
    f"LEDGER-FİLTRESİ-bozuk: replace-hâlâ-görünüyor: {sorted(found)}"
assert "charge" in found and "grant" in found
print(f"  filtre-doğru: {sorted(found)}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS gürültü-filtrelendi"
else FAIL=$((FAIL+1)); note "  FAIL gürültü-sızdı"; cat "$LOG"; fi

# 3) AYAR (bilinen-cevap): sahte-oturum-gürültüsü-ekle → yakalanmalı
note "3) ayar — sahte-tool/result-gürültü-ekle"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, tempfile, pathlib, importlib
sys.path.insert(0, "tools")
import emitter_verify as EV
# sahte-DSH-oturum-gürültüsü: op-anahtarlı-ama-seq/prev/h-YOK
d = tempfile.mkdtemp()
fake = pathlib.Path(d) / "session.fake.jsonl"
fake.write_text('{"type":"tool/result","op":"fake-noise"}\n', encoding="utf-8")
# REPO'yu-geçici-dizine-yönlendir-bu-dosyayı-da-tarsın
orig_rg = EV.REPO
class FakeRepo:
    def rglob(self, pat):
        if pat.endswith("*.jsonl"):
            yield fake
        yield from orig_rg.glob(pat)
EV.REPO = FakeRepo()
seen = EV._ledger_evidence()
EV.REPO = orig_rg
assert "fake-noise" not in seen, \
    f"sahte-oturum-gürültüsü-ledger-sayıldı: {sorted(seen)}"
print(f"  sahte-gürültü-filtrelendi: {sorted(seen)}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS ayar-gürültü-yakalandı"
else FAIL=$((FAIL+1)); note "  FAIL ayar-gürültü-sızdı"; cat "$LOG"; fi

# 4) AYAR (code-only-sınıfı): emitter-var-spec'te-yok → yakalanmalı
note "4) ayar — code-only-op (emitter-var-spec'te-yok)"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, pathlib
sys.path.insert(0, "tools")
import emitter_verify as EV
base = pathlib.Path("tests/conformance/spec/LEDGER-SPEC.md").read_text(encoding="utf-8")
# migrate-net'in-TÜM-geçişlerini-sil → gerçek-code-only-ayar
EV._read_spec = lambda: base.replace("migrate-net", "X-ALINMIS")
r = EV.scan()
EV._read_spec = lambda: base
assert any("migrate-net" in p and "SPEC'TE" in p for p in r["problems"]), \
    f"code-only-sınıfı-yakalanmadı: {r['problems']}"
# AT-057-sonrası: scan()-artık-üretim-corpus-boşluğunu-da-raporlar. Bu-hücre
# yalnızca-code-only-SPEC-sınıfını-denetler; üretim-kanıtsızlık-ayrı-sınıftır
# (AT-057'de-test-edilir). Bu-yüzden-SPEC-problemlerine-filtre-koyarız.
spec_probs = [p for p in EV.scan()["problems"] if "SPEC'TE" not in p]
assert not spec_probs, f"üretim-yeşil-olmalıydı (SPEC-dışı): {spec_probs}"
print("  code-only-ayar-yakalandı; üretim-yeşil (SPEC-dışı)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS code-only-ayarı-doğru"
else FAIL=$((FAIL+1)); note "  FAIL code-only-sınıfı-yok"; cat "$LOG"; fi

# 5) AYAR (ters yön): GERÇEK-ledger-satırı-ekle → tanınmalı
note "5) ayar — gerçek-ledger-satırı-tanınmalı"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, tempfile, pathlib
sys.path.insert(0, "tools")
import emitter_verify as EV
d = tempfile.mkdtemp()
good = pathlib.Path(d) / "real.jsonl"
# GERÇEK-Tamga-ledger-satırı: seq+prev+h-üçlüsü-var
good.write_text(
    '{"seq":1,"prev":null,"h":"abc","op":"test-emitter","amount":1}\n',
    encoding="utf-8")
orig_rg = EV.REPO
class FakeRepo:
    def rglob(self, pat):
        if pat.endswith("*.jsonl"):
            yield good
        yield from orig_rg.glob(pat)
EV.REPO = FakeRepo()
seen = EV._ledger_evidence()
EV.REPO = orig_rg
assert "test-emitter" in seen, \
    f"gerçek-ledger-satırı-tanınamadı (filtre-aşırı-katı): {sorted(seen)}"
print(f"  gerçek-satır-tanıldı: {sorted(seen)}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS ters-yön-ayarı-doğru"
else FAIL=$((FAIL+1)); note "  FAIL ters-yön-bozuk"; cat "$LOG"; fi

# 6) Sester'ın-çağrı-içi-iğnesi: negatif-kontroller + run-stdout-düzeltmesi
note "6) çağrı-içi-iğne — yorum/parametre/append-ayırımı (Sester-dersi)"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import emitter_verify as EV
# (a) üç-negatif-kontrol-Sester'ın-ördüğü-örneklerle
fails = EV._test_callin_needle()
assert not fails, f"çağrı-içi-iğne-negatif-kontroller-bozuk: {fails}"
print("  negatif-kontroller: yorum/parametre/append/cok-satirli — HEPSI-DOGRU")
# (b) run-artık-ledger-op-değil (stdout-raporu — E1(d)-düzeltme)
em = EV._code_emitters()
assert "run" not in em, \
    f"run-ledger-op-sayılıyor-ama-out(True,**kw)-stdout'tur: {sorted(em)}"
assert set(em) == {"anchor", "charge", "grant", "migrate-net"}, \
    f"beklenmeyen-emitter-set: {sorted(em)}"
print(f"  ledger-op'ları: {sorted(em)} — run-stdout'tan-çıkarıldı (anchor: RFC-009-pilot)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS çağrı-içi-iğne-doğru"
else FAIL=$((FAIL+1)); note "  FAIL çağrı-içi-iğne"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-049: 'listeli-ama-yanlış-emitter'-sınıfı-kilitlendi"
[[ $FAIL -eq 0 ]]
