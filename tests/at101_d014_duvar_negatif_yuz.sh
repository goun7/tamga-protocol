#!/usr/bin/env bash
# AT-101: D-014-DUVARININ-NEGATİF-YÜZÜ — ağ-boyutu + soğuk-başlangıç (çift-taraflı-ısırık).
#
# AT-083/092/095 duvarın-POZİTİF-yönünü-kanıtladı: DÜZ/İKİLİ-üyelik-K0'ya-uyumlu,
# ağırlıklı-varyant-transitif → RED. AMA-duvarın-MALİYETİ-ölçülmedi:
# "dünya-da-ağırlıklandırma-yapan-gerçek-sistemler-K0'ı-ihlal-ediyor-mu?"
#
# BU-TEST-ÜÇ-NEGATİF-ÖLÇÜM-YAPAR (duvarın-kendisi-değil-gerçek-davranış):
#   1) AĞ-BOYUTU-ŞERİDİ: transitif-ihlal-3→6→12-ajanda-nasıl-değişir?
#      (eğilim: azalır-AMA-hiç-sıfır-olmaz → duvar-ağ-büyüklüğünden-bağımsız)
#   2) SOĞUK-BAŞLANGIÇ-AÇLIĞI: ağırlıklı-sistemde-KUSURSUZ-yeni-ajan
#      damping(1)=0.0328 → QUARANTINED (AT-083-ölçümüyle-tutarlı);
#      ağırlıksız-sistemde-aynı-ajan-hemen-kabul
#   3) SIRALAMA-OYNANABİLİRLİĞİ: saldırgan-kuklanın-İTİBARINI-değiştirince
#      A'nın-güvenilirliği-39.72%-kaydı (transitif-sıralama-DIŞARIDAN-oynanabilir)
#
# DUVARIN-ÇİFT-TARAFLI-ISIRIĞI (resmi-belgeleme):
#   FAYDA: ağırlıklandırma-Sybil-kuklalarını-≈0'a-düşürür (AT-083'ün-ölçümü)
#   MALİYET: aynı-sönümleme-meşru-yeni-ajanı-da-aç-bırakır (0.0328)
#   → K0-duvarı-bu-ikiyi-ayrı-tutar: DÜZ/İKİLİ-GREEN, sürekli-ağırlık-RED
#
# Üretim-kodu: roboseal/reputation.py (gerçek-EigenTrust + sönümleme).
# Enstrüman-testin-içinde (tools/*-DOKUNMA — AT-095'in-rc-kodları-korunur).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/D014-DUVAR/$(date +%F)/at101.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-101: D-014-duvarının-negatif-yüzü — ağ-boyutu + soğuk-başlangıç"

RK="/home/gokun/projects/01_unicorn/68-Kredent/roboseal"
if [ ! -f "$RK/reputation.py" ]; then
  note "[SKIP] AT-101: ROBOSEAL-kodu-bu-makinede-değil (CI) —"
  note "       duvar-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$RK" <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/01_unicorn/68-Kredent")
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from roboseal.reputation import (apply_eigentrust_weights,
                                 compute_reputation_score,
                                 compute_volume_damping)
import settlement_bind_verify as SB

# --- 0) K0-safliğimiz: RFC-010-gate'inde-sıralama-YOK (AT-083-aynı-kontrol)
import inspect
_code = inspect.getsource(SB.verify)
yasak = [t for t in ("reputation", "score", "rank", "weight", "itibar")
         if t in _code.lower()]
assert not yasak, f"SB.verify'de-yasak-token: {yasak}"
print("  0) K0-korunuyor: SB.verify-sıralama-token'i-SIFIR (eşit-kanıt-eşit-davranır)")

# --- 1) AĞ-BOYUTU-ŞERİDİ: transitif-ihlal-3→6→12-ajanda-nasıl-değişir?
# Kanıt-vektörü-SABİT (başarı-bayrakları-değişmez); SADECE-2-zıplama-uzaktaki
# ajanın-skoru-0.50→0.95. A'nın-çıkışı-değişirse-transitif (D-014-ihlali).
def transitif_delta(n):
    rep_lo = [0.90, 0.01] + [0.50] * (n - 2)   # A / kukla / orta-ajanlar
    rep_hi = list(rep_lo); rep_hi[-1] = 0.95    # uzak-ajan-yükseltilir
    flags = [True, False] + [True] * (n - 2)    # bayraklar-SABİT
    a = apply_eigentrust_weights(rep_lo, flags)
    b = apply_eigentrust_weights(rep_hi, flags)
    return a, b, abs(b - a)

sonuc = {}
for n in (3, 6, 12):
    a, b, d = transitif_delta(n)
    sonuc[n] = (a, b, d)
    assert a != b, f"n={n}: transitif-ihlal-beklendi (duvar-ağ-büyüdükçe-ölmez)"
    print(f"  1) ağ-boyutu-{n:2d}: A {a:.4f} → {b:.4f}  delta={d:.4f}  TRANSITIF")

# --- 2) DELTA-ŞERİDİ-MONOTON: ağ-büyüdükçe-tek-ajanın-etkisi-azalır-AMA-ölmez
d3, d6, d12 = sonuc[3][2], sonuc[6][2], sonuc[12][2]
assert d3 > d6 > d12, f"delta-şeridi-azalmalı: {d3} > {d6} > {d12}"
assert d12 > 0.0, "12-ajanda-bile-ihlal-sürüyor (duvar-ağ-boyutundan-bağımsız)"
print(f"  2) delta-şeridi: 3→{d3:.4f} > 6→{d6:.4f} > 12→{d12:.4f}")
print(f"     azalır-AMA-hiç-sıfır-olmaz → duvar-ağ-büyüklüğünden-bağımsız")

# --- 3) SOĞUK-BAŞLANGIÇ-AÇLIĞI: ağırlıklı-sistemde-KUSURSUZ-yeni-ajan
# compute_volume_damping(1)=1-exp(-1/30)≈0.033 → mükemmel-metrikli-yeni-ajan
# bile-S<0.30'a-düşer → QUARANTINED. AT-083'ün-0.0328-ölçümüyle-tutarlı.
d1 = compute_volume_damping(1)
yeni = compute_reputation_score(1.0, 1.0, 1.0, total_claims=0,
                                refuted_claims=0, total_transactions=1)
assert abs(d1 - 0.0328) < 0.0005, f"damping(1)-AT-083-tutarlı-değil: {d1:.4f}"
assert yeni.score < 0.30 and yeni.tier == "QUARANTINED", \
    f"yeni-ajan-aç-bırakılmalı: score={yeni.score:.4f} tier={yeni.tier}"
print(f"  3) soğuk-başlangıç: KUSURSUZ-yeni-ajan damping(1)={d1:.4f} "
      f"score={yeni.score:.4f} tier={yeni.tier}")
print(f"     AT-083-ölçümüyle-birebir-tutarlı (0.0328) — duvarın-maliyeti-sürüyor")

# --- 4) AĞIRLIKSIZ-KARŞILAŞTIRMA: aynı-ajan-hemen-kabul (duvarın-YOKLUĞU)
# K0-uyumlu-sistem-basit-başarı-oranıdır (sıralama-yok): mükemmel-ilk-işlem
# → tam-güven. Aynı-ajan-ağırlıklı-sistemde-0.0328'e-düşer (çift-taraflı-ısırık).
def agridiriz_basari(flags):
    return sum(flags) / len(flags) if flags else 0.0
kabul = agridiriz_basari([True])
assert kabul == 1.0, "ağırlıksız-sistemde-yeni-ajan-hemen-kabul-edilmeli"
print(f"  4) ağırlıksız-sistem: aynı-ajan tek-mükemmel-işlem → {kabul:.4f} (hemen-kabul)")
print(f"     → duvarın-çift-taraflı-ısırığı: ağırlıklı={yeni.score:.4f} vs "
      f"ağırlıksız={kabul:.4f} (aynı-ajan, {kabul/yeni.score:.1f}x-fark)")

# --- 5) SIRALAMA-OYNANABİLİRLİĞİ: saldıgan-kuklanın-itibarı-A'yı-oynatır
# B-başarısız (gerçek-durum). B'nin-itibarını-0.01→0.95-yapınca-A'nın-çıkışı
# 0.9929'dan-0.5957'ye-düşer → A'nın-KONUMU-başka-ajanların-skoruyla-oynanabilir.
flags_sab = [True, False, True]
v_saf = apply_eigentrust_weights([0.90, 0.01, 0.50], flags_sab)
v_syb = apply_eigentrust_weights([0.90, 0.95, 0.50], flags_sab)
delta_syb = abs(v_syb - v_saf)
assert delta_syb > 0.30, \
    f"Sybil-manipülasyon-büyük-olmalı: {v_saf:.4f}→{v_syb:.4f} delta={delta_syb:.4f}"
print(f"  5) sıralama-oynanabilirliği: B-itibarı-0.01→0.95 → A {v_saf:.4f}→"
      f"{v_syb:.4f} (delta {delta_syb:.4f})")
print(f"     transitif-sıralama-DIŞARIDAN-oynanabilir → K0'ın-ölüm-nedeni")

# --- 6) RFC-010-DİKİŞİ: DÜZ/İKİLİ-GREEN + ağırlıklı-RED (AT-095-deseni)
# DÜZ-üyelik-kanıtı: sabit-eşik-koşulları (derecesi-yok — sürekli-ağırlık-DİŞLİ)
# Ağırlıklı-kanıt: çıkışı-başka-ajanların-skoru-belirler → transitif → RED
from nacl.signing import SigningKey
from nacl.encoding import HexEncoder
MIN_SIGS = 3
anahtarlar = [SigningKey.generate() for _ in range(MIN_SIGS + 1)]
pub_uye = anahtarlar[0].verify_key.encode(encoder=HexEncoder).decode()
UYE_HEAD = "a" * 64    # AT-095'in-sabit-kafa-değeriyle-aynı-biçim

def duz_uyelik_kontrol(syb):
    """DÜZ/İKİLİ-üyelik: sigcount/v1 — N-bağımsız-anahtar (sıralama-yok)."""
    if not isinstance(syb, dict):
        return "RED", 13, "sybil_membership_malformed"
    sigs = syb.get("signer_pubkeys")
    if not (isinstance(sigs, list) and len({str(k) for k in sigs}) >= MIN_SIGS):
        return "RED", 16, "member_fails_duz_kosul: sigcount/v1"
    if not (isinstance(syb.get("head_hex"), str) and len(syb["head_hex"]) == 64):
        return "RED", 15, "log_head_invalid"
    if not (isinstance(syb.get("entries"), int) and syb["entries"] >= 1):
        return "RED", 15, "log_entries_invalid"
    if syb["head_hex"].lower() != UYE_HEAD:
        return "RED", 17, "log_head_mismatch"
    return "GREEN", 0, "üyelik-doğrulandı (DÜZ/İKİLİ: sigcount/v1)"

sigs = [k.verify_key.encode(encoder=HexEncoder).decode() for k in anahtarlar]
v6, rc6, _ = duz_uyelik_kontrol({"protocol": "sigcount/v1", "head_hex": UYE_HEAD,
                                 "entries": 4, "signer_pubkeys": sigs})
assert v6 == "GREEN" and rc6 == 0, f"DÜZ-üyelik-GREEN-beklendi: {v6}/{rc6}"

# ağırlıklı-varyant: üyeliği-skora-bağla → transitif-çıktı (D-014)
def agirlikli_uyelik(skorlar, idx=0):
    """Üyeliği-diğer-ajanların-skoru-belirler (transitif-sıralama).
    Eşik-0.90: B-başarısızken-kuklanın-düşük-itibarı-A'yı-kurtarır,
    sahte-yüksek-itibar-ise-A'yı-eşik-altına-düşürür (bayraklar-SABİT)."""
    g = apply_eigentrust_weights(skorlar, [True, False, True][:len(skorlar)])
    return "GREEN" if g > 0.90 else "RED"
a6 = agirlikli_uyelik([0.90, 0.01, 0.50])
b6 = agirlikli_uyelik([0.90, 0.95, 0.50])
assert a6 != b6, "ağırlıklı-üyelik-transitif-yakalanmadı (D-014-ihlali-yok)"
print(f"  6) DİKİŞ: DÜZ/İKİLİ-sigcount/v1 → {v6}/{rc6}")
print(f"     ağırlıklı-varyant: {a6} → {b6} (transitif-çıktı → duvar-RED)")
print(f"     K0-duvarı-ayrı-tutar: DÜZ-GREEN, sürekli-ağırlık-RED")

# --- 7) DUVARIN-ÇİFT-TARAFLI-ISIRIĞI (resmi-belgeleme)
# Aynı-sönümleme-bir-taraftan-Sybil-kuklalarını-ezer-diğer-taraftan-meşru
# yeni-ajanı-aç-bırakır. Bu-K0-duvarının-gerekçesidir: maliyet-kabul-edilir
# çünkü-alternatif (ağırlıklı-sıralama) manipüle-edilebilir (ölçüm-5).
print("  7) çift-taraflı-ısırık: aynı-sönümleme →")
print(f"     FAYDA: Sybil-kuklaları-düşük-itibar → ağırlıklı-çıkış-ezilir")
print(f"     MALİYET: meşru-yeni-ajan {yeni.score:.4f}'e-düşer (QUARANTINED)")
print(f"     K0-seçimi: maliyet-kabul — alternatif-oynanabilir (delta {delta_syb:.4f})")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-D-014-duvar-negatif-yüz-ölçümü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-101: D-014-duvarının-negatif-yüzü (ağ-boyutu + soğuk-başlangıç)"
[[ $FAIL -eq 0 ]]
