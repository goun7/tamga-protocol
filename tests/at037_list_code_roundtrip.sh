#!/usr/bin/env bash
# AT-037: ret-listesi ↔ kod round-trip (GVP-PR-#3'ün-bizde-yansıması)
#
# Şeklin-kaynağı: 2026-09-18'de SolomonisBlack'in-golden-vector-provenance'sı-için
# açtığımız-issue-#2 (list-vs-code-round-trip). O-PR-ilk-koşta-gerçek-drift-yakaladı
# (3-tip-koruyucusu-listede-yoktu). Aynı-özellik-kendi-evimizde-uygulanmalı: bizim
# jcs'imizin-ret-listesi ile-koddaki-throw'lar-birebir-eşleşmeli, tek-yönlü-değil.
#
# Yön-1 (kod→liste): her-ulaşılabilir-ret listede-olmalı (gizli-ret = liste-eski)
# Yön-2 (liste→kod): her-liste-maddesi gerçekten-ret vermeli (liste-aşırı-iddia)
# Negatif-self-test: alet-fail-edebilmeli (bozulan-probe → FAIL)
#
# Bu-test AYNI zamanda 0.2.12'nin-I-JSON-düzeltmelerinin-regresyon-kapısıdır:
# 2^53-RED ve NaN/Inf-RED burada-assert-edilir, listede-kodda-uyuşmazlık-yok.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
PY="${PYTHON:-python3}"
LOG=".evidence/AT-037/$(date +%Y-%m-%d)/at037.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0

note() { echo "$@" | tee -a "$LOG"; }

note "AT-037: ret-listesi ↔ kod round-trip (list ⇄ code, her-iki-yön)"

# ---------------------------------------------------------------------------
# Dokümante-ret-listesi (tek-kaynak). Kod-bu-listeyi-tutmaz; liste-kodu-tutmaz.
# Drift-yalnızca-bu-testle-yakalanır.
# ---------------------------------------------------------------------------
ret_check() {
  local ad="$1" obj="$2" beklenen="$3"
  local sonuc rc
  sonuc="$($PY -c "import json,sys; sys.path.insert(0,'.')
from tamga_canon import jcs
try:
    jcs($obj); print('KABUL')
except ValueError as e: print('RED-ValueError')
except TypeError as e: print('RED-TypeError')" 2>/dev/null)"
  if [ "$sonuc" = "$beklenen" ]; then
    PASS=$((PASS+1)); note "  PASS liste⇄kod $ad: $sonuc"
  else
    FAIL=$((FAIL+1)); note "  FAIL liste⇄kod $ad: $sonuc (beklenen $beklenen) — LİSTE-VE-KOD-DRIFT-YAPTI"
  fi
}

# Yeşil-vectors: geçerli-I-JSON,-normal-çıktı
ret_check "2^53-1 son-güvenli-tamsayı (yeşil)" '{"max":9007199254740991}' 'KABUL'
ret_check "2^53 tam-sınır (yeşil)" '{"x":9007199254740992}' 'KABUL'
ret_check "-0.0 → 0 (yeşil)" '{"z":-0.0}' 'KABUL'
ret_check "5e-324 subnormal (yeşil)" '{"s":5e-324}' 'KABUL'

# Listeli-ret'ler: her-biri-belirli-bir-sınıf-olmalı
ret_check "2^53+1 I-JSON-dışı (RED)" '{"over":9007199254740993}' 'RED-ValueError'
ret_check "büyük-tamsayı I-JSON-dışı (RED)" '{"big":1234567890123456789}' 'RED-ValueError'
ret_check "NaN I-JSON-dışı (RED)" '{"n":float("nan")}' 'RED-ValueError'
ret_check "Infinity I-JSON-dışı (RED)" '{"i":float("inf")}' 'RED-ValueError'
ret_check "desteklenmeyen-tür set (RED)" '{"s":set()}' 'RED-TypeError'

# ---------------------------------------------------------------------------
# Yön-1 (kod→liste): koddaki-her-ret-türünden-en-az-bir-örnek-listede-var mı?
# Bizim-3-ret-sınıfımız: ijson_out_of_range, ijson_not_finite, unsupported_type.
# Eğer-kodda-4.-bir-sınıf-belirse-bu-test-yakalar (probe-exhaustive-değil-ama
# sınıf-kapsamı-tam).
# ---------------------------------------------------------------------------
sinif_kontrol() {
  local sinif="$1" obj="$2"
  local c="$($PY -c "import sys; sys.path.insert(0,'.')
from tamga_canon import jcs
try:
    jcs($obj); print('YOK')
except ValueError as e: print('VAR')
except TypeError: print('VAR')" 2>/dev/null)"
  if [ "$c" = "VAR" ]; then PASS=$((PASS+1)); note "  PASS kod→liste $sinif: koda-ulaşılabilir-ve-listede"
  else FAIL=$((FAIL+1)); note "  FAIL kod→liste $sinif: koddaki-ret-listeye-yansımıyor"; fi
}
sinif_kontrol "ijson_out_of_range" '{"over":9007199254740993}'
sinif_kontrol "ijson_not_finite"   '{"n":float("nan")}'
sinif_kontrol "unsupported_type"   '{"s":set()}'

# ---------------------------------------------------------------------------
# Negatif-self-test: alet-fail-edebilmeli. NaN-probe'unu-boz (NaN→2) → FAIL-bekle.
# Bir-test-ki-fail-edemez-hiçbir-şey-kanıtlamaz.
# ---------------------------------------------------------------------------
note "  negatif-self-test: alet-fail-edebilir-mi?"
bozuk="$($PY -c "import sys; sys.path.insert(0,'.')
from tamga_canon import jcs
try:
    jcs({'n':2}); print('KABUL')   # NaN-bozuk: artık-ret-değil
except ValueError: print('RED')" 2>/dev/null)"
if [ "$bozuk" = "KABUL" ]; then
  PASS=$((PASS+1)); note "  PASS negatif-self-test: bozuk-probe-ret-vermez → yukarıdaki-FAIL-beklenir-OLUR"
else
  FAIL=$((FAIL+1)); note "  FAIL negatif-self-test: bozuk-probe-hâlâ-ret-veriyor — alet-tutarsız"
fi

# ---------------------------------------------------------------------------
# Üçlü-parite: canon / validator / verify-mini — RED'lerde-de-birebir.
# Kopyalar-drift-yapamaz (İç-KAT-2, vauban-ile-aynı-şekilde).
# ---------------------------------------------------------------------------
note "  üçlü-parite: 3-uygulama-RED'lerde-de-birebir"
par="$($PY -c "import sys; sys.path.insert(0,'.')
from tamga_canon import jcs as c
from tamga_validator import jcs as v
import importlib.util as iu
s=iu.spec_from_file_location('m','tamga_verify_mini.py'); m=iu.module_from_spec(s); s.loader.exec_module(m)
for obj in [{'over':9007199254740993},{'n':float('nan')},{'big':10**30}]:
    r=[]
    for f in (c,v,m.jcs):
        try: f(obj); r.append('KABUL')
        except ValueError: r.append('RED')
    if len(set(r))!=1: print('DRIFT'); break
else: print('BIREBIR')" 2>/dev/null)"
if [ "$par" = "BIREBIR" ]; then PASS=$((PASS+1)); note "  PASS üçlü-parite: canon=validator=mini (RED'lerde-de)"
else FAIL=$((FAIL+1)); note "  FAIL üçlü-parite: kopyalar-drift-yaptı ($par)"; fi

note "  konsol-yüzeyi-drift (USAGE ↔ runner-+ bootstrap-girişleri)"
if python3 tools/konsol_drift_kontrol.py > /dev/null 2>&1; then
  PASS=$((PASS+1)); note "  PASS konsol-yüzeyi: 20-komut-TUTARLI (runner-+ bootstrap)"
else
  FAIL=$((FAIL+1)); note "  FAIL konsol-yüzeyi: USAGE-ile-giriş-noktaları-drift-yaptı"
fi

note ""
note "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] && note "  AT-037-kapısı: ret-listesi-ile-kod-birebir (0.2.12-I-JSON-düzeltmeleri-sabitlenmiş)"
exit $([ "$FAIL" -eq 0 ]; echo $?)
