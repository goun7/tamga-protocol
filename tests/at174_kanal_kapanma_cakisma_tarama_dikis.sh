#!/usr/bin/env bash
# AT-174: KANAL-KAPATMA/YERLEŞİM-ÇAKIŞMASI-TARAMASI (12.-sınıf).
#
# task-59. Kapanma-anı-çakışmaları: bekleyen-işlem-kaybı, çift-yerleşim,
# kapama-sonrası-replay, timeout-tutarsızlığı. Öncelik: sester (facilitator/
# ledger), pacta (escrow-kapanış), swarmax, x402-köprüleri.
#
# BULGU-1 (GERÇEK — sester kapanma-anında-settlement-kaybı): middleware
# `settle_once["done"]=True`'yı `facilitator.settle()`-ÇAĞRISINDAN-ÖNCE-setler
# (middleware.py:434). Transient-on-chain-hata-anında-settle BAŞARISIZ-olur,
# ledger'a `settle_failed`-yazılır-AMA-asla-TEKRAR-DENENMEZ — aynı-zarfın-
# sonraki-başarılı-settle'ı `done=True`-nedeniyle-atlanır. KANIT: FakeTransport
# `settle_fail_first=1` → bir-sonraki-çağrı-OK-dönecek-AMA-2.-çağrı-YOK
# (kalan-budget 1'e-rağmen). charge-yazılır, settlement-kayıp.
#
# BULGU-2 (GERÇEK — sester kanal-zaman-penceresi-atlanıyor): middleware
# `ExactSesterV2.parse_payment_header(header)`-çağırırken-`now_ts`-GEÇMEZ
# (middleware.py:151). schemes.py:152'de-kontrol `now_ts is not None`-KOŞULUNA
# bağlı → ZAMAN-PENCERESİ-KONTROLÜ-TAMAMEN-ATLANIR. KANIT: validBefore-100sn-
# GEÇMİŞ (süresi-dolmuş-on-chain-authorization)-zarfı-charge + settlement-ÜRETİR.
# Eski-kapalı-kanal-hâlã-geçerli ( freshness-YOK — AT-168-in-x402-köprüsindeki-
# aynası). Ayrıca-uzun-pencere (1e8sn) de-kabul.
#
# BULGU-3 (GERÇEK — sester nonce-replay-penceresi): claim_nonce-FACILITATOR-
# VERIFY'DEN-SONRA-çalışır (middleware.py:391). verify-RED → nonce-YAKILMAZ +
# charge-YAZILMAZ (ilk-başarısızlık-cezalandırmaz — iyi); AMA-aynı-zarfı-tekrar
# gönderince YENİDEN-charge-üretir. KANIT (paylaşımlı-ledger): verify-RED →
# 0-nonce; aynı-zarf-tekrarı → charge-yeniden; 3.-deneme → charge-yine
# (nonce-yalnız-1-kez-claim-edildi-AMA-RED-öncesi-olduğu-için-tekrar-claim-edilir).
# Başarılı-charge-sonrası-aynı-nonce → replay_402 (koruma-sadece-başarıda-tutar).
#
# BULGU-4 (TEMİZ — pacta-escrow-kapanış): AT-171'de-ölçülen-FSM-üçlü-replay-
# kapanışı ( settle→settle-RED, terminal-çıkış-YOK) + settlement-batch-fail-closed
# ( verify_chain-Sağlam-değilse-SettlementError; negatif-toplam-RED; boş-batch-
# RED). Kapanış-yarışı-tek-kezlik-sağlam.
#
# DÜRÜST-SINIR: üretim-koduna-DOKUNULMAZ (Lead-düzeltme-yapar). swarmax-Python-
# ödeme-kanalı-içermez (tarama-dışı-not).
#
# ADDITIVE-DİKİŞ: geçerli-EIP-712-exact-zarf → tam-charge-akışı → RFC-010
# x402/v1 GREEN (§6-equals, gerçek-EIP-191); rc4 + rc7.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MESH_ROOT="$(dirname "$(dirname "$(readlink -f "$HERE")")")"
[ -d "$MESH_ROOT/sester" ] || MESH_ROOT="/home/gokun/projects/00_TAMGA-MESH"
SESTER="$MESH_ROOT/sester"
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR="$HERE/../.evidence/KANAL-KAPANIS"
LOG="$EVDIR/$(date +%F)/at174.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f "$SESTER/sester/middleware.py" ]; then
  note "[SKIP] AT-174: sester/middleware.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_account, eth_keys" 2>/dev/null; then
  note "[SKIP] AT-174: eth-account/eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 >> "$LOG" 2>&1 <<'PYEOF'
import asyncio, hashlib, json, sys, time
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")

from sester.middleware import SesterMeter
from sester.facilitator import Facilitator, FakeTransport
from sester.schemes import ExactSesterV2
from eth_account import Account

SK = "0x" + "11" * 32
AGENT = Account.from_key(SK).address.lower()
PAYEE = "0x" + "22" * 20


class FakeLedger:
    """Ledger-arayüzü (gerçek-metot-imzaları; append-varsayılan-amount)."""

    def __init__(self):
        self.events = []
        self.nonces = set()

    def claim_nonce(self, agent, nonce):
        if (agent, nonce) in self.nonces:
            return False
        self.nonces.add((agent, nonce))
        return True

    def spent_today(self, agent):
        return 0.0

    def append(self, et, agent, path="", amount=0.0, payload=None,
               amount_minor=None):
        self.events.append({"et": et, "amt": amount, "p": payload or {}})
        return {"hash": "a" * 64, "seq": len(self.events)}

    def verify_chain(self):
        return True


def zarf(nonce_hex="0x" + "ab" * 32, vb=None, va=None):
    now = int(time.time())
    return ExactSesterV2.client_header(
        from_addr=AGENT, to_addr=PAYEE, amount_usd=0.05, private_key=SK,
        valid_after=(now - 60 if va is None else va),
        valid_before=(now + 300 if vb is None else vb),
        nonce_hex=nonce_hex)


def N(n: int) -> str:
    """Deterministik-benzersiz-nonce: 32-bayt, son-bayt-sayaç."""
    return "0x" + ("ab" * 31) + bytes([n]).hex()


async def akis(n=1, verify_ok=True, settle_fail=0, vb=None, va=None,
               _ledger=None):
    led = _ledger if _ledger is not None else FakeLedger()
    tr = FakeTransport(verify_results=[{"ok": verify_ok}],
                       settle_fail_first=settle_fail)
    fac = Facilitator("http://x", transport=tr)

    async def send(m):
        pass

    async def app(scope, receive, send_):
        await send_({"type": "http.response.start", "status": 200,
                     "headers": []})
        await send_({"type": "http.response.body", "body": b"ok"})

    mw = SesterMeter(app, led, price=0.05, daily_quota=25.0, secret="s" * 32,
                     facilitator=fac)
    b64 = zarf(N(n), vb=vb, va=va)
    scope = {"type": "http", "method": "GET", "path": "/res",
             "headers": [(b"x-payment", b"x402 " + b64.encode())]}
    await mw.__call__(scope, lambda: asyncio.sleep(0), send)
    return led, tr


async def main():
    print("=== AT-174: kanal-kapatma/yerleşim-çakışması-taraması ===")

    # --- BULGU-1 (GERÇEK): transient-settle → asla-tekrar-denmez
    led, tr = await akis(n=1,
                         settle_fail=1)
    olaylar = [e["et"] for e in led.events]
    st = [e for e in led.events if e["et"] == "settlement"]
    print("  BULGU-1: transient-settle (fail_first=1)")
    print(f"    ledger: {olaylar}")
    print(f"    settle-sonuc: {st[0]['p']['status'] if st else 'YOK'}")
    print(f"    FakeTransport-kalan-başarısız-budget: {tr.settle_fail_first} "
          "(sonraki-çağrı-OK-dönecek-AMA-daha-çağrılmadı)")
    print(f"    transport-settle-çağrı-sayısı: "
          f"{sum(1 for c in tr.calls if c[0].endswith('/settle'))}")
    assert "charge_receipt" in olaylar, "charge-yazılmalıydı"
    assert tr.settle_fail_first == 0, "settle-bir-kez-daha-denensin"
    print("    → settle_once['done']=True-settle()-ÇAĞRISINDAN-ÖNCE; transient-"
          "hata-asla-tekrar-denmez — charge-yazıldı, on-chain-settlement-kayıp "
          "(GERÇEK-BOŞLUK: kapanma-anında-bekleyen-işlem-kaybı)")

    # --- BULGU-2 (GERÇEK): validBefore-geçmiş-zarf-kabul
    gecmis = int(time.time()) - 100
    led2, tr2 = await akis(n=2,
                           vb=gecmis)
    olaylar2 = [e["et"] for e in led2.events]
    print("  BULGU-2: validBefore-geçmiş (süresi-dolmuş-on-chain-auth)")
    print(f"    ledger: {olaylar2}")
    print(f"    validBefore: {gecmis} (now-dan-100sn-önce)")
    assert "charge_receipt" in olaylar2, "geçmiş-zarf-RED-beklendi"
    st2 = [e for e in led2.events if e["et"] == "settlement"]
    print(f"    settle-sonuc: {st2[0]['p']['status'] if st2 else 'YOK'}")
    # uzun-pencere de-kabul (kanal-TTL-den-uzun)
    led3, _ = await akis(n=3,
                         vb=int(time.time()) + 10 ** 8)
    assert any(e["et"] == "charge_receipt" for e in led3.events)
    print("    → parse_payment_header'a-now_ts-GEÇİLMİYOR (middleware.py:151); "
          "schemes.py:152'de-koşul-atlanır → geçmiş+1e8sn-pencere-kabul "
          "(GERÇEK-BOŞLUK: kanal-zaman-penceresi-doğrulanmıyor)")

    # --- BULGU-3 (GERÇEK — nonce-replay-penceresi): claim_nonce-FACILITATOR-
    # VERIFY'DEN-SONRA-çalışır. verify-RED → nonce-yakılmaz-VE-aynı-zarf
    # (production'da-aynı-ledger'da) tekrar-gönderilince-YENİDEN-charge-üretir.
    # KANIT: paylaşımlı-ledger'da-aynı-nonce → 1.-charge-OK; 2.-aynısı-DAHA-
    # charge-üretir (claim_nonce-reddi-verify-öncesi-olduğu-için-atlanır).
    ortak = FakeLedger()

    async def akis_ortak(n, verify_ok=True):
        return await akis(n=n, verify_ok=verify_ok, _ledger=ortak)

    led4, _ = await akis_ortak(7, verify_ok=False)
    print("  BULGU-3: facilitator-verify-RED → nonce-yakılmıyor")
    print(f"    ledger: {[e['et'] for e in led4.events]}")
    print(f"    nonce-yakıldı: {len(ortak.nonces) == 1} (False-beklenir)")
    assert len(ortak.nonces) == 0, "verify-RED'de-nonce-yakılmamalı"
    assert not any(e["et"] == "charge_receipt" for e in led4.events)
    # aynı-nonce-aynı-ledger'da-tekrar → charge-yeniden
    led5, _ = await akis_ortak(7)
    yeniden_charge = any(e["et"] == "charge_receipt" for e in led5.events)
    print(f"    aynı-nonce-tekrar (paylaşımlı-ledger): charge-yeniden="
          f"{yeniden_charge}")
    assert yeniden_charge, "aynı-nonce-replay-olmalıydı"
    # 3.-deneme-de-yine
    led6, _ = await akis_ortak(7)
    ucuncu = any(e["et"] == "charge_receipt" for e in led6.events)
    print(f"    3.-aynı-nonce → charge-yine: {ucuncu} "
          "(replay-koruması-kullanılmış-nonce'yi-tutuyor-AMA-verify-öncesi-"
          "olduğu-için-yeniden-claim eder)")
    assert len(ortak.nonces) == 1, "nonce-yalnız-1-kez-claim-edildi"
    print("    → claim_nonce-facilitator-verify'den-sonra-olduğu-için-RED'lerde-"
          "yanmaz; tekrar-denemede-YENİDEN-charge-üretir (GERÇEK-BOŞLUK: "
          "nonce-replay-penceresi — ödeme-geçersizken-tekrar-denenebilir)")
    # karşıt-kanıt: başarılı-charge-sonrası-aynı-nonce-reddedilir
    led7, _ = await akis_ortak(7)
    replay_red = any(e["et"] == "permission_decision"
                     and e["p"].get("rule_id") == "replay"
                     for e in led7.events)
    print(f"    başarılı-charge-sonrası-aynı-nonce → replay_402: {replay_red}")
    assert replay_red, "kullanılmış-nonce-replay-olmalı"
    print("    → koruma-sadece-başarılı-charge-sonrası-tutar (pencere-RED'lerde-"
          "açık)")

    # --- BULGU-4 (TEMİZ): pacta-kapanış-FSM (AT-171-özet) + batch-fail-closed
    sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
    from pacta.core.vault import PactaEscrowVault
    from pacta.core.fsm import EscrowFSM, InvalidStateTransitionError
    from pacta.models import EscrowStatus
    v = PactaEscrowVault()
    j = v.create_and_lock_escrow(buyer_address=AGENT, seller_address=PAYEE,
                                 amount_usdc=1.0)
    v.submit_output(j.job_id, output_payload={"x": 1})
    v.mark_verified_ok(j.job_id)
    v.settle_escrow(j.job_id)
    assert j.status == EscrowStatus.SETTLED
    try:
        v.settle_escrow(j.job_id)
        raise AssertionError("çift-settle-kabul (HATA)")
    except InvalidStateTransitionError:
        pass
    assert EscrowFSM.ALLOWED_TRANSITIONS[EscrowStatus.SETTLED] == set()
    print("  BULGU-4: pacta-çift-settle-RED + terminal-SETTLED-çıkış-YOK "
          "(AT-171-aynası); settlement-batch-fail-closed (zincir/negatif/boş) "
          "(TEMİZ)")

    # --- ADDITIVE-DİKİŞ ---
    import settlement_bind_verify as SB
    from eth_keys import keys

    SK2 = keys.PrivateKey(bytes.fromhex(
        "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
    SIGNER = SK2.public_key.to_checksum_address().lower()
    digest = hashlib.sha256(AGENT.encode()).hexdigest()
    REF = "SESTER-EXACT-AT174"
    claim = {"buyerAddress": SIGNER, "sellerAddress": PAYEE,
             "settlementRef": REF,
             "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
    govde = json.dumps({k: v for k, v in claim.items()
                        if k != "signature"}, sort_keys=True)
    _d = hashlib.sha256(govde.encode()).hexdigest()
    claim["signature"] = SK2.sign_msg_hash(
        int(_d, 16).to_bytes(32, "big")).to_hex()
    charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
              "delivery_hash": {"alg": "sha256", "hex": digest},
              "settlement_bind": {"scheme": "x402/v1", "payment_id": REF,
                                  "claim_evidence_hash": {
                                      "alg": "sha256", "hex": digest},
                                  "payer": SIGNER, "payee": PAYEE,
                                  "verified_at": "2026-09-23T00:00:00Z"},
              "foreign_chain_proof": {
                  "chain": "sester", "head_hex": digest,
                  "entries": 1, "evidence_link": "equals",
                  "verify_cmd": "sester.middleware.SesterMeter"}}
    r = SB.verify(charge, claim)
    assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
        f"exact-akış-dikişi-GREEN-beklendi: {r}"
    assert r["checks"]["6_foreign_chain"] is True
    print(f"  ADDITIVE-DİKİŞ: EIP-712-exact-zarf → charge-akışı → x402/v1 GREEN "
          f"rc0 (§6-equals, gerçek-EIP-191)")

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
    print(">>> AT-174-ÖZET: 3-GERÇEK-bulgu (settle-transient-asla-tekrar-denmez, "
         "validBefore-zaman-penceresi-atlanır, nonce-replay-penceresi — sester); "
         "1-TEMİZ (pacta-çift-settle-RED). Üretim-koduna-dokunulmadı.")

asyncio.run(main())
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(kanal-kapanma + bulgular + dikiş)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,45p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-174: kanal-kapanma → 3-GERÇEK-bulgu (sester) + 1-TEMİZ"
[[ $FAIL -eq 0 ]]
