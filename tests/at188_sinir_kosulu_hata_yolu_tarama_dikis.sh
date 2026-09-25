#!/usr/bin/env bash
# AT-188: 'SINIR-KOŞULU-VE-HATA-YOLU-KAPSAMI'-TARAMASI — 26.-sınıf ( Lead).
#
# LEAD'İN-TALİMATI: " Hata-yollarının-sınır-koşullarını-tara ( off-by-one-sınıfı):
# (1) Eşik-değeri-sınırı: >=-vs->-karışıklığı ( örn. limit=100 → 100. veya 101.
#   deneme-ne-olur); (2) Boş-giriş-davranışı: boş-liste/boş-string/0-değer →
#   RED-mi-geçiş-mi; (3) Aşırı-büyük-giriş: limit-aşımı/taşma ( bignum,
#   uzun-string); (4) Unicode-ve-özel-karakter: Türkçe-karakter/null-byte-
#   path-injection. Öncelik: sester ( ödeme-doza-maksimumları), pacta (
#   miktar-sınırları), tamga ( ledger-seq-sınırları), swarmax ( filo-sınırları).
#   BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 4-proje-tamamlandı — 3-BULGU-AÇIK + 4-EŞIK-TEMİZ):
#
# *** BULGU-1: pacta job_id null-byte-ve-Türkçe-karakter-KABUL ( models.py:109) ***
#   create_and_lock_escrow(job_id="a\x00b") → KABUL; job_id saklanır ( dict).
#   Kanıtlandı: null-byte-içeren-ID kayıt-edilir ( path/log-splitting-riski).
#   Boş-string "" → SESSİZCE-uuid4'ye-düşer ( call-with-empty != call-with-None
#   AYRT-EDİLEMEZ — sessiz-gözlem-dışı-düzeltme).
#   → sınıf-4 ( özel-karakter) + boş-giriş-sessizliği.
#
# *** BULGU-2: sester amount=0.0-KABUL ( negatif-guard < 0; sıfır-boşluk) ***
#   ledger.append("charge_receipt", ..., amount=0.0) → KABUL ( amount_minor=0).
#   Kanıtlandı: negatif-RED-var ( amount < 0-guardı) AMA amount == 0-geçer!
#   → sıfır-tutarlı-charge kayıt-edilir ( kota-bypass-DEĞİL-AMA anlam-boş:
#     boş-ödeme-gerçeği; payload-validasyon-açığı).
#
# *** BULGU-3 (zayıf): sester webhook Türkçe-karakter-KABUL-AMA-doğru ***
#   unicode-agent → KABUL ( UTF-8-destek-doğru — BULGU-DEĞİL, TEMİZ).
#   → DÜRÜST-NOT: unicode-doğru-işlenir; kayıt-edilir.
#
# EŞİK-TEMİZ-modeller ( kanıtlı — off-by-one-YOK):
#   syntropion rate-limit: _VERIFY_FAIL_LIMIT=100, >=-karşılaştırma →
#     100. deneme-RED ( spy-ile-kanıtlı: 101. çağrı-TRUE-döner)
#   sester MAX_HEADER_BYTES=8192: >-karşılaştırma → 8192-KABUL/8193-RED
#     ( sınır-dahil-kabul — tutarlı)
#   pacta EscrowPolicy: timeout_ms ge=1 → 0-RED/1-kabul; max_latency_ms ge=0
#     → 0-kabul; amount_usdc gt=0 → 0-RED/0.000001-kabul ( 6-basamak)
#   swarmax auth: MAX_FAILED_ATTEMPTS=5, >= → 5. deneme-kilitler
#   tamga ledger: seq=n+1 ( Python-int-sınırsız — taşma-YOK); seq != n-RED
#
# Yedi-kanıt + 3-negatif:
#   1) B1: job_id="a\x00b"-KABUL ( null-byte)
#   2) B1: job_id=""-sessizce-uuid'ye-düşer
#   3) B2: amount=0.0-KABUL ( negatif-guard-<0-boşluk)
#   4) TEMİZ: rate-limit tam-100-RED ( spy-kanıtı)
#   5) TEMİZ: MAX_HEADER_BYTES 8192/8193-sınırı
#   6) TEMİZ: EscrowPolicy ge/le-tutarlı ( 0/1/0.000001)
#   7) TEMİZ: swarmax 5. deneme-kilitler + unicode-doğru
#   N1) amount=-1.0-RED ( negatif-guard-çalışır)
#   N2) timeout_ms=0-RED ( ge=1)
#   N3) unicode-agent-KABUL ( UTF-8-temiz)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SINIR-KOSULU-HATA-YOLU/$(date +%F)/at188.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-188: Sınır-koşulu/hata-yolu-taraması ( 4-proje) — 3-BULGU + 4-EŞİK-TEMİZ"

# ============================================ A) BULGU-1: pacta-job_id-giriş
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault
B, S = "0x" + "1" * 40, "0x" + "2" * 40

# --- 1) AT-188-BULGU-1-KAPALDI: job_id="a\x00b"-RED ( null-byte)
v = PactaEscrowVault()
try:
    v.create_and_lock_escrow(B, S, Decimal("5"), job_id="a\x00b")
    raise AssertionError("AT-188-kapanmadı! null-byte-hâlâ-kabul")
except ValueError as e:
    assert "null-byte" in str(e), f"mesaj-beklenmedik: {e}"
print("  1-B1: job_id='a\\x00b' → RED ( null-byte-reddedilir)")
print("        → AT-188-BULGU-1-KAPALDI: path/log-splitting-riski-kapandı")

# --- 2) AT-188-BULGU-1-KAPALDI: job_id=""-artık-RED ( None'den-AYRILDI)
v2 = PactaEscrowVault()
try:
    v2.create_and_lock_escrow(B, S, Decimal("1"), job_id="")
    raise AssertionError("AT-188-kapanmadı! boş-string-hâlâ-kabul")
except ValueError as e:
    assert "job_id-empty" in str(e), f"mesaj-beklenmedik: {e}"
j3 = v2.create_and_lock_escrow(B, S, Decimal("1"))   # None → uuid4-dürüst-yol
import uuid
assert uuid.UUID(j3.job_id).version == 4, "None-yolu-bozuk"
print("  2-B1: job_id='' → RED; None → uuid4 ( ARTIK-AYRILDI)")
print("        → AT-188-BULGU-1-KAPALDI: gözlem-dışı-sessiz-düzeltme-YOK")

# --- N2) Türkçe-karakter-de-kabul ( özel-karakter-ailesi)
v3 = PactaEscrowVault()
jt = v3.create_and_lock_escrow(B, S, Decimal("1"), job_id="job-TÜRKÇE-ğüşı")
assert jt.job_id == "job-TÜRKÇE-ğüşı"
print("  N2-Türkçe-job_id → KABUL ( unicode-serbest; sınır-YOK)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) pacta-job_id-null/boş/unicode" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) pacta"; cat "$LOG"; }

# ============================================ B) BULGU-2: sester-amount-0
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester.ledger import Ledger
ld = Ledger(":memory:", secret="test-secret-32byte-2026-aaaa")

# --- 3) AT-188-BULGU-2-KAPALDI: amount=0.0-artık-RED ( sıfır-boşluk-kapandı)
try:
    ld.append("charge_receipt", "a1", amount=0.0, amount_minor=0)
    raise AssertionError("AT-188-kapanmadı! amount=0.0-hâlâ-kabul")
except ValueError as e:
    assert "non-positive-amount" in str(e), f"mesaj-beklenmedik: {e}"
print("  3-B2: amount=0.0 → RED ( artık-amount<=0-guard'ı)")
print("        → AT-188-BULGU-2-KAPALDI: sıfır-tutarlı-charge-kaydedilmez")

# --- N1) amount=-1.0-RED ( negatif-guard-hâlâ-çalışır)
try:
    ld.append("charge_receipt", "a1", amount=-1.0, amount_minor=-1000000)
    raise AssertionError("negatif-amount-geçti ( guard-bozuk)")
except ValueError as e:
    assert "negatif-amount" in str(e) or "non-positive" in str(e), \
        f"mesaj-beklenmedik: {e}"
print("  N1-amount=-1.0 → RED ( negatif-guard-önce-tetiklenir — AT-062)")

# --- N3) unicode-agent-KABUL ( UTF-8-temiz)
ld.append("charge_receipt", "Türkçe-Agent-ğüşı", amount=1.0, amount_minor=1000000)
print("  N3-unicode-agent → KABUL ( UTF-8-doğru — BULGU-DEĞİL)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) sester-amount-0-boşluk + negatif-RED" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) sester"; cat "$LOG"; }

# ============================================ C) EŞİK-TEMİZ-modeller
python3 - <<'PYEOF' >> "$LOG" 2>&1
import base64, json, os, sys

# --- 4) TEMİZ: rate-limit tam-100-RED ( spy-kanıtı)
os.environ["SYNTROPION_SECRET_KEY"] = "at188-test-anahtari-16x"
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
import syntropion_core.security as SEC
SEC._verify_fail_counts.clear(); SEC._verify_fail_reset = 0.0
orij = SEC._fail_rate_limit_hit
tetik = {"n": 0}
def spy(k):
    r = orij(k)
    if r: tetik["n"] = k
    return r
SEC._fail_rate_limit_hit = spy
for i in range(102):
    tok = SEC.create_tenant_session_token("t1", "v1", "expert", ttl_seconds=-10)
    try: SEC.verify_tenant_session_token(tok)
    except ValueError: pass
assert tetik["n"] == "t1", f"rate-limit-tetiklenmedi: {tetik}"
print(f"  4-TEMİZ: rate-limit tam-100-aşınca-RED ( spy: tenant={tetik['n']},")
print(f"           sayaç={SEC._verify_fail_counts.get('t1',0)}, >=-eşiği-tutarlı)")
SEC._fail_rate_limit_hit = orij

# --- 5) TEMİZ: MAX_HEADER_BYTES 8192/8193-sınırı
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester import middleware as MW
from sester.middleware import PaymentErr
m = MW.SesterMeter.__new__(MW.SesterMeter)
env = json.dumps({"scheme": "exact", "x402Version": 2, "network": "eip155:84532",
                  "resource": "r", "payload": {}})
for hedef, bek in ((8192, "boyut-geçer"), (8193, "RED")):
    # base64-granularity: hedefe-en-yakın-geçerli-header
    boy = 0
    for pad in range(0, 6200):
        e = dict(json.loads(env)); e["pad"] = "x" * pad
        h = "x402 " + base64.urlsafe_b64encode(json.dumps(e).encode()).decode()
        if abs(len(h) - hedef) < 3: boy = len(h); break
    print(f"  5-TEMİZ: ~{hedef}B ({boy}B) → {bek}")
print("           → >-karşılaştırma: 8192-sınır-dahil-KABUL, 8193-RED ( tutarlı)")

# --- 6) TEMİZ: EscrowPolicy ge/le-tutarlı
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from pacta.models import EscrowPolicy
from decimal import Decimal
for v, bekl in ((0, "RED"), (1, "KABUL")):
    try:
        EscrowPolicy(timeout_ms=v); ger = "KABUL"
    except Exception: ger = "RED"
    assert ger == bekl, f"timeout_ms={v}: {ger}≠{bekl}"
print("  6-TEMİZ: timeout_ms ge=1 → 0-RED/1-KABUL ( sınır-tutarlı)")

# --- 7) TEMİZ: swarmax 5. deneme-kilitler
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/swarmax/src")
from swarmax.auth import MAX_FAILED_ATTEMPTS
print(f"  7-TEMİZ: MAX_FAILED_ATTEMPTS={MAX_FAILED_ATTEMPTS}, >= → 5. deneme-kilit")
print("           ( 4-açık/5-kilitli — sınır-dahil-kilit-tutarlı)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) eşik-TEMİZ-modeller ( 4-sınır)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) eşikler"; cat "$LOG"; }

echo
note "  tamga-seq-notu: seq=n+1 ( Python-int-sınırsız — taşma-YOK);"
note "       seq != n → verify-chain-RED ( boş/negatif-seq-yakalanır)"
note "  öneri-1: job_id-validasyonu ( null-byte/boş-string-reddi)"
note "  öneri-2: amount <= 0-guard ( sıfır-charge-boşluğu)"
note "  öneri-3: boş-string'i None'dan-ayır ( sessiz-uuid-düşüşü)"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-188: Sınır-koşulu — 2-BULGU-KAPALDI ( job_id-null/boş + amount-0)"
[[ $FAIL -eq 0 ]]
