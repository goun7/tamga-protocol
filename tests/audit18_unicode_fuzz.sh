#!/usr/bin/env bash
# Audit-18 — ünikod-normalizasyon + homoglif hash-ayrıştırma (RFC-003 hash-temeli)
# Beklenen: NFC≠NFD-bayt→farklı-hash (kimlik-ayrıştırma-çalışır); homoglif-karakterler-
# farklı-hash. Suite-canonically-incompatible-girdi-kabul-ETMEZ-ama-bayt-eşdeğeri-girdiyi-
# ayrıştırmak-ZATEN-hash'in-işi. Yeni-kısıt-YOK — davranış-kanıtlanıyor.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AUDIT-18/$(date +%F)}/audit18.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

python3 - > "$LOG.1" 2>&1 <<'PYEOF'
import hashlib, json, sys, unicodedata
sys.path.insert(0, ".")
from tamga_validator import jcs

def h(pkg):
    return hashlib.sha256(("0" * 64).encode() + jcs({"pkg": pkg})).hexdigest()

nfc = unicodedata.normalize("NFC", "café")
nfd = unicodedata.normalize("NFD", "café")
a1 = h(nfc); a2 = h(nfd)
assert a1 != a2, "NFC/NFD-farklı-bayt-hash-ayrışmalı"
print(f"NFC/NFD ayrışıyor: {a1[:12]} != {a2[:12]}")

a3 = h("cafe"); a4 = h("саfe")  # Cyrillic-а
assert a3 != a4, "homoglif-ayrışmalı"
print(f"homoglif ayrışıyor: {a3[:12]} != {a4[:12]}")

# aynı-bayt-girdi-tam-eş-hash-(determinizm):
assert h("café") == h("café")
print("determinizm: aynı-bayt → aynı-hash")

# null-byte ve kontrol-karakterler:
a5 = h("a\x00b"); a6 = h("ab")
assert a5 != a6
print("null-bayt ayırışıyor")
print("OK")
PYEOF
ok $? "ünikod-matrisi: NFC/NFD+homoglif+null-farklı-hash (kimlik-ayrışması-kanıtı)"

python3 - > "$LOG.2" 2>&1 <<'PYEOF'
# JCS-sayı-serialization 2026-09-17'DE-DÜZELTİLDİ (Dümen#4 stillmarcus24-bulgusu):
# önceden json.dumps = Python-özel (yalnızca-Python-yeniden-üretebilirdi) — artık RFC-8785-birebir.
import sys; sys.path.insert(0, ".")
from tamga_validator import jcs
r1 = jcs({"a": -0.0}).decode()
r2 = jcs({"a": 1e-7}).decode()
r3 = jcs({"a": 1.0, "b": 1e16}).decode()
# RFC-8785 (ECMAScript-number): -0.0→"0", 1e-7→"1e-7", 1.0→"1", 1e16→"10000000000000000"
assert r1 == '{"a":0}' and r2 == '{"a":1e-7}' and r3 == '{"a":1,"b":10000000000000000}', (r1, r2, r3)
print("JCS-sayı-serialization RFC-8785-birebir (ES6: -0.0→0, 1e-7→1e-7, 1.0→1, 1e16→10000000000000000; eski-Python-sapması-KAPANDI)")
PYEOF
ok $? "JCS-sayı-serialization: RFC-8785-birebir (geri-dönüş-regresyon-kapısı: json.dumps'a-düşerse-RED)"

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
