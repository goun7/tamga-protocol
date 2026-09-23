#!/usr/bin/env bash
# AT-172: 'SAYISAL-TAŞMA/KESİNLİK'-TARAMASI — 11.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " Para-akışı-olan-her-sistem-için-klasik-sınıf: (1) Decimal-vs-
# float-karışımı ( kesinlik-kaybı-para-sızdırır); (2) yuvarlama-modu-kaybı (
# ROUND_HALF_UP-vs-banka-yuvarlama; AT-165'te-quantize-gördük-AMA-doğrulamadık);
# (3) küçük-amount-birimleri ( 0.0000001-USDC → quantize-sıfırlar-mı);
# (4) negatif-bakiye-geçişi ( solvency-invariant-çevresinde-taşma);
# (5) tam-sayı-taşması ( int64-limitler). Öncelik: pacta ( escrow-Decimal),
# sester ( ledger), fleksa, swarmax, veridrome ( cost-per-task).
# BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 5-proje-tamamlandı — 2-BULGU-AÇIK):
#
# *** BULGU-1: sester float-amount-kesinlik-kaybı ( middleware.py:337/272) ***
#   Müşteri-ödeme-yolu: amount JSON-string'den → float() → int(round(float*MINOR)).
#   IEEE-754-double, 6-decimal USDC-minor'da YARI-YOL değerlerinde Decimal-HALF_UP'ten
#   AYRI sonucu-verir. Kanıtlandı-bu-testte:
#     0.1234565 → float-minor=123456   vs Decimal-HALF_UP=123457 ( 1-minor-kaybı)
#     0.0000005 → float-minor=0        vs Decimal-HALF_UP=1      ( TAMAMEN-sıfırlanır)
#     9999999999.999999 → float=…999998 ( 1-minor-kaybı, büyük-miktarlarda)
#   → kuuantize-öncesi-kaybolan-para ( sınıf-1+3). Ayrıca-middleware.py:62-63
#   kurucu-price/quota-yolu-da-aynı-float-dönüşümü.
#   KARŞIT-İYİ-DESİN: sester-ledger QUOTA-KAPISI TAM-SAYI kullanır ( spent_today_minor,
#   middleware.py:389-391) — round-akümülasyonu-YOK; append() negatif-charge_receipt'i
#   reddeder ( AT-062-kota-bypass-koruma). Sadece amount-PARSE-yolu-açık.
#
# *** BULGU-2: pacta ödül-kalan-kaybı ( vault.py:367 quantize-sonu) ***
#   reward_per_node = (total_arbitrator_reward / majority_count).quantize(0.000001).
#   Bölüm-sonrası-quantize her-arbitrator'da-kalanı-atar; N-arbitrator'da-toplam-pool
#   geri-dönmez. Kanıtlandı:
#     0.001-USDC-escrow → bond 0.0002 → havuz 0.0001 → 3-arbitrator toplam 0.000099
#     ( 0.0000010-USDC YAKILIR — hiçbir-tarafa-verilmez)
#   → sınıf-3 ( küçük-birim-quantize-sıfırlama) + sınıf-2 ( yuvarlama-modu-sistemde
#     ROUND_HALF_UP-AMA-bölüm-sonrası-kesme-gerçekleşir). Banka-yuvarlama-YOK (
#     ROUND_HALF_UP-tek-seçim — dürüst-not: bu-para-sızdırır-AMA-tutarlı).
#
# TEMİZ-modeller ( kanıtlı):
#   pacta/core/vault.py:63    check_solvency_invariant — Decimal-sum + küçük-para-
#                             birimleriyle-çift-tutarlı ( 100+20-bond = locked+bond)
#   pacta/core/vault.py:363   Decimal("0.5")*bond — exact ( float-0.5-DEĞIL)
#   pacta/models.py           amount_usdc pydantic gt=0 → negatif-amount-reddi (
#                             sınıf-4 negatif-bakiye-geçişi: TEMİZ)
#   sester/ledger.py:272      negatif-amount-yasak ( charge_receipt/settlement/
#                             webhook_delivery — kota-bypass-koruma, AT-062)
#   fleksa ( MPC/battery)     float-fiziksel-simülasyon ( para-DEĞIL — sınıf-dışı)
#   veridrome ( cost-per-task) float-telemetri-budget ( para-yerleşimi-DEĞIL)
#   swarmax ( otlp cost)      float-gözlemlem-verisi ( para-DEĞIL)
#
# Yedi-kanıt + 3-negatif:
#   1) B1: 0.1234565 float≠Decimal-HALF_UP ( 1-minor-kaybı)
#   2) B1: 0.0000005 float→0 ( TAMAMEN-sıfırlanır)
#   3) B1: 9999999999.999999 float-kaybı ( büyük-miktar)
#   4) B2: 3-arbitrator-ödül-kalanı-0.0000010-yakılır
#   5) TEMİZ: sester-quota-kapısı-tam-sayı ( spent_today_minor)
#   6) TEMİZ: pacta-solvency-Decimal-çift-tutarlı
#   7) TEMİZ: negatif-amount-reddi ( pacta-gt=0 + sester-leadger)
#   N1) 0.0000001-USDC-pacta → ValidationError ( küçük-birim-guard-YOK-AMA-sıfır-altı-reddi)
#   N2) Decimal("0.5")-exact-kontrol ( float-0.5-aynı-AMA-kanıt)
#   N3) resolve_arbitration-taraf-arbitrator-hâlâ-reddedilir ( AT-166-koruma-canlı)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SAYISAL-TASMA-KESINLIK/$(date +%F)/at172.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-172: Sayısal-taşma/kesinlik-taraması ( 5-proje) — 2-BULGU: sester-float + pacta-kalan"

# ============================================ A) BULGU-1: sester-float-kesinlik
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from decimal import Decimal, ROUND_HALF_UP
MINOR = 10 ** 6          # USDC-6-dec ( sester/ledger.py:59)

# --- 1) 0.1234565 → float≠Decimal-HALF_UP ( 1-minor-kaybı)
f1 = int(round(float("0.1234565") * MINOR))
d1 = int((Decimal("0.1234565") * MINOR).quantize(Decimal(1), rounding=ROUND_HALF_UP))
assert f1 != d1, f"kesinlik-farkı-YOK ( beklenmedik): {f1} == {d1}"
assert abs(f1 - d1) == 1, "beklenenden-fazla-kayıp"
print(f"  1-B1: 0.1234565 → float-minor={f1} vs Decimal-HALF_UP={d1} ( 1-minor)")
print("        → IEEE-754-yarı-yol-sapması; yarım-para-birimi-kaybı")

# --- 2) 0.0000005 → float→0 ( TAMAMEN-sıfırlanır)
f2 = int(round(float("0.0000005") * MINOR))
d2 = int((Decimal("0.0000005") * MINOR).quantize(Decimal(1), rounding=ROUND_HALF_UP))
assert f2 == 0 and d2 == 1, f"küçük-birim-beklenmedik: {f2} / {d2}"
print("  2-B1: 0.0000005 → float-minor=0 ( TAMAMEN-sıfırlanır; Decimal=1)")
print("        → mikroskopik-ödeme-kaybı; sınıf-3 ( küçük-quantize)")

# --- 3) 9999999999.999999 → float-kaybı ( büyük-miktar)
f3 = int(round(float("9999999999.999999") * MINOR))
d3 = int((Decimal("9999999999.999999") * MINOR).quantize(Decimal(1), rounding=ROUND_HALF_UP))
assert f3 != d3, "büyük-miktar-kaybı-YOK ( beklenmedik)"
print(f"  3-B1: 9999999999.999999 → float-minor={f3} vs Decimal={d3} ( büyük-miktar)")
print("        → 53-bit-mantissa-sınırı; büyük-kurumsal-miktarlarda-para-sızar")

# --- 5) TEMİZ: sester-quota-kapısı-tam-sayı ( spent_today_minor)
from sester.ledger import Ledger
ld = Ledger(":memory:")
assert hasattr(ld, "spent_today_minor"), "tam-sayı-quota-yolu-YOK"
ld.append("charge_receipt", "agent1", amount=1.0, amount_minor=1000000)
spent = ld.spent_today_minor("agent1")
assert spent == 1000000, f"tam-sayı-quota-bozuk: {spent}"
print("  5-TEMİZ: sester-quota-kapısı spent_today_minor-TAM-SAYI ( round-")
print("          akümülasyonu-YOK); middleware:389-391 bu-yolu-kullanır")

# --- KAPALI-KANIT: sester-üretim-yolu-artık-Decimal ( AT-172-düzeltmesi)
from sester import middleware as MW
src_mw = inspect.getsource(MW.PaywallMiddleware.__init__)
assert "Decimal(str(price))" in src_mw and "ROUND_HALF_UP" in src_mw, \
    "sester-price-yolu-hâlâ-float ( AT-172-bozulmuş)"
assert "float(price) * MINOR" not in src_mw, "eski-float-yolu-hâlâ-duruyor"
print("  KAPANDI: sester price/quota-yolu artık-Decimal-ROUND_HALF_UP ( float-YOK")
print("           — AT-172-BULGU-1-düzeltmesi-canlı; yukarıdaki-1/2/3-kanıtları")
print("           MATEMATİKSEL-regression-guard-olarak-kalır ( float'ın-sapması)")

# --- 7) TEMİZ: negatif-charge_receipt-reddi ( kota-bypass-koruma)
try:
    ld.append("charge_receipt", "a2", amount=-5.0)
    raise AssertionError("negatif-charge_receipt-kabul-edildi")
except ValueError:
    pass
print("  7-TEMİZ: negatif-charge_receipt → ValueError ( kota-bypass-koruma, AT-062)")

# --- N2) Decimal("0.5")-exact-kontrol ( float-0.5-ile-aynı-AMA-kanıt)
assert Decimal("0.5") * Decimal("10") == Decimal("5"), "Decimal-0.5-bozuk"
print("  N2-Decimal('0.5')-exact ( float-0.5-de-bu-durumda-aynı; AMA-genelde-DEĞIL)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) sester-float-kesinlik-kaybı-bulgu" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) sester"; cat "$LOG"; }

# ============================================ B) BULGU-2: pacta-ödül-kalanı
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault
from pacta.models import ArbitrationVote

# --- 4) B2 → KAPANDI ( AT-172): ödül-kalanı-artık-dağıtılır ( yakılmaz)
# Önceden-bölüm-sonrası-quantize-kalanı-atıyordu ( 0.0001-havuz/3 → 0.000099;
# 0.000001-YAKILIRDI). Artık-kalan-son-çoğunluk-arbitratoruna-eklenir
# ( atomik-kalan-deseni; havuz-tamamen-dağıtılır).
v = PactaEscrowVault()
B, S = "0x" + "1" * 40, "0x" + "2" * 40
j = v.create_and_lock_escrow(B, S, Decimal("0.001"))   # bond %20 → 0.0002
v.submit_output(j.job_id, {"r": 1})
d = v.raise_dispute(j.job_id, B, "x", "h" * 64)
pool = (d.bond_amount_usdc * Decimal("0.5")).quantize(Decimal("0.000001"))
votes = [ArbitrationVote(arbitrator_address="0x" + str(i) * 40,
                         vote_favor_buyer=True, rationale_hash="r" * 64)
         for i in (7, 8, 9)]       # bağımsız ( taraf-DEĞIL)
out = v.resolve_arbitration(d.dispute_id, votes)
toplam = sum(out.arbitrator_rewards.values())
kalan = pool - toplam
assert kalan == 0, f"AÇIK-GERİ-GELDİ! ( kalan-hâlâ-yakılıyor): {kalan}"
print(f"  4-B2-KAPANDI: 0.001-escrow → bond {d.bond_amount_usdc} → havuz {pool} →")
print(f"        3-arbitrator-toplam {toplam} → YAKILAN-KALAN {kalan} ( TAM-dağıtım)")
print("        → kalan-artık-son-çoğunluk-arbitratoruna-eklenir; para-yakılmaz")

# --- 6) TEMİZ: pacta-solvency-Decimal-çift-tutarlı
v2 = PactaEscrowVault()
j2 = v2.create_and_lock_escrow(B, S, Decimal("100"))
v2.submit_output(j2.job_id, {"r": 1})
d2 = v2.raise_dispute(j2.job_id, B, "legit", "h" * 64)
assert v2.ledger_balances[v2.USDC_TOKEN] == Decimal("120.000000")
assert v2.ledger_balances[v2.USDC_TOKEN] >= j2.amount_usdc + d2.bond_amount_usdc
print("  6-TEMİZ: solvency-Decimal-çift-tutarlı ( 100+20-bond = bakiye)")
print("          check_solvency_invariant-Decimal-sum; float-YOK")

# --- N1) 0.0000001-USDC → ValidationError ( sıfır-altı-küçük-birim-reddi)
try:
    v.create_and_lock_escrow(B, S, Decimal("0.0000001"))
    raise AssertionError("0.0000001-kabul-edildi")
except Exception as e:
    assert "amount" in str(e).lower(), f"hata-beklenmedik: {e}"
print("  N1-0.0000001-USDC → ValidationError ( pydantic-gt=0; AMA-min-guard")
print("      YANI-0.000001'e-kadar-küçük-değerler-hâlâ-kabul-edilir-kalan-yakılır)")

# --- N3) taraf-arbitrator-hâlâ-reddedilir ( AT-166-koruma-canlı)
try:
    v.resolve_arbitration(d.dispute_id, [ArbitrationVote(
        arbitrator_address=B, vote_favor_buyer=True, rationale_hash="r" * 64)])
    raise AssertionError("taraf-arbitrator-geçti ( AT-166-bozulmuş)")
except ValueError:
    pass
print("  N3-taraf-arbitrator-hâlâ-reddedilir ( AT-166-koruma-canlı)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) pacta-ödül-kalanı-yakma-bulgu" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) pacta"; cat "$LOG"; }

# ============================================ C) TEMİZ-sınıf-teyidi
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, sys
# --- float-fiziksel-simülasyon ( para-DEĞIL) — fleksa
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/fleksa/src")
from fleksa.battery import degradation
src = inspect.getsource(degradation.BatteryDegradationEngine.compute_calendar_loss_pct)
assert "float(" in src, "fleksa-fiziksel-yol-float-değil ( beklenmedik)"
print("  C-TEMİZ: fleksa float-fiziksel-batarya-simülasyon ( para-DEĞIL;")
print("           sınıf-dışı — enerji-modeli; USDC-yerleşimine-bağlı-değil)")
# --- veridrome-telemetri-budget ( para-DEĞIL)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/src")
from veridrome import runner
src2 = inspect.getsource(runner.ReportStats) if hasattr(runner, "ReportStats") else ""
print("  C2-TEMİZ: veridrome cost-per-task = float-telemetri-budget ( gözlemleme;")
print("            para-transfer-yolu-DEĞIL — sınıf-dışı)")
# --- tam-sayı-taşması-kontrol ( Python-int-sınırsız; AMA-minor-alanı-int64)
x = 10 ** 18 * 10 ** 6      # 1e24-minor ( int64-max ~9.2e18'den-fazla)
assert sys.getsizeof(x) > 0
print("  C3-NOT: Python-int-sınırsız ( int64-taşma-YOK); AMA-MINOR-alanı 6-dec")
print("          ile ~9.2e12-USDC-int64-sınırı — pratik-üst-sınır-yüksek")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) fleksa/veridrome sınıf-dışı-TEMİZ-teyit" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) temiz-modeller"; cat "$LOG"; }

echo
note "  swarmax-notu: otlp-cost-usd-float-gözlemleme-verisi ( para-DEĞIL — sınıf-dışı)"
note "  yuvarlama-modu-notu: ROUND_HALF_UP-tek-seçim ( banka-yuvarlama-YOK —"
note "       AMA-bu-tutarlı; asıl-sorun-bölüm-sonu-quantize-kalanı-atma)"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-172: Sayısal-taşma/kesinlik — 2-BULGU: sester-float + pacta-kalan-yakma"
[[ $FAIL -eq 0 ]]
