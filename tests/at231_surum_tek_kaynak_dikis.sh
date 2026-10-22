#!/usr/bin/env bash
# AT-231: SURUM-TEK-KAYNAK — pyproject.toml ↔ bootstrap --version DAVRANIŞ-DİKİŞİ.
#
# A1c-2026-10-22: tamga_bootstrap.py --version once importlib.metadata'yi
# okuyordu ( kaynak-agacinda-site-packages'taki-ESKI-kurulu-paketi-buluyordu,
# bu-deponin-pyproject'ini-degil) VE hicbir-sey-bulamazsa-stale-0.2.0rc2
# fallback'ini-basiyordu ( pyproject-0.2.13'e-karsi). Olcum-kaniti:
#   python3 tamga_bootstrap.py --version  →  "tamga-protocol 0.2.13" (ESKI:
#   importlib.yolu-ile-0.2.0-rc2-stale-mesaji).
#
# NEYİ-KANITLAR:
#   K1 TEK-KAYNAK: --version ciktisi pyproject.toml-version'ina-esit
#   K2 STALE-FALLBACK-YOK: cikti "0.2.0rc2"-icermiyor ( eski-stale-mesaj)
#   K3 PYPROJECT-TEK-SATIR: pyproject.toml'de TEK "version =" satiri-var
#      ( tekrar-yazinim-yok — biri-degistirilip-digeri-unutulamaz)
#   K4 IMPORTLIB-YALANI: importlib-metadata-ne-donerse-donsun kaynak-
#      pyproject-kazanir ( environment-i-kanitlar)
#   K5 SIDDIKLAR: bootstrap'de-sabit-yazilmis-surum-yok ( magic-string-tespifi)
#
# Para-YOK / ag-YOK / wasm-YOK. Deterministik. rc=0-beklenir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/SURUM/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at231.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

PYPROJECT="pyproject.toml"

# --- K1: TEK-KAYNAK --version == pyproject.version ------------------------------------------
PYVER=$(python3 - <<'PY'
import re
from pathlib import Path
t = Path("pyproject.toml").read_text(encoding="utf-8")
satirlar = [ln for ln in t.splitlines() if re.match(r"^version\s*=", ln)]
assert len(satirlar) == 1, f"pyproject version-satiri-1-olmali: {len(satirlar)}"
print(satirlar[0].split('"')[1])
PY
)
CLIOUT=$(python3 tamga_bootstrap.py --version 2>&1); RC=$?
CLIOUT_TRIMMED=$(echo "$CLIOUT" | tr -d '\r' | head -1)
echo "$CLIOUT_TRIMMED" | grep -q "tamga-protocol $PYVER\$" && RES1=0 || RES1=1
k $RES1 "K1 --version ciktisi pyproject-version'ina-esit ( rc=$RC)" "cikti='$CLIOUT_TRIMMED' pyproject='$PYVER'"

# --- K2: STALE-FALLBACK-YOK ----------------------------------------------------------------
echo "$CLIOUT_TRIMMED" | grep -q "0.2.0rc2" && RES2=1 || RES2=0
k $RES2 "K2 stale-0.2.0rc2-fallback-cikti-yok ( eski-stale-mesaj-kapatildi)" "cikti='$CLIOUT_TRIMMED'"

# --- K3: PYPROJECT-TEK-VERSION-SATIRI ------------------------------------------------------
NSAT=$(grep -cE "^version\s*=" "$PYPROJECT" || true)
[ "$NSAT" = "1" ] && RES3=0 || RES3=1
k $RES3 "K3 pyproject.toml'de TEK version-satiri ( tekrar-yazinim-yok)" "satir-sayisi=$NSAT"

# --- K4: IMPORTLIB-YALANI ( kaynak-pyproject-her-zaman-kazanir) -----------------------------
V4=$(PYTHONPATH="/tmp/at231_yok_$$" python3 - <<'PY' 2>&1
import sys, pathlib
sys.path.insert(0, ".")
import tamga_bootstrap as tb
# importlib.metadata'yi-yalan-soylemeye-zorla ( eski-kurulu-paket-simulasyonu)
import importlib.metadata as md
def _yalan(ad):
    return "0.0.0-eski"
md.version = _yalan
surum = tb._kaynak_surumu()
print("KAYNAK" if surum == "0.2.13" else f"YANLIS={surum}")
PY
)
[ "$V4" = "KAYNAK" ] && RES4=0 || RES4=1
k $RES4 "K4 importlib-yalan-soylese-bile kaynak-pyproject-kazanir ( _kaynak_surumu)" "$V4"

# --- K5: BOOTSTRAP'DE-SABIT-SURUM-YOK ------------------------------------------------------
# --version-yoluundes sabit-yazilmis surum-olmamali ( comment-disinda)
SABIT=$(grep -nE '"[0-9]+\.[0-9]+\.[0-9]+[a-z0-9.-]*"' tamga_bootstrap.py \
  | grep -vE "wasmtime-|WASMTIME|sha256|SHA256|hash|digest" || true)
[ -z "$SABIT" ] && RES5=0 || RES5=1
k $RES5 "K5 bootstrapde-sabit-yazilmis-surum-YOK ( magic-string-tespifi)" "${SABIT:-temiz}"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-231: surum-tek-kaynak ( pyproject.toml ↔ bootstrap --version)"
[ "$FAIL" -eq 0 ] || exit 1
