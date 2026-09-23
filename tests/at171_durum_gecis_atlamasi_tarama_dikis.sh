#!/usr/bin/env bash
# AT-171: DURUM-GEÇİŞİ-ATLAMASI-TARAMASI (10.-sınıf).
#
# task-58. AT-165'te-FSM-sağlam-bulmuştum; şimdi-atlama-yollarını-tara:
# 1) bir-durum-geçişi-ATLANILARAK-son-duruma-gidilebilir-mi (lock-atlanıp-verify)
# 2) metod-sırası-zorunlu-mu (settle-before-verify-geçerli-mi)
# 3) terminal-durumdan-çıkış-mümkün-mü (SETTLED'den-geri)
# 4) yan-etki-atlama: FSM-reddetse-AMA-ledger-çoktan-değişti-mi (para-akışı-
#    öncesi-kontrol-mu-sonra-mı)
# Öncelik: pacta, sester, fleksa, veridrome, dumen (state-makinesi-olanlar).
#
# BULGU-1 (GERÇEK — pacta yan-etki-sırası): `raise_dispute` (vault.py:317)
# **ÖNCE-bond'u-tahsil** (ledger += required_bond; disputes-kayıt-yazılır),
# **SONRA** FSM-geçiş-kontrolü (vault.py:319 SETTLED→DISPUTED). Reddedilen-
# geçişte-fonlar-çoktan-alınmış. KANIT: terminal-SETTLED-işe-dispute → FSM
# InvalidStateTransitionError-FIRLATIR-AMA-ledger 0.0→0.2-USDC-değişir-VE-
# disputes-tablosuna-1-kayıt-yazılır (gösterge-tutarsızlığı: job-hâlâ-SETTLED).
# Aynı-sınıf `settle_escrow`/`refund_timeout`'da-YOK — ödemede-para-akışı-ÖNCE-
# kontrol-edilir ( düzelme-zaten-orada-uygulandı).
#
# BULGU-2/3/4 (TEMİZ — pacta-geçiş-disiplini): LOCK-atlama-REDDİ (bilinmeyen-
# job_id-EscrowNotFoundError; LOCK-atlanmış-INITIALIZED→submit-FSM-RED);
# metod-sırası-zorunlu (OUTPUT_SUBMITTED'den-settle-RED — verify-şart);
# terminal-çıkış-YOK (SETTLED/AUTO_REFUNDED_TIMEOUT/SLASHED_REFUNDED-çıkış-
# set'leri-boş; SETTLED→DISPUTED-ve→AUTO_REFUNDED_TIMEOUT-reddedilir).
#
# BULGU-5 (TEMİZ — sester-escalation-atomiklik): decide()/consume()'da-durum-
# kontrolü-aynı-atomik-SQL-WHERE- içinde; commit-ledger-öncesi; consume-rowcount
# ile-etki-kontrolü; park()'ta-negatif-amount-kapısı. Disiplin-sağlam.
#
# DÜRÜST-SINIR: üretim-koduna-DOKUNULMAZ (Lead-düzeltme-yapar). fleksa-enerji-
# dağıtım-modülü-ödeme-FSM'i-değil (BessMode/facility-state; tarama-dışı-not);
# veridrome/dumen-para-akışlı-durum-makinesi-içermez (kanıt-sertifikası-tek-
# yönlü-düzen; AT-168).
#
# ADDITIVE-DİKİŞ: tam-escrow-akış → RFC-010 x402/v1 GREEN (gerçek-EIP-191); rc4+rc7.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MESH_ROOT="$(dirname "$(dirname "$(readlink -f "$HERE")")")"
[ -d "$MESH_ROOT/pacta" ] || MESH_ROOT="/home/gokun/projects/00_TAMGA-MESH"
PACTA="$MESH_ROOT/pacta"
SESTER="$MESH_ROOT/sester"
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR="$HERE/../.evidence/DURUM-GECIS"
LOG="$EVDIR/$(date +%F)/at171.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f "$PACTA/pacta/core/vault.py" ]; then
  note "[SKIP] AT-171: pacta/core/vault.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import web3, eth_keys" 2>/dev/null; then
  note "[SKIP] AT-171: web3/eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if [ ! -f "$SESTER/sester/escalation.py" ]; then
  note "[SKIP] AT-171: sester/escalation.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")

BUYER = "0x" + "1" * 40
SELLER = "0x" + "2" * 40

from pacta.core.vault import PactaEscrowVault
from pacta.models import EscrowPolicy, EscrowStatus
from pacta.core.fsm import InvalidStateTransitionError, EscrowFSM
from decimal import Decimal

print("=== AT-171: durum-geçişi-atlaması-taraması (gerçek-üretim-kodu) ===")

# ---------- BULGU-2: LOCK-atlama ----------
v = PactaEscrowVault()
try:
    v.submit_output("lock-atlanmis-bilinmeyen-job", output_payload={"x": 1})
    print("  BULGU-2a: bilinmeyen-job_id'ye-submit KABUL (HATA)")
    B2A = "HATA"
except Exception as e:
    B2A = "TEMİZ"
    print(f"  BULGU-2a: bilinmeyen-job_id → RED ({type(e).__name__})")

v2 = PactaEscrowVault()
j2 = v2.create_and_lock_escrow(buyer_address=BUYER, seller_address=SELLER,
                               amount_usdc=1.0, job_id="lock-atla-1")
j2.status = EscrowStatus.INITIALIZED  # LOCKED-adımı-atlandı
try:
    v2.submit_output("lock-atla-1", output_payload={"x": 1})
    print("  BULGU-2b: LOCK-atlanmış-INITIALIZED → submit KABUL (HATA)")
    B2B = "HATA"
except InvalidStateTransitionError:
    B2B = "TEMİZ"
    print("  BULGU-2b: LOCK-atlanmış-INITIALIZED → submit RED (FSM)")
assert B2A == B2B == "TEMİZ", "LOCK-atlama-kabul-edildi (geçiş-disiplini-bozuk)"

# ---------- BULGU-3: metod-sırası (settle-before-verify) ----------
v3 = PactaEscrowVault()
j3 = v3.create_and_lock_escrow(buyer_address=BUYER, seller_address=SELLER, amount_usdc=1.0)
v3.submit_output(j3.job_id, output_payload={"x": 1})
try:
    v3.settle_escrow(j3.job_id)
    print("  BULGU-3: settle-before-verify KABUL (HATA)")
    B3 = "HATA"
except InvalidStateTransitionError as e:
    B3 = "TEMİZ"
    print(f"  BULGU-3: OUTPUT_SUBMITTED→SETTLE RED (FSM: verify-zorunlu; {str(e)[:34]}…)")
assert B3 == "TEMİZ", "settle-before-verify-kabul-edildi"

# ---------- BULGU-4: terminal-çıkış-YOK ----------
v4 = PactaEscrowVault()
j4 = v4.create_and_lock_escrow(buyer_address=BUYER, seller_address=SELLER, amount_usdc=1.0)
v4.submit_output(j4.job_id, output_payload={"x": 1})
v4.mark_verified_ok(j4.job_id)
v4.settle_escrow(j4.job_id)
assert j4.status == EscrowStatus.SETTLED
# terminal-set'leri-çıkış-boş
for s in (EscrowStatus.SETTLED, EscrowStatus.AUTO_REFUNDED_TIMEOUT,
          EscrowStatus.SLASHED_REFUNDED):
    assert EscrowFSM.ALLOWED_TRANSITIONS[s] == set(), \
        f"{s.value}-terminal-değil (çıkış-var)"
print("  BULGU-4a: terminal-durumların-çıkış-set'i-boş (SETTLED/"
      "AUTO_REFUNDED_TIMEOUT/SLASHED_REFUNDED)")

# SETTLED'den-çıkış-denemeleri
for hedef, fn in (
    ("DISPUTED", lambda: v4.raise_dispute(j4.job_id, claimant_address=BUYER,
                                          reason="x", evidence_hash="a" * 64)),
    ("AUTO_REFUNDED_TIMEOUT", lambda: v4.refund_quality_failure(j4.job_id)),
):
    try:
        fn()
        print(f"  BULGU-4b: SETTLED→{hedef} KABUL (HATA)")
        B4 = "HATA"
    except InvalidStateTransitionError:
        B4 = "TEMİZ"
        print(f"  BULGU-4b: SETTLED→{hedef} RED (FSM)")
assert B4 == "TEMİZ", "terminal'den-çıkış-kabul-edildi"
print("  → geçiş-atlama/ters-sıra/terminal-çıkış: ÜÇÜ-DE-TEMİZ (FSM-haritası-sağlam)")

# ---------- BULGU-1 → KAPANDI ( AT-171): FSM-geçiş-kontrolü-artık-ÖNCE ----------
# Önceden-bond-tahsili ( ledger + disputes-kayıdı) FSM-geçişinden-ÖNCE-
# yapılıyordu; terminal-SETTLED-işe-dispute → FSM-reddeder-AMA-ledger-zaten-
# 0.2-USDC-değişmişti. Artık-geçiş-önce-kontrol-edilir ( refund_timeout-
# deseni); para-akışı-sadece-geçerli-geçişte.
v5 = PactaEscrowVault()
j5 = v5.create_and_lock_escrow(
    buyer_address=BUYER, seller_address=SELLER, amount_usdc=Decimal("1.0"),
    policy=EscrowPolicy(dispute_bond_ratio=Decimal("0.20")))
v5.submit_output(j5.job_id, output_payload={"x": 1})
v5.mark_verified_ok(j5.job_id)
v5.settle_escrow(j5.job_id)
tok = j5.deposit_token
ledger_once = float(v5.ledger_balances[tok])
dispute_once = len(v5.disputes)
durum_once = j5.status
try:
    v5.raise_dispute(j5.job_id, claimant_address=BUYER, reason="pencere-içi",
                     evidence_hash="a" * 64)
    raise AssertionError("AÇIK-GERİ-GELDİ! ( terminal-dispute-kabul)")
except InvalidStateTransitionError as e:
    assert "no bond collected" in str(e), f"AT-171-mesajı-beklendi: {e}"
delta = float(v5.ledger_balances[tok]) - ledger_once
assert abs(delta) < 1e-9, \
    f"bond-FSM-reddinden-sonra-tahsil-edilmemeliydi: {delta}"
assert len(v5.disputes) == dispute_once, \
    f"disputes-kayıdı-yazıldı ( yan-etki-sızdı): {len(v5.disputes)}"
print("  BULGU-1-KAPANDI: SETTLED'den-dispute → FSM-RED-VE-yan-etki-YOK "
      f"( ledger: {ledger_once}→{float(v5.ledger_balances[tok])}; "
      f"disputes: {dispute_once}→{len(v5.disputes)})")
print("    → FSM-geçiş-kontrolü-artık-para-akışından-ÖNCE "
      "( reddedilen-geçişte-fonlar-alınmaz)")

# karşıt-kanıt: refund_timeout'da-para-akışı-ÖNCE-kontrol (AT-165-düzelmesi)
v6 = PactaEscrowVault()
j6 = v6.create_and_lock_escrow(buyer_address=BUYER, seller_address=SELLER, amount_usdc=1.0)
v6.submit_output(j6.job_id, output_payload={"x": 1})
l6 = float(v6.ledger_balances[j6.deposit_token])
try:
    v6.refund_timeout(j6.job_id)  # SLA-içi → reddetmeli
except Exception as e:
    pass
assert float(v6.ledger_balances[j6.deposit_token]) == l6, "SLA-içi-refund-ledger-değiştirdi"
print("  KARŞIT-KANIT: refund_timeout-SLA-kontrolü-ÖNCE (ledger-değişmedi) — "
      "düzeltme-burada-uygulandı, raise_dispute'de-eksik")

# ---------- BULGU-5 (TEMİZ — sester) ----------
from sester.escalation import EscalationQueue
import tempfile, os
tmp = tempfile.mkdtemp()
eq = EscalationQueue(os.path.join(tmp, "esc.db"), ledger=None, ttl_seconds=60.0)
t = eq.park(agent="0xag", resource="res", amount=1.0, rule_id="r1")
assert eq.decide(t["esc_id"], approve=True, by="op", note="n")["status"] == "approved"
# çift-decide-reddetmeli
try:
    eq.decide(t["esc_id"], approve=False, by="op")
    print("  BULGU-5a: approved-bilete-tekrar-decide KABUL (HATA)")
    B5 = "HATA"
except ValueError as e:
    B5 = "TEMİZ"
    print(f"  BULGU-5a: approved→decide-RED ({str(e)[:40]})")
# consume-atomik
assert eq.consume(t["esc_id"]) is True
assert eq.consume(t["esc_id"]) is False, "consume-tekrar-edilebilir (HATA)"
print("  BULGU-5b: consume-atomik (rowcount-ile; tekrar-False)")
print("  → sester-escalation: durum-kontrolü-atomik-WHERE; commit-ledger-öncesi "
      "(TEMİZ)")

# ---------- ADDITIVE-DİKİŞ ----------
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
SIGNER = SK.public_key.to_checksum_address().lower()
digest = hashlib.sha256(j5.job_id.encode()).hexdigest()
REF = f"PACTA-FSM-{j5.job_id[:8]}"
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
              "verify_cmd": "pacta.core.fsm.EscrowFSM.transition"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"FSM-akış-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["6_foreign_chain"] is True
print(f"  ADDITIVE-DİKİŞ: FSM-tutarlı-escrow-akışı → x402/v1 GREEN rc0 "
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
print(">>> AT-171-ÖZET: 1-GERÇEK-bulgu (raise_dispute: para-akışı-FSM-öncesi — "
     "pacta); 4-TEMİZ-kanıt (LOCK-atlama, metod-sırası, terminal-çıkış, "
     "sester-atomiklik). Üretim-koduna-dokunulmadı.")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(durum-geçiş-atlaması + bulgular + dikiş)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,45p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-171: durum-geçişi → 1-GERÇEK-bulgu (pacta raise_dispute) + 4-TEMİZ"
[[ $FAIL -eq 0 ]]
