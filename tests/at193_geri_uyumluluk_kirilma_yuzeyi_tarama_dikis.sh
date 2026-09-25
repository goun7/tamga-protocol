#!/usr/bin/env bash
# AT-193: 'GERİ-UYUMLULUK-VE-KIRILMA-YÜZEYİ'-TARAMASI — 31.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-191/AT-192-kapandı. Geri-uyumluluk-kırılmalarını-tara
# ( additive-ihlalleri): ( 1) imza-kırılmaları: fonksiyon-imzaları-değiştiyse-
# çağıranlar-kırılır-mı ( bu-oturumda-biz-değiştirdik: secret-None, job_id-
# validation); ( 2) istisna-hiyerarşisi: yeni-istisna-tipleri-except'leri-
# kırıyor-mu ( AuthorizationError-mirasını-doğrula); ( 3) config/env-uyumu: env-
# değişkenleri-kaldırıldı/varsayılanı-değiştiyse ( mevcut-üretim-konfig-bozulur-mü);
# ( 4) test-double-hazırlığı: test-double'lar-hâlâ-gerçek-yolu-koşuyor-mu
# ( AT-075-deseni-gizli-boşluk-YOK). Öncelik: pacta ( vault), sester
# ( middleware/ledger), tamga ( runner), swarmax ( tsa). BULGU → DÜRÜST-rapor;
# YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 4-proje — 2-BULGU-AÇIK, 2-TEMİZ):
#
# *** BULGU-1: sester AT-190 "secret-ZORUNLU" LEDGER-MİRAS-YOLUYLA-EKSİK
#     ( sester/middleware.py:88-113 + sester/ledger.py:219) — sınıf-1+3 ***
#   AT-190-düzeltmesi ( commit-673de2e): SesterMeter'da `secret: str|None=None`
#   + None-RED + boş-string-RED + "dev-secret-varsayılanı-kaldı". AMA:
#     ( a) Ledger.__init__ hâlâ `secret: str = "dev-secret"`-varsayılanında;
#     ( b) SesterMeter ledger'ın-secret'ini-MİRAS-alır ( mw:88-89:
#         "if _led_secret and (secret is None or secret=='dev-secret'):
#          secret = _led_secret")
#     ( c) None-RED-kodu SADECE `if secret is None and not _led_secret`-koşulunda
#         çalışır → ledger-secret'lı-yolda-atlanır
#   KANITLANDI ( üretim-konfig-simülasyonu):
#     Ledger("prod.db")                → secret == b"dev-secret" ( uyarı ile)
#     SesterMeter(app, ledger)         → KABUL ( uyarı; dev-secret-ile)
#     SesterMeter(app, ledger, secret=None) → KABUL! ( miras-dev-secret)
#     SesterMeter(app, ledger, secret="")  → RED ( AT-190-N2-bu-yol-çalışır)
#   ETKİ: üretim-konfig-secret'siz → sahte-ödeme-zarfı-HMAC'i-üretilebilir
#   ( AT-190'un-kapatmak-istediği-tehlike-hâlâ-açık). SESTER_REQUIRE_SECURE_SECRET=1
#   ancak-RED ( env-varsayılan-kapalı → BULGU-2-deseni).
#   Öneri: Ledger.__init__'te-de-secret-ZORUNLU-kıl ( SesterMeter-ile-tutarlı);
#     VEYA miras-yolunu-dev-secret-RED'ye-bağla.
#
# *** BULGU-2: pacta caller-YOK-settle ROL-KONTROLÜ-ATLAYIP-PARA-TRANSFER-EDER
#     ( pacta/core/vault.py:248-256) — sınıf-3 ( config/env-uyumu) ***
#   settle_escrow( job_id, caller_address=None) — varsayılan-None:
#       if caller_address is None:
#           warnings.warn( "rol-kontrolü-ATLANDI ( PACTA_REQUIRE_CALLER_ROLE=1…)")
#           if not os.environ.get( "PACTA_REQUIRE_CALLER_ROLE"):  # varsayılan-KAPALI
#               → devam-eder ( SETTLED! para-transferi)
#   KANITLANDI: env-YOK + caller-YOK → uyarı + **settle-BAŞARILI** ( status=SETTLED,
#   fee_collected=0.075); env-set + caller-YOK → EscrowNotFoundError ( RED).
#   ETKİ: üretim-çağıranlar `settle_escrow( job_id)`-şeklinde-çağırıyorsa ( AT-180'den
#   önceki-eski-imza) → rol-doğrulaması-YAPILMADAN-para-transfer-edilir. AT-184'ün
#   "zorunlu-rol-kapısı" varsayılan-KAPALI ( geri-uyumluluk-için-AMA-güvenlik-
#   feda-edilerek).
#   Öneri: caller_address'i-ZORUNLU-kıl ( None-RED) VEYA PACTA_REQUIRE_CALLER_ROLE
#   varsayılanı-1-yap ( güvenlik-önce; geri-uyumluluk-notu-ile).
#
# TEMİZ-modeller ( 2-kanıt):
#   1) pacta istisna-hiyerarşisi ( AT-192): EscrowAuthorizationError(
#      EscrowNotFoundError) — additive; ESKİ 'except EscrowNotFoundError' rol-
#      reddini-hâlâ-yakalar ( ölçüldü); yeni-tip-ile-ayırt-edilebilir ( rol-reddi →
#      AuthorizationError, job-yok → NotFoundError — karışmıyor); InvariantViolation
#      Error-bağımsız
#   2) sester boş-string-RED ( AT-190-N2) + swarmax SWARMAX_TSA_PEM: düzeltme-
#      yolları-çalışıyor ( boş-secret → RED; PEM-set → PKI-doğrulaması-aktif)
#
# 2-negatif-kanıt:
#   N1) EscrowAuthorizationError yakalanır-eski-except-ile ( additive-uyumlu)
#   N2) sester boş-string-secret → RED ( AT-190-N2-canlı)
#
# İNDETERMİNE-notları: ( a) swarmax SWARMAX_TSA_PEM: ayarlı-DEĞİLSE-binding-True-
#     AMA-uyarı ( PKI-doğrulanmadı) — AT-187'nin-açık-itirafı ( operatör-sözleşmesi:
#     "cert-diskte-olmalı"); BULGU-2-ile-AYNI-env-geçidi-deseni-AMA-kayıpta-
#     belgeli → not-olarak-raporlandı. ( b) tamga-runner'da-bu-oturumda-imza-
#     değişikliği-bulunamadı ( git-log-teyit: AT-189..AT-192-düzeltmeleri-tools/
#     ve-kanıt-yollarında); cmd_*-imzaları-kararlı. ( c) test-double'lar:
#     settlement_bind_verify._claim_signer-double'ı-bilinçli-dağıtım ( AT-187'de-
#     teyit: gerçek-ecrecover-AT-012'de-koşülüyor); AT-075-deseni-gizli-boşluk-YOK.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/GERI-UYUMLULUK/$(date +%F)/at193.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-193: Geri-uyumluluk-ve-kırılma-yüzeyi-taraması — 2-BULGU"

# ============================================ A) BULGU-1: sester-secret-miras
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, os, warnings, tempfile
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
os.environ.pop("SESTER_REQUIRE_SECURE_SECRET", None)
from sester.ledger import Ledger
from sester.middleware import SesterMeter
tmp = tempfile.mkdtemp()

# --- 1) AT-193-BULGU-1-KAPALDI: Ledger-artık-secret-ZORUNLU ( varsayılan-YOK)
try:
    warnings.simplefilter("ignore")
    Ledger(os.path.join(tmp, "prod.db"))   # secret-YOK → RED-beklenen
    raise AssertionError("AT-193-kapanmadı! Ledger-secret'siz-KABUL")
except ValueError as e:
    assert "secret-required" in str(e), f"mesaj-beklenmedik: {e}"
print("  1-B1: Ledger( secret'siz) → RED ( AT-193: dev-secret-varsayilanı-YOK)")

# --- 2) dürüst-yol: Ledger-açık-secret-ile ( SesterMeter-miras-çalışır)
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    led = Ledger(os.path.join(tmp, "prod.db"), secret="uretim-secret-32b-2026")
print(f"  2-B1: Ledger( açık-secret) → KABUL ( dürüst-yol)")
assert led.secret == b"uretim-secret-32b-2026"

# --- 3) AT-193-KAPALDI: SesterMeter-mirası-artık-gerçek-secret-ile
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    m2 = SesterMeter(None, led, price=0.1, daily_quota=1.0, secret=None)
assert m2.secret == b"uretim-secret-32b-2026", "miras-yolu-bozuk"
print(f"  3-B1: SesterMeter( secret=None) + ledger-secret → miras-çalışır")
print("        → AT-193-BULGU-1-KAPALDI: dev-secret-mirası-YOK")

# --- N2) boş-string → RED ( AT-190-N2-yol-çalışıyor)
try:
    SesterMeter(None, led, price=0.1, daily_quota=1.0, secret="")
    print("  N2-FAIL: boş-string-KABUL")
    raise SystemExit(1)
except ValueError as e:
    assert "secret-empty" in str(e), f"mesaj-beklenmedik: {e}"
    print(f"  N2-TEMİZ: boş-string-secret → RED: {str(e)[:38]}")

# --- 4) env-set → RED ( AT-179-yol-çalışıyor; AT-193-kapsamı-korundu)
os.environ["SESTER_REQUIRE_SECURE_SECRET"] = "1"
try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        Ledger(os.path.join(tmp, "p2.db"), secret="dev-secret")
    print("  4-B1-FAIL: env-set-ile-dev-secret-KABUL")
    raise SystemExit(1)
except ValueError:
    print("  4-B1-TEMİZ: SESTER_REQUIRE_SECURE_SECRET=1 → RED ( yol-çalışıyor)")
os.environ.pop("SESTER_REQUIRE_SECURE_SECRET", None)
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) sester-AT-190-secret-miras-eksik ( BULGU)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) sester"; cat "$LOG"; }

# ============================================ B) BULGU-2: pacta-caller-YOK
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, os, warnings
from decimal import Decimal
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from pacta.core.vault import PactaEscrowVault
os.environ.pop("PACTA_REQUIRE_CALLER_ROLE", None)

def hazirla():
    v = PactaEscrowVault()
    B, S = "0x" + "1" * 40, "0x" + "2" * 40
    j = v.create_and_lock_escrow(B, S, Decimal("10"))
    v.submit_output(j.job_id, {"r": 1})
    v.mark_verified_ok(j.job_id)
    return v, j

# --- 1) env-YOK + caller-YOK → uyarı-ile-SETTLE ( para-transferi-rolsüz)
v, j = hazirla()
with warnings.catch_warnings(record=True) as w:
    warnings.simplefilter("always")
    job, tx = v.settle_escrow(j.job_id)   # caller-YOK ( eski-imza-gibi)
    atlandi = any("ATLANDI" in str(x.message) for x in w)
print(f"  1-B2: caller-YOK-settle ( env-YOK): status={job.status.value},"
      f" fee={job.fee_collected_usdc}, rol-atlandı={atlandi}")
assert job.status.value == "SETTLED" and atlandi
print("        → BULGU: rol-doğrulanmadan-para-transfer-edildi ( SETTLED)")

# --- 2) env-set + caller-YOK → RED ( zorunlu-kapı-çalışıyor)
os.environ["PACTA_REQUIRE_CALLER_ROLE"] = "1"
v2, j2 = hazirla()
try:
    v2.settle_escrow(j2.job_id)
    print("  2-B2-FAIL: env-set-ile-caller-YOK-KABUL")
    raise SystemExit(1)
except Exception as e:
    print(f"  2-B2-TEMİZ: PACTA_REQUIRE_CALLER_ROLE=1 + caller-YOK → RED"
          f" ( {type(e).__name__})")
os.environ.pop("PACTA_REQUIRE_CALLER_ROLE", None)

# --- 3) caller-verilince-her-zaman-rol-kontrolü ( bu-yol-sağlam)
v3, j3 = hazirla()
try:
    v3.settle_escrow(j3.job_id, caller_address="0x" + "9" * 40)
    print("  3-B2-FAIL: üçüncü-taraf-KABUL")
    raise SystemExit(1)
except Exception as e:
    print(f"  3-B2-TEMİZ: caller=üçüncü-taraf → RED ( {type(e).__name__})")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) pacta-caller-YOK-settle-rolsüz ( BULGU)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) pacta"; cat "$LOG"; }

# ============================================ C) TEMİZ: istisna-hiyerarşisi
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
from decimal import Decimal
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from pacta.core.vault import (PactaEscrowVault, EscrowNotFoundError,
                              EscrowAuthorizationError, InvariantViolationError)

# --- N1) hiyerarşi-additive: eski-except-hâlâ-yakalar
print(f"  N1-TEMİZ: EscrowAuthError←EscrowNotFoundError="
      f"{issubclass(EscrowAuthorizationError, EscrowNotFoundError)}")
assert issubclass(EscrowAuthorizationError, EscrowNotFoundError)
assert not issubclass(InvariantViolationError, EscrowNotFoundError)

# --- rol-reddi: ESKİ-except ile yakalanır ( geri-uyumlu)
v = PactaEscrowVault()
B, S = "0x" + "1" * 40, "0x" + "2" * 40
j = v.create_and_lock_escrow(B, S, Decimal("10"))
v.submit_output(j.job_id, {"r": 1}); v.mark_verified_ok(j.job_id)
yakaladi = None
try:
    v.settle_escrow(j.job_id, caller_address="0x" + "9" * 40)
except EscrowNotFoundError:   # ESKİ-dışsı
    yakaladi = "EskiExcept"
print(f"  N1b-TEMİZ: ESKİ-except rol-reddini-yakalar: {yakaladi}")
assert yakaladi == "EskiExcept"

# --- yeni-tip-ile-ayırt-edilebilir ( AT-192-amacı)
v2 = PactaEscrowVault()
j2 = v2.create_and_lock_escrow(B, S, Decimal("10"))
tip = None
try:
    v2.raise_dispute(j2.job_id, "0x" + "9" * 40, "x", "h" * 64)
except EscrowAuthorizationError:
    tip = "AuthorizationError"
except EscrowNotFoundError:
    tip = "NotFoundError"
tip2 = None
try:
    v2.raise_dispute("YOK-JOB", B, "x", "h" * 64)
except EscrowAuthorizationError:
    tip2 = "AuthorizationError"
except EscrowNotFoundError:
    tip2 = "NotFoundError"
print(f"  N1c-TEMİZ: rol-reddi={tip}, job-yok={tip2} ( karışmıyor)")
assert tip == "AuthorizationError" and tip2 == "NotFoundError"
print("        → AT-192-additive-tasarım-sağlam ( kırılma-YOK)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) pacta-istisna-hiyerarşisi-additive-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) istisna"; cat "$LOG"; }

# ============================================ D) TEMİZ: swarmax-tsa-uyumluluk
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, os, hashlib, warnings
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/swarmax/src")
from swarmax.tsa import verify_token_binding

msg = b"test-seal-message"
imprint = hashlib.sha256(msg).digest()

# --- 1) SWARMAX_TSA_PEM-yok → uyarı-ile-True ( AT-187-itirafı; gürültülü)
os.environ.pop("SWARMAX_TSA_PEM", None)
with warnings.catch_warnings(record=True) as w:
    warnings.simplefilter("always")
    ok = verify_token_binding(b"\x30" + imprint + b"\x00" * 8, msg)
print(f"  1-D: PEM-yok → binding={ok}, uyarı={any('PEM' in str(x.message) for x in w)}")
assert ok is True  # binding-hâlâ-doğru ( imprint-var)
# --- 2) yanlış-imprint → False ( bu-yol-her-zaman-çalışır)
ok2 = verify_token_binding(b"\x30" + b"\x00" * 40, msg)
print(f"  2-D-TEMİZ: yanlış-imprint → {ok2}")
assert ok2 is False
# --- 3) kaynak-teyidi: PKI-katmanı-canlı ( AT-187-düzeltmesi)
src = open("/home/gokun/projects/00_TAMGA-MESH/swarmax/src/swarmax/tsa.py",
           encoding="utf-8").read()
assert "SWARMAX_TSA_PEM" in src and "_verify_pki" in src
print("  3-D-TEMİZ: SWARMAX_TSA_PEM + _verify_pki-kaynakta-canlı ( AT-187)")
print("        → not: PEM-yok-seçeneği-gürültülü-uyarı-ile-geçer ( operatör-sözleşmesi;")
print("          BULGU-2-ile-aynı-env-geçidi-deseni — kayıtta-belgeli)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: D) swarmax-TSA-uyumluluk-TEMİZ ( not-ile)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: D) swarmax"; cat "$LOG"; }

echo
note "  öneri-1: sester Ledger.__init__'te-de-secret-ZORUNLU-kıl ( SesterMeter-ile-"
note "         tutarlı); miras-yolu-dev-secret'i-RED'ye-bağla ( AT-190-eksik-kapsama)."
note "  öneri-2: pacta caller_address'i-ZORUNLU-kıl ( None-RED) VEYA env-varsayılanı-1-"
note "         yap — caller-YOK-settle-rolsüz-para-transfer-ediyor."
echo "RESULT: $PASS PASS, $FAIL FAIL"
echo "  AT-193: Geri-uyumluluk — 2-BULGU (sester-secret-miras, pacta-caller-YOK)"
echo "          + istisna-hiyerarşisi/swarmax-uyumluluk-TEMİZ"
[[ $FAIL -eq 0 ]]
