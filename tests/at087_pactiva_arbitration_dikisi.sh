#!/usr/bin/env bash
# AT-087: PACTIVA-ARBITRATION → RFC-011-DİKİŞİ (C-sınıfı-derinleştirme — ikinci-yüz).
#
# AT-079-audit-ledger'ı-ödeme-kanalına-bağladı-AMA-arbitration.py-henüz-
# ÖLÇÜLMEMİŞTİ. Bu-test-o-ikinci-yüzü-ölçer: RFC-011'in-DIŞ-ÇÖZÜM-HEDEFİ.
#
# 22-37-Pactiva: pactiva_core/arbitration.py — GERÇEK-7-üyeli-bağımsız-tahkim:
#   create_dispute:16          — uyuşmazlık-açar + evidence_archive_hash-üretir
#   cast_juror_vote:67         — kör-oy + karesel-teminat (sqrt(stake))
#   resolve_dispute:119        — Schelling-konsensüsü + slashing-kesintisi
# Gerçek-çıktı: consensus_score + slashed_amounts + honest-flags (üretici-
# tarafı-sağlamlık — azınlık-jüri-kesilir-dürüst-jüri-kesilmez).
#
# RFC-011-BAĞLANTISI (Pacta-§5.3-üzere): Pactiva'nın-arbitration-modülü-
# dispute-pointer'ın-DIŞ-ÇÖZÜM-HEDEFİDİR. dispute_pointer_verify:
#   status:'contradiction' + counter_claim + arbitration{protocol,terms_hash}
#   + bond_pct ≥ %20 → İNDETERMİNE-rc12 (insan/hakem-gerekir — Tamga-hakem-DEĞİL)
#
# İKİNCİ-YÜZÜN-ASIL-KANITI: dispute-pointer'a-giren-her-değer-GERÇEK-Pactiva-
# çıktısıdır — terms_hash=create_dispute'in-gerçek-evidence_archive_hash'i;
# counter_claim'in-evidence_hash'i-aynı-özüt; resolved-durumu-gerçek
# resolve_dispute-outcome'una-bağlı. AT-079-ledger-üzerine-arbitration-bacağı.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-087/$(date +%F)/at087.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-087: Pactiva-arbitration → RFC-011 dispute-pointer dikişi"

PA="/home/gokun/projects/01_unicorn/22-37-Pactiva"
if [ ! -f "$PA/pactiva_core/arbitration.py" ] || [ ! -f "$PA/pactiva_core/math_models.py" ]; then
  note "[SKIP] AT-087: Pactiva-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz, SKIP-geçilir.
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-087: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$PA" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, math, os, sys, tempfile
from decimal import Decimal
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from pactiva_core import arbitration as AR
from pactiva_core.database import init_db
from pactiva_core.math_models import calculate_quadratic_jury_slashing
import settlement_bind_verify as SB
import dispute_pointer_verify as DP

# --- 0) GEÇİCİ-DB (asıl-pactiva.db'yi-BOZMAYIZ — yazma-bölgesi-izole)
TMP = tempfile.mkdtemp(prefix="at087-")
DBP = os.path.join(TMP, "pactiva-at087.db")
init_db(DBP)

# --- 1) GERÇEK-uyuşmazlık-üretimi: create_dispute → evidence_archive_hash
# evidence_archive_hash-GERÇEK-kör-delil-paketi-özütüdür (sha256, 64-hex)
EV = hashlib.sha256(json.dumps(
    {"shift": "SHIFT-AT087", "worker_claim": "8s-mesai-ödenmedi",
     "employer_claim": "mesai-6s-tamamlandı", "probe_rtt_m": 3.2,
     "clickwrap": "FSEK-5846"}, sort_keys=True).encode()).hexdigest()
assert len(EV) == 64
disp = AR.create_dispute("SHIFT-AT087", "INIT-AT087",
                         "ucret-anlasmazligi-8s-vs-6s", EV, db_path=DBP)
assert isinstance(disp["id"], str) and len(disp["id"]) == 36, \
    f"dispute-id-uuid36-beklendi: {disp['id']!r}"
assert disp["evidence_archive_hash"] == EV, "evidence-archive-hash-DB'ye-aynı-yazılmalı"
assert disp["resolution_status"] == "pending", "yeni-uyuşmazlık-pending-olmalı"
print(f"  Pactiva-create_dispute: id={disp['id'][:8]}… status={disp['resolution_status']}")
print(f"    evidence_archive_hash-üretildi: {EV[:24]}… (gerçek-sha256, 64-hex)")

# --- 2) GERÇEK-7-üyeli-jüri: kör-oylar + karesel-teminat (sqrt-stake)
# Schelling-dinamiği: 5-işçi-lehine(+1) / 2-işveren-lehine(-1). Karesel-ağırlık
# yüzünden azınlık büyük-teminatla-bile-kazanamaz (gerçek-oyun-teorisi)
SEED = [("J1", "worker_favor",   Decimal("1.0"),  Decimal("100")),
        ("J2", "worker_favor",   Decimal("1.0"),  Decimal("144")),
        ("J3", "employer_favor", Decimal("-1.0"), Decimal("400")),
        ("J4", "worker_favor",   Decimal("1.0"),  Decimal("121")),
        ("J5", "employer_favor", Decimal("-1.0"), Decimal("64")),
        ("J6", "worker_favor",   Decimal("1.0"),  Decimal("81")),
        ("J7", "worker_favor",   Decimal("1.0"),  Decimal("100"))]
votes_data = []
for jid, decision, val, stake in SEED:
    v = AR.cast_juror_vote(disp["id"], jid, decision, val, stake, db_path=DBP)
    votes_data.append({"juror_id": jid, "vote_value": val, "stake_amount": stake})
    # karesel-ağırlık-gerçek: sqrt(stake)-Decimal-2-basamak
    assert v["quadratic_vote_weight"] == Decimal(str(math.sqrt(float(stake)))).quantize(Decimal("0.01")), \
        f"karesel-ağırlık-sqrt(stake)-değil: {v['quadratic_vote_weight']}"
print("  7-jüri-kör-oyu-kütüklendi: karesel-ağırlıklar-sqrt(stake)-ile-uyumlu")

# --- 3) GERÇEK-Schelling-konsensüsü + slashing (üretici-tarafı-sağlamlık)
res = AR.resolve_dispute(disp["id"], votes_data, db_path=DBP)
assert res["juror_count"] == 7, "yedi-jüri-olmalı"
# gerçek-matematiğin-bağımsız-yinelemesi-ile-aynı-mı
cons, slashed, rewards = calculate_quadratic_jury_slashing(
    votes=[Decimal(str(v["vote_value"])) for v in votes_data],
    stakes=[Decimal(str(v["stake_amount"])) for v in votes_data])
assert res["consensus_score"] == cons, "resolve-matematiği-gerçek-fonksiyonla-aynı-olmalı"
# BAĞIMSIZ-yineleme: karesel-ağırlıklı-Schelling-skoru (sqrt(stake) × oy)
w_sum = sum(Decimal(str(v["vote_value"])) * Decimal(str(float(v["stake_amount"])**0.5))
            for v in votes_data)
tot = sum(Decimal(str(float(v["stake_amount"])**0.5)) for v in votes_data)
expect = (w_sum / tot).quantize(Decimal("0.01"))
assert expect == cons, f"Schelling-skoru-bağımsız-yinelemeyle-aynı-değil: {expect} != {cons}"
# GERÇEK-oyun-teorisi-kanıtı: 5/7-çoğunluk-+1-oyun-RAĞMEN-skor-0.50-barajının
# ALTINDA — çünkü-azınlık-J3-$400-teminatıyla-sqrt(400)=20-ağırlık-koyar-da
# karesel-ağırlık-çoğunluğun-saf-sayısını-boğar. Bu-Schelling'in-GERÇEK
# davranışıdır (sayı ≠ ağırlık); baraj-aşılamaz → split_settled.
assert cons < Decimal("0.50"), \
    "karesel-ağırlık-çoğunluğu-boğmalı (büyük-teminatlı-azınlık)"
assert res["resolution_status"] == "split_settled", \
    f"baraj-aşılamayınca-split_settled-beklendi: {res['resolution_status']}"
print(f"  resolve_dispute: outcome={res['resolution_status']} score={res['consensus_score']}")
print("    Schelling-gerçeği: 5/7-çoğunluk-+1-AMA-sqrt($400)-azınlık-skoru-boğdu")
print("      → karesel-ağırlık: sayı ≠ ağırlık (baraj-aşılmadı: split_settled)")
# slashing-gerçek: sapana-azınlık-jüri-kesilir, dürüst-jüri-kesilmez
honest_flags = [j["is_honest"] for j in res["juror_results"]]
assert honest_flags.count(False) > 0, "azınlık-jüriler-kesilmeli-Schelling'e-göre"
assert honest_flags.count(True) > 0, "dürüst-jüriler-kesilmemeli"
print(f"    slashing-gerçek: {honest_flags.count(False)}-azınlık-jüri-kesildi, "
      f"{honest_flags.count(True)}-dürüst-jüri-temiz")

# --- 3b) BARAJ-AŞILDIĞINDA-gerçek-zafer-yüzü (üretici-tarafı-tam-kapsam)
# Azınlığın-teminatını-küçült → skor-barajı-aşar → resolved_worker_favored.
# Aynı-dispute'de-yeni-oy-grubuyla-ikinci-gerçek-çözüm-ölçülür.
res2 = AR.resolve_dispute(disp["id"],
                          [{"juror_id": f"W{i}", "vote_value": Decimal("1.0"),
                            "stake_amount": Decimal("100")} for i in range(5)] +
                          [{"juror_id": f"E{i}", "vote_value": Decimal("-1.0"),
                            "stake_amount": Decimal("25")} for i in range(2)],
                          db_path=DBP)
assert res2["resolution_status"] == "resolved_worker_favored", \
    f"baraj-aşılınca-worker_favored-beklendi: {res2['resolution_status']}"
assert res2["consensus_score"] >= Decimal("0.50"), "baraj-aşılmalı"
print(f"    baraj-aşan-senaryo: {res2['resolution_status']} "
      f"(score={res2['consensus_score']} ≥ 0.50)")

# --- 4) DİKİŞ: RFC-010-charge (AT-079'la-aynı-kanal) + dispute-pointer
# x402/v1-gerçek-ecrecover (AT-075-disiplini — stub-YOK)
from eth_keys import keys
pk = keys.PrivateKey(bytes.fromhex("22"*32))
BUYER = pk.public_key.to_checksum_address().lower()
PID = "PACT-DISP-0087"
charge = {"seq": 87, "prev": "0"*64, "h": "d"*64,
          "delivery_hash": {"alg": "sha256", "hex": EV},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": EV},
                              "payer": BUYER, "payee": "0x3"*40,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": EV, "entries": 1,
                                  "evidence_link": "equals",
                                  "verify_cmd": "pactiva.audit_ledger + arbitration"}}
govde = {"buyerAddress": BUYER, "sellerAddress": "0x3"*40,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": EV}}
digest = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(digest)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

# RFC-010-GREEN-önkoşul-gerçek-ecrecover-ile (stock-yol, test-double-YOK)
r10 = SB.verify(charge, claim)
assert r10["verdict"] == "GREEN", f"RFC-010-önkoşul-GREEN-beklendi: {r10}"
assert r10["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r10["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  RFC-010-charge-GREEN (gerçek-ecrecover; evidence_link=equals ile-kanıt-bağlı)")

# --- 5) RFC-011-DIŞ-YÜZ: dispute-pointer → İNDETERMİNE-rc12
# terms_hash-GERÇEK-Pactiva-çıktısı: create_dispute'in-evidence_archive_hash'i.
# counter_claim: alıcı-teslim-edilmediğini-imzaladı (D-017-attribution-yüzü).
dp = {"status": "contradiction",
      "counter_claim": {"buyer_signed": True, "delivered": False,
                        "evidence_hash": {"alg": "sha256", "hex": EV}},
      "arbitration": {"protocol": "pacta/v1",
                      "case_ref": f"PACTA-{disp['id'][:8]}",
                      "terms_hash": EV},
      "bond_pct": 0.25}                      # Pacta-§5.3-griefing-engeli
charge_dp = json.loads(json.dumps(charge))
charge_dp["dispute_pointer"] = dp
r11 = DP.verify(charge_dp)
assert r11["verdict"] == "İNDETERMİNE" and r11["reason_code"] == 12, \
    f"çelişki-İNDETERMİNE-rc12-beklendi: {r11}"
assert r11["checks"].get("2_contradiction") is True, "counter-claim-algılanmadı"
assert r11["checks"].get("3_arbitration") is True, "yönlendirme-sağlam-değil"
assert r11["checks"].get("4_bond") is True, "bond-geçersiz"
print("  GERÇEK-Pactiva-uyuşmazlığı → dispute-pointer İNDETERMİNE rc12")
print("    (Tamga-hakem-DEĞİL: çelişkiyi-algılar + dışarı-yönlendirir)")
print(f"    terms_hash = gerçek-evidence_archive_hash ({EV[:16]}…)")

# ANA-İLKE-KANITI: RFC-010-GREEN ↔ dispute-İNDETERMİNE (AT-073'ün-dersi)
assert r10["verdict"] == "GREEN" and r11["verdict"] == "İNDETERMİNE", \
    "GREEN-'iyi-teslimat'-değil; çelişki-ayrı-bacakta-yaşar"
print("  ANA-İLKE: RFC-010-GREEN + dispute-İNDETERMİNE — 6/6 'iyi-teslimat' DEMEZ")

# --- 6) Çözülmüş-uyuşmazlık → GREEN rc0 (gerçek-arbitration-sonucuna-bağlı)
# resolve_dispute'ün-gerçek-çıktısı-resolution_status'e-bağlanır
charge_res = json.loads(json.dumps(charge))
charge_res["dispute_pointer"] = {
    "status": "resolved",
    "resolution_outcome": res["resolution_status"],
    "consensus_score": float(res["consensus_score"]),
    "arbitration": {"protocol": "pacta/v1",
                    "case_ref": f"PACTA-{disp['id'][:8]}",
                    "terms_hash": EV}}
r_res = DP.verify(charge_res)
assert r_res["verdict"] == "GREEN" and r_res["reason_code"] == 0, \
    f"resolved-GREEN-beklendi: {r_res}"
print(f"  status:'resolved' → GREEN rc0 (arbitration-gerçekten-bitti: {res['resolution_status']})")

# --- 7) NEGATİF-1: bond <%20 (Pacta-§5.3-griefing) → RED rc10
charge_low = json.loads(json.dumps(charge_dp))
charge_low["dispute_pointer"]["bond_pct"] = 0.10
r_low = DP.verify(charge_low)
assert r_low["verdict"] == "RED" and r_low["reason_code"] == 10, \
    f"düşük-bond-RED-rc10-beklendi: {r_low}"
print("  bond %10 < %20 → RED rc10 (griefing-ekonomisi-engellenir)")

# --- 8) NEGATİF-2: çelişki-var-ama-arbitration-yok → RED rc9
charge_noarb = json.loads(json.dumps(charge_dp))
charge_noarb["dispute_pointer"] = {k: v for k, v in dp.items() if k != "arbitration"}
r_na = DP.verify(charge_noarb)
assert r_na["verdict"] == "RED" and r_na["reason_code"] == 9, \
    f"arbitration-yok-RED-rc9-beklendi: {r_na}"
print("  çelişki + arbitration-yok → RED rc9 (yönlendirme-kaybolamaz)")

# --- 9) NEGATİF-3: terms_hash-çürük (64-hex-değil) → RED rc9
charge_badterms = json.loads(json.dumps(charge_dp))
charge_badterms["dispute_pointer"]["arbitration"]["terms_hash"] = "curuk-deger"
r_bt = DP.verify(charge_badterms)
assert r_bt["verdict"] == "RED" and r_bt["reason_code"] == 9, \
    f"çürük-terms_hash-RED-rc9-beklendi: {r_bt}"
print("  çürük-terms_hash (64-hex-değil) → RED rc9 (yapısal-bozukluk)")

# --- 10) PACTİVA/V1-ÖLÇÜMÜ: kendi-protokol-adı-artık-additive-listede
# Üçüncü-seçenek-yasak: bilinmeseydi-İNDETERMİNE-rc11-olurdu (sessiz-RED-yok).
# AT-087'nin-additive-isteği-Lead-tarafından-yerine-getirildi — artık-tanıdık-
# bir-protokol-olduğu-için-çelişki-düzgün-şekilde-rc12-ÜRETİLİR (üçüncü-seçenek-
# hala-geçerli: RED-değil-İNDETERMİNE — sadece-protokol-bilindiğinden-tanınır).
assert "pactiva/v1" in DP.SUPPORTED_PROTOCOLS, \
    "pactiva/v1-additive-listede-olmalı (Lead-ekledi)"
charge_pv = json.loads(json.dumps(charge_dp))
charge_pv["dispute_pointer"]["arbitration"]["protocol"] = "pactiva/v1"
r_pv = DP.verify(charge_pv)
assert r_pv["verdict"] == "İNDETERMİNE" and r_pv["reason_code"] == 12, \
    f"pactiva/v1-İNDETERMİNE-rc12-beklendi (artık-tanıdık-protokol): {r_pv}"
print("  protocol='pactiva/v1' → İNDETERMİNE rc12 (additive-listede-artık)")
print("    ADDITIVE-ALAN-KAPANDI: SUPPORTED_PROTOCOLS'e-Lead-ekledi")

# --- 11) MIN_BOND_PCT-sabiti + Pactiva'nın-gerçek-slash-oranı-tabandan-sert
assert DP.MIN_BOND_PCT == 0.20, "Pacta-§5.3-bond-%20-olmalı"
assert "pacta/v1" in DP.SUPPORTED_PROTOCOLS, "pacta/v1-destekli-olmalı"
_sig = inspect.signature(AR.resolve_dispute)
assert _sig.parameters["slash_rate"].default == Decimal("0.30"), \
    "varsayılan-slash-oranı-%30-olmalı"
assert Decimal("0.30") >= DP.MIN_BOND_PCT, \
    "Pactiva-slashing'i-Pacta-bond-tabanından-sert-olmalı"
print(f"  sabitler: MIN_BOND_PCT={DP.MIN_BOND_PCT} slash_rate=0.30 (≥ taban)")
print(f"    protokoller={DP.SUPPORTED_PROTOCOLS}")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-Pactiva-arbitration-RFC-011-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-087: Pactiva-arbitration → RFC-011"
[[ $FAIL -eq 0 ]]
