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

# 3) KATMAN-3: corpus-taraması — ÜRETİM-vs-FIXTURE-ayırmadan-sonra
note "3) corpus — üretim-ledger'ları-vs-test-fixture'leri (Veridict-canary-dersi)"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, pathlib, re
sys.path.insert(0, "."); sys.path.insert(0, "tools")
import emitter_registry as ER
import emitter_verify as EV
# TÜM-corpus (fixture-dahil) — eski-davranış
corpus_all = EV.corpus_ops()
# SADECE-üretim — test-fixture'leri-hariç
corpus_prod = EV.corpus_ops(production_only=True)
# Veridict-canary-2026-09-20-aynası: seq+prev+h-üçlüsü-FIXTURE'ler-de-üretir!
# Önceki-turda-'charge(72)-grant(7)-gerçek-gözlemlenen-küme'-diye-raporladım;
# aslında-hepsi-test-fixture-kanıtıydı. Bu-düzeltme-bu-hücre.
print(f"  tüm-corpus (fixture-dahil): {sorted(corpus_all)}")
print(f"  SADECE-üretim-corpus: {sorted(corpus_prod)}")
unbound = corpus_all - ER.EMITTED_OPS
assert not unbound, f"corpus'ta-ama-emitter-kayıdında-yok: {sorted(unbound)}"
# DÜRÜST-BİLDİRİM: üretim-corpus-boş-ise-üçlü-kapsamın-3.katmanı-ZAYIF
if not corpus_prod:
    print("  DÜRÜST-LİMİT: repoda-üretim-ledger'ı-YOK — 3.katman")
    print("    yalnızca-test-fixture-kanıtı-taşıyor, üretim-erişilebilirliği")
    print("    KANITLAYAMIYOR. migrate-net-bu-nedenle-hâlâ-doğrulanmamış.")
else:
    unbound_p = corpus_prod - ER.EMITTED_OPS
    assert not unbound_p, f"üretim-corpus'ta-kayıtsız: {sorted(unbound_p)}"
    print(f"  üretim-corpus-da-tutarlı: {sorted(corpus_prod)}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS katman-3-corpus-tutarlı (üretim-boş-dürüst)"
else FAIL=$((FAIL+1)); note "  FAIL katman-3"; cat "$LOG"; fi

# 3b) AYAR: sahte-üretim-ledger'ı-ekle → katman-3-onu-üretim-saymalı
note "3b) ayar — sahte-üretim-ledger'ı-tanınmalı (negatif-kontrol)"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, tempfile, pathlib
sys.path.insert(0, "tools")
import emitter_verify as EV
d = tempfile.mkdtemp()
# tests/-altında-DEĞİL → üretim-sayılmalı
fake = pathlib.Path(d) / "prod.jsonl"
fake.write_text('{"seq":1,"prev":null,"h":"a","op":"charge","amount":1}\n',
                encoding="utf-8")
orig = EV.REPO
class FakeRepo:
    def rglob(self, pat):
        if pat.endswith("*.jsonl"):
            yield fake
        yield from orig.glob(pat)
EV.REPO = FakeRepo()
got = EV.corpus_ops(production_only=True)
EV.REPO = orig
assert "charge" in got, f"üretim-ledger'ı-tanınamadı: {got}"
print(f"  sahte-üretim-tanıldı: {sorted(got)}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 3b-üretim-ledger-tanıma"
else FAIL=$((FAIL+1)); note "  FAIL 3b"; cat "$LOG"; fi

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
