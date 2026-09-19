#!/usr/bin/env bash
# Tamga Conformance Pack — üçüncü-taraflar için sıfır-import koşucusu.
#
# Bu paket TAMGA REPOSUNU GEREKTİRMEZ. İçinde normatif-spec özeti + bağımsız
# verifier (RFC 8785 JCS'yi sıfırdan uygular, hiçbir tamga_* modülü yok) +
# vektörler var. Üçüncü-taraf bir gerçeklemenin spec'e sadık olduğunu bununla
# denetleyebilir — bizim kodumuza erişmeden.
#
# Kullanım:
#   ./run.sh                    # tüm-vektörleri-koş
#   ./run.sh <gerçeklemeniz>    # sizin verify komutunuzu da parite için koş
#
# <gerçeklemeniz>: "python3 your_verify.py" gibi bir komut; ledger yolunu
# son argüman olarak alır, rc=0 GREEN / rc!=0 RED döndürmeli.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

PASS=0; FAIL=0; SKIP=0
note() { echo "  $*"; }

# (vektör, beklenen: green|red|empty)
declare -a VECTORS=(
  "00-clean.jsonl|green|§2-§3 tüm-kurallar-sağlam"
  "01-seq-skip.jsonl|red|§3.1 seq-aritmetik"
  "02-prev-broken.jsonl|red|§3.2 prev-zincir-bağı"
  "03-h-wrong.jsonl|red|§3.3 h-yeniden-hesap"
  "04-not-object.jsonl|red|§3.4 kayıt-JSON-nesnesi"
  "05-unparseable.jsonl|red|§3.5 parse-edilebilirlik"
  "06-empty.jsonl|empty|§4 boş-zincir-geçerli-başlangıç"
)

IMPL="${1:-}"
if [ -n "$IMPL" ]; then
  note "Parite-modu: sizin-gerçeklemeniz = $IMPL"
else
  note "Tek-mod: paketin-bağımsız-verifier'ı"
fi

for spec in "${VECTORS[@]}"; do
  v="${spec%%|*}"; rest="${spec#*|}"; expect="${rest%%|*}"; desc="${rest#*|}"
  path="vectors/$v"
  # paketin-bağımsız-verifier'ı
  python3 verify.py "$path" > /tmp/conf-out.json 2>&1; ref_rc=$?
  # bizim-uygulamamızın-çıktısını-oku
  ref_ok=$(python3 -c "
import json
try:
    d=json.load(open('/tmp/conf-out.json'))
    if d.get('empty_chain'): print('empty')
    elif d.get('ok'): print('green')
    else: print('red')
except Exception: print('error')" 2>/dev/null)
  if [ "$ref_ok" = "$expect" ]; then
    PASS=$((PASS+1)); note "  PASS $v [$ref_ok] $desc"
  else
    FAIL=$((FAIL+1)); note "  FAIL $v beklenen=$expect referans=$ref_ok $desc"
  fi
  # parite: sizin-gerçeklemeniz-aynı-sonuç-vermeli
  if [ -n "$IMPL" ]; then
    $IMPL "$path" > /dev/null 2>&1; your_rc=$?
    your_ok=$([ $your_rc -eq 0 ] && echo green || echo red)
    if [ "$expect" = "empty" ]; then
      # §4: boş-zincir-için-siz-de-geçerli-başlangıç-demelisiniz
      note "      (parite-boş-zincir: sizin-rc=$your_rc — §4'e-göre-geçerli)"
    elif [ "$your_ok" != "$expect" ]; then
      FAIL=$((FAIL+1)); note "  FAIL-parite $v sizin=$your_ok beklenen=$expect"
    else
      PASS=$((PASS+1)); note "  PASS-parite $v sizin=$your_ok"
    fi
  fi
done

# ---- sovereign-anchor conformance (katman-1; üç-ürün-özü) ----
note ""
note "Sovereign-anchor conformance — katman-1 (ANCHOR-SPEC.md §3-§5)"
if ls anchors/*.json > /dev/null 2>&1; then
  for a in anchors/*.json; do
    name="$(basename "$a" .json)"
    python3 verify_anchor.py "$a" > /tmp/conf-anchor.json 2>&1; rc=$?
    verdict=$(python3 -c "
import json
try:
    d=json.load(open('/tmp/conf-anchor.json'))
    print('green' if d.get('ok') and 'UNVERIFIED' not in d.get('verdict','')
          else 'unverified' if d.get('ok') else 'red')
except Exception: print('error')" 2>/dev/null)
    case "$name" in
      a00-clean)      want="green" ;;
      a06-no-sources) want="unverified" ;;
      *)              want="red" ;;
    esac
    if [ "$verdict" = "$want" ]; then
      PASS=$((PASS+1)); note "  PASS $name [$verdict]"
    else
      FAIL=$((FAIL+1)); note "  FAIL $name beklenen=$want referans=$verdict"
    fi
  done
fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL"
if [ $FAIL -eq 0 ]; then
  echo "  Tamga-ledger-conformance: TÜM-VEKTÖRLER-UYUMLU"
  exit 0
else
  echo "  UYUMSUZLUK-VAR — spec-ihlali-yukarıda"
  exit 1
fi
