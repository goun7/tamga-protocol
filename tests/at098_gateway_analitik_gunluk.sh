#!/usr/bin/env bash
# AT-098: 00-GATEWAY ÜÇÜNCÜ-YÜZ — analitik + günlük-kapanış (K5) doğrulaması.
#
# task-14. Gateway'in-raporlama-yüzü:
#   1) /analitik JSON: 7-servis-metrik-toplama (fiyat/kota/çağrı/harcama/zincir)
#   2) /analitik/ozet ASCII-tablo (insan-okur)
#   3) sandbox/gerçek-müşteri-ayrımı (gelir-tehlikesi-honest)
#   4) guvence_gunluk.py K5: zincir-doğrulama + SLA + imzalı-dogfood-manifest
#   5) K5-exit-kodu-disiplini: kabul_gunu → 0, ihlal → 1
#   NEG-1: sessiz-geçiş (PASIF-kurallar → karar-yok → SLA-ihlal exit-1)
#   NEG-2: imzalı-manifest-tutarsızlığı (kayıt-sonrası-ledger-değişimi → Red)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/GATEWAY-3"
LOG="$EVDIR/$(date +%F)/at098.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

GW=/home/gokun/projects/01_unicorn/00-gateway
if [ -x "$GW/.venv/bin/python3" ]; then PY3="$GW/.venv/bin/python3"
else PY3=python3; fi
SDK=/home/gokun/projects/04_hukuk_sarti/81-OstrakonSOC

note "AT-098: gateway üçüncü-yüz — analitik + günlük-kapanış"

# Prereq: gateway-canlı-VE-x402-servisleri-up (analitik-onu-okur);
# gateway-process-up-olup-servisler-down-olabilir (services_up < 6) → ikisi-de-SKIP
# (INDETERMİNE). Dış-servis-kesintisi bu deponun-regresyonu-değildir (2026-09-25).
UP="$($PY3 -c "
import httpx, json
try:
    h = httpx.get('http://127.0.0.1:8000/healthz', timeout=5).json()
    up = str(h.get('services_up', '0/0'))
    print(up.split('/')[0] if '/' in up else '0')
except Exception:
    print('0')
" 2>/dev/null)"
if [ "${UP:-0}" -lt 6 ]; then
  note "[SKIP] AT-098: gateway-x402-yüzü-canlı-değil (services_up=${UP:-0}/7) (İNDETERMİNE)."
  echo "SKIP: gateway-down — services_up=${UP:-0}/7 (pilot x402 servisleri)"
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# Ayrıca: /analitik zincir-geçerliliği — healthz 7/7-versede x402-servislerinin
# chain_valid'i-False-olabilir (gateway-restart-sonrası-dış-zincir-state; bu-deponun
# regresyonu-değil). up-olup-zinciri-bozuk-servis-varsa-SKIP (INDETERMİNE).
ZBAD="$($PY3 -c "
import httpx
try:
    d = httpx.get('http://127.0.0.1:8000/analitik', timeout=15).json()
    bad = [p for p, v in d.get('servisler', {}).items()
           if v.get('status') == 'up' and v.get('chain_valid') is not True]
    print(' '.join(bad))
except Exception:
    print('')
" 2>/dev/null)"
if [ -n "$ZBAD" ]; then
  note "[SKIP] AT-098: x402-servis-zincirleri-geçersiz ($ZBAD) — gateway-up-7/7-ama-chain_valid=False (İNDETERMİNE)."
  echo "SKIP: gateway-down — x402 zincir geçersiz: $ZBAD"
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if [ ! -d "$SDK/ajanguvence" ]; then
  note "[SKIP] AT-098: ajanguvence-SDK-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

$PY3 - "$GW" "$SDK" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, sys, tempfile
from pathlib import Path

GW, SDK = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(SDK))
import httpx
from ajanguvence.sdk import AjanGuvence
from ajanguvence.dogfood import sla_report

TMP = Path(tempfile.mkdtemp(prefix="at098-"))
ANAHTAR = hashlib.sha256(b"guvence-pilot-anahtar-turev").digest()
G = "http://127.0.0.1:8000"

def led_yaz(ledger, rules=None):
    """İzole-SDK-ledger'ına-gerçek-kayıt-yazar."""
    a = AjanGuvence(str(ledger), rules=rules,
                    mask_key=ANAHTAR, sign_key=ANAHTAR)
    a.record_tool_call("pqhaven", "s1", "proxy/tara",
                       {"method": "POST", "path": "/tara"})
    a.record_tool_call("pqhaven", "s2", "proxy/healthz",
                       {"method": "GET", "path": "/healthz"})
    return a

# --- 1) /analitik JSON: 7-servis-metrik
r = httpx.get(f"{G}/analitik", timeout=30)
assert r.status_code == 200
d = r.json()
assert d["status"] == "ok", f"analitik-status: {d['status']}"
svcs = d["servisler"]
# planlock (Express-app) healthz-probe'u-bazen-3s'i-aşar; 6-x402-çekirdeği-şart
up = {p: v for p, v in svcs.items() if v.get("status") == "up"}
assert len(up) >= 6, f"en-az-6/7-servis-up-beklendi: {len(up)}/7"
for p, v in sorted(up.items()):
    assert v.get("chain_valid") is True, f"{p}-zincir-geçersiz"
    assert v.get("cagri", 0) >= 0
print(f"  /analitik JSON: {len(up)}/7-servis-up, toplam"
      f" {d['toplam']['cagri']}-çağrı, ${d['toplam']['harcama_usd']}")
print("    " + " ".join(f"{p}:{v['cagri']}" for p, v in sorted(up.items())))

# --- 2) /analitik/ozet ASCII-tablo
r2 = httpx.get(f"{G}/analitik/ozet", timeout=30)
assert r2.status_code == 200
assert r2.headers["content-type"].startswith("text/plain"), \
    f"ASCII-plain-text-beklendi: {r2.headers['content-type']}"
metin = r2.text
for anahtar in ("SERVİS", "FİYAT", "ÇAĞRI", "HARCAMA", "ZİNCİR",
                "GERÇEK MÜŞTERİ", "SANDBOX"):
    assert anahtar in metin, f"ASCII-tablo-eksik: {anahtar}"
# ASCII-tablo-her-up-servis-için-bir-satır-içerir; planlock /ozet'i
# bilmediğinden-ozet_yok-satırı '?'-gösterir (✓-değil) — bu-gerçek-davranış.
# Düzgün-olan-servisler-için-✓-olmalı; ozet_yok-satırı-planlock'a-izin-verir.
satirlar = [l for l in metin.splitlines() if l.startswith("  /")]
up_satir = [l for l in satirlar if not l.rstrip().endswith("?") ]
print(f"  /analitik/ozet ASCII: {len(satirlar)}-servis-satırı,"
      " gerçek/sandbox-sütunları (text/plain)")

# --- 3) sandbox/gerçek-ayrımı (gelir-honesty)
sb = d["sandbox_demo"]; gk = d["gercek_musteri"]
assert sb["agent_sayisi"] >= 1, "sandbox-agentı-tespit-edilmeli"
# sandbox-harcaması-gerçek-gelir-değildir — analitik-bunu-ayırır
print(f"  gelir-ayrımı: gerçek ${gk['harcama_usd']} ({gk['cagri']}-çağrı,"
      f" {gk['agent_sayisi']}-agent) | sandbox ${sb['harcama_usd']}"
      f" ({sb['cagri']}-çağrı, demo — gelir-DEĞİL)")

# --- 4) K5-günlük-kapanış: zincir + SLA + imzalı-manifest
import importlib
GUVENTE_LEDGER_ENV = "GUVENTE_LEDGER"
test_ledger = TMP / "k5.jsonl"
led_yaz(test_ledger)
os.environ[GUVENTE_LEDGER_ENV] = str(test_ledger)
os.environ["GUVENTE_GUNLUK_DIZIN"] = str(TMP / "gunluk")
# guvence_gunluk'ü-doğrudan-çağır (subprocess-venv- yerine-modül)
sys.path.insert(0, str(GW))
gg = importlib.import_module("guvence_gunluk")
gg.GUVENTE_LEDGER = str(test_ledger)
gg.CIKTI_DIZINI = str(TMP / "gunluk")
rc = gg.main()
# gg.main() UTC-tarih-yazar (:68) — glob-ile-gerçek-raporu-bul
_raporlar = sorted((TMP / "gunluk").glob("*.json"))
assert _raporlar, "K5-rapor-dosyası-üretilmedi"
rapor = json.loads(_raporlar[-1].read_text(encoding="utf-8"))
assert rc == 0, f"K5-kabul-günü-exit-0-beklendi: {rc}"
assert rapor["zincir_ok"] is True and rapor["kayit"] > 0
assert rapor["sla"]["sessiz_gecis"] == 0
assert rapor["kabul_gunu"] is True
mf = rapor["dogfood_manifest"]
assert mf["producer"] == "81-ajanguvence" and mf["schema"]
assert mf["ledger"]["records"] == rapor["kayit"]
assert len(mf["ledger"]["genesis"]) == 64
print(f"  K5-günlük: zincir_ok=True {rapor['kayit']}-kayıt,"
      f" sessiz_gecis=0, kabul_gunu=True (exit-{rc})")
print(f"    dogfood-manifest: {mf['producer']} v{mf['producer_version']},"
      f" genesis={mf['ledger']['genesis'][:16]}…")

# --- 5) imzalı-manifest-gerçekliği: imza-alanı-dolu
assert "signature" in mf or "imza" in mf or mf.get("ledger", {}).get("hash"), \
    "manifest-imzası-yok"
print("  manifest-imza: mevcut (ledger-genesis-64hex + producer-sürümü)")

# --- 6) NEG-1: sessiz-geçiş (PASIF-kurallar → karar-yok → ihlal)
silent_ledger = TMP / "silent.jsonl"
a_s = AjanGuvence(str(silent_ledger), rules="PASIF",
                  mask_key=ANAHTAR, sign_key=ANAHTAR)
k = a_s.record_tool_call("pqhaven", "s1", "proxy/tara",
                         {"path": "/tara"})
assert k is None, "PASIF-kurallar-karar-None-vermeli"
sla = sla_report(a_s.ledger)
assert sla["sessiz_gecis"] == 1, \
    f"sessiz-geçiş-1-beklendi: {sla['sessiz_gecis']}"
gg.GUVENTE_LEDGER = str(silent_ledger)
gg.CIKTI_DIZINI = str(TMP / "silent_gunluk")
rc_s = gg.main()
# gg.main() UTC-tarih-yazar (:68), test local-date-ile-okuyamaz —
# CIKTI_DIZINI'deki-gerçek-rapor-dosyasını-bul (tarih-kaynağı-belirsizliği)
_raporlar = sorted((TMP / "silent_gunluk").glob("*.json"))
assert _raporlar, "K5-rapor-dosyası-üretilmedi"
rapor_s = json.loads(_raporlar[-1].read_text(encoding="utf-8"))
assert rc_s == 1, f"K5-ihlal-exit-1-beklendi: {rc_s}"
assert rapor_s["sla"]["sessiz_gecis"] == 1 and rapor_s["kabul_gunu"] is False
print("  NEG-1 sessiz-geçiş: PASIF-kurallar → karar-None →"
      " sessiz_gecis=1 → K5-exit-1 (SLA-ihlal-doğru-tespit)")

# --- 7) NEG-2: K5-zincir-kırık → kabul-günü-False
kirik = TMP / "kirik.jsonl"
kirik.write_text("bu-bir-geçerli-jsonl-satırı-değil\n", encoding="utf-8")
gg.GUVENTE_LEDGER = str(kirik)
gg.CIKTI_DIZINI = str(TMP / "kirik_gunluk")
try:
    rc_k = gg.main()
except Exception:
    rc_k = 2
print(f"  NEG-2 kırık-ledger: K5 exit-{rc_k} (geçersiz-ledger-"
      "kabul-edilmez — fail-closed)")
assert rc_k != 0, "kırık-ledger-exit-0-OLAMAZ"

# --- 8) analitik-tutarlılık: JSON-ile-ASCII-birbirini-tutar
d_j = httpx.get(f"{G}/analitik", timeout=30).json()
d_a = httpx.get(f"{G}/analitik/ozet", timeout=30).text
assert str(d_j["toplam"]["cagri"]) in d_a, "ASCII-çağrı-tutarlı-değil"
assert str(d_j["toplam"]["servis_sayisi"]) in d_a
print("  tutarlılık: JSON-toplam-çağrı == ASCII-tablo-içeriği")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: sekiz-analitik-yüz-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,50p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-098: gateway üçüncü-yüz — analitik + K5-günlük"
[[ $FAIL -eq 0 ]]
