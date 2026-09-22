#!/usr/bin/env bash
# AT-128: VERIDROME-DÖRDÜNCÜ-YÜZ ( contracts-on-chain-sertifika-katmanı) →
# RFC-010-DİKİŞİ.
#
# 73-Veridrome: AT-072 ( RFC-6962-audit-log — core/crypto.py), AT-108
# ( W3C-VC-credential), AT-126 ( TEE-donanım-tasdiki) bağlandı. KALAN-
# ÖLÇÜLMEMİŞ-KRİPTO-YÜZ ( bu-test): **on-chain-sözleşme-katmanı**:
#   syntropion-değil — VERIDROME'un-ERC-8004-kayıt-yüzü:
#   contracts/client.py:43 — InMemoryVeridromeRegistryClient.issue_certificate
#     GERÇEK-keccak-256-ile-32-byte-certId-üretir ( eth_utils.keccak):
#       packed = agentId + pcr0Measurement + merkleRoot + now.to_bytes(32)
#       certId = keccak(packed)
#   contracts/abi.py:8 — VERIDROME_REGISTRY_ABI — ERC-8004/EAS-uyumlu-kayıt
#     ABI'ı ( issueCertificate(bytes32,bytes32,bytes32,tuple,address) → bytes32)
#   contracts/client.py:123 — Web3VeridromeRegistryClient — gerçek-web3-ile
#     ABI'yı-derler ( canlı-RPC-GEREKMEZ-eager-bağlantı-yok)
#
# ERC-8004-ÖZELLİĞİ ( bu-testin-asıl-kanıtı): keccak-256-hem-Ethereum-dünyasının
# ( eth_utils.keccak) hem-de-Tamga-çekirdeğinin ( tamga_keccak.keccak256) ortak
# özütüdür — bu-test-o-iki-kripto-alanın-GERÇEK-bayt-paritesini-ölçer-ve-on-chain
# sertifika-kanıtıyla-ödeme-kanalına-bağlar. EAS-abi'ındaki-"Attestation"-
# kaydı-üç-bytes32'den-doğar ( agent+pcr0+merkle) — tekdüze-kanıt-üretimi.
#
# DÜRÜST-BULGU ( test-double-YOK-disiplini): erc8004/v1-scheme-adayının-GERÇEK
# _claim_signer-yolu-keccak256-bytes-döndürür-AMA-verify()-str-buyerAddress-ile
# karşılaştırır → bytes≠str-asla-eşleşmez → GERÇEK-yoldan-GREEN-veremez ( RED
# rc4). AT-065-bunu-SB._claim_signer=lambda-ile-test-double-aracılıyla-aşmış;
# bu-test-double-YAZAMADIğı-için-dikiş-x402/v1-ile-gerçek-ecrecover-üzerinden
# yapılır-ve-erc8004/v1-yolunun-gerçek-davranışı-dürüstçe-ölçülür.
#
# Altı-kanıt + 2-negatif + 1-dürüst-bulgu:
#   1) ABI-yapısal-gerçeklik: ERC-8004-imza + gerçek-web3-ile-derleme
#   2) GERÇEK-keccak-certId-üretimi + bağımsız-yeniden-üretim + iki-alan-paritesi
#   3) Üretici-tarafı-sağlamlık: geçersiz-PCR0/anomali/yetersiz-teminat-RED
#      + yaşam-döngüsü ( deposit→slash→revoke→verify-False)
#   4) RFC-010-x402/v1-GREEN ( ERC-8004-keccak-özütü + gerçek-ecrecover, §6)
#   5) NEG-1: sahte-imza → RED rc4
#   6) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7
#   7) DÜRÜST-BULGU: erc8004/v1-gerçek-yol → RED rc4 ( bytes/str-uyumsuzluk)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/VERIDROME-4/$(date +%F)/at128.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-128: Veridrome dördüncü-yüz (contracts ERC-8004 on-chain) → RFC-010 dikişi"

VR="/home/gokun/projects/01_unicorn/73-Veridrome/src"
if [ ! -f "$VR/veridrome/contracts/client.py" ] || [ ! -f "$VR/veridrome/contracts/abi.py" ]; then
  note "[SKIP] AT-128: Veridrome-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# eth_utils (gerçek-keccak) + web3 (ABI-derleme) yokluğu-eksiklik-değil-İNDETERMİNE
if ! python3 -c "import eth_utils, web3" 2>/dev/null; then
  note "[SKIP] AT-128: eth_utils/web3-yok — gerçek-keccak+ABI-derleme-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$VR" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, sys.argv[1])              # .../73-Veridrome/src
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from veridrome.contracts.client import (
    InMemoryVeridromeRegistryClient, Web3VeridromeRegistryClient)
from veridrome.contracts.abi import VERIDROME_REGISTRY_ABI
from eth_utils import keccak, to_checksum_address
from eth_keys import keys as ek
from tamga_keccak import keccak256
from web3 import Web3
import settlement_bind_verify as SB

# --- 1) ABI-YAPISAL-GERÇEKLİK: ERC-8004/EAS-uyumlu-kayıt-ABI'ı
fns = {f["name"] for f in VERIDROME_REGISTRY_ABI if f.get("type") == "function"}
evs = {e["name"] for e in VERIDROME_REGISTRY_ABI if e.get("type") == "event"}
assert {"issueCertificate", "depositCollateral", "slashCollateral",
        "revokeCertificate", "verifyCertificate"} <= fns, "zorunlu-fonksiyonlar-yok"
assert {"CertificateIssued", "CertificateRevoked", "CollateralDeposited",
        "CollateralSlashed"} <= evs, "zorunlu-eventler-yok"
ic = next(f for f in VERIDROME_REGISTRY_ABI if f.get("name") == "issueCertificate")
# ERC-8004-kayıt-şekli: bytes32-agent + bytes32-pcr0 + bytes32-merkle + tuple-metrics + address
assert [i["type"] for i in ic["inputs"]] == ["bytes32", "bytes32", "bytes32", "tuple", "address"], \
    f"issueCertificate-giriş-şekli-bozuk: {[i['type'] for i in ic['inputs']]}"
assert ic["outputs"][0]["type"] == "bytes32", "certId-bytes32-olmalı"
# metrics-tuple: 5-uint32 (EAS-uyumlu-öznitelik-yığını)
mt = next(i for i in ic["inputs"] if i["type"] == "tuple")
assert [c["type"] for c in mt["components"]] == ["uint32"] * 5
# GERÇEK-web3-ile-ABI-derleme ( canlı-RPC-YOK — eager-bağlantı-yok)
ct = Web3().eth.contract(abi=VERIDROME_REGISTRY_ABI)
assert hasattr(ct.functions, "issueCertificate") and hasattr(ct.functions, "getCertificate")
print("  ABI-ERC-8004: issueCertificate(bytes32,bytes32,bytes32,tuple(5×uint32),address)"
      " → bytes32; gerçek-web3-ile-derlendi")

# --- 2) GERÇEK-keccak-certId-üretimi + iki-kripto-alanın-bayt-paritesi
CLI = InMemoryVeridromeRegistryClient()
PCR0 = bytes.fromhex("123456") + b"\x00" * 29
CLI.set_pcr0_validity(PCR0, True)
AGENT = b"\xaa\xbb\xcc" + b"\x00" * 29     # agentId (EAS-subject)
MROOT = b"\xdd\xee\xff" + b"\x00" * 29     # executionMerkleRoot (AT-108'in-kökü)
CERT = CLI.issue_certificate(AGENT, PCR0, MROOT, 9200, 300, 4, 11, 150,
                             to_checksum_address("0x" + "2" * 40))
assert isinstance(CERT, bytes) and len(CERT) == 32, "certId-32-byte-olmalı"
REC = CLI.certificates[CERT]
# bağımsız-yeniden-üretim ( üretici-tarafı-üretim-yolu-birebir)
PACKED = AGENT + PCR0 + MROOT + REC.issued_at.to_bytes(32, "big")
assert keccak(PACKED) == CERT, "bağımsız-keccak-yeniden-üretimi-eşleşmedi"
# İKİ-KRİPTO-ALAN-BİRLEŞİMİ: Ethereum-keccak ≡ Tamga-keccak ( RFC-010-keccak256-etiketi)
assert keccak(PACKED) == keccak256(PACKED), "eth-utils≡tamga-keccak-paritesi-bozuk"
assert keccak(PACKED).hex() != hashlib.sha256(PACKED).hexdigest(), "keccak≠sha256"
assert keccak(b"").hex() == keccak256(b"").hex() == \
    "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470", "boş-vektör"
assert REC.expires_at - REC.issued_at == 30 * 86400, "30-gün-geçerlilik"
print(f"  gerçek-keccak-certId: {CERT.hex()[:16]}… (32B; eth-utils≡tamga-keccak; "
      f"30-gün-geçerli)")

# --- 3) ÜRETİCİ-TARAFI-SAĞLAMLIK + on-chain-yaşam-döngüsü
# (a) kayıt-dışı-PCR0 → RED ( güvenilir-TEE-profili-zorunlu)
try:
    CLI.issue_certificate(AGENT, b"\x99" * 32, MROOT, 9000, 200, 5, 10, 100,
                          to_checksum_address("0x" + "2" * 40))
    raise AssertionError("kayıt-dışı-PCR0-reddedilmeli")
except ValueError:
    pass
# (b) anomali-eşiği-aşımı → RED ( overfit-koruması)
BAD = b"\x77" * 32
CLI.set_pcr0_validity(BAD, True)
try:
    CLI.issue_certificate(AGENT, BAD, MROOT, 9000, 200, 5, 10, 5000,
                          to_checksum_address("0x" + "2" * 40))
    raise AssertionError("anomali>4500-reddedilmeli")
except ValueError:
    pass
# (c) yaşam-döngüsü: teminat-kilitleme → slashing → iptal
CLI.deposit_collateral(CERT, 10_000_000)
assert REC.collateral_staked == 10_000_000, "teminat-kilitlenmedi"
assert CLI.slash_collateral(CERT, "0x" + "3" * 40, 2_000_000) == 8_000_000
try:
    CLI.slash_collateral(CERT, "0x" + "3" * 40, 9_000_000)   # 8M<yeterli
    raise AssertionError("yetersiz-teminat-reddedilmeli")
except ValueError:
    pass
assert CLI.verify_certificate(CERT) is True
CLI.revoke_certificate(CERT, "SLOH-kötü-niyetli-yürütme")
assert CLI.verify_certificate(CERT) is False, "iptal-sonrası-geçersiz-olmalı"
print("  üretici-tarafı: kayıtsız-PCR0/anomali>4500/yetersiz-teminat → ValueError; "
      "deposit→slash→revoke → verify-False")

# --- 4) Web3-CLIENT: gerçek-web3-ile-ABI-derleme ( RPC-çağrısı-YAPILMAZ)
W3C = Web3VeridromeRegistryClient(rpc_url="http://127.0.0.1:1/",
                                  contract_address="0x" + "11" * 20)
assert hasattr(W3C.contract.functions, "issueCertificate"), "Web3-ABI-derlenmedi"
print("  Web3-client: gerçek-web3 + ERC-8004-ABI-derlendi (eager-RPC-yok; "
      "canlı-ağ-gerektirmez)")

# --- 5) DİKİŞ: ERC-8004-keccak-özütü → RFC-010-x402/v1-GREEN ( GERÇEK-ecrecover)
BUY = ek.PrivateKey(os.urandom(32))
ADDR = to_checksum_address(BUY.public_key.to_address())
KANIT = CERT.hex()                            # on-chain-kayıt-özütü ( keccak-256)
govde = {"buyerAddress": ADDR, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "VRD-CERT-128",
         "evidenceHash": {"alg": "keccak256", "hex": KANIT}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = "0x" + BUY.sign_msg_hash(bytes.fromhex(d)).to_bytes().hex()
assert len(sig) == 132  # 0x + 130-hex ( r+s+v)
claim = dict(govde); claim["signature"] = sig
charge = {"seq": 128, "prev": "0" * 64, "h": "e" * 64,
          "delivery_hash": {"alg": "keccak256", "hex": KANIT},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "VRD-CERT-128",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": ADDR, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": KANIT,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "veridrome.contracts.client."
                                                "InMemoryVeridromeRegistryClient"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"ERC-8004-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-ecrecover-imzası-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-zincir-geçmedi"
print("  ERC-8004-keccak-özütü → RFC-010-x402/v1-GREEN (gerçek-ecrecover; "
      "§6-zincir-head=certId)")

# --- 6) NEG-1: sahte-imza → RED rc4
for sahte in ("ff" * 33, os.urandom(65).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
print("  sahte-imza (geçersiz-uzunluk + rastgele-65-byte) → RED rc4")

# --- 7) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "keccak256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
s2 = "0x" + BUY.sign_msg_hash(bytes.fromhex(d2)).to_bytes().hex()
c2 = dict(govde2); c2["signature"] = s2
r2 = SB.verify(charge, c2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r2}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")

# --- 8) DÜRÜST-BULGU: erc8004/v1-scheme-adayının-GERÇEK-yolu → RED rc4
# _claim_signer-erc8004/v1: keccak256(bytes.fromhex(digest))-BYTES-döndürür; verify()
# str-buyerAddress-ile-karşılaştırır → bytes≠str-asla-eşleşmez. AT-065-bunu-test-
# double-lambda-ile-aştı; double-YASAK-olduğu-için-biz-gerçek-davranışı-ölçeriz:
# scheme-adayı-doğal-olsa-da-gerçek-yoldan-GREEN-veremez ( fail-closed-rc4).
govdeE = {"buyerAddress": keccak256(bytes.fromhex(d)).hex(),   # kök-hex (mantıklı-buyer)
          "sellerAddress": "0x" + "2" * 40,
          "settlementRef": "VRD-ERC-128",
          "evidenceHash": {"alg": "sha256", "hex": "c" * 64}}
dE = hashlib.sha256(json.dumps(govdeE, sort_keys=True).encode()).hexdigest()
chargeE = {"seq": 129, "prev": "0" * 64, "h": "e" * 64,
           "delivery_hash": {"alg": "sha256", "hex": "c" * 64},
           "settlement_bind": {"scheme": "erc8004/v1", "payment_id": "VRD-ERC-128",
                               "claim_evidence_hash": {"alg": "sha256", "hex": "c" * 64},
                               "payer": govdeE["buyerAddress"],
                               "payee": "0x" + "2" * 40,
                               "verified_at": "2026-09-22T00:00:00Z"}}
claimE = dict(govdeE); claimE["signature"] = govdeE["buyerAddress"]  # sembolik-imza
rE = SB.verify(chargeE, claimE)
assert rE["verdict"] == "RED" and rE["reason_code"] == 4, \
    f"erc8004/v1-gerçek-yol-RED-rc4-beklendi (bytes/str): {rE}"
print("  DÜRÜST-BULGU: erc8004/v1-gerçek-_claim_signer-bytes→str-uyumsuz → "
      "RED rc4 (double-YOK; AT-065'in-lambda-bypass'ı-kullanılmadı)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: sekiz-Veridrome-contracts-ERC-8004-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-128: Veridrome dördüncü-yüz (contracts ERC-8004) → RFC-010"
[[ $FAIL -eq 0 ]]
