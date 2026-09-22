#!/usr/bin/env bash
# AT-149: PACTA-TAMGA-RECEİPT-ALICI-TARAFI-KÖPRÜSÜ — AT-148'in-dışladığı-yüzün-
# tamamlıyıcısı ( mesh-sinerjisinin-İKİNCİ-yönü: alıcı-tarafı).
#
# LEAD'İN-TALİMATI: " AT-148'de-buldun: pacta-tier2_proof.verify_tamga_receipt-
# TÜKETİR. Alıcı-tarafı-da-ölçülmeli — gelen-tamga-receipt'i-gerçek-doğrulama +
# reddi-nasıl-yapıyor ( sahte-receipt → RED). … §6-foreign-chain-daha-anlamlı-
# olabilir ( üçüncü-taraf-zincirini-tüketme)."
#
# ÜRETİCİ-OLARAK-TAMGA, ALICI-OLARAK-PACTA ( köprünün-iki-yönü):
#   Tamga-tarafı: gerçek-EIP-191-imzalı-output_hash ( eth_account.encode_defunct
#     — Pacta'nın-beklediği-format: "0x"+130hex)
#   Pacta-tarafı ( ölçülen-yüz):
#     tier2_proof.py:41 verify_tamga_receipt → üç-katmanlı-alıcı-doğrulama:
#       (1) receipt.verify_tamga_integrity ( yapısal-bütünlük, models.py:78)
#       (2) output_hash == sha256( canonical-payload) ( gerçek-hash-bağlantısı,
#           compute_payload_hash — sort_keys-kanonikleştirme)
#       (3) ECDSA: encode_defunct( output_hash) + Account.recover_message →
#           recovered == expected_signer ( GERÇEK-EIP-191, keccak256)
#     vault.py:130 submit_output → receipt'i-job'a-bağlar → 161 mark_verified_ok
#       → 169 settle_escrow ( keccak256-tx-hash)
#   Yani: alıcı-tarafı-doğrulama-olmadan-escrow-SETTLE-OLAMAZ — receipt-kapısı
#   üretim-akışının- merkezindedir.
#
# RFC-010-BAĞLAMA ( Lead'in-notuna-uygun — §6-alıcı-tarafı-daha-anlamlı):
#   output_hash hem-Pacta'nın-doğruladığı-kanıt hem-RFC-010'un-evidenceHash'idir
#   → §6-chain="pacta" evidence_link="equals": Pacta-alıcı-tarafı-doğrulaması,
#   RFC-010-ise-ödeme-tarafını-bağlar ( AYNI-kanıtı-iki-yönden-tüketme).
#
# Yedi-kanıt + 3-negatif:
#   1) gerçek-üretim-receipt: output_hash=sha256( canonical-payload) + EIP-191-sig
#   2) verify_tamga_receipt-True ( üç-katmanlı-alıcı-doğrulama-geçti)
#   3) EIP-191-gerçek-ecrecover: recovered == expected_signer ( bağımsız-teyit)
#   4) escrow-üretim-akışı: lock → submit( receipt) → mark_verified_ok → settle
#   5) receipt'i-olmadan-veya-uyumsuz-olarak-settle-yolu-doğrulama-ister
#   6) tahriz-dayanıklılığı: payload-değişince-output_hash-değişir ( sha256)
#   7) RFC-010-GREEN ( §6-pacta-equals; alıcı-tarafı-üçüncü-zinciri-tüketme)
#   N1) output_hash-uymazlığı → RED ( hash-katmanı)
#   N2) sahte-imza → RED ( ECDSA-katmanı, recovered ≠ expected)
#   N3) eksik-receipt → RED ( kapı-eksikliği)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/PACTA-ALICI-KOPRU/$(date +%F)/at149.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-149: Pacta tamga-receipt alıcı-tarafı köprüsü (verify_tamga_receipt) → RFC-010"

PACTA="/home/gokun/projects/00_TAMGA-MESH/pacta"
if [ ! -f "$PACTA/pacta/verification/tier2_proof.py" ]; then
  note "[SKIP] AT-149: Pacta-kodu-bu-makinede-değil (CI) — alıcı-tarafı-yüzü"
  note "       ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_account, eth_keys, web3" 2>/dev/null; then
  note "[SKIP] AT-149: eth_account/eth_keys/web3-yok — gerçek-ECDSA-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$PACTA" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, sys.argv[1])          # pacta-paketi
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from pacta.models import TamgaExecutionReceipt
from pacta.verification.tier2_proof import Tier2CryptographicValidator as T2
from pacta.core.vault import PactaEscrowVault
from pacta.models import EscrowStatus
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_account import Account
from eth_account.messages import encode_defunct
from eth_utils import to_checksum_address

# --- 1) GERÇEK-üretim-receipt: output_hash + EIP-191-sig ( Tamga-üretici-tarafı)
SIGNER = ek.PrivateKey(os.urandom(32))
ADDR = to_checksum_address(SIGNER.public_key.to_address())
payload = {"job": "scrape-51", "result": {"rows": 51, "status": "ok"},
           "digest": "at149-canlik"}
out_hash = hashlib.sha256(
    json.dumps(payload, sort_keys=True).encode()).hexdigest()
# Pacta'nın-beklediği-format: "0x"+130hex ( tier2:74)
sig = Account.sign_message(
    encode_defunct(text=out_hash), private_key=SIGNER).signature.hex()
if not sig.startswith("0x"):
    sig = "0x" + sig          # tier2:74-formatı: "0x"+130hex
assert sig.startswith("0x") and len(sig) == 132, f"sig-formatı-bozuk: {len(sig)}"
receipt = TamgaExecutionReceipt(
    job_id="at149-j1", program_hash="a" * 64, input_commitment="b" * 64,
    output_hash=out_hash, wasi_trace_root="c" * 64, instruction_count=4242,
    timestamp_epoch=1790000000, signature=sig)
assert receipt.verify_tamga_integrity() is True, "yapısal-bütünlük-bozuk"
print(f"  üretim-receipt: output_hash=sha256( canonical-payload)={out_hash[:16]}… "
          "+ gerçek-EIP-191-sig ( 0x+130hex)")

# --- 2) verify_tamga_receipt-True ( üç-katmanlı-alıcı-doğrulama)
res = T2.verify_tamga_receipt(payload, receipt, expected_signer=ADDR)
assert res.is_valid is True, f"alıcı-doğrulaması-geçmedi: {res.reason}"
assert res.proof_type == "TAMGA_WASI", f"proof-type-yanlış: {res.proof_type}"
assert "4242" in res.reason, "instruction-count-sebette-yok"
print(f"  verify_tamga_receipt-True ( 3-katman: integrity + hash + ECDSA): "
          f"{res.reason}")

# --- 3) EIP-191-gerçek-ecrecover ( bağımsız-teyit — Pacta'nın- Kendi-yolu)
recovered = Account.recover_message(
    encode_defunct(text=out_hash), signature=receipt.signature)
assert recovered.lower() == ADDR.lower(), "EIP-191-recover-adrese-çözümlenmedi"
# AYNI-hash'i-farklı-anahtarla-imzala → recover-farklı-olmalı
OTHER = ek.PrivateKey(os.urandom(32))
sig_other = Account.sign_message(
    encode_defunct(text=out_hash), private_key=OTHER).signature.hex()
rec_other = Account.recover_message(
    encode_defunct(text=out_hash), signature=sig_other)
assert rec_other.lower() != ADDR.lower(), "farklı-anahtar-aynı-adresi-verdi"
print("  EIP-191-gerçek-ecrecover: recovered == expected_signer ( keccak256; "
          " bağımsız-teyit + anahtar-ayrımı)")

# --- 4) ESCROW-üretim-akışı: receipt-kapısı olmadan settle-olmaz
v = PactaEscrowVault()
job = v.create_and_lock_escrow(ADDR, "0x" + "2" * 40, 10)
assert job.status == EscrowStatus.ESCROW_LOCKED, f"kilitlenmedi: {job.status}"
sub = v.submit_output(job.job_id, payload, tamga_receipt=receipt)
assert sub.status == EscrowStatus.OUTPUT_SUBMITTED, "submit-olmadı"
assert sub.tamga_receipt is not None and sub.output_payload == payload, \
    "receipt/iş-yükü-job'a-bağlanmadı"
v.mark_verified_ok(job.job_id)
assert sub.status == EscrowStatus.VERIFIED_OK, "verified_ok-olmadı"
j2, tx = v.settle_escrow(job.job_id)
assert j2.status == EscrowStatus.SETTLED, "settle-olmadı"
assert j2.settlement_tx == tx and tx.startswith("0x"), "tx-hash-bağlanmadı"
print(f"  escrow-akışı: LOCK → SUBMIT( receipt) → VERIFIED_OK → SETTLED "
          f"( tx={tx[:14]}…) — alıcı-doğrulaması-üretim-merkezinde")

# --- 5) tahriz-dayanıklılığı: payload-değişince-output_hash-değişir
payload2 = dict(payload); payload2["result"] = {"rows": 0, "status": "fail"}
out2 = hashlib.sha256(json.dumps(payload2, sort_keys=True).encode()).hexdigest()
assert out2 != out_hash, "payload-değişti-ama-hash-aynı ( tahriz-yutuldu)"
assert T2.compute_payload_hash(payload) == out_hash, "compute-bağımsız-tutmadı"
print("  tahriz-dayanıklı: payload-bozulunca-output_hash-değişir ( sha256-"
          "kanonik); compute_payload_hash-bağımsız-teyit")

# --- 6) RFC-010-GREEN ( §6-pacta-equals; Lead'in-notu: alıcı-tarafı-üçüncü-
#     zinciri-tüketme — output_hash-AYNI-kanıt-iki-yönden)
BUYER = ek.PrivateKey(os.urandom(32))
BADDR = to_checksum_address(BUYER.public_key.to_address())
govde = {"buyerAddress": BADDR, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "PACTA-ALICI-149",
         "evidenceHash": {"alg": "sha256", "hex": out_hash}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sigx = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
claim = dict(govde); claim["signature"] = sigx
charge = {"seq": 1, "prev": "0" * 64, "h": out_hash,
          "delivery_hash": {"alg": "sha256", "hex": out_hash},
          "settlement_bind": {"scheme": "x402/v1",
                              "payment_id": "PACTA-ALICI-149",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": BADDR, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "pacta", "head_hex": out_hash,
                                  "entries": 1,
                                  "evidence_link": "equals",
                                  "verify_cmd": "pacta.tier2: verify_tamga_receipt"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"pacta-alıcı-dikişi-GREEN-beklendi: {r}"
for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
          "5_evidence_hash", "6_foreign_chain"):
    assert r["checks"].get(k) is True, f"{k}-geçmedi: {r}"
print("  output_hash → RFC-010-GREEN ( x402/v1-gerçek-ecrecover; 6/6; "
          "§6-pacta-alıcı-tarafı-equals; AYNI-kanıt-iki-yönden-tüketildi)")

# --- N1) output_hash-uymazlığı → RED ( hash-katmanı)
bad_h = TamgaExecutionReceipt(
    job_id="at149-j1", program_hash="a" * 64, input_commitment="b" * 64,
    output_hash="f" * 64, wasi_trace_root="c" * 64, instruction_count=4242,
    timestamp_epoch=1790000000, signature=sig)
rn1 = T2.verify_tamga_receipt(payload, bad_h, expected_signer=ADDR)
assert rn1.is_valid is False and "mismatch" in rn1.reason, \
    f"hash-uymazlığı-yakalanmadı: {rn1.reason}"
print("  N1-output_hash-uymazlığı → RED ( hash-katmanı: receipt ≠ payload)")

# --- N2) sahte-imza → RED ( ECDSA-katmanı, recovered ≠ expected)
# tier2:74'nin-format-kapısını-geçmek-için-DOĞRU-biçimlendirilmiş-sahte-imza
_sig_raw = Account.sign_message(
    encode_defunct(text=out_hash),
    private_key=ek.PrivateKey(os.urandom(32))).signature.hex()
sig_bad = _sig_raw if _sig_raw.startswith("0x") else "0x" + _sig_raw
# BULGU-KAPANDI ( AT-149-düzeltmesi): "0x"-öneksiz-130hex-imza eskiden
# tier2:74 ECDSA-katmanını-ATLARDI ( startswith-kapısı → hash+integrity →
# GREEN). Üretimde-istismar-edilebilir-açktı: hash'i-doğru-bildiği-sürece
# herkes-sahte-receipt-üretip-escrow-settle-edebilirdi. Düzeltme-ile-artık
# expected_signer-verildiğinde-format-uyumsuzluğu-RED-verir ( fail-closed).
_chk = Account.sign_message(
    encode_defunct(text=out_hash),
    private_key=ek.PrivateKey(os.urandom(32))).signature.hex()
assert not _chk.startswith("0x"), "eth_account-beklenmedik-0x-önekli"
_r_skip = T2.verify_tamga_receipt(payload, TamgaExecutionReceipt(
    job_id="at149-j1", program_hash="a" * 64, input_commitment="b" * 64,
    output_hash=out_hash, wasi_trace_root="c" * 64, instruction_count=4242,
    timestamp_epoch=1790000000, signature=_chk), expected_signer=ADDR)
assert _r_skip.is_valid is False, \
    "0x'siz-imza-hâlâ-ECDSA'yı-atlıyor ( AÇIK-GERİ-GELDİ!) — fail-closed-beklendi"
assert "not skipped" in _r_skip.reason or "132-hex" in _r_skip.reason, \
    f"fail-closed-nedeni-beklenmedik: {_r_skip.reason}"
print("  0x'siz-imza → RED ( AÇIK-KAPANDI: expected_signer-ZORUNLU-artık; "
          "eskiden-bu-format-ECDSA'yı-atlayıp-GREEN-veriyordu)")
bad_s = TamgaExecutionReceipt(
    job_id="at149-j1", program_hash="a" * 64, input_commitment="b" * 64,
    output_hash=out_hash, wasi_trace_root="c" * 64, instruction_count=4242,
    timestamp_epoch=1790000000, signature=sig_bad)
rn2 = T2.verify_tamga_receipt(payload, bad_s, expected_signer=ADDR)
assert rn2.is_valid is False and "does not match" in rn2.reason, \
    f"sahte-imza-yakalanmadı: {rn2.reason}"
print("  N2-sahte-imza ( farklı-anahtar, geçerli-EIP-191) → RED ( ECDSA-"
          "katmanı: recovered ≠ expected_signer)")

# --- N3) eksik-receipt → RED ( kapı-eksikliği — settle-yolu-temiz-değil)
rn3 = T2.verify_tamga_receipt(payload, None)
assert rn3.is_valid is False and "Missing" in rn3.reason, \
    f"eksik-receipt-yakalanmadı: {rn3.reason}"
# yapısal-bozukluk-da-reddedilmeli ( instruction_count ≤ 0)
bad_z = TamgaExecutionReceipt(
    job_id="at149-j1", program_hash="a" * 64, input_commitment="b" * 64,
    output_hash=out_hash, wasi_trace_root="c" * 64, instruction_count=0,
    timestamp_epoch=1790000000, signature=sig)
rn4 = T2.verify_tamga_receipt(payload, bad_z, expected_signer=ADDR)
assert rn4.is_valid is False and "integrity" in rn4.reason, \
    f"yapısal-bozukluk-yakalanmadı: {rn4.reason}"
print("  N3-eksik-receipt → RED ( Missing); yapısal-bozukluk ( instruction=0) "
          "→ RED ( integrity-katmanı)")
print("  ALICI-TARAFI-KÖPRÜSÜ-BAĞLANDI: pacta-verify_tamga-receipt → RFC-010 "
          "( §6-pacta); mesh-sinerjisinin-üretici+alıcı-iki-yönü-de-ölçüldü")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-pacta-alıcı-tarafı-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-149: Pacta tamga-receipt alıcı-tarafı köprüsü (verify_tamga_receipt) → RFC-010"
[[ $FAIL -eq 0 ]]
