#!/usr/bin/env bash
# Audit-17 — export-snapshot bayt-matrisi (F24 kripto-yüzeyi sertleştirmesi)
# Kurcalama sınıfları: truncate / gövde-bit-flip / header-flip / son-bayt / swap / magic-swap
# Beklenen: hepsi RED (fail-closed), kimisi plaintext-sızıntısına dönüşmez; header
# yalnız gerçek-değil-olan alanlar taşır (RFC-002 E-2: format/pkg_name/sha256/nonce —
# ciphertext + keystore blob şifreli; 'tamga'/'agent' kelimesi yalnız header'da设计 gereği).
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AUDIT-17/$(date +%F)}/audit17.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
export TAMGA_KS_PASSPHRASE=a17-2026
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
python3 tamga_runner.py export "$W" -o "$W/snap.tsg" --seed "$SEED" > /dev/null 2>&1
ok $? "kuruluş: taban-snapshot (1.8 KB)"
python3 - "$W" > "$LOG.h" 2>&1 <<'PYEOF'
import sys, pathlib
snap = (pathlib.Path(sys.argv[1]) / "snap.tsg").read_bytes()
body = snap[512:]
# ciphertext-bölgesinde-plaintext-desenler-YOK (header-dışı):
leaks = [t for t in (b"delivery_hash", b"fee_sim", b"stdout_sha256", b"memory_probe") if t in body]
sys.exit(0 if not leaks else 1)
PYEOF
ok $? "gizlilik: gövde-(ciphertext)-bölgesinde-alan-adı-deseni YOK (yalnız-header-dizayn)"

python3 - "$W" "$SEED" > "$LOG.m" 2>&1 <<'PYEOF'
import json, subprocess, sys, pathlib, os
W, seed = pathlib.Path(sys.argv[1]), sys.argv[2]
snap = (W / "snap.tsg").read_bytes()
env = dict(os.environ)
def imp(data, label):
    p = W / "mod.tsg"
    p.write_bytes(data)
    r = subprocess.run(["python3", "tamga_runner.py", "import", str(p), str(W / "tgt"), "--seed", seed],
                       capture_output=True, text=True, env=env)
    print(f"{label:<20} rc={r.returncode} {r.stdout.strip()[:56]}")
    return r.returncode
cases = [
    ("truncate-yarı", snap[: len(snap)//2]),
    ("gövde-bit-flip", snap[:len(snap)//2] + bytes([snap[len(snap)//2] ^ 1]) + snap[len(snap)//2+1:]),
    ("header-flip", bytes([snap[10] ^ 1]) + snap[1:]),
    ("son-bayt-flip", snap[:-1] + bytes([snap[-1] ^ 1])),
    ("iki-bayt-swap", snap[:10] + bytes([snap[11], snap[10]]) + snap[12:]),
    ("magic-swap", b"XSG1" + snap[4:]),
]
sys.exit(0 if all(imp(d, l) == 1 for l, d in cases) else 1)
PYEOF
ok $? "kurcalama-matrisi: 6/6-sınıf-RED (fail-closed, reason_code-1/3)"

rm -rf "$W"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
