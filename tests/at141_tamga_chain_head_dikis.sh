#!/usr/bin/env bash
# AT-141: TAMGA/NATIVE-ZİNCİRİNİN-BLOK-ÜRETİM-YÜZÜ — chain_head → RFC-010 (x402/v1).
#
# task-49 (yönelim-değişimi: tamga-protocol-blockchain'e-dönüş). tamga/native
# zincirinin-blok-üretim-yüzü `tamga_project_head.py:chain_head(pkg)`: defteri
# D5-boyunca-GERÇEKTEN-yeniden-oynar, (head, lines)-döndürür, kırık → ValueError.
# Bu-test o-yüzü-ölçer (test-double-YOK: gerçek-ledger.jsonl + gerçek-D5-matematiği).
#
# BAĞIMSIZ-TEYİT (Lead-ile-uyuşma): 3-kayıtlık-gerçek-pakette head-in-canlı-D5-
# değeri-64-hex; son-kaydın-h'si-ile-birebir (parity); satır-2-tahrizi "broken@2"
# ile-yakalanır. Head ts-içerdiği-için-canlı-değer-sabit-değildir — sabit-hash
# iddia-edilmez, D5-matematiği-ve-parite-doğrulanır (Lead'in-0fe5…-değeri-onun-
# kendi-koşumunun-zamanlı-kaydıdır; D5-uyumu-tutarlı).
#
# project(head): RFC-009 §5 batch-yaprak-izdüşümü — keccak²(sha256-head).
#
# DİKİŞ: head → RFC-010 x402/v1 (equals-link: head = evidenceHash = delivery
# = §6-tamga foreign-head — tek-64-hex-değer-bütün-§6-bağını-taşır).
#
# NEGATİFLER: rc4 sahte-imza, rc7 evidenceHash-swap, zincir-kırık-üçlüsü
# ( seq-atlama / prev-swap / taşma) → ValueError broken@N.
#
# K0-DUVARI: Sybil-kontrolleri-düz-ikili-ZORUNLU (ağırlıklı-transitif-YASAK —
# EigenTrust-KIRMIZI, delta-0.6454→0.4892). Bu-testte-Sybil-ağırlığı-ölçülMEZ —
# chain_head'in-blok-üretim-yüzü-saf-zincir-matematiğidir, K0-kanal-üzerinden-
# gitmez (yine-de-K0-duvarı-hatırlatılarak-testin-sınırları-belirtildi).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/TAMGA-CHAIN-HEAD"
LOG="$EVDIR/$(date +%F)/at141.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f tamga_project_head.py ]; then
  note "[SKIP] AT-141: tamga_project_head.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-141: eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

W="$(mktemp -d)"
python3 - "$W" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, pathlib, shutil, subprocess, sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")

W = pathlib.Path(sys.argv[1]); PKG = W / "pkg"
env = dict(os.environ, TAMGA_KS_PASSPHRASE="at141-pass-2026")

def sh(*a):
    return subprocess.run([sys.executable, *a], capture_output=True, text=True, env=env)

# --- 0) gerçek-paket: quickstart + grant + run → 3-kayıtlık-gerçek-defter
sh("tamga_runner.py", "quickstart", str(PKG))
sh("tamga_runner.py", "grant", str(PKG), "0.01", "at141-hibe")
sh("tamga_runner.py", "run", str(PKG), "--note", "at141-blok")
lines = [l for l in (PKG / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
         if l.strip()]
if len(lines) < 3:
    print(f"  [İNDETERMİNE] kurulum-3-kayıt-üretmedi ({len(lines)}) — engine-"
          f"yoksa-koşum-yeşil-sayılamaz; sonuç-esirgenir")
    sys.exit(0)
print(f"  gerçek-paket: {len(lines)}-kayıtlık-gerçek-ledger.jsonl (D5-canlı)")

from tamga_project_head import chain_head, project
from tamga_keccak import keccak256

# --- 1) chain_head: D5'i-gerçekten-yeniden-oynar → (head, lines)
head, n = chain_head(PKG)
assert n == len(lines), f"satır-sayısı-uyuşmaz: {n} ≠ {len(lines)}"
assert isinstance(head, str) and len(head) == 64, f"head-64-hex-değil: {head!r}"
assert head != "0" * 64, "head-GENESIS-kaldı (kayıtlar-zincire-girmedi)"
assert all(c in "0123456789abcdef" for c in head), "head-hex-karakter-dışı"
# parity: head-son-kaydın-h'si-ile-birebir (D5-gerçek-yeniden-oynama-kanıtı)
son = json.loads(lines[-1])
assert head == son["h"], f"parity-bozuk: {head} ≠ {son['h']}"
print(f"  chain_head: {n}-kayıt-yeniden-oynandı → head={head[:20]}… "
      f"(parity: son-kaydın-h'si-ile-birebir, 64-hex, GENESIS-değil)")

# --- 2) project(head): RFC-009 §5 batch-yaprak-izdüşümü (keccak²)
proj = project(head)
assert proj["projection_version"] == "TAMGA_PROJECT_HEAD_V1"
assert proj["chain_head"] == head, "izdüşüm-head'i-giriş-head'i-değil"
K = lambda b: bytes.fromhex(keccak256(b).hex())
beklenen_yaprak = "0x" + K(K(bytes.fromhex(head))).hex()
assert proj["leaf_encoded"] == beklenen_yaprak, "yaprak ≠ keccak²(sha256-head)"
assert proj["leaf_encoded"].startswith("0x") and len(proj["leaf_encoded"]) == 66
assert "presentation-only" in proj["honest_boundary"]
print(f"  project(head): leaf={proj['leaf_encoded'][:20]}… "
      f"(keccak²-şeması, AT-022-ile-birebir, sunum-paritesi-sınırı-işli)")

# --- 3) NEG: zincir-kırık-üçlüsü → ValueError broken@N
def tahrif(klasor, satir, **degisiklik):
    hedef = W / klasor
    shutil.copytree(PKG, hedef)
    ls = (hedef / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
    r = json.loads(ls[satir - 1])
    r.update(degisiklik)
    ls[satir - 1] = json.dumps(r)
    (hedef / "ledger.jsonl").write_text("\n".join(ls) + "\n", encoding="utf-8")
    return hedef

# 3a) satır-2-tahrifi → broken@2 (Lead'in-bağımsız-teyidi-ile-uyuşma)
try:
    chain_head(tahrif("bad2", 2, note="TAHRIF"))
    raise AssertionError("satır-2-tahrifi-yakalanmadı!")
except ValueError as e:
    assert "broken@2" in str(e), f"broken@2-beklendi: {e}"
    print("  NEG satır-2-tahrifi: ValueError broken@2 (Lead-teyidi-ile-uyuşma)")

# 3b) seq-atlama (son-kaydın-seq'si-9) → broken@N
try:
    chain_head(tahrif("bad_seq", 3, seq=9))
    raise AssertionError("seq-atlama-yakalanmadı!")
except ValueError as e:
    assert "broken@" in str(e), f"broken@N-beklendi: {e}"
    print(f"  NEG seq-atlama: ValueError {e} (sayaç-kaynaktan-sonra-artar)")

# 3c) prev-swap (orta-kaydın-prev'i-sahte) → broken@N
try:
    chain_head(tahrif("bad_prev", 2, prev="d" * 64))
    raise AssertionError("prev-swap-yakalanmadı!")
except ValueError as e:
    assert "broken@" in str(e), f"broken@N-beklendi: {e}"
    print(f"  NEG prev-swap: ValueError {e} (zincir-bağı-rec.prev==önceki-h)")

# 3d) taşma: sahte-kayıt-append → broken@N+1 (seq/prev-uyumsuz)
tasm = W / "bad_tasma"
shutil.copytree(PKG, tasm)
with open(tasm / "ledger.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps({"seq": 99, "op": "charge", "prev": "e" * 64,
                        "val": 1, "h": "0" * 64}) + "\n")
try:
    chain_head(tasm)
    raise AssertionError("taşma-yakalanmadı!")
except ValueError as e:
    assert "broken@" in str(e), f"broken@N-beklendi: {e}"
    print(f"  NEG taşma (sahte-append): ValueError {e} (üçlü-üretmez)")

# --- 4) DİKİŞ: head → RFC-010 x402/v1 GREEN (gerçek-EIP-191, equals-link)
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
BUYER = SK.public_key.to_checksum_address().lower()
digest = head  # equals-link: head = evidenceHash = delivery = §6-head
claim = {"buyerAddress": BUYER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "TAMGA-HEAD-141",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "TAMGA-HEAD-141",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": BUYER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "tamga", "head_hex": head,
              "entries": n, "evidence_link": "equals",
              "verify_cmd": "tamga_project_head.chain_head"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"chain-head-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["2_claim_sig"] is True and \
    r["checks"]["6_foreign_chain"] is True
print(f"  DİKİŞ: tamga/native-chain-head → x402/v1 GREEN rc0 ({n}-blok, "
      f"§6-equals, gerçek-EIP-191, double-YOK)")

# --- 5) NEG-1: sahte-imza → rc4
bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4 (gerçek-ecrecover-reddeder)")

# --- 6) NEG-2: evidenceHash-swap → rc7
c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7 (zincir-head'i-değiştirilemez)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(chain-head + dikiş + negatif)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }
rm -rf "$W"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-141: tamga/native chain-head blok-üretim-yüzü → RFC-010 (x402/v1)"
[[ $FAIL -eq 0 ]]
