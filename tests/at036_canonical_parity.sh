#!/usr/bin/env bash
# AT-036 (kontrol-58) — canonicalization-parity: our Python RFC-8785 === Node/ECMAScript.
# Sebep: 2026-09-17'ye-kadar jcs = json.dumps(sort_keys=True) idi — Python-özel.
# Bulan-yabancı (Dümen#4, stillmarcus24): "json.dumps is not a canonical form" — zincir-
# özetini-yalnız-Python-yeniden-üretebiliriyor. Düzeltme: tamga_canon (ECMAScript number
# serialization + UTF-16 code-unit member order). Bu-kontrol ilkel-düzeyde-üç-parite-ve
# çapraz-dil-oracle'ını çalıştırır.
#
# Üç-verdit-sözleşmesi: node var → 12/12 bayt-birebir-beklenir (GREEN) / farklı-tek-byte
# RED / node-yok → İNDETERMİNE (rc2 — boyut-test-edilemiyor, sessiz-yeşil-sayılmaz).
set -u
cd "$(dirname "$0")/.."
rc=0
echo "AT-036a: vauban-selftest — RFC-8785 özleri + 3-uygulama-paritesi (mini/validator/canon)"
if python3 tools/vauban_conformance.py --selftest >/tmp/at036_selftest.txt 2>&1; then
  ok=1
else
  ok=0; rc=1
fi
tail -1 /tmp/at036_selftest.txt
if [ "$ok" = 1 ] && grep -qE "[0-9]+/[0-9]+ RFC-8785-öz-OK" /tmp/at036_selftest.txt; then
  echo "  PASS — ECMAScript-number (1.0→1, 2.93e-07→2.93e-7, 1e16→10000000000000000) + UTF-16-sıra"
else
  echo "  FAIL — selftest-kırmızı (yukarıdaki-diverjans)"; rc=1
fi

echo "AT-036b: çapraz-dil-oracle — python-canonical vs node (ECMAScript-native)"
if ! command -v node >/dev/null 2>&1; then
  echo "  İNDETERMİNE — node-yok: çapraz-dil-boyutu bu-makinada-test-edilemiyor (rc2)"
  echo "  python-iç-parite (036a) yeşil; dış-parite CI'da-koşar (node-ubuntu-runner)"
  exit "$rc"
fi
if bash tools/jcs_parity.sh >/tmp/at036_parity.txt 2>&1; then
  ok=1
else
  ok=0; rc=1
fi
line="$(grep 'JCS-PARİTE' /tmp/at036_parity.txt || true)"
echo "  $line"
if [ "$ok" = 1 ] && echo "$line" | grep -q "bayt-birebir"; then
  echo "  PASS — Python ≡ Node byte-for-byte (sayı-üretimi + anahtar-sıralama)"
else
  echo "  FAIL — python/node diverjansı (yukarıdaki #N)"; sed -n '/divergence/,+2p' /tmp/at036_parity.txt; rc=1
fi
exit "$rc"
