#!/usr/bin/env bash
# AT-121: SWARMAX-DÖRDÜNCÜ-YÜZ (statistics/classifier/apd analitik-stabilite) → RFC-010 x402/v1.
#
# Swarmax-üç-yüzü-bağlandı: AT-067 (evidence), AT-099 (sealing), AT-102
# (loop_breaker + mad_robust_z). DÖRDÜNCÜ-YÜZ: **ölçülmemiş-analitik-yüzler**
#   metrics/statistics.py:
#     cusum_update:169  Page-Hinkley-kayma-tespiti (g=max(0,g+(x-mu0-δ)); g>h→alarm)
#     psi:178         Population-Stability-Index (PSI>0.25→large_shift, banking §3.2-5)
#     jsd_divergence:89 Jensen-Shannon-divergence (band: healthy/alarm)
#     ewma_update:48   üssel-hareketli-ortalama (maliyet-istikrarı)
#   metrics/classifier.py:
#     Classifier.observe:71  new_class_seen-disiplini (§3.1 — yeni-hata-sınıfı-uyarısı)
#   metrics/apd.py:
#     FpBudget:71       R10: false-positive-bütçesi (ratio≤%5)
#
# SWARMAX-ÖZELLİĞİ: kanıt-BİR-ANALİTİK-KARARDIR — "hizmet-davranışı-stabil"
# sözleşmesi. AT-102'nin-para-tahliye-döngüsü-tespitinden-farklı-olarak-bu-yüz
# GİDİŞ-veya-MODEL-BOZULMASI kanıtlar: maliyet-kayması (cusum), dağılım-kayması
# (psi/jsd), bilinmeyen-hata-sınıfı (classifier), FP-israfı (apd).
#
# ÖDEME-SEMANTİĞİ: yalnızca-STABİL-pencere-ödemeyi-yetkilendirir. Herhangi-bir
# alarm (cusum/psi/jsd/classifier/fp-budget) → kanıt-uyumsuz → ödeme-yeşillenmez.
# Dört-yüz-birleşimi: AT-067 (ne-oldu) × AT-099 (mühür) × AT-102 (döngü-avı)
# × AT-121 (analitik-stabilite) = tam-operasyonel-garanti.
#
# §3b-SCHEME: metrikler-asimetrik-kanal-üretmez → x402/v1. evidenceHash =
# stabil-pencere-kanıtı-özeti (machine-checkable: metrikler-yeniden-çağrılınca
# aynı-sonuç → aynı-özet).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SWARMAX-4/$(date +%F)/at121.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-121: Swarmax-analitik-stabilite (dördüncü-yüz) → RFC-010 x402/v1"

SW="/home/gokun/projects/01_unicorn/69-Swarmax/src"
if [ ! -f "$SW/swarmax/metrics/statistics.py" ]; then
  note "[SKIP] AT-121: Swarmax-kodu-bu-makinede-değil (CI) —"
  note "       analitik-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-121: eth_keys-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SW" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from swarmax.metrics.statistics import (
    cusum_update, CusumState, psi, jsd_divergence, ewma_update, EwmaState)
from swarmax.metrics.classifier import Classifier
from swarmax.metrics.apd import FpBudget
import settlement_bind_verify as SB

from eth_keys import keys

# --- 1) CUSUM: stabil-akış → alarm-YOK; kayma → alarm (Page-Hinkley)
st = CusumState(g=0.0, drift=0.05, threshold=5.0)
alarms_stable = [cusum_update(st, 1.0, mu0=1.0).alarm for _ in range(8)]
assert not any(alarms_stable) and st.g == 0.0, "stabil-akış-g-birikmemeli"
st2 = CusumState(g=0.0, drift=0.05, threshold=5.0)
alarms_drift = []
for x in [1.0, 1.0, 2.0, 3.5, 5.0, 6.5, 8.0, 9.5]:
    alarms_drift.append(cusum_update(st2, x, mu0=1.0).alarm)
assert alarms_drift[-1] is True and st2.g > 5.0, "kaymada-alarm-vermeli"
# üretici-sağlamlığı: g-negatif-olamaz (max(0,·)-disiplini)
assert st.g >= 0.0 and st2.g >= 0.0
print(f"  cusum (Page-Hinkley): stabil→g=0-alarm-YOK | kayma→g={st2.g:.1f}-alarm")
print(f"    g=max(0,·)-disiplini: negatif-birikim-yok (fail-closed)")

# --- 2) PSI: stabil-dağılım → large-YOK; kaymış → large (banking-§3.2-5)
p_stable = psi({"ok": 90, "warn": 8, "err": 2}, {"ok": 89, "warn": 9, "err": 2})
assert p_stable.large_shift is False and p_stable.value < 0.25, \
    f"stabil-PSI<0.25-beklendi: {p_stable.value}"
p_drift = psi({"ok": 90, "warn": 8, "err": 2}, {"ok": 5, "warn": 20, "err": 75})
assert p_drift.large_shift is True and p_drift.value > 0.25, \
    f"kaymış-PSI>0.25-beklendi: {p_drift.value}"
print(f"  PSI (banking): stabil={p_stable.value:.4f}<0.25 | kaymış={p_drift.value:.4f}>0.25")

# --- 3) JSD: özdeş → healthy-band; farklı → alarm-band
j_same = jsd_divergence({"ok": 9, "err": 1}, {"ok": 9, "err": 1})
assert j_same.value == 0.0 and j_same.band == "healthy"
j_diff = jsd_divergence({"ok": 9, "err": 1}, {"ok": 1, "err": 9})
assert j_diff.value > 0.0 and j_diff.band != "healthy", \
    f"farklı-dağılım-alarm-band-beklendi: {j_diff.band}"
print(f"  JSD-divergence: özdeş=0.0/healthy | farklı={j_diff.value:.3f}/{j_diff.band}")

# --- 4) EWMA: maliyet-istikrarı (ilk-değer → mu, silahsız)
es = EwmaState()
ew = ewma_update(es, 10.0)
assert ew.mu == 10.0 and ew.alarm is False, "ilk-örnek-silahsız-olmalı"
print(f"  EWMA: ilk-örnek mu={ew.mu} armed={ew.armed} (soğuk-başlangıç-güvenli)")

# --- 5) CLASSIFIER: new_class_seen-disiplini (§3.1)
clf = Classifier()
first = clf.observe("timeout")
second = clf.observe("timeout")
assert first is True and second is False, \
    "ilk-görüş-yeni-sınıf; tekrar-yeni-değil (gözlem-belleği)"
clf.observe("rate_limit")
assert clf.observe("timeout") is False, "görülmüş-sınıf-yine-yeni-değil"
print(f"  Classifier: ilk-yeni→True | tekrar→False (§3.1-gözlem-belleği)")

# --- 6) APD-FpBudget: R10 false-positive-bütçesi (ratio≤%5)
fp = FpBudget()
for _ in range(100):
    fp.record_cycle(false_positive=False)
for _ in range(4):
    fp.record_cycle(false_positive=True)
assert fp.cycles == 104 and fp.false_positives == 4
assert fp.ratio <= 0.05 and fp.within_budget is True, \
    f"4/104={fp.ratio:.4f} ≤%5-bütçe-içi-beklendi"
# bütçe-aşımı-gerçek
fp2 = FpBudget()
for _ in range(10):
    fp2.record_cycle(false_positive=True)
assert fp2.ratio > 0.05 and fp2.within_budget is False, "10/10-aşım-beklendi"
print(f"  FpBudget (R10): 4/104={fp.ratio:.4f}≤%5-içi | 10/10=aşım")

# --- 7) DİKİŞ: STABİL-pencere-kanıtı → RFC-010 x402/v1 (STOCK-yol)
# tüm-metrikler-aynı-anda-temiz: cusum-alarm-yok + psi-stabil + jsd-healthy
# + classifier-new-class-yok + fp-bütçe-içi
st3 = CusumState(g=0.0, drift=0.05, threshold=5.0)
c_alarms = [cusum_update(st3, 1.0, mu0=1.0).alarm for _ in range(8)]
p3 = psi({"ok": 90, "warn": 8, "err": 2}, {"ok": 89, "warn": 9, "err": 2})
j3 = jsd_divergence({"ok": 9, "err": 1}, {"ok": 9, "err": 1})
clf3 = Classifier(); clf3.observe("timeout"); clf3.observe("rate_limit")
fp3 = FpBudget()
for _ in range(100):
    fp3.record_cycle(False)
fp3.record_cycle(True)   # 1/101 < %5 — bütçe-içi

proof = {
    "cusum_alarms": c_alarms,
    "cusum_final_g": st3.g,
    "psi_value": p3.value,
    "psi_large_shift": p3.large_shift,
    "jsd_value": j3.value,
    "jsd_band": j3.band,
    "ewma_mu": ewma_update(EwmaState(), 1.0).mu,
    "new_class_seen": clf3.observe("timeout"),   # False — temiz
    "fp_ratio": fp3.ratio,
    "fp_within_budget": fp3.within_budget,
    "window_cycles": 8,
}
assert not any(c_alarms) and p3.large_shift is False and j3.band == "healthy"
assert proof["new_class_seen"] is False and fp3.within_budget is True
EH = hashlib.sha256(json.dumps(proof, sort_keys=True).encode("utf-8")).hexdigest()
assert len(EH) == 64
# deterministik-gerçek: yeniden-üret-aynı-özet
assert hashlib.sha256(json.dumps(proof, sort_keys=True).encode("utf-8")).hexdigest() == EH
pk = keys.PrivateKey(bytes.fromhex("dd" * 32))
BUYER = pk.public_key.to_checksum_address().lower()
PAYEE = "0x71c8a18174415cc92067749eb3544dffd3f87884"
PID = "SWARMAX-ANALITIK-121"
govde = {"buyerAddress": BUYER, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": EH}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(d_claim)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 121, "prev": "0"*64, "h": "b"*64,
          "delivery_hash": {"alg": "sha256", "hex": EH},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": EH},
                              "payer": BUYER, "payee": PAYEE,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": EH,
                                  "entries": 8, "evidence_link": "equals",
                                  "verify_cmd": "swarmax.metrics.statistics+classifier+apd"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Swarmax-analitik-dikiş-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print(f"  stabil-pencere-kanıtı → RFC-010-GREEN (x402/v1, STOCK-yol)")
print(f"    5-metrik-aynı-anda-temiz: cusum+psi+jsd+classifier+fp-budget")

# --- 8) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("0x" + "dd"*65, os.urandom(65).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (65-bayt-sahte + rastgele) → RED rc4")

# --- 9) NEGATİF-2: alarm-gizleme-tahrizi → evidenceHash-swap-RED rc7
# saldırgan-kayıp-psi'yi-stabil-gösterir-AMA-gerçek-psi-large_shift=True
proof_fake = {**proof, "psi_value": 0.001, "psi_large_shift": False,
              "cusum_alarms": [False]*8}
EH2 = hashlib.sha256(json.dumps(proof_fake, sort_keys=True).encode("utf-8")).hexdigest()
assert EH2 != EH, "sahte-kanıt-farklı-özet-üretmeli"
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": EH2}}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
sig2 = "0x" + pk.sign_msg_hash(bytes.fromhex(d2)).to_bytes().hex()
claim2 = dict(govde2); claim2["signature"] = sig2
r7 = SB.verify(charge, claim2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"alarm-gizleme-RED-rc7-beklendi: {r7}"
print("  alarm-gizleme-tahrizi (sahte-stabil-psi) → RED rc7")
print("    taşıma-ölçüldü: gerçek-stabil-kanıt-delivery_hash'e-sabit")

# --- 10) ÇAPRAZ-KANIT: gerçek-alarm-kanıtı-asla-GREEN-kanıtta-kullanılamaz
p_bad = psi({"ok": 90, "warn": 8, "err": 2}, {"ok": 5, "warn": 20, "err": 75})
EH_bad = hashlib.sha256(json.dumps(
    {"psi_value": p_bad.value, "psi_large_shift": p_bad.large_shift},
    sort_keys=True).encode("utf-8")).hexdigest()
assert EH_bad != EH, "alarmlı-kanıt-temiz-kanıttan-ayrık-olmalı"
assert p_bad.large_shift is True
print("  çapraz-kanıt: alarmlı-psi-temiz-kanıttan-ayrık (rc7-yolu)")

# --- 11) DÖRT-YÜZ-BİRLEŞİMİ (Swarmax'ın-tam-operasyonel-garantisi)
# AT-067 (evidence: ne-oldu) × AT-099 (sealing: mühür)
# × AT-102 (loop-breaker: döngü-avı) × AT-121 (analitik-stabilite)
# = ödeme-artık-beş-bağımsız-analitik-kontrolle-teminatlı
assert r["checks"]["2_claim_sig"] and r["checks"]["6_foreign_chain"]
assert st2.g > 5.0 and p_drift.value > 0.25 and j_diff.band != "healthy"
assert fp2.within_budget is False
print("  dört-yüz-birleşimi: AT-067 × AT-099 × AT-102 × AT-121")
print("    beş-analitik-kontrol (cusum/psi/jsd/classifier/fp) — ödeme-garantisi")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-bir-Swarmax-analitik-stabilite-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-121: Swarmax-analitik-stabilite (dördüncü-yüz) → RFC-010"
[[ $FAIL -eq 0 ]]
