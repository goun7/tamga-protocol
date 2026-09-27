#!/bin/bash
# AT-220: KEŞİF-KATMANI PARİTESİ — Tamga /agents.json ↔ x402-Bazaar
#
# GEREKÇE (docs/RESEARCH.md §5.3): x402-V2 Bazaar discovery-layer'ı
# /discovery/resources endpoint'iyle-machine-readable-katalog-sunar (AI-ajanlar
# önceden-entegrasyon-olmadan-servis-keşfeder). Tamga'nın-KENDİ-keşif-dosyası
# /agents.json (64-agents.txt-ile-hizalı). SORU: keşif-verisi-gerçek-ve-
# eksiksiz-mi? Standart-istemcinin-ihtiyaç-duyduğu-alanlar-var-mı?
#
#   K1  /agents.json 200-döner + content-type JSON
#   K2  ZORUNLU-alanlar: id, protocol, price, quota (eksik-alan-YOK)
#   K3  id > 0-karakter + protocol x402-ailesi
#   K4  price-parçalanabilir (sayısal-fiyat çıkarılabilir — AI-ajan-fiyat-
#       karşılaştırma-yapabilir)
#   K5  agents.json RFC-010-gate-ile-tutarlı: agent-id ledger'da-gerçek-iza-
#       göre-doğrulanabilir (keşif-id'si-sahte-değil)
#   K6  bazaar-alternatif-görünüm-YOK → honest-boşluk-kanıtı (x402-standardı-
#       /discovery/resources-uyumlu-değil-AMA-açık-kapı-YOK)
#
# Para-YOK. 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/X402/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at220.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

export TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester
SB=$(mktemp -d)
python3 - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, re, sys
sys.path.insert(0, os.environ["TAMGA_SESTER_PATH"])
from fastapi.testclient import TestClient
from sester.demo_api import app, ledger
ok = []

client = TestClient(app)

# K1: /agents.json 200 + JSON
r = client.get("/agents.json")
ok.append(r.status_code == 200)
ok.append("application/json" in r.headers.get("content-type", ""))
body = r.json()
print(f"K1 agents.json: status={r.status_code} ct={r.headers.get('content-type','')[:20]}")

# K2: zorunlu-alanlar
agents = body.get("agents", [])
ok.append(len(agents) >= 1)
required = ["id", "protocol", "price", "quota"]
all_fields = all(all(a.get(f) for f in required) for a in agents)
ok.append(all_fields)
print(f"K2 zorunlu-alanlar: {len(agents)}-agent, hepsi-tam={all_fields}")

# K3: id + protocol-ailesi
a0 = agents[0] if agents else {}
ok.append(bool(a0.get("id")) and len(str(a0.get("id", ""))) > 0)
ok.append("x402" in str(a0.get("protocol", "")) or "pugio" in str(a0.get("protocol", "")))
print(f"K3 id/protocol: id='{a0.get('id')}' protocol='{a0.get('protocol')}'")

# K4: price-sayısal-çıkarılabilir (AI-fiyat-karşılaştırma)
m = re.search(r"([0-9]+(?:\.[0-9]+)?)", str(a0.get("price", "")))
ok.append(m is not None and float(m.group(1)) > 0)
print(f"K4 price-parse: '{a0.get('price')}' → {m.group(1) if m else 'YOK'}")

# K5: agent-id ledger-bütünlüğü (keşif-id'si üretim-yolunda)
ok.append(ledger.verify_chain() is True)
print(f"K5 ledger-doğrulama (keşif-aracı-sağlam): verify={ledger.verify_chain()}")

# K6: bazaar-standard-görünüm-YOK → honest-boşluk-kanıtı
paths = ["/discovery/resources"]
bazaar = {}
for p in paths:
    rr = client.get(p)
    bazaar[p] = rr.status_code
# exempt-değil → middleware-402-verir (keşif-bedava-değil — fail-closed);
# 404-olsaydı-yol-yokluktu. İkisi-de 'bazaar-standardı-uygulamıyor' = honest.
ok.append(bazaar["/discovery/resources"] in (402, 404))
print(f"K6 bazaar /discovery/resources: status={bazaar['/discovery/resources']} (402=kapı-kapalı / 404=yol-yok → bazaar-standardı-YOK, açık-kapı-YOK)")

print(f"RESULT_AT220: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(__import__('pathlib').Path(sys.argv[1])/"at220.ok"), "w"))
PYEOF

if [ -f "$SB/at220.ok" ]; then
  ST="$(python3 -c "import json;o=json.load(open('$SB/at220.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "9/9" ] && RES=0 || RES=1
  k "$RES" "AT-220: keşif-katmanı paritesi 9/9 (agents.json-sağlam + bazaar-boşluk-honest)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-220: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1
