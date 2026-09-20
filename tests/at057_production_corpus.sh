#!/usr/bin/env bash
# AT-057: ÜRETİM-CORPUS-BOŞLUK-DENETİMİ — Veridict-canary-2026-09-20-aynası.
#
# DERS: seq+prev+h-üçlüsü-FIXTURE'ler-de-üretir. İlk-emitter-verify-koşusu
# "charge(72), grant(7)"-dedi — YANLIŞ; hepsi-fixture-kurulumundan-geldi.
# Veridict'in-canary-hatasıyla-BİREBİR-aynı-sınıf: sayım-kanıtın-GİRMEDİĞİ-
# yerden-geliyordu (fixture-üretimi → üretim-erişilebilirliği-sanısı).
#
# ÜÇÜNCÜ-SEÇENEK-YASAK (K0-rule-7, AT-056-sonrası): bir-kod-emitter'ı-ya-ÜRETİM
# ledger'ında-kanıtlanır-ya-da-açık-eksiklik-bildirimi-yapar. Sessiz-geçiş-
# YASAK — "kanıtladı"-demek-üretim-kanıtı-sıfırken-yalan-söylüyor.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-057/$(date +%F)/at057.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

# 0) ÜRETİM-LEDGER'I-TESTTE-ÜRET (.evidence/-gitignore'da-olduğu-için-
# commit'e-girmiyor; test-her-koşuda-kendi-kanıtını-yaratır — kanıt-commit'e
# değil-koşuya-bağlı, tekrar-oynatılabilir-offline). Ayrı-modül: bash-heredoc-
# içinde-python-literal-tırnaklama-tuzağından-kaçınır.
export PROD="$HERE/../.evidence/PROD-CORPUS/2026-09-20"
mkdir -p "$PROD"
python3 tests/helpers/prod_corpus_make.py >> "$LOG" 2>&1
RC=$?
if [ $RC -ne 0 ]; then FAIL=$((FAIL+1)); note "  FAIL 0) üretim-ledger-üretilemedi"; cat "$LOG"; fi

note "AT-057: üretim-corpus-boşluğu — Veridict-canary-aynası"

# 1) ÜRETİM-CORPUS-AYRAÇ-ÇALIŞIYOR: fixture'ler-hariç-tutuluyor
note "1) fixture'ler-üretim-corpus'undan-hariç"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys; sys.path.insert(0, "tools")
import emitter_verify as EV
prod = EV.corpus_ops(production_only=True)
allc = EV.corpus_ops(production_only=False)
# fixture-kanıtları-üretim-sayılmamalı
assert "charge" in allc, "fixture-corpus'unda-charge-olmalı"
# üretim-corpus'u-BOŞ-değil-artık (AT-057-prodrun-koydu)
assert "charge" in prod, "üretim-corpus'unda-charge-YOK — prodrun-bozuk"
assert "grant" in prod, "üretim-corpus'unda-grant-YOK"
print("  üretim-corpus:", sorted(prod))
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 1) üretim-corpus-ayraç"; else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) ÜRETİM-LEDGER-GERÇEK: seq+prev+h-üçlüsü-taşıyor
note "2) üretim-ledger-satırları-üçlü-taşıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import json, os, pathlib
lp = pathlib.Path(os.environ["PROD"]) / "prodrun" / "ledger.jsonl"
assert lp.exists(), f"üretim-ledger-yok: {lp}"
lines = [l for l in lp.read_text(encoding="utf-8").splitlines() if l.strip()]
assert len(lines) >= 2, f"üretim-ledger-boş: {len(lines)}-satır"
for l in lines:
    r = json.loads(l)
    assert all(k in r for k in ("seq", "prev", "h")), f"üçlü-eksik: {r.keys()}"
    assert r.get("op") in ("charge", "grant", "migrate-net"), \
        f"beklenmeyen-op: {r.get('op')}"
print(f"  {len(lines)}-üretim-satırı-üçlü-tamam")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 2) üretim-ledger-üçlü"; else FAIL=$((FAIL+1)); note "  FAIL 2)"; cat "$LOG"; fi

# 3) TÜM-ÜÇ-EMITTER-ÜRETİM-KANITLI: charge/grant/migrate-net
note "3) üç-emitter'ın-hepsi-üretim-ledger'ında-kanıtlandı"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys; sys.path.insert(0, "tools")
import emitter_verify as EV
r = EV.scan()
# üçü-de-artık-üretim-corpus'unda — problems'te-ÜRETİM-kanıtsızlık-OLMAMALI
up = [p for p in r["problems"] if "ÜRETİM" in p and "KANIT-YOK" in p]
assert not up, f"üretim-kanıtsızlık-kaldı: {up}"
prod = EV.corpus_ops(production_only=True)
for op in ("charge", "grant", "migrate-net"):
    assert op in prod, f"{op}-üretim-corpus'unda-yok"
print("  üç-emitter-üretim-kanıtlandı:", sorted(prod))
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 3) migrate-net-dürüst-bildirim"; else FAIL=$((FAIL+1)); note "  FAIL 3)"; cat "$LOG"; fi

# 4) ÜÇÜNCÜ-SEÇENEK-YASAK: üretim-corpus-boşalınca-RED
note "4) ayar — üretim-corpus-boşalınca-RED"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys; sys.path.insert(0, "tools")
import emitter_verify as EV
orig = EV.corpus_ops
def fake(production_only=False):
    if production_only:
        return set()   # üretim-corpus-boş
    return orig(production_only=False)
EV.corpus_ops = fake
try:
    r = EV.scan()
    ch = [p for p in r["problems"] if "charge" in p and "ÜRETİM" in p]
    assert ch, "üretim-corpus-boşalınca-charge-yakalanmadı!"
    print("  boş-üretim-corpus → charge-RED (sessiz-geçiş-yok)")
finally:
    EV.corpus_ops = orig
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 4) üçüncü-seçenek-yasak"; else FAIL=$((FAIL+1)); note "  FAIL 4)"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-057: üretim-corpus-boşluğu (Veridict-canary-aynası)"
[[ $FAIL -eq 0 ]]
