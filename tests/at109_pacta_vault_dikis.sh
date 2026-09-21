#!/usr/bin/env bash
# AT-109: PACTA-ESCROW-VAULT (üçüncü-yüz) → RFC-010-DİKİŞİ (x402/v1 — gerçek-ecrecover).
#
# Pacta'nın-iki-yüzü-bağlandı (AT-073-RFC-011-dispute-pointer, AT-084-canlı-hakemlik).
# Kalan-üçüncü-yüz: core/vault.py — non-custodial-escrow-vault:
#   - settle_escrow:169 — EIP-1559-tx-hash'i-gerçek-Web3.keccak-ile-üretir
#   - check_solvency_invariant:63 — fail-closed-InvariantViolationError
#   - core/fsm.py:18 — EscrowFSM — resmi-geçiş-tablosu (delivery-vs-payment)
#   - models.py:131/137 — calculate_fee/net_seller_amount (75-bps — AT-084-ekonomisi)
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   pacta/core/vault.py:97    create_and_lock_escrow — fon-kilidi+solvency
#   pacta/core/vault.py:169   settle_escrow — tx-hash+fee+net+ledger
#   pacta/core/vault.py:63    check_solvency_invariant — DÜZ/İKİLİ-invariant
#   pacta/core/vault.py:193   EIP-1559-raw-tx → Web3.keccak (gerçek-keccak256)
#   pacta/core/fsm.py:18     EscrowFSM.ALLOWED_TRANSITIONS (formal-lifecycle)
#   pacta/models.py:131/137  calculate_fee (75-bps) / net_seller_amount
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate
#   tamga/tamga_attest_verify.py:64   ecrecover_to_pub (x402/v1-sözleşmesi)
#
# §3b-ŞEMA-SEÇİMİ: x402/v1 — AT-080/084/085/090-cluster-kararı (gerçek-EIP-191-
# secp256k1; Pacta-zaten-Base-L2-EVM-escrow — adresler-doğal-EVM).
#
# EVIDENCEHASH-TASARIMI (önemli-mühendislik-kararı): tx-hash-ZAMAN-damgalıdır
# (raw-tx: job_id‖settled_at_ms‖net) → alıcı-tx'i-BAĞIMSIZ-YENİDEN-ÜRETEMEZ.
# Bu-yüzden-evidenceHash = sha256(canonical-özüt{job_id,tx,fee,net}) — alıcı-
# özütü-vault'tan-alıp-yeniden-hesaplar. Tx-hash-özütün-İÇİNDE-kanıttır; ayrıca
# üretici-tarafında-raw-tx'i-yeniden-kurup-Web3.keccak-ile-birebir-tutar (§4d-
# iki-kanal-notu: keccak-tx-kanalı ≠ sha256-claim-kanalı).
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-vault: lock→submit→verify→settle → tx-hash + fee 0.75/net 99.25
#   2) ÜRETİCİ-TARAFI-SAĞLAMLIK: tx=gerçek-keccak-yeniden-üretim + solvency-fail-closed + FSM
#   3) DİKİŞ-GREEN: özüt-sha256=evidenceHash + x402/v1 → 6-kontrol (STOCK)
#   4) §6-foreign_chain: evidence_link='derived' (AT-085-deseni) → GREEN
#   5) NEGATİF-1: sahte-vault-özütü (uydurma-hash) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/PACTA-VAULT/$(date +%F)/at109.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-109: Pacta-escrow-vault (üçüncü-yüz) → RFC-010 x402/v1 dikişi"

PV="/home/gokun/projects/00_TAMGA-MESH/pacta/pacta/core/vault.py"
if [ ! -f "$PV" ]; then
  note "[SKIP] AT-109: Pacta-kodu-bu-makinede-değil (CI) —"
  note "       vault-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, web3" 2>/dev/null; then
  note "[SKIP] AT-109: eth-keys-veya-web3-yok —"
  note "       gerçek-keccak/imza-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")

LOG = sys.argv[1]                                  # kanıt-dizini (shell-değişkeni-değil)

from decimal import Decimal
from web3 import Web3

from pacta.core.vault import (PactaEscrowVault, InvariantViolationError,
                             EscrowNotFoundError)
from pacta.core.fsm import EscrowFSM, InvalidStateTransitionError
from pacta.models import EscrowStatus
import settlement_bind_verify as SB
import tamga_attest_verify as TAV
from eth_keys import keys

# STUB-YOK (AT-075-disiplini): gate'in-imza-yoluna-dokunmadık
assert "ecrecover_to_pub" in inspect.getsource(SB._claim_signer)

# --- 1) GERÇEK-vault: tam-lifecycle → tx-hash + fee + net (AT-084-ekonomisi)
vault = PactaEscrowVault()
BK = keys.PrivateKey(bytes.fromhex("7a" * 31 + "01"))  # test-only-anahtar
BUYER = BK.public_key.to_address()
SELLER = "0x" + "2" * 40
job = vault.create_and_lock_escrow(BUYER, SELLER, 100.0)
assert job.status == EscrowStatus.ESCROW_LOCKED
assert vault.check_solvency_invariant() is True       # kilit sonrası sağlam
job = vault.submit_output(job.job_id, {"result": "scraped-42", "rows": 51})
job = vault.mark_verified_ok(job.job_id)
job, tx_hash = vault.settle_escrow(job.job_id)
# tx-hash: gerçek-EIP-1559-biçimi (0x+64hex-keccak)
assert tx_hash.startswith("0x") and len(tx_hash) == 66
assert job.status == EscrowStatus.SETTLED              # terminal-durum
# AT-084-ile-birebir-aynı-ekonomi (75-bps-fee): 100 → fee 0.75 / net 99.25
assert job.fee_collected_usdc == Decimal("0.750000")
assert job.net_seller_amount() == Decimal("99.250000")
assert vault.total_protocol_revenue_usdc == Decimal("0.750000")
# solvency-settle-sonrası-da-sağlam (vault-tutarsız-bırakmadı)
assert vault.check_solvency_invariant() is True
print(f"  GERÇEK-vault: 100-USD → tx {tx_hash[:20]}… | fee {job.fee_collected_usdc}"
      f" / net {job.net_seller_amount()}")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: keccak-yeniden-üretim + solvency + FSM
# (a) tx-hash-gerçek-keccak: raw-tx'i-bağımsız-yeniden-kur-ve-karşılaştır
raw_tx_bytes = (f"BaseL2:PactaVault:{job.job_id}:{job.settled_at_epoch_ms}"
                f":{job.net_seller_amount()}").encode()
assert Web3.to_hex(Web3.keccak(raw_tx_bytes)) == tx_hash, \
    "tx-hash-gerçek-keccak256-değil (bağımsız-yeniden-üretim-tutarsız)"
# (b) solvency-fail-closed:ledger'i-çalınmış-hale-getir → ihlal-tespit
vault.ledger_balances[PactaEscrowVault.USDC_TOKEN] -= Decimal("50.0")
try:
    vault.check_solvency_invariant()
    raise AssertionError("solvency-ihlali-tespit-edilmeli")
except InvariantViolationError:
    pass
vault.ledger_balances[PactaEscrowVault.USDC_TOKEN] += Decimal("50.0")  # geri-al
# (c) FSM-formal-geçişler: terminal-durumdan-geçiş-izinsiz
try:
    EscrowFSM.transition(EscrowStatus.SETTLED, EscrowStatus.ESCROW_LOCKED)
    raise AssertionError("terminal-durumdan-geçiş-reddedilmeli")
except InvalidStateTransitionError:
    pass
assert EscrowFSM.can_transition(EscrowStatus.ESCROW_LOCKED,
                                EscrowStatus.OUTPUT_SUBMITTED) is True
# (d) eksik-job: fail-closed-bulunamadı
try:
    vault.refund_timeout("olmayan-job")
    raise AssertionError("olmayan-job-reddedilmeli")
except EscrowNotFoundError:
    pass
print("    üretici-tarafı: tx=gerçek-keccak-yeniden-üretim; solvency-ihlali-"
      "InvariantViolationError; terminal-geçiş-InvalidStateTransitionError")

# --- 3) DİKİŞ-GREEN: özüt-sha256=evidenceHash + x402/v1 (AT-080-reçetesi)
# tx-ZAMAN-damgalı-olduğu-için-özüt-üzerinden-bağlarız (machine-checkable)
canon = json.dumps({"job_id": job.job_id, "tx": tx_hash,
                    "fee": str(job.fee_collected_usdc),
                    "net": str(job.net_seller_amount())}, sort_keys=True)
ph = hashlib.sha256(canon.encode()).hexdigest()
assert len(ph) == 64
PID = f"PACTA-ESCROW-{job.job_id[:8]}"
govde = {"buyerAddress": BUYER, "sellerAddress": SELLER, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": ph}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
s = BK.sign_msg_hash(bytes.fromhex(digest_hex))      # z=raw-sha256, öneksiz
sig_hex = (s.r.to_bytes(32, "big") + s.s.to_bytes(32, "big")
           + bytes([27 + s.v])).hex()
assert TAV.ecrecover_to_pub(digest_hex, sig_hex).lower() == BUYER.lower(), \
    "gerçek-imza-gerçek-adrese-çözümlenmedi"
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 109, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": ph},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": ph},
                              "payer": BUYER, "payee": SELLER,
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"vault-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: vault-özüt-sha256=evidenceHash, x402/v1 6-kontrol (STOCK-ecrecover)")

# --- 4) §6-foreign_chain: derived-bağı (AT-085-deseni — tx keccak≠sha256
# olduğu-için-head=tx-olamaz; derived: head=sha256(receipt-baytları))
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                             # whitelist-kısıtı (AT-079-dersi)
    "head_hex": hashlib.sha256(bytes.fromhex(ph)).hexdigest(),
    "entries": 1,
    "evidence_link": "derived",
    "verify_cmd": "pacta.core.vault.settle_escrow"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
print("  §6-foreign_chain: evidence_link='derived' (head=sha256(özüt)) → GREEN")

# --- kanıt-fixture'ı-kalıcı la
FX = os.path.join(os.path.dirname(LOG), "at109-pacta-vault.json")
json.dump({"test": "AT-109", "scheme": "x402/v1", "project": "pacta/core/vault",
           "job_id": job.job_id, "settlement_tx": tx_hash,
           "fee_usdc": str(job.fee_collected_usdc),
           "net_seller_usdc": str(job.net_seller_amount()),
           "evidence_sha256": ph, "payment_id": PID,
           "charge": charge6, "claim": claim, "verdict": r6["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-vault-özütü (uydurma-hash) → RED rc7
# saldırgan-gerçek-vault-settle-üretmeden-uydurma-64hex-yazar; alıcı-özütü
# yeniden-hesaplayınca-tutmaz → evidenceHash-uyuşmazlığı.
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-vault-RED-rc7-beklendi: {rN1}"
print("  sahte-vault-özütü (uydurma-64hex) → RED rc7 — kanıtsız-ödeme-alınamaz")

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
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Pacta-vault-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-109: Pacta-escrow-vault (üçüncü-yüz) → RFC-010 x402/v1"
[[ $FAIL -eq 0 ]]
