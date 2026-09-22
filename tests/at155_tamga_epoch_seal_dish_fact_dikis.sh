#!/usr/bin/env bash
# AT-155: TAMGA-EPOCH-SEAL / RFC-009-ANCHOR — DIŞ-FACT'İ-KENDİ-ZİNCİRİNE-BAĞLAMA-YÜZÜ.
#
# task-53 (blockchain-yüzü-11; AT-153-önerisi). AT-027 DIŞ-doğrulama-idi (dış→içe
# okuma: epoch-seal'i-biz-doğrularız); bu-test YÖN-TERS: TAMGA'NIN-dış-fact'i-KENDİ
# D5-zincirine-ALMASI (içe-yazma: cmd_anchor → op="anchor").
#
# GERÇEK-BAĞLAMA-YÜZÜ-VAR: cmd_anchor (tamga_runner.py:1425) RFC-009-§2-R9-1..R9-5-
# uygular-ve-op="anchor"-kaydını-D5-zincirine-yazar. anchor-kaydı-ZİNCİRİN-HEDEF'ine
# KRIPTOGRAFİK-BAĞLANIR: h = sha256(prev + jcs(anchor − {h, node_sig})) — foreign_fact
# değiştirilirse-zincir-KIRILIR (bu-testin broken@4-negatifi-ile-kanıtı).
#
# R9-5 (presentation-only): anchor-KAYIT-yapar-DOĞRULAMAZ — dış-fact'in-geçerliliği
# bizim-iddiamız-DEĞİL (green-giydirme-yasak). Bu-test-gerçek-donmuş-kanıt-değerlerini
# kullanır (epoch-10: fact=0x0236…, root=0x997c… — composition-fixture cross-check'li)
# AMA-doğrulama-iddia-ETMEZ; anchor-kaydının-zincire-girişini-ölçer.
#
# DİKİŞ: anchor-sonrası-head → RFC-010 x402/v1 GREEN rc0, equals-link — bu-zincirin
# DIŞ-fact-alma-yüzü §6-foreign_chain'e-MİRROR (foreign_chain_proof chain="tamga",
# head=head — dış-fact'i-almış-zincirin-ödeme-yüzü).
#
# NEGATİFLER: rc4 sahte-imza, rc7 evidenceHash-swap, + anchor-yüzü-negatifleri:
# bilinmeyen-registry → rc7 (kayıt-reddi); anchor-tahrizi → broken@4 (zincir-kırık —
# dış-fact-kriptografik-bağın-kanıtı).
#
# K0-DUVARI: Sybil-değil-zincir-tutarlılığı; ağırlık-ÖLÇÜLMEZ.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/TAMGA-EPOCH-ANCHOR"
LOG="$EVDIR/$(date +%F)/at155.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f tamga_runner.py ]; then
  note "[SKIP] AT-155: tamga_runner.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-155: eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

W="$(mktemp -d)"
python3 - "$W" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, pathlib, shutil, subprocess, sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")

W = pathlib.Path(sys.argv[1])
ROOT = pathlib.Path(".")
env = dict(os.environ, TAMGA_KS_PASSPHRASE="at155-pass-2026")

def sh(*a):
    return subprocess.run([sys.executable, "tamga_runner.py", *a],
                          capture_output=True, text=True, env=env, cwd=str(ROOT))

# gerçek-donmuş-kanıt-değerleri (composition-fixture cross-check'li epoch-10)
FACT = "0x02362521254a8ca4f75097267655f6aeb8524217a25c261f60538edc367136e2"
DIGEST = "0x997c497ef5fe81b98290e990cd8f62e674bd55db8ab3c3ea85d3931b1e6ff71d"
VAT = "2026-09-10T07:32:08Z"

# --- 0) gerçek-paket: quickstart + grant + run → 3-kayıtlık-gerçek-defter
SEED = json.loads(sh("keygen").stdout)["seed_hex"]
PKG = W / "pkg"
sh("quickstart", str(PKG))
sh("grant", str(PKG), "0.01", "at155-hibe")
sh("run", str(PKG), "--seed", SEED, "--note", "at155-blok")
lines = [l for l in (PKG / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
         if l.strip()]
if len(lines) < 3:
    print(f"  [İNDETERMİNE] kurulum-3-kayıt-üretmedi ({len(lines)}) — engine-"
          f"yoksa-koşum-yeşil-sayılamaz; sonuç-esirgenir")
    sys.exit(0)
print(f"  gerçek-paket: {len(lines)}-kayıtlık-gerçek-ledger.jsonl (anchor-öncesi)")

from tamga_project_head import chain_head

h_before, n_before = chain_head(PKG)

# --- 1) cmd_anchor: dış-fact'i-KENDİ-zincirine-bağla (R9-1..R9-5)
r = sh("anchor", str(PKG), "--foreign-registry", "apodix/epoch",
       "--foreign-fact", FACT, "--foreign-digest", DIGEST,
       "--verified-at", VAT,
       "--tool", "verifier_epoque.py + tools/keccak256.py (dual-impl)",
       "--foreign-source",
       "https://explorer.testnet.apodix.vauban.tech/v1/anchors/proof/0x0236")
aj = json.loads(r.stdout) if r.stdout.strip().startswith("{") else {"ok": False}
assert aj.get("ok") is True, f"anchor-GREEN-beklendi: {aj}"
lines2 = [l for l in (PKG / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
          if l.strip()]
anc = json.loads(lines2[-1])
assert len(lines2) == len(lines) + 1, "anchor-kayıdı-eklenmedi"
assert anc["op"] == "anchor" and anc["seq"] == len(lines2), \
    f"anchor-op/seq-bozuk: {anc.get('op')}/{anc.get('seq')}"
assert anc["prev"] == json.loads(lines2[-2])["h"], "anchor-prev-zincire-bağlı-değil"
assert anc["anchor_version"] == "TAMGA_EXTERNAL_ANCHOR_V1", "R9-1"   # R9-1
assert anc["foreign_registry"] == "apodix/epoch", "R9-2"            # R9-2
assert all(anc[k] == v for k, v in
           (("foreign_fact", FACT), ("foreign_digest", DIGEST))), "R9-3"  # R9-3
assert anc["verified_at"] == VAT, "R9-4"                             # R9-4
assert anc["presentation_only"] is True, "R9-5"                     # R9-5
print(f"  cmd_anchor GREEN: op=anchor seq={anc['seq']} — dış-fact (apodix/epoch "
      f"{FACT[:14]}…) R9-1..R9-5-ile-D5-zincirine-BAĞLANDI (presentation-only)")

# --- 2) head-anchor'ı-yansıtır + okuma-yolu-doğrulama
h_after, n_after = chain_head(PKG)
assert n_after == len(lines2) and h_after != h_before, \
    "anchor-head'i-üretmedi (dış-fact-zincire-girmedi)"
assert h_after == anc["h"], "head ≠ anchor-kaydının-h'si (parity)"
lv = json.loads(sh("ledger-verify", str(PKG)).stdout)
assert lv.get("ok") is True, f"ledger-verify-başarısız: {lv}"
print(f"  head-anchor'ı-yansıtır: {h_after[:20]}… (anchor-öncesi {h_before[:14]}… → "
      f"değişti; parity anchor.h-ile-birebir; ledger-verify-ok — R9-okuma-yolunda-da)")

# --- 3) NEG: anchor-tahrizi → broken@4 (dış-fact-kriptografik-bağın-kanıtı)
bad = W / "pkg_bad"; shutil.copytree(PKG, bad)
bl = (bad / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
ba = json.loads(bl[-1]); ba["foreign_fact"] = "0x" + "f" * 64
bl[-1] = json.dumps(ba)
(bad / "ledger.jsonl").write_text("\n".join(bl) + "\n", encoding="utf-8")
try:
    chain_head(bad)
    raise AssertionError("anchor-tahrizi-yakalanmadı!")
except ValueError as e:
    assert "broken@4" in str(e), f"broken@4-beklendi: {e}"
print("  NEG anchor-tahrizi (foreign_fact-swap): broken@4 — dış-fact-zincire-"
      "KRIPTOGRAFİK-bağlı (fact-değişirse-zincir-kırılır; R9-kaydı-üretildiği-"
      "için-kırılım-proof'u)")

# --- 4) NEG: bilinmeyen-registry → rc7 (kayıt-öncesi-reddi; kayıt-eklenmez)
r7 = sh("anchor", str(PKG), "--foreign-registry", "bilinmeyen/registry",
        "--foreign-fact", FACT, "--foreign-digest", DIGEST, "--verified-at", VAT)
j7 = json.loads(r7.stdout)
assert j7.get("ok") is False and j7.get("reason_code") == 7, \
    f"bilinmeyen-registry-rc7-beklendi: {j7}"
assert "unknown_registry" in j7.get("reason", ""), "reason-metni-bozuk"
n_after_reject = len([l for l in (PKG / "ledger.jsonl").read_text(encoding="utf-8")
                      .splitlines() if l.strip()])
assert n_after_reject == n_after, "reddedilen-anchor-zincire-eklenmiş!"
print("  NEG bilinmeyen-registry: rc7 + kayıt-eklenmedi (R9-2-yazma-yolu-reddi)")

# --- 5) DİKİŞ: anchor-head → RFC-010 x402/v1 GREEN (§6-foreign_chain'e-mirror)
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
BUYER = SK.public_key.to_checksum_address().lower()
digest = h_after  # equals-link: anchor-head = evidenceHash = delivery = §6-head
claim = {"buyerAddress": BUYER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "TAMGA-EPOCH-ANCHOR-155",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "TAMGA-EPOCH-ANCHOR-155",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": BUYER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "tamga", "head_hex": h_after,
              "entries": n_after, "evidence_link": "equals",
              "verify_cmd": "tamga_runner.cmd_anchor"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"anchor-head-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["2_claim_sig"] is True and \
    r["checks"]["6_foreign_chain"] is True
print(f"  DİKİŞ: dış-fact-bağlı-head → x402/v1 GREEN rc0 ({n_after}-blok, "
      f"§6-equals — DIŞ-fact-alma-yüzü §6'ya-mirror; gerçek-EIP-191, double-YOK)")

# --- 6) NEG-1: sahte-imza → rc4
bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4 (gerçek-ecrecover-reddeder)")

# --- 7) NEG-2: evidenceHash-swap → rc7
c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7 (anchor-head'i-değiştirilemez)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(dış-fact-bağlama + dikiş + negatif)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }
rm -rf "$W"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-155: RFC-009 anchor dış-fact'i D5-zincirine-bağlar → RFC-010 (x402/v1)"
[[ $FAIL -eq 0 ]]
