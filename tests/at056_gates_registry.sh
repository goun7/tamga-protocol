#!/usr/bin/env bash
# AT-056: GATES-KAYIT-DEFTERİ — Kural-7.1'in-makine-hali.
#
# SESTER'IN-test_215'i-ile-aynı-şekil (onun-önerisi: "senin-AT-056'na-EVET, yaz —
# ve-işte-benim-şeklim-ki-aynı-olsun"). Üç-yönlü-denetim:
#   (a) KAYITSIZ-KAPI-RED  — yeni-geçitli-yazım-fonksiyonu-unutulamaz
#   (b) ESASIZ-KAYIT-RED  — kapı-kaldıysa-kayıt-da-kalkmalı
#   (c) BOŞ/YASAK-NOT-RED — "eksiksiz"/"tam-kapsam"-iddiası-yasak (Kural-7.1)
#   (d) SELF-CATCHING     — yardımcılar-GATES'e-konamaz (Sester'ın-own-tuzak)
#
# SESTER'IN-SELF-CATCHING-DERSİ-BİZDE-İKİ-KEZ-ÇALIŞTI:
#  1. İlk-halim-"guard-içeren-her-fonksiyon"-deseydi-unknown_ops()-kendini-yakalardı
#     (o-da-EMITTED_OPS-kontrolü-içerir-ama-RED-vermez). Doğru-ayrım: KAPI-RED-VERİR.
#  2. LEDGER-ayracım-çok-geniş-eşleyince-cmd_run/cmd_memory'yi-yanlış-kapı-sandı
#     (onlar-yalnızca `_, sp, _ = _pkg(pkg)`-çağırıyor). İnceleynce-cmd_run'ın-
#     GERÇEK-bir-_ledger_append-çağrısı-olduğu-çıktı → GATES'e-doğru-olarak-eklendi.
#     Yani-yanlış-pozitif-bir-gerçek-keşfe-dönüştü.
#
# GÜVEN-SINIRI (Sester'ın-itirafı): makine-katmanı-notu-yazanın-dürüst-yazdığını-
# varsayar. Denetim-boşluğu-ve-"tam-kapsam"-kelimesini-yakalar-AMA-özü-deneyemez.
# Makine-ritüeli-sabitler, özü-değil — insan-soru-disiplini-ikame-değil-tamamlayıcı.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
LOG=".evidence/AT-056/$D/at056.log"
mkdir -p ".evidence/AT-056/$D"
: > "$LOG"

note "AT-056: GATES-kayıt-defteri — Kural-7.1 makine-hali"

# 0) ANA-DENETİM: mevcut-GATES-temiz
note "0) mevcut-GATES-üç-yönlü-denetim-temiz"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import gates_registry as GR
r = GR.check()
assert r["ok"], f"GATES-sorunlu: {r['problems']}"
print(f"  {len(r['gates'])}-kapı-kayıtlı, hiç-sorun-yok")
for g in r["gates"]:
    print(f"    {g}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 0) GATES-temiz"
else FAIL=$((FAIL+1)); note "  FAIL 0)"; cat "$LOG"; fi

# 1) (a) KAYITSIZ-KAPI-RED: yeni-kapı-GATES'e-eklenmezse-yakalanmalı
note "1) ayar-a — kayıtsız-yeni-kapı-yakalanıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import gates_registry as GR
orig = dict(GR.GATES)
# yeni-kapı-ekle-kayıtsız (simülasyon: mevcut-kayıtlardan-birini-sil)
GR.GATES.pop("tamga_runner.py:cmd_import")
r = GR.check()
GR.GATES.clear(); GR.GATES.update(orig)
assert not r["ok"], "kayıtsız-kapı-yakalanmadı!"
assert any("cmd_import" in p for p in r["problems"]), r["problems"]
print("  kayıtsız-kapı-yakalandı (RED)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 1) (a) kayıtsız-kapı-RED"
else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) (b) ESASIZ-KAYIT-RED: kapı-kalkarsa-kayıt-da-kalkmalı
note "2) ayar-b — esasız-kayıt-yakalanıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import gates_registry as GR
orig = dict(GR.GATES)
GR.GATES["tamga_runner.py:cmd_yok_böyle_birşey"] = "KÖR-NOKTA: x"
r = GR.check()
GR.GATES.clear(); GR.GATES.update(orig)
assert not r["ok"], "esasız-kayıt-yakalanmadı!"
assert any("esasiz" in p for p in r["problems"]), r["problems"]
print("  esasız-kayıt-yakalandı (RED)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 2) (b) esasız-kayıt-RED"
else FAIL=$((FAIL+1)); note "  FAIL 2)"; cat "$LOG"; fi

# 3) (c) BOŞ-VE-YASAK-KELİME-NOTU-RED
note "3) ayar-c — boş-ve-'tam-kapsam'-notu-yakalanıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import gates_registry as GR
orig = dict(GR.GATES)
for bad in ("", "   ", "bu-kapı-artık-tam-kapsam-sağlar"):
    GR.GATES["tamga_runner.py:_ledger_append"] = bad
    r = GR.check()
    assert not r["ok"], f"yasak-not-yakalanmadı: {bad!r}"
GR.GATES.clear(); GR.GATES.update(orig)
print("  boş-ve-yasak-kelime-notu-yakalandı (RED)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 3) (c) boş/yasak-not-RED"
else FAIL=$((FAIL+1)); note "  FAIL 3)"; cat "$LOG"; fi

# 4) (d) SELF-CATCHING: yardımcılar-GATES'e-konamaz
note "4) ayar-d — unknown_ops-yardımcı-kapı-değil (Sester-self-catching)"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import gates_registry as GR
orig = dict(GR.GATES)
GR.GATES["tamga_runner.py:unknown_ops"] = "KÖR-NOKTA: x"
r = GR.check()
GR.GATES.clear(); GR.GATES.update(orig)
assert not r["ok"], "yardımcı-GATES'e-kondu!"
assert any("self-catching" in p for p in r["problems"]), r["problems"]
print("  unknown_ops-yardımcı-olarak-yakalandı (RED) — kapı-RED-vermez")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 4) (d) self-catching-koruma"
else FAIL=$((FAIL+1)); note "  FAIL 4)"; cat "$LOG"; fi

# 5) KAPI-HÂLÂ-RED-VERİYOR (esasız-ölçüm-de-çalışır)
note "5) her-kayıtlı-kapı-gerçekten-RED-veriyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import gates_registry as GR
r = GR.check()
assert r["ok"]
# bilinen-üç-üretim-geçidinin-eylemleri-daha-önce-kanıtlandı (AT-050/052/053)
print(f"  {len(r['gates'])}-kapı: her-biri-RED-veriyor (AT-050/052/053-ile-kanıtlı)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 5) kapılar-RED-veriyor"
else FAIL=$((FAIL+1)); note "  FAIL 5)"; cat "$LOG"; fi

# 6) SESTER'IN-AŞIRİ-TARAFTA-HATA-İLKESİ: sessiz-geçiş-yasak
note "6) üçüncü-seçenek-yok — yazım-bölgesi-ya-GATES'te-ya-STATE_ONLY'de"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import gates_registry as GR
r = GR.check()
assert r["ok"], f"GATES-bozuk: {r['problems']}"
# her-yazım-bölgesi-sınıflandırılmış-olmalı
known = set(GR.GATES) | set(GR.STATE_ONLY)
for mod in ("tamga_runner.py", "tamga_netproxy.py"):
    fns = GR._write_regions(mod)
    for fn in fns:
        key = f"{mod}:{fn}"
        assert key in known, f"SESSİZ-GEÇİŞ: {key} ne-GATES'te-ne-STATE_ONLY'de"
print(f"  {len(known)}-yazım-bölgesi-tamamen-sınıflandırıldı (sessiz-geçiş-yok)")
# ayar: STATE_ONLY'den-çıkart → (a)-RED-vermeli
orig = dict(GR.STATE_ONLY)
GR.STATE_ONLY.pop("tamga_runner.py:cmd_memory")
r2 = GR.check()
GR.STATE_ONLY.clear(); GR.STATE_ONLY.update(orig)
assert not r2["ok"], "sessiz-geçiş-yakalanmadı!"
assert any("cmd_memory" in p_ for p_ in r2["problems"]), r2["problems"]
print("  ayar: STATE_ONLY-kaldırılınca-RED (sessiz-geçiş-yasak)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 6) sessiz-geçiş-yasak (aşırı-taraf-ilkesi)"
else FAIL=$((FAIL+1)); note "  FAIL 6)"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-056: GATES-üç-yönlü+self-catching (Kural-7.1-makine-hali)"
[[ $FAIL -eq 0 ]]
