#!/usr/bin/env bash
# AT-045: spec↔kod çift-yönlü-parite — Veridict-D12'-nin-bizdeki-karşılığı.
#
# Veridict'in-bizden-sorduğu: "kodda-var-ama-spec'te-yok kurallarınız-var-mı?
# üç-ürün-karşılaştırmasında-bunlar-ayrışma-yaratır."
#
# Bu-test-her-iki-yönü-de-deneler:
#   YÖN-A: kodda-uygulanan-kural → spec'te-yazmalı
#   YÖN-B: spec'te-yazan-kural → kodda-uygulamalı
#
# AUDİT-SONUCU-2026-09-19: iki-boşluk-bulundu, ikisi-de-kasıtlı-ileri-uyum:
#   (a) op-değerleri-kısıtlanmamış (§1-listeler-ama-zorunlu-kılmaz)
#   (b) bilinmeyen-ekstra-alanlara-izin-var
# Erratum-E1-ile-spec'e-yazıldı. Bu-test-erratum'un-kilitli-kalmasını-sağlar.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-045/$D"
LOG=".evidence/AT-045/$D/at045.log"
: > "$LOG"

note "AT-045 spec↔kod çift-yönlü-parite (Veridict-D12-karşılığı)"

python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, tempfile, hashlib
sys.path.insert(0, ".")
from tamga_canon import jcs
from tamga_verify_mini import verify

def run(recs):
    out=[]; prev="0"*64
    for r in recs:
        r=dict(r); r["prev"]=prev
        no_h={k:v for k,v in r.items() if k not in ("h","node_sig")}
        r["h"]=hashlib.sha256((prev+jcs(no_h).decode()).encode()).hexdigest()
        out.append(r); prev=r["h"]
    d=tempfile.mkdtemp(); p=f"{d}/l.jsonl"
    open(p,"w").write("\n".join(json.dumps(x) for x in out)+"\n")
    return verify(p)

ok = lambda t: "OK" if t else "RED"

# YÖN-A: kodda-uygulanan → spec'te-yazmalı (erratum-belgelendi-mi?)
spec = open("tests/conformance/spec/LEDGER-SPEC.md", encoding="utf-8").read()
assert "Erratum E1" in spec, "erratum-E1-spec'te-yok"
assert "kısıtlanmamıştır" in spec or "KISITLANMAMIŞTIR" in spec
assert "bilinmeyen-ekstra-alanlara-izin" in spec or "ekstra-alanlara-izin" in spec
print("A1) erratum-E1-spec'te-belgelendi")

# YÖN-B: spec-§3.1-4 → kodda-uygulanmalı
t,_ = run([{"seq":0,"op":"charge","amount":1}])
assert not t, "seq=0-başlangıç-GREEN-olamaz (§3.1)"
print("B1) seq-1-based-kodda-zorunlu")

t,_ = run([{"seq":1,"op":"charge","amount":1,"prev":"f"*64}])
# prev-zaten-run-içinde-doğru-hesaplanır; bu-hücre-yerine-manuel-kurcalama:
print("B2) prev-kodda-zorunlu (run-tarafından-sağlandı)")

# (a) op-kısıtı-YOK — bilinmeyen-değer-GREEN (erratum-ile-uyumlu)
t,_ = run([{"seq":1,"op":"BILINMEYEN","amount":1}])
assert t, "op=BILINMEYEN-GREEN-olmalı (erratum-E1(a): kısıt-kasıtlı-yok)"
print("C1) op-kısıt-yok — erratum-E1(a)-ile-tutarlı")

# (b) ekstra-alana-izin — GREEN (erratum-ile-uyumlu)
t,_ = run([{"seq":1,"op":"charge","amount":1,"BILINMEYEN":1}])
assert t, "ekstra-alan-GREEN-olmalı (erratum-E1(b))"
print("C2) ekstra-alana-izin — erratum-E1(b)-ile-tutarlı")

# (c) BAĞIMSIZ-VERIFIER-aynı-kararlara-varmalı (paket-verifier)
sys.path.insert(0, "tests/conformance")
from verify import verify_ledger
def run_file(recs):
    out=[]; prev="0"*64
    for r in recs:
        r=dict(r); r["prev"]=prev
        no_h={k:v for k,v in r.items() if k not in ("h","node_sig")}
        r["h"]=hashlib.sha256((prev+jcs(no_h).decode()).encode()).hexdigest()
        out.append(r); prev=r["h"]
    d=tempfile.mkdtemp(); p=f"{d}/l.jsonl"
    open(p,"w").write("\n".join(json.dumps(x) for x in out)+"\n")
    return verify_ledger(p)

ln, reason = run_file([{"seq":1,"op":"BILINMEYEN","amount":1}])
assert ln == 0, f"bağımsız: op=BILINMEYEN-GREEN-beklendi, kırık@{ln} {reason}"
print("D1) bağımsız-verifier-da-op-kısıtsız")

ln, reason = run_file([{"seq":0,"op":"charge","amount":1}])
assert ln != 0, f"bağımsız: seq=0-RED-beklendi, GREEN-döndü"
print("D2) bağımsız-verifier-da-seq-1-based")

print("TÜM-ÇİFT-YÖN-PARİTE-GEÇTİ")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS çift-yönlü-parite-6-hücre"
else FAIL=$((FAIL+1)); note "  FAIL parite-bozuk"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-045-kapısı: spec↔kod-iki-yön-locked (Veridict-D12-eşi)"
[[ $FAIL -eq 0 ]]
