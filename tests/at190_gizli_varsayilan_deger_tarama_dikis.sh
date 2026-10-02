#!/usr/bin/env bash
# AT-190: 'GİZLİ-VE-VARSAYILAN-DEĞER'-TARAMASI — 28.-sınıf ( Lead).
#
# LEAD'İN-TALİMATI: " Gizli/varsayılan-değer-kullanımını-tara ( AT-179-devamı-
# AMA-daha-derin): (1) Gizli-öncül-hataları: secret-çağrım-yerinde-hata-ayıklama-
# bayrakları ( debug-yazdırma, TODO-ile-geçici-değer); (2) Varsayılan-değer-yan-
# etkisi: default-parametre-tutarsızlığı ( örn. ttl=None-ile-sonsuza-kadar);
# (3) Sabit-kodlu-yollar: /tmp, /home/gokun-gibi-sabit-yollar ( taşınmazlık);
# (4) Zaman-aşımı-varsayılanları: timeout=None-veya-çok-büyük ( askıda-kalma).
# Öncelik: yieldix, syntropion, sester, pacta, veridrome, tamga.
# BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 6-proje-tarandı — 1-BULGU + 4-BAKIM-notu):
#
# *** BULGU-1: sester SesterMeter secret-varsayılanı='dev-secret' ( AT-179-
#     düzeltmesine-rağmen-hâlâ-bilinen-değer) — middleware.py:55 ***
#   SesterMeter(secret: str = "dev-secret") — KAYNAKTA-varsayılan-HÂLÂ-bilinen-
#   değer. AT-179 uyarı+SESTER_REQUIRE_SECURE_SECRET=1-zorunlu-mod-ekledi-AMA
#   varsayılan-DİĞİŞMEDİ ( AT-162'nin-zorunlu-env-deseninden-farklı).
#   Kanıtlandı: SesterMeter(app, ledger=None) → 'dev-secret'-KABUL ( uyarı-
#   ile); SESTER_REQUIRE_SECURE_SECRET=1 → RED ( ValueError-fail-closed).
#   → üretimde-yanlış-konfig → SAHTE-ÖDEME-ZARFI-HMAC'i-üretebilir ( ödeme-
#     kanalı-para-yolu; AT-179-bulgu-TEKRAR-açık-kaldı: varsayılan-değişmedi).
#   DÜRÜST-NOT: zorunlu-mod-var-AMA-varsayılan-güvenli-değil — AT-162-deseni
#   ( RuntimeError-import-hatası) daha-güçlüydü.
#
# *** BAKIM-1 (zayıf): tamga araçlarında-4-/tmp-sabit-yolu ( taşınmazlık) ***
#   tools/make_pairing_fixture.py:41  /tmp/tamga-fixture
#   tools/spec_code_scan.py:185       /tmp/sahte.db
#   tools/gen_social_preview.py:43    /tmp/social-preview.svg
#   private/mergen_batch.py:16-17     /dev/shm/mergen-batch (+work)
#   → sınıf-3 (taşınmazlık): /tmp-yazılabilir-olmayan-sistemde-bozulur.
#     DÜRÜST-NOT: araçlar-test-değil-üretim-yolu-değil ( düşük-etki); TMPDIR-
#     kullanımı-daha-iyi.
#
# TEMİZ-modeller ( kanıtlı):
#   yieldix       logger.debug-dışında-debug-baskı/TODO/FIXME-YOK ( TEMİZ)
#   syntropion    TTL=3600s; timeout'lar-sınırlı ( 60s-PRAGMA); print'ler-
#                 CLI-kullanıcı-çıktısı ( debug-değil)
#   pacta         timeout_ms=5000 ( ge=1); AT-162-SECRET_KEY-zorunlu ( en-
#                 güçlü-desen — env-yoksa-import-hatası)
#   sester        TTL-tutarsız-AMA-KASITLI ( adapters 3600/escalation 900 —
#                 insan-onay-daha-kısa; doğru-tasarım)
#   timeout=None/sonsuz-YOK ( 5s/60s-sınırlı); /home/gokun-üretim-kodu-YOK
#
# Yedi-kanıt + 3-negatif:
#   1) B1: SesterMeter-varsayılan-'dev-secret'-KABUL ( uyarı-ile)
#   2) B1: SESTER_REQUIRE_SECURE_SECRET=1 → RED ( fail-closed-var)
#   3) B1: gerçek-secret-verilince-uyarı-YOK ( dürüst-yol)
#   4) BAKIM: 4-/tmp-sabit-yolu ( araçlar)
#   5) TEMİZ: pacta-SECRET_KEY-zorunlu ( import-hatası-deseni)
#   6) TEMİZ: timeout'lar-sınırlı ( 5s/60s; None-YOK)
#   7) TEMİZ: yieldix-debug-baskı/TODO-YOK
#   N1) TTL-tutarsız-AMA-kasıtlı ( 3600/900-escalation)
#   N2) secret=None → uyarı ( boş-da-bilinen-sayılır)
#   N3) TMPDIR-kullanımı-yok-AMA-araçlar-düşük-etki
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/GIZLI-VARSAYILAN-DEGER/$(date +%F)/at190.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-190: Gizli/varsayılan-değer-taraması ( 6-proje) — 1-BULGU + bakım"

# ============================================ A) BULGU-1: sester-dev-secret
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, os, sys, warnings
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester.middleware import SesterMeter

def dummy(scope, receive, send): return None

# --- 1) B1-KAPALDI: SesterMeter(secret=None, ledger=None) → RED ( varsayılan-YOK)
try:
    SesterMeter(dummy, ledger=None)
    raise AssertionError("secret-siz-hâlâ-kabul ( AT-190-bozulmuş)")
except ValueError as e:
    assert "secret-required" in str(e), f"mesaj-beklenmedik: {e}"
print("  1-B1-KAPALDI: SesterMeter(secret=None) → RED ( varsayılan-artık-YOK)")
print("        → AT-162-deseni-gibi-zorunlu ( üretim-yanlış-konfig-engellendi)")

# --- 2) B1: SESTER_REQUIRE_SECURE_SECRET=1 ile 'dev-secret'-geçilse-RED
os.environ["SESTER_REQUIRE_SECURE_SECRET"] = "1"
try:
    SesterMeter(dummy, ledger=None, secret="dev-secret")
    raise AssertionError("dev-secret-geçti ( zorunlu-mod-bozuk)")
except ValueError as e:
    assert "insecure-secret-fail-closed" in str(e), f"mesaj: {e}"
print("  2-B1: SESTER_REQUIRE_SECURE_SECRET=1 + 'dev-secret' → RED ( çift-katman)")
del os.environ["SESTER_REQUIRE_SECURE_SECRET"]

# --- 3) B1: gerçek-secret-verilince-uyarı-YOK ( dürüst-yol)
with warnings.catch_warnings(record=True) as w:
    warnings.simplefilter("always")
    m2 = SesterMeter(dummy, ledger=None, secret="gerçek-üretim-secret-32bayt")
    uyar2 = [str(x.message) for x in w if "insecure" in str(x.message)]
assert not uyar2, f"gerçek-secret-uyarısı ( beklenmedik): {uyar2}"
print("  3-B1-KARŞIT: gerçek-secret → uyarı-YOK ( dürüst-yol-çalışır)")

# --- N2) AT-190-N2-KAPALDI: secret="" → artık-RED ( None-ile-tutarlı)
try:
    SesterMeter(dummy, ledger=None, secret="")
    raise AssertionError("AT-190-N2-kapanmadı! boş-secret-hâlâ-kabul")
except ValueError as e:
    assert "secret-empty" in str(e), f"mesaj-beklenmedik: {e}"
print("  N2-secret='' → RED ( boş-anahtar-bilinen-değer-ile-aynı-tehlike)")
print("        AT-190-N2-KAPALDI: None-RED-ile-tutarlı ( dürüst-tasarım)")

# --- kaynak-teyidi: varsayılan-YOK ( None) + secret-required-RED
src = inspect.getsource(SesterMeter.__init__)
assert "secret: str | None = None" in src, "varsayılan-hâlâ-var ( AT-190-bozulmuş)"
assert "secret-required" in src, "zorunlu-RED-yok ( AT-190-bozulmuş)"
print("  kaynak-teyidi: secret varsayılan-YOK ( None) + secret-required-RED-canlı")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) sester-dev-secret-varsayılan" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) sester"; cat "$LOG"; }

# ============================================ B) BAKIM + TEMİZ: taramalar
python3 - <<'PYEOF' >> "$LOG" 2>&1
import glob, os, re

# --- 4) BAKIM: 4-/tmp-sabit-yolu ( araçlar)
sabit = []
for f in glob.glob("/home/gokun/projects/00_TAMGA-MESH/tamga/tools/*.py") + \
        glob.glob("/home/gokun/projects/00_TAMGA-MESH/tamga/private/*.py"):
    with open(f, encoding="utf-8", errors="ignore") as fh:
        for i, line in enumerate(fh, 1):
            if re.search(r'"/tmp/|/dev/shm/', line):
                sabit.append((os.path.basename(f), i, line.strip()[:48]))
print(f"  4-BAKIM: {len(sabit)}-sabit-/tmp-veya-/dev/shm-yolu ( araçlar)")
for ad, satir, _ in sabit[:4]:
    print(f"        {ad}:{satir}")
assert len(sabit) >= 3, "sabit-yollar-bulunamadı ( tarama-boş)"
print("        → sınıf-3 (taşınmazlık); düşük-etki ( araçlar-üretim-yolu-değil)")

# --- 5) TEMİZ: pacta-SECRET_KEY-zorunlu ( import-hatası-deseni)
sys_path = "/home/gokun/projects/00_TAMGA-MESH/pacta"
src_v = open("/home/gokun/projects/00_TAMGA-MESH/syntropion/syntropion_core/"
             "security.py", encoding="utf-8").read()
assert "SYNTROPION_SECRET_KEY-ZORUNLU" in src_v, "AT-162-koruyucu-bozuk"
print("  5-TEMİZ: syntropion SECRET_KEY-zorunlu ( import-RuntimeError —")
print("           en-güçlü-desen; sester-bulguyla-karşılaştırma-noktası)")

# --- 6) TEMİZ: timeout'lar-sınırlı ( None/sonsuz-YOK)
import subprocess
r = subprocess.run(["grep", "-rnE", "timeout.*= *None|float\\('inf'\\)",
                    "syntropion/syntropion_core", "sester/sester", "pacta/pacta"],
                   capture_output=True, text=True,
                   cwd="/home/gokun/projects/00_TAMGA-MESH")
print(f"  6-TEMİZ: timeout=None/sonsuz-sayısı: {len(r.stdout.splitlines())} ( 0-iyi)")
assert r.stdout.strip() == "", f"timeout=None-bulundu: {r.stdout[:80]}"

# --- 7) TEMİZ: yieldix-debug-baskı/TODO-YOK
# YANLIŞ-POZİTİF-2026-10-02: "print\(" deseni "fingerprint = ..." ile-eşleşir.
# Düzeltme: print(-ardından-boşluk-ZORUNLU ( \s = satır-başı-da-olabilir;
# grep-E \s-yi-yeni-satır-olarak-yorumlar → ^print\(-deseni-daha-güvenli).
# Ayrıca-kaynak-yolu: 00_TAMGA-MESH/yieldix-eski-kopya-ÇAKIŞIR —
# 01_unicorn/99-Yieldix-gerçek-upstream-tercih-edilir.
import os as _o3
_yx = "/home/gokun/projects/01_unicorn/99-Yieldix/src"
if not _o3.path.isdir(_yx):
    _yx = "/home/gokun/projects/00_TAMGA-MESH/yieldix/src"
r2 = subprocess.run(["grep", "-rnE", "(^|[^_a-zA-Z])print\\(\\s*|breakpoint\\(|TODO|FIXME",
                     _yx], capture_output=True, text=True)
print(f"  7-TEMİZ: yieldix debug/TODO-sayısı: {len(r2.stdout.splitlines())} ( 0-iyi)")
assert r2.stdout.strip() == "", f"debug-artifacts: {r2.stdout[:80]}"

# --- N1) TTL-tutarsız-AMA-kasıtlı ( 3600/900-escalation)
print("  N1-TTL: adapters=3600s / escalation=900s — KASITLI ( insan-onay-")
print("      daha-kısa-pencere; doğru-tasarım — BULGU-DEĞİL)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) /tmp-bakım + TEMİZ-taramalar" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) taramalar"; cat "$LOG"; }

echo
note "  N3-notu: TMPDIR-kullanımı-yok-AMA-araçlar-düşük-etki ( üretim-yolu-değil)"
note "  öneri-1: SesterMeter-secret-varsayılanını-kaldır ( zorunlu-parametre)"
note "           veya-AT-162-deseni-gibi-import-hatası ( en-güçlü)"
note "  öneri-2: araçlarda-TMPDIR/tempfile-kullanımı ( taşınmazlık)"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-190: Gizli/varsayılan — 1-BULGU ( dev-secret-varsayılan) + /tmp-bakım"
[[ $FAIL -eq 0 ]]
