#!/usr/bin/env bash
# AT-058: AYRAÇ-SINIFI-ÖRTÜŞME-DENETİMİ — Kural-7.2'nin-makine-hali.
#
# ÖLÇÜLEN-BULGU: Sester'ın-ayraç-sınıfı-SQL-yazım-deyimleri ('INSERT INTO'-
# TÜM-tablolar + 'copy_from'), Tamga'nınki-dosya-deyimleri ('fdopen/O_APPEND/
# O_TRUNC'). **Ayraç-sınıfları-HİÇ-örtüşmüyor.**
#
# LEAD-DOĞRULAMASIYLA-DÜZELTME (2026-09-21): ilk-halimiz-Sester'ın-ayracını-dar
# 'INSERT INTO events'-olarak-tanımlıyordu — STALE-çıktı (lead: tarama-artık-
# 'INSERT INTO'-TÜM-tablolar + 4-gizli-bölge-NON_GATES'te-beyanlı-claim_nonce-×2,
# insert_nonce, EscalationQueue.park; anchors-events'e-yazmıyor, bridges.py-
# alıcı-tarafı-yalnız-zarf-üretir). Dar-pattern-'sql-copy'yi-yanlışça-blind-spot
# sanıyordu. Genişletildi-ve-ölçüm-artık-geçerli — SONUÇ-aynı (ortak-YOK),-ama
# doğru-yöntemle. Üçüncü-seçenek-her-tarafta-sağlanıyor.
#
# Kural-7.2 (K0-rule-8): bir-ürünün-iç-denetimi-yeşilken-çapraz-ürün-soru-
# disiplini-devam-etmeli. Bu-test-o-disiplinin-makine-halidir: bilinen-yazım-
# deyim-sınıflarından-hangisinin-hangi-ayraçta-yakalandığını-ölçer-ve-ORTAK-
# SINIF-YOKSA-'üçüncü-seçenek-tamamlandı'-iddiasını-RED-verir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-058/$(date +%F)/at058.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-058: ayraç-sınıfı-örtüşme — Kural-7.2-makine-hali"

# 1) AYRAÇLAR-GERÇEK-ŞEKİLDE-ÇALIŞIYOR: her-ayracı-kendi-sınıfını-yakalıyor
note "1) her-ayracı-kendi-sınıfını-yakalıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys; sys.path.insert(0, "tools")
import ayrac_sinifi_denetle as AD
assert AD.yakalar(AD.SESTER_PAT, "cur.execute('INSERT INTO events (x)')"), "sester-SQL-yakalamadı"
assert AD.yakalar(AD.TAMGA_PAT, 'os.fdopen(fd, "w")'), "tamga-fdopen-yakalamadı"
assert AD.yakalar(AD.TAMGA_PAT, "os.O_APPEND"), "tamga-O_APPEND-yakalamadı"
print("  ayraçlar-kendi-sınıflarını-yakalıyor")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 1) ayraçlar-çalışıyor"; else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) ÇAPRAZ-GİZLİ-DEYİM: bir-ayracın-diğer-ürünün-deyimini-görmemesi
note "2) çapraz-deyim-körlüğü (gerçek-blind-spot)"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys; sys.path.insert(0, "tools")
import ayrac_sinifi_denetle as AD
# Sester'ın-ayracı-Tamga'nın-dosya-deyimini-GÖRMEZ
assert not AD.yakalar(AD.SESTER_PAT, 'os.fdopen(fd, "w")'), "sester-fdopen'i-gördü (yanlış)"
# Tamga'nın-ayracı-Sester'ın-SQL'ini-GÖRMEZ
assert not AD.yakalar(AD.TAMGA_PAT, "cur.execute('INSERT INTO events (x)')"), "tamga-SQL'i-gördü (yanlış)"
print("  çapraz-körlük-doğru: her-ayracı-sadece-kendi-sınıfını-görür")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 2) çapraz-körlük"; else FAIL=$((FAIL+1)); note "  FAIL 2)"; cat "$LOG"; fi

# 3) ORTAK-SINIF-YOKSA-KURAL-7.2-İHLALİ
note "3) ortak-sınıf-yok → 'tamamlandı'-iddiası-RED"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys; sys.path.insert(0, "tools")
import ayrac_sinifi_denetle as AD
d = AD.denetle()
assert not d["ortak_var"], "ortak-sınıf-var-olduğu-iddia-edildi-ama-ölçüm-göstermedi"
assert d["sester_yalniz"] and d["tamga_yalniz"], "ayrı-sınıflar-olmalı"
print("  ortak-YOK; sester-yalnız:", d["sester_yalniz"], "| tamga-yalnız:", d["tamga_yalniz"])
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 3) Kural-7.2-canlı"; else FAIL=$((FAIL+1)); note "  FAIL 3)"; cat "$LOG"; fi

# 4) KESİŞME-İHLMALİ-OLMAYAN-DEYİM: hiç-ayraç-yakamıyorsa-yeni-blind-spot
note "4) hiç-yakalanmayan-deyimler = bilinen-blind-spot-listesi"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys; sys.path.insert(0, "tools")
import ayrac_sinifi_denetle as AD
d = AD.denetle()
assert d["hicbiri"], "hiç-yakalanmayan-deyim-olmalı (gerçek-blind-spot)"
print("  hiç-yakalanmayanlar:", d["hicbiri"])
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 4) blind-spot-listesi"; else FAIL=$((FAIL+1)); note "  FAIL 4)"; cat "$LOG"; fi

# 5) NEGATİF-KONTROL: ayraçlar-yanlış-eşleşmiyor (örnek-gerçekten-masun-olmalı:
# hiçbir-ayracın-literal'ini-taşımayan-satırlar; 'and False' ölü-kodu-kaldırıldı)
note "5) negatif-kontrol — masum-satır-yakalanmıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys; sys.path.insert(0, "tools")
import ayrac_sinifi_denetle as AD
# masun: ne-SQL-yazım-literal'i-ne-dosya-deyimi-taşır
for masum in ("x = 1 + 2", "print('merhaba')", "# yorum-satiri", "y = deger"):
    assert not AD.yakalar(AD.SESTER_PAT, masum), f"masun-SQL'e-yakalandi: {masum}"
    assert not AD.yakalar(AD.TAMGA_PAT, masum), f"masun-Tamga'ya-yakalandi: {masum}"
print("  masum-satırlar-yakalanmıyor")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 5) negatif-kontrol"; else FAIL=$((FAIL+1)); note "  FAIL 5)"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-058: ayraç-sınıfı-örtüşme (Kural-7.2-makine-hali)"
[[ $FAIL -eq 0 ]]
