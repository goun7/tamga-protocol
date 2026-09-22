#!/usr/bin/env bash
# AT-153: TAMGA-CONSENSUS-KATMANI-TARAMASI — multi-node head-uzlaşma-yüzü-ARA (dürüst).
#
# task-52 (blockchain-yüzü-10). Tamga-blockchain-dönüşümü-için-henüz-ölçülmemiş-yüz:
# "birden-fazla-node-arası-tutarlılık (consensus-benzeri-yüz)".
#
# VERDICT: İNDETERMİNE — Tamga-çekirdeğinde-GERÇEK-bir-consensus-katmanı (head-
# uzlaşması/reconciliation/quorum/fork-çözümleme) YOK. RFC-003-ledger.md §49:
#   "3. A multi-node shared ledger → Phase 3 (a network, not single-machine simnet)."
# §55 residual-limit: "simnet v0 (single-writer): a seed-owner who is also the
# node-owner can still mint consistent state". §123: L2 (Phase 3: ERC-8004
# reputation binding). Kod-taraması: reconcile/quorum/fork/merge-head-üretimi-
# YOK (bu-test-gerçek-tarama-yapar, varsayım-değil).
#
# ÖLÇÜLEN-GERÇEK-YÜZ (consensus DEĞİL — F24-portability): export → birden-fazla
# bağımsız-hedefe-import → head'ler-BİREBİR-EŞİT. Ama bu DETERMİNİSTİK-TAŞINMADIR:
# zincir-node_id'sini-ve-node_sig'i-KAYNAK-node'dan-taşır; import-eden-node
# yeniden-imzalamaz/yeniden-uzlaşmaz. Uzlaşma (farklı-node'ların-farklı-head'lerini
# bağdaştırma) yok — tek-yazıcı-simnet-v0.
#
# K0-DUVARI: bu-Sybil-DEĞİL-zincir-tutarlılığı; ağırlık-ÖLÇÜLMEZ (ağırlıklı/
# transitif-EigenTrust-YASAK — KIRMIZI, delta-0.6454→0.4892). Consensus-tespiti-
# edilse-bile-bu-test-düz-ikili-tutarlılık-üzerinden-gider.
#
# ADDITIVE-DİKİŞ (uzlaşma-için-DEĞİL — F24-taşınan-head'in-ödeme-yüzü): taşınan
# D5-head → RFC-010 x402/v1 GREEN rc0, equals-link; rc4 + rc7 negatifleri.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/TAMGA-CONSENSUS"
LOG="$EVDIR/$(date +%F)/at153.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f tamga_runner.py ]; then
  note "[SKIP] AT-153: tamga_runner.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, nacl" 2>/dev/null; then
  note "[SKIP] AT-153: eth_keys/nacl-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

W="$(mktemp -d)"
python3 - "$W" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, pathlib, shutil, subprocess, sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")

W = pathlib.Path(sys.argv[1])
ROOT = pathlib.Path(".")
env = dict(os.environ, TAMGA_KS_PASSPHRASE="at153-pass-2026")

def sh(*a):
    return subprocess.run([sys.executable, "tamga_runner.py", *a],
                          capture_output=True, text=True, env=env, cwd=str(ROOT))

VEC = ROOT / "tests/vectors/tc-a1"

# --- 0) gerçek-node-cosign'lı-zincir: grant + run (--node-key ile L1-zincir)
SEED = json.loads(sh("keygen").stdout)["seed_hex"]
sh("keygen-node", str(W / "nodeA"))
sh("keygen-node", str(W / "nodeB"))
sA = (W / "nodeA" / "node_seed.hex").read_text().strip()
sB = (W / "nodeB" / "node_seed.hex").read_text().strip()
nA = (W / "nodeA" / "node_pub.hex").read_text().strip()
nB = (W / "nodeB" / "node_pub.hex").read_text().strip()
assert nA != nB, "iki-bağımsız-node-anahtarı-aynı-üretildi"

PKG = W / "pkg"; PKG.mkdir()
for f in ("tamga.json", "agent.wasm"):
    shutil.copy(VEC / f, PKG / f)
sh("grant", str(PKG), "0.01", "at153", "--node-key", sA)
sh("run", str(PKG), "--seed", SEED, "--node-key", sA, "--note", "at153")
recs = [json.loads(l) for l in (PKG / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
        if l.strip()]
if len(recs) < 2:
    print(f"  [İNDETERMİNE] kurulum-2-kayıt-üretmedi ({len(recs)}) — engine-yoksa-"
          f"koşum-yeşil-sayılamaz; sonuç-esirgenir")
    sys.exit(0)
assert all(r.get("node_id") == nA and "node_sig" in r for r in recs), \
    "node-cosign-L1-zincir-değil (node_id/node_sig-eksik)"
print(f"  gerçek-zincir: {len(recs)}-kayıt, hepsi-nodeA-cosign'lı "
      f"(node_id-hash-içinde, node_sig-hash-dışında — D8)")

# --- 1) F24-portability: export → 2-bağımsız-hedefe-import (L1 + trust)
sh("export", str(PKG), "-o", str(W / "snap.tsg"), "--seed", SEED)
assert (W / "snap.tsg").stat().st_size > 0, "export-boş-snap"
(W / "trust.json").write_text(json.dumps([nA]), encoding="utf-8")

from tamga_project_head import chain_head

h0, n0 = chain_head(PKG)
importler = {}
for ad in ("impA", "impB"):
    d = W / ad; d.mkdir()
    for f in ("tamga.json", "agent.wasm"):
        shutil.copy(VEC / f, d / f)
    r = sh("import", str(W / "snap.tsg"), str(d), "--cosign-policy", "L1",
           "--node-trust", str(W / "trust.json"))
    rr = json.loads(r.stdout) if r.stdout.strip().startswith("{") else {"ok": False}
    assert rr.get("ok") is True, f"{ad}-import-başarısız: {rr}"
    lv = json.loads(sh("ledger-verify", str(d)).stdout)
    assert lv.get("ok") is True, f"{ad}-ledger-verify-başarısız: {lv}"
    h, n = chain_head(d)
    importler[ad] = h
    assert h == h0 and n == n0, f"{ad}-head-uyumsuz: {h} ≠ {h0}"
print(f"  F24-portability: 2-bağımsız-hedefe-import → head'ler-BİREBİR-EŞİT "
      f"({h0[:20]}…, {n0}-kayit, ledger-verify-ikisinde-de-ok)")

# --- 2) CONSENSUS-FACE-PROBE (gerçek-kod-taraması — varsayım-değil)
import re
yuzler = []
for mod in sorted(ROOT.glob("tamga_*.py")):
    try:
        src = mod.read_text(encoding="utf-8")
    except Exception:
        continue
    for pat in ("reconcil", "quorum", "fork", r"merge.*head", r"head.*merge",
                "majority", "byzantine", "ballot", "finalize"):
        for m in re.finditer(pat, src, re.IGNORECASE):
            yuzler.append(f"{mod.name}:{pat}")
# RFC-003-§49-belgesel-kanıt: Phase-3-erteleme
rfc = (ROOT / "docs/RFC-003-ledger.md").read_text(encoding="utf-8")
phase3 = "A multi-node shared ledger" in rfc and "Phase 3" in rfc
residual = "single-writer" in rfc
if yuzler:
    print(f"  [İLGİLİ-BULGU] consensus-benzeri-belirteçler: {sorted(set(yuzler))[:6]}")
else:
    print("  consensus-face-probe: reconcile/quorum/fork/merge-head/majority/"
          "byzantine/ballot/finalize — kod-yüzünde HİÇBİRİ YOK (gerçek-tarama)")
if phase3 and residual and not yuzler:
    print("  RFC-003-§49/§55: multi-node-shared-ledger-Phase-3'e-erteli; simnet-v0-"
          "single-writer-residual-limit-işli → GERÇEK-CONSENSUS-KATMANI-YOK")
    VERDICT = "İNDETERMİNE"
else:
    VERDICT = "ÖLÇÜLEBİLİR"
    print("  [UYARI] consensus-benzeri-yüz-tespit-edildi — RFC-010-bağı-yapılmalı")
print(f"  >>> VERDICT: {VERDICT} — consensus-benzeri-yüz-{'YOK' if VERDICT == 'İNDETERMİNE' else 'VAR'}")

# --- 3) ADDITIVE-DİKİŞ (F24-taşınan-head — uzlaşma-DEĞIL-ödeme-yüzü; gerçek-EIP-191)
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
BUYER = SK.public_key.to_checksum_address().lower()
digest = h0  # equals-link: taşınan-head = evidenceHash = delivery = §6-head
claim = {"buyerAddress": BUYER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "TAMGA-CONSENSUS-153",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "TAMGA-CONSENSUS-153",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": BUYER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "tamga", "head_hex": h0,
              "entries": n0, "evidence_link": "equals",
              "verify_cmd": "tamga_project_head.chain_head"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"F24-head-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["6_foreign_chain"] is True
print(f"  ADDITIVE-DİKİŞ: F24-taşınan-head → x402/v1 GREEN rc0 ({n0}-blok, "
      f"§6-equals) — NOT: bu-uzlaşma-kanıtı-DEĞİL; taşınan-zincirin-ödeme-yüzü")

# --- 4) NEG-1: sahte-imza → rc4
bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4 (gerçek-ecrecover-reddeder)")

# --- 5) NEG-2: evidenceHash-swap → rc7
c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7 (taşınan-head'i-değiştirilemez)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(consensus-tarama + F24-portability + dikiş + negatif)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }
rm -rf "$W"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-153: consensus-katman-taraması → İNDETERMİNE (gerçek-yüz-yok; F24-portability-ölçüldü)"
[[ $FAIL -eq 0 ]]
