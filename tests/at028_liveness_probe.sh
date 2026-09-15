#!/usr/bin/env bash
# AT-028 — liveness probe karar-matrisi (offline, CI-deterministik).
# Araç (tamga_liveness; console `tamga liveness-probe`) CANLI ağa gider (Sepolia+mainnet GREEN, ölü-RPC İNDETERMİNE
# 2026-09-15 el-koşumuyla tescilli); SÜİT içi kontrol ise saatleri-İNELER: script'li mock-RPC
# üzerinden 5-hâl — GREEN / statik-zincir İNDETERMİNE / error-yanıt / çöp-yanıt (traceback YOK)
# / genesis RED. Timestamp-GÜVENSİZLİĞi sözleşmesi: probe sunucu-duvar-saatini HİÇ okumaz —
# mock'un "timestamp" alanı bilerek ÇELİŞKİLİ verilir (yanlış-sahte-taze) ve GREEN yine de
# number-farkıyla karar vermelidir: kanıt = varlık-karıtı, söz-değil.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-028/$(date +%F)}/at028.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"
# at008 dersi: anormal-ölümde sahte-sunucu-yeti mi ölü-RPC-sonucunu-bozabilir → hem-girişte
# hem-çıkışta kalıp-temizliği (lock-tuzagı-aile-disiplini).
pkill -f "/tmp/at028-" 2>/dev/null; trap 'pkill -f "/tmp/at028-" 2>/dev/null' EXIT
D=$(mktemp -d /tmp/at028-XXXX)

cat > "$D/mock.py" <<'PYEOF'
import http.server, json, sys
MODE = sys.argv[1]; PORT = int(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        num = body["params"][0]
        if MODE == "advancing":      # latest=100; K-öncesi sorulursa 90 döner → span=10
            n = 100 if num == "latest" else 90
            r = {"number": hex(n), "timestamp": "0x0"}  # timestamp ÇELİŞKİLİ-SAhte: okunmamalı
        elif MODE == "static":       # her-soru 100 → span=0 → K-ilerleme KANITSIZ → İNDETERMİNE
            r = {"number": "0x64", "timestamp": "0xffffffffff"}
        elif MODE == "genesis":
            r = {"number": "0x0", "timestamp": "0x0"}
        elif MODE == "error":
            self._send({"jsonrpc": "2.0", "id": 1, "error": {"code": -32000, "message": "handler fail"}}); return
        elif MODE == "garbage":
            self._send({"jsonrpc": "2.0", "id": 1}); return   # "result" YOK
        self._send({"jsonrpc": "2.0", "id": 1, "result": r})
    def _send(self, o):
        b = json.dumps(o).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PYEOF

run_case() { MODE=$1; WANT_RC=$2; WANT_VERDICT=$3; PORT=$((40280+RANDOM%200));
  python3 "$D/mock.py" "$MODE" "$PORT" & SRV=$!
  for i in 1 2 3 4 5 6 7 8 9 10; do python3 -c "import socket,sys; s=socket.socket(); sys.exit(s.connect_ex(('127.0.0.1',$PORT)))" 2>/dev/null && break; sleep 0.2; done
  OUT=$(python3 -m tamga_liveness --rpc "http://127.0.0.1:$PORT" --max-age-blocks 10 2>&1); RC=$?
  kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
  echo "[$MODE rc=$RC] $OUT" >> "$LOG"
  if [ "$RC" -eq "$WANT_RC" ] && echo "$OUT" | grep -q "$WANT_VERDICT" && ! echo "$OUT" | grep -q Traceback; then
    ok 0 "AT-028 $MODE → rc$RC $WANT_VERDICT (traceback-yok)"
  else
    ok 1 "AT-028 $MODE: rc=$RC beklenen=$WANT_RC, çıktı: $(echo "$OUT" | head -1 | cut -c1-80)"
  fi
}

run_case advancing 0 GREEN
run_case static    2 İNDETERMİNE
run_case genesis   1 RED
run_case error     2 İNDETERMİNE
# evaluated-alanı: bakamadı=false, baktı=true (makine-okunur-ayrim — #2887 dersinin-kendi-hijyeni)
PORT=$((40280+RANDOM%200)); python3 "$D/mock.py" error "$PORT" & SRV=$!
for i in 1 2 3 4 5 6 7 8 9 10; do python3 -c "import socket,sys;s=socket.socket();sys.exit(s.connect_ex(('127.0.0.1',$PORT)))" 2>/dev/null && break; sleep 0.2; done
OUT=$(python3 -m tamga_liveness --rpc "http://127.0.0.1:$PORT" --max-age-blocks 10 2>/dev/null)
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d['evaluated'] is False and d['verdict']=='İNDETERMİNE' else 1)"
ok $? "AT-028 evaluated:false — 'bakamadım' 'baktık-yeşil-değil'den makine-alanıyla-ayrılır"
run_case garbage   2 İNDETERMİNE

rm -rf "$D"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
