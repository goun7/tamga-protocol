#!/usr/bin/env bash
# AT-055: ALICI-TARAFI-BİLİNMEYEN-OP — Sester'ın-5.tur-derstinin-bizdeki-aynası.
#
# SESTER'IN-İTİRAFININ-BİZDEKİ-GERÇEĞİ: "operatör-pg_restore/COPY-ile-doğrudan-
# DB'ye-yazarsa-bölge-kapım-onu-göremez-ve-o-satır-yine-de-yeşil-doğrulanır,
# çünkü-kanıt-zinciri-event_type'ı-opak-veri-olarak-hash'liyor (§7-rule-3)."
#
# BİZDE-AYNISI-KANITLANDI: operatör-doğrudan-ledger.jsonl'a-geçerli-hash-zinciriyle
# op='tenderix-fake'-yazarsa:
#   - üretici-tarafı-3-katman-da-göremez (_ledger_append/_log/cmd_import-kapıları
#     yalnızca-BU-KÜTÜPHANE-üzerindeki-çağrıları-kapsar — kod-kapsamı-sabıtı)
#   - _verify_chain-op'u-OPAK-veri-olarak-hash'ler → zincir-yeşil-geçer
#
# Bu-üretici-garantisinin-dürüst-hali: "BU-KÜTÜPHANE-üzerinden-yazılan-her-satırın
# bilinen-op'u-var" — "veritabanındaki-ver-ledger'daki-her-satırın"-değil.
#
# KAPANIŞ (K0-uyumlu, alıcı-tarafı): unknown_ops(recs)-yardımcı-okunan-kayıtlarda
# bilinmeyen-op'ları-döndürür. KARAR-alıcıda-kalır (abstain/warn/reject) —
# sert-reject-bilerek-yardımcıda-DEĞİL: E1(a)-serbestliği-ve-§7-opaklığı-bozmaz
# (Sester'ın-§7-rule-3'ü-ve-Veridict-D13-abstain'ı-ile-aynı-ruh).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
LOG=".evidence/AT-055/$D/at055.log"
mkdir -p ".evidence/AT-055/$D"
: > "$LOG"

note "AT-055: alıcı-tarafı-bilinmeyen-op (Sester-5.tur-aynası)"

# 1) ÜRETİM-GERÇEĞİ: doğrudan-yazılmış-bilinmeyen-op-zincir-yeşili-geçer
note "1) doğrudan-yazma — bilinmeyen-op-zincir-yeşili-geçiyor (kanıt)"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, json, tempfile, pathlib, hashlib
sys.path.insert(0, "."); sys.argv = ["x"]
import tamga_runner as TR
d = tempfile.mkdtemp(); lp = pathlib.Path(d) / "L.jsonl"
recs = []; prev = "0" * 64
for i, op in enumerate(["charge", "tenderix-fake", "grant"], 1):
    r = {"op": op, "detail": "x", "seq": i, "prev": prev}
    h = hashlib.sha256((prev + TR.jcs(dict(r))).encode()).hexdigest()
    r["h"] = h; prev = h; recs.append(r)
with open(lp, "w") as f:
    for r in recs: f.write(TR.jcs(r) + "\n")
tip, why = TR._ledger_head(lp)
assert why == "ok", f"zincir-kırıldı-beklenmiyordu: {why}"
print(f"  zincir-yeşil: {why} — op-opak-veri-olarak-hash'lendi")
# unknown_ops-onu-GÖRÜR
read = [json.loads(l) for l in open(lp)]
got = TR.unknown_ops(read)
assert got == {"tenderix-fake"}, f"yakalanamadı: {got}"
print(f"  unknown_ops: {got} — alıcı-tarafı-gördü")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 1) sınıf-kanıtlandı-ve-görüldü"
else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) KÜTÜPHANE-YOLU-HÂLÂ-GEÇİTLİ (üretici-tarafı-korunuyor)
note "2) kütüphane-yolu — _ledger_append-hâlâ-RED-veriyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, tempfile, pathlib
sys.path.insert(0, "."); sys.argv = ["x"]
import tamga_runner as TR
import io, contextlib
d = tempfile.mkdtemp(); lp = pathlib.Path(d) / "t.jsonl"
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    r = TR._ledger_append(lp, {"op": "tenderix-fake"})
assert r == 1, f"fail-closed-bozuldu: rc={r}"
assert not lp.exists(), "yazdı!"
print("  _ledger_append-hâlâ-RED+yazmıyor — üretici-tarafı-sağlam")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 2) üretici-geçidi-korunuyor"
else FAIL=$((FAIL+1)); note "  FAIL 2)"; cat "$LOG"; fi

# 3) E1(a)-KORUNUMU: yardımcı-reject-ETMEZ (opaklık-bozulmaz)
note "3) E1(a) — yardımcı-bilinmeyeni-reject-etmez (opt-in)"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, inspect
sys.path.insert(0, ".")
import tamga_runner as TR
src = inspect.getsource(TR.unknown_ops)
# yardımcı-yalnızca-DÖNDÜRÜR — karar-vermez
assert "return" in src and "reason_code" not in src, \\
    "yardımcı-karar-vermemeli!"
print("  yardımcı-yalnızca-görür — reject/warn/abstain-alıcıda")
# E1(a): op-kısıtlama-yok
import emitter_registry as ER
assert isinstance(ER.EMITTED_OPS, (set, frozenset))
print(f"  E1(a)-serbest-korunuyor: {len(ER.EMITTED_OPS)}-kayıtlı-op")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 3) E1(a)+§7-opaklık-korunuyor"
else FAIL=$((FAIL+1)); note "  FAIL 3)"; cat "$LOG"; fi

# 4) ÜRETİM-LEDGER'INDA-BİLİNMEYEN-OP-YOK (mevcut-corpus-temiz)
note "4) mevcut-corpus — bilinmeyen-op-yok"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, json, pathlib
sys.path.insert(0, "."); sys.argv = ["x"]
import tamga_runner as TR
tot = set()
for p in pathlib.Path(".").rglob("*.jsonl"):
    if ".venv" in p.parts or ".evidence" in p.parts:
        continue
    try:
        recs = [json.loads(l) for l in p.read_text(encoding="utf-8", errors="replace") if l.strip()]
    except Exception:
        continue
    u = TR.unknown_ops(recs)
    if u:
        print(f"    {p}: {sorted(u)}")
    tot |= u
assert not tot, f"corpus'ta-bilinmeyen-op-var: {sorted(tot)}"
print(f"  corpus-temiz — bilinmeyen-op-yok ({len(tot)})")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 4) corpus-temiz"
else FAIL=$((FAIL+1)); note "  FAIL 4)"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-055: alıcı-tarafı-kapı (üretici-kapsam-sınırı-dürüst-bildirildi)"
[[ $FAIL -eq 0 ]]
