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

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]
