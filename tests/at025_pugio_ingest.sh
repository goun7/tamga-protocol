#!/usr/bin/env bash
# AT-025 - PUGIO K0 kanıt-bundle ingest (81-MERGEN tarafı okuyucu; RFC-009 receiver-2.-adım)
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-025/$(date +%F)}/at025.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# 1) selftest: temiz-bundle SAĞLAM + kazınmış RED + makbuz-bağı
python3 tamga_pugio_ingest.py --selftest > "$LOG.st" 2>&1
ok $? "selftest: temiz→SAĞLAM, kazınmış→RED, makbuz-bağı"

# 2) gerçek-akış: mini-bundle üret → doğrula → makbuz-al (tam-yol)
python3 - > "$W/flow.out" 2>&1 <<PYEOF
import hashlib, json, pathlib, subprocess, time
from tamga_pugio_ingest import _canonical, _merkle, GENESIS

events, prev = [], GENESIS
for i, (et, amount) in enumerate([("charge_receipt", 0.02), ("charge_receipt", 0.03),
                                  ("permission_decision", 0.0)]):
    ev = {"seq": i+1, "ts": time.time(), "event_type": et, "agent_id": "ag-at025",
          "host": "/api", "amount": amount, "payload": '{"i":%d}' % i, "prev_proof": prev}
    ev["proof"] = hashlib.sha256(_canonical(ev, prev).encode()).hexdigest()
    events.append(ev); prev = ev["proof"]
bundle = {"pugio_bundle_version": 1, "generated": time.time(), "agent": "ag-at025",
          "head": prev, "merkle_root": _merkle([e["proof"] for e in events]),
          "event_count": len(events), "events": events}
pathlib.Path("$W/bundle.json").write_text(json.dumps(bundle))

r = subprocess.run(["python3", "tamga_pugio_ingest.py", "$W/bundle.json"],
                   capture_output=True, text=True)
assert r.returncode == 0, r.stdout + r.stderr
assert "SAĞLAM" in r.stdout
rec = json.loads([l.split(":", 1)[1].strip() for l in r.stdout.splitlines()
                  if l.startswith("makbuz")][0])
assert rec["type"] == "pugio_bundle_verification" and rec["verdict"] == "SAĞLAM"
assert rec["audit"]["receipts"] == 2 and rec["audit"]["decisions"] == 1
assert abs(rec["audit"]["charge_total"] - 0.05) < 1e-9
expect = hashlib.sha256(f"SAĞLAM|{bundle['head']}|{bundle['merkle_root']}|{len(events)}".encode()).hexdigest()[:32]
assert rec["receipt_id"] == expect, "makbuz-bağı kopuk"
print("tam-yol: üret→doğrula→makbuz (audit-toplamlarıyla) TAM")
PYEOF
ok $? "tam-yol: bundle üretimi → doğrulama → deterministik makbuz (audit dahil)"

# 3) head-tampering: en son proof'un payload'ı değişir → proof-uyuşmazlığı RED
python3 - <<PYEOF
import json, pathlib
b = json.loads(pathlib.Path("$W/bundle.json").read_text())
b["events"][-1]["payload"] = '{"i":"KAZIK"}'
pathlib.Path("$W/bad.json").write_text(json.dumps(b))
PYEOF
python3 tamga_pugio_ingest.py "$W/bad.json" > "$W/bad.out" 2>&1
[ $? -ne 0 ] && grep -q "RED" "$W/bad.out"
ok $? "payload-kazıma → proof-uyuşmazlığı RED (makbuz ÜRETİLMEZ)"

# 4) merkle-kökü kazıma: kök alanı elle değişmiş → RED
python3 - <<PYEOF
import json, pathlib
b = json.loads(pathlib.Path("$W/bundle.json").read_text())
b["merkle_root"] = "f" * 64
pathlib.Path("$W/bad2.json").write_text(json.dumps(b))
PYEOF
python3 tamga_pugio_ingest.py "$W/bad2.json" > "$W/bad2.out" 2>&1
[ $? -ne 0 ] && grep -q "merkle" "$W/bad2.out"
ok $? "merkle-kökü değişimi → RED"

# 5) event_count sahteciliği → RED
python3 - <<PYEOF
import json, pathlib
b = json.loads(pathlib.Path("$W/bundle.json").read_text())
b["event_count"] = 999
pathlib.Path("$W/bad3.json").write_text(json.dumps(b))
PYEOF
python3 tamga_pugio_ingest.py "$W/bad3.json" > "$W/bad3.out" 2>&1
[ $? -ne 0 ] && grep -q "event_count" "$W/bad3.out"
ok $? "event_count sahteciliği → RED"

# 6) sürüm-kapısı: pugio_bundle_version=2 → RED
python3 - <<PYEOF
import json, pathlib
b = json.loads(pathlib.Path("$W/bundle.json").read_text())
b["pugio_bundle_version"] = 2
pathlib.Path("$W/bad4.json").write_text(json.dumps(b))
PYEOF
python3 tamga_pugio_ingest.py "$W/bad4.json" > "$W/bad4.out" 2>&1
[ $? -ne 0 ] && grep -q "sürüm" "$W/bad4.out"
ok $? "bilinmeyen-bundle-sürümü → RED (sürüm-kapısı)"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]
