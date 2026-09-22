#!/usr/bin/env bash
# AT-146: TAMGA-CHAIN-HEAD-ÜRETİM-TUTARLILIĞI — tamga_bundle._chain_head → RFC-010 (x402/v1).
#
# task-51 (blockchain-yüzü-5-tamamlayıcısı). AT-141 chain_head(pkg) dosya-yüzünü
# ölçtü ( ValueError-fırlatan-yol); bu-test BUNDLE-İÇİ-üretim-çekirdeğine-odaklanır:
# `tamga/tamga_bundle.py:_chain_head(lp)` — build()'in-iç-head-üretimi.
#
# FARK (AT-141'e-göre): _chain_head ValueError-FIRLATMAZ — (head, lines, verdict)
# üçlüsü-döndürür; kırık-zincirde-head-boş-verdict="broken@N". build() kırık-zincirde
# BİLE-bundle-üretir (rc=1: "kırık-zincir-de-kanıttır" — fail-loud-ama-kanıtı-saklar).
#
# ÜÇLÜ-ÇAPRAZ-DOĞRULAMA: _chain_head ≡ tamga_verify_mini.verify ≡ son-kaydın-h'si
# (üç-bağımsız-yol-aynı-D5-head'ini-üretir — bundle-içi-üretim-çekirdeği-mini-verifier
# ile-birebir; how_to_verify-sözleşmesi-gerçek).
#
# DİKİŞ: build()'in-ürettiği-head → RFC-010 x402/v1 (equals-link: head = evidenceHash
# = delivery = §6-tamga — tek-64-hex-bütün-§6-bağını-taşır).
#
# NEGATİFLER: rc4 sahte-imza, rc7 evidenceHash-swap, _chain_head-üzerinde-3-zincir-
# kırık ( seq-atlama / prev-swap / taşma) → verdict broken@N + head-boş.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/TAMGA-CHAIN-HEAD"
LOG="$EVDIR/$(date +%F)/at146.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f tamga_bundle.py ]; then
  note "[SKIP] AT-146: tamga_bundle.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-146: eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

W="$(mktemp -d)"
python3 - "$W" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, pathlib, shutil, subprocess, sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")

W = pathlib.Path(sys.argv[1]); PKG = W / "pkg"
env = dict(os.environ, TAMGA_KS_PASSPHRASE="at146-pass-2026")

def sh(*a):
    return subprocess.run([sys.executable, *a], capture_output=True, text=True, env=env)

# --- 0) gerçek-paket: quickstart + grant + run → 3-kayıtlık-gerçek-defter
sh("tamga_runner.py", "quickstart", str(PKG))
sh("tamga_runner.py", "grant", str(PKG), "0.01", "at146-hibe")
sh("tamga_runner.py", "run", str(PKG), "--note", "at146-blok")
lp = PKG / "ledger.jsonl"
lines = [l for l in lp.read_text(encoding="utf-8").splitlines() if l.strip()]
if len(lines) < 3:
    print(f"  [İNDETERMİNE] kurulum-3-kayıt-üretmedi ({len(lines)}) — engine-"
          f"yoksa-koşum-yeşil-sayılamaz; sonuç-esirgenir")
    sys.exit(0)
print(f"  gerçek-paket: {len(lines)}-kayıtlık-gerçek-ledger.jsonl (D5-canlı)")

from tamga_bundle import _chain_head, build
import tamga_verify_mini as VM

# --- 1) _chain_head: D5'i-yeniden-oynar → (head, lines, verdict)
tip, n, verdict = _chain_head(lp)
assert verdict == "ok", f"verdict-ok-beklendi: {verdict}"
assert n == len(lines), f"satır-sayısı-uyuşmaz: {n} ≠ {len(lines)}"
assert isinstance(tip, str) and len(tip) == 64, f"head-64-hex-değil: {tip!r}"
assert tip != "0" * 64, "head-GENESIS-kaldı (kayıtlar-zincire-girmedi)"
assert all(c in "0123456789abcdef" for c in tip), "head-hex-karakter-dışı"
son = json.loads(lines[-1])
assert tip == son["h"], f"parity-bozuk: {tip} ≠ {son['h']}"
print(f"  _chain_head: {n}-kayıt-yeniden-oynandı → head={tip[:20]}… "
      f"(parity: son-kaydın-h'si-ile-birebir, verdict=ok, 64-hex)")

# --- 2) build()-in-iç-head-üretimi: bundle.head == _chain_head.head
out, md, bundle = build(PKG, W / "out")
ch = bundle["chain"]
assert ch["head"] == tip, f"bundle-head ≠ _chain_head: {ch['head']} ≠ {tip}"
assert ch["lines"] == n and ch["verdict"] == "ok"
assert ch["records"] and len(ch["records"]) == n, "bundle-kayıt-kopyası-eksik"
assert bundle["bundle_format"] == "tamga-evidence-bundle/1"
charge_kayitlari = [r for r in lines if json.loads(r).get("op") == "charge"]
assert len(bundle["jobs"]) == len(charge_kayitlari) >= 1, \
    "iş=charge-kaydı-çözümü-bozuk (RFC-003 D5)"
assert bundle["jobs"][0]["h"] == json.loads(charge_kayitlari[0])["h"], \
    "job-h'si-chain-kaydından-farklı (kopya-bozuk)"
print(f"  build() iç-üretim: bundle.chain.head == _chain_head.head "
      f"({ch['head'][:20]}…) — çekirdek-bundle'a-aynen-girer; {len(ch['records'])}-"
      f"kayıt-kopyalandı, {len(bundle['jobs'])}-iş(charge)")

# --- 3) ÜÇLÜ-ÇAPRAZ-DOĞRULAMA: _chain_head ≡ mini-verifier ≡ son-h
mtip, mverdict = VM.verify(str(lp))
assert mtip == tip, f"mini-verifier-head ≠ _chain_head: {mtip} ≠ {tip}"
assert mverdict == "ok", f"mini-verifier-verdict: {mverdict}"
# how_to_verify-sözleşmesi-gerçek: bundle-kayıtlarını-besle → aynı-head
recs = "\n".join(json.dumps(r) for r in ch["records"])
(W / "recs.jsonl").write_text(recs + "\n", encoding="utf-8")
btip, bverdict = VM.verify(str(W / "recs.jsonl"))
assert btip == tip and bverdict == "ok", \
    f"bundle-kayıtlarından-head-üretilemedi: {btip}/{bverdict}"
print("  üçlü-çapraz-doğrulama: _chain_head ≡ tamga_verify_mini ≡ son-kaydın-h'si"
      " ≡ bundle.records'tan-yeniden-üretim (how_to_verify-sözleşmesi-canlı)")

# --- 4) no-ledger-yolu: eksik-defter → ("", 0, "no-ledger")
bos_tip, bos_n, bos_v = _chain_head(PKG / "yok.jsonl")
assert bos_tip == "" and bos_n == 0 and bos_v == "no-ledger", \
    f"no-ledger-yolu-bozuk: {bos_tip!r}/{bos_n}/{bos_v}"
print("  no-ledger-yolu: ('', 0, 'no-ledger') — eksik-defter-istisna-değil-verdict")

# --- 5) NEG: 3-zincir-kırık → verdict broken@N + head-boş
def tahrif(klasor, satir, **degisiklik):
    hedef = W / klasor
    shutil.copytree(PKG, hedef)
    ls = (hedef / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
    r = json.loads(ls[satir - 1])
    r.update(degisiklik)
    ls[satir - 1] = json.dumps(r)
    (hedef / "ledger.jsonl").write_text("\n".join(ls) + "\n", encoding="utf-8")
    return hedef / "ledger.jsonl"

# 5a) seq-atlama
t, nn, v = _chain_head(tahrif("bad_seq", 3, seq=9))
assert v == "broken@3" and t == "", f"seq-atlama-bozuk: {v!r}/{t!r}"
print("  NEG seq-atlama: verdict=broken@3, head-boş (sayaç-kaynaktan-sonra-artar)")

# 5b) prev-swap
t, nn, v = _chain_head(tahrif("bad_prev", 2, prev="d" * 64))
assert v == "broken@2" and t == "", f"prev-swap-bozuk: {v!r}/{t!r}"
print("  NEG prev-swap: verdict=broken@2, head-boş (rec.prev==önceki-h)")

# 5c) taşma: sahte-kayıt-append
tasm = W / "bad_tasma"
shutil.copytree(PKG, tasm)
with open(tasm / "ledger.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps({"seq": 99, "op": "charge", "prev": "e" * 64,
                        "val": 1, "h": "0" * 64}) + "\n")
t, nn, v = _chain_head(tasm / "ledger.jsonl")
assert v == "broken@4" and t == "", f"taşma-bozuk: {v!r}/{t!r}"
print("  NEG taşma (sahte-append): verdict=broken@4, head-boş (üçlü-üretmez)")

# 5d) kırık-zincir-de-kanıttır: build() kırıkta-da-bundle-üretir (verdict-işlenir)
o2, m2, b2 = build(W / "bad_seq", W / "out_bad")
assert b2["chain"]["verdict"] == "broken@3" and b2["chain"]["head"] == "", \
    f"kırık-zincir-bundle-işlenmedi: {b2['chain']['verdict']!r}"
print("  kırık-zincir-de-kanıttır: build() broken@3-verdict'ini-bundle'a-işler "
      "(head-boş; fail-loud-ama-kanıt-saklanır)")

# --- 6) DİKİŞ: head → RFC-010 x402/v1 GREEN (gerçek-EIP-191, equals-link)
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
BUYER = SK.public_key.to_checksum_address().lower()
digest = tip  # equals-link: head = evidenceHash = delivery = §6-head
claim = {"buyerAddress": BUYER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "TAMGA-BUNDLE-146",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "TAMGA-BUNDLE-146",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": BUYER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "tamga", "head_hex": tip,
              "entries": n, "evidence_link": "equals",
              "verify_cmd": "tamga_bundle._chain_head"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"bundle-head-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["2_claim_sig"] is True and \
    r["checks"]["6_foreign_chain"] is True
print(f"  DİKİŞ: bundle-içi-chain-head → x402/v1 GREEN rc0 ({n}-blok, §6-equals,"
      f" gerçek-EIP-191, double-YOK)")

# --- 7) NEG-1: sahte-imza → rc4
bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4 (gerçek-ecrecover-reddeder)")

# --- 8) NEG-2: evidenceHash-swap → rc7
c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7 (bundle-head'i-değiştirilemez)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(bundle-içi-head + dikiş + negatif)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }
rm -rf "$W"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-146: tamga_bundle._chain_head üretim-tutarlılığı → RFC-010 (x402/v1)"
[[ $FAIL -eq 0 ]]
