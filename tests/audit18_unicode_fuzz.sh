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
# JCS-sayı-uyumsuzluğu-BELGELİ-durum-(dürüst-sınır; fix-v0.2-dilimi):
import sys; sys.path.insert(0, ".")
from tamga_validator import jcs
r1 = jcs({"a": -0.0}).decode()
r2 = jcs({"a": 1e-7}).decode()
# beklenen-(RFC-8785): '0' ve '1e-7'; biz-'-0.0'/'1e-07' — DOKÜMANTASYON-DİSİPLİNİ:
assert r1 == '{"a":-0.0}' and r2 == '{"a":1e-07}', (r1, r2)
print("JCS-'RFC-8785-subset'-sınırı-dokümantasyonla-doğrulandı (ES6-sapma:-0.0/1e-07)")
PYEOF
ok $? "JCS-subset-dürüst-sınırı: ES6-sapması-belgeli (fix-v0.2-kurucu-kapısı)"

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]
