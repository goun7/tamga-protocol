#!/usr/bin/env bash
# AT-018 - M6: manifest v0.3.0 DRAFT schema (RFC-008 external-receipt; additive contract)
# Additive-contract: 0.2.0-sembada-VALID-olan-her-manifest-0.3.0-da-da-VALID-kalmali
# (regresyon-yok); 0.2.0-da-RED-olanlar-(tc-a3 admin_backdoor gibi)-0.3.0-da-da-RED-kalmali.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-018/$(date +%F)}/at018.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"
VENV=".venv-jsonschema/bin/python"
[ -x "$VENV" ] || VENV=python3

"$VENV" - > "$LOG.1" 2>&1 <<'PYEOF'
import json, jsonschema, pathlib
s3 = json.load(open("specs/manifest-0.3.0-draft.schema.json"))
v = jsonschema.Draft202012Validator(s3)
w = pathlib.Path("tests/vectors/m6-external-receipt")
ok_ext = json.load(open(w / "ok-external-receipt.json"))
assert not list(v.iter_errors(ok_ext)), "ok-vektoru-RED-dustu"
for f in sorted(w.glob("red-*.json")):
    errs = list(v.iter_errors(json.load(open(f))))
    assert errs, f.name + " - RED-olmaliydi ama VALID cikti"
print("5-sentetik-vektor: 1-VALID + 4-RED-beklenigi-gibi")
PYEOF
ok $? "M6: sentetik-vektorler (1-VALID + 4-RED beklenigi-gibi)"

"$VENV" - > "$LOG.2" 2>&1 <<'PYEOF'
import json, jsonschema, pathlib
s2 = json.load(open("specs/manifest-0.2.0-draft.schema.json"))
s3 = json.load(open("specs/manifest-0.3.0-draft.schema.json"))
v2 = jsonschema.Draft202012Validator(s2)
v3 = jsonschema.Draft202012Validator(s3)
valid_n = red_n = 0
for d in sorted(pathlib.Path("tests/vectors").iterdir()):
    m = d / "tamga.json"
    if not m.exists():
        continue
    man = json.load(open(m))
    red2 = list(v2.iter_errors(man))
    red3 = list(v3.iter_errors(man))
    if red2:
        assert red3, d.name + " - 0.2.0-RED ama 0.3.0-VALID: ADDITIVE-IHLAL"
        red_n += 1
    else:
        assert not red3, d.name + " - 0.2.0-VALID ama 0.3.0-RED: REGRESYON"
        valid_n += 1
assert valid_n >= 6 and red_n >= 2, (valid_n, red_n)   # tc-a3+a4-adversarial-beklenir
print(f"additive-contract: {valid_n}-VALID-korundu + {red_n}-RED-korundu (adversarial-dahil)")
PYEOF
ok $? "M6: additive-contract (VALID-koruma + RED-koruma)"

"$VENV" - > "$LOG.3" 2>&1 <<'PYEOF'
import json, jsonschema
s3 = json.load(open("specs/manifest-0.3.0-draft.schema.json"))
s2 = json.load(open("specs/manifest-0.2.0-draft.schema.json"))
v2 = jsonschema.Draft202012Validator(s2)
ok_ext = json.load(open("tests/vectors/m6-external-receipt/ok-external-receipt.json"))
errs = list(v2.iter_errors(ok_ext))
assert errs, "0.3.0-manifest-0.2.0-sembada-VALID-cikti - yukseltme-izolasyonu-bozuk"
assert any("external_receipt" in e.message for e in errs), "hata-external_receipt-i-gostermeli"
print("0.3.0-yeniligi 0.2.0-sembada RED (izolasyon-dogru: yukseltme-opsiyonel-gorunur)")
PYEOF
ok $? "M6: 0.2.0-sembada-0.3.0-iddialari-RED (izolasyon-kontrolu)"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]
