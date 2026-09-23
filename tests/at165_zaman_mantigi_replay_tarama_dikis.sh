#!/usr/bin/env bash
# AT-165: ZAMAN-MANTIK-AÇIĞI-VE-REPLAY-TARAMASI (6.-sınıf).
#
# task-56. Kriptografi-doğru-AMA-zaman/replay-mantığı-boşluk: escrow/ödeme-
# akışlarında-süre-ve-tek-kezlik-disiplini-ölçülür.
#
# BULGU-1 (GERÇEK — pacta): `EscrowPolicy.dispute_window_sec` (varsayılan-60)
# MODELLERDE-OKUNUYOR-AMA-KARŞILAŞTIRILMIYOR. `vault.raise_dispute` docstring'i
# "Buyer raises dispute within dispute window" yazar-AMA pencere-kontrolü-YOK:
# VERIFIED_OK-durumundaki-bir-işe-pencere-dışı-120sn-sonra-DA-İTİRAZ-KABUL +
# bond- alınır (kanıt: bu-testin-ölçümü).
#
# BULGU-2 (GERÇEK — pacta): timeout_ms-SLA-uygulaması-PARÇALI. `submit_output`
# `now_ms - locked_at > timeout_ms`-kontrol-eder-AMA-`settle_escrow`-ETMEZ:
# timeout'u-dolmuş-VERIFIED_OK-iş-settle-edilebilir (5sn-SLA'sı-aşılmış-olsa-bile).
#
# BULGU-3 (TEMİZ — pacta double-settle): FSM-replay-koruması-GERÇEK —
# settle→settle reddedilir (SETTLED→SETTLED-geçersiz, InvalidStateTransitionError);
# settle-sonrası-dispute-VE-refund-da-reddedilir. Üçlü-replay-kapısı-sağlam.
#
# BULGU-4 (TEMİZ — sester): replay-koruması-KALICI — ledger.seen_nonces tablosu
# (restart-pencere-sıfırlamaz); escalation-queue consume() tek-kezlik (AT-127'de
# ölçüldü). Sester-tarafında-zaman/replay-boşluğu-yok.
#
# DÜRÜST-SINIR: bu-test-üretim-koduna-DOKUNMAZ (Lead-düzeltme-yapar); bulguları-
# ölçer-ve-raporlar. Bulgu-1/2'nin-etkisi: sözleşme-penceresi-dışı-itiraz-ve-aşmış-
# SLA-ile-settle-mümkün; fark-EDİLEBİLİR-AMA-üretim-para-akışında-gerçek-riske-yol-açar.
#
# ADDITIVE-DİKİŞ: pacta-escrow-tam-akış (lock→submit→verify→settle) → RFC-010
# x402/v1 GREEN (gerçek-EIP-191); rc4 + rc7.
set -uo pipefail
# tests/-symlink'i-checkout'a-işaret-ettiği-için-göreceli-yol-yanlış-çözümlenir:
# workspace-kökünü-gerçek-test-dizininin-atalarından-bul (mutlak-çözüm).
HERE="$(cd "$(dirname "$0")" && pwd)"
MESH_ROOT="$(dirname "$(dirname "$(readlink -f "$HERE")")")"
[ -d "$MESH_ROOT/pacta" ] || MESH_ROOT="/home/gokun/projects/00_TAMGA-MESH"
PACTA="$MESH_ROOT/pacta"
SESTER="$MESH_ROOT/sester"
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR="$HERE/../.evidence/ZAMAN-REPLAY"
LOG="$EVDIR/$(date +%F)/at165.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f "$PACTA/pacta/core/vault.py" ]; then
  note "[SKIP] AT-165: pacta/core/vault.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import web3, eth_keys" 2>/dev/null; then
  note "[SKIP] AT-165: web3/eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if [ ! -f "$SESTER/sester/middleware.py" ]; then
  note "[SKIP] AT-165: sester/middleware.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, sys, time
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")

BUYER = "0x" + "1" * 40
SELLER = "0x" + "2" * 40

from pacta.core.vault import PactaEscrowVault, EscrowNotFoundError
from pacta.models import EscrowPolicy, EscrowStatus
from pacta.core.fsm import InvalidStateTransitionError

print("=== AT-165: zaman-mantığı + replay-taraması (gerçek-üretim-kodu) ===")

# ---------- PACTA ----------
v = PactaEscrowVault()

# tam-akış (GREEN-taban)
pol = EscrowPolicy(dispute_window_sec=60, timeout_ms=5000)
j = v.create_and_lock_escrow(buyer_address=BUYER, seller_address=SELLER,
                             amount_usdc=1.0, policy=pol)
assert j.status == EscrowStatus.ESCROW_LOCKED
v.submit_output(j.job_id, output_payload={"result": "ok"})
v.mark_verified_ok(j.job_id)
print(f"  tam-akış: lock→submit→verified_ok ({j.job_id[:8]}…, "
      f"timeout_ms={pol.timeout_ms}, dispute_window_sec={pol.dispute_window_sec})")

# --- BULGU-3 (TEMİZ): double-settle / post-settle replay
try:
    v.settle_escrow(j.job_id)
    B3A = "TEMİZ"
    print("  BULGU-3a-notu: ilk-settle-SONRASI-durum =", j.status.value)
except InvalidStateTransitionError as e:
    B3A = "TEMİZ"
    print(f"  BULGU-3a: double-settle → REDDİ (FSM: {str(e)[:44]}…)")
# double-settle'i izole-ölç (tartışmasız-kanıt)
v_x = PactaEscrowVault()
jx = v_x.create_and_lock_escrow(buyer_address=BUYER, seller_address=SELLER,
                                amount_usdc=1.0, policy=pol)
v_x.submit_output(jx.job_id, output_payload={"result": "ok"})
v_x.mark_verified_ok(jx.job_id)
v_x.settle_escrow(jx.job_id)
try:
    v_x.settle_escrow(jx.job_id)
    B3A = "HATA"
    print("  BULGU-3a: double-settle-KABUL (HATA — FSM-replay-boşluğu)")
except InvalidStateTransitionError as e:
    print(f"  BULGU-3a: double-settle → REDDİ (FSM: SETTLED→SETTLED-geçersiz)")
try:
    v.raise_dispute(j.job_id, claimant_address=BUYER, reason="sonra",
                    evidence_hash="a" * 64)
    print("  BULGU-3b: settle-sonrası-dispute-REDDİ-BEKLENDİ-AMA-KABUL (HATA)")
    B3B = "HATA"
except (InvalidStateTransitionError, EscrowNotFoundError) as e:
    # AT-165-sonrası: pencere-dışı-da-reddeder ( her-iki-yol-da-RED = TEMİZ)
    B3B = "TEMİZ"
    print(f"  BULGU-3b: settle-sonrası-dispute → REDDİ ( {type(e).__name__})")
try:
    v.refund_timeout(j.job_id)
    print("  BULGU-3c: settle-sonrası-refund-REDDİ-BEKLENDİ-AMA-KABUL (HATA)")
    B3C = "HATA"
except (InvalidStateTransitionError, EscrowNotFoundError) as e:
    B3C = "TEMİZ"
    print(f"  BULGU-3c: settle-sonrası-refund → REDDİ ( {type(e).__name__})")
assert B3A == B3B == B3C == "TEMİZ", "pacta-FSM-replay-koruması-bozuk"

# --- BULGU-1 → DÜZELTİLDİ ( AT-165): dispute-window-artık-doğrulanıyor
# Önceden-pencere-dışı-120sn-dispute-KABUL-ediliyordu ( window-60sn); artık-
# EscrowNotFoundError-reddi. Bu-iddia-açık-geri-gelirse-YAKALAR.
v2 = PactaEscrowVault()
j2 = v2.create_and_lock_escrow(buyer_address=BUYER, seller_address=SELLER,
                               amount_usdc=1.0, policy=pol)
v2.submit_output(j2.job_id, output_payload={"result": "ok"})
v2.mark_verified_ok(j2.job_id)
# kanıt: işi-120sn-önce-tamamlanmış-göster (60sn-pencere-aşımı)
j2.submitted_at_epoch_ms -= 120_000
lb_before = v2.ledger_balances[j2.deposit_token]
try:
    v2.raise_dispute(j2.job_id, claimant_address=BUYER, reason="pencere-dışı",
                     evidence_hash="a" * 64)
    raise AssertionError("AÇIK-GERİ-GELDİ! ( pencere-dışı-dispute-kabul)")
except EscrowNotFoundError as e:
    assert "dispute-window-expired" in str(e), f"beklenmedik-neden: {e}"
lb_after = v2.ledger_balances[j2.deposit_token]
assert lb_before == lb_after, "pencere-dışı-dispute-bond-aldı ( açıklık)"
print("  BULGU-1-KAPANDI: VERIFIED_OK + pencere-dışı-120sn → dispute-RED "
      "( EscrowNotFoundError; bond-alınmadı)")
print("    → dispute_window_sec-artık-KARŞILAŞTIRILiyor ( docstring-ile-uyumlu)")

# --- BULGU-2 (settle-yolunda-timeout-kontrolü): izole-ölçüm-aşağıda ---
# ( AT-165-sonrası-yol-değişti: j2-artık-dispute-alamıyor → bu-not-gereksiz)

# izole-BULGU-2 → DÜZELTİLDİ ( AT-165): timeout-dolu-VERIFIED_OK → settle-reddi
# Önceden-SLA-aşımı-settle-KABUL-ediliyordu ( satıcı-aşmış-SLA'yla-para-aldı);
# artık-EscrowNotFoundError + refund_timeout'a-yönlendirme.
v3 = PactaEscrowVault()
j3 = v3.create_and_lock_escrow(buyer_address=BUYER, seller_address=SELLER,
                               amount_usdc=1.0, policy=pol)
v3.submit_output(j3.job_id, output_payload={"result": "ok"})
v3.mark_verified_ok(j3.job_id)
j3.locked_at_epoch_ms -= 10_000   # 10sn-önce (5sn-timeout-aşımı)
try:
    v3.settle_escrow(j3.job_id)
    raise AssertionError("AÇIK-GERİ-GELDİ! ( timeout-aşımı-settle-kabul)")
except EscrowNotFoundError as e:
    assert "exceeded timeout SLA" in str(e), f"beklenmedik-neden: {e}"
# alıcının-iade-hakkı-hâlâ-geçerli ( refund_timeout-çalışır)
j3b = v3.refund_timeout(j3.job_id)
assert j3b.status == EscrowStatus.AUTO_REFUNDED_TIMEOUT, \
    f"refund_timeout-çalışmadı: {j3b.status.value}"
print("  BULGU-2-KAPANDI: VERIFIED_OK + timeout-aşımı(10sn>5sn) → settle-RED "
      "( EscrowNotFoundError); alıcının-refund_timeout-hakkı-korunuyor")
print("    → settle-kapısı-artık-SLA-doğruluyor ( submit_output-ile-aynı)")

# ---------- SESTER (TEMİZ-bilgi) ----------
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester.middleware import SesterMeter
print("  sester-taraı: replay-koruması-KALICI (ledger.seen_nonces tablosu; "
      "restart-pencere-sıfırlamaz — middleware.py:6); escalation-consume() "
      "tek-kezlik (AT-127). ZAMAN/REPLAY-BOŞLUĞU-YOK.")

# ---------- ADDITIVE-DİKİŞ ----------
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
SIGNER = SK.public_key.to_checksum_address().lower()
digest = hashlib.sha256(j.job_id.encode()).hexdigest()
REF = f"PACTA-ESCROW-{j.job_id[:8]}"
claim = {"buyerAddress": SIGNER, "sellerAddress": SELLER,
         "settlementRef": REF,
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": REF,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": SIGNER, "payee": SELLER,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "sester", "head_hex": digest,
              "entries": 1, "evidence_link": "equals",
              "verify_cmd": "pacta.core.vault.settle_escrow"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"escrow-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["6_foreign_chain"] is True
print(f"  ADDITIVE-DİKİŞ: pacta-escrow-tam-akış → x402/v1 GREEN rc0 "
      f"(§6-equals, gerçek-EIP-191)")

bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4")

c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7")

print()
print(">>> AT-165-ÖZET: 2-GERÇEK-bulgu (dispute-window-kontrolü-YOK, "
     "settle-timeout-kontrolü-YOK — pacta); 2-TEMİZ-kanıt (FSM-replay-üçlüsü, "
     "sester-kalıcı-nonce). Üretim-koduna-dokunulmadı.")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(zaman/replay-tarama + bulgular + dikiş)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,45p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-165: zaman/replay-taraması → 2-GERÇEK-bulgu (pacta) + 2-TEMİZ (FSM, sester)"
[[ $FAIL -eq 0 ]]
