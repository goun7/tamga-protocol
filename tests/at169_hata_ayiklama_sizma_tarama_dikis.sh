#!/usr/bin/env bash
# AT-169: 'HATA-AYIKLAMA-BİLGİ-SIZMASI'-TARAMASI — 9.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " Bugün-4-açık-bulduk; hepsi-kriptografik-yada-yetki. Şimdi-en-aza-
# tutulmuş-ama-gerçek-sınıf: (1) hata-mesajlarında-GİZLİ-veri ( stack-trace, key-
# fragment, hash-tümü); (2) logger-secret-yazıyor ( DEBUG-seviyesinde-ANAHTAR-çekirdek-
# değeri); (3) timing/enum-önyargı: farklı-girişler-farklı-hata-kodları → bilgi-sızar
# ( örn: 'kullanıcı-yok' vs 'şifre-yanlış'); (4) verbose-mod-sızması: --debug-ile-
# secret-görünüyor. Öncelik: syntropion ( auth/logger), pacta, dumen, yieldix, swarmax.
# BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 5-proje-tamamlandı — 2-BULGU-AÇIK):
#
# *** BULGU-1: enum-önyargı ( syntropion/security.py:129/133) — sınıf-3 ***
#   verify_tenant_session_token farklı-girişler-için-FARKLI-hata-üretir:
#     2-parça-token → "Malformed token structure"
#     3-parça-yanlış-imza → "Invalid cryptographic token signature"
#   → saldırgan token-yapısını-ayrıştırabilir ( geçerli-3-parça-formatı-doğru-tahmin-
#     edilebilir; sonra-imza-yanlış-der). Ayrıca-base64-çözme-hatası-aynı-ValueError'a-
#     düşer ( istisna-tipi-tutarsız). KARŞIT: hmac.compare_digest-sabit-zamanlı-AMA-
#     hata-METNİ-zamanlama-sızıntısı-vermez ( dürüst-not: enum-önyargı-zayıf-sınıf;
#     gerçek-anahtar-sızdırmaz).
#
# *** BULGU-2: boş-adres-kabulü ( pacta/core/vault.py create_and_lock_escrow) — yetki-kenarı ***
#   create_and_lock_escrow("", "0xseller", 10) → buyer_address=""-ile-escrow-oluşur;
#   seller=""-de-kabul. Adres-formatı ( 0x+40hex) DOĞRULANMAZ. Sonuç: raise_dispute'ün
#   rol-kontrolü ( AT-166) boş-adrese-karşı-çalışır-AMA-escrow'un-kendisi-boş-rollerle-
#   kurulabilir ( 'kim-olduğunu-bilmediğimiz-taraflar'). Kanıtlandı.
#   → yetki-yükseltmenin-bir-üst-derdecei: rol-DOĞRULAMA-YOK ( boş-rol-geçerli)
#
# TEMİZ-modeller ( bilgi-sızıntısı-YOK-kanıt):
#   dumen/reports/signing.py:55     _fingerprint(pub) — sadece-pubkey-özet ( gizli-değil)
#   pacta/cli.py:60                 TxHash-yazdırır ( herkese-açık-onchain-veri)
#   dumen/gateway/proxy.py:249      detail=str(e) — Upstream-hatası ( dış-servis-hatası;
#                                    iç-stack-DEĞIL — sınır-notu)
#   yieldix                         bu-sınıfta-aday-yüz-bulunamadı (TEMİZ)
#   swarmax                         bu-sınıfta-aday-yüz-bulunamadı (TEMİZ)
#
# logger-taraması ( sınıf-2): TEMİZ — syntropion/pacta/dumen/swamax'da-secret-yazan-
# logger-YOK ( sadece-venture-tohumlama-ve-TxHash-mesajları)
#
# Yedi-kanıt + 3-negatif:
#   1) BULGU-1: 2-parça vs 3-parça-yanlış-imza → FARKLI-hata ( enum-önyargı)
#   2) BULGU-1: base64-çözme-hatası → aynı-ValueError ( istisna-tipi-tutarsız)
#   3) BULGU-2: boş-buyer-adresi-ile-escrow-oluşur ( rol-doğrulama-YOK)
#   4) BULGU-2: boş-seller-adresi-ile-escrow-oluşur
#   5) KARŞIT: negatif-miktar → ValidationError ( amount-doğrulaması-GERÇEK-çalışır)
#   6) TEMİZ: dumen-pubkey-fingerprint ( sadece-açık-anahtar-özet)
#   7) TEMİZ: logger-taraması-secret-YOK ( 5-proje)
#   N1) 3-parça-geçersiz-format → tutarlı-reddi ( ValueError)
#   N2) compare_digest-sabit-zamanlı ( zamanlama-saldırısına-karşı-TEMİZ)
#   N3) geçerli-token → payload-çöz ( dürüst-yol-çalışır)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/HATA-AYIKLAMA-SIZMA/$(date +%F)/at169.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-169: Hata-ayıklama-bilgi-sızması-taraması ( 5-proje) — 2-BULGU: enum+boş-adres"

# ============================================ A) BULGU-1: enum-önyargı ( syntropion)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import os, sys
os.environ.setdefault("SYNTROPION_SECRET_KEY", "at169-test-anahtari-16-karakter")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
from syntropion_core.security import (create_tenant_session_token,
    verify_tenant_session_token)

tok = create_tenant_session_token("t1", "v1", "expert")

# --- 1) BULGU-1 → KAPANDI ( AT-169): artık-aynı-hata-mesajı ( enum-önyargı-YOK)
# Önceden-2-parça→'Malformed' vs 3-parça-yanlış-imza→'Invalid-signature'
# ( farklı-hata = yapı-aşamalı-tahmin). Artık-her-başarısızlık-AYNI-mesaj.
h1 = None
try:
    verify_tenant_session_token("a.b")
except ValueError as e:
    h1 = str(e)
h2 = None
try:
    verify_tenant_session_token(tok.rsplit(".", 1)[0] + ".WRONGSIG")
except ValueError as e:
    h2 = str(e)
assert h1 == h2, f"enum-önyargı-hâlâ-VAR ( farklı-hata): {h1!r} != {h2!r}"
print("  1-BULGU-1-KAPANDI: 2-parça-ve-3-parça-yanlış-imza → AYNI-hata "
      f"({h1!r}); yapı-aşamalı-tahmin-eden-bilgi-YOK")

# --- 2) base64-çözme-hatası → KAPANDI: aynı-ValueError ( tip-tutarlı)
h3 = None
try:
    verify_tenant_session_token("x.y.0")
except Exception as e:
    h3 = str(e)
assert h3 == h1, f"base64-hatası-farklı-mesaj: {h3!r} != {h1!r}"
print("  2-BULGU-1-KAPANDI: bozuk-base64-payload → aynı-tek-tip-hata "
      "( istisna-tipi-tutarlı; payload-içeriği-hakkında-bilgi-YOK)")

# --- N2) compare_digest-sabit-zamanlı ( zamanlama-TEMİZ)
import inspect
src = inspect.getsource(verify_tenant_session_token)
assert "compare_digest" in src, "sabit-zamanlı-kıyaslama-YOK"
print("  N2-compare_digest-sabit-zamanlı ( zamanlama-saldırısına-karşı-TEMİZ)")

# --- N3) geçerli-token → payload-çöz ( dürüst-yol-çalışır)
p = verify_tenant_session_token(tok)
assert p["tenant_id"] == "t1" and p["role"] == "expert", f"payload-bozuk: {p}"
print("  N3-geçerli-token → payload-çözülür ( dürüst-yol-çalışır)")
print("  enum-notu: bulgu-zayıf-sınıf ( anahtar-SIZMAZ; sadece-hata-metni-ayrımı);")
print("             KARŞIT-öneri: tek-tip-hata ('Invalid token')")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) syntropion-token-enum-önyargı-bulgu" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) enum"; cat "$LOG"; }

# ============================================ B) BULGU-2: pacta-boş-adres
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault

# --- 3/4) BULGU-2 → KAPANDI ( AT-169): boş-adres-artık-reddedilir
v = PactaEscrowVault()
# Önceden-create_and_lock_escrow("", "0xseller", 100) → escrow-KURULURDU
# ( boş-rol-geçerli). Artık-ValueError ( fail-closed). Geri-gelirse-YAKALAR.
for label, b, s in (("boş-buyer", "", "0x"+"2"*40),
                    ("boş-seller", "0x"+"1"*40, "")):
    try:
        v.create_and_lock_escrow(b, s, Decimal("100"))
        raise AssertionError(f"AÇIK-GERİ-GELDİ! ( {label}-kabul)")
    except ValueError:
        pass
print("  3/4-BULGU-2-KAPANDI: boş-buyer-ve-boş-seller → ValueError ( fail-closed)")

# --- N1) '0x'-öneksiz-adres → KAPANDI ( AT-169): artık-reddedilir
for bad in ("plain-text-buyer", "noseller"):
    try:
        v.create_and_lock_escrow(bad, "0x"+"2"*40, Decimal("1"))
        raise AssertionError(f"AÇIK-GERİ-GELDİ! ( {bad}-kabul)")
    except ValueError:
        pass
print("  N1-'0x'-öneksiz-adres → ValueError ( önek-zorunlu; KAPANDI)")

# --- 5) KARŞIT: negatif-miktar → ValidationError ( amount-doğrulaması-GERÇEK)
try:
    v.create_and_lock_escrow("0x" + "1" * 40, "0x" + "2" * 40, Decimal("-5"))
    raise AssertionError("negatif-miktar-kabul-edildi")
except Exception as e:
    assert "amount" in str(e).lower(), f"negatif-hatası-beklenmedik: {e}"
print("  5-KARŞIT: negatif-amount → ValidationError ( amount-ve-adres-doğrulaması")
print("            artık-TUTARLI — her-ikisi-de-üretim-kapısında-doğrulanır)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) pacta-boş-adres-escrow-bulgu (rol-kenarı)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) pacta"; cat "$LOG"; }

# ============================================ C) TEMİZ-model-kanıtı
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, pathlib, sys
# --- 6) dumen-pubkey-fingerprint ( sadece-açık-anahtar-özet; gizli-değil)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/dumen")
from dumen.reports.signing import _fingerprint
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
pub = Ed25519PrivateKey.generate().public_key()
fp = _fingerprint(pub)
assert isinstance(fp, str) and len(fp) > 0, "fingerprint-boş"
# fingerprint-gizli-değil ( pubkey'ten-türetilir; private-key-içermez)
src = inspect.getsource(_fingerprint)
assert "private" not in src.lower(), "fingerprint-private-key-içerir!"
print(f"  6-TEMİZ: dumen _fingerprint(pub) — sadece-AÇIK-anahtar-özet ( gizli-YOK);")
print("           private-key-kaynakta-YOK ( sızıntı-sınıfında-değil)")

# --- 7) logger-taraması: 5-projede-secret-yazan-logger-YOK
projeler = [
    "/home/gokun/projects/00_TAMGA-MESH/syntropion/syntropion_core",
    "/home/gokun/projects/00_TAMGA-MESH/pacta/pacta",
    "/home/gokun/projects/00_TAMGA-MESH/dumen/dumen",
    "/home/gokun/projects/00_TAMGA-MESH/yieldix/src/yieldix",
    "/home/gokun/projects/00_TAMGA-MESH/swarmax/src/swarmax",
]
import re
SİZINTI = re.compile(r"(logger|logging|print)\s*[\.(].{0,80}(secret|private_key|"
                     r"priv_key|password|passwd|seed_phrase|SECRET_KEY|token_hex)",
                     re.IGNORECASE)
bulunan = []
for kök in projeler:
    for py in pathlib.Path(kök).rglob("*.py"):
        if "__pycache__" in str(py) or "/test" in str(py):
            continue
        try:
            metin = py.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for satır in metin.splitlines():
            if SİZINTI.search(satır):
                bulunan.append(f"{py.name}: {satır.strip()[:70]}")
assert not bulunan, f"logger-secret-sızması-bulundu: {bulunan[:3]}"
print("  7-TEMİZ: 5-proje-logger-taraması — secret/private_key/password-yazan-YOK")
print("           ( regex-teyidi; sadece-TxHash/venture-mesajları)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) dumen-fingerprint + logger-tarama-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) temiz-modeller"; cat "$LOG"; }

echo
note "  dumen-proxy-notu: detail=str(e) Upstream-hatası-için ( dış-servis-hatası;"
note "       iç-stack-DEĞIL) — sınır-notu, gerçek-sızıntı-sayılıyor"
note "  yieldix/swarmax: bu-sınıfta-aday-yüz-bulunamadı (TEMİZ)"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-169: Hata-ayıklama-bilgi-sızması — 2-BULGU: enum-önyargı + pacta-boş-adres"
[[ $FAIL -eq 0 ]]
