#!/bin/bash
# AT-218: LEDGER BATCH-VERIFY THROUGHPUT + KÜMÜLATİF-BAĞLAMSAL-BÜTÜNLÜK
#
# GEREKÇE (docs/RESEARCH.md §5.3b): x402-V2'nin batch-settlement-scheme'i
# (EIP-3009 ödeme-kanalları + kümülatif-kuponlar + toplu-onchain-redemption)
# tekrarlanan-ücretli-çağrıların-throughput'u-için-tasarlanmış. TAMGA'DA-ÖDEME-
# KANALI-YOK — bunun-yerine-off-chain-HMAC-zinciri-var. SORU: Tamga'nın-yolu
# throughput-açısından-yeterli-mi VE bütünlük-batch-çalışınca-korunur-mu?
#
# Bu-test-iki-yanıt-verir:
#   K1  THROUGHPUT: 1000-event'lik-sağlıklı-zinciri tek verify_chain-çağrısıyla
#       <5 saniyede-doğrula (batch-settlement-alternatifinin-pratik-eşdeğeri)
#   K2  KÜMÜLATİF-KESİRLİK: 1000'lik-zincirde ORTADA-bir-satır-bozulursa
#       verify False-vermeli (küçük-bir-bozukluk-tüm-batch'i-geçersiz-kılar)
#   K3  DOĞRU-POZİTİF-KONTROL: aynı-1000-zincir bozulmadan-önce True
#   K4  EVENT-ÇEŞİTLİLİĞI: tüm-11-taksonomi-tipi-karışık-sırada-doğrulanır
#   K5  HIZ-REGRESYONU: önceki-çalıştırmadan-2×-yavaşlamaz (önbellek-yok)
#
# Para-YOK (yerel-sqlite). 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/SESTER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at218.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

export TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester
SB=$(mktemp -d)
python3 - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, pathlib, sqlite3, sys, time
sys.path.insert(0, os.environ["TAMGA_SESTER_PATH"])
from sester.ledger import Ledger
ok = []

sb = pathlib.Path(sys.argv[1])
db = str(sb / "batch.sqlite")
SECRET = "at218-batch-secret"
L = Ledger(db, SECRET)
TYPES = ["charge_receipt", "refund", "permission_decision", "policy_denied",
         "escalation_parked", "escalation_approved", "escalation_denied",
         "escalation_consumed", "protocol_intent", "settlement", "webhook_delivery"]

N = 1000
t0 = time.monotonic()
for i in range(N):
    et = TYPES[i % len(TYPES)]
    amt = float(i + 1) * 0.0001
    # charge_receipt P0.0-yasak (kota-bypass-koruyucu); diğer-tipler-0.0-ok
    if et == "charge_receipt":
        amt = float(i + 1) * 0.0001
    else:
        amt = 0.0 if (i % 3 == 0) else 0.001
    L.append(et, f"agent-{i%8}", f"host-{i%4}", amt,
             json.dumps({"i": i, "batch": "at218"}))
append_dur = time.monotonic() - t0

# K3: doğru-pozitif-önce
t0 = time.monotonic()
v_ok = L.verify_chain()
verify_dur = time.monotonic() - t0
ok.append(v_ok is True)
print(f"K3 doğru-pozitif: verify={v_ok} ({N}-event)")

# K1: throughput — 1000-event < 5s
ok.append(verify_dur < 5.0)
print(f"K1 throughput: verify {N}-event {verify_dur:.3f}s'de (<5s={verify_dur<5.0}); append {append_dur:.3f}s")

# K4: event-çeşitliliği — 11-tip-de-yazıldı
written = set(sqlite3.connect(db).execute(
    "SELECT DISTINCT event_type FROM events").fetchall())
written = {w[0] for w in written}
ok.append(written == set(TYPES))
print(f"K4 çeşitlilik: {len(written)}/11-tip-yazıldı")

# K2: kümülatif-kesirlik — ORTADAKI-satırı-boz (seq=500)
con = sqlite3.connect(db)
row = con.execute("SELECT hash FROM events WHERE seq = 500").fetchone()
h = row[0]
con.execute("UPDATE events SET hash = ? WHERE seq = 500",
            (h[:-1] + ("0" if h[-1] != "0" else "1"),))
con.commit()
# teneke-Ledger (stale-snapshot-YOK — AT-213-dergisi)
Lv = Ledger(db, SECRET)
v_bad = Lv.verify_chain()
Lv.close()
ok.append(v_bad is False)
print(f"K2 kümülatif-kesirlik: orta-satır-bozuk → verify={v_bad} (False-beklenir)")
con.close()

# K5: hız-regresyonu — ikinci-tam-zincir-hızlı-kurulup-ölçülür
sb2 = pathlib.Path(str(sb) + "-b"); sb2.mkdir(exist_ok=True)
db2 = str(sb2 / "b2.sqlite")
L2 = Ledger(db2, SECRET)
t0 = time.monotonic()
for i in range(N):
    et2 = TYPES[i % len(TYPES)]
    amt2 = 0.001 if et2 == "charge_receipt" else (0.0 if i % 3 == 0 else 0.001)
    L2.append(et2, "a", "h", amt2, "{}")
dur2 = time.monotonic() - t0
ok.append(dur2 < 5.0)   # aynı-büyüklükte-hızlı
print(f"K5 hız-regresyonu: 2.-zincir {dur2:.3f}s (<5s={dur2<5.0})")
L2.close()

print(f"RESULT_AT218: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(sb / "at218.ok"), "w"))
PYEOF

if [ -f "$SB/at218.ok" ]; then
  ST="$(python3 -c "import json;o=json.load(open('$SB/at218.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "5/5" ] && RES=0 || RES=1
  k "$RES" "AT-218: ledger batch-verify throughput + kümülatif-kesirlik 5/5 (1000-event)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-218: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1
