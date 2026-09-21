#!/usr/bin/env bash
# AT-061: TASARIM↔PİLOT-ŞEKİL-PARİTESİ — AT-017'in-donmuş-F1-şekli-ile
# AT-059/AT-060'ın-yazdığı-gerçek-kayıt-aynı-şekli-öğretir-mi?
#
# BULGU (2026-09-21, bu-oturum): İKİ-uyumsuzluk-vardı —
#   (A) RFC-009-§2'nin-donmuş-şeklinde-'foreign_source'-var-AMA-cmd_anchor
#       onu-yazmıyordu (donmuş-alan-sessizce-düşmüştü);
#   (B) donmuş-tasarım-vector'unda-'presentation_only'-YOKTU — yani-AT-017'in
#       aktardığı-şekli-AT-060'ın-yeni-okuma-kapısı-RED'liyordu. AT-017'in-
#       sözü ("pilot-günü-yazıcıdır-tasarımcı-değil")-bozulmuştu.
#
# DÜZELTME: tasarıma-presentation_only-eklendi (h-D5'yle-yeniden-hesaplandı),
# cmd_anchor'a-isteğe-bağlı---foreign-source-eklendi. Bu-test-ikisini-MAKİNE-
# ye-kilitler — donmuş-şekil-bir-daha-sessizce-uyumsuzlaşamaz.
#
# İLKEL (AT-047-SPEC_OPS-dersi): parite-elle-listeyle-ölçülürse-kirlenir. Bu-
# yüzden-ZORUNLU/İSTEĞE-BAĞLI-kümeleri-ÇIKARIMLA-türetilir: her-alanı-sırayla
# çıkar, okuma-kapısının-RED'lemesini-gözlemle. RED'lenen=zorunlu, geçen=
# isteğe-bağlı. Hiçbir-sabit-liste-yazılmadı.
#
# KİLİT-KOŞUL: donmuş-tasarımın-içeriği-gerçek-zincire-enjekte-edildiğinde
# ledger-verify-GREEN-olmalı — tasarım-bize-verifier'ın-reddettiği-bir-şekil
# öğretemez.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-061/$(date +%F)/at061.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

python3 - > "$LOG" 2>&1 <<'PYEOF'
import sys, json, pathlib, tempfile, shutil
sys.path.insert(0, "."); sys.argv = ["x"]
import tamga_runner as TR

VEC = pathlib.Path("tests/vectors/anchor-v0-design/anchor-design-vector.json")
design = json.loads(VEC.read_text(encoding="utf-8"))

# 1) AT-017-hala-kendisiyle-tutarlı (h-D5'yle-yeniden-hesap)
import hashlib
from tamga_validator import jcs
body = {k: v for k, v in design.items() if k not in ("h", "node_sig")}
assert hashlib.sha256(design["prev"].encode() + jcs(body)).hexdigest() == design["h"], \
    "tasarım-vector'u-D5'yle-tutarsız (AT-017-bozuldu)"
print("  1) tasarım-D5-tutarlı")

# 2) ZINCİR-İÇERİĞİ: seq/prev/h-zincire-ait-biz-koymuyoruz; kalan-İÇERİK
content = {k: v for k, v in design.items() if k not in ("seq", "prev", "h")}
assert content["op"] == "anchor"

def inject(rec, mutate=None):
    """rec'i-geçerli-bir-zincirin-sonuna-ekler-ve-ledger-verify-sonucunu-döndürür."""
    pkg = pathlib.Path(tempfile.mkdtemp())
    lp = pkg / "ledger.jsonl"
    # küçük-temel-zincir (bir-charge): ledger-verify-yalnızca-bu-dosyayı-okur
    TR._ledger_append(lp, {"op": "charge", "pkg": "at061-parite", "session": 1,
                           "engine": "test", "cpu_saat": 0.01, "ram_gb_sn": 0.01,
                           "io_mb": 0.0, "wall_ms": 1, "fee_birebir": "0",
                           "stdout_sha256": "0" * 64, "reason": "at061-temel"})
    r = TR._ledger_append(lp, dict(rec, **(mutate or {})))
    if isinstance(r, int):
        shutil.rmtree(pkg, ignore_errors=True)
        return None, None      # yazılamadı
    # out()-sözleşmesi: JSON'i-basip-rc-döndürür (0=GREEN, 1=RED)
    rc = TR.cmd_ledger_verify([str(pkg)])
    shutil.rmtree(pkg, ignore_errors=True)
    return rc == 0, rc

# 3) KİLİT: donmuş-tasarımın-içeriği-gerçek-zincirde-GREEN-doğrulanmalı
ok, res = inject(content)
assert ok, f"donmuş-tasarım-RED: {res}"
print("  3) donmuş-tasarım-içeriği-ledger-verify-GREEN (verifier'in-reddettiği-"
      "şekli-öğretmiyor)")

# 4) ZORUNLU/İSTEĞE-BAĞLI-ÇIKARIMI (elle-liste-YOK): her-alanı-çıkar-ve-gözlemle
required, optional = set(), set()
for f in sorted(content):
    if f == "op":
        continue               # yapısal: her-kayıtta-olmalı-ayrı-tutulur
    trial = {k: v for k, v in content.items() if k != f}
    ok2, _ = inject(trial)
    (required if not ok2 else optional).add(f)
print(f"  4) zorunlu-çıkarım: {sorted(required)}")
print(f"     isteğe-bağlı-çıkarım: {sorted(optional)}")

# R9-1..R9-5-alanlarının-hepsi-zorunlu-olmalı (okuma-kapısı-arkası)
for f in ("anchor_version", "foreign_registry", "foreign_fact", "foreign_digest",
          "verified_at", "presentation_only"):
    assert f in required, f"{f}-zorunlu-değil-olmalı (R9-ihlali-okumada-yakalanmıyor)"
# op-da-yapısal-zorunlu
assert content["op"] == "anchor"
# İSTEĞE-BAĞLI-olarak-yalnız-bilinen-alanlar-onaylanır (foreign_source RFC-009-§2,
# tool tanımlayıcı-meta); bilinmeyen-bir-alan-isteğe-bağlı-kesilirse-burada-patlama
assert optional <= {"foreign_source", "tool"}, \
    f"beklenmeyen-isteğe-bağlı-alanlar: {sorted(optional)}"
assert "foreign_source" in optional, "foreign_source-zorunlu-olmamalı (additive)"
print("  4b) R9-alanları-zorunlu; foreign_source/tool-isteğe-bağlı-onaylandı")

# 5) NEGATİF-ÖZ-DENETİM: presentation_only-çıkarılınca-RED-olmalı (parite-
# testi-kendini-yakar — tasarıma-geri-eklenirse-burada-patlardı)
trial = {k: v for k, v in content.items() if k != "presentation_only"}
ok3, res3 = inject(trial)
assert not ok3, "presentation_only'suz-tasarım-GREEN-geçemez (R9-5-green-giydirme)"
print("  5) presentation_only'suz-tasarım-RED (parite-testi-kendini-yakar)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 1-5) tasarım↔pilot-parite (çıkarımla)"; else FAIL=$((FAIL+1)); note "  FAIL parite"; cat "$LOG"; fi

# 6) cmd_anchor'ın---foreign-source-bayrağı-donmuş-alanı-yazar-ve-GREEN-doğrulanır
note "6) --foreign-source-donmuş-alanı-yazıyor"
PKG6="$(mktemp -d)"
python3 tamga_runner.py quickstart "$PKG6" >> "$LOG" 2>&1
python3 tamga_runner.py anchor "$PKG6" --foreign-registry apodix/epoch \
  --foreign-fact "0x02362521254a8ca4f75097267655f6aeb8524217a25c261f60538edc367136e2" \
  --foreign-digest "0x997c497ef5fe81b98290e990cd8f62e674bd55db8ab3c3ea85d3931b1e6ff71d" \
  --verified-at 2026-09-10T07:32:08Z --tool "at061" \
  --foreign-source "https://explorer.testnet.apodix.vauban.tech/v1/anchors/proof/0x0236" \
  >> "$LOG" 2>&1
RC_SRC=$?
python3 - "$PKG6" <<'PYEOF' >> "$LOG" 2>&1
import sys, json, pathlib
rows = [json.loads(l) for l in (pathlib.Path(sys.argv[1]) / "ledger.jsonl").read_text(
    encoding="utf-8").splitlines() if l.strip()]
a = [r for r in rows if r.get("op") == "anchor"][0]
assert a.get("foreign_source", "").startswith("https://"), \
    f"foreign_source-yazılmamış: {a.get('foreign_source')!r}"
print("  foreign_source-kayıtta:", a["foreign_source"])
PYEOF
RC_CHK=$?
python3 tamga_runner.py ledger-verify "$PKG6" >> "$LOG" 2>&1
RC_LV=$?
if [ $RC_SRC -eq 0 ] && [ $RC_CHK -eq 0 ] && [ $RC_LV -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 6) --foreign-source-yazıldı-ve-GREEN"
else
  FAIL=$((FAIL+1)); note "  FAIL 6) src=$RC_SRC chk=$RC_CHK lv=$RC_LV"; cat "$LOG"
fi
rm -rf "$PKG6"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-061: tasarım↔pilot-şekil-paritesi"
[[ $FAIL -eq 0 ]]
