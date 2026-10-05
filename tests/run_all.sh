#!/usr/bin/env bash
# Tamga Protocol — one-command regression suite
# Semantics: kontrol <exit> — 0 = PASS, non-zero = FAIL (bash PIPESTATUS convention;
# not 'POSIX': PIPESTATUS is bash-specific (Audit-9 B19). The suite builds its own
# one-shot sandbox every run; it never breaks persistent fixtures.
set -u
cd "$(dirname "$0")/.."
# [Fix-2026-10-02 → 2026-10-03 portability] Bagimliliklar (eth_account,
# eth_utils, ...) bu makinede user-site ($HOME/.local)'da; HOME_degisince
# user-site kaybolur ve testler ImportError ile fail ederdi (29 test).
# Cozum: ÇALIŞAN yorumlayicinin KENDİ user-site'ini PYTHONPATH'e ekle
# (site.getusersitepackages). Önceki-yol MUTLAT /home/gokun/.../python3.14/
# site-packages kullanıyordu — bu (a) CI'da yoktur (inert), (b) 3.14-site'i
# 3.10-3.13 gibi BAŞKA bir yorumlayıcıda PYTHONPATH'e koyarsa rpds'in
# C-extension'ı ABI-uyumsuzluğuyla jsonschema'i kırar (AT-018). Sürümler
# artık eşleşir; user-site yoksa hiçbir şey eklenmez — opsiyonel bağımlılık
# gerektiren kontroller kontrol_req ile dürüst-SKIP verir (aşağıda).
_usp="$(python3 -c 'import site; print(site.getusersitepackages() or "")' 2>/dev/null || true)"
if [ -n "$_usp" ] && [ "$_usp" != "None" ] && [ -d "$_usp" ]; then
  export PYTHONPATH="$_usp${PYTHONPATH:+:$PYTHONPATH}"
fi
TAMGA_RUN_ALL_ABS="$(realpath "$0")"; export TAMGA_RUN_ALL_ABS
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
# AT-162-düzeltmesi: syntropion-sabit-default-key-kaldırıldı → test-ortamı
# için-zorunlu-env ( üretim-değil; ci-deterministik-test-key)
export SYNTROPION_SECRET_KEY="${SYNTROPION_SECRET_KEY:-simnet-syntropion-test-key-32b}"
# concurrency guard (D1 closed 2026-09-15, hardened same-day): the suite shares sandbox
# dirs — parallel instances produce false FAILs (observed). One mutex, fail-loud.
# Command-form flock (not exec-fd form): util-linux marks its fd close-on-exec, so test
# servers spawned by controls can never hold the lock past the suite's own lifetime —
# an inherited-fd deadlock was caught by the FIRST live refusal the guard printed.
LOCKF="${TMPDIR:-/tmp}/tamga-run-all.lock"
if [ -z "${TAMGA_SUITE_LOCKED:-}" ] && command -v flock >/dev/null 2>&1; then
  if ! flock -n -o "$LOCKF" -c true; then
    echo "run_all.sh: another suite run holds the lock ($LOCKF) — eşzamanlı koşum yakalandı: diğer run bitsin ya da sırayla koş"; exit 1
  fi
  export TAMGA_SUITE_LOCKED=1
  exec flock -o "$LOCKF" bash "$TAMGA_RUN_ALL_ABS" "$@"
fi
# ct_log.jsonl: append-only evidence-log — AT-168/AT-179 her koşumda yazar; tracked
# olduğu için suite çalışma-ağacını kirletir ve push öncesi manuel checkout gerektirir.
# Suite başında HEAD'e-döndür (temiz-başlangıç) + çıkışta-da-temizle (trap EXIT —
# her çıkış-yolunda). Testlerin asıl kanıtları .evidence/'da (untracked) — kayıp-yok.
_ct_log_reset() { git checkout -- ct_log.jsonl 2>/dev/null || true; }
_ct_log_reset
trap _ct_log_reset EXIT
# usage: bash tests/run_all.sh [slow]   — env: TAMGA_KS_PASSPHRASE, RUN_SLOW=1, TAMGA_EVIDENCE_DIR
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'USG'
tests/run_all.sh — Tamga Protocol acceptance suite (83 controls; 88 with RUN_SLOW=1 — slow-gated: c30 cross-host wall + AT-019 wheel + AT-020 self-pilot + AT-026 wheel-tam-modül + AT-032 agent-rebuild)

usage: bash tests/run_all.sh            # fast suite (~20 s)
       RUN_SLOW=1 bash tests/run_all.sh # + c30 cross-host control (needs local simnet fixtures)
       bash tests/run_all.sh --help     # this text

env:
  TAMGA_KS_PASSPHRASE   keystore passphrase (public simnet constant: simnet-2026)
  TAMGA_EVIDENCE_DIR    evidence output dir (default .evidence)

prerequisites: bash tests/setup.sh (pinned wasmtime), pip install -r requirements.txt
concurrency: the suite shares sandbox dirs — two parallel run_all.sh instances
 produce false FAILs (observed 2026-09-15); run one at a time (flock guard: D1 open-debt).
USG
  exit 0
fi
LOG="${TAMGA_EVIDENCE_DIR:-.evidence}/REGRESYON/$(date +%F)/run_all-$(date +%H%M%S).log"
mkdir -p "$(dirname "$LOG")"
SB="tests/simnet/.sandbox"
PASS=0; FAIL=0; SKIP=0
say() { echo "  [$1] $2"; }
kontrol() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); say PASS "$2"; else FAIL=$((FAIL+1)); say FAIL "$2"; fi; }
# dış-servis-kesintisi-ilkeleri (2026-09-25): test "SKIP: <neden>" satırı basıp
# exit-0-dönerse-PASS-değil-SKIP-sayılır — dış-bağımlılık-bu-deponun-regresyonu
# değildir-ve-yanlış-KIRMIZI-üretmez (AT-082/093/098: 00-gateway x402-upstream).
# Test-kendisi-SKIP-korumasını-uygular (services_up-okuma); run_all.sh-sadece-sayar.
kontrol_skip() {
  local out rc desc neden
  out="$1"; rc="$2"; desc="$3"
  neden="$(printf '%s\n' "$out" | grep -m1 '^SKIP:' || true)"
  if [ -n "$neden" ]; then
    SKIP=$((SKIP+1)); say SKIP "$desc — $neden"
  else
    kontrol "$rc" "$desc"
  fi
}

# kontrol_live: canlı-gas-testleri rc=3 → GEÇERLİ-SKIP (bakiye/anahtar-yok).
# DÜZELTME (2026-09-26): önceden-SKIP'yı-exit-0-sanıp-PASS-sayıyordu →
# '0 SKIP' raporu-YANLIŞ-çıkıyordu (AT-207-bakiye-SKIP'i-PASS-gibi-gösterdi).
kontrol_live() {
  local rc="$1" desc="$2"
  if [ "$rc" = "0" ]; then PASS=$((PASS+1)); say PASS "$desc"
  elif [ "$rc" = "3" ]; then SKIP=$((SKIP+1)); say SKIP "$desc — bakiye/anahtar-yok (geçerli-canlı-SKIP)"
  else FAIL=$((FAIL+1)); say FAIL "$desc"
  fi
}
bekle_red() { kontrol "$@"; }  # semantic alias for expected-RED greps (grep -q based); single implementation (Tur-2 cleanup)

# [Fix-2026-10-03] CI-faithful absence-guards (CI-run #338 kök-nedeni).
# Birçok kontrol RFC-010 "dikiş" doğrulamasıdır: TAMGA-MESH'in kardeş
# projelerini (sester, pacta, syntropion_core, veridrome, swarmax, ...)
# $TAMGA_MESH_ROOT altından import eder ve/veya zero-dependency-ilkesi
# dışında opsiyonel PyPI yüzeyleri kullanır (eth_account, fastapi; pyproject
# 'relayer'/'evm-test' ekstraları opsiyonel-bırakılmıştır). GitHub CI bu
# repoyu TEK BAŞINA checkout eder ve yalnız requirements.txt (PyNaCl +
# jsonschema) kurar → bu yüzeyler CI'da YOKTUR ve kontrol İNDETERMİNE'dir:
# ne yeşil-boyanır (maskeleme) ne de kırmızı (yanlış-regresyon). AT-067/
# AT-070/AT-082'nin yerleşik-desenini suite-geneline yayar; önkoşul VARSA
# (tam-mesh makinesi) kontrol-normal-koşulur — test asla-devre-dışı-değil.
TAMGA_MESH_ROOT="${TAMGA_MESH_ROOT:-/home/gokun/projects/00_TAMGA-MESH}"
_mesh_ok() { [ -d "$TAMGA_MESH_ROOT/sester" ] && [ -d "$TAMGA_MESH_ROOT/pacta" ] && [ -d "$TAMGA_MESH_ROOT/tamga" ]; }
_mod_ok() { python3 -c "import $1" >/dev/null 2>&1; }
kontrol_req() {  # kontrol_req <rc> <desc> <önkoşul>... — önkoşul: 'mesh' | modül-adı
  local rc="$1" desc="$2"; shift 2
  local p why=""
  for p in "$@"; do
    if [ "$p" = "mesh" ]; then
      _mesh_ok || why="TAMGA-MESH kardeş-repoları bu checkout'ta yok (CI)"
    elif ! _mod_ok "$p"; then
      why="opsiyonel bağımlılık '$p' kurulu değil (requirements.txt dışı)"
    fi
    if [ -n "$why" ]; then SKIP=$((SKIP+1)); say SKIP "$desc — $why — İNDETERMİNE, yeşil-boyanmaz"; return; fi
  done
  kontrol "$rc" "$desc"
}

{
  echo "# run_all — $(date -Iseconds)"

  # ÜRETİM-CORPUS-ÖNCE (AT-057, bağımlılık-sırası): emitter_verify.py'nin
  # üretim-denetimi (AT-049/AT-057) deneysel-üretim-ledger'ını-ister; bu-yüzden
  # kontrol-73'ten-ÖNCE-üretilmeli (CI'da-AT-049-kırmızıydı, yerelde-77/77-
  # geçiyordu-çünkü-önceki-koşudan-kalmıştı). Üretim-kanıtı-koşuya-bağlı,
  # commit'e-değil (.evidence/-gitignore).
  export PROD="$(pwd)/.evidence/PROD-CORPUS/$(date +%F)"
  mkdir -p "$PROD"
  python3 tests/helpers/prod_corpus_make.py > /dev/null 2>&1 || \
    echo "  [UYARI] üretim-corpus-üretilemedi — AT-049/AT-057-boş-corpusta-koşar"

  echo "--- AT-001a: manifest validation vectors (expecting 2 ACCEPT + 5 RED; v0.2.0-flip 2026-09-11)"
  python3 tamga_validator.py validate tests/vectors/tc-a1 | grep -q '^ACCEPT'; kontrol $? "tc-a1 ACCEPT"
  python3 tamga_validator.py validate tests/vectors/tc-a6 | grep -q '^ACCEPT'; kontrol $? "tc-a6 ACCEPT (v0.2.0 üst-sınır flip-SONRASI açık)"
  for tc in tc-a2 tc-a3 tc-a4 tc-a5 tc-a7; do
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
  # AT-163-düzeltmesi: run-artık-tahriz-edilmiş-state'i-reddeder ( graph_merkle-
  # mismatch); migration-için-TEMİZ-paket-gerekir — eskiden-run-tahrizi-yutuyordu
  # ( sessiz-yeşil-geçiş), şimdi-fail-closed. Yukarıdaki-KURCALANDI-pkg'ı-kullanma.
  rm -rf "$SB/pkg-mig"; mkdir -p "$SB/pkg-mig"
  cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkg-mig/"
  python3 tamga_runner.py run "$SB/pkg-mig" --seed "$SEED" > /dev/null   # temiz-zincir
  python3 tamga_runner.py export "$SB/pkg-mig" -o "$SB/snap3.tsg" --seed "$SEED" > /dev/null
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

  # ---- kontrol-43: AT-021 quickstart wizard (ilk-paket-tek-komut; B1) ----
  # NOT (taze-göz-denetimi D4): 44/45-ID'leri tarihsel-atlanmıştır; yorum-etiketleri
  # KARARARIDIR — dış-başvurular (TESTS/AGENT-GUIDE/RFC'ler) bu-ID'lerle eşleşir,
  # fiilî-koşum-sırası-DEĞİL. Yeniden-numaralandırma dış-başvuruları kırardı.
  bash tests/at021_quickstart.sh > /dev/null 2>&1
  kontrol $? "AT-021: quickstart (tam-akis + sozlesme + 3-negatif: isim/dolu-hedef/tekrar)"

  # ---- kontrol-46: AT-022 kompozisyon-vektörü (RFC-009 batch-leaf matematigi; op/const YOK) ----
  bash tests/at022_composition_vector.sh > /dev/null 2>&1
  kontrol $? "AT-022: kompozisyon-vektörü (epoch-10 kök çapraz-teyit + zincirbaşı izdüşümü + determinizm)"

  # ---- kontrol-47: AT-023 project-head CLI (zincirbaşı → batch-yaprak; kullanıcı-yüzeyi) ----
  bash tests/at023_project_head.sh > /dev/null 2>&1
  kontrol $? "AT-023: project-head CLI (D5-parite + yaprak-şeması + -o + bozuk-zincir RED)"

  # ---- kontrol-48: AT-024 PUGIO köprüsü alıcısı (external_anchor doğrulama; RFC-009 receiver-tarafı) ----
  bash tests/at024_pugio_receiver.sh > /dev/null 2>&1
  kontrol $? "AT-024: PUGIO-köprüsü (selftest + kopuk-bağ + zarf-tip + fail-loud + sürüm-kapısı)"

  # ---- kontrol-49: AT-025 PUGIO K0-bundle ingest (81-MERGEN tarafı; RFC-009 receiver-2.-adım) ----
  bash tests/at025_pugio_ingest.sh > /dev/null 2>&1
  kontrol $? "AT-025: PUGIO-bundle-ingest (tam-yol makbuz + payload/merkle/count kazıma RED + sürüm-kapısı)"

  # ---- kontrol-51: AT-027 epoch-mührü doğrulama CLI (dış-kanıt yüzeyi; offline-deterministik) ----
  bash tests/at027_epoch_verify.sh > /dev/null 2>&1
  kontrol $? "AT-027: epoch-verify (dahil-etme GREEN + kök/kanıt/fact kazıma RED + ölü-RPC İNDETERMİNE)"

  # ---- kontrol-54: AT-030 DIŞ delivery-attestation doğrulayıcısı (stdlib-only cross-verify) ----
  bash tests/at030_attest_verify.sh > /dev/null 2>&1
  kontrol $? "AT-030: capacity-attest 7/7 bağımsız-koşum + üretim-claim GREEN + rc2/rc1-kapıları"

  # ---- kontrol-53: AT-028 liveness-probe karar-matrisi (offline mock-RPC; #2887 hattının aracı) ----
  bash tests/at028_liveness_probe.sh > /dev/null 2>&1
  kontrol $? "AT-028: liveness-probe 5-hâl karar-matrisi (GREEN/İNDETERMİNE×3/RED; timestamp-güvensizliği sözleşmesi)"

  # ---- kontrol-52: AT-029 CR-v0.1-canonicalisation cross-proof (dış-vektör, kendi-muskül) ----
  bash tests/at029_cr_crossproof.sh > /dev/null 2>&1
  kontrol $? "AT-029: CR-cross-proof (PR-592 hakemiyle 8/8 + vendor-hash-pin + digest-kazıma RED)"

  # ---- kontrol-55: AT-033 twin-hygiene (TR-doğmuş belgeye TR-ikiz YASAK; dil-notu elle-sayaç YASAK) ----
  bash tests/at033_twin_hygiene.sh > /dev/null 2>&1
  kontrol $? "AT-033: twin-hygiene (K1 özdeş-kopya-ikiz + K2 TR-orijinal-kardeş-yasak + K3 disk-türer dil-notu)"

  # ---- kontrol-56: AT-034 zero-digest-counter (red-öncesi-hash-yok; çift-yönlü sayaç) ----
  bash tests/at034_zero_digest_counter.sh > /dev/null 2>&1
  kontrol $? "AT-034: zero-digest-counter (zarf-eksik/bozuk-JSON/unknown-registry = 0-hash; yeşil+tamper = tam-1-hash)"

  # ---- kontrol-58: AT-036 canonicalization-parity (python-RFC8785 === node-ECMAScript; node-yoksa İNDETERMİNE) ----
  bash tests/at036_canonical_parity.sh > /dev/null 2>&1
  kontrol $? "AT-036: canonical-parity (ECMAScript-number 1.0→1 + UTF-16-sıra; 3-uygulama + node-oracle)"

  # ---- kontrol-59: AT-037 ret-listesi↔kod round-trip (GVP-PR-#3'ün-bizde-yansıması) ----
  bash tests/at037_list_code_roundtrip.sh > /dev/null 2>&1
  kontrol $? "AT-037: list⇄code-roundtrip (ret-listesi-ile-kod-birebir; 0.2.12-I-JSON-RED'leri-sabitlenmiş)"

  # ---- kontrol-57 (slow): AT-032 builder-determinism (aynı-pinli-toolchain çift-derleme bayt-bayt) ----
  if [ "${RUN_SLOW:-0}" = "1" ]; then
    bash tests/at032_agent_rebuild.sh > /dev/null 2>&1
    kontrol $? "AT-032: agent-rebuild (çift-derleme-bayt-bayt + rustc-patch-drift sınıf-bildirimi; cargo-yoksa-bağırarak-SKIP)"
  fi

  # ---- kontrol-50 (slow): AT-026 wheel paket-tamlık (repo↔py-modules↔wheel üç-yönlü + tam-kurulum import) ----
  if [ "${RUN_SLOW:-0}" = "1" ]; then
    bash tests/at026_wheel_tam_modul.sh > /dev/null 2>&1
    kontrol $? "AT-026: wheel-tam-modül (0.2.3-ingest-dersi; üç-yönlü-eşitlik + kurulum-import)"
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


  # ---- kontrol-59: AT-038 BAĞIMSIZ attest-verify (sıfır-tamga-import; 7-golden-çift-üretim) ----
  bash tests/at038_attest_verify_bagimsiz.sh > /dev/null 2>&1
  kontrol $? "AT-038: BAĞIMSIZ attest-verify (foreign-claim keccak+JCS+ecrecover saf-Python; 7/7-çift-üretim)"

  # ---- kontrol-60: AT-002a registration-v1 şema-doğrulayıcı (Faz-3-ön-iş, P9'suz) ----
  bash tests/at002a_registration_schema.sh > /dev/null 2>&1
  kontrol $? "AT-002a: ERC-8004 registration-v1 üret+doğrula + 6-negatif-yol-RED + JCS-paritesi"

  # ---- kontrol-61: AT-002c kimlik-çapası (node-kimliği ↔ makbuz-signer bağı; P9'suz) ----
  bash tests/at002c_identity_anchor.sh > /dev/null 2>&1
  kontrol $? "AT-002c: identity-anchor eip155-şema + signer-uyumu + 3-negatif-yol-RED"

  # ---- kontrol-62: AT-002d charge-kayıt bağımsız-doğrulama (stdlib-only; P9'suz) ----
  bash tests/at002d_receipt_compat.sh > /dev/null 2>&1
  kontrol $? "AT-002d: charge-üyelik + zincir-doğrulama + digest-parite + 3-negatif-yol-RED"

  # ---- kontrol-63: AT-002e kâr-solucanğı (λ-eşik-geçerliliği; P9'suz-ön-iş) ----
  bash tests/at002e_profit_worm.sh > /dev/null 2>&1
  kontrol $? "AT-002e: λ-eşik-bant-bağlı (300/1000/1500) + eski-tek-2000-keşfi"

  # ---- kontrol-64: AT-039 yüzey-sabitleme (doğrulama-arayüzleri-testle-kilitli) ----
  bash tests/at039_surface_lock.sh > /dev/null 2>&1
  kontrol $? "AT-039: CLI/import-yüzeyleri + argüman-sözleşmesi + sester-bağı"

  # ---- kontrol-65: AT-040 spec↔üretim verifier paritesi (Veridict-örneği) ----
  bash tests/at040_spec_parity.sh > /dev/null 2>&1
  kontrol $? "AT-040: JCS-16/16 + temiz-ikili-GREEN + 6-mutasyon-RED-uyum + bağımsızlık"

  # ---- kontrol-66: AT-041 sovereign-anchor (üç-ürün tek-öz + iki-katmanlı) ----
  bash tests/at041_sovereign_anchor.sh > /dev/null 2>&1
  kontrol $? "AT-041: üç-ürün-tek-öz + kök-kurcalama-RED + sahte-yeşile-boyama-RED"

  # ---- kontrol-67: AT-042 settlement-köprü (Veridict-eşi; iki-katmanlı) ----
  bash tests/at042_settlement_bridge.sh > /dev/null 2>&1
  kontrol $? "AT-042: build+verify iki-katmanlı + Veridict-saldırı-kilidi + limits"

  # ---- kontrol-68: AT-043 conformance pack (sıfır-import, repo-dışı-çalışır) ----
  bash tests/at043_conformance_pack.sh > /dev/null 2>&1
  kontrol $? "AT-043: 7-vektör + izolasyon + sıfır-tamga-import + üretim-parite"

  # ---- kontrol-69: AT-045 spec↔kod çift-yönlü-parite (Veridict-D12-eşi) ----
  bash tests/at045_spec_code_parity.sh > /dev/null 2>&1
  kontrol $? "AT-045: erratum-E1 + seq/op/ekstra-alan iki-yön-locked"

  # ---- kontrol-70: AT-046 tri-product spec↔code-divergence-tarayıcı ----
  python3 tools/spec_code_scan.py > /dev/null 2>&1
  kontrol $? "AT-046: 9-kural-çift-yönlü + sıfır-divergence + parite"

  # ---- kontrol-71: AT-047 spec-needle-machine (YÖN-B-makinede + op-otomatik) ----
  python3 tools/spec_needle_machine.py > /dev/null 2>&1
  kontrol $? "AT-047: 18-needle-makine + op-kümesi-E1(c)-otomatik"

  # ---- kontrol-72: AT-048 dedektör-öz-doğrulama (stillmarcus24-yoldaş-kuralı) ----
  bash tests/at048_detector_selftest.sh > /dev/null 2>&1
  kontrol $? "AT-048: 4-sınıf-bilinen-cevap + 18/0/0/0 + absent≠failure"

  # ---- kontrol-73: AT-049 emitter-doğrulama (yanlış-emitter-sınıfı-kilidi) ----
  bash tests/at049_emitter_verify.sh > /dev/null 2>&1
  kontrol $? "AT-049: op-emitter'ları-koddan-kanıtlandı + gürültü-filtresi"

  # ---- kontrol-86: AT-062 grant-şema-okuma-kapısı (AT-060-deseni-yayılır) ----
  bash tests/at062_grant_read_gate.sh > /dev/null 2>&1
  kontrol $? "AT-062: grant amount/note okuma-tarafında-RED (reason-16)"

  # ---- kontrol-85: AT-061 tasarım↔pilot-şekil-paritesi (donmuş-şekil-yazıcıyla-aynı) ----
  bash tests/at061_design_pilot_shape_parity.sh > /dev/null 2>&1
  kontrol $? "AT-061: donmuş-F1-şekli ↔ gerçek-anchor-kaydı (çıkarımla)"

  # ---- kontrol-84: AT-060 RFC-009 anchor-okuma-kapısı (yazma-yolu-yetmez) ----
  # ---- kontrol-85: AT-064 çoklu-ödeme-kanal-dispatch'ı (B-yönü) ----
  # ---- kontrol-86: AT-065 PQHaven-erc8004-dikişi (gerçek-üçüncü-proje) ----
  # ---- kontrol-87: AT-066 Ajan-Borsası receipt_hash-dikişi ----
  # ---- kontrol-88/89: AT-067 Swarmax + AT-068 Dümen-dikişleri ----
  bash tests/at067_swarmax_evidence_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-067: 69-Swarmax-evidence → RFC-010 tamga/native"
  # ---- kontrol-90..93: AT-069 §6 + AT-070/071/072 B-sınıfı-sonu ----
  bash tests/at069_foreign_chain_gate.sh > /dev/null 2>&1
  kontrol $? "AT-069: §6 yabancı-zincir-sorgulama-borcu-kapandı"
  bash tests/at070_fleksa_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-070: 76-Fleksa W3C-VC+Merkle → RFC-010"
  bash tests/at071_tenderix_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-071: 64-Tenderix ed25519-üç-fallback → RFC-010"
  # ---- kontrol-94/95: AT-073 RFC-011 dispute + AT-074 ROBOSEAL-çatışma ----
  bash tests/at073_dispute_pointer.sh > /dev/null 2>&1
  kontrol $? "AT-073: RFC-011 dispute-pointer (anlaşmazlık-bacağı)"
  # ---- kontrol-96: AT-075 Unpump-gerçek-dikiş + ecrecover-boşluk ----
  bash tests/at075_unpump_gercek_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-075: Unpump-gerçek-6/6 + ecrecover-stub-gizli-boşluk"

  # ---- kontrol-97..100: AT-076..079 C-sınıfı-kalan-dördü-dikişleri ----
  bash tests/at076_pqhaven_teori_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-076: 80-PQHaven-teorisi CBOM+Merkle → RFC-010"
  bash tests/at077_yieldix_ed25519_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-077: 99-Yieldix gerçek-Ed25519 → RFC-010 (tamga/native-boşluk)"
  bash tests/at078_syntropion_escrow_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-078: 18-Syntropion FSEK-escrow → RFC-010 (gerçek-ecrecover)"
  bash tests/at079_pactiva_audit_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-079: 22-37-Pactiva audit-ledger → RFC-010/011 (evidence_link)"

  # ---- kontrol-101: AT-080 Ajan-Borsası-gerçek-x402/v1-dikiş (teammate) ----
  bash tests/at080_ajan_borsasi_gercek_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-080: 24-Ajan-Borsası receipt_hash → RFC-010 (gerçek-x402/v1)"

  # ---- kontrol-102: AT-084 Pacta-anlaşmazlık-yüzü (teammate, RFC-011-canlı) ----
  bash tests/at084_pacta_anlasmazlik_yuzu.sh > /dev/null 2>&1
  kontrol $? "AT-084: 03-Pacta Tier3-Schelling → RFC-011 canlı-hakemlik"

  # ---- kontrol-103: AT-083 ROBOSEAL-K0 çözüm-uzayı (teammate, araştırma) ----
  bash tests/at083_roboseal_k0_cozum_uzayi.sh > /dev/null 2>&1
  kontrol $? "AT-083: ROBOSEAL-K0 ağırlıksız-Sybil-savunması-mümkün-mü"

  # ---- kontrol-104: AT-081 Unpump-X-Bind-Signature gerçek-müşteri-imzası ----
  bash tests/at081_unpump_x_bind_signature.sh > /dev/null 2>&1
  kontrol $? "AT-081: Unpump bağ-anahtarı → gerçek-müşteri-imzası (D5-kapsama)"

  # ---- kontrol-105b: AT-082 00-gateway-pilot-Sepolia-anchor (teammate) ----
  # dış-servis-kesintisi-SKIP-korumalı (x402-upstream-down → SKIP, FAIL-değil)
  _out="$(bash tests/at082_gateway_pilot_sepolia_anchor.sh 2>&1)"; _rc=$?
  kontrol_skip "$_out" "$_rc" "AT-082: 00-gateway 6-x402-pilot → Sepolia anchor (R9-1..5)"

  # ---- kontrol-108: AT-092 K0-Sybil-additive (teammate, AT-083'ün-uygulaması) ----
  bash tests/at092_k0_sybil_additive.sh > /dev/null 2>&1
  kontrol $? "AT-092: K0-uyumlu-Sybil-üyelik (ağırlıksız-GREEN, ağırlıklı-RED)"

  # ---- kontrol-109..112: AT-091/093/094 + AT-085 (teammate-döngü-2) ----
  bash tests/at091_veridict_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-091: Veridict-imzalı-sertifika → RFC-010 (tamga/native)"
  # dış-servis-kesintisi-SKIP-korumalı (x402-upstream-down → SKIP, FAIL-değil)
  _out="$(bash tests/at093_gateway_ic_yuz.sh 2>&1)"; _rc=$?
  kontrol_skip "$_out" "$_rc" "AT-093: 00-gateway iç-yüz guvence-kanca + bekçi + 7-route"
  bash tests/at094_pactiva_peer_attestation_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-094: 22-37-Pactiva peer-attestation → RFC-010/011"
  bash tests/at095_k0_kalan_adaylar.sh > /dev/null 2>&1
  kontrol $? "AT-095: K0-kalan-3-aday (DepositLock/Zaman/N-imza — DÜZ/İKİLİ)"
  bash tests/at096_syntropion_api_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-096: 18-Syntropion API/cli FSEK-yüzü → RFC-010"
  bash tests/at097_yieldix_server_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-097: 99-Yieldix server gerçek-HTTP-endpoint → RFC-010"
  # dış-servis-kesintisi-SKIP-korumalı (x402-upstream-down → SKIP, FAIL-değil)
  _out="$(bash tests/at098_gateway_analitik_gunluk.sh 2>&1)"; _rc=$?
  kontrol_skip "$_out" "$_rc" "AT-098: gateway üçüncü-yüz analitik + K5-günlük"
  bash tests/at099_swarmax_sealing_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-099: 23-Swarmax sealing (Merkle+Ed25519) → RFC-010"
  bash tests/at100_fiyat_kirilimi_koruma.sh > /dev/null 2>&1
  kontrol $? "AT-100: fiyat-kırılımı-koruma (underpayment/replay/quote-expiry)"
  bash tests/at101_d014_duvar_negatif_yuz.sh > /dev/null 2>&1
  kontrol $? "AT-101: D-014-duvarı-negatif-yüz (ağ-şeridi + soğuk-başlangıç)"
  bash tests/at102_swarmax_loop_breaker_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-102: 23-Swarmax loop-breaker + mad-robust-z → RFC-010"
  bash tests/at103_dumen_signing_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-103: 13-Dümen reports/signing (üçlü-doğrulama) → RFC-010"
  bash tests/at104_dumen_watch_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-104: 13-Dümen watch süreklilik (fail-loud + kurtarma) → RFC-010"
  bash tests/at105_sester_policy_signed_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-105: Sester policy-signed (JWS-ES256 + gevşeme-gate) → RFC-010"
  bash tests/at107_fleksa_policy_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-107: 21-Fleksa policy-verifier (Ed25519 + fail-closed) → RFC-010"
  bash tests/at106_tenderix_escrow_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-106: 26-Tenderix escrow+dispute (S6-fail-closed) → RFC-010/011"
  bash tests/at085_sester_batch_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-085: Sester settlement-batch → RFC-010 (evidence_link-derived)"

  # ---- kontrol-105..107: AT-087/088/089 C-sınıfı-ikinci-yüzler (teammate) ----
  bash tests/at087_pactiva_arbitration_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-087: 22-37-Pactiva arbitration → RFC-011 (pactiva/v1-additive)"
  bash tests/at088_yieldix_telemetry_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-088: 99-Yieldix telemetry/reporter → RFC-010 (imzalı-SLA)"
  bash tests/at089_syntropion_vesting_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-089: 18-Syntropion revenue_router/vesting → RFC-010 (FSEK-%20)"

  bash tests/at074_roboseal_catisma.sh > /dev/null 2>&1
  kontrol $? "AT-074: ROBOSEAL-itibar-çatışması (K0 + D-014)"

  bash tests/at072_veridrome_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-072: 73-Veridrome RFC-6962-CT-log → RFC-010"

  bash tests/at068_dumen_evidence_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-068: 77-Dümen-evidence-chain → RFC-010 (AT-036-bağı)"

  bash tests/at066_ajan_borsasi_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-066: 24-ajan-borsasi receipt_hash → RFC-010-5.kontrol"

  bash tests/at065_pqhaven_erc8004_bind.sh > /dev/null 2>&1
  kontrol $? "AT-065: 25-pqhaven-x402 Merkle-kökü-ile-erc8004/v1-dikişi"

  bash tests/at064_payment_channel_dispatch.sh > /dev/null 2>&1
  kontrol $? "AT-064: scheme-dispatch + çapraz-scheme-saldırısı-RED"

  bash tests/at060_anchor_read_gate.sh > /dev/null 2>&1
  kontrol $? "AT-060: anchor R9-1..R9-5 okuma-tarafında-RED (reason-16)"

  # ---- kontrol-87: AT-063 RFC-010 cross-artifact-settlement-binding ----
  # (AT-063'e-yeniden-numaralandırıldı: önceki-oturum-AT-060-numarasını-benim
  #  anchor-okuma-kapısı-testimle-çakıştırmıştı — benim-AT-060'ım-3-commitle-
  #  referans-alındığı-için-RFC-010-testi-AT-063'e-taşındı)
  bash tests/at063_settlement_bind.sh > /dev/null 2>&1
  kontrol $? "AT-063: safal207-dikişi beş-kontrol + negatif-üyeler"

  # ---- kontrol-83: AT-059 RFC-009 external-chain-anchor (pilot-açık) ----
  bash tests/at059_rfc009_anchor.sh > /dev/null 2>&1
  kontrol $? "AT-059: RFC-009-anchor R9-1..R9-5 + negatif-kontroller"

  # ---- kontrol-82: AT-058 ayraç-sınıfı-örtüşme (Kural-7.2-makine-hali) ----
  bash tests/at058_ayrac_sinifi.sh > /dev/null 2>&1
  kontrol $? "AT-058: ayraç-sınıfı-örtüşme + çapraz-körlük"

  # ---- kontrol-81: AT-057 üretim-corpus-boşluğu (Veridict-canary-aynası) ----
  bash tests/at057_production_corpus.sh > /dev/null 2>&1
  kontrol $? "AT-057: üretim-corpus + üçüncü-seçenek-yasak"

  # ---- kontrol-80: AT-056 GATES-kayıt-defteri (Kural-7.1-makine-hali) ----
  bash tests/at056_gates_registry.sh > /dev/null 2>&1
  kontrol $? "AT-056: GATES-üç-yönlü + self-catching"

  # ---- kontrol-79: AT-055 alıcı-tarafı-bilinmeyen-op (Sester-5.tur) ----
  bash tests/at055_unknown_ops_receiver.sh > /dev/null 2>&1
  kontrol $? "AT-055: alıcı-tarafı-görür (üretici-kapsam-sınırı)"

  # ---- kontrol-78: AT-054 absent-vs-failure (stillmarcus24-#2887) ----
  bash tests/at054_absent_vs_failure.sh > /dev/null 2>&1
  kontrol $? "AT-054: absent-state ≠ instrument-failure"

  # ---- kontrol-77: AT-053 restore-geçidi (üçüncü-yazım-deyimi) ----
  bash tests/at053_restore_gate.sh > /dev/null 2>&1
  kontrol $? "AT-053: gömülü-zincir-kurulumunda-op-geçidi"

  # ---- kontrol-76: AT-052 yazım-bölgesi-geçitli (Sester'ın-mimari-cevabı) ----
  bash tests/at052_write_region_gate.sh > /dev/null 2>&1
  kontrol $? "AT-052: ikinci-yazım-deyimi-kapatıldı (bölge-geçitli)"

  # ---- kontrol-75: AT-051 blockchain-üçlü-paritesi (epoch-10-canlı-zincir) ----
  bash tests/at051_blockchain_triple_parity.sh > /dev/null 2>&1
  kontrol $? "AT-051: 3-bağımsız-keccak + on-chain-root-paritesi"

  # ---- kontrol-74: AT-050 üçlü-kapsam (Sester'ın-iddia-düzeltmesi) ----
  bash tests/at050_triple_coverage.sh > /dev/null 2>&1
  kontrol $? "AT-050: runtime-fail-closed + statik + corpus (üçlü)"
  bash tests/at108_veridrome_w3cvc_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-108: 73-Veridrome W3C-VC (Ed25519+CT-log) → RFC-010"
  bash tests/at109_pacta_vault_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-109: Pacta-escrow-vault (EIP-1559-keccak) → RFC-010"
  bash tests/at110_pqhaven_teori_canli_uyumluluk.sh > /dev/null 2>&1
  kontrol $? "AT-110: PQHaven teori↔canlı uyumluluk (AT-076-düzeltme) → RFC-010"
  bash tests/at111_aborsa_mainnet_guard_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-111: Ajan-Borsası mainnet-guard (gerçek-keccak) → RFC-010"
  bash tests/at113_veridict_settlement_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-113: Veridict-settlement (3-yol-reconciliation-gate) → RFC-010"
  bash tests/at112_syntropion_license_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-112: 18-Syntropion license-key (HMAC-SHA256, attribution→authorization)"
  bash tests/at114_yieldix_breaker_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-114: 19-Yieldix circuit-breaker (Teorem-3-izolasyon) → RFC-010"
  bash tests/at115_unpump_finalize_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-115: 02-Unpump finalize_bind (D5-kapsama-üretim-fix) → RFC-010"
  bash tests/at116_pactiva_contract_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-116a: 03-Pactiva üçlü-sözleşme (4857-İSK) → RFC-010"
  bash tests/at116_pactiva_webhook_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-116b: 03-Pactiva webhook-HMAC (sabit-zamanlı) → RFC-010"
  bash tests/at117_roboseal_rfc9421_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-117: ROBOSEAL RFC-9421/RFC-8032 imza-çekirdeği → RFC-010"
  bash tests/at118_yieldix_hasher_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-118: 19-Yieldix hasher (Decimal+TR-UTF8-koruması) → RFC-010"
  bash tests/at119_dumen_filters_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-119: 13-Dümen filters politika-yüzü (enjeksiyon+PII) → RFC-010"
  bash tests/at121_swarmax_analitik_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-121: 23-Swarmax analitik-stabilite ( cusum+psi+jsd+FpBudget)"
  bash tests/at122_roboseal_did_belge_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-122: ROBOSEAL DID-belge + revocation-fail-closed → RFC-010"
  bash tests/at123_veridict_anchor_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-123: Veridict-anchor (Rekor-RFC-6962+ECDSA-P256) → RFC-010"
  bash tests/at126_veridrome_tee_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-126: 73-Veridrome TEE-tasdik ( donanım-ECDSA-P384) → RFC-010"
  bash tests/at129_yieldix_kalan_yuz_taramasi.sh > /dev/null 2>&1
  kontrol $? "AT-129: Yieldix-kalan-yüz-taraması ( İNDETERMİNE + 3-düzeltme)"
  bash tests/at127_sester_escalation_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-127: Sester-escalation ledger-yüzü ( hash-chain-olayları)"
  bash tests/at128_veridrome_contracts_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-128: Veridrome-contracts ERC-8004 ( keccak-certId)"
  bash tests/at131_syntropion_audit_ledger_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-131: Syntropion-audit-ledger ( Merkle-hash-chain)"
  bash tests/at132_syntropion_shm_ipc_butunluk_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-132: Syntropion-shm-IPC-bütünlüğü ( struct-checksum + flock)"
  bash tests/at133_syntropion_revenue_router_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-133: Syntropion-revenue-router ( AT-131+132-kanal-birleşimi)"
  bash tests/at134_veridrome_vapap_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-134: Veridrome-VAPAP-agent-yetkilendirme ( gerçek-Ed25519)"
  bash tests/at135_sester_escalation_consumed_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-135: Sester-escalation-consumed ( üretim-HTTP-yolu)"
  bash tests/at136_dumen_birlesim_paterni_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-136: Dümen-birleşim-paterni ( 6-kanal-tek-chain-head)"
  bash tests/at137_veridrome_dom_mutator_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-137: Veridrome-dom_mutator ( İNDETERMİNE — HMAC-10hex)"
  bash tests/at138_swarmax_birlesim_persist_alarm_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-138: Swarmax-_persist_alarm-birleşimi ( 3-kanal-evidence_seq)"
  bash tests/at139_roboseal_verifier_replay_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-139: ROBOSEAL-RFC-9421-tam-yol + ReplayCache ( tek-seferlik)"
  bash tests/at141_tamga_chain_head_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-141: tamga/native-chain-head-blok-üretim ( D5-yeniden-oynama)"
  bash tests/at143_tamga_bundle_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-143: tamga/native-bundle-kanıt-çekirdeği ( D5 + JCS-mührü)"
  bash tests/at144_tamga_node_cosign_dos_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-144: tamga/native-node-cosign-DoS-direnç ( 3-saldırı-rc14)" eth_account
  bash tests/at142_tamga_node_key_otorite_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-142: tamga/native-node-key-otorite ( node_id-mühür + node_sig-ayrı)"
  bash tests/at147_sester_tamga_kopru_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-147: Sester-Tamga-zincir-köprüsü ( tek-üretici-iki-yöre)"
  bash tests/at148_swarmax_seal_anchor_kopru_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-148: Swarmax-seal-anchor-kopru-pru ( merkle+Ed25519, secretsiz)"
  bash tests/at149_pacta_tamga_receipt_alici_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-149: Pacta-tamga-receipt-alici-tarafi ( 3-katman + acik-kapandi)"
  bash tests/at150_kripto_gecit_kapisi_denetim_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-150: kripto-gecit-kapisi-denetimi ( tenderix+sester-temiz)"
  bash tests/at145_tamga_sybil_duz_ikili_dikis.sh > /dev/null 2>&1
  _out="$(bash tests/at145_tamga_sybil_duz_ikili_dikis.sh 2>&1)"; _rc=$?
  # AT-145 DÜRÜST-SKIP-verirse ( roboseal-yok) PASS=0-FAIL=0-ile-rc=0-döner;
  # kontrol_skip-SKIP-satırını-_out-içinde-arar ( AT-082-deseni)
  kontrol_skip "$_out" "$_rc" "AT-145: Sybil-tarama ( INDETERMINE: composition_vector-RFC009-Merkle)"
  bash tests/at146_tamga_chain_head_uretim_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-146: tamga-bundle-ic-chain-head-uretim ( 4-yonlu-capraz-dogrulama)"
  bash tests/at151_veridict_rekor_dis_zincir_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-151: veridict-Rekor-dis-zincir-capasi ( gercek-canli-kayit + pin)"
  bash tests/at152_baglanmamis_kanit_yuzleri_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-152: baglanmamis-kanit-yuzleri ( veridrome+fleksa+yieldix-kendi-adlari)"
  bash tests/at153_tamga_consensus_tarama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-153: consensus-tarama ( INDETERMİNE: Phase-3-erteli; F24-tasima-olcumu)"
  bash tests/at154_pactiva_hmac_sinir_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-154: pactiva-HMAC-sinir + proof-of-audit-zinciri ( §6-tamam)"
  bash tests/at155_tamga_epoch_seal_dish_fact_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-155: tamga-dis-fact-baglama ( cmd_anchor-R9; tahriz-broken@4)"
  bash tests/at156_rfc009_sunum_paritesi_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-156: RFC009-sunum-paritesi ( derived-baglanmaz, equals-GERCEK-bag)"
  bash tests/at157_alici_tarafi_tuketim_denetim_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-157: alici-tarafi-tuketim-denetimi ( zkTLS-acigi-KAPANDI)"
  bash tests/at159_swarmax_tamga_native_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-159: swarmax-seal → tamga/native-semasi ( R-noktasi-koruma)"
  bash tests/at158_tamga_state_root_tarama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-158: state-root-tarama ( INDETERMİNE; graph_merkle-olcumu)"
  bash tests/at160_dogrulanmayan_kanit_iddia_tarama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-160: dog-iddia-tarama ( yieldix-SPF/DKIM/DMARC-acigi-KAPANDI)"
  bash tests/at161_veridrome_keccak_erc8004_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-161: veridrome-keccak → erc8004/v1 ( sema-dengesi-3/3)"
  bash tests/at162_kimlik_sizdiran_ozet_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-162: kimlik-sizdiran-ozet-tarama ( syntropion-sabit-default-key-KAPANDI)" mesh
  bash tests/at164_rfc010_s6_tutarlilik_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-164: RFC010-s6 ↔ kod-tutarlilik ( standardizasyon)" mesh
  bash tests/at167_rfc010_s6_derived_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-167: RFC010-s6.2-derived-turetme ( 5-kanit + 4-negatif)" mesh eth_account
  bash tests/at165_zaman_mantigi_replay_tarama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-165: zaman-mantigi-replay ( 2-bulgu-kapandi)"
  bash tests/at166_yetki_yukseltme_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-166: yetki-yukseltme-taramasi ( 2-bulgu-kapandi)" mesh
  bash tests/at168_kanit_butunlugu_tarama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-168: kanit-butunlugu ( 2-bulgu-kapandi)"
  bash tests/at169_hata_ayiklama_sizma_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-169: hata-ayiklama-sizma ( 2-bulgu-kapandi)" mesh
  bash tests/at170_sema_izolasyon_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-170: sema-izolasyonu ( 1-duruust + 5-negatif)" mesh eth_account
  bash tests/at173_rfc010_s6_none_parite_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-173: RFC010-s6.3-none-parite ( 5-kanit)" mesh eth_account
  bash tests/at171_durum_gecis_atlamasi_tarama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-171: durum-gecis-atlamasi ( yan-etki-once-FSM)"
  bash tests/at172_sayisal_tasma_kesinlik_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-172: sayisal-tasma-kesinlik ( 2-bulgu-kapandi)" mesh
  bash tests/at176_tamga_self_chain_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-176: tamga-self-chain ( gercek-D5-head-GREEN)" eth_account
  bash tests/at175_giris_dogrulama_tutarsizligi_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-175: giris-dogrulama-tutarsizligi ( 2-bulgu-kapandi)" mesh
  bash tests/at174_kanal_kapanma_cakisma_tarama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-174: kanal-kapanma-cakisma ( 3-sester-bulgu-kapandi)"
  bash tests/at177_depolama_tutarlilik_tarama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-177: depolama-tutarliligi ( ct-log-zinciri-kapandi)"
  bash tests/at178_yetki_devri_zinciri_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-178: yetki-devri-zinciri ( trust-fail-closed)" mesh
  bash tests/at179_yapilandirma_sabiti_guveni_tarama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-179: yapilandirma-sabiti-guveni ( 0644-ve-dev-secret-kapandi)"
  bash tests/at180_iptal_geri_alma_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-180: iptal-ve-geri-alma ( revocation-fail-closed-exp-zorunlu)" mesh
  bash tests/at181_zamanlama_yaris_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-181: zamanlama-ve-yaris ( kota-TOCTOU+ledger-lock-kapandi)" mesh
  bash tests/at182_giris_siniri_azaltma_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-182: giris-siniri-ve-azaltma ( job_id-carpisma+header-sinir+rate-limit)" mesh
  bash tests/at183_hata_yayilmazlik_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-183: hata-yayilmazlik ( yanlis-imza-sayildi+job_id-sizinti+ct_log-fail-closed)" mesh
  bash tests/at184_dagitik_tutarlilik_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-184: dagitik-tutarlilik ( event_id+idempotency+zorunlu-rol-kapisi)" mesh
  bash tests/at185_kanit_uretim_tesis_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-185: kanit-uretim-tesisi ( validFrom-gelecek-RED+ts-monotonluk)" mesh
  bash tests/at186_guvenlik_borcu_teknik_bakim_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-186: guvenlik-borcu-bakim ( AT-036-notu+env-guard+gen_lang_index)" mesh
  bash tests/at187_dogrulama_yolu_kanca_noktasi_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-187: dogrulama-yolu-kanca ( TSA-PKI-openssl+fail-closed)" mesh
  bash tests/at188_sinir_kosulu_hata_yolu_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-188: sinir-kosulu ( job_id-null/boş-RED+amount<=0-RED)" mesh
  bash tests/at189_yardimci_arac_denetim_iz_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-189: yardimci-arac-denetim-iz ( self_pilot-0600-atomik)" mesh
  bash tests/at190_gizli_varsayilan_deger_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-190: gizli-varsayilan-deger ( secret-zorunlu+boş-RED)" mesh
  bash tests/at191_kanit_uretim_tutarlilik_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-191: kanit-uretim-tutarlilik ( head_source-dangling-RED)" mesh
  bash tests/at192_hata_mesaji_sizintisi_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-192: hata-mesaji-sizintisi ( AuthorizationError+help-flag)" mesh
  bash tests/at193_geri_uyumluluk_kirilma_yuzeyi_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-193: geri-uyumluluk ( Ledger-secret-zorunlu+buyer-rol)" mesh
  bash tests/at194_giris_temizligi_standart_yol_tarama_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-194: giris-temizligi ( TEMIZ: shell=True-yok)" mesh
  bash tests/at195_relayer_katman0_kanit_uretim_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-195: relayer-KATMAN-0 ( fnv1a64-byte-identical + SHA-256(ct)-digest + JCS)"
  bash tests/at197_relayer_ledger_secret_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-197: relayer-KATMAN-1 ( Ledger-secret-zorunlu; dev-secret-RED-25)" mesh
  bash tests/at198_relayer_cpu_kisit_registry_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-198: relayer-KATMAN-1 ( cpu-çift-kısıt + registry-dışı-modül-RED)"
  bash tests/at196_relayer_evm_uctan_uca_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-196: relayer-KATMAN-2 ( uçtan-uca EVM→WASI→chain; status:1 + gasUsed)"
  # AT-199: relayer-DAEMON (poll→execute→fulfill) + unpump-bridge paritesi —
  # mühür-3 canlı (append-dönüşü), input_sha256 bağımsız, delivery_hash keccak,
  # tamga-sim/1 scheme, charge-record paritesi, daemon fail-closed, sester zinciri
  bash tests/at199_relayer_daemon_parite_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-199: relayer-DAEMON ( poll→execute→fulfill + unpump-bridge paritesi)"
  # AT-200: IVerifier — relayer kanıtlarını BAĞIMSIZ doğrular (saf-stdlib,
  # relayer'siz; 6/6 yeşil + 7 tahriz-RED + gerçek ledger.jsonl üyeliği)
  bash tests/at200_iverifier_basimsiz_dogrulama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-200: IVerifier ( bağımsız-doğrulama-arayüzü; 10/10)"
  # AT-201: keccak-parite — tamga_keccak == eth_utils.keccak == GERÇEK-EVM-opcode
  # (py-evm state-machine; keccak-256 legacy-padding; sha3_256 tuzak-kanıtı)
  bash tests/at201_keccak_parite_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-201: keccak-parite ( 3-kaynak; 6/6)"
  # AT-202: daemon replay-protection — aynı request iki-kez fulfill-edilemez
  # (fulfilled-seti; 2 özdeş-log + max_cycles=2 → tek-fulfill)
  bash tests/at202_daemon_replay_koruma_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-202: daemon replay-protection ( 4/4)"
  # AT-203: gas-limit fail-closed — gas=21000 → RC_TX_FAILED, daemon crash-ETMEZ
  bash tests/at203_gas_limit_fail_closed_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-203: gas-limit fail-closed ( 5/5)"
  # AT-204: CANLI ZİNCİR — Base mainnet'te gerçek imza+receipt. Anahtar
  # KULLANICI tarafından ~/.tamga/relayer-live.env (0600) — yoksa GEÇERLİ-SKIP.
  # AT-204/AT-205: CANLI ZİNCİR — Base mainnet'te gerçek tx (para-harcar!).
  # Öntanımlı-ATLA: anahtar bu-makinede-varsa-her-suite-koşumunda ~$0.015
  # gas-harcanır. TAMGA_LIVE=1 ile-açıkça-isteyince-koşulur; aksi-halde
  # SKIP (insan-eylemi — AT-098-disiplini). 220→218 PASS + 3 SKIP olarak-rapor.
  if [ "${TAMGA_LIVE:-0}" = "1" ]; then
    bash tests/at204_canli_zincir_dikis.sh > /dev/null 2>&1
    kontrol_live $? "AT-204: canlı-zincir ( Base mainnet; anahtar-varsa 5/5)"
    bash tests/at205_canli_oracle_fulfill_dikis.sh > /dev/null 2>&1
    kontrol_live $? "AT-205: canlı oracle+fulfillExecution ( Base mainnet; anahtar-varsa 7/7)"
    # AT-207: canlı replay-protection — daemon-restart simülasyonü (ayrı-daemon_loop
    # çağrısı; in-memory set-her-çağrıda-boş). Ya replay-guard-aktif (0-fulfill) ya
    # da GÜVENLİK-AÇIĞI kanıtlanır. Para-harcar (~$0.008) → TAMGA_LIVE-guard'lı.
    bash tests/at207_canli_replay_koruma_dikis.sh > /dev/null 2>&1
    kontrol_live $? "AT-207: canlı replay-protection ( Base mainnet; 4/4 veya açık-kanıtı)"
    # AT-211: CANLI CONTRACT replay-guard — AT-210'un-guard-bytecode'u GERÇEK
    # Base mainnet'e-deploy (guard-oracle) + daemon-çağrı-#1 fulfill, #2 → guard
    # REVERT. Açığın-canlıda-kapatılması (AT-207-bulgusu). Para-harcar (~$0.01).
    bash tests/at211_canli_contract_guard_dikis.sh > /dev/null 2>&1
    kontrol_live $? "AT-211: canlı contract replay-guard ( Base mainnet; 6/6 guard-REVERT)"
  else
    echo "  AT-204/AT-205: SKIP (TAMGA_LIVE=1 değil — canlı-gas-korunuyor)"
    echo "  AT-204/AT-205: SKIP (TAMGA_LIVE=1 değil — canlı-gas-korunuyor)" >&2
  fi
  # AT-206: canlı-tx BAĞIMSIZ-DOĞRULAMA — IVerifier.verify-tx. Okuma-yalnız
  # (gas-YOK; sabit immutable-tx'ler) → TAMGA_LIVE-gerektirmez; ağ-yoksa-SKIP.
  bash tests/at206_canli_tx_dogrulama_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-206: canlı-tx doğrulama ( IVerifier.verify-tx; okuma-yalnız 5/5)"
  # AT-208: batch-verify — N paketi TEK çağrıda denetler (müşteri-değeri:
  # "100 paketi tek seferde"). 5 kontrol: kullanım-hatası + 2-geçerli +
  # bozuk-ledger RED + özet-modu.
  bash tests/at208_batch_verify.sh > /dev/null 2>&1
  kontrol $? "AT-208: batch-verify ( 5/5; N-paket-tek-çağrı)"
  # AT-209: registry backup/restore — mayınlar registry-kaybında-hayatta.
  # Üretim-dayanıklılığı: registry sil → atomik-yedekten-geri-yükle +
  # load_registry ile-DOĞRULA; bozuk-yedek RED (fail-closed). 4/4.
  bash tests/at209_registry_restore.sh > /dev/null 2>&1
  kontrol $? "AT-209: registry-backup/restore ( 4/4; mayınlar-hayatta)"
  # AT-210: CONTRACT-side replay-guard — AT-207'nin-canlı-açığının-2.-katmanı.
  # El-yazımı EVM runtime: SLOAD(requestId) → REVERT-if-dolu; SSTORE. YEREL
  # anvil'de (para-YOK) → 3x-idempotent; daemon-disk-önbelleği-katman-1,
  # contract-guard'ı-katman-2 (kullanıcı-onayı: 'önce-daemon-sonra-contract').
  bash tests/at210_contract_replay_guard_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-210: contract replay-guard ( oracle fulfillExecution tek-seferlik 5/5)"
  # AT-212: WASI default-deny sandbox denetimi — CVE-2026-47261 (filesystem
  # bypass; preopen-gerektirir) + CVE-2026-34987 (memory escape; patched<
  # Tamga-sürümü) bağışıklık-kanıtı. WAT modülleri: path_open → EBADF (fd-3
  # preopen-YOK), sock_open → tanımsız (network-YOK). docs/RESEARCH.md §3.
  bash tests/at212_wasi_default_deny_sandbox_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-212: WASI default-deny sandbox ( CVE-2026-47261/34987 bağışıklık 7/7)"
  # AT-213: LEDGER FUZZ robustness — 50-bozuk-enjeksiyon (hash/prev/amount/ts/
  # payload) hepsi-verify_chain-RED; OracleTrust-vaadinin-robustness-kanıtı
  # (docs/RESEARCH.md §2). Yerel-sqlite (para-YOK).
  bash tests/at213_ledger_fuzz_robustness_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-213: ledger fuzz robustness ( 50/50-RED fail-closed + self-heal)" mesh
  # AT-214: x402 V1/V2 header uyum-analizi — V2 (11-Ara-2025) X-Payment'i-
  # deprecated-etti; Tamga'nın-V1-yolu-sağlıklı, V2-header'ları-güvenli-bekleme
  # (fail-closed; açık-kapı-YOK). docs/RESEARCH.md §1. Yerel-ASGI (para-YOK).
  bash tests/at214_x402_v2_header_uyum_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-214: x402 V1/V2 header uyum-analizi ( 8/8; V1-çalışır V2-red)" mesh
  # AT-216: x402 payment-identifier (idempotency) retry-davranışı — resmi-spec
  # extension'ı (2026-09-27-taraması, docs/RESEARCH.md §5.2). Tamga'nın-KENDİ
  # nonce-replay-koruması-çalışır (K1); standart pay_id-boşluğu-honest-kanıt.
  bash tests/at216_x402_payment_identifier_retry_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-216: x402 payment-identifier retry-davranışı ( 7/7)" mesh
  # AT-217: WASI sonsuz-döngü/DoS koruması — wasmtime-güvenlik-politikası-2026
  # "uninterruptible infinite loops" + "memory exhaustion"ı-AÇIK sayar (§6).
  # Tehlikeli-wasm'ları-üret-ve-kesilmeyi-ölç (para-YOK).
  bash tests/at217_wasi_sonsuz_dongu_dos_korumasi_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-217: WASI sonsuz-döngü/DoS koruması ( 6/6; kesilir + normal-çalışır)"
  # AT-218: ledger batch-verify throughput — x402-V2 batch-settlement'ın-
  # (§5.3b) off-chain-alternatif-kanıtı: 1000-event 0.010s'de-doğrulanır,
  # orta-satır-bozuk → tüm-zincir-RED (kümülatif-kesirlik).
  bash tests/at218_ledger_batch_throughput_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-218: ledger batch-verify throughput ( 5/5; 1000-event<5s)" mesh
  # AT-219: x402 upto-scheme sınır-semantiği — maxAmountRequired-ilanı-doğru;
  # fazla-ödemeyi-RED (ekonomik-koruma AT-100-NEG), eksik-RED, tam-eşit-200,
  # 6-decimal-USDC-minor-eşitliği. docs/RESEARCH.md §5.1.
  bash tests/at219_x402_upto_sinir_semantik_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-219: x402 upto-scheme sınır-semantiği ( 6/6; fazla/eksik-RED)" mesh
  # AT-220: keşif-katmanı paritesi — /agents.json sağlıklı (4-zorunlu-alan +
  # parse-fiyat + ledger-bütünlüğü); /discovery/resources-YOK-AMA-402 (keşif-
  # bile-bedava-değil; fail-closed). docs/RESEARCH.md §5.3.
  bash tests/at220_kesif_katmani_paritesi_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-220: keşif-katmanı paritesi ( 9/9; agents.json + bazaar-honest)" mesh fastapi
  # AT-221: SIWX ↔ Tamga ajan-kimlik paritesi — CAIP-122/EIP-4361 (§5.5).
  # Kimlik-ödemeli-bağlı (atfedilebilir), EVM-imza SIWX-ile-aynı-matematik,
  # tekrar-erişim/auth-only honest-boşluk (ekonomik-model-seçimi), fail-closed.
  bash tests/at221_siwx_ajan_kimlik_paritesi_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-221: SIWX ↔ Tamga ajan-kimlik paritesi ( 7/7)" mesh
  # AT-222: wasmtime platform-tier + CVE-kapsam-dışı — x86_64 Tier-1,
  # sürüm-48.0.1 ≥ CVE-34987-patch-ailesi, deterministik-Tier-1-stability.
  # AT-212'nin-kaynak-kanıtını-çalışma-zamanı-üçlüsüyle-tamamlar.
  bash tests/at222_wasmtime_platform_tier_cve_kapsam_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-222: wasmtime platform-tier + CVE-kapsam-dışı ( 5/5)"
  # AT-223: facilitator-bağımsızlık — x402-resmi-docs production-mainnet için
  # public-facilitator-ÖNERMEZ; Tamga-self-facilitating: facilitatorsuz-exact
  # fail-closed-402, pugio0 self-contained-200 (§5.6).
  bash tests/at223_facilitator_bagimsizlik_dikis.sh > /dev/null 2>&1
  kontrol_req $? "AT-223: facilitator-bağımsızlık / self-facilitate ( 5/5)" mesh
  # AT-224: canlı-kanıt tazelik — README/docs'taki Base-mainnet-iddialarını
  # BUGÜN bağımsız-public-RPC'den-yeniden-doğrular (güncel-tarihli-veriler).
  # Salt-okuma, anahtarsız; internet-yoksa exit-3-SKIP (asla-false-PASS).
  bash tests/at224_canli_kanit_tazelik_dikis.sh > /dev/null 2>&1
  rc224=$?
  if [ "$rc224" = "3" ]; then kontrol_skip 1 "AT-224: canlı-kanıt tazelik ( SKIP — internet-yok)"; else kontrol "$rc224" "AT-224: canlı-kanıt tazelik doğrulaması ( 6/6; emitter+tx BUGÜN)"; fi
  # AT-225: daemon-kaos-dikişi — gecikme / ardışık-hata / RPC-crash / gaz-spike /
  # normal altında fail-closed. Üretim-bulgusu: cursor-cycle-sonunda-ilerler →
  # hata-sonrası-toparlanmada-request-kaçabilir (backfill-ile-çözülür).
  bash tests/at225_daemon_kaos_dikis.sh > /dev/null 2>&1
  # [Fix-2026-10-03] AT-225 mesh-modülü (sester.ledger) gerektirir: relayer
  # tamga_oracle_relayer.py:486 'from sester.ledger import Ledger' — CI yalnızca
  # bu repo'yu checkout eder → sester YOK → TamgaRelayerError ile kırmızı.
  # Kardeş-repo yokken İNDETERMİNE'dir (CI-run #339, 3.13 bacağı).
  kontrol_req $? "AT-225: daemon-kaos-dikişi — fail-closed her-senaryoda ( 5/5)" mesh
  # AT-226: RFC-010 SUBMITTER/PAYEE-AYRIMI — x402-#2887 (babyblueviper1). Üç
  # adres ayrı-rollerdir: payer=buyerAddress, payee=sellerAddress=merchant'ın
  # payTo'su, submitter=tx.from=FACILITATOR. Facilitator-attribution'ı
  # SUBMITTER'a-keylenir, ASLA payee'ye. Kontrol-7-additive: submitter-yoksa
  # eski-GREEN (geri-uyumlu); submitter==payee → RED rc9 conflation. RFC-010-§3c.
  bash tests/at226_rfc010_submitter_payee_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-226: RFC-010 submitter/payee-ayırmı ( x402-#2887; 3/3)"
  # AT-227: fail-closed SystemExit-dikişi — bozuk-state/graph_merkle → rc!=0 +
  # structured-JSON (traceback-YOK). AT-197'nin-secret-yolunu-tamamlar.
  bash tests/at227_fail_closed_systemexit_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-227: fail-closed SystemExit dikişi ( 5/5)"
  # AT-228: TAMPER-DETECTION-DERİN + registry-round-trip + fail-closed-anahtar.
  # AT-208'in-K6/K7'sine-derinlik-katar: stdout_sha256/seq/ts-tamper → RED-14;
  # node_sig-bozuk → RED (D8-imza-katmanı); registry backup→sil→restore-sonrası
  # registry-check-GREEN; geçersiz-hex/yanlış-uzunluk/olmayan-seed → RED.
  bash tests/at228_tamper_derin_registry_roundtrip_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-228: tamper-derin + registry-round-trip + fail-closed-anahtar ( 10/10)"
  # AT-215: x402-RESPONSE-PROVENANCE — PR #3304 normative-vektörünün bağımsız-
  # yeniden-türetimi. tools/x402_response_provenance.py'nin-gerçek-çalıştığını-
  # kanıtlar (byte-exact-134 + kapalı-küme + verify-yolu; x402'ye-bağımsız).
  bash tests/at215_x402_response_provenance_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-215: x402 response-provenance bağımsız-türetim ( PR #3304, 6/6)"
  # AT-090: SESTER-LEDGER → RFC-010 DOĞRUDAN-DİKİŞ — üretim-ledger'ını (5299-py,
  # 6-x402-servisinin-arkasındaki-gerçek-ledger) RFC-010-gate'ine-bağlar. Önce-
  # kayıt-dışıydı (tek-başına-yeşil-rc=0); suite-kapsamına-alındı (Faz-4).
  bash tests/at090_sester_ledger_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-090: Sester-ledger → RFC-010 doğrudan-dikiş ( gerçek-ledger)"
  bash tests/at163_state_tahriz_run_korumasi_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-163: state-tahriz-run-korumasi ( import-rc17-canli, run-yolu-acik)"
  bash tests/at120_sester_bridges_k1_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-120: Sester-bridges K1-köprü ( alıcı-tarafı-pür-sha256) → RFC-010"
  bash tests/at125_pactiva_qr_canlilik_dikisi.sh > /dev/null 2>&1
  kontrol $? "AT-125: Pactiva qr-canlılık ( rolling-HMAC + replay-koruması)"
  # AT-229: BRANDSTRIKE-TSA — README'nin time-axis DOC-bağı ARTIK-KOD: tools/
  # brandstrike_tsa.py bir RFC 3161 TSA-tokenını Tamga'nın hash-zincirinin
  # zincirbaşı-özetine bağlar ( messageImprint == sha256(chain-tip)). Zaman-
  # ekseni (TSA-oradan) + bütünlük-ekseni (JCS hash-chain-buradan) tek-kanıtta
  # birleşir. 11-kontrol: runner'la-zincir-paritesi + GREEN + 6-RED ( decoy/
  # replay/imza/red-status/malformed-DER/kırık-zincir) + sıfır-yeni-bağımlılık.
  bash tests/at229_brandstrike_tsa_dikis.sh > /dev/null 2>&1
  kontrol $? "AT-229: BrandStrike-TSA code-bond ( RFC 3161 ↔ hash-chain; zaman-ekseni)"

  rm -rf "$SB"
  echo ""
  echo "RESULT: $PASS PASS, $SKIP SKIP, $FAIL FAIL — log: $LOG"
  [ "$FAIL" = "0" ]
} 2>&1 | tee -a "$LOG"
exit ${PIPESTATUS[0]}
