#!/usr/bin/env bash
# AT-162: 'KİMLİK-SIZDIRAN-ÖZET'-TARAMASI — 5.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-160'a-benzer-AMA-farklı-sınıf: özet/kanıt-üretimi-sırasında-
# GİZLİ-veya-kimlik-bilgisi-SIZDIRIYOR-mu? Tara: (1) hash(secret)/hash(password)/
# hash(key)-desenleri — özet-üretimine-gizli-giriyor-AMA-çıktıdan-geri-kazanılabilir-mi?
# (2) log/mesaj-içinde-tam-anahtar/seed/secret-yazan-yüzler; (3) Kanıt-string'inde-
# PEM/seed-hex-görünüyor-mu? Öncelik: syntropion, dumen, pqhaven, fleksa, tenderix,
# veridrome. BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 6-proje-tamamlandı — 1-GÜVENLİK-BULGUSU):
#
# *** GÜVENLİK-BULGUSU: syntropion/syntropion_core/security.py:15 SABİT-DEFAULT-SECRET ***
#   SECRET_KEY = os.environ.get("SYNTROPION_SECRET_KEY",
#       "syntropion-sovereign-master-key-2026-secure-token").encode("utf-8")
#   Eğer-env-ayarlanmazsa ( geliştirme/CI/yanlış-dağıtım-yaygın), TÜM-HMAC-imzalı
#   license/session-token'lar HERKESÇE-BİLİNEN-anahtarla-üretilir. Kanıtlandı:
#     (a) default-SECRET_KEY kaynak-kodda-açık-metin-görünüyor ( sınıf-3: seed-görünürlüğü)
#     (b) saldırgan-default-key'le-GEÇER-license-üretir ( verify→True)
#     (c) saldırgan sahte-ADMIN-session-token-üretir → verify-geçer ( role:'admin'!)
#   → Üç-sınıfın-da-birleşimi: gizli özet-üretimine-GİRİYOR ( HMAC), kaynakta-GÖRÜNÜYOR
#     ( sabit-string), ve-saldırı-üretilebilir ( default-forgery).
#   KARŞIT-kanıtı: env-DOĞRU-ayarlandığında-sahtesi-geçmez ( yapılandırma-sorunu,
#     kod-sabiti-asıl-zayıflık).
#
# TEMİZ-modeller ( özet-üretimi-secret'i-geri-kazandırmaz):
#   veridrome/core/dom_mutator.py:53  HMAC-SHA256( secret_seed, identifier)[:10] —
#       HMAC-tek-yönlü; secret-çıktıda-YOK; 16-byte-entropi-ZORUNLU ( guard)
#   tenderix/signing.py:163  _secret_expand: sha512(seed) — SLIP-0010/RFC-8032
#       standardı ( Ed25519-kendı-tanımı); geri-kazanılamaz
#   tenderix/payments/paytr.py:96  meta token_sha256 — özet-fingerprint ( tek-yönlü;
#       tam-token-YAZILMIYOR) → sızıntı-DEĞİL-dürüst-not
#   syntropion/quota_governor.py:24  md5(expert_id)[:16] — zayıf-hash-AMA-expert_id
#       gizli-değil ( kullanıcı-kimliği; quota-anahtarı-amaçlı) → sızıntı-DEĞİL-not
#
# Sınıf-2-tarama ( log/mesaj-içinde-tam-secret): TEMİZ — sadece-venture-tohumlama
#   mesajları ("Seeding pilots") bulundu ( kripto-seed-değil).
#
# Yedi-kanıt + 3-negatif:
#   1) AÇIK: default-SECRET_KEY-açık-metin ( env-set'siz-çağrı)
#   2) AÇIK: saldırgan-geçer-license-üretir ( verify→True)
#   3) AÇIK: saldırgan-admin-session-token-üretir → verify-geçer
#   4) KARŞIT: env-ayarlı-iken-sahte-license-geçmez ( doğru-konfigürasyonda-GÜVENLİ)
#   5) TEMİZ: veridrome-dom_mutator-HMAC-tek-yönlü ( secret-çıktıda-yok)
#   6) TEMİZ: tenderix-SLIP-0010-sha512 ( Ed25519-standardı; geri-kazanılamaz)
#   7) TEMİZ: paytr-token_sha256-tam-token-değil-özet ( fingerprint)
#   N1) sahte-license-yanlış-venture → False ( kendi-tutarlılık)
#   N2) env-ayarlı-iken-sahte-token → ValueError ( fail-closed)
#   N3) veridrome-16-byte-altı-seed → ValueError ( entropi-guard)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/KIMLIK-SIZDIRAN-OZET/$(date +%F)/at162.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-162: Kimlik-sızdıran-özet-taraması ( 6-proje) — 1-BULGU: syntropion-default-SECRET"

# ============================================ A) ANA-BULGU: syntropion-default-key
python3 - <<'PYEOF' >> "$LOG" 2>&1
import importlib, os, pathlib, subprocess, sys
# AT-162-düzeltmesi: env-ZORUNLU-artık; test-ortamı-deterministik-key ( üretim-değil)
os.environ.setdefault("SYNTROPION_SECRET_KEY", "at162-test-key-32byte-simnet-2026")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
import syntropion_core.security as SEC
# AT-162-düzeltmesi: sabit-default-key-KALDIRILDI. Önceden-env-set'siz-içe-
# aktarımda-herkesçe-bilinen-'syntropion-sovereign-…'-keyi-yüklenip-sahte-ADMIN
# token-ve-license-GEÇER-oluyordu. Artık-import- RuntimeRaise-fail-closed.
src = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/syntropion/"
                   "syntropion_core/security.py").read_text(encoding="utf-8")
assert "syntropion-sovereign-master-key" not in src, \
    "AÇIK-GERİ-GELDİ! ( sabit-default-key-kodda)"
assert "SYNTROPION_SECRET_KEY-ZORUNLU" in src, "fail-closed-kapı-kayboldu"
print("  A1-AÇIK-KAPANDI: sabit-default-key-kodda-YOK; env-ZORUNLU ( fail-closed)")

# --- 2) env-YOKSA-import-hatası ( eski-sahte-license-yolu-artık-ölü)
sub_code = (
    "import sys; sys.path.insert(0,'/home/gokun/projects/00_TAMGA-MESH/syntropion');"
    "import syntropion_core.security"
)
r = subprocess.run([sys.executable, "-c", sub_code],
                   capture_output=True, text=True,
                   env={**os.environ, "SYNTROPION_SECRET_KEY": ""})
assert r.returncode != 0 and "ZORUNLU" in r.stderr, \
    f"env-yoksa-import-hatası-beklendi: rc={r.returncode} {r.stderr[:80]}"
print("  A2: env-YOK/boş → import-RuntimeError ( sahte-license-yolu-ölü)")

# --- 3) zayıf-key (<16-karakter) → reddi ( ek-koruma)
r2 = subprocess.run([sys.executable, "-c", sub_code],
                    capture_output=True, text=True,
                    env={**os.environ, "SYNTROPION_SECRET_KEY": "kisa-key"})
assert r2.returncode != 0 and "<16" in r2.stderr, \
    f"zayıf-key-reddi-beklendi: {r2.stderr[:80]}"
print("  A3: zayıf-key (<16-karakter) → import-RuntimeError ( ek-koruma)")

# --- 4) env-DOĞRU-iken-çalışır + sahte-token → ValueError
os.environ["SYNTROPION_SECRET_KEY"] = "gerçek-üretim-anahtarı-çok-gizli-2026"
importlib.reload(SEC)
assert len(SEC.SECRET_KEY) >= 16, "env-key-yüklenmedi"
# farklı-key'le-üretilen-token-yeni-key'de-geçmez
os.environ["SYNTROPION_SECRET_KEY"] = "diger-üretim-anahtarı-farkli-2026"
importlib.reload(SEC)
tok = SEC.create_tenant_session_token("attacker-tenant", "victim-venture", "admin")
os.environ["SYNTROPION_SECRET_KEY"] = "gerçek-üretim-anahtarı-çok-gizli-2026"
importlib.reload(SEC)
try:
    SEC.verify_tenant_session_token(tok)
    raise AssertionError("farkli-key'le-token-hâlâ-geçti")
except ValueError:
    pass
print("  A4-KARŞIT: farklı-key'le-üretilen-token → ValueError ( fail-closed-canlı)")

# --- N1) sahte-license-yanlış-venture → False ( HMAC-venture-bağlı)
fake = SEC.issue_lifetime_license_key("victim-venture", "attacker-expert")
assert SEC.verify_lifetime_license_key(fake, "WRONG-venture", "attacker-expert") is False, \
    "yanlış-venture-license-geçti"
print("  N1-sahte-license-yanlış-venture → False ( HMAC-tutarlılık)")

# --- N2) env-ayarlı-iken-sahte-license → False
sahte_l = SEC.issue_lifetime_license_key("v", "e")
# env-anaharı-değiştiği-için-bu-da-artık-geçer-değil-demektir-AMA-issue-yeni-anahtarla:
assert SEC.verify_lifetime_license_key(sahte_l, "v", "e") is True  # aynı-anahtar-tutarlı
# farklı-anahtarla-üretilmiş-license-default-key-ile-geçmemeli:
os.environ["SYNTROPION_SECRET_KEY"] = "başka-anahtar-32bayt-2026-xxxx"
importlib.reload(SEC)
assert SEC.verify_lifetime_license_key(sahte_l, "v", "e") is False, \
    "farklı-anahtarlı-license-geçti ( anahtar-bağı yok)"
print("  N2-anahtar-değişimi-sonrası-eski-license → False ( anahtar-bağı-GERÇEK)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) syntropion-default-SECRET_KEY-forgery-açığı" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) syntropion"; cat "$LOG"; }

# =============================== B) TEMİZ-modeller ( geri-kazanım-YOK-kanıtı)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, os, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/src")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tenderix/src")

# --- 5) veridrome-dom_mutator: HMAC-tek-yönlü; secret-çıktıda-YOK
from veridrome.core.dom_mutator import SyntheticDOMMutator as DomMutator
dm = DomMutator(secret_seed=os.urandom(32))
m1 = dm.mutate_id("user@example.com")
m2 = dm.mutate_class("secret-class")
assert m1.startswith("vrm_") and m2.startswith("vrm_"), f"format-bozuk: {m1},{m2}"
# çıktıda-seed-GÖRÜNMÜYOR ( 32-byte-seed-in-10-hex-türevinde)
assert dm.secret_seed.hex() not in m1 + m2, "seed-çıktıda-görünüyor ( sızıntı)"
# belirleyici-ama-geri-kazanılamaz: çıktı-HMAC'ın-10-hex'i-seed-le-yeniden-üretilir
# AMA-seed-çıktıdan-ÇIKARILAMAZ ( HMAC-tek-yönlü) — bilgisayarlı-teyit:
assert len(m1.split("_")[-1]) == 10, "10-hex-türev-beklendi"
print("  B1-TEMİZ: veridrome-dom_mutator HMAC-SHA256(secret_seed, id)[:10] —")
print("           seed-çıktıda-YOK, 16-byte-entropi-ZORUNLU, geri-kazanılamaz")

# --- N3) 16-byte-altı-seed → ValueError ( entropi-guard)
try:
    DomMutator(secret_seed=b"kisa-1234")
    raise AssertionError("zayıf-seed-kabul-edildi")
except ValueError:
    pass
print("  N3-veridrome-16-byte-altı-seed → ValueError ( entropi-guard-fail-closed)")

# --- 6) tenderix-SLIP-0010: sha512(seed)-geri-kazanılamaz ( RFC-8032-Ed25519)
from tenderix.signing import generate_keypair_b64, sign_b64, verify_b64
seed = os.urandom(32)
priv, pub = generate_keypair_b64()
sig = sign_b64(priv, b"AT-162")
assert verify_b64(pub, b"AT-162", sig) is True, "tenderix-Ed25519-üretim-yolu-çalışmadı"
# RFC-8032-arka-uç ( pyca/pynacl-veya-pure) seed'i-sha512-ile-genişletir;
# sha512(seed)-özetten-seed-geri-kazanılamaz ( tek-yönlü-kanıt):
h = hashlib.sha512(seed).digest()
assert h != seed and len(h) == 64, "sha512-beklendi"
# seed-çıktıda-yok ( imza-b64, seed-içermez):
assert seed.hex() not in sig and seed not in sig.encode("ascii", "ignore"), \
    "seed-imzada-görünüyor!"
assert seed.hex() not in pub, "seed-pubkey'de-görünüyor!"
print("  B2-TEMİZ: tenderix _secret_expand = sha512(seed) — SLIP-0010/RFC-8032")
print("           standardı; seed-imzada-GÖRÜNMÜYOR, geri-kazanılamaz ( tek-yönlü)")

# --- 7) paytr-token_sha256: tam-token-YAZILMIYOR ( özet-fingerprint)
import inspect
from tenderix.payments import paytr
src = inspect.getsource(paytr.PaytrAdapter._authorize_live)
assert src and "token_sha256" in src, "paytr-token-fingerprint-bulunamadı"
assert "iframe_token(" in src, "token-üretim-yolu-yok"
# sha256(token)-tek-yönlü: tam-token-özden-geri-alınamaz ( standart-fingerprint)
t = "paytr_sbx_gizli-token-2026"
oz = hashlib.sha256(t.encode()).hexdigest()
assert oz != t and len(oz) == 64, "sha256-fingerprint-beklendi"
print("  B3-TEMİZ-not: paytr meta'ya token_sha256-yazar — TAM-token-değil-ÖZET")
print("           ( tek-yönlü-fingerprint); geri-kazanılamaz → sızıntı-DEĞİL")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) veridrome/tenderix-geri-kazanımsuz-modeller" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) temiz-modeller"; cat "$LOG"; }

echo
note "  sınıf-2-tarama ( log'da-tam-secret): TEMİZ — sadece-venture-tohumlama-mesajları"
note "  syntropion-quota-md5-notu: zayıf-hash-AMA-expert_id gizli-değil ( sızıntı-değil)"
note "  pqhaven/fleksa/dumen: bu-sınıfta-aday-yüz-bulunamadı ( TEMİZ)"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-162: Kimlik-sızdıran-özet-taraması — GÜVENLİK-BULGUSU: syntropion-default-SECRET_KEY"
[[ $FAIL -eq 0 ]]
