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

# 7) boş-bundle: 0-olay kanıt-zarfı → makbuz ÜRETİLMEZ (taze-göz-bulgusu, 2026-09-13)
python3 - <<PYEOF
import json, pathlib
g = "0" * 64
b = {"pugio_bundle_version": 1, "events": [], "head": g,
     "merkle_root": g, "event_count": 0}
pathlib.Path("$W/empty.json").write_text(json.dumps(b))
PYEOF
python3 tamga_pugio_ingest.py "$W/empty.json" > "$W/empty.out" 2>&1
[ $? -ne 0 ] && grep -q "boş-bundle" "$W/empty.out" && ! grep -q "SAĞLAM" "$W/empty.out"
ok $? "boş-bundle (0-olay) → RED, makbuz ÜRETİLMEZ (boş-kanıt-yanılsaması-kapalı)"

# 8) non-dict-bundle (JSON-dizisi) → RED, traceback YOK (taze-göz O3)
printf '[1]' > "$W/nondict.json"
python3 tamga_pugio_ingest.py "$W/nondict.json" > "$W/nondict.out" 2>&1
[ $? -ne 0 ] && grep -q "RED" "$W/nondict.out" && ! grep -q "Traceback" "$W/nondict.out"
ok $? "non-dict-bundle → RED (traceback-YOK; fail-loud-sözleşmesi)"

# 9) dev-tam sayı (10**400 ts) → RED, traceback YOK (taze-göz O3)
python3 - <<PYEOF
import json, pathlib
g = "0" * 64
ev = {"seq": 1, "ts": 10**400, "event_type": "charge_receipt", "agent_id": "a",
      "host": "h", "amount": 1, "payload": "p", "prev_proof": g, "proof": "x"}
b = {"pugio_bundle_version": 1, "events": [ev], "head": "y",
     "merkle_root": "z", "event_count": 1}
pathlib.Path("$W/devint.json").write_text(json.dumps(b))
PYEOF
python3 tamga_pugio_ingest.py "$W/devint.json" > "$W/devint.out" 2>&1
[ $? -ne 0 ] && grep -q "RED" "$W/devint.out" && ! grep -q "Traceback" "$W/devint.out"
ok $? "dev-tam-sayı-ts → RED (float-taşması-yakalandı; traceback-YOK)"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]
