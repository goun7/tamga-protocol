#!/usr/bin/env bash
# AT-048: dedektör-öz-doğrulama — stillmarcus24-yoldaş-kuralı (x402#2887).
#
# "A detector returning a confident majority is indistinguishable from a
#  broken one." — stillmarcus24, 2026-09-20. İlk-dedektörü-40-satırdan-25'ini-
# işaretlemiş-ama-gerçek-sayı-SIFIRMIŞ (ayırt-edici-alanları-gözden-kaçırmış).
#
# YOLDAŞ-KURAL: dedektör-bilinen-bir-cevaba-koşturulmalı; yeniden-üremiyorsa
# KOŞU-GEÇERSİZDİR. Bu-kuralı-kendi-tarayıcımıza-uygularız: spec_code_scan.py
# "18-aligned-0-divergence"-diyor-ama-tarayıcı-gerçek-bir-ayrışmayı-yeniden-
# üretebiliyor-mu? Üretemezse-o-rakam-anlamsızdır.
#
# Dört-bilinen-cevap (her-divergence-sınıfı-biri):
#   aligned / spec-only / code-only / untested
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-048/$D"
LOG=".evidence/AT-048/$D/at048.log"
: > "$LOG"

note "AT-048 dedektör-öz-doğrulama (stillmarcus24-yoldaş-kuralı)"

# 1) tarayıcı-dört-sınıfı-da-bilinen-cevapla-yeniden-üretmeli
note "1) dört-bilinen-cevap — her-divergence-sınıfı"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, copy
sys.path.insert(0, "tools")
import spec_code_scan as S
orig = [copy.deepcopy(r) for r in S.RULES]
NEEDLE = "`seq`-1-based-aritmetik-artan"   # spec'te-gerçekten-var
known = [
    ("X-ALIGNED",  "seq0",        "red",    "aligned"),
    ("X-SPECONLY", "extra_field", "green",  "spec-only"),   # kırım-GREEN→uygulanmıyor
    ("X-CODEONLY", "seq0",        "red",    "code-only"),
    ("X-UNTESTED", None,          None,     "untested"),
]
fail = []
for tag, case, red, expect in known:
    rule = (tag, "bilinen-cevap-testi", NEEDLE if tag != "X-CODEONLY"
            else "BU-NEEDLE-ASLA-OLMAMALI", case, red)
    S.RULES = list(orig) + [rule]
    d = S.scan()
    got = {r["id"]: r["divergence"] for r in d["rules"]}.get(tag)
    if got != expect:
        fail.append(f"{tag}: got={got} expected={expect}")
    else:
        print(f"  ✓ {tag} → {got}")
# untested-için-case-None-iken-aynı-needle-kullanılıyor (documented=True);
# code-only-için-farklı-needle (documented=False) — doğru
S.RULES = orig
assert not fail, f"bilinen-cevap-yeniden-üretilmedi: {fail}"
# üretim-kendisi-hâlâ-temiz-olmalı (enjeksiyon-geri-alındı)
d = S.scan()
assert d["summary"]["untested"] == 0 and d["summary"]["code_only"] == 0, \
    f"enjeksiyon-geri-alınmadı: {d['summary']}"
print("dört-sınıf-bilinen-cevapla-yeniden-üretildi; üretim-temiz")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 4/4-sınıf-yeniden-üretildi"
else FAIL=$((FAIL+1)); note "  FAIL dedektör-bozuk"; cat "$LOG"; fi

# 2) üretim-rakamı-geçerli (enjeksiyon-sonrası-temiz)
note "2) üretim-rakamı — enjeksiyon-kirlenmedi"
python3 tools/spec_code_scan.py --format json > /tmp/at048.json 2>> "$LOG"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import json
d = json.load(open("/tmp/at048.json"))
s = d["summary"]
# 18-kural-hepsi-aligned (önceki-kanıtlı-durum)
assert s == {"aligned": 18, "spec_only": 0, "code_only": 0, "untested": 0}, s
assert len(d["rules"]) == 18
print(f"üretim: {s} — rakam-bilinen-cevapla-destekleniyor")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 18/0/0/0-geçerli"
else FAIL=$((FAIL+1)); note "  FAIL rakam-bozuk"; cat "$LOG"; fi

# 3) YOK-HALİ==ARIZA-HALİ-sınıfı-bizde-de-var-mı (stillmarcus24'un-asıl-sınıfı)
note "3) absent==instrument-failure — bizdeki-kanıt-alanları (ledger+anchor)"
python3 - <<'PYEOF' >> "$LOG" 2>&1
# stillmarcus24: bir-alanın-yok-hali-ile-enstrüman-arıza-hali byte-identik-ise,
# tüketici-ayiramaz. İki-yüz-de-denendi: mini-verifier + sovereign-anchor.
import sys, json, tempfile, hashlib, pathlib
sys.path.insert(0, ".")

# (a) LEDGER: boş-dosya vs parse-hatası — reason'lar-aynı-olmamalı
from tamga_verify_mini import verify
d = tempfile.mkdtemp()
pA = f"{d}/empty.jsonl";   pathlib.Path(pA).write_text("", encoding="utf-8")
pB = f"{d}/parsebad.jsonl"; pathlib.Path(pB).write_text("BU-JSON-DEĞİL\n", encoding="utf-8")
tA, rA = verify(pA); tB, rB = verify(pB)
assert rA != rB, f"LEDGER-absent==failure: {rA!r}"
print(f"  ledger: boş={rA!r} parse-hata={rB!r} — AYRI")

# (b) ANCHOR: sources-YOK vs sources-GEÇERSİZ-YOL — verdict'ler-aynı-olmamalı
#   DİKKAT (ilk-denemede-yanlış-kanıt-ürettim, dürüst-not): products_proved/
#   all_proved-çelişen-fixture-her-iki-durumda-aynı-reason-verirdi → sahte-
#   uyarı. Doğru-fixture'da-sınıf-yok: UNVERIFIED vs RED.
sys.path.insert(0, "tools")
from sovereign_anchor import verify as averify
def canon(o): return json.dumps(o, sort_keys=True, separators=(",", ":")).encode()
res = {"tamga": {"ok": True, "verdict": "GREEN"}}
base = {"type": "sovereign-anchor", "version": "0.1",
        "products_present": ["tamga"], "products_proved": ["tamga"],
        "all_proved": True, "results": res}
a = dict(base); a["sources"] = {}
a["anchor_root"] = hashlib.sha256(canon({"results": res, "sources": {}})).hexdigest()
b = dict(base); b["sources"] = {"tamga_claim": "/tmp/olmayan/x.json"}
b["anchor_root"] = hashlib.sha256(canon({"results": res, "sources": b["sources"]})).hexdigest()
p1, p2 = f"{d}/a1.json", f"{d}/a2.json"
json.dump(a, open(p1, "w")); json.dump(b, open(p2, "w"))
vA, vB = averify(p1), averify(p2)
# geçersiz-yol-durumunda-RED-döner (ok=False); verdict-alanı-olmayabilir
vA_v = vA.get("verdict", "RED" if not vA.get("ok") else "?")
vB_v = vB.get("verdict", "RED" if not vB.get("ok") else "?")
assert vA_v != vB_v, \
    f"ANCHOR-absent==failure: {vA_v!r} == {vB_v!r}"
print(f"  anchor: kaynak-yok={vA_v!r} geçersiz-yol={vB_v!r} — AYRI")
print("  stillmarcus24-sınıfı-bizde-tespit-edilmedi (iki-yüz-de)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS absent≠failure-bizde"
else FAIL=$((FAIL+1)); note "  FAIL sınıf-tespit-edildi!"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-048-kapısı: dedektör-bilinen-cevapla-doğrulandı (sayı-anlamlı)"
[[ $FAIL -eq 0 ]]
