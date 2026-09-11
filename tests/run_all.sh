#!/usr/bin/env bash
# Tamga Protocol — one-command regression suite
# Semantics: kontrol <exit> — 0 = PASS, non-zero = FAIL (bash PIPESTATUS convention;
# not 'POSIX': PIPESTATUS is bash-specific (Audit-9 B19). The suite builds its own
# one-shot sandbox every run; it never breaks persistent fixtures.
set -u
cd "$(dirname "$0")/.."
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
# usage: bash tests/run_all.sh [slow]   — env: TAMGA_KS_PASSPHRASE, RUN_SLOW=1, TAMGA_EVIDENCE_DIR
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USG'
tests/run_all.sh — Tamga Protocol acceptance suite (40 controls; 43 with RUN_SLOW=1 — AT-019 wheel + AT-020 self-pilot)

usage: bash tests/run_all.sh            # fast suite (~10 s)
       RUN_SLOW=1 bash tests/run_all.sh # + c30 cross-host control (needs local simnet fixtures)
       bash tests/run_all.sh --help     # this text

env:
  TAMGA_KS_PASSPHRASE   keystore passphrase (public simnet constant: simnet-2026)
  TAMGA_EVIDENCE_DIR    evidence output dir (default .evidence)

prerequisites: bash tests/setup.sh (pinned wasmtime), pip install -r requirements.txt
USG
  exit 0
fi
LOG="${TAMGA_EVIDENCE_DIR:-.evidence}/REGRESYON/$(date +%F)/run_all-$(date +%H%M%S).log"
mkdir -p "$(dirname "$LOG")"
SB="tests/simnet/.sandbox"
PASS=0; FAIL=0
say() { echo "  [$1] $2"; }
kontrol() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); say PASS "$2"; else FAIL=$((FAIL+1)); say FAIL "$2"; fi; }
bekle_red() { kontrol "$@"; }  # semantic alias for expected-RED greps (grep -q based); single implementation (Tur-2 cleanup)

{
  echo "# run_all — $(date -Iseconds)"

  echo "--- AT-001a: manifest validation vectors (expecting 1 ACCEPT + 5 RED)"
  python3 tamga_validator.py validate tests/vectors/tc-a1 | grep -q '^ACCEPT'; kontrol $? "tc-a1 ACCEPT"
  for tc in tc-a2 tc-a3 tc-a4 tc-a5 tc-a6; do
    if python3 tamga_validator.py validate "tests/vectors/$tc" | grep -q '^RED'; then kontrol 0 "$tc RED"; else kontrol 1 "$tc RED"; fi
  done

  echo "--- AT-001f: import negative vectors (reason 7/9/8) — details: .evidence/AT-001/$(date +%F)/AT-001f-vektorler.log"
  bash tests/negative_snapshots.sh > /dev/null 2>&1; kontrol $? "tc-s7/s9/s8 negative vectors (3 expected RED)"

  echo "--- AT-003: node-cosign negative vectors (F25 closure) — details: .evidence/AT-003/$(date +%F)/AT-003-cosign.log"
  bash tests/negative_cosign.sh > /dev/null 2>&1; kontrol $? "tc-n1..n6 node-cosign vectors (L1/L0 policy)"

  echo "--- building sandbox (one-shot node)"
  rm -rf "$SB"; mkdir -p "$SB/pkg"
  cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkg/"
  SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')

  python3 tamga_runner.py grant "$SB/pkg" 0.01 "takim-hibe" | grep -q '"seq": 1'; kontrol $? "grant seq-1 zincire girdi"
  python3 tamga_runner.py run "$SB/pkg" --seed "$SEED" --note "takim-notu" | grep -q '"ok": true'; kontrol $? "run ok"

  echo "--- slice-11: input binding (D11) — input_sha256 in receipt + deterministic replay"
  printf '{"islem":"d11","v":1}' > "$SB/pkg/in.json"
  python3 tamga_runner.py run "$SB/pkg" --seed "$SEED" --input "$SB/pkg/in.json" --require-proof --note d11a > /dev/null
  python3 tamga_runner.py run "$SB/pkg" --seed "$SEED" --input "$SB/pkg/in.json" --require-proof --note d11b > /dev/null
  python3 - "$SB/pkg/ledger.jsonl" <<'PY'
import sys, json, hashlib
ch = [json.loads(l) for l in open(sys.argv[1]) if l.strip() and json.loads(l).get("op") == "charge"]
bek = hashlib.sha256(open(sys.argv[1].rsplit("/", 1)[0] + "/in.json", "rb").read()).hexdigest()
girdili = [r for r in ch if r.get("input_sha256")]
assert len(girdili) >= 2, "girdili makbuz yok"
assert all(r["input_sha256"] == bek for r in girdili), "input_sha256 mismatch"
assert girdili[-1]["stdout_sha256"] == girdili[-2]["stdout_sha256"], "replay broke"
PY
  kontrol $? "D11: input hash in receipt + same-input→same-output"
  python3 tamga_runner.py ledger-verify "$SB/pkg" | grep -q '"ok": true'; kontrol $? "chain tip verifies"

  echo "--- F21: truncate → import RED (reason 14)"
  python3 tamga_runner.py export "$SB/pkg" -o "$SB/snap.tsg" --seed "$SEED" > /dev/null
  python3 - "$SB/pkg/ledger.jsonl" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); lines = p.read_text().splitlines(); lines.pop()
p.write_text(chr(10).join(lines) + chr(10))
PY
  python3 tamga_runner.py import "$SB/snap.tsg" "$SB/pkg" | grep -q '"reason_code": 14'
  bekle_red $? "import after truncation → reason-14 RED"

  echo "--- merkle: tamper state → import into fresh pkg RED (reason 17)"
  python3 - "$SB" <<'PY'
import json, sys, pathlib
sb = pathlib.Path(sys.argv[1])
st = json.loads((sb / "pkg/state.json").read_text())
for n in st["memory"]["nodes"]:
    if n["kind"] == "note":
        n["text"] = "KURCALANDI"; break
(sb / "pkg/state.json").write_text(json.dumps(st, ensure_ascii=False))
PY
  python3 tamga_runner.py export "$SB/pkg" -o "$SB/snap2.tsg" --seed "$SEED" > /dev/null
  mkdir -p "$SB/pkg2"; cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkg2/"
  python3 tamga_runner.py import "$SB/snap2.tsg" "$SB/pkg2" | grep -q '"reason_code": 17'
  bekle_red $? "merkle kurcalama reason-17 RED"

  echo "--- migration: moving to a fresh node + embedded chain (F24 closure)"
  python3 tamga_runner.py run "$SB/pkg" --seed "$SEED" > /dev/null   # zinciri onar (charge ekle)
  python3 tamga_runner.py export "$SB/pkg" -o "$SB/snap3.tsg" --seed "$SEED" > /dev/null
  mkdir -p "$SB/pkg3"; cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkg3/"
  python3 tamga_runner.py import "$SB/snap3.tsg" "$SB/pkg3" | grep -q '"ok": true'; kontrol $? "migration ACCEPT"
  python3 tamga_runner.py ledger-verify "$SB/pkg3" | grep -q '"ok": true'; kontrol $? "embedded chain verified on target (F24)"

  echo "--- AT-001d essence: snapshot body is encrypted (plaintext scan)"
  if grep -q "takim-notu" "$SB/snap3.tsg"; then kontrol 1 "plaintext leak in snapshot body"; else kontrol 0 "0 plaintext leaks in snapshot body"; fi

  if [ "${RUN_SLOW:-0}" = "1" ]; then
    # Audit-9 B16: the slow round depends on gitignored fixtures (c30 + seedC) — it cannot
    # run in a fresh clone; the precondition gate prints a clear message.
    if [ ! -f tests/simnet/node-C/pkg-c30/tamga.json ] || [ ! -f tests/simnet/seedC.hex ]; then
      echo "  [SKIP] RUN_SLOW skipped: tests/simnet/node-C + seedC.hex fixtures are absent in this clone (gitignored)"
    else
    echo "--- AT-001c essence: 31s wall measurement (slow)"
    W=$(python3 tamga_runner.py run tests/simnet/node-C/pkg-c30 --seed "$(cat tests/simnet/seedC.hex)" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("wall_ms",0))')
    if [ "$W" -ge 30000 ] 2>/dev/null; then kontrol 0 "c30 wall_ms=$W ≥ 30000"; else kontrol 1 "c30 wall_ms=$W < 30000"; fi
    fi

  # ---- kontrol-41 (slow): AT-019 published-wheel nacl-blocked real verification ----
  bash tests/at019_wheel_noengine.sh > /dev/null 2>&1
  kontrol $? "AT-019: published-wheel nacl-blocked verification (no-deps install; restricted-host story)"

  # ---- kontrol-42 (slow): AT-020 SELF-PILOT ucd-bacakli-uctan-uca-teslimat (dis-taraf-YOK) ----
  bash tests/at020_self_pilot.sh > /dev/null 2>&1
  kontrol $? "AT-020: self-pilot uc-bacak-delivered/ran/satisfied + 2 tamper-negatif (dis-taraf-gerekmez)"
  fi

  # ---- kontrol-18: AT-005 memory import (multi-format, idempotent, oversize RED) ----
  bash tests/at005_memory_import.sh > /dev/null 2>&1
  kontrol $? "AT-005: memory-import (4-format + idempotency + oversize RED)"

  # ---- kontrol-19: AT-006 net proxy (RFC-005A slices 1-2; box stays socket-free) ----
  bash tests/at006_net_proxy.sh > /dev/null 2>&1
  kontrol $? "AT-006: net-proxy (decl-RED + allow-list tunnel + deny/pinhole + byte cap + D12 binding)"

  # ---- kontrol-20: AT-007 pairing fixture (x402 <-> Tamga, #3379) ----
  bash tests/at007_pairing_fixture.sh > /dev/null 2>&1
  kontrol $? "AT-007: pairing-fixture (labeling + membership + sha256/keccak256 + tamper REDs)"

  # ---- kontrol-21: AT-008 agent-side net shim (RFC-006 D13; runner-as-proxy-client) ----
  bash tests/at008_net_shim.sh > /dev/null 2>&1
  kontrol $? "AT-008: net-shim (framed stdin + request-line evidence + mock-HTTPS + soft denial + cap RED)"

  # ---- kontrol-22: AT-009 RFC-007 R1 net.json -> runtime.net (founder-approved) ----
  bash tests/at009_manifest_net.sh > /dev/null 2>&1
  kontrol $? "AT-009: manifest-net (migrate-net one-way + D12a jcs-canonical binding + ambiguous RED + dual-read + schema RED)"

  # ---- kontrol-23: AT-010 RFC-007 R2 labeled delivery digest (D10, founder-approved) ----
  bash tests/at010_delivery_hash.sh > /dev/null 2>&1
  kontrol $? "AT-010: delivery-hash (labeled sha256|keccak256 digest in the charge + ledger depth-gate + pairing chain)"

  # ---- kontrol-24: AT-011 RFC-007 R3 D12 conditional unity + formal binding ----
  bash tests/at011_d12_unity.sh > /dev/null 2>&1
  kontrol $? "AT-011: d12-unity (trio together-or-neither + net_mb formality + manifest binding + deletion detection)"

  # ---- kontrol-25: AT-012 dx402 pairing verification (RFC-007 track, #3379) ----
  bash tests/at012_dx402_pairing.sh > /dev/null 2>&1
  kontrol $? "AT-012: dx402-pairing (paymentId + CID roundtrip + ecrecover + pair-charge bridge + tamper RED)"

  # ---- kontrol-26: Audit-11 ledger bombası (D1: satır-bombası + grant-note kapısı) ----
  bash tests/audit11_ledger_bomb.sh > /dev/null 2>&1
  kontrol $? "Audit-11: ledger-bomb (50MB-line fail-closed + grant-note cap + legit-flow intact)"

  # ---- kontrol-27: Audit-12 / AT-013 pip-kurulum sağlığı (motor-free doğrulama-yolçapı) ----
  bash tests/at013_pip_sanity.sh > /dev/null 2>&1
  kontrol $? "AT-013: pip-sanity (install+keygen+ledger-verify engine-free in isolated venv)"

  # ---- kontrol-28: Audit-13 / AT-014 mini-verifier (runner-paritesi + tamper-RED) ----
  bash tests/at014_mini_verifier.sh > /dev/null 2>&1
  kontrol $? "AT-014: mini-verifier (runner≡mini parity + tamper RED + line-bomb guard + desert-mode)"

  # ---- kontrol-29: Audit-14 / AT-015 evidence-bundle (tek-komut-kanıt-paketi) ----
  bash tests/at015_bundle.sh > /dev/null 2>&1
  kontrol $? "AT-015: evidence-bundle (JSON+MD copy-equal + mini-verify reproducibility + tamper RED)"

  # ---- kontrol-30: Audit-15 state-sertleştirme (fail-closed-RED + F21-kaniti) ----
  bash tests/audit15_state_hardening.sh > /dev/null 2>&1
  kontrol $? "Audit-15: state-hardening (corrupt-state fail-closed + tamper-inert-chain + nesting ok)"

  # ---- kontrol-31: Audit-16 node-revocation (OQ-3-çalışır + mimari-notu-belgelenir) ----
  bash tests/audit16_revocation_gap.sh > /dev/null 2>&1
  kontrol $? "Audit-16: node-revocation (L1-import revoked-RED; verify-lists documented as architecture)"

  # ---- kontrol-32: Audit-17 export-snapshot-fuzz (6-kurcalama-sınıfı-RED + gövde-gizliliği) ----
  bash tests/audit17_snapshot_fuzz.sh > /dev/null 2>&1
  kontrol $? "Audit-17: snapshot-fuzz (truncate/flip/swap/magic→RED; ciphertext-bölgesi-desen-temiz)"

  # ---- kontrol-33: Audit-18 ünikod-hash-ayrıştırma (JCS-subset-sınırı-belgeli) ----
  bash tests/audit18_unicode_fuzz.sh > /dev/null 2>&1
  kontrol $? "Audit-18: unicode-fuzz (NFC/NFD+homoglif+null→farklı-hash; JCS-subset sınırı belgeli)"

  # ---- kontrol-34: verify-lite (nacl-ENGELLİ ortamda stdlib-saf-yolçaplar) ----
  python3 tools/verify_lite.py > /dev/null 2>&1
  kontrol $? "verify-lite: mini-verifier+pairing-hash+explain nacl-blocked ortamda PASS"

  # ---- kontrol-35: AT-015 sürüm-pinli-export-vektörleri (P4) ----
  bash tests/at015_pinned_exports.sh > /dev/null 2>&1
  kontrol $? "AT-015: pinned-exports (mem0/letta/zep sürüm-pinli şekiller → sniff+import+determinizm)"

  # ---- kontrol-36: Audit-19 zaman-tüneli ölçümü (unlock-RED≈başarı; KDF-parite) ----
  bash tests/audit19_timing.sh > /dev/null 2>&1
  kontrol $? "Audit-19: timing (unlock-RED≈başarı band-içi; scrypt her yolçapta tam koşar)"

  # ---- kontrol-37: AT-016 explain CLI (TR/EN + tamper-RED + receipt-kanonik) ----
  bash tests/at016_explain.sh > /dev/null 2>&1
  kontrol $? "AT-016: explain CLI (TR/EN rendering + tamper→EŞLEŞMİYOR + receipt canonical)"

  # ---- kontrol-38: corpus-fuzz binder (unicode-ayrışma + deterministik-üreticiler) ----
  bash tests/run_corpus_fuzz.sh > /dev/null 2>&1
  kontrol $? "corpus-fuzz: unicode-corpus-ayrışık + audit-üreticileri-deterministik + surrogate-üretici"

  # ---- kontrol-39: AT-017 anchor-design-vector (F1; const-YOK, şekil-matematiği-donuk) ----
  bash tests/at017_anchor_design.sh > /dev/null 2>&1
  kontrol $? "AT-017: anchor-design-vector (F1 şekli D5-uyumlu; §4.4-parite-beyanlı; const-YOK)"


  # ---- kontrol-40: AT-018 M6 manifest-schema draft (v0.3.0 additive; RFC-008 external-receipt) ----
  bash tests/at018_m6_manifest_schema.sh > /dev/null 2>&1
  kontrol $? "AT-018: M6 manifest-schema v0.3.0-draft (additive-contract; 1-VALID+4-RED sentetik; izolasyon)"

  rm -rf "$SB"
  echo ""
  echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
  [ "$FAIL" = "0" ]
} 2>&1 | tee -a "$LOG"
exit ${PIPESTATUS[0]}
