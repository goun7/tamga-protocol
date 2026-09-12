#!/usr/bin/env bash
# Audit-19 — import fail-path zaman-tüneli ölçümü (mükemmelliyet-yolu Boyut-2)
# Soru: scrypt-unlock-RED-(yanlış-şifre)-başarıdan-ANLAMLI-farklı-zamanda-mı?
# Bağlam: import-yerel-CLI — saldırgan-çıktıyı-zaten-görür; zaman-tüneli-yalnız-uzak-
# oracle-senaryosunda-anlamı-var. Ölçüm-dokümantasyonu-yine-de-dürüstlük-gereği.
# Beklenen: KDF-(scrypt)-her-yolçapta-TAM-koşar-(xdec-içinde-AEAD-doğrulamasına-kadar);
# unlock-RED≈başarı-(oran~1.0); magic-RED-kdf'e-gelmeden-döner-ama-yorumlayıcı-başlangıcı-
# (~50ms)-dominant-olduğundan-duvar-süresi-farkı-sinyal-değil.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AUDIT-19/$(date +%F)}/audit19.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
export TAMGA_KS_PASSPHRASE=a19-2026
cd "$(cd "$(dirname "$0")/.." && pwd)"
W=$(mktemp -d)

python3 - "$W" > "$LOG.setup" 2>&1 <<'PYEOF'
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
ok $? "kuruluş: taban-snapshot"

python3 - "$W" > "$LOG.timing" 2>&1 <<'PYEOF'
import json, subprocess, tempfile, pathlib, shutil, os, sys, time, statistics
W = pathlib.Path(sys.argv[1])
env = dict(os.environ)
snap = (W / "snap.tsg").read_bytes()
def timed(snapdata, tgt, envpass, reps=7):
    ts = []
    for _ in range(reps):
        shutil.rmtree(tgt, ignore_errors=True)
        p = W / "probe.tsg"; p.write_bytes(snapdata)
        t0 = time.perf_counter()
        r = subprocess.run(["python3", "tamga_runner.py", "import", str(p), str(tgt)],
                           capture_output=True, text=True, env=envpass)
        ts.append((time.perf_counter() - t0) * 1000)
    return statistics.median(ts)
m_bad = b"XSG1" + snap[4:]
env_bad = dict(env, TAMGA_KS_PASSPHRASE="yanlis-parola-9")
mc = timed(m_bad, W / "tgt_c", env)
ma = timed(snap, W / "tgt_a", env_bad)
mb = timed(snap, W / "tgt_b", env)
print(f"C-magic-RED  : {mc:.1f} ms (kdf-öncesi-dönüş beklenir)")
print(f"A-unlock-RED : {ma:.1f} ms (scrypt-TAM-koşar — AEAD-doğrulamasına-kadar)")
print(f"B-başarı     : {mb:.1f} ms")
r1 = ma / mb
print(f"oran A/B = {r1:.2f} (sızıntı-yok eşiği: 0.6-1.6 bantı)")
r2 = mc / mb
print(f"oran C/B = {r2:.2f} (yorumlayıcı-başlangıcı-dominant)")
# iddialar: unlock-RED-başarı-bandında; KDF-parite-kanıtı-kod-tarafından-(xdec-exception-sonrası):
# band 0.6-1.6 (kurucu-onayı 2026-09-12): iddia AYNI-iş ölçümüdür, mutlak-ms değil;
# tam-süit-yükü altında ±%20 sapma normaldir; ölçüm-kanıtı logda kalır (dürüst-not).
assert 0.6 <= r1 <= 1.6, f"unlock-RED-zamanı-bant-dışı: {r1}"
print("OK")
PYEOF
ok $? "zaman-matrisi: unlock-RED≈başarı-(band-içi); ölçüm-kanıt-logda"

rm -rf "$W"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
