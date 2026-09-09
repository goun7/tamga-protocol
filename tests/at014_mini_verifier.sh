#!/usr/bin/env bash
# Audit-13 (AT-014) — B2 mini-verifier: runner-olmadan-zincir-doğrulaması.
# Kanıt-hedefi: (1) aynı-ledger'da-runner-ve-mini-AYNI-tip/AYNI-head (parite);
# (2) tamper-(amount-flip)-mini-RED; (3) devasa-satır-mini-RED-(bomba-yutulmaz);
# (4) --expect-tip-bağlama; (5) pip-kurulumu-OLMADAN çöl-dosyasıyla-çalışır.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AUDIT-13/$(date +%F)}/at014.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
export TAMGA_KS_PASSPHRASE=mini-2026
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
W=$(mktemp -d)

python3 - "$W" > "$LOG.1" 2>&1 <<'PYEOF'
import json, sys, pathlib, shutil
W = pathlib.Path(sys.argv[1])
shutil.copy("tests/vectors/tc-net-demo/tamga.json", W / "tamga.json")
shutil.copy("tests/vectors/tc-net-demo/agent.wasm", W / "agent.wasm")
sys.path.insert(0, ".")
import tamga_validator as tv
m = json.load(open(W / "tamga.json"))
sk = tv.SigningKey.generate()
m["signature"] = {"algo": "ed25519", "key": sk.verify_key.encode().hex(), "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(m)).signature.hex()
(W / "tamga.json").write_text(json.dumps(m, indent=2))
(W / "seed.hex").write_text(sk.encode().hex())
PYEOF
SEED=$(cat "$W/seed.hex")
python3 tamga_runner.py run "$W" --seed "$SEED" > /dev/null 2>&1
ok $? "kuruluş: taban-zincir-üretildi"

# (1) parite:
R1=$(python3 tamga_runner.py ledger-verify "$W" 2>/dev/null | python3 -c "import json,sys; r=json.load(sys.stdin); print(r['ok'], r['head'])")
R2=$(python3 tamga_verify_mini.py "$W/ledger.jsonl" | python3 -c "import json,sys; r=json.load(sys.stdin); print(r['ok'], r['head'])")
[ "$R1" = "$R2" ]; ok $? "parite: runner ≡ mini (ok + head birebir)"

TIP=$(echo "$R2" | cut -d' ' -f2)
python3 tamga_verify_mini.py "$W/ledger.jsonl" --expect-tip="$TIP" > "$LOG.2" 2>&1
grep -q '"ok": true' "$LOG.2"; ok $? "expect-tip-bağlaması: doğru-tip-kabul"

# (2) tamper:
python3 - "$W" <<'PYEOF'
import json, sys, pathlib
W = pathlib.Path(sys.argv[1])
lines = (W / "ledger.jsonl").read_text().splitlines()
rec = json.loads(lines[0]); rec["amount"] = 999.0
(W / "ledger.jsonl").write_text("\n".join([json.dumps(rec)] + lines[1:]) + "\n")
PYEOF
python3 tamga_verify_mini.py "$W/ledger.jsonl" > "$LOG.3" 2>&1
grep -q '"ok": false' "$LOG.3" && grep -q 'broken@' "$LOG.3"; ok $? "tamper-(amount-flip) → mini-RED"

# (3) satır-bombası-paritesi (Audit-11-kuralı-burada-da):
python3 - "$W" <<'PYEOF'
import json, sys, pathlib
W = pathlib.Path(sys.argv[1])
lines = (W / "ledger.jsonl").read_text().splitlines()
rec = json.loads(lines[0]); rec.pop("amount", None)
lines[0] = json.dumps(rec)
lines.append(json.dumps({"op": "x", "note": "B" * (50 * 1024 * 1024)}))
(W / "ledger.jsonl").write_text("\n".join(lines) + "\n")
PYEOF
python3 tamga_verify_mini.py "$W/ledger.jsonl" > "$LOG.4" 2>&1
grep -q '"ok": false' "$LOG.4" && grep -q 'bomba' "$LOG.4"; ok $? "50MB-satır → mini-RED-(yutulmadı, Audit-11-paritesi)"

# (4) çöl-modu: mini-sADECE-dosyayı-alır (runner/pkg-gerekmez):
cp "$W/ledger.jsonl" "$W/colon.jsonl"
( cd /tmp && python3 "$ROOT/tamga_verify_mini.py" "$W/colon.jsonl" ) > "$LOG.5" 2>&1; RC=$?
[ "$RC" -eq 1 ] && grep -q '"ok": false' "$LOG.5"; ok $? "çöl-modu: başka-cwd'den-sadece-dosya-yoluyla-koşar (rc=1-zincir-kırık-beklenir)"

rm -rf "$W"
python3 -c "
import sys; sys.path.insert(0, '.')
from tamga_verify_mini import foreign_leaf_verdict as fv
r1 = fv('TAMGA_CHAIN_HEAD_V1', 0x12, 0x34)
r2 = fv('', 1, 2)
r3 = fv('OTHER_V1', 1, 2)
r4 = fv('X', 0, 0)
assert r1[0] == 'indeterminate' and r2[0] == 'indeterminate' and r3[0] == 'indeterminate' and r4[0] == 'refuted', (r1, r2, r3, r4)
print('v3-verdict: F1-empty=indeterminate, F2-zero=refuted, unknown=indeterminate, known=indeterminate(presentation-only)')
" > "$LOG.v3" 2>&1
ok $? "v3-foreign-leaf: üç-verdict-disiplini (§4.4 indeterminate-never-absent)"

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
