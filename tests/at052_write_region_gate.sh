#!/usr/bin/env bash
# AT-052: YAZIM-BÖLGESİ-GEÇİTLİ — Sester'ın-2026-09-20-mimari-cevabının-uygulaması.
#
# SESTER'IN-AYNI-SINIF-BİZDE-VAR-MI-sorusunun-yanıtı: EVET-VAR.
# Onlar-Ledger.insert_event/PgLedger.insert_event'i-buldular (hash'leriyle-aynen
# satır-kopyalayan-ikinci-deyim); bizde-tam-aynı-sınıf-tamga_netproxy.py:_log()
# idi — _ledger_append'i-atlayıp-O_APPEND-ile-yazan, "op"-değil-"event"-taşıyan,
# hash-zinciri-olmayan-ikinci-yazım-deyimi.
#
# DÜRÜST-SINIR: bu-bir-Tamga-ledger'ı-DEĞİLDİR (seq/prev/h-yok). Ama-ders-aynı:
# ad-sabitlemeli-tarayıcı-kaçınılmaz (_append-tetikleyicisiyle-sabırlı), o-yüzden
# garantiyi-"tarayıcı-her-deyimi-adlandırıyor"-yerine-"her-yazım-bölgesi-geçitli"
# olarak-yeniden-çapalandık (Sester'ın-test_213'-ünün-bizdeki-karşılığı).
#
# ÜÇLÜ-KAPSAMIN-YENİ-YORUMU (Sester'ın-4.tur-dersi):
#  (1) runtime-fail-closed      — _ledger_append-yazım-sınırı
#  (2) statik-tarayıcı          — _append-tetikleyicisi (ad-sabitli-KAÇINILMAZ)
#  (3) bölge-kapsamlı-tarama    — deyim-adına-bakmadan-OW_APPEND/fdopen-"a"-bular
#      + runtime-geçit-her-bölgede (netproxy-artık-KNOWN_NET_EVENTS-ile-geçitli)
#  **(2)-yalnızca-(3)-ile-birlikte-eksiksiz** — ad-sabit-zayıflık-yapısal-kapsamla
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
LOG=".evidence/AT-052/$D/at052.log"
mkdir -p ".evidence/AT-052/$D"
: > "$LOG"

note "AT-052: yazım-bölgesi-geçitli (Sester'ın-mimari-cevabının-uygulaması)"

# 1) İKİNCİ-YAZIM-DEYİMİ-GERÇEK: _log()-geçitli-ve-bilinmeyeni-reddetmeli
note "1) netproxy-geçidi — bilinmeyen-event-yazılmıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, tempfile, pathlib
sys.path.insert(0, ".")
import tamga_netproxy as N
d = tempfile.mkdtemp(); ev = pathlib.Path(d) / "events.jsonl"
class P:
    events_path = str(ev)
    _lock = __import__("threading").Lock()
    _events = []
# geçitli-bilinen-event → yazılmalı
N.TamgaProxy._log(P(), {"event": "net_denied", "host": "h"})
lines = ev.read_text().splitlines() if ev.exists() else []
assert len(lines) == 1, f"bilinen-event-yazılmadı: {lines}"
import json as _j
assert _j.loads(lines[0])["event"] == "net_denied"
# bilinmeyen-event → HİÇ-yazılmamalı (fail-closed)
N.TamgaProxy._log(P(), {"event": "sneaky_write", "host": "h"})
assert len(ev.read_text().splitlines()) == 1, "bilinmeyen-event-yazıldı!"
print("  bilinen-yazıldı, sneaky_write-reddedildi (1-satır-kaldı)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 1) netproxy-fail-closed"
else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) BÖLGE-KAPSAMLI-TARAMA — _append-adına-bağlı-kalmadan-tüm-bölgeler
note "2) bölge-kapsamlı-tarama — ad-sabitli-tarayıcıdan-bağımsız"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, pathlib, re
PROD = ("tamga_runner.py", "tamga_netproxy.py", "tamga_bundle.py", "tamga.py",
        "tamga_keccak.py", "tamga_liveness.py", "tamga_net_shim.py")
regions = []
for p in sorted(pathlib.Path(".").glob("*.py")):
    if p.name not in PROD:
        continue
    for i, l in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        # AT-053: truncate("w")-yazım-bölgeleri-de-dahil (restore-kurulumu)
        if re.search(r'(O_APPEND|O_TRUNC|fdopen\([^)]*"[wa]"|open\([^,]+,\s*"[wa]")', l):
            regions.append((p.name, i))
# üretimde-en-az-2-bölge-olmalı (runner + netproxy)
assert len(regions) >= 3, f"yazım-bölgesi-3'den-az: {regions}"
# netproxy-bölgesi-artık-geçitli
src = pathlib.Path("tamga_netproxy.py").read_text(encoding="utf-8")
assert "KNOWN_NET_EVENTS" in src, "netproxy-geçidi-yok"
assert "return   # fail-closed" in src, "fail-closed-yok"
print(f"  {len(regions)}-yazım-bölgesi-tanıldı, netproxy-geçitli")
for n, i in regions:
    print(f"    {n}:{i}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 2) bölge-kapsamlı-3-bölge"
else FAIL=$((FAIL+1)); note "  FAIL 2)"; cat "$LOG"; fi

# 3) AD-SABİT-TARAYICI-İLE-KARŞILAŞTIRMA — netproxy-_append-tarayıcısında-görünmüyor
note "3) ad-sabit-tarayıcı-netproxy'yi-göremiyor (kaçınılmazlık-kanıtı)"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
import emitter_verify as EV
em = EV._code_emitters()
# netproxy'nin-event-türleri-emitör-setinde-OLMAMALI (farklı-deyim, farklı-alan)
assert "net_denied" not in em and "net_connect" not in em, \\
    "ad-sabit-tarayıcı-netproxy'yi-gördü (beklenmeyen)"
print(f"  ad-sabit-tarayıcı: {sorted(em)}")
print("  net_*-türleri-görünmüyor → ad-sabit-kaçınılmaz, bölge-kapsamı-şart")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 3) ad-sabit-kaçınılmazlık-kanıtı"
else FAIL=$((FAIL+1)); note "  FAIL 3)"; cat "$LOG"; fi

# 4) TÜM-ÜRETİM-EVENT-TÜRLERİ-KAYITLI
note "4) üretilen-her-tür-KNOWN_NET_EVENTS-içinde"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, re, pathlib
sys.path.insert(0, ".")
import tamga_netproxy as N
src = pathlib.Path("tamga_netproxy.py").read_text(encoding="utf-8")
produced = set(re.findall(r'"event":\s*"(net_[^"]+)"', src))
unknown = produced - N.KNOWN_NET_EVENTS
assert not unknown, f"üretilen-ama-kayıtsız-türler: {sorted(unknown)}"
print(f"  üretilen: {sorted(produced)} — hepsi-kayıtlı")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 4) tüm-türler-kayıtlı"
else FAIL=$((FAIL+1)); note "  FAIL 4)"; cat "$LOG"; fi

# 5) ELLE-TUTULAN-LİSTE-KİRLENMESİ — proxy_start-dersi
note "5) elle-tutulan-tür-listesi-gerçek-üretim-event'ini-kaçırır (düzeltildi)"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, re, pathlib
sys.path.insert(0, ".")
import tamga_netproxy as N
# _log-çağrılarından-çıkarılan-türler
src = pathlib.Path("tamga_netproxy.py").read_text(encoding="utf-8")
log_types = set(re.findall(r'"event":\s*"(net_[^"]+)"', src))
# runner-cross-call: tamga_runner.py-içindeki-_log-çağrıları
runner = pathlib.Path("tamga_runner.py").read_text(encoding="utf-8")
cross = set(re.findall(r'_log\(\s*\{?"event":\s*"([^"]+)"', runner))
all_produced = log_types | cross
unknown = all_produced - N.KNOWN_NET_EVENTS
assert not unknown, f"üretilen-ama-KNOWN'da-yok: {sorted(unknown)}"
assert "proxy_start" in N.KNOWN_NET_EVENTS, "proxy_start-eksik (AT-006-kırılması)"
print(f"  üretilen-tüm-türler: {sorted(all_produced)}")
print(f"  KNOWN: {sorted(N.KNOWN_NET_EVENTS)} — hepsi-kapsanıyor")
print("  DERS: ilk-liste-yalnız-_log()-içindekileri-gördü; runner-cross-call'")
print("        kaçmıştı-ve-AT-006-kırıldı. Elle-liste-kirlenme-riski-GERÇEK.")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 5) tüm-üretim-türleri-kapsanıyor"
else FAIL=$((FAIL+1)); note "  FAIL 5)"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-052: ikinci-yazım-deyimi-kapatıldı (bölge-geçitli)"
[[ $FAIL -eq 0 ]]
