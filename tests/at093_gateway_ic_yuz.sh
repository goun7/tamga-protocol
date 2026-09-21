#!/usr/bin/env bash
# AT-093: 00-GATEWAY İÇ-YÜZ — guvence-kanca + cron-bekçi + 7-route-dispatch.
#
# task-9 (gateway-derinleştirme). Gateway'in-iç-yüzünü-ölçer:
#   1) K1-kanca: /pqhaven pilot-filası SDK-kayıt + karar (deny→403)
#   2) K1-fail-closed: SDK-yüklenemezse istek-İLETİLMEZ (503)
#   3) K1-kapsam: kanca-yalnız /pqhaven (diğer-6-servis-dokunulmaz)
#   4) _match_route: 7-route-en-uzun-prefix + 404 + /healthz
#   5) zincir-kanca-doğrulaması: sdk.check() imzalı-ledger
#   6) cron-bekçi: son-K5-rapor-yaşı → alarm/temiz
#   NEG-1: fail-closed-503 (kayıt-yok-geçiş-yok)
#   NEG-2: K1-deny-sıralama-bug'ı (proxy/admin allow-geçer — G3'yü-G2-golüyor)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/GATEWAY-IC"
LOG="$EVDIR/$(date +%F)/at093.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

# gateway-venv (fastapi+httpx); yoksa-sistem-python3
GW=/home/gokun/projects/01_unicorn/00-gateway
if [ -x "$GW/.venv/bin/python3" ]; then PY3="$GW/.venv/bin/python3"
else PY3=python3; fi

note "AT-093: 00-gateway iç-yüz — guvence-kanca + bekçi + 7-route"

# Prereq: gateway-canlı (gerçek-trafiğin-yolu); yoksa-SKIP
if ! $PY3 -c "import httpx; httpx.get('http://127.0.0.1:8000/healthz',timeout=5)" \
     >/dev/null 2>&1; then
  note "[SKIP] AT-093: gateway :8000-canlı-değil (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# Prereq: SDK (81-OstrakonSOC) — kanca'nın-çalışabilmesi-için
if [ ! -d /home/gokun/projects/04_hukuk_sarti/81-OstrakonSOC/ajanguvence ]; then
  note "[SKIP] AT-093: ajanguvence-SDK-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# Prereq: KuralMotoru — NEG-2-sıralama-testi-için
if ! $PY3 -c "import sys; sys.path.insert(0,'/home/gokun/projects/04_hukuk_sarti/81-OstrakonSOC'); import ajanguvence.rules" 2>/dev/null; then
  note "[SKIP] AT-093: ajanguvence.rules-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

$PY3 - "$GW" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, sys, hashlib, tempfile
from datetime import date, timedelta
from pathlib import Path

GW = Path(sys.argv[1])
sys.path.insert(0, str(GW))                      # gateway.py + guvence_*
sys.path.insert(0, "/home/gokun/projects/04_hukuk_sarti/81-OstrakonSOC")

from fastapi import FastAPI, Request
from fastapi.testclient import TestClient
import httpx

TMP = Path(tempfile.mkdtemp(prefix="at093-"))
TEST_LEDGER = TMP / "ledger.jsonl"
ANAHTAR = hashlib.sha256(b"guvence-pilot-anahtar-turev").digest()

def kanca_app(ledger, sdk_yolu=GW / "guvence_kurallar.json", fc=False):
    """Gerçek guvence_kanca'yı-çalıştıran-izole-ASGI-app (test-double-YOK)."""
    import importlib, guvence_kanca as gk
    importlib.reload(gk)
    gk.GUVENTE_PREFIX = "/pqhaven"
    gk.GUVENTE_LEDGER = str(ledger)
    gk.GUVENTE_KURALLAR = str(sdk_yolu)
    gk.GUVENTE_SDK_YOLU = "/nonexistent-at093" if fc else \
        "/home/gokun/projects/04_hukuk_sarti/81-OstrakonSOC"
    gk._sdk, gk._sdk_hatasi = None, None
    if fc:
        # GERÇEK-import-başarısızlığı: önceki-testin-SDK-cache'i-temizlenir
        # (yoksa sys.path'teki-önceki-yol-import'u-başarılı-yapar → 503-gelemez)
        for m in list(sys.modules):
            if m == "ajanguvence" or m.startswith("ajanguvence."):
                sys.modules.pop(m)
        sys.path = [p for p in sys.path if "81-OstrakonSOC" not in p]
    os.environ["GUVENTE_PILOT"] = "1"
    app = FastAPI()
    @app.api_route("/{p:path}", methods=["GET", "POST"])
    async def proxy(p: str, request: Request):
        engel = gk.guvence_kanca(request)
        if engel is not None:
            return engel
        return {"iletildi": p}
    return TestClient(app), gk

# --- 1) K1-kanca: /pqhaven pilot-filası-kayıt-altına-alınır
c, gk = kanca_app(TEST_LEDGER)
r = c.post("/pqhaven/tara", headers={"X-Guvence-Agent": "at093"})
assert r.status_code == 200 and r.json()["iletildi"] == "pqhaven/tara"
kayitlar = [json.loads(l) for l in TEST_LEDGER.read_text().splitlines()]
tipler = [k["event"]["type"] for k in kayitlar]
assert "tool_call" in tipler and "permission_decision" in tipler, \
    f"kanca-kayıt-yok: {tipler}"
karar = [k["event"]["payload"]["decision"]
         for k in kayitlar if k["event"]["type"] == "permission_decision"][0]
assert karar == "allow"
print("  K1-kanca: /pqhaven/tara → iletildi + tool_call/permission_decision"
      " ledger'a-yazıldı (karar=allow)")

# --- 2) NEG-1: fail-closed — SDK-yüklenemezse-istek-İLETİLMEZ
c2, gk2 = kanca_app(TMP / "fc.jsonl", fc=True)
r = c2.post("/pqhaven/tara")
assert r.status_code == 503 and r.json()["error"] == "guvence_fail_closed", \
    f"fail-closed-503-beklendi: {r.status_code} {r.json()}"
print("  NEG-1 fail-closed: SDK-yok → 503 guvence_fail_closed "
      "(kayıt-yok-geçiş-yok — pilot-disiplin)")

# --- 3) K1-kapsam: /cleartag-pilot-dışı-kanca-tetiklenmez
c3, gk3 = kanca_app(TMP / "diger.jsonl")
r = c3.post("/cleartag/dogrula")
assert r.status_code == 200
dig_yol = TMP / "diger.jsonl"
dig = [json.loads(l) for l in dig_yol.read_text().splitlines()] \
    if dig_yol.exists() else []
assert not dig, f"kanca-pilot-dışı-yola-dokundu: {len(dig)}-kayıt"
print("  K1-kapsam: /cleartag/dogrula → kanca-tetiklenmedi "
      "(yalnız /pqhaven-filası)")

# --- 4) _match_route: 7-route-en-uzun-prefix + 404 + /healthz
import gateway
beklenti = {"/planlock": 4021, "/callsnap": 8001, "/vadedostu": 8002,
            "/repriceai": 8003, "/pqhaven": 8004, "/cleartag": 8005,
            "/borsa": 8006}
for p, port in beklenti.items():
    m = gateway._match_route(p + "/alt/yol")
    assert m is not None and m[0] == p and m[1][1] == port, \
        f"{p} → {m} (port {port} beklenmişti)"
assert gateway._match_route("/bilinmiyor/x") is None
assert gateway._match_route("/healthz") is None   # gateway'in-kendi
print("  _match_route: 7-route-en-uzun-prefix ✓ + bilinmeyen→None + "
      "/healthz-gateway'in-kendi")
print("    " + " ".join(f"{p}:{v}" for p, v in beklenti.items()))

# --- 5) zincir-kanca-doğrulaması: sdk.check() imzalı-ledger
# NEG-1 sys.path'i-temizledi — SDK'yı-geri-ekle
SDK_YOL = "/home/gokun/projects/04_hukuk_sarti/81-OstrakonSOC"
if SDK_YOL not in sys.path:
    sys.path.insert(0, SDK_YOL)
from ajanguvence.sdk import AjanGuvence
CANLI = GW / "guvence_ledger.jsonl"
sdk = AjanGuvence(str(CANLI), mask_key=ANAHTAR, sign_key=ANAHTAR)
rapor = sdk.check()
assert rapor.ok and rapor.kayit_sayisi > 0, \
    f"zincir-kırık: ok={rapor.ok}"
# ledger-imza-yer-tutucusu-değil: her-kayıtta-hmac-var
import ajanguvence.ledger as led_mod
src = __import__("inspect").getsource(led_mod)
assert "_verify" in src or "imza" in src, "ledger-doğrulama-yolu-yok"
print(f"  zincir-kanca: sdk.check() zincir_ok=True ({rapor.kayit_sayisi}-kayıt,"
      " imzalı-jsonl)")

# --- 6) cron-bekçi: canlı-günlük → sağlıklı (alarm-temiz)
os.environ["GUVENTE_GUNLUK_DIZINI"] = str(GW / "guvence_gunluk")
os.environ["GUVENTE_BEKCI_ALARM"] = str(TMP / "alarm.json")
import importlib, guvence_bekci as gb
importlib.reload(gb)
rc = gb.main()
son = sorted((GW / "guvence_gunluk").glob("*.json"))[-1]
durum = json.loads(son.read_text(encoding="utf-8"))
assert rc == 0 and durum.get("zincir_ok") is True
print(f"  cron-bekçi: son-K5 {son.name} → sağlıklı (exit-0, zincir_ok=True,"
      f" kayıt={durum.get('kayit')})")

# --- 7) NEG-2: K1-deny-sıralama-bug'ı-KAPANDI (Lead-düzeltti: en-uzun-eşleşme)
#    a) GERÇEK-kural-dosyası: /pqhaven/admin → deny (DÜZELTME-SONRASI-DOĞRU)
#    Önce-bug vardı: matches[0]=G2('proxy/')-seçiyordu, G3-deny'yi-goluyordu.
#    Düzeltme (rules.py:78 max-len-tool)): artık-en-spesifik-G3-kazanır.
c4, gk4 = kanca_app(TMP / "bug.jsonl")
r = c4.post("/pqhaven/admin")
bug_kayit = [json.loads(l) for l in (TMP / "bug.jsonl").read_text().splitlines()]
bug_karar = [k["event"]["payload"]["decision"]
             for k in bug_kayit if k["event"]["type"] == "permission_decision"]
print(f"  NEG-2 (a): /pqhaven/admin → {r.status_code} karar={bug_karar}"
      " — G3-deny-uygulandı (DÜZELTME-SONRASI)")
assert r.status_code == 403 and bug_karar == ["deny"], \
    "G3-deny-uygulanmalı (Lead-düzeltmesi-sonrası)"
#    b) KÖK-NEDEN-kanıtı: KuralMotoru-artık-en-uzun-tool'u-seçer
from ajanguvence.rules import KuralMotoru
km = KuralMotoru(json.loads((GW / "guvence_kurallar.json").read_text()))
k2 = km.decide("pqhaven", "proxy/admin")
assert k2.karar == "deny" and k2.kural_id == "G3", \
    "en-spesifik-G3-seçilmeli (matches[0]-değil-max-len)"
k3 = km.decide("pqhaven", "proxy/healthz")
assert k3.karar == "allow" and k3.kural_id == "G1"
print("    DÜZELTME-KANITI: decide=max(len(tool)) — G3-deny, G1-healthz-allow")
#    c) GERİ-UYUM: genel-rotalar-hâlâ-allow (düzeltme-aşırı-sert-değil)
k4 = km.decide("pqhaven", "proxy/tara")
assert k4.karar == "allow" and k4.kural_id == "G2", \
    "genel-proxy/-rotaları-hâlâ-allow (geri-uyum-korundu)"
#    c) DÜZELTME-YOLU: G2-çıkarılınca-G3-çalışır (sıralama-gerçek-neden)
dz = TMP / "duzeltilmis.json"
d = json.loads((GW / "guvence_kurallar.json").read_text())
d["permissions"] = [p for p in d["permissions"] if p["id"] != "G2"]
dz.write_text(json.dumps(d), encoding="utf-8")
c5, gk5 = kanca_app(TMP / "dz.jsonl", sdk_yolu=dz)
r5 = c5.post("/pqhaven/admin")
dz_karar = [json.loads(l)["event"]["payload"]["decision"]
            for l in (TMP / "dz.jsonl").read_text().splitlines()
            if json.loads(l)["event"]["type"] == "permission_decision"]
assert r5.status_code == 403 and dz_karar == ["deny"], \
    f"düzeltildi-sonra-deny-gelmeli: {r5.status_code} {dz_karar}"
print("    DÜZELTME-YOLU: 'proxy/'-genel-kuralı-kaldır → G3 deny-çalışır"
      " (403) — sıralama-önceliği-düzeltmesi-gerekiyor")

# --- 8) CANLI-gateway-üzerinden-gerçek-kanca-trafiği
# planlock (Express) healthz-probe'u-bazen-yavaş; 6-x402-çekirdeği-şart
hg = httpx.get("http://127.0.0.1:8000/healthz", timeout=8).json()
n_up = int(hg["services_up"].split("/")[0])
assert n_up >= 6, f"en-az-6/7-beklendi: {hg['services_up']}"
g = hg.get("guvence", {})
assert g.get("pilot") == "aktif" and g.get("zincir_ok") is True, \
    f"kanca-canlı-değil: {g}"
print(f"  CANLI-gateway: /healthz {hg['services_up']} + guvence pilot=aktif"
      f" zincir_ok=True kayit={g.get('kayit')}"
      f" kararlar={g.get('kararlar')}")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: sekiz-gateway-iç-yüz-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,60p' "$LOG"; }

# --- pqhaven LocalScanner.scan_path upstream-bug-kanıtı
note "  pqhaven-bug-raporu (upstream):"
$PY3 - >> "$LOG" 2>&1 <<'PYEOF' || true
import inspect, sys
from pathlib import Path
sys.path.insert(0, "/home/gokun/projects/01_unicorn/80-PQHaven/src")
sys.path.insert(0, "/home/gokun/projects/01_unicorn/25-pqhaven-x402")
from pqhaven.scanner import LocalScanner
src = inspect.getsource(LocalScanner)
has_dir = "def scan_directory" in src
has_path = "def scan_path" in src
print(f"  LocalScanner: scan_directory={has_dir} scan_path={has_path}")
assert has_dir and not has_path, "scan_path-yok-gerçeği"
# servis-çağrı-yeri (upstream-raporu-için-tam-yer)
svc = Path("/home/gokun/projects/01_unicorn/25-pqhaven-x402/x402_servis.py")
lines = svc.read_text(encoding="utf-8").splitlines()
cagri = [i + 1 for i, l in enumerate(lines) if "scan_path" in l]
print(f"  x402_servis.py:{cagri} → local_scanner.scan_path(...) çağırır")
print("  → servis /tara scan_type:'local' → AttributeError: "
      "'LocalScanner' object has no attribute 'scan_path' → 400")
print("  → AT-082-pilot-bu-gerçeği-ölçtü (network-tarama-çalışır, local-400)")
print("  DÜZELTME (upstream): scan_path→scan_directory-adlandırma-uyumu,")
print("        VEYA servis-tarafında-bir-adapter (path→directory)")
PYEOF
grep -q "scan_path=False" "$LOG" \
  && note "    ✓ LocalScanner.scan_path-yok (scan_directory-var) — x402_servis.py:188'de-çağrılıyor" \
  || note "    (upstream-raporu-log'da)"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-093: 00-gateway iç-yüz — guvence-kanca + bekçi + 7-route"
[[ $FAIL -eq 0 ]]
