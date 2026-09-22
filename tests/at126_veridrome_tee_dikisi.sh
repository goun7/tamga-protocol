#!/usr/bin/env bash
# AT-126: VERIDROME-ÜÇÜNCÜ-YÜZ ( TEE donanım-tasdiki) → RFC-010-tamga/native.
#
# 73-Veridrome: AT-072 ( RFC-6962-audit-log), AT-108 ( W3C-VC-credential)
# bağlandı. KALAN-ÖLÇÜLMEMİŞ-KRİPTO-YÜZ ( bu-test): core/tee_attestation.py —
#   TEEAttestationVerifier.verify_attestation (:29) — AMD SEV-SNP / AWS Nitro
#     uzaktan-tasdik; PCR0-ölçütü + nonce ( host_data/user_data) + **opsiyonel
#     ECDSA P-384/P-256 donanım-imza-doğrulaması** ( _verify_crypto_signature
#     :58, gerçek-cryptography-ECDSA, P-384-önce-P-256-yedek)
#   PhysicalTEEHardwareDriver (:161) — /dev/sev-guest + /dev/nsm tespiti;
#     donanım-yoksa-deterministik-emülasyon ( gold-image-v1.3-PC R0)
# AT-108'in-W3C-VC'si tee_platform="sev-snp" + pcr0-tasırdı — AMA-asıl-
# doğrulayıcı-modül-henüz-ölçülmemişti. AT-126-onu-doldurur.
#
# DİKİŞ-ÖZELLİĞİ: geçerli-tasdik-sonucunun-claims-özütü (sha256) RFC-010'a
# evidenceHash-olarak-girer; ödeme-imzası-ayrı-atılır ( double-YOK — RFC-010
# §3b: digest'in-ham-baytları-üzerine, AT-108-VeridromeAuthoritySigner'ın
# kendi-imza-yoluyla).
#
# Altı-kanıt + 2-negatif:
#   1) SEV-SNP: doğru-PCR0+nonce → is_valid-True ( gerçek-emülasyon-yolu)
#   2) AWS-Nitro: pcrs["0"]+user_data → is_valid-True
#   3) gerçek-ECDSA-P384-donanım-imzası → sig-yolu-geçerli; P-256-yedek
#   4) fail-closed-çoğullu: yanlış-PCR0 / yanlış-nonce / sahte-imza /
#      desteklenmeyen-platform → is_valid-False
#   5) /dev-sev-guest + /dev-nsm-tespiti ( donanım-yok → deterministik-emülasyon)
#   6) RFC-010-tamga/native-GREEN ( tasdik-özütü + gerçek-Ed25519, §6)
#   7) NEG-1: sahte-imza → RED rc4; NEG-2: evidenceHash-swap → RED rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/VERIDROME-3/$(date +%F)/at126.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-126: Veridrome TEE donanım-tasdiki → RFC-010 tamga/native dikişi"

VR="/home/gokun/projects/01_unicorn/73-Veridrome/src"
if [ ! -f "$VR/veridrome/core/tee_attestation.py" ]; then
  note "[SKIP] AT-126: Veridrome-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import cryptography, nacl" 2>/dev/null; then
  note "[SKIP] AT-126: cryptography/PyNaCl-yok — gerçek-ECDSA/Ed25519-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$VR" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from veridrome.core.tee_attestation import (
    TEEAttestationVerifier, PhysicalTEEHardwareDriver)
from veridrome.core.crypto import VeridromeAuthoritySigner
import settlement_bind_verify as SB

NONCE = os.urandom(16)

# --- 1) SEV-SNP: doğru-PCR0+nonce → is_valid-True (gerçek-emülasyon-yolu)
EMU = PhysicalTEEHardwareDriver.fetch_hardware_attestation(NONCE)
assert "measurement" in EMU and "host_data" in EMU
PCR0 = EMU["measurement"]
assert len(PCR0) == 64 and all(c in "0123456789abcdef" for c in PCR0)
r = TEEAttestationVerifier.verify_attestation("sev-snp", EMU, PCR0, NONCE)
assert r.is_valid is True, f"geçerli-SEV-SNP-beklendi: {r.message}"
assert r.nonce_matched is True and r.pcr0 == PCR0
assert r.message == "AMD SEV-SNP Attestation Verified"
assert r.claims["policy"] == 0x30000
print(f"  SEV-SNP: gerçek-emülasyon-yolu → is_valid-True "
      f"(PCR0={PCR0[:16]}…, policy=0x{r.claims['policy']:x})")

# --- 2) AWS-NITRO: pcrs["0"]+user_data → is_valid-True
NITRO = {"pcrs": {"0": hashlib.sha384(b"veridrome-nitro-gold-v1").hexdigest()},
         "user_data": NONCE.hex(), "module_id": "i-native-enclave-01",
         "timestamp": 1789262700}
rN = TEEAttestationVerifier.verify_attestation("AWS-NITRO", NITRO,
                                               NITRO["pcrs"]["0"], NONCE)
assert rN.is_valid is True and rN.platform == "AWS-NITRO"
assert rN.message == "AWS Nitro Enclave Attestation Verified"
assert rN.claims["module_id"] == "i-native-enclave-01"
print(f"  AWS-NITRO: pcrs['0']+user_data → is_valid-True "
      f"(module={rN.claims['module_id']})")

# --- 3) GERÇEK-ECDSA-P384-donanım-imzası → sig-yolu-geçerli
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes, serialization
sk = ec.generate_private_key(ec.SECP384R1())
pub_pem = sk.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo).decode()
data = f"{PCR0}:{EMU['host_data']}".encode()
sig = sk.sign(data, ec.ECDSA(hashes.SHA384()))
SIG_PAYLOAD = dict(EMU)
SIG_PAYLOAD["signature"] = sig
SIG_PAYLOAD["public_key"] = pub_pem
rSig = TEEAttestationVerifier.verify_attestation("AMD-SEV-SNP", SIG_PAYLOAD,
                                                 PCR0, NONCE)
assert rSig.is_valid is True, f"ECDSA-geçerli-beklendi: {rSig.message}"
assert rSig.message == "AMD SEV-SNP Attestation Verified"
# P-256-yedek-anahtar-da-çalışır ( SHA256-fallback-yolu)
sk256 = ec.generate_private_key(ec.SECP256R1())
pub256 = sk256.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo).decode()
sig256 = sk256.sign(data, ec.ECDSA(hashes.SHA256()))
r256 = TEEAttestationVerifier.verify_attestation(
    "SEV-SNP", {**SIG_PAYLOAD, "public_key": pub256, "signature": sig256},
    PCR0, NONCE)
assert r256.is_valid is True, f"P-256-yedek-beklendi: {r256.message}"
print("  gerçek-ECDSA: P-384-ana-+-P-256-yedek-yolu → sig_valid-True "
      "(opsiyonel-anahtar-kontrolü-üretim-yoluyla)")

# --- 4) FAIL-CLOSED-çoğullu: 4-reddetme-yolu
badPCR = TEEAttestationVerifier.verify_attestation("SEV-SNP", EMU, "e" * 64, NONCE)
badNonce = TEEAttestationVerifier.verify_attestation("SEV-SNP", EMU, PCR0, os.urandom(16))
badSig = TEEAttestationVerifier.verify_attestation(
    "AMD-SEV-SNP", {**SIG_PAYLOAD, "signature": b"\x11" * 96}, PCR0, NONCE)
badPlat = TEEAttestationVerifier.verify_attestation("INTEL-TDX", EMU, PCR0, NONCE)
assert badPCR.is_valid is False, "yanlış-PCR0-kabul-edildi"
assert badNonce.is_valid is False, "yanlış-nonce-kabul-edildi"
assert badSig.is_valid is False, "sahte-imza-kabul-edildi"
assert badPlat.is_valid is False, "bilinmeyen-platform-kabul-edildi"
assert badPlat.message.startswith("Desteklenmeyen TEE platformu")
# alias-tutarlılığı
assert TEEAttestationVerifier.verify_mock_or_real("SEV-SNP", EMU, PCR0, NONCE).is_valid is True
print("  fail-closed: yanlış-PCR0/nonce/sahte-imza/bilinmeyen-platform → "
      "is_valid-False (alias-tutarlı)")

# --- 5) DONANIM-TESPİTİ: /dev-sev-guest + /dev-nsm
assert PhysicalTEEHardwareDriver.SEV_GUEST_DEVICE == "/dev/sev-guest"
assert PhysicalTEEHardwareDriver.AWS_NSM_DEVICE == "/dev/nsm"
hw = PhysicalTEEHardwareDriver.detect_hardware_tee()
# bu-makinede-gerçek-TEE-yok → None (dürüst-ölçüm)
print(f"  donanım-tespiti: detect_hardware_tee()={hw} "
      f"(yoksa-None; emülasyon-deterministik)")

# --- 6) RFC-010-TAMGA/NATIVE-GREEN (tasdik-özütü + gerçek-Ed25519)
signer = VeridromeAuthoritySigner()
PUB_HEX = signer.public_key_bytes.hex()
assert len(PUB_HEX) == 64
# geçerli-tasdik-claims'inin-özütü-ödeme-kanıtıdır
ATTEST_OZUT = hashlib.sha256(
    json.dumps(rSig.claims, sort_keys=True).encode()).hexdigest()
govde = {"buyerAddress": PUB_HEX, "sellerAddress": "0x2" * 40,
         "settlementRef": "VRD-TEE-126",
         "evidenceHash": {"alg": "sha256", "hex": ATTEST_OZUT}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig_hex = signer.sign(bytes.fromhex(d)).hex()   # AT-108-yolu, gerçek-Ed25519
assert len(sig_hex) == 128
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 26, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": ATTEST_OZUT},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "VRD-TEE-126",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": PUB_HEX, "payee": "0x2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": ATTEST_OZUT,
                                  "entries": 1,
                                  "verify_cmd": "veridrome.core.tee_attestation.TEEAttestationVerifier.verify_attestation"}}
r10 = SB.verify(charge, claim)
assert r10["verdict"] == "GREEN", f"TEE-dikişi-GREEN-beklendi: {r10}"
assert r10["checks"].get("2_claim_sig") is True, "stock-Ed25519-doğrulaması-geçmedi"
assert r10["checks"].get("6_foreign_chain") is True, "§6-tamga-zinciri-geçmedi"
print(f"  tasdik-claims-özütü → RFC-010-tamga/native-GREEN (§6-tamga-zinciri, "
      f"PC R0={PCR0[:16]}…)")

# --- 7) NEG-1: sahte-imza → RED rc4
for sahte in ("ff" * 64, os.urandom(64).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (128-hex-sıfır/rastgele) → RED rc4 (fail-closed)")

# --- 8) NEG-2: evidenceHash-swap (aynı-gerçek-anahtarla-yeni-imzalı) → RED rc7
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
c2 = dict(govde2); c2["signature"] = signer.sign(bytes.fromhex(d2)).hex()
r2 = SB.verify(charge, c2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r2}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: sekiz-Veridrome-TEE-tasdik-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-126: Veridrome TEE donanım-tasdiki → RFC-010 tamga/native"
[[ $FAIL -eq 0 ]]
