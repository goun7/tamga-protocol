#!/usr/bin/env bash
# AT-229: BRANDSTRIKE-TSA — RFC 3161 time-axisın Tamga hash-zincirine KOD-bağı.
#
# README'nin "The time axis — BrandStrike" paragrafı DOC-bağıydı (RFC 3161 TSA
# ↔ JCS hash-chain); tools/brandstrike_tsa.py onu KOD'a çevirir. Bu-kontrol
# aracın GERÇEK-çalıştığını-kanıtlar: TSA-tokenı ile ledger'ın-zincirbaşı aynı
# özet-üzerinde-birleştirilir — zaman-ekseni bütünlük-eksenine-BAĞLANIR.
#
# NEYİ-KANITLAR:
#   K1 SELFTEST: 21/21 in-process iddia (zincir-paritesi + DER + GREEN + RED'ler)
#   K2 ZİNCİR-PARİTESİ: chain_tip, tamga_runner._ledger_head ile BİREBİR (gerçek
#      ledger'da; bağımsız-modül-aynı-matematik)
#   K3 GREEN-YOL: gerçek-imzalı-token gerçek-ledger'ın-zincirbaşı-üzerinde → ok
#   K4 DECOY-RED: aynı-anahtarlı-geçerli-imza ama YANLIŞ-özett → RED (imprint)
#   K5 REPLAY-RED: nonce-uyumsuz → RED (tekrar-oynama-koruması)
#   K6 İMZA-RED: farklı-anahtar-imzası → RED (imza-kapısı-gerçek)
#   K7 RED-STATUS: TSA-reddi → RED + failInfo-yüzeye-çıkıyor
#   K8 MALFORMED-RED: bozuk/truncated DER → RED (crash-YOK, fail-closed)
#   K9 KIRIK-ZİNCİR: bozuk-ledger + geçerli-token → RED (hash-ekseni ayrı-kapı)
#   K10 BAĞIMSIZLIK: araç yalnızca stdlib+PyNaCl+tamga_canon (sıfır-yeni-bağımlılık)
#
# Para-YOK / ağ-YOK (yerel-test-TSA-anahtarı; TAMGA_LIVE-GEREKMEZ). Deterministik.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/BRANDSTRIKE/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at229.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

TOOL="tools/brandstrike_tsa.py"
WORK=$(mktemp -d)
TSA_KEY="9090909090909090909090909090909090909090909090909090909090909090"
FIX="9090909090909090909090909090909090909090909090909090909090909090"

# --- test ledger: gerçek runner-üretimi (grant + run) ---------------------------------------
rm -rf "$WORK/pkg"; mkdir -p "$WORK/pkg"
cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$WORK/pkg/"
SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
python3 tamga_runner.py grant "$WORK/pkg" 0.01 "at229" >/dev/null 2>&1
python3 tamga_runner.py run "$WORK/pkg" --seed "$SEED" --note "at229-run" >/dev/null 2>&1
LEDGER="$WORK/pkg/ledger.jsonl"
RUNNER_TIP=$(python3 tamga_runner.py ledger-verify "$WORK/pkg" 2>/dev/null \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("head",""))' 2>/dev/null)

# --- K1: SELFTEST (21/21) ------------------------------------------------------------------
OUT=$(python3 "$TOOL" selftest 2>&1); RC=$?
S1=$(echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("passed",0))' 2>/dev/null)
O1=$(echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("ok",False))' 2>/dev/null)
[ "$RC" = "0" ] && [ "$O1" = "True" ] && [ "$S1" = "21" ] && RES1=0 || RES1=1
k $RES1 "K1 selftest 21/21 (in-process: zincir-paritesi+DER+GREEN+RED, rc=$RC)" "rc=$RC ok=$O1 passed=$S1"

# --- K2: ZİNCİR-PARİTESİ — chain_tip ≡ runner._ledger_head (gerçek-ledger) -----------------
P2=$(python3 - "$LEDGER" "$RUNNER_TIP" <<'PY' 2>&1
import sys, pathlib
sys.path.insert(0, "."); sys.path.insert(0, "tools")
import brandstrike_tsa as bst, tamga_runner as tr
mine, why = bst.chain_tip(bst.load_ledger(sys.argv[1]))
theirs, why2 = tr._ledger_head(pathlib.Path(sys.argv[1]))
print("PARITY" if mine == theirs == sys.argv[2] and why == why2 == "ok" else f"MINE={mine[:12]} RUNNER={theirs[:12]} HEAD={sys.argv[2][:12]}")
PY
)
[ "$P2" = "PARITY" ] && RES2=0 || RES2=1
k $RES2 "K2 zincir-paritesi: chain_tip ≡ tamga_runner._ledger_head (gerçek-ledger)" "$P2"

# --- K3: GREEN-YOL — gerçek-imzalı-token, gerçek-ledger'ın-zincirbaşı ----------------------
python3 "$TOOL" demo --tsa-key "$TSA_KEY" --ledger "$LEDGER" --out-response "$WORK/good.resp" > "$WORK/k3.json" 2>&1; RC3=$?
G3=$(python3 -c 'import json; d=json.load(open("'"$WORK/k3.json"'")); print("OK" if d.get("ok") else d.get("reason"))' 2>/dev/null)
[ "$RC3" = "0" ] && [ "$G3" = "OK" ] && RES3=0 || RES3=1
k $RES3 "K3 GREEN: gerçek-imzalı-token gerçek-ledger-zincirbaşı-üzerinde → ok" "rc=$RC3 $G3"

# verify-yolu: token dosyası + ledger → ok (rc0)
R3B=$(python3 "$TOOL" verify "$WORK/good.resp" "$LEDGER" 2>&1); RC3B=$?
V3B=$(echo "$R3B" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("ok" if d.get("ok") else d.get("reason"))' 2>/dev/null)
[ "$RC3B" = "0" ] && [ "$V3B" = "ok" ] && RES3B=0 || RES3B=1
k $RES3B "K3b verify-yolu: token-dosyası + ledger → ok (rc0, JSON-verdikt)" "rc=$RC3B $V3B"

# --- K4: DECOY-RED — geçerli-imza, YANLIŞ-özett → RED ---------------------------------------
python3 "$TOOL" demo --tsa-key "$TSA_KEY" --ledger "$LEDGER" --bad-imprint > "$WORK/k4.json" 2>&1; RC4=$?
V4=$(python3 -c 'import json; d=json.load(open("'"$WORK/k4.json"'")); print(d.get("reason","?"))' 2>/dev/null)
[ "$RC4" = "0" ] && [ "$V4" = "imprint_mismatch: token does not cover this digest" ] && RES4=0 || RES4=1
k $RES4 "K4 decoy-RED: geçerli-imza ama yanlış-özett → imprint_mismatch" "rc=$RC4 $V4"

# --- K5: REPLAY-RED — nonce-uyumsuz → RED ---------------------------------------------------
R5=$(python3 - "$WORK/good.resp" "$LEDGER" <<'PY' 2>&1
import sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")
import brandstrike_tsa as bst
resp = bytes.fromhex(open(sys.argv[1]).read().strip())
v, r, _ = bst.bind_chain(resp, bst.load_ledger(sys.argv[2]), nonce=0xDEAD)
print(r)
PY
)
V5=$(echo "$R5" | tail -n1)
[ "$V5" = "nonce_mismatch: expected 57005, got 1234605616436508552" ] && RES5=0 || RES5=1
k $RES5 "K5 replay-RED: nonce-uyumsuz → nonce_mismatch (tekrar-oynama-koruması)" "$V5"

# --- K6: İMZA-RED — farklı-anahtarın-imzası → RED -------------------------------------------
R6=$(python3 - "$WORK/good.resp" "$LEDGER" "$TSA_KEY" <<'PY' 2>&1
import sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")
import brandstrike_tsa as bst
from nacl.signing import SigningKey
resp = bytes.fromhex(open(sys.argv[1]).read().strip())
v, r, _ = bst.bind_chain(resp, bst.load_ledger(sys.argv[2]),
                         tsa_key=SigningKey(bytes.fromhex("1"*64)).verify_key.encode().hex())
print(r)
PY
)
V6=$(echo "$R6" | tail -n1)
case "$V6" in signature_invalid:*) RES6=0;; *) RES6=1;; esac
k $RES6 "K6 imza-RED: farklı-anahtar-imzası → signature_invalid (imza-kapısı-gerçek)" "$V6"

# --- K7: RED-STATUS — TSA-reddi → RED + failInfo --------------------------------------------
R7=$(python3 - "$LEDGER" <<'PY' 2>&1
import sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")
import brandstrike_tsa as bst
from nacl.signing import SigningKey
recs = bst.load_ledger(sys.argv[1])
digest, _, _ = bst.tip_imprint(recs)
imp = bst._message_imprint(digest)
sk = SigningKey(bytes.fromhex("9"*64))
tst = bst._tst_info(imp, 11, bst.DEMO_GEN_TIME, 1)
resp = bst.build_timestamp_resp(imp, serial=11, gen_time=bst.DEMO_GEN_TIME, nonce=1,
                                signature=sk.sign(tst).signature, status=2,
                                status_string="unsupported policy",
                                fail_info=["unacceptedPolicy"])
v, r, d = bst.bind_chain(resp, recs)
print(f"{r} | failInfo={d.get('fail_info')}")
PY
)
V7=$(echo "$R7" | tail -n1)
[ "$V7" = "tsa_status_rejection | failInfo=['unacceptedPolicy']" ] && RES7=0 || RES7=1
k $RES7 "K7 red-status: TSA-reddi → RED + failInfo-yüzeye-çıkıyor" "$V7"

# --- K8: MALFORMED-RED — bozuk/truncated/garbage DER → RED (crash-YOK) ----------------------
RES8=0
for junk in "" "00" "303133" "zz" "3081"; do
  printf '%s' "$junk" > "$WORK/junk.der"
  python3 "$TOOL" verify "$WORK/junk.der" "$LEDGER" > "$WORK/k8.json" 2>&1; RC8=$?
  V8=$(python3 -c 'import json; d=json.load(open("'"$WORK/k8.json"'")); print(d.get("reason","?")[:18])' 2>/dev/null)
  [ "$RC8" = "1" ] && [ "$V8" = "response_malformed" ] || { RES8=1; note "    junk='$junk' rc=$RC8 reason=$V8"; }
done
k $RES8 "K8 malformed-RED: 5-bozuk-DER → response_malformed rc1 (crash-YOK)" "yukarıda"

# --- K9: KIRIK-ZİNCİR — geçerli-token + bozuk-ledger → RED ----------------------------------
R9=$(python3 - "$WORK/good.resp" "$LEDGER" <<'PY' 2>&1
import sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")
import brandstrike_tsa as bst
recs = bst.load_ledger(sys.argv[2])
recs[-1]["prev"] = "f"*64                      # chain'i-kır (h-artık-uyumsuz)
resp = bytes.fromhex(open(sys.argv[1]).read().strip())
v, r, _ = bst.bind_chain(resp, recs)
print(r)
PY
)
V9=$(echo "$R9" | tail -n1)
case "$V9" in chain_not_verifiable:*) RES9=0;; *) RES9=1;; esac
k $RES9 "K9 kırık-zincir-RED: geçerli-token + bozuk-ledger → chain_not_verifiable" "$V9"

# --- K10: BAĞIMSIZLIK — yalnızca stdlib + PyNaCl + tamga_canon -----------------------------
# Sıfır-yeni-bağımlılık: import-satırları stdlib/tamga_canon/nacl-dışı-birşey içermemeli
BAD=$(grep -E "^import |^from " "$TOOL" | grep -vE "^from tamga_canon|^import (datetime|hashlib|json|re|sys)$|^from pathlib import Path$" || true)
[ -z "$BAD" ] && RES10=0 || RES10=1
k $RES10 "K10 bağımsızlık: sıfır-yeni-bağımlılık (stdlib + PyNaCl + tamga_canon)" "${BAD:-temiz}"

rm -rf "$WORK"
echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-229: BrandStrike RFC-3161 TSA ↔ Tamga hash-chain code-bond (zaman-ekseni-bağlandı)"
[ "$FAIL" -eq 0 ] || exit 1
