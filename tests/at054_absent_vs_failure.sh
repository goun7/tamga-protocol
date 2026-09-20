#!/usr/bin/env bash
# AT-054: ABSENT-STATE-≠-INSTRUMENT-FAILURE — stillmarcus24'ün-#2887-dersi.
#
# ÖNERDİĞİM-AMA-KENDİ-KODUMDA-HİÇ-KOŞTURMADIĞIM-denetim-sınıfı. #2887'ye-
# katkım-"field-level-consistency"-idi; ama-audit-sınıfını-kendimde-tutup-
# dışarıa-vermem-dürüst-değildi. Bu-test-onu-kapatır.
#
# SINIF-TANIMI: bir-kanıt-alanının-YOKLUK-hali-ile-ALET-BOZUKLUK-hali
# byte-identical-ise, "kırık-dedektör"-ile "gerçekten-doğrulanamaz"-ayırt-
# edilemez → dedektör-çoğunlukla-kendinden-emin-döndürür-ama-aslında-bozuktur.
#
# BİZDEKİ-DURUM (test-ile-kanıtlanır):
#   absent-state   (sources={})         → ok:True + UNVERIFIED-INDEPENDENTLY
#   failure-state  (dosya-yok/bozuk)    → ok:False + RED
#   → AYRIŞIYOR — sınıf-kapalı. İYİ.
#
# AMA-İKİ-ZAYIF-YÜZ-BULUNDU (bu-test-ikisini-de-yakalar):
#   (a) iki-giriş-noktası-aynı-durum-için-FARKLI-reason-metni-veriyor
#       (tools: "kaynaklar-verilmemiş" vs pack: "kaynaklar-yok")
#   (b) pack-STRUCTURAL-GREEN-veriyor,-tools-vermiyor — tüketici-karışıklığı
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
LOG=".evidence/AT-054/$D/at054.log"
mkdir -p ".evidence/AT-054/$D"
: > "$LOG"

note "AT-054: absent-state ≠ instrument-failure (stillmarcus24-#2887)"

# 1) ANA-SINIF: absent-≠-failure-byte-identity (iki-giriş-noktasında-da)
note "1) absent-≠-failure — iki-giriş-noktasında-da-ayrışıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, json, tempfile, hashlib
sys.path.insert(0, "tools"); sys.path.insert(0, "tests/conformance")
import sovereign_anchor as SA
import verify_anchor as VA
d = tempfile.mkdtemp()
def canon(o): return json.dumps(o, sort_keys=True, separators=(",",":")).encode()

def mk_absent():
    a = {"type":"sovereign-anchor","version":"0.1","products_present":["tamga"],
         "products_proved":["tamga"],"all_proved":True,
         "results":{"tamga":{"ok":True,"verdict":"GREEN","detail":"temiz"}},
         "sources":{}}
    a["anchor_root"] = hashlib.sha256(canon({"results":a["results"],"sources":{}})).hexdigest()
    return a

# absent-state
a = mk_absent(); pA = f"{d}/A.json"; json.dump(a, open(pA,"w"))
rA_tools = SA.verify(pA); rA_pack = VA.verify_anchor(pA)

# failure-state-1: dosya-yok
rB = SA.verify(f"{d}/yok.json")
# failure-state-2: bozuk-JSON
pC = f"{d}/C.json"; open(pC,"w").write("{bozuk")
rC = SA.verify(pC)

# ANA-iddia: absent ≠ her-iki-failure-türü
assert str(rA_tools) != str(rB), f"absent==dosya-yok byte-identical: {rA_tools}"
assert str(rA_tools) != str(rC), f"absent==bozuk-json byte-identical: {rA_tools}"
assert rA_tools.get("ok") is True and rB.get("ok") is False, "ok-bayrağı-ayrışmıyor"
print("  absent: ok:True + UNVERIFIED  |  failure: ok:False + RED")
print("  → sınıf-KAPALI (hâlâ-ayrışıyor)")
print(f"  pack-absent-verdict: {rA_pack.get('verdict')}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 1) absent-≠-failure-ana-sınıf"
else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) ZAYIF-YÜZ-(a): iki-giriş-noktası-aynı-reason-metni-vermeli
note "2) reason-metni-paritesi — iki-giriş-noktası-tutarlı"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, json, tempfile, hashlib
sys.path.insert(0, "tools"); sys.path.insert(0, "tests/conformance")
import sovereign_anchor as SA
import verify_anchor as VA
d = tempfile.mkdtemp()
def canon(o): return json.dumps(o, sort_keys=True, separators=(",",":")).encode()
a = {"type":"sovereign-anchor","version":"0.1","products_present":["tamga"],
     "products_proved":["tamga"],"all_proved":True,
     "results":{"tamga":{"ok":True,"verdict":"GREEN"}},"sources":{}}
a["anchor_root"] = hashlib.sha256(canon({"results":a["results"],"sources":{}})).hexdigest()
p = f"{d}/a.json"; json.dump(a, open(p,"w"))
rt = SA.verify(p); rp = VA.verify_anchor(p)
vt, vp = rt.get("verdict"), rp.get("verdict")
print(f"  tools-verdict: {vt}  |  pack-verdict: {vp}")
# ikisi-de-UNVERIFIED-olmalı (aynı-durum-aynı-karar)
assert vt == "UNVERIFIED-INDEPENDENTLY", f"tools-yanlış: {vt}"
assert vp == "UNVERIFIED-INDEPENDENTLY", f"pack-yanlış: {vp}"
print("  iki-giriş-noktası-da-UNVERIFIED — karar-tutarlı")
# reason-metni-farklı-ama-aynı-anlam — zayıf-yüz-olarak-kayıtlandı
print(f"  tools-reason: {rt.get('reason','')[:40]}")
print(f"  pack-reason:  {rp.get('reason','')[:40]}")
# AT-054-düzeltme: metin-artık-birleştirildi — mutlak-parite
assert rt.get("reason") == rp.get("reason"), \
    f"reason-metni-hâlâ-farklı: tools={rt.get('reason')!r} pack={rp.get('reason')!r}"
print("  reason-metni-birebir-aynı — zayıf-yüz-kapatıldı")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 2) karar-tutarlı (metin-paritesi-zayıf-yüz)"
else FAIL=$((FAIL+1)); note "  FAIL 2)"; cat "$LOG"; fi

# 3) TERS-YÖN-AYARI: failure'ı-absent-mış-gibi-gizleme-saldırısı
note "3) ayar — failure'ı-absent-gizleme-RED-vermeli"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, json, tempfile, hashlib
sys.path.insert(0, "tools")
import sovereign_anchor as SA
d = tempfile.mkdtemp()
def canon(o): return json.dumps(o, sort_keys=True, separators=(",",":")).encode()
a = {"type":"sovereign-anchor","version":"0.1","products_present":["tamga"],
     "products_proved":["tamga"],"all_proved":True,
     "results":{"tamga":{"ok":True,"verdict":"GREEN"}},"sources":{}}
a["anchor_root"] = hashlib.sha256(canon({"results":a["results"],"sources":{}})).hexdigest()
# SALDIRI: sources'ı-boz-bir-dosyaya-işaret-et-ama-anchor_root'u-absent-haliyle-bırak
a["sources"] = {"tamga_claim": f"{d}/yok-kanıt.json"}
# anchor_root'u-KASITLI-absent-hesabıyla-bırak (kurcalama-tespiti-beklenir)
p = f"{d}/s.json"; json.dump(a, open(p,"w"))
r = SA.verify(p)
assert r.get("ok") is False, f"failure-absent-gizlendi: {r}"
print(f"  saldırı-RED: {r.get('reason','')[:56]}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 3) ters-yön-saldırısı-yakalandı"
else FAIL=$((FAIL+1)); note "  FAIL 3)"; cat "$LOG"; fi

# 4) BOŞ-SONUÇ-DİZİSİ: results={}-absent-değil-failure-değil
note "4) results-boş — üçüncü-durum-ayrışıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, json, tempfile, hashlib
sys.path.insert(0, "tools")
import sovereign_anchor as SA
d = tempfile.mkdtemp()
def canon(o): return json.dumps(o, sort_keys=True, separators=(",",":")).encode()
a = {"type":"sovereign-anchor","version":"0.1","products_present":[],
     "products_proved":[],"all_proved":True,"results":{},"sources":{}}
a["anchor_root"] = hashlib.sha256(canon({"results":{},"sources":{}})).hexdigest()
p = f"{d}/e.json"; json.dump(a, open(p,"w"))
r = SA.verify(p)
# boş-durum-da-UNVERIFIED-olmalı (absent-ailesi), RED-değil
assert r.get("ok") is True, f"boş-durum-RED-verdi: {r}"
print(f"  boş-results: {r.get('verdict')} — absent-ailesinde-doğru")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 4) boş-durum-doğru-aile"
else FAIL=$((FAIL+1)); note "  FAIL 4)"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-054: absent-≠-failure-kanıtlı + 2-zayıf-yüz-kayıtlı"
[[ $FAIL -eq 0 ]]
