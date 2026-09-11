#!/usr/bin/env bash
# AT-016 — explain CLI end-to-end (insan-dilli-kanıt-özet; D5-yeniden-hesap-yolçapı)
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-016/$(date +%F)}/at016.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)

# 1) fixture-charge-üzerinden-TR:
python3 - "$T" > "$LOG.1" 2>&1 <<'PYEOF'
import json, sys, pathlib
fx = json.loads(pathlib.Path("docs/pairing/pairing-fixture.json").read_text(encoding="utf-8"))
rec = fx["tamga_observed"]["charge_record"]["value"]
pathlib.Path(sys.argv[1], "rec.json").write_text(json.dumps(rec), encoding="utf-8")
PYEOF
python3 tools/explain.py "$T/rec.json" > "$T/tr.out" 2>&1
ok $? "explain TR: fixture-charge-çalıştı"
if grep -q "Zincir-dürüstlüğü: h DOĞRULANDI" "$T/tr.out"; then ok 0 "TR: zincir-dürüstlüğü-DOĞRULANDI-satırı"; else ok 1 "TR: zincir-dürüstlüğü-DOĞRULANDI-satırı"; fi
if grep -q "seq 2" "$T/tr.out"; then ok 0 "TR: seq-2-etiketi"; else ok 1 "TR: seq-2-etiketi"; fi

# 2) EN-yolçapı:
python3 tools/explain.py --en "$T/rec.json" > "$T/en.out" 2>&1
ok $? "explain EN: çalıştı"
if grep -q "Chain integrity: h VERIFIED" "$T/en.out"; then ok 0 "EN: chain-integrity-VERIFIED-satırı"; else ok 1 "EN: chain-integrity-VERIFIED-satırı"; fi

# 3) TAMPER-bulma-(kurcalanmış-kayıt→EŞLEŞMİYOR-RED-beyanı):
python3 - "$T" > "$LOG.3" 2>&1 <<'PYEOF'
import json, sys, pathlib
fx = json.loads(pathlib.Path("docs/pairing/pairing-fixture.json").read_text(encoding="utf-8"))
rec = fx["tamga_observed"]["charge_record"]["value"]
rec["fee_sim"] = rec["fee_sim"] * 2   # hash-içeriği-kurcala
pathlib.Path(sys.argv[1], "tampered.json").write_text(json.dumps(rec), encoding="utf-8")
PYEOF
python3 tools/explain.py "$T/tampered.json" > "$T/tampered.out" 2>&1
if grep -q "EŞLEŞMİYOR" "$T/tampered.out"; then ok 0 "TAMPER: kurcalanmış-kayıt-EŞLEŞMİYOR-RED"; else ok 1 "TAMPER: kurcalanmış-kayıt-EŞLEŞMİYOR-RED"; fi

# 4) receipt-yolçapı-(dx402-kanonik-kontrol):
ls private/external-evidence/2026-09-07-dx402-canonical/recv-canonical.json > /dev/null 2>&1
if [ $? -eq 0 ]; then
  python3 tools/explain.py private/external-evidence/2026-09-07-dx402-canonical/recv-canonical.json > "$T/receipt.out" 2>&1
  if grep -q "kanonik 0x+64-lower" "$T/receipt.out"; then ok 0 "receipt: kanonik-kontrol-satırı"; else ok 1 "receipt: kanonik-kontrol-satırı"; fi
else
  echo "  SKIP: receipt-fixture-bu-makinede-yok" | tee -a "$LOG"; PASS=$((PASS+1))
fi

# 5) kök-modül-yolçapı (0.2.2: tamga_explain wheel-yüzeyi; alias-değil-asıl):
python3 tamga_explain.py "$T/rec.json" > "$T/root.out" 2>&1
ok $? "kök-modül: tamga_explain-aynı-çıktı"
if [ "$T/tr.out" ] && cmp -s "$T/root.out" <(python3 tools/explain.py "$T/rec.json" 2>&1); then ok 0 "kök-modül == alias (bayt-eşit-çıktı)"; else ok 1 "kök-modül-çıktı-alias'tan-farklı"; fi

rm -rf "$T"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
