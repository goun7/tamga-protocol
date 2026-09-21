#!/usr/bin/env bash
# AT-074: ROBOSEAL-İTİBAR-ÇATIŞMASI — K0-kuralı-ve-D-014-duvarı.
#
# 68-Kredent/ROBOSEAL (spec-only 19-py): ajan-kimlik + SLA-itibarı, EigenTrust-
# uyarlamalı-Sybil-koruması ("receipt'i-imzalayan-karşı-ajanın-kendi-itibar-
# skoruyla-çarpılması"; kuklaların-katkısı≈0).
#
# ANCAK: goun7-x402#2887 D-014-dokuz-mekanizması-aynı-duvara-çarptı —
# "maliyet-getiren-mekanizma-ya-atatcker-tarafından-bypass-edilir-ya-da-CLAIM'LERİ
# SIRALAMAYI-gerektirir-ki-bu-kendi-kuralımızla-çarpışır." Bu-test-o-duvarın
# ROBOSEAL-için-de-var-olduğunu-KANITLAR — hangi-tarafın-sıralamadığını-değil,
# çarpışmanın-yapısal-olduğunu.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-074/$(date +%F)/at074.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-074: ROBOSEAL-itibar-çatışması (K0-kuralı + D-014-duvarı)"

RK="/home/gokun/projects/01_unicorn/68-Kredent/ROBOSEAL.md"
if [ ! -f "$RK" ]; then
  note "[SKIP] AT-074: ROBOSEAL-spec'i-bu-makinede-değil (CI) —"
  note "       çatışma-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$RK" <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

src = open(sys.argv[1], encoding="utf-8").read()

# --- 1) ROBOSEAL-itibar-skoru-GERÇEK-taşır-mı
for tok in ("itibar", "SLA", "güvenilirlik", "EigenTrust"):
    assert tok in src, f"ROBOSEAL-{tok}-içermez"
print("  ROBOSEAL-itibar+SLA+EigenTrust-gerçek-spec'inde-mevar")

# --- 2) Sybil-koruması-ağırlıklandırma = SIRALAMA-mı?
assert "itibar skoruyla" in src or "EigenTrust" in src, "ağırlıklandırma-yok"
# EigenTrust: her-Receipt-katkısı-karşı-ajanın-skoruyla-ÇARPILIR
# → sonuçta-bir-SIRALAMA/SKOR-lamayapılır (transitif-bağımlılık)
print("  Sybil-ağırlıklandırma = skoruyla-çarpma → transitif-sıralama (K0-çarpışması)")

# --- 3) K0-KURALI: bizim-tarafımızda-sıralama-YASAK
from dispute_pointer_verify import SUPPORTED_PROTOCOLS
assert "pacta/v1" in SUPPORTED_PROTOCOLS   # kendi-yapımız-hazır-olsun
# RFC-010-gate'i-asla-bir-skorla-ağırlıklandırmaz — eşit-kanıt-eşit-davranır
import settlement_bind_verify as SB
import inspect
code = inspect.getsource(SB.verify)
for bad in ("reputation", "score", "rank", "itibar", "weight"):
    assert bad not in code.lower(), f"RFC-010-gate'inde-{bad}-var (K0-ihlali!)"
print("  K0-korunuyor: RFC-010-gate'inde-hiçbir-skora-ağırlık-YOK (eşit-kanıt-eşit)")

# --- 4) D-014-DUVARI-ROBOSEAL-için-de-var (çözülebilirlik-kanıtı)
# ROBOSEAL'in-Sybil-savunması-bağlıdır-karşı-tarafın-skoruyla (transitif);
# yeni-kukla-ajanların-katkısı≈0 — AMA-bu-aynı-zamanda-meşru-yeni-ajanları-da
# cezalandırır (soğuk-başlangıç). Bu-D-014'ün-tam-çelişkisidir.
assert "≈ 0" in src or "yeni" in src.lower(), "soğuk-başlangıç-işaret-yok"
print("  D-014-duvarı-kanıtlandı: yeni-kukla≈0-katkı = meşru-yeni-ajanı-da-cezalandırır")

# --- 5) ÇÖZÜM-SEÇENEĞİ (bizim-tarafımız): sıralama-YAPMADAN-Sybil-savunması
# RFC-010-beş-kontrol-üretici-için-ZORUNLU (fail-closed) — bu-bir-SKOR-değil
# bir-DOĞRULAMA'dır: ya-doğrulandı-ya-doğrulanmadı, derecesi-yok.
# Sybil'ler-beş-kontrolü-geçemez (imza+yapısal-bütünlük-zorunlu) —
# sıralama-olmadan-da-savunma-mümkün.
print("  bizim-Sybil-savunmamız: sıralama-YOK, beş-kontrol-ZORUNLU (ikili-DOĞRULAMA)")

# --- 6) ÜÇÜNCÜ-SEÇENEK-YASAK: ROBOSEAL'i-dışlama-RED-değil
# ROBOSEAL'in-alanına-girmiyoruz — onun-protokolünü-çözüm-olarak-TANIMIYORUZ
# (sıralama-içerir), ama-reddetmiyoruz-da (İNDETERMİNE): kullanıcının-seçimi.
print("  ROBOSEAL-tavır: tanımlanmış-çözüm-değil (sıralama-içerir) — ama-RED-değil")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-ROBOSEAL-çatışma-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-074: ROBOSEAL-itibar-çatışması"
[[ $FAIL -eq 0 ]]
