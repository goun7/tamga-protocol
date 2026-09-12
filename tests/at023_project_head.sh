#!/usr/bin/env bash
# AT-023 - project-head CLI (zincirbaşı → batch-yaprak izdüşümü; RFC-009/AT-022'in kullanıcı-yüzeyi)
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-023/$(date +%F)}/at023.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export TAMGA_KS_PASSPHRASE=at023-pass-2026

# 1) gerçek-paket: quickstart + grant (defterde en-az-bir-charge; engine-gerekmez)
python3 tamga_runner.py quickstart "$W/pkg" >/dev/null 2>&1 || true
python3 tamga_runner.py grant "$W/pkg" 0.01 "at023" >/dev/null 2>&1 || true
[ -f "$W/pkg/ledger.jsonl" ]; ok $? "kurulum: gerçek-paket + defter-var"

# 2) CLI-çıktı-sözleşmesi: alanlar + D5-parite + yaprak-kodlama-AT-022-birebir
python3 - > "$LOG.1" 2>&1 <<PYEOF
import json, hashlib, subprocess, sys, pathlib
sys.path.insert(0, ".")
from tamga_project_head import chain_head, project
from tamga_keccak import keccak256

out = subprocess.run(["python3", "tamga_bootstrap.py", "project-head", "$W/pkg"],
                     capture_output=True, text=True, check=True).stdout
d = json.loads(out)
head, n = chain_head(pathlib.Path("$W/pkg"))
assert d["chain_head"] == head, "CLI-başı ≠ yeniden-hesap"
assert d["ledger_lines"] == n and n >= 1
assert d["projection_version"] == "TAMGA_PROJECT_HEAD_V1"
K = lambda b: bytes.fromhex(keccak256(b).hex())
assert d["leaf_encoded"] == "0x" + K(K(bytes.fromhex(head))).hex(), "yaprak ≠ AT-022-şeması"
assert "presentation-only" in d["honest_boundary"]
print("CLI-sözleşme: baş/parite/yaprak/dürüstlük-sınırı TAM")
PYEOF
ok $? "CLI-çıktısı: D5-parite + AT-022-yaprak-şeması + sunum-paritesi-notu"

# 3) -o-dosya-yolu
python3 tamga_bootstrap.py project-head "$W/pkg" -o "$W/head.json" >/dev/null 2>&1
ok $? "CLI: -o dosya-yolu"

# 4) bozuk-zincir → RED (reason-14-ailesi; exit-1)
cp -r "$W/pkg" "$W/bad" 2>/dev/null
printf '%s\n' '{"seq": 99, "op": "charge", "prev": "deadbeef", "val": 1, "h": "0000000000000000000000000000000000000000000000000000000000000000"}' >> "$W/bad/ledger.jsonl"
python3 tamga_bootstrap.py project-head "$W/bad" >/dev/null 2>&1
[ $? -ne 0 ]; ok $? "bozuk-zincir → RED (h-eşleşmez; exit≠0)"

# 5) defter-yok → RED
python3 tamga_bootstrap.py project-head "$W/yok" >/dev/null 2>&1
[ $? -ne 0 ]; ok $? "defter-yok → RED"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]
