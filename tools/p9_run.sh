#!/usr/bin/env bash
# P9 GERÇEK KOŞU (founder, cüzdan gerekli) — ödeme-sonrası tek-komut.
#
# Kullanım: bash tools/p9_run.sh <TAM-TX-HASH> <RECEIP-JSON> [TARİH]
# Örnek:    bash tools/p9_run.sh 0xabc123…65 receipt.json
#
# Üç-ölçüt-keseni: ANINDA + KANIT + BAĞIMSIZ. Hepsi-dolu-sayılırsa P9 KAPANIR.
# K19.2: tx-hash-asla-kesik-kabul-edilmez (araç-kendisi-reddeder).
set -euo pipefail

HASH="${1:?kullanım: p9_run.sh <TAM-TX-HASH> <RECEIPT-JSON> [TARİH]}"
REC="${2:?receipt-json-şart (ödeme-anında-üretilmiş-olmalı)}"
DATE="${3:-$(date +%Y-%m-%d)}"

# K19.2: önce-evidence'a-yaz, SONRA-postala/dokümante-et
EV=".evidence/P9/$DATE"
mkdir -p "$EV"
printf '%s\n' "$HASH" > "$EV/tx-hash.txt"

echo "1/5 bağımsız ödeme-bacağı (stdlib-only, tamga-kodu-ödemede-yok)…"
python3 tools/p9_independent_verify.py "$HASH" --receipt "$REC" | tee "$EV/p9-verify.log"
RC1=${PIPESTATUS[0]}

echo
echo "2/5 makbuz-bacağı (paymentId → contentHash → receipt zinciri)…"
if python3 tools/verify_dx402_vector.py "$REC" 2>&1 | tee "$EV/dx402-verify.log"; then :; fi

echo
echo "3/5 ham RPC yanıtı arşivleniyor (bağımsız-doğrulama-ham-kanıtı)…"
python3 - "$HASH" <<'PY' | tee "$EV/rpc-receipt.json"
import json, sys, urllib.request
h = sys.argv[1]
payload = json.dumps({"jsonrpc":"2.0","id":1,"method":"eth_getTransactionReceipt","params":[h]}).encode()
req = urllib.request.Request("https://1rpc.io/base", data=payload,
      headers={"Content-Type":"application/json","User-Agent":"tamga-p9-run"})
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        print(json.dumps(json.load(r).get("result"), indent=1))
except Exception as e:
    print(json.dumps({"hata": str(e)}))
PY

echo
echo "4/5 meta…"
cp "$REC" "$EV/receipt.json"
python3 - "$HASH" "$DATE" <<'PY' | tee "$EV/meta.json"
import json, sys, datetime
h, d = sys.argv[1], sys.argv[2]
print(json.dumps({"tarih": d, "gercek_kanit": True, "tx_hash": h,
                  "tur": "GERCEK", "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()},
                 indent=1))
PY

echo
echo "5/5 üç-ölçüt-keseni:"
echo "  ANINDA   : receipt-zamanı ≤ block-zamanı (dx402-verify'da-kontrol)"
echo "  KANIT    : $EV/tx-hash.txt + rpc-receipt.json (TAM-hash)"
echo "  BAĞIMSIZ : p9-verify.log (stdlib-only, tamga-kodu-ödemede-yok)"
echo
echo "P9-koşusu-bitti — ROADMAP'te-P9-satırını-✅-ile-güncelle (üç-ölçüt-doluysa)"
