#!/usr/bin/env bash
# Tamga 30-saniyelik demo — öl → taşı → diril → makbuzu doğrula
# Kayıt: asciinema rec -c "bash tools/demo.sh" docs/assets/demo.cast  (kurulumdan sonra)
# Onay: her adımın beklenen-çıkışı satır içi yorumda; ayrıntı docs/DEMO-SENARYO.md
set -euo pipefail
cd "$(dirname "$0")/.."
export TAMGA_KS_PASSPHRASE="simnet-2026"          # simnet sabiti — gerçek sır değil
W=tests/simnet/.demo; rm -rf "$W"; mkdir -p "$W/node1/pkg" "$W/node2/pkg"

echo "# 1) Ajan kimliği üretilir (seed YALNIZ stdout'a — diske yazılmaz)"
SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')

echo "# 2) node1'de ajan girdili iş yapar (Dilim-11): girdi-hash'i makbuza bağlanır"
cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$W/node1/pkg/"
python3 tamga_validator.py sign "$W/node1/pkg/tamga.json" "$W/node1/pkg/agent.wasm" tests/keys/operator/seed.hex > /dev/null
printf '{"gorev":"ozet","v":7}' > "$W/girdi.json"
python3 tamga_runner.py grant "$W/node1/pkg" 0.02 "demo-hibe" > /dev/null
python3 tamga_runner.py run "$W/node1/pkg" --seed "$SEED" --input "$W/girdi.json" --require-proof --note "node1-de doğdu" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  koşum ok:", d["ok"], "| ücret:", d["fee_sim"])'

echo "# 3) makine ölür — ajan ŞİFRELİ snapshot'la taşınır"
python3 tamga_runner.py export "$W/node1/pkg" -o "$W/ajan.tsg" --seed "$SEED" > /dev/null
python3 - <<'PY'
import pathlib, json, hashlib
b = pathlib.Path("tests/simnet/.demo/ajan.tsg").read_bytes()
head = b[:2]
print("  snapshot:", len(b), "bayt | gövde-düz-metin taraması:", b.count(b'"text"'), " ham-json-imzası (0 beklendik)")
PY

echo "# 4) node2 (farklı dizin) ajanı KALDIĞI YERDEN diriltir"
cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$W/node2/pkg/"
python3 tamga_validator.py sign "$W/node2/pkg/tamga.json" "$W/node2/pkg/agent.wasm" tests/keys/operator/seed.hex > /dev/null
python3 tamga_runner.py import "$W/ajan.tsg" "$W/node2/pkg" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  import ok:", d["ok"], "| ajan:", d.get("agent_id","")[:16] + "…", "| restore-düğüm:", d.get("memory_nodes"), "| devam-oturumu:", d.get("resumed_session"))'

echo "# 5) makbuz zinciri hedef-node'da doğrulanır"
python3 tamga_runner.py ledger-verify "$W/node2/pkg" | python3 -c 'import sys,json;print("  ledger-verify ok:", json.load(sys.stdin)["ok"])'
python3 tamga_runner.py memory "$W/node2/pkg" --search "node1" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  hafıza-hatırlama:", d["hits"] if "hits" in d else d)'
rm -rf "$W"
echo "# demo-bitti — 30 saniyede: doğdu → girdili-iş yaptı → öldü → taşındı → dirildi → kanıtlandı"
