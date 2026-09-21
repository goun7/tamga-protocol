#!/usr/bin/env bash
# AT-106: TENDERIX-İKİNCİ-YÜZ (escrow+dispute) → RFC-010 x402/v1 + RFC-011 dikişi.
#
# AT-071-sadece-İLK-yüzü-ölçtü (ed25519-imza → tamga/native). İkinci-yüz:
#   src/tenderix/escrow.py — non-custodial-emanet-durum-makinesi (SPEC §6)
#       CREATED→AUTHORIZED→SETTLED|REFUNDED|DISPUTED; resolve() karar-geçidi
#       S6-sözleşmesi: DISPUTED→SETTLED yalnız-resolve() ile (fail-closed);
#       SETTLED→DISPUTED kapısı-açık (teslim-sonrası-itiraz)
#   src/tenderix/dispute.py — hash-zincirli-delil-defteri (81-OstrakonSOC-uyumlu)
#       GENESIS="sha256:"+64-sıfır; entry_hash=sha256(prev+canon);
#       verify_chain; LedgerBroken-tahriz-tespiti; disk-yükleme-doğrulaması
#
# TENDERIX-ÖZELLİĞİ: kanıt-BİR-DURUM-GEÇİŞİDİR — "para-yalnız-SETTLED'de-serbest
# kalır"-sözleşmesi. AT-071'in-imzalı-teklifinin-arkasındaki-ÖDEME-ÇÖZÜMLEMESİ
# budur: authorize→dispute→resolve-ömür-döngüsü-bir-gerçek-kanıt-zinciri-üretir.
#
# İKİ-PROTOKOL-ÖLÇÜMÜ:
#   RFC-010 (x402/v1): escrow-ömür-döngüsü-zincir-head'i → evidenceHash → GREEN
#   RFC-011 (dispute): dispute_resolved-olayı → status:'resolved'
#       — "tenderix/v1"-SUPPORTED_PROTOCOLS'ta-ise-GREEN-rc0;
#         değilse-dürüst-İNDETERMİNE-rc11 (yeşil-boya-YOK — Lead'e-additive-talep)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/TENDERIX-2/$(date +%F)/at106.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-106: Tenderix-escrow+dispute (ikinci-yüz) → RFC-010 x402/v1 + RFC-011"

TX="/home/gokun/projects/01_unicorn/64-Tenderix/src"
if [ ! -f "$TX/tenderix/escrow.py" ] || [ ! -f "$TX/tenderix/dispute.py" ]; then
  note "[SKIP] AT-106: Tenderix-kodu-bu-makinede-değil (CI) —"
  note "       emanet-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-106: eth_keys-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$TX" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from tenderix.escrow import Escrow, EscrowState, EscrowError
from tenderix.dispute import DisputeLedger, GENESIS, LedgerBroken
import settlement_bind_verify as SB
import dispute_pointer_verify as DP

from eth_keys import keys

# --- 0) İZOLE-çalışma-dizini
TMP = tempfile.mkdtemp(prefix="at106-")

def hayatar(led):
    """Escrow-geçişlerini-delil-defterine-yazan-callback (gerçek-üretim-yolu)."""
    def cb(offer_id, frm, to):
        led.append("escrow_" + frm.value.lower() + "_to_" + to.value.lower(),
                   offer_id, {"from": frm.value, "to": to.value})
    return cb

# --- 1) GERÇEK-ömür-döngüsü: authorize→dispute→resolve(satıcı-kazanır)
LP = os.path.join(TMP, "dispute.jsonl")
led = DisputeLedger(LP)
esc = Escrow(on_transition=hayatar(led))
assert esc.state("O-1") == EscrowState.CREATED
esc.authorize("O-1", "auth-ref-106")
assert esc.state("O-1") == EscrowState.AUTHORIZED
esc.dispute("O-1")
assert esc.state("O-1") == EscrowState.DISPUTED
esc.resolve("O-1", buyer_wins=False)   # satıcı-kazanır → SETTLED
assert esc.state("O-1") == EscrowState.SETTLED
ok, why = led.verify_chain()
assert ok and why == "OK", f"zincir-geçerli-olmalı: {ok} {why}"
# GENESIS-gerçek: "sha256:"+64-sıfır (81-OstrakonSOC-ailesi)
assert GENESIS == "sha256:" + "0"*64, "GENESIS-sha256-öneki+64-sıfır"
evs = led.entries_for("O-1")
assert [e["event"] for e in evs] == ["escrow_created_to_authorized",
                                     "escrow_authorized_to_disputed",
                                     "escrow_disputed_to_settled"], \
    f"ömür-döngüsü-olayları-eksik: {[e['event'] for e in evs]}"
HEAD = led._prev
assert HEAD.startswith("sha256:") and len(HEAD) == 64 + 7
HEAD_HEX = HEAD[len("sha256:"):]
assert len(HEAD_HEX) == 64 and all(c in "0123456789abcdef" for c in HEAD_HEX)
print(f"  escrow-ömür-döngüsü: authorize→dispute→resolve → SETTLED (3-olay)")
print(f"    GENESIS: {GENESIS[:16]}… | head: {HEAD_HEX[:20]}… (64-hex)")
print(f"    verify_chain: OK | her-geçiş-delil-defterine-yazıldı")

# --- 2) İKİ-ÇÖZÜM-YÖNÜ: buyer_wins-true→REFUNDED / false→SETTLED
esc_b = Escrow()
esc_b.authorize("O-B", "r"); esc_b.dispute("O-B"); esc_b.resolve("O-B", True)
assert esc_b.state("O-B") == EscrowState.REFUNDED, "buyer-wins→REFUNDED"
esc_s = Escrow()
esc_s.authorize("O-S", "r"); esc_s.dispute("O-S"); esc_s.resolve("O-S", False)
assert esc_s.state("O-S") == EscrowState.SETTLED, "seller-wins→SETTLED"
print(f"  resolve-iki-yön: buyer_wins=True→REFUNDED | False→SETTLED (gerçek)")

# --- 3) FAIL-CLOSED: DISPUTED→settle-YASAK (S6-sözleşmesi)
esc_f = Escrow()
esc_f.authorize("O-F", "r"); esc_f.dispute("O-F")
try:
    esc_f.settle("O-F")
    raise AssertionError("DISPUTED→settle-geçmemeli (fail-closed)")
except EscrowError:
    pass
# geçersiz-geçişler-genel: CREATED→settle
try:
    Escrow().settle("O-G")
    raise AssertionError("CREATED→settle-geçmemeli")
except EscrowError:
    pass
print("  fail-closed: DISPUTED→settle-ve-CREATED→settle → EscrowError (S6)")

# --- 4) ÜRETİCİ-TARAFI-SAĞLAMLIK: tahriz → LEDGER_BROKEN
led._entries[0]["payload"]["enjected"] = True
ok2, why2 = led.verify_chain()
assert ok2 is False and "BROKEN" in why2, \
    f"tahriz-tespit-edilmeli: {ok2} {why2}"
led._entries[0]["payload"].pop("enjected")
assert led.verify_chain()[0] is True, "geri-alma-zinciri-onarmalı"
# disk-yükleme-doğrulaması: kalıcı-zincir-bağımsızca-doğrulanır
led_disk = DisputeLedger(LP)
assert len(led_disk) == 3 and led_disk.verify_chain()[0] is True
print("  tahriz-koruması: geçmiş-kayıt-değişimi → LEDGER_BROKEN@0 (T9)")
print("    disk-yükleme: kalıcı-zincir-bağımsızca-doğrulandı (3-kayıt)")

# --- 5) DİKİŞ-1: escrow-zinciri → RFC-010 x402/v1 (STOCK-yol)
# evidenceHash = çözülen-emanet-zincirinin-head'i (machine-checkable:
# DisputeLedger.verify_chain-ile-bağımsız-yeniden-doğrulanır)
pk = keys.PrivateKey(bytes.fromhex("77" * 32))
BUYER = pk.public_key.to_checksum_address().lower()
PAYEE = "0x71c8a18174415cc92067749eb3544dffd3f87884"
PID = "TENDERIX-ESCROW-106"
govde = {"buyerAddress": BUYER, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": HEAD_HEX}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(d_claim)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 106, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": HEAD_HEX},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": HEAD_HEX},
                              "payer": BUYER, "payee": PAYEE,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": HEAD_HEX,
                                  "entries": len(led), "evidence_link": "equals",
                                  "verify_cmd": "tenderix.dispute + escrow"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Tenderix-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  escrow-ömür-döngüsü → RFC-010-GREEN (x402/v1, STOCK-yol)")
print(f"    ödeme-id={PID}; SETTLED-kanıtı-delivery_hash'e-bağlı")

# --- 6) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("0x" + "77"*65, os.urandom(65).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (65-bayt-sahte + rastgele) → RED rc4")

# --- 7) NEGATİF-2: emanet-zincirine-tahriz → evidenceHash-swap-RED rc7
led3 = DisputeLedger()
e3 = Escrow(on_transition=hayatar(led3))
e3.authorize("O-7", "r"); e3.resolve("O-7")   # doğrudan-çözüm (dispute-yok)
head3 = led3._prev[len("sha256:"):]
assert head3 != HEAD_HEX, "farklı-ömür-döngüsü-farklı-head"
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": head3}}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
sig2 = "0x" + pk.sign_msg_hash(bytes.fromhex(d2)).to_bytes().hex()
claim2 = dict(govde2); claim2["signature"] = sig2
r7 = SB.verify(charge, claim2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"emanet-ikame-RED-rc7-beklendi: {r7}"
print("  farklı-emanet-döngüsü-ikame (yeni-gerçek-imzalı-head) → RED rc7")
print("    taşıma-ölçüldü: çözülen-head-delivery_hash'e-sabittir")

# --- 8) DİKİŞ-2: dispute-resolved → RFC-011 (anlaşmazlık-bacağı)
# Tenderix'in-delil-defteri-gerçek-anlaşmazlık-olayları-tutar: dispute_opened,
# dispute_resolved. RFC-011-status:'resolved' → GREEN-rc0 deseni (AT-084-aynısı).
charge11 = dict(charge)
charge11["dispute_pointer"] = {
    "status": "resolved",
    "counter_claim": {"delivered": "no", "sig": "0x" + "11"*65},
    "arbitration": {"protocol": "tenderix/v1", "bond_pct": 0.30,
                    "outcome": "seller_favored"},
}
r11 = DP.verify(charge11)
# "tenderix/v1"-SUPPORTED_PROTOCOLS'ta-ise-GREEN-rc0; değilse-İNDETERMİNE-rc11
# (dürüst-sonuç — yeşil-boya-YOK; Lead'e-additive-talep-gönderildi)
if "tenderix/v1" in DP.SUPPORTED_PROTOCOLS:
    assert r11["verdict"] == "GREEN" and r11["reason_code"] == 0, \
        f"resolved+tenderix/v1 → GREEN-rc0-beklendi: {r11}"
    print(f"  dispute-resolved → RFC-011-GREEN-rc0 (tenderix/v1-additive-kabul)")
else:
    assert r11["verdict"] == "İNDETERMİNE" and r11["reason_code"] == 11, \
        f"unknown-protocol-rc11-beklendi: {r11}"
    print("  dispute-resolved + tenderix/v1 → İNDETERMİNE rc11 (dürüst)")
    print("    NOT: SUPPORTED_PROTOCOLS'ta-yok — Lead'e-additive-talep-gönderildi")
    print("    (pacta/v1 + holistis/disputeContext + pactiva/v1 — additive-açık)")

# --- 9) RFC-011-status:'none' → GREEN-rc0 (itiraz-yok-gerçek-durum)
charge11n = dict(charge)
charge11n["dispute_pointer"] = {"status": "none"}
r11n = DP.verify(charge11n)
assert r11n["verdict"] == "GREEN" and r11n["reason_code"] == 0, \
    f"status:none → GREEN-rc0-beklendi: {r11n}"
print("  status:none (itiraz-yok) → RFC-011-GREEN-rc0 (protokol-bağımsız)")

# --- 10) RFC-011-negatifleri: bond<%20 → RED-rc10; contradiction+yok → rc12
charge11b = dict(charge)
charge11b["dispute_pointer"] = {
    "status": "open", "arbitration": {"protocol": "tenderix/v1", "bond_pct": 0.10}}
r11b = DP.verify(charge11b)
assert r11b["reason_code"] == 10, f"bond<%20 → rc10-beklendi: {r11b}"
charge11c = dict(charge)
charge11c["dispute_pointer"] = {"status": "contradiction"}
r11c = DP.verify(charge11c)
assert r11c["reason_code"] == 12, f"contradiction+yok → rc12-beklendi: {r11c}"
print("  RFC-011-negatifleri: bond<0.20→rc10 | contradiction+yok→rc12")

# --- 11) İKİ-YÜZ-BİRLEŞİMİ: AT-071 (imzalı-teklif) × AT-106 (emanet-çözümü)
# AT-071-imzalı-CSVO-teklifinin-ödemesi-ancak-emanet-SETTLED-olduğunda-serbest
# kalır — imza-TEKLİFİ, emanet-ÖDEMEYİ-çözer (Tenderix'in-iki-yüzü-birleşir).
assert r["checks"]["2_claim_sig"] is True and esc.state("O-1") == EscrowState.SETTLED
print("  iki-yüz-birleşimi: AT-071 (imzalı-teklif) × AT-106 (emanet-çözümü)")
print("    imza-teklifi-bağlar, emanet-SETTLED-ödemesi-çözer")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-bir-Tenderix-escrow+dispute-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-106: Tenderix-escrow+dispute (ikinci-yüz) → RFC-010 + RFC-011"
[[ $FAIL -eq 0 ]]
