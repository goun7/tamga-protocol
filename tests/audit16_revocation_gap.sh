#!/usr/bin/env bash
# Audit-16 — node-revocation-retirement-gap: "--node-revoked"-yalnız-L1-import-dalında-uygulanmış;
# MÜMKÜN-açık: ledger-verify-tek-başına-iptal-listesini-bilmiyor (retired-node-imzası-bağımsız-
# zincir-doğrulamasında-GEÇERLİ-kalır). BULGU-BEKLENTİSİ: açık-varsa-kanıtla, yoksa-belgele.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AUDIT-16/$(date +%F)}/audit16.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
export TAMGA_KS_PASSPHRASE=a16-2026
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
NID=$(python3 tamga_runner.py keygen-node "$W" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['node_id'])")
python3 tamga_runner.py run "$W" --seed "$SEED" --node-key "$NID" > /dev/null 2>&1
ok $? "kuruluş: node-cosign'lı-charge-kaydı"

python3 - "$W" > "$LOG.2" 2>&1 <<'PYEOF'
import json, sys, pathlib
W = pathlib.Path(sys.argv[1])
lines = [json.loads(l) for l in (W / "ledger.jsonl").read_text().splitlines() if l.strip()]
nid = [r.get("node_id") for r in lines if r.get("node_id")]
print("cosign'lı-kayıt:", bool(nid))
(W / "node_id.txt").write_text(nid[0] if nid else "")
sys.exit(0 if nid else 1)
PYEOF
ok $? "node_id-bulundu"

echo "[\"$NID\"]" > "$W/revoked.json"
echo "[\"$NID\"]" > "$W/trust.json"

# PROBE: ledger-verify--revocation-BİLMİYOR (kabul-kararı-araç-mimarisi):
python3 tamga_runner.py ledger-verify "$W" > "$LOG.3" 2>&1
grep -q '"ok": true' "$LOG.3"; ok $? "probe: verify-iptal-listesi-İSTEMEZ (mimari-gerçek; belgelendi)"

# PROBE: import-L1+revoked→RED-(OQ-3-kapısı-çalışıyor):
python3 tamga_runner.py export "$W" -o "$W/s.tsg" --seed "$SEED" > /dev/null 2>&1
mkdir -p "$W/target"
cp tests/vectors/tc-net-demo/tamga.json "$W/target/"
cp tests/vectors/tc-net-demo/agent.wasm "$W/target/"
rm -f "$W/target/ledger.jsonl"
python3 tamga_runner.py import "$W/s.tsg" "$W/target" --cosign-policy L1 --node-trust "$W/trust.json" --node-revoked "$W/revoked.json" > "$LOG.4" 2>&1
grep -q 'node_id_iptal_edildi\|node_id_untrusted' "$LOG.4"; ok $? "OQ-3: L1-import-iptal-listesi-RED"

rm -rf "$W"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
