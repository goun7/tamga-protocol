#!/usr/bin/env bash
# Corpus-besleyici - kirli-input-arsivini-tekrarlanabilir-ureticilere-baglar (Boyut-2)
# Tek-komut: unicode-corpus-unu-hash-ayristirma-taramasindan gecirir + audit-ailelerini
# deterministik-ureticiler uzerinden ucer. Yeni-kod-eski-kirli-input-la-geri-doner-mi?
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/CORPUS/$(date +%F)}/corpus-fuzz.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

# 1) unicode-corpus - hash-ayristirma (ayni-dize-hicbir-islemde-es-hash-uretmemeli):
python3 - > "$LOG.uni" 2>&1 <<'PYEOF'
import hashlib, sys, pathlib
sys.path.insert(0, ".")
lines = pathlib.Path("tests/corpus/unicode/strings.txt").read_text(encoding="utf-8").splitlines()
hashes = [hashlib.sha256(l.encode("utf-8")).hexdigest() for l in lines if l]
assert len(hashes) == len(set(hashes)), "corpus-ici-hash-cakismasi"
print(f"{len(hashes)}-corpus-dizesi-tumu-ayrik-hash")
PYEOF
ok $? "unicode-corpus: tum-dizeler-ayrik-hash"

# 2) audit-ureticileri-deterministik ucer (ayni-sonuc-iki-kosumda):
bash tests/audit17_snapshot_fuzz.sh > /dev/null 2>&1; a1=$?
bash tests/audit17_snapshot_fuzz.sh > /dev/null 2>&1; a2=$?
if [ $a1 -eq 0 ] && [ $a2 -eq 0 ]; then ok 0 "audit-17-ureticisi: iki-kosum-da-PASS (deterministik)"; else ok 1 "audit-17-uretici-tutarsiz: $a1/$a2"; fi

# 3) lone-surrogate-ureticisi-import-edilebilir (bellek-ici-sinir-kaniti):
python3 -c "
import sys; sys.path.insert(0, 'tests/corpus/unicode')
import lone_surrogate_gen
assert len(lone_surrogate_gen.S) == 1 and 0xD800 <= ord(lone_surrogate_gen.S) <= 0xDFFF
print('lone-surrogate-bellek-ici-uretilebilir')
" > "$LOG.surrogate" 2>&1
ok $? "lone-surrogate: bellek-ici-uretici-calisir"

# 4) snapshot-corpus-ureticisi (tests/corpus/snapshot/tamper_gen.py): deterministik +
#    turetilen-6-sinifin-hepsi-dosya-uretir + manifest-expected-alanlari-tam:
bash - > "$LOG.snapgen" 2>&1 <<'OUTER'
set -e
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export TAMGA_KS_PASSPHRASE=corpus-binder-2026
cp tests/vectors/tc-net-demo/tamga.json tests/vectors/tc-net-demo/agent.wasm "$T/"
python3 - "$T" <<'PY'
import json, sys, pathlib
sys.path.insert(0, ".")
import tamga_validator as tv
W = pathlib.Path(sys.argv[1])
m = json.load(open(W / "tamga.json"))
sk = tv.SigningKey.generate()
m["signature"] = {"algo": "ed25519", "key": sk.verify_key.encode().hex(), "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(m)).signature.hex()
(W / "tamga.json").write_text(json.dumps(m, indent=2))
(W / "seed.hex").write_text(sk.encode().hex())
PY
SEED=$(cat "$T/seed.hex")
python3 tamga_runner.py run "$T" --seed "$SEED" > /dev/null
python3 tamga_runner.py export "$T" -o "$T/snap.tsg" --seed "$SEED" > /dev/null
D1=$(mktemp -d); D2=$(mktemp -d)
python3 tests/corpus/snapshot/tamper_gen.py "$T/snap.tsg" "$D1" > /dev/null
python3 tests/corpus/snapshot/tamper_gen.py "$T/snap.tsg" "$D2" > /dev/null
diff -r "$D1" "$D2" > /dev/null
python3 - "$D1" <<'PY'
import json, sys, pathlib
mf = json.loads((pathlib.Path(sys.argv[1]) / "manifest.json").read_text())
assert set(mf["classes"]) == {"truncate","body-flip","header-flip","tail-flip","swap","magic-swap"}
assert all(c["expected"] for c in mf["classes"].values())
print("snapshot-corpus-ok")
PY
OUTER
ok $? "snapshot-corpus: uretici-deterministik + 6-sinif + manifest-tam"

# 5) schema-corpus-ureticisi (tests/corpus/schema/state_tamper_gen.py): deterministik +
#    5-desen + manifest-expected-alanlari-tam:
bash - > "$LOG.schemagen" 2>&1 <<'OUTER'
set -e
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export TAMGA_KS_PASSPHRASE=corpus-binder-2026
cp tests/vectors/tc-net-demo/tamga.json tests/vectors/tc-net-demo/agent.wasm "$T/"
python3 - "$T" <<'PY'
import json, sys, pathlib
sys.path.insert(0, ".")
import tamga_validator as tv
W = pathlib.Path(sys.argv[1])
m = json.load(open(W / "tamga.json"))
sk = tv.SigningKey.generate()
m["signature"] = {"algo": "ed25519", "key": sk.verify_key.encode().hex(), "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(m)).signature.hex()
(W / "tamga.json").write_text(json.dumps(m, indent=2))
(W / "seed.hex").write_text(sk.encode().hex())
PY
SEED=$(cat "$T/seed.hex")
python3 tamga_runner.py run "$T" --seed "$SEED" > /dev/null
D1=$(mktemp -d); D2=$(mktemp -d)
python3 tests/corpus/schema/state_tamper_gen.py "$T/state.json" "$D1" > /dev/null
python3 tests/corpus/schema/state_tamper_gen.py "$T/state.json" "$D2" > /dev/null
diff -r "$D1" "$D2" > /dev/null
python3 - "$D1" <<'PY'
import json, sys, pathlib
mf = json.loads((pathlib.Path(sys.argv[1]) / "manifest.json").read_text())
assert set(mf["patterns"]) == {"truncated","invalid-json","tip-swap","sessions-inflate","nested-deep"}
assert all(p["expected"] for p in mf["patterns"].values())
print("schema-corpus-ok")
PY
OUTER
ok $? "schema-corpus: uretici-deterministik + 5-desen + manifest-tam"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]
