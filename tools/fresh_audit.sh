#!/usr/bin/env bash
# fresh_audit.sh — kurulu-tekerleği YABANCI gibi okutan tek-komut ritüel (E-14/E-15 sınıflarının
# tekrar-üreticisi; 0.2.5'ten beri elle-koşan tur artık takvimli). PyPI'dan temiz-venv kurar,
# yolçaplarını + boş-argman matrisini + E2E'yi koşar, tek satır verdict basar.
#
# Kullanım: bash tools/fresh_audit.sh [--version X.Y.Z] [--keep]   (varsayılan: en-son PyPI)
# Kapı NOTLARI: quickstart-E2E yalnız engine-önbelleği VARSA koşar (indirme zorlaması yok —
# CI-egress bütçesi); --full ile indirmeye izin verilir. Her SKIP gerekiri stderr'e basılır:
# sessiz-atlama yok (İNDETERMİNE ilkesinin araç-hali).
set -u
VER=""; KEEP=0; ALLOW_DL=0
while [ $# -gt 0 ]; do case "$1" in
  --version) VER="$2"; shift 2;; --keep) KEEP=1; shift;; --full) ALLOW_DL=1; shift;;
  *) echo "bilinmeyen bayrak: $1" >&2; exit 2;;
esac; done
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
DAY=$(date +%F); DIR=".evidence/FRESH-AUDIT/$DAY"; mkdir -p "$DIR"
V="$DIR/venv"; PASS=0; FAIL=0; SKIP=0
log() { echo "$*" | tee -a "$DIR/report.log"; }
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); log "  PASS: $2"; else FAIL=$((FAIL+1)); log "  FAIL: $2"; fi; }
skip() { SKIP=$((SKIP+1)); log "  SKIP: $1"; }   # CI-ilk-koşum bulgusu: $2-yazılmıştı, set-u-yakaladı

PY="${PYTHON:-python3}"
rm -rf "$V"; $PY -m venv "$V" || { log "venv kurulamadı"; exit 2; }
PIP="$V/bin/pip"; TAMGA="$V/bin/tamga"
PKG="tamga-protocol$([ -n "$VER" ] && echo "==$VER")"
# Propagasyon-dersi (0.2.6): index-liste önce, backend sonra — pip'e 2-kaçış-ver, sonra SESSİZ
# başarısız olma: rc2 İNDETERMİNE (bug'umuz değil, PyPI'nin taze-yayın penceresi).
if ! $PIP install -q --no-cache-dir "$PKG" 2>"$DIR/pip.log" || [ ! -x "$TAMGA" ]; then
  sleep 30
  if ! $PIP install -q --no-cache-dir "$PKG" 2>>"$DIR/pip.log"; then
    log "[İNDETERMİNE] PyPI kurulumu yapılamadı (propagasyon mu, kesinti mi — pip.log'a bak): $DIR/pip.log"
    rm -rf "$V"; exit 2
  fi
fi
INSTALLED=$($PIP show tamga-protocol 2>/dev/null | awk '/^Version/{print $2}')
log "kuralı-yabancı: taze-venv · tamga-protocol $INSTALLED (pip --no-cache-dir)"

# 1) yardım + sürüm satırı
$TAMGA --help > "$DIR/help.out" 2>&1; ok $? "--help rc0"
grep -q "version: $INSTALLED" "$DIR/help.out"; ok $? "USAGE sürüm-dizgisi kurulu-sürümle eşit ($INSTALLED)"

# 2) doctor (engine-süz sağlık)
$TAMGA doctor > "$DIR/doctor.out" 2>&1 && grep -q "SAĞLIKLI" "$DIR/doctor.out"
ok $? "doctor: SAĞLIKLI"

# 3) E-14 boş-argman matrisi: mesaj-RED rc1, traceback YOK, vakum-yeşil YOK
CRASH=0
for c in grant run export memory keygen-node ledger ledger-verify quickstart; do
  o=$($TAMGA "$c" 2>&1); r=$?
  echo "$o" | grep -q Traceback && CRASH=1
  { [ "$r" -ne 1 ] || echo "$o" | grep -q '"ok": true'; } && CRASH=1
done
ok $CRASH "boş-argman matrisi (8-komut): rc1 + traceback-yok + vakum-yeşil-yok"

# 4) epoch-verify üçlü-sözleşme: selftest rc0 + ölü-RPC rc2
$TAMGA epoch-verify --selftest > "$DIR/es.out" 2>&1; rc=$?; [ "$rc" -eq 0 ]
ok $? "epoch-verify --selftest rc0 (ağ YOK)"
$TAMGA epoch-verify --selftest 2>&1 | grep -q "OK"; ok $? "selftest iç-kontrol satırı OK"

# 5) E-15 zincir-bağı CANLI (tek-ağ-çağrısı; E2E bayrağından bağımsız — ölürse SKIP değil İN:
#    gerçek-endpoint-denetimi ritüelin-varlık-nedeni). Proof üretimi offline selftest'le-sınırlı;
#    zincir-bağı-provası için sentetik-kanıt + sahte-uyumlu-RPC yerine: gerçek-mainnet-ucuna
#    sepolia-beklentisi → rc2 "yanlış-zincir" BEKLENİR (hastalığın-ilacı-kanıtı).
python3 - "$DIR" <<'PYEOF' > "$DIR/proof.out" 2>&1
import hashlib, json, pathlib, sys
sys.path.insert(0, ".")
from tamga_epoch_verify import _leaf   # tek-doğru-yaprak-formülü-modülün-kendisi-verecek
d = pathlib.Path(sys.argv[1])
fact = "0x" + hashlib.sha256(b"tamga-fresh-audit-synthetic").digest().hex()
root = "0x" + _leaf(fact).hex()          # yaprak=keccak(keccak(fact)); yaprak-sayısı=1 → kanıt-[] → kök=yaprak
payload = {"fact_hash": fact, "epoch_id": 0, "leaf_count": 1, "proof": [], "root": root}
d.joinpath("proof.json").write_text(json.dumps(payload))
PYEOF
ok $? "sentetik-kanıt üretildi (modülün-keccak-yaprak-formülüyle; offline dahil-etme GREEN)"
$TAMGA epoch-verify "$DIR/proof.json" --rpc https://ethereum-rpc.publicnode.com \
  > "$DIR/wrongchain.out" 2>&1; rc=$?
grep -q "yanlış-zincir" "$DIR/wrongchain.out" && [ "$rc" -eq 2 ]; ok $? "E-15 canlı: mainnet-ucu → rc2 yanlış-zincir (bağ-ölü-değil)"

# 5b) liveness-probe CONSOLE-YÜZEYİ (0.2.9+): ölü-port → rc2 İNDETERMİNE (offline-deterministik)
$TAMGA liveness-probe --rpc http://127.0.0.1:9/x > "$DIR/deadport.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q "İNDETERMİNE" "$DIR/deadport.out"; ok $? "liveness-probe console: ölü-port → rc2 (wheel-yüzeyi, üç-sonuç)"

# 6) quickstart E2E — engine-önbelleği varsa (indirme YOK, gürültü YOK)
ENGINE="$HOME/.cache/tamga/bin"
if ls "$ENGINE"/wasmtime* >/dev/null 2>&1 || [ -x tools/bin/wasmtime ]; then
  W=$(mktemp -d /tmp/fa-qs-XXXX)
  timeout 180 $TAMGA quickstart "$W/pkg" > "$DIR/qs.out" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && grep -q '"steps"' "$DIR/qs.out"; ok $? "quickstart E2E (engine-önbelleği-var, indirme-yapılmadı)"
  rm -rf "$W"
elif [ "$ALLOW_DL" -eq 1 ]; then
  W=$(mktemp -d /tmp/fa-qs-XXXX)
  timeout 600 $TAMGA quickstart "$W/pkg" > "$DIR/qs.out" 2>&1; rc=$?
  grep -q '"steps"' "$DIR/qs.out"; ok $? "quickstart E2E (--full: engine-indirmesine-izin verildi)"
  rm -rf "$W"
else
  skip "quickstart E2E: engine-önbelleği YOK ve --full verilmedi — indirme dayatılmaz, gerekçe görünür"
fi

[ "$KEEP" -eq 1 ] || rm -rf "$V"
TOTAL=$((PASS+FAIL))
log "VERDICT: $PASS/$TOTAL PASS, $FAIL FAIL, $SKIP SKIP — sürüm $INSTALLED · kanıt: $DIR"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
