#!/usr/bin/env bash
# AT-062: GRANT-ŞEMA-OKUMA-KAPISI — AT-060'ın-anchor-deseni-diğer-şema-yüzeylerine
# yayılır (lead-yönergesi: "sadece-anchor-değil").
#
# BULGU: cmd_grant-yazma-yolunda-üç-shape-kuralı-doğruluyordu —
#   amount-sayısal (RED 1 "amount is not a number")
#   amount ∈ (0,1e6] (Audit-4 F18 policy bound)
#   note ≤ MAX_NOTE_BYTES (Audit-2 F12)
# AMA-ledger-verify'da-grant-için-HİÇBİR-kapı-yoktu. Kanıtlandı:
# amount="not-a-number"-içeren-bir-grant hem-zincire-giriyor hem-de-GREEN-geçiyor.
# D5-hash-byteleri-kilitler-ANLAMI-değil — metinsel-amount-bir-toplam/λ-eşik-
# tüketicisini-exception'da-kırar (üç-ürün-tek-öz-yüzeyi, AT-041).
#
# NEGATİF-amount-özellikle-kritik: cmd_grant-0<-miktarı-RED'ler (bir-grant-
# alıcıdan-para-çekemez), ama-okuma-kapısı-yoksa-el-yazımı-veya-üçüncü-taraf-
# aracı-negatif-grant-yazıp-GREEN-geçebilirdi — bu-bir-ekonomik-saldırı-yolu.
#
# ÇÖZÜM: _grant_violation-TEK-KAYNAK — cmd_grant-ve-ledger_verify-aynı-
# fonksiyonu-paylaşır (AT-047-SPEC_OPS-dersi: iki-yerde-elle-kural-drift'e-
# yer-yok). Okuma-kapısı-RED 16 (anchor-ile-aynı-shape-gate-ailesi).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-062/$(date +%F)/at062.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

cat > "$LOG.inject.py" <<'PYEOF'
import sys, pathlib
PKG, MODE = sys.argv[1], sys.argv[2]
sys.path.insert(0, "."); sys.argv = ["x"]
import tamga_runner as TR
GOOD = {"op": "grant", "pkg": "at062", "amount": 1.0, "note": "at062-kanit"}
rec = dict(GOOD)
if MODE == "good":
    pass
elif MODE == "r_str":        # amount-string (kanıtlanan-boşluk)
    rec["amount"] = "not-a-number"
elif MODE == "r_bool":       # JSON-boolean (float(True)==1.0-tuzağı)
    rec["amount"] = True
elif MODE == "r_missing":    # amount-yok
    rec.pop("amount")
elif MODE == "r_neg":        # negatif (ekonomik-saldırı)
    rec["amount"] = -5.0
elif MODE == "r_zero":       # sıfır
    rec["amount"] = 0.0
elif MODE == "r_huge":       # > 1e6 policy-bound
    rec["amount"] = 1e9
elif MODE == "r_note":       # dev-note
    rec["note"] = "x" * 70000
else:
    sys.exit(2)
lp = pathlib.Path(PKG) / "ledger.jsonl"
r = TR._ledger_append(lp, rec)
sys.exit(0 if isinstance(r, dict) else 1)
PYEOF

note "AT-062: grant-şema-okuma-kapısı (AT-060-deseni-yayılır)"

run_case() {  # $1=mod $2=beklenen $3=açıklama
  local MODE="$1" EXPECT="$2" DESC="$3"
  local PKG; PKG="$(mktemp -d)"
  python3 tamga_runner.py quickstart "$PKG" >> "$LOG" 2>&1 || true
  python3 "$LOG.inject.py" "$PKG" "$MODE" >> "$LOG" 2>&1
  python3 tamga_runner.py ledger-verify "$PKG" >> "$LOG" 2>&1
  local RC=$?
  if [ "$EXPECT" = "RED" ]; then
    if [ $RC -ne 0 ]; then PASS=$((PASS+1)); note "  PASS $DESC (RED rc=$RC)";
    else FAIL=$((FAIL+1)); note "  FAIL $DESC — GREEN-geçti"; cat "$LOG"; fi
  else
    if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS $DESC (GREEN)";
    else FAIL=$((FAIL+1)); note "  FAIL $DESC — geri-çekildi"; cat "$LOG"; fi
  fi
  rm -rf "$PKG"
}

run_case good      GREEN "0) geçerli-grant-GREEN"
run_case r_str     RED   "1) amount-string (kanıtlanan-boşluk)"
run_case r_bool    RED   "2) amount-JSON-boolean (float(True)-tuzağı)"
run_case r_missing RED   "3) amount-yok"
run_case r_neg     RED   "4) negatif-amount (ekonomik-saldırı-yolu)"
run_case r_zero    RED   "5) sıfır-amount"
run_case r_huge    RED   "6) >1e6-policy-bound"
run_case r_note    RED   "7) dev-note > MAX_NOTE_BYTES"

# 8) REGRESYON: cmd_grant'ın-kendisi-hala-aynı-CLI-sözleşmeyle-çalışır
note "8) cmd_grant-yazma-yolu-bozulmadı (AT-regresyonu)"
PKG8="$(mktemp -d)"
python3 tamga_runner.py quickstart "$PKG8" >> "$LOG" 2>&1
python3 tamga_runner.py grant "$PKG8" 0.5 "regression-note" >> "$LOG" 2>&1
RC_G=$?
python3 tamga_runner.py grant "$PKG8" "abc" >> "$LOG" 2>&1     # parse_error-reason-1
RC_BAD=$?
python3 tamga_runner.py ledger-verify "$PKG8" >> "$LOG" 2>&1
RC_LV=$?
if [ $RC_G -eq 0 ] && [ $RC_BAD -ne 0 ] && [ $RC_LV -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 8) grant-GREEN + 'abc'-RED + verify-GREEN"
else
  FAIL=$((FAIL+1)); note "  FAIL 8) g=$RC_G bad=$RC_BAD lv=$RC_LV"; cat "$LOG"
fi
rm -rf "$PKG8"

# 9) GERİ-DÖNÜŞÜM-KONTROLÜ: yazma-yolu-da-artık-_grant_violation-kullanıyor —
# negatif-amount-cmd_grant'dan-da-RED-olmalı (eski-sözleşme-korundu)
note "9) cmd_grant-negatif-amount-RED (aynı-kaynak-doğrulaması)"
PKG9="$(mktemp -d)"
python3 tamga_runner.py quickstart "$PKG9" >> "$LOG" 2>&1
python3 tamga_runner.py grant "$PKG9" -1.0 >> "$LOG" 2>&1
RC_NEG=$?
python3 tamga_runner.py grant "$PKG9" 0 >> "$LOG" 2>&1
RC_ZERO=$?
if [ $RC_NEG -ne 0 ] && [ $RC_ZERO -ne 0 ]; then
  PASS=$((PASS+1)); note "  PASS 9) negatif-ve-sıfır-cmd_grant'dan-RED"
else
  FAIL=$((FAIL+1)); note "  FAIL 9) neg=$RC_NEG zero=$RC_ZERO"; cat "$LOG"
fi
rm -rf "$PKG9"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-062: grant-şema-okuma-kapısı (AT-060-deseni-yayılır)"
[[ $FAIL -eq 0 ]]
