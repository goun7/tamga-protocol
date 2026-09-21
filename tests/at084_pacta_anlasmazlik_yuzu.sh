#!/usr/bin/env bash
# AT-084: PACTA-ANLAŞMAZLIK-YÜZÜ — RFC-011 dispute-pointer → CANLI Pacta hakemliği.
#
# AT-073 (2026-09-21) RFC-011-gate'ini-ölçtü-AMA-iki-şeyle-sentetik-yoldan:
#   (a) charge-verisi-uydurma ("c"*64), (b) SB._claim_signer=lambda-test-double'ı.
# RFC-011-§4'ün-SONRA-borcunu-koymadı: "(a) Pacta-hakemlik-simülasyonu-ile-canlı-test"
# — yani-dispute_pointer'in-işaret-ettiği-pacta/v1-HİÇ-ÇALIŞMADI. Bu-test-o-borcunu-
# öder: RFC-011'in-çelişki-algılayıcısı-gerçek-bir-Ajan-Borsası-işinde-atar-ve-Pacta'nın
# GERÇEK-Schelling-hakem-motoru-çelişkiyi-çözer.
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   pacta/pacta/verification/tier3_arbitration.py:21  calculate_schelling_outcome
#   pacta/pacta/models.py:50    EscrowPolicy.dispute_bond_ratio=Decimal("0.20") §5.3
#   pacta/pacta/models.py:101/142/157/170  EscrowJob/DisputeClaim/ArbitrationVote/Outcome
#   tamga/tools/dispute_pointer_verify.py:35  verify() (+:23 MIN_BOND_PCT, :22 SUPPORTED)
#   ajan-borsasi/borsa_core.py:176   complete_work (AT-080-zincirinin-devamı)
#   tamga/tamga_attest_verify.py:64   ecrecover_to_pub (gerçek-EIP-191)
#
# BAĞLAMA-HİKÂYESİ (dürüst-ve-gerçek): Ajan-Borsası'da-tamamlanan-bir-işe
# (AT-080-disiplini: gerçek-receipt_hash + gerçek-x402/v1-imzası) alıcı-itiraz-eder
# — "delivered:no" (scrape-boş-döndü). RFC-010-hâlâ-GREEN'dir (mutabakat-kanıtı),
# ama-RFC-011-çelişkiyi-yakalar-ve-İNDETERMİNE-verir (insan/hakem-gerekir). Sonra
# Pacta'nın-gerçek-Tier3-motoru-Schelling-oylamasıyla-karar-verir-ve-kayıt
# status:resolved'a-döner → GREEN. Tamga-hakem-DEĞİL-algılayıcı+yönlendiricidir.
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-Pacta-modülü: Tier3+modeller-gerçek-yoldan + bond-kaynağı-paritesi
#   2) GERÇEK-RFC-010-dikiş: Ajan-Borsası receipt_hash + gerçek-x402/v1 (STOCK-yol)
#   3) ÇELİŞKİ: alıcının-gerçek-imzalı-delivered:no'su → İNDETERMİNE-rc12 (ANA-İLKE)
#   4) CANLI-PACTA-BAĞLANTISI: gerçek-Tier3-oylaması → resolved → GREEN
#   5) NEGATİF-1: çelişki-var-ama-arbitration-YOK → RED rc9
#   6) NEGATİF-2: bond <%20 → RED rc10 (Pacta-§5.3-griefing-kapısı)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/PACTA-DISPUTE/$(date +%F)/at084.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-084: Pacta anlaşmazlık-yüzü — RFC-011 dispute-pointer → canlı hakemlik"

BOLSA="/home/gokun/projects/00_TAMGA-MESH/ajan-borsasi/borsa_core.py"
PACTA="/home/gokun/projects/00_TAMGA-MESH/pacta"
if [ ! -f "$BOLSA" ] || [ ! -f "$PACTA/pacta/verification/tier3_arbitration.py" ]; then
  note "[SKIP] AT-084: Ajan-Borsası-veya-Pacta-kodu-bu-makinede-değil (CI) —"
  note "       canlı-hakemlik-bağı-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: gerçek-imza-üretilemez-AMA-RED-boyanmaz.
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-084: eth_keys-kütüphanesi-yok —"
  note "       gerçek-EIP-191-imzası-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$BOLSA" "$PACTA" "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sys, tempfile
from decimal import Decimal
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOLLAR (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/ajan-borsasi")
sys.path.insert(0, sys.argv[2])                    # pacta-paketi

LOG = sys.argv[3]                                  # kanıt-dizini (shell-değişkeni-değil)

import borsa_core as B
import settlement_bind_verify as SB
import tamga_attest_verify as TAV
from dispute_pointer_verify import verify as dp_verify, MIN_BOND_PCT
from eth_keys import keys

from pacta.models import (EscrowJob, EscrowPolicy, DisputeClaim, ArbitrationVote,
                          ArbitrationOutcome)
from pacta.verification.tier3_arbitration import Tier3ArbitrationEngine

# --- yardımcı: §3b-x402/v1-imza-sözleşmesi (z=raw-sha256, EIP-191-öneksiz, 65-byte)
def eip191_imzala(privkey, govde):
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
    s = privkey.sign_msg_hash(bytes.fromhex(d))
    return (s.r.to_bytes(32, "big") + s.s.to_bytes(32, "big")
            + bytes([27 + s.v])).hex(), d

# --- 1) GERÇEK-Pacta-modülü: Tier3-ve-modeller-gerçek-yoldan + bond-kaynağı-paritesi
src3 = inspect.getsource(Tier3ArbitrationEngine.calculate_schelling_outcome)
assert "schelling" in src3.lower() or "buyer_favored" in src3, "Tier3-gerçek-değil"
policy = EscrowPolicy()                            # §5.3-%20-itiraz-teminatı
assert policy.dispute_bond_ratio == Decimal("0.20")
assert float(policy.dispute_bond_ratio) == MIN_BOND_PCT, \
    "gate'in-bond-eşiği-Pacta'nın-gerçek-policy'sinden-gelmiyor"
job = EscrowJob(buyer_address="0xbuyer", seller_address="0xseller",
                amount_usdc="100.00")              # gerçek-Decimal-muhasebesi
assert job.calculate_fee() == Decimal("0.750000")  # 75-bps
assert job.net_seller_amount() == Decimal("99.250000")
# Pacta-§5.2-atfı-gerçek (önceden-var-bağ — AT-073-9.-kontrolün-canlı-hâli)
kagit = open(os.path.join(sys.argv[2], "PROJE_KAGIDI.md"), encoding="utf-8").read()
assert "TamgaVerifier.verify" in kagit and "TamgaReceipt" in kagit, "Pacta→Tamga-atfı-yok"
print("  GERÇEK-Pacta: Tier3+modeller-yüklü; bond 0.20-policynin-gerçek-Decimalsı")
print("    EscrowJob-Decimal-muhasebesi: fee=0.750000, net-seller=99.250000")

# --- 2) GERÇEK-RFC-010-dikiş: Ajan-Borsası-akışı + gerçek-x402/v1 (STOCK-yol)
assert "ecrecover_to_pub" in inspect.getsource(SB._claim_signer), \
    "_claim_signer-gerçek-ecrecover'ı-çağırmıyor (STUB-var)"
TMP = tempfile.mkdtemp(prefix="at084-")
DBP = os.path.join(TMP, "borsa.sqlite")            # asıl-borsayı-BOZMAYIZ
ONCEKI = hashlib.sha256(b'{"urun":"RepriceAI-v3","dogrulandi":true}').hexdigest()
AGENT = "0x1a642f0e3c3af545e7acbd38b07251b3990914f1"
B.list_agent(AGENT, "RepriceAI", "repricing", 0.01, ONCEKI, db=DBP)
BUYER_KEY = keys.PrivateKey(bytes.fromhex("7a" * 31 + "01"))   # test-only-anahtar
BUYER = BUYER_KEY.public_key.to_address()
SELLER = AGENT
bid = B.place_bid(AGENT, BUYER, 0.05,
                  json.dumps({"is": "scrape-51", "format": "csv"}),
                  "nonce-at084-1", db=DBP)
match = B.match_bid(bid.bid_id, db=DBP)
assert match is not None, "eşleşme-olmalı"
RECEIPT = {"kind": "ChargeReceipt", "match_id": match.match_id,
           "bid_id": match.bid_id, "agent_id": match.agent_id, "buyer": BUYER,
           "amount": match.amount, "work_spec": bid.work_spec,
           "result": {"scraped_rows": 51, "status": "ok"},
           "completed_at": "2026-09-30T12:00:00Z"}
receipt_hash = hashlib.sha256(
    json.dumps(RECEIPT, sort_keys=True).encode()).hexdigest()
done = B.complete_work(match.match_id, receipt_hash, db=DBP)
assert done.work_done is True and done.receipt_hash == receipt_hash
PID = f"BORS-{match.match_id}"
govde = {"buyerAddress": BUYER, "sellerAddress": SELLER, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": receipt_hash}}
sig_hex, _ = eip191_imzala(BUYER_KEY, govde)
assert TAV.ecrecover_to_pub(
    hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest(),
    sig_hex).lower() == BUYER.lower(), "gerçek-imza-adrese-çözümlenmedi"
charge = {"seq": 84, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": receipt_hash},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": receipt_hash},
                              "payer": BUYER, "payee": SELLER,
                              "verified_at": "2026-09-30T12:00:00Z"}}
claim = dict(govde); claim["signature"] = sig_hex
r010 = SB.verify(charge, claim)
assert r010["verdict"] == "GREEN" and all(r010["checks"].values()), \
    f"RFC-010-GREEN-beklendi: {r010}"
print(f"  RFC-010-GERÇEK-GREEN: receipt_hash={receipt_hash[:20]}… (stock-ecrecover)")

# --- 3) ÇELİŞKİ: alıcının-gerçek-imzalı-delivered:no-iddiası → İNDETERMİNE-rc12
# holistis-D-017'nin-boşluğu: satıcı-teslim-etti-diyor (RFC-010-GREEN), alıcı-
# teslim-OLMADI-diyor (gerçek-ikinci-imza). İkisi-de-imza-geçerli → attribution,
# not-truth. Karşı-iddia-kanıtı-gerçek-boş-scrape-logudur.
KANIT = {"job_id": match.match_id, "scraped_rows": 0, "error": "source_empty",
         "buyer_log": "2026-09-30T12:01:00Z veri-dönmedi", "delivered": False}
kanit_hash = hashlib.sha256(json.dumps(KANIT, sort_keys=True).encode()).hexdigest()
karsi_govde = {"buyerAddress": BUYER, "job_id": match.match_id,
               "delivered": False, "evidence_hash": kanit_hash}
karsi_sig, _ = eip191_imzala(BUYER_KEY, karsi_govde)
assert TAV.ecrecover_to_pub(
    hashlib.sha256(json.dumps(karsi_govde, sort_keys=True).encode()).hexdigest(),
    karsi_sig).lower() == BUYER.lower(), "karşı-iddia-imzası-adrese-çözümlenmedi"
# şartlar-özü: gerçek-escrow-şartlarının-sha256'ı (Pacta-EscrowJob'dan)
terms = {"job_id": job.job_id, "buyer": BUYER, "seller": SELLER,
         "amount_usdc": str(job.amount_usdc), "service": "scrape-51",
         "dispute_bond_ratio": str(policy.dispute_bond_ratio)}
terms_hash = hashlib.sha256(json.dumps(terms, sort_keys=True).encode()).hexdigest()
# bond-Pacta'nın-gerçek-policynin-Decimalsından (uydurma-değil): 100*0.20=20.00
bond_usdc = (job.amount_usdc * policy.dispute_bond_ratio).quantize(Decimal("0.000001"))
dp = {"status": "contradiction",
      "counter_claim": {"buyer_signed": True, "delivered": False,
                        "evidence_hash": {"alg": "sha256", "hex": kanit_hash},
                        # additive-kanıt-alanı (RFC-011-§2'nin-kendisi-additive-der;
                        # gate-bilinmeyen-anahtarları-görmez) — imza-GERÇEK-üretilidi
                        "buyer_signature_hex": karsi_sig},
      "arbitration": {"protocol": "pacta/v1", "case_ref": "",
                      "terms_hash": terms_hash},
      "bond_pct": float(policy.dispute_bond_ratio)}
charge_dp = json.loads(json.dumps(charge)); charge_dp["dispute_pointer"] = dp
rdp = dp_verify(charge_dp)
assert rdp["verdict"] == "İNDETERMİNE" and rdp["reason_code"] == 12, \
    f"çelişki-İNDETERMİNE-rc12-beklendi: {rdp}"
# ANA-İLKE (RFC-011-§3): RFC-010-hâlâ-GREEN — GREEN "iyi-teslimat"-DEMEZ
r010b = SB.verify(charge_dp, claim)
assert r010b["verdict"] == "GREEN", \
    f"RFC-010-additive-dispute_pointer'la-bozulmamalı: {r010b}"
print("  ÇELİŞKİ: alıcı-gerçek-imzalı-delivered:no → İNDETERMİNE rc12")
print("    ANA-İLKE: RFC-010-GREEN-kaldı — GREEN 'iyi-teslimat'-değil-'itiraz-yok'")

# --- 4) CANLI-PACTA-BAĞLANTISI: gerçek-Tier3-Schelling-oylaması → resolved → GREEN
# (a) gerçek-DisputeClaim: bond-policynin-%20'si-gerçek-Decimalsı
dispute = DisputeClaim(job_id=job.job_id, claimant_address=BUYER,
                       bond_amount_usdc=bond_usdc,
                       reason="delivered:no — scrape-boş-döndü",
                       evidence_hash=kanit_hash)
assert dispute.bond_amount_usdc == Decimal("20.000000"), \
    f"bond-gerçek-policynin-çarpanından-gelmeli: {dispute.bond_amount_usdc}"
# (b) gerçek-Schelling-oylaması: 5-hakem, 3-alıcı-tarafı → çoğunluk
oylar = []
for i, favor in enumerate((True, True, True, False, False)):
    gerekce = (f"source_empty-logu-ve-önceki-51/51-geçmişine-zıt; "
               f"hakem-{i}-kanıt-inceledi")
    oylar.append(ArbitrationVote(
        arbitrator_address=f"0xarb{i}", vote_favor_buyer=favor,
        staked_amount_pacta="1000",
        rationale_hash=hashlib.sha256(gerekce.encode()).hexdigest()))
bf, oduller, cezalar = Tier3ArbitrationEngine.calculate_schelling_outcome(
    oylar, dispute.bond_amount_usdc, job.amount_usdc)
assert bf is True, "çoğunluk-alıcı-tarafı-olmalı (3/5)"
assert len(oduller) == 3 and len(cezalar) == 2, "oy-dağılımı-yanlış"
# gerçek-Decimal-matematiği: ödül-havuzu=seller_collateral*0.20=20.00/3 → 6.666667
assert all(v == Decimal("6.666667") for v in oduller.values()), \
    f"ödül-bölüşümü-yanlış: {oduller}"
# quadratic-slashing: (2/5)²*1000*0.1 = 16.000000 (azınlık-cezası-gerçek)
assert all(v == Decimal("16.000000") for v in cezalar.values()), \
    f"ceza-yanlış: {cezalar}"
out = ArbitrationOutcome(dispute_id=dispute.dispute_id, job_id=job.job_id,
                         buyer_favored=bf, votes_for_buyer=3, votes_for_seller=2,
                         slashed_seller_bond_usdc=sum(cezalar.values()),
                         refunded_to_buyer_usdc=job.amount_usdc,
                         paid_to_seller_usdc=Decimal("0.000000"),
                         arbitrator_rewards=oduller)
# (c) çözüm-charge'a-yansır: status-resolved + case_ref-doldu → GREEN
charge_res = json.loads(json.dumps(charge_dp))
charge_res["dispute_pointer"]["status"] = "resolved"
charge_res["dispute_pointer"]["arbitration"]["case_ref"] = dispute.dispute_id
rres = dp_verify(charge_res)
assert rres["verdict"] == "GREEN" and rres["reason_code"] == 0, \
    f"resolved-GREEN-beklendi: {rres}"
print(f"  CANLI-PACTA: Tier3-Schelling buyer_favored=True (3/5); "
      f"ödül=6.666667×3, ceza=16.000000×2")
print(f"    case_ref={dispute.dispute_id[:8]}… → status:resolved → GREEN")
print("    RFC-010-pacta/v1-yönlendirmesi-GERÇEK-bir-motorca-çözüldü (AT-073'ün-borcu)")

# --- kanıt-fixture'ı-kalıcı-la
FX = os.path.join(os.path.dirname(LOG), "at084-pacta-canli.json")
json.dump({"test": "AT-084", "rfc": "RFC-011→Pacta/v1",
           "match_id": match.match_id, "payment_id": PID,
           "receipt_hash": receipt_hash, "buyer": BUYER, "seller": SELLER,
           "counter_claim": KANIT, "counter_evidence_hash": kanit_hash,
           "terms_hash": terms_hash, "bond_usdc": str(bond_usdc),
           "dispute_id": dispute.dispute_id, "buyer_favored": bf,
           "rewards": {k: str(v) for k, v in oduller.items()},
           "slashes": {k: str(v) for k, v in cezalar.items()},
           "charge_resolved": charge_res, "claim": claim,
           "verdict_rfc010": r010b["verdict"],
           "verdict_dispute_resolved": rres["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: çelişki-var-ama-arbitration-YOK → RED rc9 (yönlendirme-kayıp)
dpN1 = json.loads(json.dumps(dp)); del dpN1["arbitration"]
cN1 = json.loads(json.dumps(charge)); cN1["dispute_pointer"] = dpN1
rN1 = dp_verify(cN1)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 9, \
    f"arbitration-yok-RED-rc9-beklendi: {rN1}"
print("  çelişki-+arbitration-yok → RED rc9 (yönlendirme-kaybolamaz)")

# --- 6) NEGATİF-2: bond <%20 (griefing-kapısı) → RED rc10
dpN2 = json.loads(json.dumps(dp)); dpN2["bond_pct"] = 0.10
cN2 = json.loads(json.dumps(charge)); cN2["dispute_pointer"] = dpN2
rN2 = dp_verify(cN2)
assert rN2["verdict"] == "RED" and rN2["reason_code"] == 10, \
    f"düşük-bond-RED-rc10-beklendi: {rN2}"
print("  bond %10 < %20 → RED rc10 (Pacta-§5.3-griefing-önlenir)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Pacta-anlaşmazlık-yüzü-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-084: Pacta anlaşmazlık-yüzü (RFC-011 → canlı hakemlik)"
[[ $FAIL -eq 0 ]]
