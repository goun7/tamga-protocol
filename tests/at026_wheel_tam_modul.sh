#!/usr/bin/env bash
# AT-026 (RUN_SLOW) — wheel paket-tamlık sözleşmesi: repo'daki her tamga_*.py
# kök-modülü py-modules listesinde VE üretilen wheel'de olmalı.
# Ders-kaynağı: 0.2.3'te tamga_pugio_ingest.py py-modules'ta UNUTULDU — PyPI
# kurulumu AT-025 yüzeyini kırıktı (kurulum-import-çökmesi sınıfı). Bu kontrol
# o sınıfı süit-tarafında sonsuza dek yakalar.
# Sem: py-modules ↔ repo-kökü ↔ wheel-içeriği ÜÇ-yönlü eşitlik.
set -u
PASS=0; FAIL=0
LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-026/$(date +%F)}/at026.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1) repo-kökündeki tamga_*.py modülleri (test/vektör-sanal-dosyaları hariç):
ls tamga_*.py 2>/dev/null | sed 's/\.py$//' | LC_ALL=C sort -u > "$WORK/repo.txt"
ok $? "repo-kökü tarandı ($(wc -l < "$WORK/repo.txt") modül)"

# 2) py-modules listesi pyproject'tan:
python3 - <<PY > "$WORK/piproj.txt"
import re
s = open("pyproject.toml").read()
m = re.search(r"py-modules\s*=\s*\[(.*?)\]", s, re.S)
mods = re.findall(r'"([^"]+)"', m.group(1)) if m else []
import locale
print("\n".join(sorted(set(mods))))
PY
ok $? "py-modules okundu ($(wc -l < "$WORK/piproj.txt") modül)"

# 3) ÜÇ-yönlü eşitlik #1: repo ↔ py-modules
diff "$WORK/repo.txt" "$WORK/piproj.txt" > "$WORK/d1.txt" 2>&1
ok $? "repo-kökü == py-modules (eksik/çok: $(wc -l < "$WORK/d1.txt") satır)"

# 4) wheel üret (temiz dist zorunlu — çift-wheel glob tuzağı dersi):
rm -rf dist && python3 -m build --wheel --sdist > "$WORK/build.log" 2>&1
ok $? "wheel+sdist üretildi (temiz dist/)"

# 5) ÜÇ-yönlü eşitlik #2: py-modules ↔ wheel içeriği
WHEEL=$(ls -t dist/tamga_protocol-*.whl | head -1)
python3 - "$WHEEL" "$WORK/piproj.txt" << 'PY' > "$WORK/missing.txt"
import sys, zipfile
wheel, listfile = sys.argv[1], sys.argv[2]
names = zipfile.ZipFile(wheel).namelist()
mods = [l.strip() for l in open(listfile) if l.strip()]
missing = [m for m in mods if f"{m}.py" not in names]
print("\n".join(missing))
PY
EXS=$(grep -c . "$WORK/missing.txt" || true)
[ "$EXS" -gt 0 ] && echo "  wheel'de-eksik: $(grep . "$WORK/missing.txt" | tr '\n' ' ')" | tee -a "$LOG"
ok $([ "$EXS" -eq 0 ]; echo $?) "py-modules == wheel içeriği (eksik: $EXS modül)"

# 6) kurulum-import-çökmesi kapısı: TAM kurulumda (pynacl dahil) her modül
# import EDİLEBİLMELİ — --no-deps kurulumda pynacl-isteyen modüllerin kırılması
# beklenen ve bu kontrolün konusu DEĞİL (AT-019 zaten nacl-engelli-yolu sınar).
python3 -m venv "$WORK/venv" > /dev/null 2>&1
"$WORK/venv/bin/pip" install --quiet "$WHEEL" > /dev/null 2>&1
while read -r mod; do
  [ -z "$mod" ] && continue
  "$WORK/venv/bin/python" -c "import $mod" > /dev/null 2>&1
  ok $? "import $mod (tam-kurulum-sonrası)"
done < "$WORK/piproj.txt"

echo "AT-026 RESULT: $PASS PASS, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
