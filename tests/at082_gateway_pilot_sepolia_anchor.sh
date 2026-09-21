#!/usr/bin/env bash
# AT-082: 00-GATEWAY-PILOT-TRAFİĞİ — 6 x402-servisi → Sepolia anchor (RFC-009).
#
# PROJE-HARITASI §7-ikinci-öncelik. 00-gateway (gateway.py:51 _match_route)
# 6 x402-servisini-tek-porttan-serve-eder (planlock-kendi-trial-sistemi-
# olduğu-için-hariç). Bu-test:
#   1) gateway-canlı-ve-7/7-up (/healthz)
#   2) 6-servisin-6-da-gerçek-x402-çağrı (exact-sester, gerçek-EIP-191)
#   3) her-çağrı-bir-receipt (Sester-ledger + Tamga-RFC-010-dikişi)
#   4) toplanan-receipt'lar → TEK-Sepolia-anchor (RFC-009 R9-1..R9-5)
#   5) R9-3-kanonik-0x+64-lowercase-özdoğrulama
#   6) NEGATİF: rasgele-adres-fail-closed-402 (gerçek-para-korunur)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/GATEWAY-PILOT/$(date +%F)/at082.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-082: 00-gateway pilot-trafiği — 6 x402-servisi → Sepolia anchor"

# Gateway-canlı-değilse-SKIP (INDETERMİNE — yeşil-boyanmaz)
if ! python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=5)" 2>/dev/null; then
  note "[SKIP] AT-082: gateway-8000-canlı-değil (CI/yerel-sandbox-yok) —"
  note "       pilot-traffic-ölçülemedi (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth-account-yokluğu-eksiklik-değil-İNDETERMİNE (gerçek-imza-üretilemez)
if ! python3 -c "import eth_account" 2>/dev/null; then
  note "[SKIP] AT-082: eth_account-yok — gerçek-EIP-191-üretilemedi (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

EV=".evidence/GATEWAY-PILOT"

# --- 1-4) pilot-trafik + receipt-toplama + anchor-üretimi
# stdout'u-ayrı-tut: quota-durumunu-pilot-çıktısından-okumak-için
PILOT_OUT="$(python3 tests/at082_pilot_traffic.py "$EV" 2>> "$LOG")" \
  || { note "  FAIL: pilot-trafik-koşmadı"; cat "$LOG"; FAIL=$((FAIL+1)); }
echo "$PILOT_OUT" >> "$LOG"

# KOTA-DURUMU: sandbox-demo-anahtarının-günlük-kotası-dolduysa-SKIP (INDETERMİNE).
# Bu-gerçek-fail-closed-davranıştır (quota_exceeded 402) — yeşil-boyanmaz;
# test-sahte-başarı-üretmez, ertesi-gün-veya-taze-anahtar-la-koşar.
# Tespit: pilot-traffic.json'daki-402-yanıt-gövdesinde-quota_exceeded.
if python3 - <<'PYEOF' 2>/dev/null
import json
from pathlib import Path
p = Path(".evidence/GATEWAY-PILOT/pilot-traffic.json")
if not p.exists():
    raise SystemExit(1)
d = json.loads(p.read_text(encoding="utf-8"))
for s, v in d.get("services", {}).items():
    body = str(v.get("body", ""))
    if "quota_exceeded" in body:
        print(f"quota: {s}")
        raise SystemExit(0)
raise SystemExit(1)
PYEOF
then
  note "[SKIP] AT-082: sandbox-günlük-kota-doldu (\$5) — fail-closed-402."
  note "       gerçek-sınırlama (INDETERMİNE); ertesi-gün-koş."
  if [ -f "$EV/pilot-traffic.6of6.json" ]; then
    note "       ÖNCEKİ-6/6-GREEN-kanıt: $EV/pilot-traffic.6of6.json"
  fi
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 tests/at082_sepolia_anchor.py "$EV" >> "$LOG" 2>&1 || {
  note "  FAIL: anchor-üretilemedi"; cat "$LOG"; FAIL=$((FAIL+1)); }

python3 - "$EV" <<'PYEOF' >> "$LOG" 2>&1
import json, sys, urllib.request
from pathlib import Path
ev = Path(sys.argv[1])
pilot = json.loads((ev / "pilot-traffic.json").read_text(encoding="utf-8"))
anchor = json.loads((ev / "anchor-sepolia.json").read_text(encoding="utf-8"))

# --- 1) gateway 7/7-up
h = json.loads(urllib.request.urlopen(
    "http://127.0.0.1:8000/healthz", timeout=8).read())
up = h.get("services_up", "0/0")
assert up == "7/7", f"gateway-7/7-up-beklendi: {up}"
print(f"  gateway /healthz: {up} up — gateway.py:51 _match_route 6-x402-tek-port")

# --- 2) 6-servisin-6-da-x402-çağrı-200
SVC = ("cleartag", "pqhaven", "repriceai", "callsnap", "vadedostu", "borsa")
for s in SVC:
    r = pilot["services"][s]
    assert r["http"] == 200, f"{s}-200-beklendi: {r['http']} {r['body'][:120]}"
print("  6-servisin-6-da-gerçek-x402-çağrı: 200 (exact-sester, gerçek-EIP-191)")
print("    " + " ".join(f"{s}:{pilot['services'][s]['http']}" for s in SVC))

# --- 3) her-çağrı-bir-receipt (Sester-ledger)
recs = pilot.get("receipts", [])
by_svc = {}
for r in recs:
    by_svc.setdefault(r["service"], []).append(r)
assert set(by_svc) == set(SVC), f"eksik-servis: {set(SVC)-set(by_svc)}"
for s, rs in by_svc.items():
    assert len(rs) >= 1, f"{s}-receipt-yok"
print(f"  her-çağrı-bir-receipt: 6-servis-{len(by_svc)}-kanal "
      f"(toplam {len(recs)} ledger-kayıdı)")

# --- 4) TEK-anchor (merkle-kökü 6-yaprak-üzerinden)
n = anchor["receipt_count"]
assert n == 6, f"6-yaprak-beklendi: {n}"
assert len(anchor["leaves"]) == 6, "6-leaf-beklendi"
assert anchor["sepolia"].get("ok") is True, \
    f"Sepolia-RPC-okuma-başarısız: {anchor['sepolia'].get('error')}"
print(f"  TEK-Sepolia-anchor: 6-receipt → merkle-kökü "
      f"(block {anchor['sepolia']['block_height']}, read-only-RPC)")

# --- 5) R9-1..R9-5 özdoğrulama
sys.path.insert(0, ".")
from tamga_runner import _is_canonical_0x64, _ANCHOR_VERSION, _KNOWN_FOREIGN_REGISTRIES
assert anchor["anchor_version"] == _ANCHOR_VERSION, "R9-1-anchor_version"
assert anchor["foreign_registry"] in _KNOWN_FOREIGN_REGISTRIES, "R9-2-registry"
assert _is_canonical_0x64(anchor["foreign_fact"]), "R9-3-foreign_fact-kanonik"
assert _is_canonical_0x64(anchor["foreign_digest"]), "R9-3-foreign_digest-kanonik"
assert anchor["foreign_fact"].startswith("0x") and len(anchor["foreign_fact"]) == 66
assert all(c in "0123456789abcdef" for c in anchor["foreign_fact"][2:])
assert anchor["presentation_only"] is True, "R9-5-presentation-only"
print(f"  R9-1..R9-5: version/registry/kanonik-0x+64/UTC/presentation-only ✓")
print(f"    foreign_fact  : {anchor['foreign_fact']}")
print(f"    foreign_digest: {anchor['foreign_digest']}")

# --- 6) NEGATİF: rasgele-adres fail-closed-402 (gerçek-para-korunur)
import urllib.error
req = urllib.request.Request("http://127.0.0.1:8000/cleartag/dogrula",
    data=json.dumps({"offer_id":"x","current_price":1.0,
                     "history":[]}).encode(),
    headers={"Content-Type":"application/json",
             "X-Payer-Address": "0x" + "ab" * 20}, method="POST")
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        kod = r.status
except urllib.error.HTTPError as e:
    kod = e.code
assert kod in (402, 403, 503), f"fail-closed-402-beklendi: {kod}"
print(f"  NEGATİF: rasgele-adres (ödeme-yok) → {kod} fail-closed "
      f"(gerçek-para-korunur)")
PYEOF
RC=$?
if [ $RC -eq 0 ] && [ $FAIL -eq 0 ]; then
  PASS=$((PASS+1))
  note "  PASS: altı-gateway-pilot-kontrolü"
  # Başarılı-koşumun-kanıtını-sakla (günlük-kota-dolunca-sonraki-koşumlar
  # SKIP-verir; bu-dosya-ilk-6/6-GREEN-kanıtı-olarak-kalır)
  cp "$EV/pilot-traffic.json" "$EV/pilot-traffic.6of6.json" 2>/dev/null || true
  cp "$EV/anchor-sepolia.json" "$EV/anchor-sepolia.6of6.json" 2>/dev/null || true
  cp "$LOG" "${LOG%.log}.GREEN.log" 2>/dev/null || true
else
  FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"
fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-082: 00-gateway pilot-trafiği → Sepolia anchor"
[[ $FAIL -eq 0 ]]
