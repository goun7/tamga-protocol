#!/usr/bin/env bash
# AT-226: RFC-010 SUBMITTER/PAYEE-AYRIMI — x402-#2887 (babyblueviper1) kapanışı.
#
# babyblueviper1'nin-x402#2887-teşhisi (RFC-010-§3c):
#   "payTo = merchant'tır; facilitator = tx.from'dur (submitter). Merchant'ın
#    payee-adresi-asla-facilitator-adresi-olamaz. Bir-kayıt-şekli-'hangi-
#    facilitator-settle-etti'ne-keylenmek-isterse-SUBMITTER-adresine-
#    keylenmelidir — payee'ye-değil; yoksa-her-merchant-attribution'sız-görünür."
#
# ÜÇ-ÖLÇÜLEN-DURUM (her-biri-tam-gerçek-yol — AT-077-derse-uygun: imza-gerçek
# Ed25519'dur (tamga/native), test-double-YOK — böylece kontrol-7'nin-alan-
# mantığı-gerçek-doğrulama-yolunda-ölçülür, sahte-yeşil-veremez):
#
#   1) GREEN: submitter-VAR-ve-payee'den-AYRI → tam-gate-GREEN. Bu-kanıtlar:
#      facilitator-attribution'ı-DOĞRU-anahtara (submitter/tx.from)-keylendiğinde
#      kabul-edilir — ve-alan-additive'dir (yoksa-da-GREEN — eski-dikişler-bozulmaz).
#   2) RED rc9: submitter == payee → RED `submitter_payee_conflation`. #2887'nin-
#      kendi-iddiasının-fail-closed-gücü: merchant'ın-payee-adresi-asla-facilitator
#      olamaz; bu-ayrımı-çökerten-kayıt-reddedilir (gizli-açık-kapı-değil).
#   3) RED rc6: facilitator-YANLIŞLA-`payee`'ye-keylenmiş (eski-üretici-tuzağı) →
#      RED `party_mismatch`. Bu-kanıtlar-MEVCUT-payer/payee-keylemenin-zaten-
#      doğru-olduğunu: claim.sellerAddress (merchant) ≠ bind.payee (facilitator)
#      — yanlış-keyleme-önceden-yakalanır (safal207'nin-party-negatifiyle-aynı).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-226/$(date +%F)/at226.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-226: RFC-010 submitter/payee-ayırmı (x402-#2887)"

PY=python3
WORK="$(mktemp -d)"

# --- ortak-charge+claim-yazıcı (gerçek-Ed25519-imzalı, tamga/native)
write_base() {
  $PY - "$WORK" <<'PYEOF'
import json, pathlib, sys, hashlib
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
w = pathlib.Path(sys.argv[1])

# Deterministik-simnet-anahtarı ( üretim-ÖZEL-ANAHTARI DEĞİL — test-tohumu)
from nacl.signing import SigningKey
from nacl.encoding import HexEncoder
SEED = hashlib.sha256(b"at226-simnet-test-key").digest()
sk = SigningKey(SEED)
BUYER = sk.verify_key.encode(encoder=HexEncoder).decode()   # 64-hex pubkey

MERCHANT   = "0x2222222222222222222222222222222222222222"
FACILITOR  = "0x3333333333333333333333333333333333333333"

claim = {"buyerAddress": BUYER, "sellerAddress": MERCHANT,
         "settlementRef": "PAY-226",
         "evidenceHash": {"alg": "sha256", "hex": "c"*64}}
govde = json.dumps({k: v for k, v in claim.items()}, sort_keys=True)
digest = hashlib.sha256(govde.encode("utf-8")).hexdigest()
claim["signature"] = sk.sign(bytes.fromhex(digest)).signature.hex()

base = {"op": "charge", "seq": 1, "prev": "0"*64, "h": "a"*64,
        "stdout_sha256": "b"*64,
        "delivery_hash": {"alg": "sha256", "hex": "c"*64},
        "settlement_bind": {"scheme": "tamga/native", "payment_id": "PAY-226",
                            "claim_evidence_hash": {"alg": "sha256", "hex": "c"*64},
                            "payer": BUYER, "payee": MERCHANT,
                            "submitter": FACILITOR,
                            "verified_at": "2026-09-29T00:00:00Z"}}
(w/"base.json").write_text(json.dumps({"charge": base, "claim": claim}),
                          encoding="utf-8")
PYEOF
}
write_base

# 1) GREEN: submitter-VAR-ve-payee'den-AYRI → tam-gate-GREEN (+yoksa-da-GREEN)
note "1) submitter-var-ve-payee'den-ayrı → GREEN | submitter-yoksa-eski-GREEN"
$PY - "$WORK" <<'PYEOF' >> "$LOG" 2>&1
import json, pathlib, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
import settlement_bind_verify as SB
w = pathlib.Path(sys.argv[1])
d = json.loads((w/"base.json").read_text(encoding="utf-8"))

r = SB.verify(dict(d["charge"]), dict(d["claim"]))
assert r["verdict"] == "GREEN", f"GREEN-beklendi: {r}"
assert r["checks"].get("7_submitter_payee") is True, f"7-ayarlanmadı: {r['checks']}"

# additive-geri-uyumluluk: submitter-YOKSA-eski-davranış-korunur (R9-2)
c2 = json.loads(json.dumps(d["charge"])); del c2["settlement_bind"]["submitter"]
r2 = SB.verify(c2, dict(d["claim"]))
assert r2["verdict"] == "GREEN", f"yokken-GREEN-beklendi: {r2}"
assert "7_submitter_payee" not in r2["checks"], "yokken-7-koşmamalı"
print("  GREEN: submitter=tx.from-facilitator-payee'den-ayrı + additive-yoksa-GREEN")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 1) facilitator-attribution-doğru-keyli"; else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) RED rc9: submitter == payee → #2887-ihlali (merchant'ın-payee'si-asla-facilitator)
note "2) submitter == payee → RED rc9 submitter_payee_conflation (#2887)"
$PY - "$WORK" <<'PYEOF' >> "$LOG" 2>&1
import json, pathlib, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
import settlement_bind_verify as SB
w = pathlib.Path(sys.argv[1])
d = json.loads((w/"base.json").read_text(encoding="utf-8"))

# facilitator-adresi-merchant'ın-payee-adresine-çökertiliyor (#2887-tuzağı)
c = json.loads(json.dumps(d["charge"]))
c["settlement_bind"]["submitter"] = c["settlement_bind"]["payee"]
r = SB.verify(c, dict(d["claim"]))
assert r["verdict"] == "RED", f"RED-beklendi: {r}"
assert r["reason_code"] == 9, f"rc9-beklendi: {r['reason_code']}"
assert r["reason"].startswith("submitter_payee_conflation"), f"reason: {r['reason']}"
print("  RED rc9: submitter==payee-reddedildi ( facilitator ≠ merchant)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 2) #2887-kuralı-fail-closed"; else FAIL=$((FAIL+1)); note "  FAIL 2)"; cat "$LOG"; fi

# 3) RED rc6: facilitator-YANLIŞLA-payee'ye-keylenmiş → mevcut-keyleme-zaten-reddeder
note "3) facilitator payee'ye-keylenirse → RED rc6 party_mismatch (mevcut-keyleme-doğru)"
$PY - "$WORK" <<'PYEOF' >> "$LOG" 2>&1
import json, pathlib, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
import settlement_bind_verify as SB
w = pathlib.Path(sys.argv[1])
d = json.loads((w/"base.json").read_text(encoding="utf-8"))

# Eski-üretici-tuzağı: tx.from (facilitator) payee-alanına-kopyalanıyor.
# claim.sellerAddress-hâlâ-merchant → kontrol-4-yakalar ( safal207-party-negatifi)
c = json.loads(json.dumps(d["charge"]))
c["settlement_bind"]["payee"] = "0x3333333333333333333333333333333333333333"
r = SB.verify(c, dict(d["claim"]))
assert r["verdict"] == "RED", f"RED-beklendi: {r}"
assert r["reason_code"] == 6, f"rc6-beklendi: {r['reason_code']}"
assert r["reason"] == "party_mismatch", f"reason: {r['reason']}"
print("  RED rc6: payee'ye-keylenen-facilitator-party_mismatch-ile-reddedildi")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 3) mevcut-keyleme-yanlış-keylemeyi-reddeder"; else FAIL=$((FAIL+1)); note "  FAIL 3)"; cat "$LOG"; fi

rm -rf "$WORK"
echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-226: RFC-010 submitter/payee-ayırmı (x402-#2887)"
[[ $FAIL -eq 0 ]]
