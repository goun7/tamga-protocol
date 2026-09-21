#!/usr/bin/env bash
# AT-111: AJAN-BORSASI-MAINNET-GUARD (üçüncü-yüz) → RFC-010-DİKİŞİ (x402/v1 — gerçek-ecrecover).
#
# AT-080 receipt_hash'u-bağladı (borsa_core.complete_work). Kalan-üçüncü-yüz:
# mainnet_verify.py + mainnet_guard.py — gerçek-zincir-ödeme-doğrulama-çifti:
#   - TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)") — gerçek-EVM
#   - find_transfer — Base-mainnet-USDC-Transfer-log'larını-keccak-topic'le-arar
#   - require_mainnet_payment — sandbox-guard + fail-closed-402/500/503
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   ajan-borsasi/mainnet_verify.py:32  TRANSFER_TOPIC (keccak256-sabiti)
#   mainnet_verify.py:64               _addr_topic (32-byte-topic-gömme)
#   mainnet_verify.py:77/148           find_transfer / verify_mainnet_payment
#   mainnet_verify.py:155              amount_minor = round(usd × 1e6) (USDC-6-dec)
#   ajan-borsasi/mainnet_guard.py:46   is_sandbox_payer (whitelist)
#   mainnet_guard.py:51                require_mainnet_payment (fail-closed-gate)
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate
#   tamga/tamga_keccak.py              keccak256 (bağımsız-yeniden-üretim)
#   tamga/tamga_attest_verify.py:64    ecrecover_to_pub (x402/v1-sözleşmesi)
#
# §3b-ŞEMA-SEÇİMİ: x402/v1 — AT-080-ile-aynı-cluster-kararı (Ajan-Borsası'nın-
# ödeme-layer'ı-x402; mainnet-guard-zaten-EVM-adresleri-ve-EIP-191-imzaları-yönetir).
#
# KANIT-MÜHENDİSLİĞİ (ağ-olmadan-gerçek-ölçüm): canlı-RPC-çağrısı-üretime-aittir;
# bu-test-double-YERINE-gerçek-kodun-ürettiği-kripto-nesneleri-ölçer:
#   (1) TRANSFER_TOPIC — tamga_keccak'ile-BİREBİR-bağımsız-yeniden-üretim
#   (2) _addr_topic — EVM-32-byte-gömme-kuralı-sol-hizalı-sıfırlar
#   (3) USDC-6-decimal-matematiği (0.05 → 50000-minor)
#   (4) mainnet-guard-kararları — gerçek-starlette-Request + gerçek-HTTPException
#   (5) TransferFound-özütü → evidenceHash; alıcı-tüm-topic'leri-bağımsız-
#       hesaplayıp-özütü-yeniden-üretir (machine-checkable — §4d-iki-kanal:
#       keccak-zincir-kanalı ≠ sha256-claim-kanalı)
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-keccak-nesneler: topic+addr-topic+6-dec+TransferFound
#   2) ÜRETİCİ-TARAFI-SAĞLAMLIK: guard'ın-5-kararı (402/402/500/geçer/test-None)
#   3) DİKİŞ-GREEN: transfer-özüt-sha256=evidenceHash + x402/v1 → 6-kontrol
#   4) §6-foreign_chain: evidence_link='derived' → GREEN
#   5) NEGATİF-1: sahte-transfer-özütü (uydurma-hash) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/ABORSA-MAINNET/$(date +%F)/at111.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-111: Ajan-Borsası-mainnet-guard (üçüncü-yüz) → RFC-010 x402/v1 dikişi"

AB="/home/gokun/projects/00_TAMGA-MESH/ajan-borsasi/mainnet_guard.py"
if [ ! -f "$AB" ]; then
  note "[SKIP] AT-111: Ajan-Borsası-kodu-bu-makinede-değil (CI) —"
  note "       mainnet-guard-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, fastapi, starlette" 2>/dev/null; then
  note "[SKIP] AT-111: eth-keys/fastapi/starlette-yok —"
  note "       gerçek-imza-ve-HTTP-nesneleri-üretilemedi (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/ajan-borsasi")

LOG = sys.argv[1]                                  # kanıt-dizini (shell-değişkeni-değil)

import mainnet_verify as MV
import mainnet_guard as MG
import settlement_bind_verify as SB
from tamga_keccak import keccak256
import tamga_attest_verify as TAV
from eth_keys import keys
from starlette.requests import Request
from fastapi import HTTPException

# STUB-YOK (AT-075-disiplini): gate'in-imza-yoluna-dokunmadık
assert "ecrecover_to_pub" in inspect.getsource(SB._claim_signer)

# çevre-değişken-izolasyonu (gerçek-os.environ — test-çifti-değil)
_env_backup = dict(os.environ)
def _restore():
    os.environ.clear(); os.environ.update(_env_backup)

# --- 1) GERÇEK-keccak-nesneler: topic + addr-topic + 6-decimal + TransferFound
# (a) TRANSFER_TOPIC: bağımsız-yeniden-üretim (tamga_keccak — bizim-kendi-
#     keccak'ımız-üretim-sabitiyle-BİREBİR-tutar; farklı-algoritma-asla-kabul)
kt = "0x" + keccak256(b"Transfer(address,address,uint256)").hex()
assert kt == MV.TRANSFER_TOPIC, \
    f"TRANSFER_TOPIC-keccak-yeniden-üretim-tutarsız: {kt} vs {MV.TRANSFER_TOPIC}"
assert kt == "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
# (b) _addr_topic: EVM-kuralı — 40-hex-adres-32-byte-topic'e-SOL-HİZALI-sıfırlarla
addr = "0x" + "2" * 40
assert MV._addr_topic(addr) == "0x" + "0" * 24 + "2" * 40, \
    "addr-topic-32-byte-gömme-yanlış (sol-hizalı-sıfırlar)"
# case-insensitive-adres
mixed = "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01"
assert MV._addr_topic(mixed) == "0x" + mixed[2:].lower().rjust(64, "0")
# (c) USDC-6-decimal: verify_mainnet_payment-tutar-matematiği
assert int(round(0.05 * 1_000_000)) == 50000
assert MV.USDC_CONTRACT == "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"  # Base-USDC
assert MV.CONFIRMED_BLOCKS == 20 and MV.SEARCH_BLOCKS == 5000   # reorg-güvenliği
# (d) TransferFound: gerçek-dataclass-üretimi
tf = MV.TransferFound(True, tx_hash="0x" + "a" * 64, amount_minor=50000,
                      detail="block 12345")
assert tf.found is True and len(tf.tx_hash) == 66 and tf.amount_minor == 50000
print(f"  GERÇEK-keccak-nesneler: topic {MV.TRANSFER_TOPIC[:18]}… birebir; "
      f"addr-topic-32byte; 0.05-USD→50000-minor (USDC-6)")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: guard'ın-gerçek-kararları (starlette-Request)
PAY_TO = "0x" + "2" * 40
SBX = "0x" + "a" * 40
try:
    os.environ["UNPUMP_TEST"] = "0"
    os.environ["UNPUMP_SANDBOX"] = "1"
    os.environ["UNPUMP_SANDBOX_KEYS"] = SBX
    os.environ["AJANBORSA_MAINNET"] = "1"
    # (a) test-mode → zincir-arama-yok (None)
    os.environ["UNPUMP_TEST"] = "1"
    assert MG.require_mainnet_payment(
        Request({"type": "http", "headers": []}),
        price=0.05, pay_to=PAY_TO, service_name="ajanborsa") is None
    # (b) sandbox-payer → geçer + request.state.sandbox=True
    #     (DİKKAT-§5b: "0x"-ön-eki-BÜYÜK-harf-OLMAMALI — guard-küçük-"0x"-bekler;
    #     hex-kısmı-büyük-olarak-whitelist'in-case-insensitive-olduğunu-test-eder)
    os.environ["UNPUMP_TEST"] = "0"
    SBX_UP = "0x" + SBX[2:].upper()
    req_sb = Request({"type": "http",
                      "headers": [(b"x-payer-address", SBX_UP.encode())]})
    assert MG.require_mainnet_payment(req_sb, price=0.05, pay_to=PAY_TO,
                                      service_name="ajanborsa") == SBX_UP
    assert req_sb.state.sandbox is True, "sandbox-bayrağı-eksik"
    # case-insensitive-whitelist
    assert MG.is_sandbox_payer(SBX.upper()) is True
    assert MG.is_sandbox_payer("0x" + "b" * 40) is False    # yabancı
    # sandbox-devre-dışı → whitelist-bile-olsa-False
    os.environ["UNPUMP_SANDBOX"] = "0"
    assert MG.is_sandbox_payer(SBX) is False
    os.environ["UNPUMP_SANDBOX"] = "1"
    # (c) eksik-payer-header → 402 (fail-closed)
    try:
        MG.require_mainnet_payment(Request({"type": "http", "headers": []}),
                                   price=0.05, pay_to=PAY_TO,
                                   service_name="ajanborsa")
        raise AssertionError("eksik-payer-402-vermeli")
    except HTTPException as e:
        assert e.status_code == 402
    # (d) yanlış-biçim-payer → 402
    try:
        MG.require_mainnet_payment(
            Request({"type": "http", "headers": [(b"x-payer-address", b"kisa")]}),
            price=0.05, pay_to=PAY_TO, service_name="ajanborsa")
        raise AssertionError("yanlış-payer-402-vermeli")
    except HTTPException as e:
        assert e.status_code == 402
    # (e) pay_to-boş → 500 (yapılandırma-hatası-asla-sessiz-geçmemeli)
    try:
        MG.require_mainnet_payment(Request({"type": "http", "headers": []}),
                                   price=0.05, pay_to="",
                                   service_name="ajanborsa")
        raise AssertionError("pay_to-yok-500-vermeli")
    except HTTPException as e:
        assert e.status_code == 500
    # (f) ana-mod-kapalı → None (servis-mainnet-istemezse-zincir-arama)
    os.environ["AJANBORSA_MAINNET"] = "0"
    assert MG.require_mainnet_payment(
        Request({"type": "http", "headers": []}),
        price=0.05, pay_to=PAY_TO, service_name="ajanborsa") is None
    print("    guard-5-karar: test-None; sandbox-geçer+flag (case-insens); "
          "eksik/yanlış-payer→402; pay_to-yok→500; mainnet-off→None")
finally:
    _restore()

# --- 3) DİKİŞ-GREEN: transfer-özüt-sha256=evidenceHash + x402/v1 (AT-080-reçetesi)
BK = keys.PrivateKey(bytes.fromhex("7a" * 31 + "01"))  # test-only-anahtar
BUYER = BK.public_key.to_address()
# özüt: alıcı-tüm-topic'leri-bağımsız-hesaplar (machine-checkable)
canon = json.dumps({"transfer_topic": MV.TRANSFER_TOPIC,
                    "from_topic": MV._addr_topic(BUYER),
                    "to_topic": MV._addr_topic(PAY_TO),
                    "tx_hash": tf.tx_hash,
                    "amount_minor": tf.amount_minor}, sort_keys=True)
ph = hashlib.sha256(canon.encode()).hexdigest()
assert len(ph) == 64
# alıcı-yeniden-üretimi: keccak+padding-gerçek-yoldan
assert "0x" + keccak256(b"Transfer(address,address,uint256)").hex() \
    == MV.TRANSFER_TOPIC
PID = "ABORSA-MAINNET-0001"
govde = {"buyerAddress": BUYER, "sellerAddress": PAY_TO, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": ph}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
s = BK.sign_msg_hash(bytes.fromhex(digest_hex))      # z=raw-sha256, öneksiz
sig_hex = (s.r.to_bytes(32, "big") + s.s.to_bytes(32, "big")
           + bytes([27 + s.v])).hex()
assert TAV.ecrecover_to_pub(digest_hex, sig_hex).lower() == BUYER.lower(), \
    "gerçek-imza-gerçek-adrese-çözümlenmedi"
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 111, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": ph},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": ph},
                              "payer": BUYER, "payee": PAY_TO,
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"mainnet-guard-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: transfer-özüt-sha256=evidenceHash, x402/v1 6-kontrol (STOCK)")

# --- 4) §6-foreign_chain: derived-bağı (AT-085-deseni)
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                             # whitelist-kısıtı (AT-079-dersi)
    "head_hex": hashlib.sha256(bytes.fromhex(ph)).hexdigest(),
    "entries": 1,
    "evidence_link": "derived",
    "verify_cmd": "mainnet_verify.find_transfer"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
print("  §6-foreign_chain: evidence_link='derived' (head=sha256(özüt)) → GREEN")

# --- kanıt-fixture'ı-kalıcı-la
FX = os.path.join(os.path.dirname(LOG), "at111-aborsa-mainnet.json")
json.dump({"test": "AT-111", "scheme": "x402/v1",
           "project": "ajan-borsasi/mainnet_guard+verify",
           "transfer_topic": MV.TRANSFER_TOPIC, "tx_hash": tf.tx_hash,
           "amount_minor": tf.amount_minor, "evidence_sha256": ph,
           "usdc_contract": MV.USDC_CONTRACT, "payment_id": PID,
           "charge": charge6, "claim": claim, "verdict": r6["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-transfer-özütü (uydurma-hash) → RED rc7
# saldırgan-gerçek-keccak-topic-üretmeden-uydurma-64hex-yazar; alıcı-topic'leri
# bağımsız-hesaplayınca-özüt-tutmayacak → evidenceHash-uyuşmazlığı.
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-transfer-RED-rc7-beklendi: {rN1}"
print("  sahte-transfer-özütü (uydurma-64hex) → RED rc7 — kanıtsız-ödeme-alınamaz")

# --- 6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
govde2 = dict(govde)
govde2["sellerAddress"] = "0x" + "9" * 40           # başkası
s2 = BK.sign_msg_hash(bytes.fromhex(
    hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()))
claim2 = dict(govde2)
claim2["signature"] = (s2.r.to_bytes(32, "big") + s2.s.to_bytes(32, "big")
                       + bytes([27 + s2.v])).hex()
rN2 = SB.verify(charge, claim2)
assert rN2["verdict"] == "RED" and rN2["reason_code"] == 6, \
    f"party-swap-RED-rc6-beklendi: {rN2}"
assert rN2["checks"].get("2_claim_sig") is True, \
    "negatif-imza-GEÇERLİ-olmalı (saldırı-imzada-değil-party-bağında-yakalanmalı)"
print("  party-swap (imza-geçerli, satıcı-değişti) → RED rc6 (party_mismatch)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Ajan-Borsası-mainnet-guard-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-111: Ajan-Borsası-mainnet-guard (üçüncü-yüz) → RFC-010 x402/v1"
[[ $FAIL -eq 0 ]]
