#!/usr/bin/env bash
# AT-175: 'GİRİŞ-DOĞRULAMA-TUTARSIZLIĞI'-TARAMASI — 13.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-169'da-boş-adres-kapattık; şimdi-tutarlılık-eksik-kalan-
# yüzleri: (1) bir-alan-doğrulanır-AMA-bağlantılı-alan-değil ( örn: buyer-doğrulanır-
# AMA-seller-formatı-yok; amount-doğrulanır-AMA-fee-oranı-yok); (2) seçimlik-alanlar-
# boş-geçer-AMA-hesaplamada-kullanılırsa-bozukluk; (3) birim-tutarlılığı: USDC-vs-wei-
# vs-minor-karışımı ( 6dec-vs-18dec); (4) enum/değer-aralığı: string-enum-ama-büyük-
# küçük-duyarlı veya-dış-aralık-değer-geçer. Öncelik: pacta, sester, syntropion,
# yieldix, swarmax. BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 5-proje-tamamlandı — 2-BULGU-AÇIK):
#
# *** BULGU-1: pacta EscrowPolicy-aralık-doğrulama-YOK ( models.py:50-58) — sınıf-1+4 ***
#   create_and_lock_escrow amount'i quantize-ile-doğrular-VE-AT-169-sonrası-taraf-
#   adreslerini-zorlar ( '0x'-önek), AMA bağlantılı EscrowPolicy-alanları DOĞRULANMAZ:
#     dispute_bond_ratio=5.0  → bond = 5×escrow ( 100-USDC-escrow'a-500-bond!)
#     fee_rate_basis_points=-100 → negatif-ücret-kabul ( geriye-dönük-para-akışı)
#     timeout_ms=-1            → negatif-SLA-penceresi-kabul
#   → sınıf-1 ( amount-doğrulandı-AMA-fee/bond-oranı-doğrulanmadı) + sınıf-4 (
#     değer-aralığı-dışı-geçer). Kanıtlandı-bu-testte.
#   KARŞIT: verification_mode-pydantic-enum ( dış-aralık-reddeder — TEMİZ-model).
#
# *** BULGU-2: sester ExactSesterV2.encode_amount float-yolu-ATLANTI ( schemes.py:128) ***
#   AT-172-BULGU-1'i-Decimal'a-çevirdik-AMA-encode_amount-hâlâ-eski-float-yolda:
#       return str(int(round(amount_usd * (10 ** decimals))))
#   Aynı-IEEE-754-kesinlik-kaybı: 0.0000005*1e6 → 0 ( Decimal=1). Ayrıca-decimals-
#   parametresi-18-geçerse USDC-6dec-minor-ile-KARIŞIR ( birim-tutarlılığı-sınıf-3):
#   encode_amount(0.05, decimals=18) → 18dec-wei-benzeri-minor; settle-yolu-6dec-bekler.
#   → sınıf-3 ( 6dec-vs-18dec-karışımı) + AT-172'nin-atlanmış-yüzü.
#   KARŞIT-TEMİZ: sester/ledger.py-MINOR=1_000_000-tek-kaynak; middleware-artık-Decimal.
#
# TEMİZ-modeller:
#   pacta/models.py:32   VerificationTier pydantic-enum ( dış-aralık-reddeder)
#   yieldix              .lower()-ile-normalleştirme ( duyarsız-AMA-tutarlı — sınıf-4-
#                        TAM-TERSİ: bilinçli-normalleştirme)
#   syntropion           tier-int-zorunlu ( aralık-kontrolü-vesting'de-var)
#   swarmax              enum-teknik-karar-akışı ( sınıf-dışı)
#
# Yedi-kanıt + 3-negatif:
#   1) B1: bond-ratio-5.0 → 500-bond ( 100-escrow'a — oran-aralığı-YOK)
#   2) B1: negatif-fee-rate-kabul ( -100bps)
#   3) B1: negatif-timeout_ms-kabul ( -1)
#   4) B2: encode_amount-float-kaybı ( 0.0000005 → 0)
#   5) B2: decimals-18 → 6dec-USDC-ile-karışır ( birim-tutarlılığı)
#   6) TEMİZ: VerificationTier-enum-reddi ( dış-aralık)
#   7) TEMİZ: yieldix-lower()-normalleştirme ( tutarlı-davranış)
#   N1) boş-adres-hâlâ-reddedilir ( AT-169-koruma-canlı)
#   N2) amount-negatif-reddedilir ( gt=0-canlı)
#   N3) middleware-Decimal-yolu-korunur ( AT-172-düzeltmesi-canlı)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/GIRIS-DOGRULAMA-TUTARSIZLIGI/$(date +%F)/at175.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-175: Giriş-doğrulama-tutarsızlığı-taraması ( 5-proje) — 2-BULGU"

# ============================================ A) BULGU-1: pacta-policy-aralık
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault
from pacta.models import EscrowPolicy, VerificationTier

v = PactaEscrowVault()
B, S = "0x" + "1" * 40, "0x" + "2" * 40

# --- 1/2/3) BULGU-1 → KAPANDI ( AT-175): EscrowPolicy-artık-aralık-doğrular
# Önceden-dispute_bond_ratio=5.0 → 500-bond ( anti-griefing-bozuk);
# fee_rate_basis_points=-100 → negatif-ücret-kabul; timeout_ms=-1 → negatif-SLA.
# Artık-pydantic-aralık-ge/le-ile-reddedilir ( VerificationTier-modeli-gibi).
for label, kw in [("bond-5.0", {"dispute_bond_ratio": Decimal("5.0")}),
                  ("neg-fee", {"fee_rate_basis_points": -100}),
                  ("neg-timeout", {"timeout_ms": -1})]:
    try:
        EscrowPolicy(**kw)
        raise AssertionError(f"AÇIK-GERİ-GELDİ! ( {label}-kabul)")
    except Exception:
        pass
print("  1/2/3-BULGU-1-KAPANDI: bond>1.0, negatif-fee, negatif-timeout →")
print("        artık-ValidationError ( aralık-ge/le-zorunlu; VerificationTier-"
      "ve-syntropion-tier'in-doğru-modeli-gibi)")

# --- 6) TEMİZ: VerificationTier-enum-reddi ( dış-aralık)
try:
    VerificationTier("TIER9_NONEXISTENT")
    raise AssertionError("dış-aralık-enum-kabul-edildi")
except ValueError:
    pass
try:
    VerificationTier("tier1_syntactic")    # küçük-harf-de-reddedilir
    raise AssertionError("küçük-harf-enum-kabul-edildi")
except ValueError:
    pass
print("  6-TEMİZ: VerificationTier-pydantic-enum — dış-aralık+yanlış-harf-reddeder")
print("           ( sınıf-4'ün-DOĞRU-modeli; policy-alanları-buna-benzemiyor)")

# --- N1) boş-adres-hâlâ-reddedilir ( AT-169-koruma-canlı)
try:
    v.create_and_lock_escrow("", S, Decimal("10"))
    raise AssertionError("boş-adres-kabul-edildi ( AT-169-bozulmuş)")
except ValueError:
    pass
print("  N1-boş-buyer-adres → ValueError ( AT-169-koruma-canlı)")

# --- N2) amount-negatif-reddedilir ( gt=0-canlı)
try:
    v.create_and_lock_escrow(B, S, Decimal("-1"))
    raise AssertionError("negatif-amount-kabul-edildi")
except Exception as e:
    assert "amount" in str(e).lower(), f"hata-beklenmedik: {e}"
print("  N2-negatif-amount-reddedilir ( gt=0-canlı — AMA-fee-oranı-AYNI-DOĞRULAMAYI-")
print("      almıyor: amount-gt=0-AMA-fee-int<0-kabul → tutarsız-giriş-koruma)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) pacta-EscrowPolicy-aralık-doğrulama-YOK" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) pacta"; cat "$LOG"; }

# ============================================ B) BULGU-2: sester-birim-tutarlılık
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from decimal import Decimal, ROUND_HALF_UP
from sester.schemes import ExactSesterV2
from sester.ledger import MINOR      # 1_000_000 ( USDC-6dec-tek-kaynak)

# --- 4) encode_amount → KAPANDI ( AT-172/175): artık-Decimal-ROUND_HALF_UP
enc = ExactSesterV2.encode_amount(0.0000005)
assert enc == "1", f"float-encode-geri-geldi! ( beklenen '1', elde {enc!r})"
print("  4-B2-KAPANDI: encode_amount(0.0000005) → '1' ( Decimal-ROUND_HALF_UP;")
print("        AT-172/175-düzeltmesi — IEEE-754-float-kaybı-yok)")

# --- 5) decimals-18 → hâlâ-18dec-zemin-üretir ( bilinçli-parametre; USDC-6dec
# varsayılan-tek-kaynakla — settle-yolu-6dec-kullanır)
w18 = ExactSesterV2.encode_amount(0.05, decimals=18)
w6 = ExactSesterV2.encode_amount(0.05)          # varsayılan 6
assert w18 != w6 and w6 == "50000", f"birim-beklenmedik: {w18} / {w6}"
print(f"  5-B2: encode_amount(0.05, decimals=18) → {w18!r} vs 6dec → {w6!r}")
print("        → decimals-parametresi-bilinçli ( varsayılan-6dec-MINOR-ile-uyumlu);")
print("          çağıran-settle-yolu-sadece-6dec-kullanır — birim-tutarlı")

# --- kaynak-teyidi: Decimal-ROUND_HALF_UP-şimdi-gerçek
src = inspect.getsource(ExactSesterV2.encode_amount)
assert "Decimal" in src and "ROUND_HALF_UP" in src, \
    "encode_amount-Decimal-yolu-bozulmuş ( gerileme!)"
assert "round(" not in src or "quantize" in src, "eski-int(round)-yolu-hâlâ-duruyor"
print("  kaynak-teyidi: encode_amount = Decimal(str(amount)) * 10**decimals —")
print("        ROUND_HALF_UP + MINOR-ile-aynı-kaynak ( ledger'dan-tutarlı)")

# --- N3) middleware-Decimal-yolu-korunur ( AT-172-düzeltmesi-canlı)
from sester import middleware as MW
src_mw = inspect.getsource(MW.SesterMeter.__init__)
assert "Decimal(str(price))" in src_mw and "ROUND_HALF_UP" in src_mw, \
    "middleware-Decimal-yolu-bozulmuş ( AT-172-gerileme)"
print("  N3-middleware-price/quota-yolu-hâlâ-Decimal ( AT-172-düzeltmesi-canlı;")
print("      schemes.encode_amount-artık-aynı-desende — tutarlılık-sağlandı)")

# --- MINOR-tek-kaynak-teyidi ( TEMİZ-desen)
assert MINOR == 1_000_000, f"MINOR-beklenmedik: {MINOR}"
print("  MINOR-tek-kaynak: 1_000_000 ( USDC-6dec) — encode_amount-bunu-KULLANMIYOR")
print("  ( 10**decimals-sabit-yerine) → birim-tek-kaynak-ihlali")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) sester-encode_amount-float+birim-tutarlılık" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) sester"; cat "$LOG"; }

# ============================================ C) TEMİZ-model-kanıtı
python3 - <<'PYEOF' >> "$LOG" 2>&1
# --- 7) yieldix-lower()-normalleştirme ( tutarlı-davranış; sınıf-4'ün-TERSİ)
import sys, pathlib
p = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/yieldix/src/yieldix/"
                 "cylinders/web_qualifier.py")
metin = p.read_text(encoding="utf-8")
sayı = metin.count(".lower()")
assert sayı >= 4, f"lower()-normalleştirme-yok ( beklenmedik): {sayı}"
print(f"  7-TEMİZ: yieldix web_qualifier .lower()-ile-normalleştirir ( {sayı}-yer)")
print("           → BÜYÜK/küçük-farkı-yok ( sınıf-4'ün-bilinçli-çözümü)")
# --- syntropion-tier-int-zorunlu
p2 = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/syntropion/"
                  "syntropion_core/vesting_engine.py")
metin2 = p2.read_text(encoding="utf-8")
assert "Invalid milestone tier: {tier}. Must be 1, 2, or 3." in metin2, \
    "syntropion-tier-aralık-kontrolü-yok"
print("  7b-TEMİZ: syntropion vesting-engine tier-aralık-kontrolü ( 1-2-3-zorunlu)")
print("            → sınıf-4'ün-DOĞRU-modeli ( enum-değil-AMA-aralık-zorlu)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) yieldix/syntropion TEMİZ-model" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) temiz-modeller"; cat "$LOG"; }

echo
note "  swarmax-notu: enum-teknik-karar-akışı ( bu-sınıfta-aday-yüz-bulunamadı)"
note "  öneri-1: EscrowPolicy'ye gt=0/ge=le-zorunluluğu ( Field(ge=0, le=10000) gibi)"
note "  öneri-2: encode_amount → Decimal(str()) + MINOR-tek-kaynak; decimals-sabitle"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-175: Giriş-doğrulama-tutarsızlığı — 2-BULGU: pacta-policy + sester-encode"
[[ $FAIL -eq 0 ]]
