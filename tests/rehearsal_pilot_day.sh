#!/usr/bin/env bash
# A3 — İki-taraflı pilot-günü PROVASI (rehearsal): bizim-her-iki-rolümüzle 113B akışını
# uçtan-uca simüle eder — sıfır-ağ, sıfır-yeni-kod (yalnız-mevcut-araçların-bütünlüğü).
#
# Rol-A (bizim-node): taze-pkg + grant + run --delivery-alg keccak256 → fixture-üretimi
# Rol-B (karşı-taraf-doğrulayıcı): receipt.json-(mock-settlement)+blob'u-alır; verify_dx402_vector
#   paymentId/ecrecover-SKIP-yoluyla-çalışır (mock' unverifiable-ama-etiketli) + --pair-charge
#   bizim-ledger'ıyla-ÇAPRAZ-KÖPRÜ → EŞ-beklenir.
# Çıktı: prova-raporu (süre, komut-sayısı, PASS/FAIL) — pilot-günü-şablonu.
set -u
PASS=0; FAIL=0; LOG=".evidence/REHEARSAL/$(date +%F)/pilot-day.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
export TAMGA_KS_PASSPHRASE=simnet-2026
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
T0=$(date +%s)

W=$(mktemp -d)
# --- Rol-A: makbuz-üretimi ---
NET='{"format":"tamga-net-declaration/1","egress":["127.0.0.1:1"],"max_bytes_per_run":1048576,"timeout_s":10}'
python3 tools/make_pairing_fixture.py "$W/pkgA" "$W/pairing" > "$W/make.json" 2>>"$LOG"
ok $? "A: fixture-üretimi (make_pairing_fixture: keygen+grant+run+delivery-hash)"
grep -q '"ok": true' "$W/make.json"; ok $? "A: fixture-JSON geçerli"

# --- Rol-B: karşı-taraf-doğrulama (bizim-araçlarla) ---
python3 tools/verify_pairing_fixture.py "$W/pairing" > "$W/verify.json" 2>>"$LOG"
ok $? "B: pairing-fixture-doğrulaması (6/6-beklenir)"
grep -q '"ok": true' "$W/verify.json"; ok $? "B: verify_pairing_fixture ok=true"

# --- ÇAPRAZ-KÖPRÜ: charge.delivery_hash == delivery_bytes.keccak256 ---
python3 - "$W" > "$LOG.bridge" 2>&1 <<'PYEOF'
import json, subprocess, sys, pathlib
W = pathlib.Path(sys.argv[1])
fx = json.load(open(f"{W}/pairing/pairing-fixture.json"))
charge = fx["tamga_observed"]["charge_record"]["value"]
dhash = charge["delivery_hash"]["hex"]
(W / "ledger.jsonl").write_text(json.dumps(charge) + "\n")
(W / "recv-eq.json").write_text(json.dumps({"receipt": {"contentHash": "0x" + dhash}}))
r = subprocess.run([sys.executable, "tools/verify_dx402_vector.py", "--pair-charge", str(W / "recv-eq.json"), str(W / "ledger.jsonl")], capture_output=True, text=True)
print(r.stdout)
sys.exit(r.returncode)
PYEOF
ok $? "KÖPRÜ: charge.delivery_hash ↔ receipt.contentHash eş-kararı (--pair-charge)"

T1=$(date +%s); echo "prova-süresi: $((T1-T0))s, komut-izleri: $LOG" | tee -a "$LOG"
rm -rf "$W"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
