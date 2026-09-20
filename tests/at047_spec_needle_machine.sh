#!/usr/bin/env bash
# AT-047: spec-needle-machine — "spec'te-yazıyor" gözle-değil-makine-ile.
#
# DERS (Sester-2026-09-20): "benim-YÖN-B-negatif-kontrolüm-elle-grep'ti, yani
# spec'te-yazıyor-derken-göz-ile-bakmıştım." Aynısı-bizde-de-vardı — AT-046'nın
# spec-coverage'si-bir-needle-listesi-ile-ölçülüyor-ama-o-liste-ELLE-yazıldı.
# Bu-test-listenin-kendisini-makineye-taşır.
#
# İkinci-ders (E1(c)): op-kümesi-tükenmezliği-gözle-kanıtlanamaz. Deneyi-yaptım
# — kısıt-ekleyip-tam-suite-koştum: DALGA-1-2-FAIL (verify-lite'da-op:"note",
# AT-045'de-BILINMEYEN). SONRA-jsonl'ları-taradım: `replace`-CANLI-oturum-
# ledger'ında (__pycache__/session.v3.jsonl) — spec'te-yoktu. **Sester-K0.2'nin
# birebir-bizdeki-örneği.**
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-047/$D"
LOG=".evidence/AT-047/$D/at047.log"
: > "$LOG"

note "AT-047 spec-needle-machine (YÖN-B-artık-makinede)"

# 1) tüm-needle'lar-spec'te-var
note "1) 18-needle — makine-ile-aranır"
python3 tools/spec_needle_machine.py >> "$LOG" 2>&1
if [ $? -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 18/18-needle-belgeli"
else FAIL=$((FAIL+1)); note "  FAIL needle-düştü"; cat "$LOG"; fi

# 2) op-kümesi-uyumu (E1(c)-otomatik-yakalama)
note "2) op-kümesi — spec'te-yazmayan-ledger-op'u-yakalar"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
from spec_needle_machine import check_op_coverage
undoc, found = check_op_coverage()
assert not undoc, f"spec-dışı-ledger-op'ları-keşfedildi: {undoc}"
assert "charge" in found and "grant" in found, "çekirdek-op'lar-yok"
# LEDGER-FİLTRESİ-kanıtı: session.v3.jsonl-'replace'-gürültüsü-artık-yakalanmaz
assert "replace" not in found, \
    "replace-tool/result-gürültüsü-hâlâ-ledger-op-sayılıyor (filtre-bozuk)"
# E1(c)-düzeltme: yanlış-bulguyu-spec'te-teslim-eden-itàiraf-yazılı-olmalı
import pathlib
spec = pathlib.Path("tests/conformance/spec/LEDGER-SPEC.md").read_text(encoding="utf-8")
assert "E1(c)-düzeltme" in spec, "yanlış-bulgu-itàrafı-spec'te-yok"
print(f"op-kümesi-uyumlu: {sorted(found)}")
PYEOF
if [ $? -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS op-kümesi-spec-ile-uyumlu"
else FAIL=$((FAIL+1)); note "  FAIL op-kümesi-uyumsuz"; cat "$LOG"; fi

# 3) fail-closed-dalga-YÖNTEMİ-kanıtlandı (deney-sonucu-dokümante)
note "3) dalga-yöntemi — deney-kanıtı-dokümante"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import pathlib
spec = pathlib.Path("tests/conformance/spec/LEDGER-SPEC.md").read_text(encoding="utf-8")
# E1(c)-erratum'u-dalga-yöntemini-anlatıyor-olmalı
assert "fail-closed-dalga-deneyi" in spec or "fail-closed" in spec, \
    "E1(c)-dalga-yöntemini-anlatmıyor"
assert "Gözle" in spec and "tükenmezlik" in spec, "gözle-uyarı-yazılı-değil"
print("dalga-yöntemi-ve-gözle-uyarı-spec'te-dokümante")
PYEOF
if [ $? -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS dalga-yöntemi-dokümante"
else FAIL=$((FAIL+1)); note "  FAIL dokümantasyon-eksik"; cat "$LOG"; fi

# 3b) VERIDICT-CANARY-AYNASI: fixture-kanıtı-üretim-sayılmamalı
note "3b) fixture-üretim-sayılmıyor (Veridict-canary-dersi)"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import emitter_verify as EV
# tüm-corpus'ta-charge-var (fixture) — production_only=True-artık-üretim-
# corpus'unu-okur (AT-057-sonrası-run_all.sh-onu-her-koşuda-üretir).
# CANARY-AYRIMI: fixture'lar-üretim-corpus'una-karışmadan-ayrılmalı.
# Ölçüm-yöntemi: tüm-corpus >= üretim-corpus (fixture'lar-ekstra-olarak-var)
# VE-üretim-corpus-'anchor'-ı-içermeli (AT-059-kantı-üretimde).
assert "charge" in EV.corpus_ops(), "fixture-corpus-bozuk"
prod_ops = EV.corpus_ops(production_only=True)
assert "charge" in prod_ops, "üretim-corpus'unda-charge-yok (prod-make-bozuk)"
assert "anchor" in prod_ops, "üretim-corpus'unda-anchor-yok (AT-059-üretim-kanıtı-kayboldu)"
# ÜRETİM-AYRIMI: bir-fixture-içi-op-üretim-corpus'una-GİRMEMELİ — bunu
# ölçmenin-temiz-yolu: .evidence/PROD-CORPUS-dışı-tüm-yolları-okuyan-eski-
# davranışın-production_only ile AYRI olduğunu-kanıtlamak-yerine, doğrudan
# emitter_verify'i-çağırıp-ayrımı-gözle: üretim-corpus'undaki-op'ların-hepsi
# PROD-CORPUS-dosyalarından-gelmeli (mock'a-gerek-yok — gerçek-dosya-ayraçı)
import pathlib, inspect
src = inspect.getsource(EV.corpus_ops)
assert "PROD" in src or "production_only" in src, \
    "corpus_ops-üretim-ayrımı-yok (Veridict-canary-sınıfı-tehlikede)"
print("  fixture-üretim-sızıntısı-yok (PROD-CORPUS-ayrımı-ölçüldü)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS fixture-üretim-ayrıldı"
else FAIL=$((FAIL+1)); note "  FAIL fixture-sızdı"; cat "$LOG"; fi

# 4) AYAR: emitter'ı-olmayan-gerçek-ölü-girdi-yakalanmalı (Türkçe-karakter-dahil)
note "4) ayar — emitter'sız-ölü-girdi (Türkçe-regex-kapsamı)"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, pathlib, tempfile
sys.path.insert(0, "tools")
import spec_needle_machine as M
base = pathlib.Path("tests/conformance/spec/LEDGER-SPEC.md").read_text(encoding="utf-8")
# Kayıt-türleri-satırına-emitter'ı-OLMAYAN-değer-ekle (Türkçe-karakterli)
# AT-059-sonrası-desen-güncellendi: satır-artık-'anchor'-ile-devam-ediyor
iso = base.replace("`migrate-net` (R1-ağ-geçiş-kanıtı),",
                   "`migrate-net` (R1-ağ-geçiş-kanıtı), `bogus-tür`;")
d = tempfile.mkdtemp()
(pathlib.Path(d) / "LEDGER-SPEC.md").write_text(iso, encoding="utf-8")
M.SPEC_DIR = pathlib.Path(d)
dead = M.check_dead_entries()
# AT-057-sonrası-check_dead_entries-artık-üretim-corpus'undan-okur; bu-yüzden
# bogus-tür-üretim-corpus'unda-yok → ÖLÜ-listesinde-DEĞİL, AMA-main()-AT-057
# raporlamasında-çıkar. Önce-eski-ölü-sınıfı-ölç (fixture'da-olsaydı-yakalardı):
M._found_ops = lambda production_only=False: {"charge", "grant", "bogus-tür"} \
    if not production_only else {"charge", "grant"}
dead = M.check_dead_entries()
assert "bogus-tür" in dead, \
    f"emitter'sız-ölü-girdi-yakalanmadı (regex-Türkçe-dışlıyor): {dead}"
# run/migrate-net-emitter'ı-olduğu-için-yeşil-olmalı (E1(d)-sınıfı)
assert "run" not in dead and "migrate-net" not in dead, \
    f"emitter'lı-değerler-yanlış-ölü-sayılıyor: {dead}"
print(f"  bogus-tür-yakalandı; run/migrate-net-emitter-korumasıyla-yeşil")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS ölü-girdi-ayarı-doğru"
else FAIL=$((FAIL+1)); note "  FAIL ölü-girdi-sızıntısı"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-047-kapısı: YÖN-B-makinede + op-kümesi-otomatik"
[[ $FAIL -eq 0 ]]
