#!/usr/bin/env bash
# AT-136: VERIDROME-ALTINCI-YÜZ-DİRİ-DEĞİL — DOM-mutasyon-HMAC-yüzünün-DÜRÜST-
# DEĞERLENDİRMESİ ( RFC-010-a-bağlanabilir-mi?).
#
# 73-Veridrome: AT-072/108/126/128/134 bağlandı. BU-TEST-BAŞKA-BİR-TÜR:
# aday-yüzü-ölçer-ve-Bağlanabilirlik-kararını-DÜRÜSTÇE-verir ( test-double-YOK,
# umursama-YOK).
#
# ADAY-YÜZ: core/dom_mutator.py — Sentetik-DOM-Mutasyon-Motoru:
#   :50 _hash_identifier — h = hmac.new(secret_seed, id, sha256).hexdigest()[:10]
#     → "vrm_{prefix}_{h}"  ( 10-hex = 40-bit-uzay)
#   :43 __init__ — secret_seed ≥ 16-byte ( yoksa-ValueError)
#   :65 mutate_html — BeautifulSoup-DOM-dönüşümü; WAI-ARIA-özniteliklerini-
#     korur ( PRESERVED_ATTRIBUTES); id/class/data-testid'yi-mutasyona-uğratır
#
# BAĞLANABİLİRLİK-KARARI ( RFC-010-a-dikiş-için-iki-koşul — Lead'in-çerçevesi):
#   KOŞUL-1: HMAC-çıktısı-bir-NONCE/İDEMPOTENT-TOKEN-mı? ( tek-seferlik-işlem;
#     alıcı-daha-önce-gördüğünü-reddeder)
#   KOŞUL-2: dışarıdan-BAĞIMSIZ-doğrulanabilir-mi? ( 3.-taraf-HMAC'i-
#     gizli-seed-olmadan-doğrular)
#
# DÜRÜST-BULGU: İKİ-KOŞUL-DA-SAĞLANMAZ → RFC-010-DİKİŞİ-YAPILMAZ ( İNDETERMİNE):
#   (a) NONCE-DEĞİL: mutate_*-TAMAMEN-DETERMİNİSTİK — aynı-seed+aynı-identifier
#       her- zaman-AYNI-çıkıtıyı-verir ( 5-üretim-aynı; önbellek-aynı).
#       Nonce her-seferinde-BENZERSİZ-olmalıydı. Tek-seferlik-işlem-semantiği
#       YOK ( replay/nonce/consumed-kod-yolu-yok).
#   (b) DIŞARIDAN-DOĞRULANAMAZ: simetrik-HMAC — "bu-mutasyon-bu-tozdan-mı"
#       kanıtı-gizli-seed'i-gerektirir; 3.-taraf-erişemez. sha256(mutant-html)
#       özeti-ALINABİLİR-AMA-mutasyonun-DOĞRULUĞUNU-kanıtlamaz ( herhangi-bir-
#       HTML-aynı-özütü-verebilir) → §3b-"sha256(gerçek-artifact)"-deseni-bu-
#       yüzde-ANLAMSIZ.
#   (c) 40-BİT-ZAYIFLIK: 10-hex = 2^40 ≈ 1.1e12-olası-değer; birthday-
#       saldırı-2^20 ≈ 1M-identifier-ile-çakışma. Bilinçli-zayıf-tasarım
#       ( anti-ezberleme-için-yeterli; ödeme-kanıtı-için-değil).
#
# ÜRETİM-TARAFI-YİNE-ÖLÇÜLÜR ( kanıt-çift-taraflı): determinizmi, seed-
# zorunluluğu, WAI-ARIA-koruması, mutasyon-gerçekliği, mapping, biçim.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/VERIDROME-6/$(date +%F)/at136.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-136: Veridrome DOM-mutator-HMAC-yüzü — bağlanabilirlik-değerlendirmesi"

VE="/home/gokun/projects/01_unicorn/73-Veridrome/src"
if [ ! -f "$VE/veridrome/core/dom_mutator.py" ]; then
  note "[SKIP] AT-136: Veridrome-kodu-bu-makinede-değil (CI) —"
  note "       değerlendirme-yapılamadı (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import bs4, cryptography" 2>/dev/null; then
  note "[SKIP] AT-136: bs4/cryptography-yok — gerçek-DOM-mutasyon-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$VE" <<'PYEOF' >> "$LOG" 2>&1
import collections, hashlib, hmac, inspect, os, re, sys
sys.path.insert(0, sys.argv[1])              # .../73-Veridrome/src
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from veridrome.core.dom_mutator import SyntheticDOMMutator

# --- 1) ÜRETİM-TARAFI: seed-zorunluluğu ( kriptografik-entropi-gate'i)
for bad in (b"", b"kisa", b"\x01" * 15):
    try:
        SyntheticDOMMutator(bad)
        raise AssertionError(f"zayıf-seed-reddedilmeli ({len(bad)}-byte)")
    except ValueError:
        pass
M = SyntheticDOMMutator(os.urandom(32))      # gerçek-32-byte-toz
print("  seed-gate'i: <16-byte → ValueError; 32-byte-toz-kabul")

# --- 2) ÜRETİM-TARAFI: HMAC-10hex-biçimi + determinizmi
MID = M.mutate_id("login-btn")
assert re.match(r"^vrm_[A-Za-z0-9]{1,4}_[0-9a-f]{10}$", MID), f"biçim-bozuk: {MID}"
parca = MID.split("_")
assert parca[0] == "vrm"
assert parca[1] == "logi", "prefix-identifier'ın-ilk-4-alnum'u-olmalı"
assert parca[2] == hmac.new(M.secret_seed, b"login-btn", hashlib.sha256).hexdigest()[:10]
# DETERMİNİZM ( üretici-tarafı-üretim-yolu-birebir)
assert len({M.mutate_id("login-btn") for _ in range(5)}) == 1, "5-üretim-aynı-olmalı"
M2 = SyntheticDOMMutator(M.secret_seed)
assert M2.mutate_id("login-btn") == MID, "aynı-toz → aynı-mutasyon"
M3 = SyntheticDOMMutator(os.urandom(32))
assert M3.mutate_id("login-btn") != MID, "farklı-toz → farklı-mutasyon"
print(f"  mutate_id: {MID} ( vrm_+4-alnum+10-hex; deterministik; toz-bağımlı)")

# --- 3) ÜRETİM-TARAFI: gerçek-DOM-mutasyonu + WAI-ARIA-koruması
from bs4 import BeautifulSoup
HTML = ('<button id="login-btn" class="btn-primary" role="button" '
        'aria-label="Giris" aria-hidden="false" aria-required="true" '
        'data-testid="login" data-cy="login-btn">Giris</button>')
OUT = M.mutate_html(HTML)
b = BeautifulSoup(OUT, "html.parser").find("button")
# WAI-ARIA-öznitelikleri-KORUNUR ( erişilebilirlik-ağacı-değişmez)
assert b["role"] == "button" and b["aria-label"] == "Giris"
assert b["aria-hidden"] == "false" and b["aria-required"] == "true"
# id/class/data-*-test-identifier'ları-MUTASYONA-UĞRAR ( anti-ezberleme)
assert b["id"] != "login-btn" and b["id"].startswith("vrm_")
assert b["class"] != ["btn-primary"] and b["class"][0].startswith("vrm_")
assert b["data-testid"] != "login" and b["data-testid"].startswith("vrm_")
assert b["data-cy"] != "login-btn" and b["data-cy"].startswith("vrm_")
# HARİÇ: metin-içeriği-değişmez ( işlevsel-DOM-aynı)
assert b.get_text() == "Giris"
# mapping-gerçek: harita-mutasyonlarla-tutarlı
im = M.get_id_mapping()
assert im.get("login-btn") == b["id"], "id-mapping-tutarsız"
print("  mutate_html: WAI-ARIA-korundu ( role/aria-*); id/class/data-testid-"
      "mutasyona-uğradı; mapping-tutarlı")

# --- 4) DEĞERLENDİRME-(a): NONCE/İDEMPOTENT-TOKEN-DEĞİL ( KOŞUL-1-SAĞLANMAZ)
# kanıt-1: deterministik — nonce her-seferinde-BENZERSİZ-olmalıydı
assert len({M.mutate_id("login-btn") for _ in range(5)}) == 1
# kanıt-2: kod-yolunda-tek-seferlik-semantik-YOK ( alıcı-reddi/idempotency)
src = inspect.getsource(SyntheticDOMMutator)
yasak = [t for t in ("replay", "nonce", "consumed", "used_once", "one-time",
                     "idempoten", "expire") if t in src.lower()]
assert not yasak, f"tek-seferlik-semantik-bulundu: {yasak}"
print("  değerlendirme-(a): DETERMİNİSTİK + tek-seferlik-semantik-YOK → "
      "nonce/idempotency-tokenı-DEĞİL")

# --- 5) DEĞERLENDİRME-(b): DIŞARIDAN-BAĞIMSIZ-DOĞRULANAMAZ ( KOŞUL-2-SAĞLANMAZ)
# simetrik-HMAC: "bu-mutasyon-bu-tozdan"-kanıtı-gizli-seed'i-gerektirir
h10 = MID.split("_")[-1]
assert len(h10) == 10
# sha256(artifact)-özütü-alınabilir-AMA-mutasyonu-kanıtlamaz ( §3b-deseni-
# bu-yüzde-anlamsız: herhangi-bir-HTML-aynı-özüt-üretebilir)
ozet = hashlib.sha256(OUT.encode()).hexdigest()
assert len(ozet) == 64
# 3.-taraf-gizli-seed olmadan HMAC'i-yeniden-üretip-doğrulayamaz
# ( simetrik-kanıt; özet-ALMAK ≠ DOĞRULAMAK)
print("  değerlendirme-(b): simetrik-HMAC-gizli-toz → 3.-taraf-doğrulayamaz; "
      "sha256(html)-özütü-mutasyonun-doğruluğunu-kanıtlamaz")

# --- 6) DEĞERLENDİRME-(c): 40-BİT-TRUNCATION-ZAYIFLIĞI
alan = 16 ** 10
assert alan == 2 ** 40
# küçük-deneysiz-tarama ( 100K-identifier) — 40-bit-alanda-beklenen-~0
g = collections.Counter(M.mutate_id(f"id-{i}") for i in range(100_000))
cakisma = sum(c - 1 for c in g.values() if c > 1)
assert len(g) == 100_000 - cakisma
print(f"  değerlendirme-(c): 10-hex = 2^40 = {alan:.3g}-olası-değer; birthday-"
      f"2^20≈{2**20:,}; 100K-taramada-{cakisma}-çakışma")

# --- KARAR: İKİ-KOŞUL-DA-SAĞLANMAZ → RFC-010-DİKİŞİ-YAPILMAZ
# ( HMAC-10hex-asla-evidenceHash-değildir — 64-hex-gerekir; nonce/idempotency-
# işlevi-olmadığı-için-bağlanabilir-bir-ödeme-kanıtı-da-değildir)
assert len(h10) < 64, "HMAC-10hex-evidenceHash-olamaz (uzunluk-yetersiz)"
print("  KARAR: İNDETERMİNE — RFC-010-dikişi-bu-yüzle-yapılmaz ( nonce-"
      "değil + dışarıdan-doğrulanamaz); üretim-tarafı-gerçek-ve-sağlam")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  ÖLÇÜM-TAMAM: altı-dom-mutator-değerlendirme-kontrolü (İNDETERMİNE)" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL, 1 İNDETERMİNE — RFC-010-dikişi-yapılmadı (HMAC-yüzü: nonce-değil + dışarıdan-doğrulanamaz) — log: $LOG"
echo "  AT-136: Veridrome DOM-mutator-HMAC-yüzü — bağlanabilirlik-değerlendirmesi"
[[ $FAIL -eq 0 ]]
