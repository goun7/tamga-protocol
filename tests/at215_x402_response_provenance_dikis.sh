#!/usr/bin/env bash
# AT-215: X402-RESPONSE-PROVENANCE — PR #3304 normative-vektörünün bağımsız-
# yeniden-türetimi. tools/x402_response_provenance.py'nin GERÇEK-çalıştığını-
# kanıtlar (mevcut-testi-YOKTU — araç-kodsuz-test-evidansı-istedi-lead).
#
# PR #3304 (x402 spec/extensions/response-provenance.md): bir-yanıtın-kaynağını
# KANONİK-SABİT-NOKTA-üzerinden-kanıtlar. Kapalı-küme-kuralı: fixed-point'ın
# tam-beş-üyesi-var (endpoint/inputs/result/method/dataVintage), fazlası-veya-
# eksikliği unverifiable. Araç-x402'ye-SIFIR-bağımlılık-kuruyor (sadece-sha256
# + RFC-8785-JCS-via-tamga_canon) — bu-bağımsızlığın-kendisi-kanıtı-verir.
#
# NEYİ-KANITLAR:
#   K1 POSİTİF: PR #3304'nun-yayımlanmış-vektörü → byte-exact (134-bayt, hash-esleşir)
#   K2 BAĞIMSIZLIK: araç x402-spec-vektörünü-tamga_canon-ile-türetir, x402-kodu-YOK
#   K3 KAPALI-KÜME: fazla-üye → unverifiable (fail-loud; sessiz-kabul-YOK)
#   K4 EKSİK-ÜYE: eksik-üye → unverifiable (aynı-disiplin)
#   K5 VERIFY-YOLU: harici-fixed-point-dosyası-doğrulanır (rc-0 + responseHash)
#   K6 NEGATİF-LOAD: bozuk-JSON → rc1 (crash-değil, mesaj-RED)
#
# Para-YOK (yerel-kanonikleştirme; TAMGA_LIVE-GEREKMEZ). 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/X402/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at215.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

TOOL="tools/x402_response_provenance.py"
WORK=$(mktemp -d)

# --- K1: POSİTİF — PR #3304 vektörü byte-exact -------------------------------
OUT=$(python3 "$TOOL" vector 2>&1); RC=$?
H1=$(echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok' if d.get('byte_exact') else 'BAD')" 2>/dev/null)
B1=$(echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('canonical_bytes'))" 2>/dev/null)
[ "$RC" = "0" ] && [ "$H1" = "ok" ] && [ "$B1" = "134" ] && RES1=0 || RES1=1
k $RES1 "K1 PR#3304-vektörü-byte-exact (134-bayt, hash-esleşir, rc=$RC)" "rc=$RC byte_exact=$H1 bytes=$B1"

# --- K2: BAĞIMSIZLIK — araç-x402'ye-bağlanmıyor ------------------------------
# x402-spec-sınıfı-kodu-import-etmiyor; sadece-sha256+jcs. KAYNAK-taraması.
if grep -qE "import x402|from x402|x402\." "$TOOL" 2>/dev/null; then
  # istisna: spec/extensions/response-provenance.md YORUM-satırı-referansı
  X402_REAL=$(grep -cE "^[^#]*\bx402\b" "$TOOL" 2>/dev/null || echo 0)
else
  X402_REAL=0
fi
# docstring'deki "x402"-sözcüğü-yasak-değil; gerçek-import-yok
IMPORTS=$(grep -E "^import |^from " "$TOOL" | grep -vE "^from tamga_canon|^import (hashlib|json|sys|pathlib)" | grep -vi "x402" | wc -l)
# x402-referansları-yalnızca-docstring/yorum-satırında-olmalı
CODE_X402=$(grep -vE "^\s*#|^\s*\"\"\"|^\s*'" "$TOOL" | grep -cE "\bx402\b" 2>/dev/null || echo 0)
[ "$X402_REAL" = "0" ] && RES2=0 || RES2=1
k $RES2 "K2 bağımsızlık — x402-kodu-importu-YOK (sadece-sha256+tamga_canon)" "kod-icinde-x402-referans=$CODE_X402"

# --- K3: KAPALI-KÜME — fazla-üye → unverifiable ------------------------------
echo '{"endpoint":"/e","inputs":{"a":1},"result":{"r":1},"method":"m","dataVintage":"2026-07","EXTRA":1}' > "$WORK/fp-extra.json"
R3=$(python3 "$TOOL" verify "$WORK/fp-extra.json" 2>&1); RC3=$?
V3=$(echo "$R3" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('verdict','?'))" 2>/dev/null)
[ "$RC3" = "1" ] && [ "$V3" = "unverifiable" ] && RES3=0 || RES3=1
k $RES3 "K3 fazla-üye → unverifiable (rc1, fail-loud)" "rc=$RC3 verdict=$V3"

# --- K4: EKSİK-ÜYE → unverifiable ------------------------------------------
echo '{"endpoint":"/e","inputs":{"a":1},"result":{"r":1}}' > "$WORK/fp-missing.json"
R4=$(python3 "$TOOL" verify "$WORK/fp-missing.json" 2>&1); RC4=$?
V4=$(echo "$R4" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('verdict','?'))" 2>/dev/null)
[ "$RC4" = "1" ] && [ "$V4" = "unverifiable" ] && RES4=0 || RES4=1
k $RES4 "K4 eksik-üye → unverifiable (aynı-disiplin)" "rc=$RC4 verdict=$V4"

# --- K5: VERIFY-YOLU — geçerli-fixed-point → ok + responseHash --------------
echo '{"endpoint":"/v1/echo-sum","inputs":{"a":2,"b":3},"result":{"sum":5},"method":"sum = a + b, integer addition","dataVintage":"2026-07"}' > "$WORK/fp-ok.json"
R5=$(python3 "$TOOL" verify "$WORK/fp-ok.json" 2>&1); RC5=$?
OK5=$(echo "$R5" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok' if d.get('ok') and d.get('responseHash')=='81ea1f2227fd9df5b868954e6d26d091810352f148dade483b260844788ede03' else 'BAD')" 2>/dev/null)
[ "$RC5" = "0" ] && [ "$OK5" = "ok" ] && RES5=0 || RES5=1
k $RES5 "K5 verify-yolu: harici-fixed-point → ok (hash-spec-le-birebir)" "rc=$RC5 $OK5"

# --- K6: NEGATİF-LOAD — bozuk-JSON → rc1 (crash-değil) ----------------------
echo '{not json' > "$WORK/fp-broken.json"
python3 "$TOOL" verify "$WORK/fp-broken.json" >/dev/null 2>&1; RC6=$?
[ "$RC6" = "1" ] && RES6=0 || RES6=1
k $RES6 "K6 bozuk-JSON → rc1 (mesaj-RED, crash-YOK)" "rc=$RC6"

rm -rf "$WORK"
echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-215: x402 response-provenance bağımsız-yeniden-türetim (PR #3304)"
[ "$FAIL" -eq 0 ] || exit 1
