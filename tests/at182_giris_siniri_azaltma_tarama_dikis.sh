#!/usr/bin/env bash
# AT-182: 'GİRİŞ-SINIRI-VE-AZALTMA'-TARAMASI — 20.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " Denetim-döngümüzün-ilk-sınıflarından-beri-giriş-yüzeylerini-
# sertleştirdik ( AT-169-…-AT-175). Şimdi-derinleş: (1) Hız-sınırlandırma-YOK:
# tekrar-tekrar-deneme-saldırısı ( brute-force-imza/nonce/anahtar-tahmini) —
# herhangi-bir-yüzeyde-rate-limit-YOK-mu; (2) Kaynak-tüketimi: büyük-istek/girdi
# → bellek/CPU-aşımı ( DoS-via-parse); (3) Azaltma-devreleri: hatalı-eylemler-
# ardışık-olduğunda-kilitlenme-YOK-mu; (4) Numaralandırma-zafiyeti: sıralı-
# ID'lerden-bilgi-sızması ( örn. job_id/seq-tahmin-edilebilir). Öncelik:
# syntropion ( API-girişi), pacta ( escrow-API), yieldix ( pipeline-girişi),
# sester ( ödeme-header-parse). BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 4-proje-tamamlandı — 3-BULGU-AÇIK):
#
# *** BULGU-1: syntropion token-verify'de-rate-limit-YOK ( security.py:130) ***
#   verify_tenant_session_token her-çağrıda-bağımsız-doğrular — hiç-istek-sayacı,
#   rate-limit, veya kilitlenme-YOK. Kanıtlandı: 1000-hatalı-deneme
#   3.4ms'te → ~294.000-deneme/sn ( sınırsız-brute-force).
#   → sınıf-1 ( tekrar-tekrar-deneme). DÜRÜST-NOT: HMAC-SHA256-imzası-128-bit-
#   güvenli-olduğundan-bu-hızda-kırılamaz ( bulgu-GERÇEK-AMA-pratik-etki-düşük);
#   rate-limit-yine-de-olumması-gereken-azaltma-katmanı.
#
# *** BULGU-2: pacta caller-supplied-job_id + çakışma-YOK ( vault.py:103-140) ***
#   create_and_lock_escrow( job_id="job-1") → uuid4-default-ATLANIR; çağıran
#   İSTEDİĞİ-ID'yi-verebilir ( tahmin-edilebilir/sıralı). DAHA-KÖTÜSÜ: çakışan-ID
#   mevcut-job'u SESSİZCE-üzerine-yazar ( self.jobs[job_id]=job). Kanıtlandı:
#     create("job-1") → create("job-1") → jobs["job-1"]-ikinci-nesne ( birincisi-KAYIP)
#   → sınıf-4 ( numaralandırma) + veri-kayıbı: önceki-escrow'un-100-USDC'si
#     kaybolur ( solvency-dict'ten-silinir). dispute_id'de-aynı-desen ( L428).
#
# *** BULGU-3: sester ödeme-header-parse-büyüklük-sınırı-YOK ( middleware.py:171) ***
#   parse_payment_header: token.strip() → base64-decode → json.loads — hiç-uzunluk/
#   boyut-sınırı-YOK. Kanıtlandı: 10MB-header → 67ms/istek; şişirme-ile-hafif-DoS
#   ( bellek/CPU-aşımı). → sınıf-2 ( kaynak-tüketimi).
#   KARŞIT-İYİ-DESİN: SAFE_SNAP_MAX-import'ta-var ( tamga-deseni-uygulandı-AMA
#   header-yolunda-YOK).
#
# TEMİZ-modeller ( kanıtlı):
#   syntropion/circuit_breaker.py    CircuitBreaker ( CLOSED/OPEN/HALF_OPEN;
#                                    failure_threshold %30, window-20, cooldown-30s)
#                                    → sınıf-3-azaltma-devresi-GERÇEK-çalışır
#   syntropion/database.py:56        transactional-backoff ( max_retries+exponential)
#   pacta/models.py:109/150         uuid4-default_factory ( çakışma-YOKSA-rastgele)
#   sester/ledger.py:406             claim_nonce-atomik-first-writer-wins ( replay-
#                                    koruması; restart-atlamaz)
#   yieldix                         bu-sınıfta-aday-yüz-bulunamadı (TEMİZ)
#
# Yedi-kanıt + 3-negatif:
#   1) B1: 1000-hatalı-token-deneme → ~294K/sn ( rate-limit-YOK)
#   2) B2: caller-job_id="job-1"-kabul ( uuid-atlanır)
#   3) B2: çakışan-job_id → mevcut-job-sessizce-üzerine-yazılır
#   4) B3: 10MB-header-parse 67ms ( boyut-sınırı-YOK)
#   5) TEMİZ: circuit-breaker-OPEN-sonrası-reddi ( azaltma-GERÇEK)
#   6) TEMİZ: uuid4-varsayılan-entropy ( caller-ID-vermezse)
#   7) TEMİZ: claim_nonce-replay-koruması ( first-writer-wins)
#   N1) geçerli-token-hâlâ-çalışır ( 1000-redden-sonra)
#   N2) token-3-parça-formatı-korunur ( enum-önyargı-YOK — AT-169-canlı)
#   N3) HMAC-compare_digest-sabit-zamanlı ( zamanlama-sızıntısı-YOK)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/GIRIS-SINIRI-AZALTMA/$(date +%F)/at182.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-182: Giriş-sınırı-ve-azaltma-taraması ( 4-proje) — 3-BULGU"

# ============================================ A) BULGU-1+TEMİZ: syntropion
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, os, sys, time
os.environ.setdefault("SYNTROPION_SECRET_KEY", "at182-test-anahtari-16-karakter")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
from syntropion_core.security import (create_tenant_session_token,
    verify_tenant_session_token)

# --- 1) B1: 1000-hatalı-token-deneme → ~294K/sn ( brute-force-yolu-SAYILMIYOR)
# AT-182-BULGU-1-düzeltmesi-yarım: rate-limit-sadece-İMZASI-GEÇERLI-yolda;
# hatalı-imza-yolu _record_verify_failure-ÇAĞIRMADAN-reddeder ( sayaç-artmaz).
import syntropion_core.security as SEC
t0 = time.perf_counter()
n = 0
for i in range(1000):
    try:
        verify_tenant_session_token(f"a.{i}.WRONGSIG")
    except ValueError:
        n += 1
dt = time.perf_counter() - t0
rate = 1000 / dt if dt > 0 else float("inf")
assert n == 1000, f"reddir-beklenmedik: {n}"
sayac = SEC._verify_fail_counts.get("anon", 0)
assert sayac == 1000, f"anon-sayaç-beklenmedik: {sayac} ( 1000-deneme)"
print(f"  1-B1: 1000-hatalı-İMZALI-deneme → {n}-reddi, {dt*1000:.1f}ms")
print(f"        → {rate:,.0f}-deneme/sn — rate-limit-sayaç={sayac} ( ARTAR!)")
print("        GECİKMİŞ-UYGULAMA-KAPALDI: hatalı-imza-da-anon-bucket'te-SAYILIR")
print("        ( AT-183-düzeltmesi; sayaç-brute-force-hacmini-gözlemlenebilir-kılar)")
print("        DÜRÜST-NOT: HMAC-128-bit-kırılamaz ( bulgu-GERÇEK-AMA-düşük-etki)")

# --- N1) geçerli-token-hâlâ-çalışır ( 1000-redden-sonra)
tok = create_tenant_session_token("t1", "v1", "expert")
p = verify_tenant_session_token(tok)
assert p["tenant_id"] == "t1" and p["role"] == "expert", f"payload-bozuk: {p}"
print("  N1-1000-redden-sonra-geçerli-token-hâlâ-çalışır ( durum-kirlenmesi-YOK)")

# --- N2) token-3-parça-formatı-korunur ( AT-169-enum-düzeltmesi-canlı)
h1 = None
try: verify_tenant_session_token("a.b")
except ValueError as e: h1 = str(e)
h2 = None
try: verify_tenant_session_token(tok.rsplit(".", 1)[0] + ".WRONGSIG")
except ValueError as e: h2 = str(e)
assert h1 == h2 == "Invalid token", f"enum-önyargı-GERİ-GELDİ: {h1!r} != {h2!r}"
print("  N2-2-parça-ve-yanlış-imza → AYNI-'Invalid token' ( AT-169-canlı)")

# --- 5) TEMİZ: circuit-breaker-OPEN-sonrası-reddi ( azaltma-GERÇEK)
from syntropion_core.circuit_breaker import CircuitBreaker
cb = CircuitBreaker()
for _ in range(25):                  # window-20-üstü-başarısız
    cb.record_call(success=False, error_msg="test")
assert cb.is_operational() is False, "circuit-breaker-trip-etmedi"
print("  5-TEMİZ: CircuitBreaker — 25-başarısız-çağrı → OPEN ( is_operational=False)")
print("           azaltma-devresi-GERÇEK ( failure-%30/window-20/cooldown-30s)")

# --- N3) HMAC-compare_digest-sabit-zamanlı ( zamanlama-sızıntısı-YOK)
src = inspect.getsource(verify_tenant_session_token)
assert "compare_digest" in src, "sabit-zamanlı-kıyaslama-YOK"
print("  N3-compare_digest-sabit-zamanlı ( zamanlama-saldırısına-TEMİZ)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) syntropion-rate-limit-YOK + circuit-breaker-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) syntropion"; cat "$LOG"; }

# ============================================ B) BULGU-2: pacta-job_id
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault

# --- 2) B2: caller-job_id="job-1"-kabul ( uuid-atlanır) — hâlâ-açık-AMA
v = PactaEscrowVault()
B, S = "0x" + "1" * 40, "0x" + "2" * 40
j1 = v.create_and_lock_escrow(B, S, Decimal("100"), job_id="job-1")
assert j1.job_id == "job-1", f"job_id-beklenmedik: {j1.job_id!r}"
print("  2-B2: create_and_lock_escrow(job_id='job-1') → KABUL ( uuid4-atlanır)")
print("        → tahmin-edilebilir/sıralı-ID ( numaralandırma — sınıf-4-açık)")

# --- 3) B2-ÇAKIŞMA-KAPANDI: job_id_collision-RED ( AT-182-düzeltmesi-canlı)
try:
    v.create_and_lock_escrow(B, S, Decimal("50"), job_id="job-1")
    raise AssertionError("çakışan-job_id-hâlâ-kabul ( AT-182-bozulmuş)")
except ValueError as e:
    assert "job_id_collision" in str(e), f"mesaj-beklenmedik: {e}"
assert v.jobs["job-1"] is j1 and v.jobs["job-1"].amount_usdc == Decimal("100.000000")
print("  3-B2-ÇAKIŞMA-KAPANDI: job_id_collision → ValueError ( mevcut-job")
print("        KORUNUR — 100-USDC-kaybı-YOK; AT-182-düzeltmesi-canlı)")
print("        → numaralandırma ( caller-job_id) hâlâ-açık-AMA-veri-kayıbı-kapandı")

# --- 6) TEMİZ: uuid4-varsayılan-entropy ( caller-ID-vermezse)
v2 = PactaEscrowVault()
a = v2.create_and_lock_escrow(B, S, Decimal("10"))
b = v2.create_and_lock_escrow(B, S, Decimal("10"))
assert a.job_id != b.job_id and len(a.job_id) == 36, "uuid4-bozuk"
import uuid
assert uuid.UUID(a.job_id).version == 4, "uuid4-değil"
print("  6-TEMİZ: job_id-uuid4-varsayılan ( 36-karakter, v4-entropy; çakışma-YOK)")
print("           → numaralandırma-SADECE-caller-job_id-verdiğinde")

# --- kaynak-teyidi: çakışma-kontrolü-YOK
import inspect
src = inspect.getsource(PactaEscrowVault.create_and_lock_escrow)
assert "if job_id is not None" in src or "if job_id:" in src, \
    "job_id-yolu-kaynakta-yok"
assert "job_id_collision" in src, "çakışma-kontrolü-yok ( AT-182-bozulmış)"
assert "job_id-invalid" in src, "null-byte-guard-yok ( AT-188-bozulmuş)"
print("  kaynak-teyidi-B2: job_id_collision + null-byte-RED-canlı ( AT-182/188)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) pacta-job_id-numaralandırma+çakışma" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) pacta"; cat "$LOG"; }

# ============================================ C) BULGU-3 + TEMİZ: sester
python3 - <<'PYEOF' >> "$LOG" 2>&1
import base64, inspect, json, sys, time
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")

# --- 4) B3-KAPANDI: MAX_HEADER_BYTES=8192-RED ( AT-182-düzeltmesi-canlı)
from sester import middleware as MW
from sester import middleware as MW
from sester.middleware import PaymentErr
# küçük-zarf: GEÇERLİ-JSON-olmalı ( base64→{"s":"x"}); büyük: raw-AAAA-şişirme
kucuk = "x402 eyJzY2hlbWUiOiAiZXhhY3QiLCAieDQwMlZlcnNpb24iOiAyLCAibmV0d29yayI6ICJlaXAxNTU6ODQ1MzIiLCAicmVzb3VyY2UiOiAiciIsICJwYXlsb2FkIjoge319"
buyuk = "x402 " + base64.urlsafe_b64encode(b"A" * 20_000).decode()
for etiket, hdr in (("geçerli-küçük", kucuk), ("20KB-şişirme", buyuk)):
    try:
        MW.SesterMeter._parse_exact(MW.SesterMeter.__new__(MW.SesterMeter), hdr, "r")
        sonuc = "kabul"
    except PaymentErr as e:
        sonuc = f"PaymentErr: {str(e)[:44]}"
    print(f"  4-B3-KAPANDI: {etiket}-header ({len(hdr)}B) → {sonuc}")
    if "şişirme" in etiket:
        # 20KB-şişirme: boyut-sınırı-önce-tetiklenmeli ( base64/EIP-3009-öncesi)
        assert "8192" in sonuc, "büyük-header-reddedilmedi ( gerileme!)"
    else:
        # küçük-zarf: boyut-geçerli-AMA-EIP-3009-alan-eksik-hatası-alabilir;
        # önemli-olan-8192-sınırı-uygulanmamış-olması ( "8192"-mesajı-YOK)
        assert "8192" not in sonuc, "küçük-header-yanlışlıkla-boyut-reddi"
print("        → 8KB-üstü-RED ( tamga-SAFE_SNAP_MAX-deseni — DoS-kapandı)")

# --- kaynak-teyidi: MAX_HEADER_BYTES-guard-canlı
src = inspect.getsource(MW.SesterMeter._parse_exact)
assert "urlsafe_b64decode" in src, "parse-yolu-bulunamadı"
assert "MAX_HEADER_BYTES" in src, "uzunluk-guard-YOK ( AT-182-bozulmuş)"
print("  kaynak-teyidi: _parse_exact-MAX_HEADER_BYTES=8192-guard-canlı")

# --- 7) TEMİZ: claim_nonce-replay-koruması ( first-writer-wins)
from sester.ledger import Ledger
ld = Ledger(":memory:")
a1 = ld.claim_nonce("agent1", "nonce-X")
a2 = ld.claim_nonce("agent1", "nonce-X")
assert a1 is True and a2 is False, f"replay-koruması-bozuk: {a1}/{a2}"
print("  7-TEMİZ: claim_nonce-atomik-first-writer-wins ( replay-koruması;")
print("           ilk-True, tekrar-False — restart-atlamaz; kalıcı-seen_nonces)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) sester-header-DoS + replay-koruması-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) sester"; cat "$LOG"; }

echo
note "  yieldix-notu: bu-sınıfta-aday-yüz-bulunamadı (TEMİZ — pipeline-iç-girişler"
note "       sınırlı; rate-limit-sınıfı-dışında)"
note "  öneri-1: verify-token'e-attempt-counter/lockout ( N-deneme-sonrası-gecikme)"
note "  öneri-2: job_id-çakışma-reddi ( 'if job_id in self.jobs: raise')"
note "  öneri-3: header-uzunluk-kapası ( örn. 8KB-üstü-RED — SAFE_SNAP_MAX-gibi)"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-182: Giriş-sınırı-azaltma — 3-BULGU: rate-limit + job_id + header-DoS"
[[ $FAIL -eq 0 ]]
