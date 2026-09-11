#!/usr/bin/env bash
# AT-021 — quickstart wizard: ilk-paket-tek-komut-akışı (B1; kurucu-ONAYLI 2026-09-11)
# Kanit-kulturu: yesil-akis + 3-negatif (isim-kurali / dolu-hedef / tekrar-hedef).
# Negatif-semantik: wizard RED'lerinde rc=1 BEKLENIR (bekle_red kullanilir).
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-021/$(date +%F)}/at021.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1) GREEN: tam-akis (5-adim + rc=0)
python3 tamga_runner.py quickstart "$WORK/ilk" > "$LOG.1" 2>&1
ok $? "quickstart: tam-akis-yesil (paket+imza+run+zincir)"

# 2) GREEN: sozlesme (deterministik-seed + disk-iz + spec 0.2.0 + 5-adim)
python3 - "$WORK" > "$LOG.2" 2>&1 <<'PYEOF'
import json, pathlib, subprocess, sys
work = pathlib.Path(sys.argv[1])
r = subprocess.run(["python3", "tamga_runner.py", "quickstart", str(work / "ilk2"),
                    "--name", "test-quickstart", "--seed", "11" * 32],
                   capture_output=True, text=True)
d = json.loads(r.stdout)
assert d["ok"] is True and r.returncode == 0
assert len(d["steps"]) == 5, d["steps"]
assert d["package"] == "test-quickstart"
assert d["seed_hex"] == "11" * 32
assert d["agent_id"] and len(d["agent_id"]) == 64
pkg = work / "ilk2"
for f in ("tamga.json", "agent.wasm", "ledger.jsonl", "state.json"):
    assert (pkg / f).exists(), f
m = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
assert m["package"]["name"] == "test-quickstart"
assert m["spec_version"] == "0.2.0"
print("quickstart: cikti-sozlesmesi + disk-iz + deterministik-seed ok")
PYEOF
ok $? "quickstart: sozlesme (5-adim + spec 0.2.0 + disk-iz + deterministik-seed)"

# 3) NEGATIF-1: isim-kurali-disi → rc=1 BEKLENIR
if python3 tamga_runner.py quickstart "$WORK/bad" --name "Kötüİsim" > "$LOG.3" 2>&1; then
  ok 1 "quickstart-negatif: gecersiz-isim RED"
else
  ok 0 "quickstart-negatif: gecersiz-isim RED"
fi

# 4) NEGATIF-2: dolu-hedef → rc=1 BEKLENIR (uzerine-yazma-kulturu-yok)
mkdir -p "$WORK/dolu"; echo x > "$WORK/dolu/mevcut.txt"
if python3 tamga_runner.py quickstart "$WORK/dolu" > "$LOG.4" 2>&1; then
  ok 1 "quickstart-negatif: dolu-hedef RED"
else
  ok 0 "quickstart-negatif: dolu-hedef RED"
fi

# 5) NEGATIF-3: ayni-hedef-tekrar → rc=1 BEKLENIR (ilk2 artik dolu)
if python3 tamga_runner.py quickstart "$WORK/ilk2" > "$LOG.5" 2>&1; then
  ok 1 "quickstart-negatif: hedef-artik-dolu RED (tekrar-yasak)"
else
  ok 0 "quickstart-negatif: hedef-artik-dolu RED (tekrar-yasak)"
fi

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]
