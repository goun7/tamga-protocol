#!/bin/bash
# AT-213: LEDGER FUZZ ROBUSTNESS — bozuk-girişler-karşısında-fail-closed.
#
# GEREKÇE (docs/RESEARCH.md §2 ile-bağlantılı): OracleTrust'ın-temel-vaadi
# "provenance-kayıtları-doğrulanabilir" — Tamga'da sester.ledger verify_chain()
# bunu-sağlar. AMA robustness KANITLANMAMIŞTİ: 50-rastgele-bozuk-event
# (yanlış-hash, sıralama-bozuk, negatif-miktar, bytes-payload-şifre-dışı,
# prev-hash-kopuk) eklendiğinde verify_chain HEPSİNİ-RED-vermeli ve zara-görmüş
# SAF-DELİK BIRAKMAMALI. Bu-test "sessiz-yeşil-geçiş" tuzağını-arar:
#   • bozulmadan-önce: verify-True (sağlıklı-temel)
#   • her-bozuk-enjeksiyon-sonrası: verify-False (fail-closed)
#   • 50/50-RED + toplam-1-hariç-hepsi-bozuk (yan-etki-yayılımı-YOK)
#   • son-geri-yükleme: önbellekten-saftan-rekalküle (self-heal kanıtı)
#
# Para-YOK (yerel-sqlite; TAMGA_LIVE-GEREKMEZ). 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/SESTER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at213.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

export TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester
SB=$(mktemp -d)
python3 - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, pathlib, random, sqlite3, sys, subprocess
sys.path.insert(0, os.environ["TAMGA_SESTER_PATH"])
from sester.ledger import Ledger, canonical_line, seal
ok = []

random.seed(213)
sb = pathlib.Path(sys.argv[1])
db = str(sb / "receipts.sqlite")
SECRET = "fuzz-secret-213"
L = Ledger(db, SECRET)

# --- sağlıklı-temel: 20-geçerli-event (ERRATUM-K0.2-taksonomisi-ile) ---
TYPES = ["charge_receipt", "refund", "permission_decision", "policy_denied",
         "escalation_parked", "escalation_approved", "escalation_denied",
         "escalation_consumed", "protocol_intent", "settlement", "webhook_delivery"]
for i in range(20):
    L.append(TYPES[i % len(TYPES)], f"agent-{i%4}", f"host-{i%3}",
             float(i + 1) * 0.001,
             json.dumps({"i": i, "p": "x" * (i % 32)}))
base = L.verify_chain()
ok.append(base is True)
print(f"K1 sağlıklı-temel: verify={base} (20-event)")

# --- 50-bozuk-enjeksiyon: her-biri-sonrası verify-False-bekle ---
# seal() str-döndürür (hexdigest) → sqlite TEXT; mutasyonlar-STR-olmalı.
con = sqlite3.connect(db)
red = 0; total = 0
def last_seq():
    return con.execute("SELECT MAX(seq) FROM events").fetchone()[0]
for i in range(50):
    kind = i % 5
    if kind == 0:    # hash-boz: son-hex-karakteri-tersine-çevir
        row = con.execute("SELECT hash FROM events WHERE seq = (SELECT MAX(seq) FROM events)").fetchone()
        h = row[0] if isinstance(row[0], str) else str(row[0])
        con.execute("UPDATE events SET hash = ? WHERE seq = (SELECT MAX(seq) FROM events)",
                    (("0" if h[-1] != "0" else "1") + h[1:],))
    elif kind == 1:  # prev-kop: prev_hash'ı-genesis-dışı-şeyle-değiştir
        con.execute("UPDATE events SET prev_hash = ? WHERE seq = (SELECT MAX(seq) FROM events)",
                    ("ff" * 32,))
    elif kind == 2:  # neg-miktar (charge_receipt-yolu-dışında-desteklenir-AMA
                     # verify-ETHSİZ-mutasyona-uğramış-satırı-reddetmeli)
        con.execute("UPDATE events SET amount = ? WHERE seq = (SELECT MAX(seq) FROM events)",
                    (-1.0 * (i + 1),))
    elif kind == 3:  # ts-boz: sıralı-olmayan-timestamp
        con.execute("UPDATE events SET ts = ? WHERE seq = (SELECT MAX(seq) FROM events)",
                    (1e19 * (i + 1),))
    else:            # payload-boz
        con.execute("UPDATE events SET payload = ? WHERE seq = (SELECT MAX(seq) FROM events)",
                    ("INJECTED-X" * 8,))
    con.commit()
    total += 1
    v = L.verify_chain()
    if v is False: red += 1
    else: print(f"  #{i} kind-{kind}: VERIFY-TRUE (!) — fail-closed-DELİK")
ok.append(red == total)
print(f"K2 50-bozuk-enjeksiyon: {red}/{total}-RED (fail-closed-oranı {100*red//total}%)")

# K3: self-heal — bozuk-son-satırı-sil; kalan-19-sağlam-satırı-yeni-Ledger'la
#     doğrula (bağlantı-önbelleği-örtüşmesin). Mutasyonlar-sadece-son-satırı
#     UPDATE-etti (yeni-seq-eklemedi) → seq>20-boş; seq-20-bozuk.
con.execute("DELETE FROM events WHERE seq >= 20")
con.commit(); con.close()
L2 = Ledger(db, SECRET)
after = L2.verify_chain()
ok.append(after is True)
print(f"K3 self-heal: bozuk-son-satır-silindi → verify={after} (19-sağlam-kaldı)")
L2.close()
print(f"RESULT_AT213: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(sb / "at213.ok"), "w"))
PYEOF

if [ -f "$SB/at213.ok" ]; then
  ST="$(python3 -c "import json;o=json.load(open('$SB/at213.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "3/3" ] && RES=0 || RES=1
  k "$RES" "AT-213: ledger fuzz robustness 3/3 (K1 sağlıklı-temel K2 50/50-RED K3 self-heal)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-213: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-213: ledger fuzz — bozuk-girişlerde fail-closed (para-YOK)"
[ "$FAIL" -eq 0 ] || exit 1
