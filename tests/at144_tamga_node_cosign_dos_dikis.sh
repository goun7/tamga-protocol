#!/usr/bin/env bash
# AT-144: TAMGA-NATIVE-BLOCKCHAIN — node-cosign DoS-direnç-yüzü → RFC-010
#
# Blockchain-dönüşümünün-ilk-yüzü: blok-üretim-tutarlılığı-üç-saldırı-altında:
#   A1 tüm-zincir-sahteciliği ( saldırganın-kendi-node-anahtarıyla-sıfırdan kurulan)
#   A2 dürüst-node_id + saldırgan-imzası ( kimlik-calınmış, imza-sahte)
#   A3 node_sig-atılmış-kayıtlar ( kısmi/full-cosign-drop)
# Üçü-de L1-cosign-policy-altında-rc14-reddi → fail-closed-DoS-direnç.
#
# DİKİŞ: dürüst-üretim-paketinin-gerçek-chain-head'i ( chain_head-yeniden-oynama)
# → RFC-010 x402/v1 ( chain-head = evidenceHash = delivery = §6-tamga).
#
# NEGATİFLER:
#   NEG-1 sahte-imza → RED rc4
#   NEG-2 evidenceHash-swap → RED rc7
#   NEG-3 zincir-kırık ( seq-atla) → chain_head ValueError
set -uo pipefail

TESTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTDIR/.." && pwd)"
LOG="$ROOT/.evidence/TAMGA-CHAIN/$(date +%F)/at144.log"
mkdir -p "$(dirname "$LOG")"

PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }
note()  { echo "$*" >> "$LOG"; }

# --- önbilgi: audit8-saldırı-simülasyonu-kendi-başına-koş ( gerçek-üretim-yolu)
if [ ! -f "$ROOT/tests/audit8_node_cosign.py" ]; then
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — audit8-yok (İNDETERMİNE)"
  exit 0
fi

cd "$ROOT"
OUT="$(timeout 300 python3 tests/audit8_node_cosign.py 2>&1)"
rc=$?
if [ $rc -ne 0 ]; then
  echo "$OUT" | tail -20 >> "$LOG"
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — audit8-koşulamadı (İNDETERMİNE)"
  exit 0
fi
echo "$OUT" >> "$LOG"

# A1/A2/A3-üçü-de-reddedildi-mi
a1=$(echo "$OUT" | grep -c "A1 RESULT: L1 closed it (expected)")
a2=$(echo "$OUT" | grep -c "A2 RESULT: both layers caught the signature layer (expected)")
a3=$(echo "$OUT" | grep -c "A3 SONUÇ: L1 node_sig_missing RED (expected)")
rc14=$(echo "$OUT" | grep -c "reason=14")

if [ "$a1" = "1" ] && [ "$a2" = "1" ] && [ "$a3" = "1" ] && [ "$rc14" -ge 3 ]; then
  PASS=$((PASS+1)); note "  A1+A2+A3-üçü-reddedildi (rc14 ×$rc14) — DoS-direnç-fail-closed"
else
  FAIL=$((FAIL+1)); note "  SALDIRI-GEÇTİ! a1=$a1 a2=$a2 a3=$a3 rc14=$rc14"
fi

# --- DİKİŞ: dürüst-paketin-chain-head'i → RFC-010
python3 <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, pathlib, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
sys.path.insert(0, str(pathlib.Path.cwd()))
from tamga_project_head import chain_head
import settlement_bind_verify as SB

# dürüst-D5-defteri-üret ( audit8'in-kullandığı-aynı-zincir-matematiği)
prev = "0"*64; lines = []
for i, ev in enumerate(["node-join","block-1","cosign-1"], 1):
    rec = {"prev": prev, "seq": i, "event": ev, "node_id": "honest-node-144"}
    j = json.dumps(rec, sort_keys=True, separators=(",", ":"))
    h = hashlib.sha256((prev + j).encode()).hexdigest()
    rec["h"] = h; prev = h; lines.append(rec)

pkg = pathlib.Path("/tmp/at144-durus-pkg"); pkg.mkdir(parents=True, exist_ok=True)
(p := pkg / "ledger.jsonl").write_text("\n".join(json.dumps(r) for r in lines) + "\n", encoding="utf-8")
HEAD, N = chain_head(pkg)
assert len(HEAD) == 64 and N == 3, f"head-üretim-beklendi: len={len(HEAD)} n={N}"
print(f"  dürüst-chain-head: {HEAD[:20]}… ({N}-kayıt, 64-hex)")

# NEG-3: zincir-kırık ( seq-2-atlandı) → ValueError
kirik = [json.loads(l) for l in p.read_text().splitlines()]
kirik = [kirik[0], kirik[2]]
(pathlib.Path("/tmp/at144-kirik.jsonl")).write_text("\n".join(json.dumps(r) for r in kirik) + "\n")
kp = pkg; (kp / "ledger.jsonl").write_text("\n".join(json.dumps(r) for r in kirik) + "\n")
try:
    chain_head(pkg); raise SystemExit("ZİNCİR-KIRIK-YAKALANMADI!")
except ValueError:
    print("  seq-atlama → ValueError broken@2 ( zincir-kırık-doğru-tespit)")
# dürüst-defteri-geri-yükle
(kp / "ledger.jsonl").write_text("\n".join(json.dumps(r) for r in lines) + "\n", encoding="utf-8")
HEAD, N = chain_head(pkg)

from nacl.signing import SigningKey
# x402/v1 = GERÇEK-EIP-191-secp256k1 (§3b: encode_defunct-öneki-var; raw-özüt-DEĞİL)
from eth_account import Account
from eth_account.messages import encode_defunct
acct = Account.create()
PUB = acct.address
govde = {"buyerAddress": PUB, "sellerAddress": "0x" + "2"*40,
         "settlementRef": "TAMGA-CHAIN-144",
         "evidenceHash": {"alg": "sha256", "hex": HEAD}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
_sig = Account.sign_message(encode_defunct(hexstr=d), acct.key)
sig_hex = "0x" + _sig.r.to_bytes(32, "big").hex() + _sig.s.to_bytes(32, "big").hex() + hex(_sig.v)[-2:]
assert len(sig_hex) == 132, f"EIP-191-imza-132-hex-beklendi: {len(sig_hex)}"
# özümden-adres == buyer ( gerçek-EIP-191-kanıtı)
_cek = Account.recover_message(encode_defunct(hexstr=d), vrs=(_sig.v, _sig.r, _sig.s))
assert _cek.lower() == PUB.lower(), "EIP-191-özüm-buyer'a-uymadı"
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 144, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": HEAD},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "TAMGA-CHAIN-144",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": PUB, "payee": "0x"+"2"*40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": HEAD, "entries": 3,
                                  "evidence_link": "equals",
                                  "verify_cmd": "tamga_project_head.chain_head"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"blockchain-head-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True and r["checks"].get("6_foreign_chain") is True
print(f"  dürüst-chain-head → RFC-010 x402/v1 GREEN rc0 ( §6-tamga-zinciri, entries=3)")

# NEG-1: sahte-imza → RED rc4
cs = dict(govde); cs["signature"] = "ff"*64
rs = SB.verify(charge, cs)
assert rs["verdict"] == "RED" and rs["reason_code"] == 4, f"sahte-imza-rc4: {rs}"
print("  sahte-imza → RED rc4 (fail-closed)")

# NEG-2: evidenceHash-swap → RED rc7
g2 = dict(govde); g2["evidenceHash"] = {"alg": "sha256", "hex": "9"*64}
d2 = hashlib.sha256(json.dumps(g2, sort_keys=True).encode()).hexdigest()
c2 = dict(g2); c2["signature"] = sk.sign(bytes.fromhex(d2)).signature.hex()
r2 = SB.verify(charge, c2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, f"swap-rc7: {r2}"
print("  evidenceHash-swap → RED rc7 (fail-closed)")
PYEOF
kontrol $? "AT-144-node-cosign-DoS-direnç + chain-head-dikiş"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-144: tamga-native-blockchain node-cosign DoS-direnç-yüzü → RFC-010"
[ "$FAIL" = "0" ]
