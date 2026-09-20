#!/usr/bin/env bash
# AT-060: RFC-009 ANCHOR-OKUMA-KAPISI — 'anchor'-kaydının-anlamsal-geçerliliği
# zincir-hash'inden-GELEMEZ (AT-050-üçlü-kapsam-dersinin-anchor'a-uygulanması).
#
# 4a1686c (AT-059) yalnızca-YAZMA-yolunu-kilitledi: cmd_anchor R9-1..R9-5'i
# doğrular. AMA _ledger_append-düşük-seviyeli-çağrı (sadece-op-taksonomisine-
# bakar, reason-15) veya-herhangi-bir-üçüncü-taraf-aracı R9-ihlali-içeren-bir
# anchor-yazabilir — o-yol-cmd_anchor'dan-GEÇMEZ. Kanıtlandı: R9-1..R9-5'in-
# hepsini-ihlal-eden-bir-kayıt hem-zincire-giriyor hem-de ledger-verify'da
# GREEN-geçiyordu (rc=0). D5-hash-byteleri-kilitler, ANLAMI-değil.
#
# EN-KRİTİK-R9-5: presentation_only-etiketsiz-bir-anchor-dış-fact'i-bizim
# doğrulamışımız-gibi-sunar — green-giydirme-işte-budur. Okuma-kapısı-onu-
# RED'ler (reason-16, delivery_hash/D12-shape-gate'leriyle-aynı-desen).
#
# GREEN: geçerli-anchor-içeren-ledger-GREEN-doğrulanır (geri-çekilme-yok).
# NEGATİFLER (her-biri-taze-pakette, tek-bir-kural-ihlal):
#   R9-1: anchor_version != TAMGA_EXTERNAL_ANCHOR_V1      → RED 16
#   R9-2: foreign_registry bilinmiyor                     → RED 16
#   R9-3: foreign_digest kanonik-değil (büyük-harf/kısa)  → RED 16
#   R9-4: verified_at RFC3339-UTC-Z-değil                 → RED 16
#   R9-5: presentation_only-eksik (green-giydirme)        → RED 16
#   idempotens: cmd_anchor'ın-kendisi-hala-çalışıyor (AT-059-yolu-bozulmadı)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-060/$(date +%F)/at060.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

FACT="0x02362521254a8ca4f75097267655f6aeb8524217a25c261f60538edc367136e2"
DIGEST="0x997c497ef5fe81b98290e990cd8f62e674bd55db8ab3c3ea85d3931b1e6ff71d"
VTIME="2026-09-10T07:32:08Z"

# kötü-kayıdı-düşük-seviyeden-yazan-araç (cmd_anchor'ı-atlar — üçüncü-taraf-
# aracı-simülasyonu). Mod-başına-bir-kural-ihlal-eder.
cat > "$LOG.inject.py" <<'PYEOF'
import sys, pathlib
PKG, MODE = sys.argv[1], sys.argv[2]
sys.path.insert(0, "."); sys.argv = ["x"]
import tamga_runner as TR
GOOD = {"op": "anchor", "anchor_version": "TAMGA_EXTERNAL_ANCHOR_V1",
        "foreign_registry": "apodix/epoch",
        "foreign_fact": "0x02362521254a8ca4f75097267655f6aeb8524217a25c261f60538edc367136e2",
        "foreign_digest": "0x997c497ef5fe81b98290e990cd8f62e674bd55db8ab3c3ea85d3931b1e6ff71d",
        "verified_at": "2026-09-10T07:32:08Z", "tool": "inject",
        "presentation_only": True}
rec = dict(GOOD)
if MODE == "good":
    pass
elif MODE == "r91_version":
    rec["anchor_version"] = "EVIL-V2"
elif MODE == "r92_registry":
    rec["foreign_registry"] = "evil/registry"
elif MODE == "r93_digest":
    rec["foreign_digest"] = "0XABC"          # büyük-harf + kısa
elif MODE == "r94_time":
    rec["verified_at"] = "2026-09-10"        # T/Z-yok
elif MODE == "r95_nopo":
    rec.pop("presentation_only")
else:
    sys.exit(2)
lp = pathlib.Path(PKG) / "ledger.jsonl"
r = TR._ledger_append(lp, rec)
sys.exit(0 if isinstance(r, dict) else 1)
PYEOF

note "AT-060: RFC-009-anchor-okuma-kapısı (yazma-yolu-yetmez)"

run_case() {  # $1=mod $2=beklenen-sonuç (RED|GREEN) $3=açıklama
  local MODE="$1" EXPECT="$2" DESC="$3"
  local PKG; PKG="$(mktemp -d)"
  python3 tamga_runner.py quickstart "$PKG" >> "$LOG" 2>&1 || true
  python3 "$LOG.inject.py" "$PKG" "$MODE" >> "$LOG" 2>&1
  python3 tamga_runner.py ledger-verify "$PKG" >> "$LOG" 2>&1
  local RC=$?
  if [ "$EXPECT" = "RED" ]; then
    if [ $RC -ne 0 ]; then PASS=$((PASS+1)); note "  PASS $DESC (RED rc=$RC)";
    else FAIL=$((FAIL+1)); note "  FAIL $DESC — GREEN-geçti (okuma-kapısı-yok)"; cat "$LOG"; fi
  else
    if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS $DESC (GREEN)";
    else FAIL=$((FAIL+1)); note "  FAIL $DESC — geri-çekildi"; cat "$LOG"; fi
  fi
  rm -rf "$PKG"
}

run_case good          GREEN "0) geçerli-anchor-GREEN-doğrulanır"
run_case r91_version   RED   "1) R9-1 yanlış-anchor_version"
run_case r92_registry  RED   "2) R9-2 bilinmeyen-foreign_registry"
run_case r93_digest    RED   "3) R9-3 kanonik-olmayan-digest"
run_case r94_time      RED   "4) R9-4 RFC3339-Z-değil"
run_case r95_nopo      RED   "5) R9-5 presentation_only-eksik (green-giydirme)"

# 6) REGRESYON: cmd_anchor'ın-kendisi-hala-çalışır — refactor-yazma-yolunu
# bozmamalı (AT-059'un-5/5-yolu). İlk-3-CLI-negatifi-hala-aynı-rc'lerle.
note "6) cmd_anchor-yazma-yolu-bozulmadı (AT-059-regresyonu)"
PKG6="$(mktemp -d)"
python3 tamga_runner.py quickstart "$PKG6" >> "$LOG" 2>&1
python3 tamga_runner.py anchor "$PKG6" --foreign-registry apodix/epoch \
  --foreign-fact "$FACT" --foreign-digest "$DIGEST" \
  --verified-at "$VTIME" --tool "regression" >> "$LOG" 2>&1
RC_GREEN=$?
python3 tamga_runner.py anchor "$PKG6" --foreign-registry evil/registry \
  --foreign-fact "$FACT" --foreign-digest "$DIGEST" \
  --verified-at "$VTIME" >> "$LOG" 2>&1
RC_REG=$?
python3 tamga_runner.py ledger-verify "$PKG6" >> "$LOG" 2>&1
RC_LV=$?
if [ $RC_GREEN -eq 0 ] && [ $RC_REG -ne 0 ] && [ $RC_LV -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 6) anchor-GREEN + registry-RED + verify-GREEN"
else
  FAIL=$((FAIL+1)); note "  FAIL 6) green=$RC_GREEN reg=$RC_REG verify=$RC_LV"; cat "$LOG"
fi
rm -rf "$PKG6"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-060: RFC-009-anchor-okuma-kapısı"
[[ $FAIL -eq 0 ]]
