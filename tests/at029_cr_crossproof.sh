#!/usr/bin/env bash
# AT-029 — CR-v0.1 canonicalisation CROSS-PROOF (in-toto PR-592 / Anomly; dış-vektör,
# kendi-muskül: tamga_verify_mini.jcs — epoch-anchor digest yolu — upstream'in tarafsız
# runner'ıyla notlanır). Kapsam-dürüstlüğü: yalnız 8-vektörlük canonicalisation-katmanı;
# receipt/verdict katmanı CR-aritmetiğidir, Tamga CR-certifier değildir — iddia edilmez.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-029/$(date +%F)}/at029.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)

# 1) vendor bütünlüğü: upstream dosyaları hash-pin'li (VENDOR-NOTE.md ile aynı-değerler) —
#    suskun-kayma-yok; upstream değişirse bu-kontrol KIRMALI olur, tazeleme-bilinçli-olur.
python3 - "$T" <<'PYEOF' > "$LOG.1" 2>&1
import hashlib, pathlib, sys
pins = {
  "tests/vendor-cr/spec/CR-v0.1-conformance-vectors.json":
    "2e940bf3006d95481690c9f264b9f1a4d23b076db4793a046c8abf940eb13e02",
  "tests/vendor-cr/python/conformance_runner.py":
    "4e9216e85ba1bd727c595cf7246eb9730654ed4bf6a508ed5336e1e8b97b2e2f",
}
bad = [p for p, h in pins.items()
       if hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() != h]
pathlib.Path(sys.argv[1], "pin.ok").write_text("0" if not bad else "1")
print("pin-ihlali:", bad if bad else "YOK")
PYEOF
ok "$(cat "$T/pin.ok" 2>/dev/null || echo 1)" "vendor-hash-pin'leri sağlam (vektör+runner byte-identical)"

# 2) aday-üretimi + hakem-notu: tamga jcs-yolu → 8/8 (rc0 + özeti-satırda-gör)
python3 tools/cr_crossproof.py > "$T/cand.json" 2>"$LOG.gen"
ok $? "aday-üretildi (tools/cr_crossproof.py, stdlib+tamga.jcs)"
python3 tests/vendor-cr/python/conformance_runner.py "$T/cand.json" \
  --require canonicalisation > "$T/grade.out" 2>&1
RC=$?
if [ "$RC" -eq 0 ] && grep -q "canonicalisation 8/8" "$T/grade.out" \
   && grep -q "PASS: required layer" "$T/grade.out"; then ok 0 "upstream-runner: 8/8 cross-proof PASS (rc0)"; else ok 1 "runner-notu: $RC — $(tail -1 "$T/grade.out")"; fi

# 3) kapsam-dürüstlüğü: aday SADECE canonicalisation-adi taşır (receipt/refuse sızıntısı
#    olsa "hepsini-geçtim" sahte-iddiasına-dönüşürdü) — bayt-kaydı:
python3 - "$T/cand.json" <<'PYEOF' >> "$LOG.3" 2>&1
import json, sys
names = [v["name"] for v in json.load(open(sys.argv[1]))]
assert len(names) == 8 and all(n.startswith(("canonical/", "tensor/", "tensors/")) for n in names), names
PYEOF
ok $? "kapsam-dürüstlüğü: tam-8-vektör, yalnız-canonicalisation-katmanı"

# 4) negatif-vektör (kabul-yolunu-kırmadan-RED-kanıtı): kaçış-vektörü-digest'ine-bayt-
#    kazıma → hakem RED vermeli (rc!=0 veya PASS-satırı-yok) — pass-path-kırılmadan.
python3 - "$T/cand.json" "$T/tampered.json" <<'PYEOF' >> "$LOG.4" 2>&1
import json, pathlib, sys
cand = json.load(open(sys.argv[1]))
for v in cand:
    if v["name"] == "canonical/escaping":
        v["digest"] = v["digest"][:-1] + ("0" if v["digest"][-1] != "0" else "1")
pathlib.Path(sys.argv[2]).write_text(json.dumps(cand))
PYEOF
python3 tests/vendor-cr/python/conformance_runner.py "$T/tampered.json" \
  --require canonicalisation > "$T/tam.out" 2>&1
RC=$?
if [ "$RC" -ne 0 ] && grep -q "FAIL" "$T/tam.out"; then ok 0 "negatif: digest-kazıması hakemce RED (rc$RC)"; else ok 1 "kazıma-yakalanmadı (rc$RC) — HAKEM-GÜVENSİZ"; fi

rm -rf "$T"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
