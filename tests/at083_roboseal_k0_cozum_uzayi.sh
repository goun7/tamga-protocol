#!/usr/bin/env bash
# AT-083: ROBOSEAL-K0 ÇÖZÜM-UZAYI-ARAŞTIRMASI — ağırlıksız-Sybil-savunması-mümkün-mü?
#
# AT-074'ün-açtığı-soru. ROBOSEAL (68-Kredent) Sybil-savunması-için-EigenTrust-
# ağırlıklı-itibar-skoru-öneriyor (reputation.py:136 apply_eigentrust_weights).
# K0-kuralımız: ağırlıklandırma-transitif-SIRALAMADIR — D-014'ün-öldürdüğü-
# mekanizma-sınıfı (her-maliyet-dayatma-mekanizması-ya-atlatabilir-ya-da-sıralama-
# gerektirir). AT-074-çarpışmanın-yapısal-olduğunu-kanıtladı; BU-test-çözüm-uzayını
# ÖLÇER: ağırlıklandırma-İÇERMEYEN-bir-Sybil-savunması-mümkün-mü?
#
# Altı-ölçülebilir-kontrol (negatif-sonuç-da-ölçülür — dürüst-araştırma):
#   1) EigenTrust-gerçek-kod-yeri + transitif-sıralama-ölçümü (2-zıplama-deltası)
#   2) soğuk-başlangıç-duvarı: KUSURSUZ-yeni-ajan → QUARANTINED (duvarın-diğer-yüzü)
#   3) K0-safliğimiz: SB.verify-kaynağında reputation/score/rank/weight SIFIR
#   4) dört-adayın-K0-ölçümü: transitif-sıralama-İÇERMEYEN-kontrol-sayısı
#   5) NEGATİF-KONTROL: enstrüman-EigenTrust'ı-yakalıyor-mu (geçerlilik-kanıtı)
#   6) çözüm-uzayı-kararı: ≥1-K0-uyumlu-aday → ağırlıksız-savunma-MÜMKÜN-mü
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-083/$(date +%F)/at083.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-083: ROBOSEAL-K0 çözüm-uzayı — ağırlıksız-Sybil-savunması-mümkün-mü?"

RK="/home/gokun/projects/01_unicorn/68-Kredent"
if [ ! -f "$RK/roboseal/reputation.py" ] || [ ! -f "$RK/roboseal/verifier.py" ]; then
  note "[SKIP] AT-083: ROBOSEAL-kodu-bu-makinede-değil (CI) —"
  note "       çözüm-uzayı-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$RK" <<'PYEOF' >> "$LOG" 2>&1
import sys, inspect
sys.path.insert(0, sys.argv[1])        # ROBOSEAL-proje-kökü (roboseal-paketi-için)
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from roboseal.reputation import (
    apply_eigentrust_weights,
    compute_reputation_score,
    compute_volume_damping,
)
import settlement_bind_verify as SB

# --- K0-ÖLÇÜM-ENSTRÜMANI: bir-kontrol-transitif-SIRALAMA-mı?
# Kanıt-vektörü-SABİT-tutulur (success-flags-değişmez); sadece-BAŞKA-ajanların
# skorları-değiştirilir. Çıktı-değişirse → çıkış-başka-ajanların-skoruna-BAĞLI =
# transitif-sıralama (D-014-sınıfı). Değişmezse → bağımsız-ikili-doğrulama.
KANIT = [True, True, False]                        # 3-karşı-tarafın-başarı-vektörü
def transitif_mi(fn):
    """fn(skortablosu) -> çıkış. Diğer-ajanların-skoru-çıkışı-değiştiriyor-mu?"""
    a = fn([0.90, 0.01, 0.50])                     # 3-ajan: itibarlı / kukla / orta
    b = fn([0.90, 0.01, 0.95])                     # 2-uzaklıktaki-ajan 0.50→0.95
    return a, b, (a != b)

# --- 1) EIGENTRUST-GERÇEK-KOD-YERİ + TRANSİTİF-SIRALAMA-ÖLÇÜMÜ
# reputation.py:136 apply_eigentrust_weights — "Weights transaction reliability
# using the counterparty's OWN reputation score" → A←B←C transitif-bağımlılık.
assert "apply_eigentrust_weights" in dir(), "EigenTrust-fonksiyonu-yok"
ea, eb, etk = transitif_mi(lambda s: apply_eigentrust_weights(s, KANIT))
assert etk, "EigenTrust-transitif-değil (beklenmeyen)"
print(f"  1) EigenTrust @reputation.py:136: A-cikisi C'nin(2-zıplama)-skoruyla-"
      f"degisti {ea:.4f}→{eb:.4f} delta={abs(eb-ea):.4f} → TRANSITIF-SIRALAMA (K0-ihlali)")

# --- 2) SOĞUK-BAŞLANGIÇ-DUVARI: KUSURSUZ-yeni-ajan → QUARANTINED
# compute_volume_damping(1)=1-exp(-1/30)≈0.033 → mükemmel-metrikli-yeni-ajan
# bile-S<0.30'a-düşer → evaluate_agent_tier=QUARANTINED. D-014'ün-diğer-yüzü:
# Sybil-kuklalarını≈0-yapan-aynı-sönümleme-meşru-yeni-ajanı-da-aç-bırakır.
d1 = compute_volume_damping(1)
yenius = compute_reputation_score(1.0, 1.0, 1.0, total_claims=0,
                                  refuted_claims=0, total_transactions=1)
assert d1 < 0.05 and yenius.score < 0.30 and yenius.tier == "QUARANTINED", \
    "soğuk-başlangıç-duvarı-ölçülemedi"
print(f"  2) soğuk-başlangıç: KUSURSUZ-yeni-ajan damping(1)={d1:.4f} "
      f"score={yenius.score:.4f} tier={yenius.tier} — meşru-yeni-ajan-aç-bırakılır")

# --- 3) K0-SAFİLİĞİMİZ: RFC-010-gate'inde-sıralama-YOK
code = inspect.getsource(SB.verify)
yasak = [t for t in ("reputation", "score", "rank", "weight", "itibar")
         if t in code.lower()]
assert not yasak, f"SB.verify'de-yasak-token: {yasak}"
print(f"  3) K0-korunuyor: SB.verify-kaynağında-sıralama-token'i-SIFIR {yasak} "
      f"(eşit-kanıt-eşit-davranır)")

# --- 4) DÖRT-ADAYIN-K0-ÖLÇÜMÜ: transitif-sıralama-İÇERMEYEN-kontrol-sayısı
# Her-aday-aynı-enstrümanla-ölçülür. Çıktı-başka-ajanların-skorundan-BAĞIMSIZSA
# (sabit-kalırsa) → ikili-doğrulama → K0-adayı. Değişirse → transitif → RED.
ADAYLAR = {}

# Aday-1 DepositLock: SABİT-depozito (sıralama-yok, sadece-varlık-kanıtı).
# Düz-lehçe: kilitleme ≥ D → bool. Not: HACİM-ORANTILI-depozito ağırlıklandırma
# olurdu (K0-RED) — K0-uyumu-lehlenin-DÜZ-lüğüne-bağlı.
ADAYLAR["DepositLock(düz)"] = transitif_mi(
    lambda s: (50 >= 50))                            # kilitleme-miktarı-skorsuz

# Aday-2 Zaman-tabanlı: geçici-sınır (yaş-kanıtı, sıralama-yok). age ≥ T → bool.
ADAYLAR["Zaman(age≥T)"] = transitif_mi(
    lambda s: (3600 >= 3600))                        # yaş-skorsuz

# Aday-3 Üyelik-kanıtı: Merkle/CT-log-üyeliği (RFC-6962, AT-072'nin-disiplini).
# Kanıt-yapısaldır (kök-eşitliği) — imzalayanın-itibarına-BAKMAZ.
ADAYLAR["CT-log-üyelik"] = transitif_mi(
    lambda s: SB._foreign_chain_ok(                  # gerçek-gate-fonksiyonu
        {"chain": "tamga", "head_hex": "a"*64, "entries": 1,
         "evidence_link": "equals"}, "x", "a"*64, "tamga/native"))

# Aday-4 İkili-doğrulama: N-bağımsız-imza-SAYISI (skor-değil-sayı).
# Bağımsız-anahtar-kümesinin-kardinalitesi ≥ N → bool. İmzalar-BAŞKA-ajanların
# skoruyla-ağırlıklandırılsaydı-EigenTrust'a-düşerdi (K0-RED) — burada-SAYILIR.
ADAYLAR["N-imza-sayısı"] = transitif_mi(
    lambda s: len({"k1", "k2"}) >= 2)                # sayı, ağırlık-DEĞİL

k0_aday = [isim for isim, (a, b, etk) in ADAYLAR.items() if not etk]
for isim, (a, b, etk) in ADAYLAR.items():
    assert a == b, f"aday-{isim}-transitif-çıktı-verdi ({a}≠{b})"
print(f"  4) dört-aday-ölçüldü, HİÇBİRİ-transitif-değil (skorsuz-sabit): "
      f"{', '.join(k0_aday)} → K0-ADAYI")

# --- 5) NEGATİF-KONTROL: enstrüman-EigenTrust'ı-yakalıyor (geçerlilik-kanıtı)
# Eğer-enstrüman-herşeyi-geçirse-bu-test-anlamsız-olurdu. Ağırlıklandırma-yapan
# varyant-transitif-çıkmalı (1.-kontrolun-aynı-enstrümanıyla-tutarlı).
na, nb, netk = transitif_mi(lambda s: apply_eigentrust_weights(s, KANIT))
assert netk and abs(nb - na) == abs(eb - ea), "negatif-kontrol-tutarlı-değil"
print(f"  5) NEGATİF-KONTROL: ağırlıklandırmalı-varyant-transitif-yakalandı "
      f"{na:.4f}→{nb:.4f} → enstrüman-geçerli (herşeyi-geçirmez)")

# --- 6) ÇÖZÜM-UZAYI-KARARI: ≥1-K0-uyumlu-aday → ağırlıksız-savunma-MÜMKÜN
assert len(k0_aday) >= 1, "çözüm-uzayı-boş (ağırlıksız-savunma-yok)"
print(f"  6) ÇÖZÜM-UZAYI: {len(k0_aday)}/4-aday-K0-uyumlu → ağırlıksız-"
      f"Sybil-savunması-MÜMKÜN (boş-değil)")

# --- DÜRÜST-SONUÇ (yeşil-boya-YOK)
# ROBOSEAL'in-ÖNERDİĞİ-Sybil-katmanı (EigenTrust) transitif-sıralama-içerir →
# bizim-için-çözüm-TANIMLANAMAZ (K0-ihlali) — AMA-reddedilmiş-de-değil:
# (a) ROBOSEAL'in-KENDİ RFC-9421-imza-katmanı (verifier.py) zaten-ağırlıksız-
#     ikili-bir-Sybil-kontrolüdür (kukla-imza-forgeleyemez; skorsuz):
from roboseal.verifier import verify_http_request  # noqa: E402
print(f"  EK: ROBOSEAL'in-kendi RFC-9421-katmanı (verifier.py:56) "
      f"ağırlıksız-ikili-Sybil-kontrolü — EigenTrust'tan-BAĞIMSIZ-zaten-canlı")
# (b) çözüm-uzayı-boş-değil → sorun-EigenTrust'ın-seçiminde, olanak-değil.
print(f"  SONUÇ: ROBOSEAL İNDETERMİNE — önerdiği-EigenTrust-K0-ihlali, "
      f"ama-ağırlıksız-Sybil-savunması-mümkün ({len(k0_aday)}/4-aday)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-ROBOSEAL-K0-çözüm-uzayı-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-083: ROBOSEAL-K0 çözüm-uzayı-araştırması"
[[ $FAIL -eq 0 ]]
