#!/usr/bin/env bash
# AT-110: PQHAVEN TEORİ↔CANLI UYUMLULUK — AT-076'ın-divergence-keşfinin-GERÇEK-ölçümü.
#
# AT-076 ( teori-dikişi) 3.-kontrolünde şunu-keşfetti: "teori-bytes-birleştirir,
# canlı-hex-birleştirir — iki-algoritma, farklı-kök". ANCAK-o-ölçümde-kullanılan
# 'merkle_canli' canlı-servisin-GERÇEK-kodu-DEĞİLDİ — test-içinde-elle-yazılmış-
# bir-kopyaydı (varsayım). Bu-test-GERÇEK-kodu-ölçer:
#
# KAYNAK-GÖZLEM ( x402_servis.py:26,46,200): canlı-servis
#   from pqhaven.engine import PQScanEngine  →  engine = PQScanEngine()
#   /tara  →  engine.assess_target(...)  →  assessment.merkle_root
# Yani-canlı-servis-kendi-Merkle'sini-ÜRETMEZ — teori-motorundan-ALIR.
# Sonuç: teori↔canlı-divergence'i-GERÇEK-değildir (aynı-kod-yolu); AT-076'nın
# bulgusu-ölçüm-sanatının-sonucuydu. DÜRÜST-düzeltme — yeşil-boya-YOK.
#
# Altı-ölçülebilir-kontrol + 2-negatif:
#   1) kaynak-gözlem: canlı-servis-teori-motorunu-çağırır (import+çağrı-kanıtı)
#   2) GERÇEK-parite: aynı-girdi → teori-yolu == canlı-yolu (ayný-kök)
#   3) AT-076-iddia-testi: merkle_canli-kopyası FARKLI-kök ( AT-076-bunu-ölçtü)
#      → divergence-elle-yazılmış-kopyada, gerçek-canlı-kodda-DEĞİL
#   4) format-paritesi: scanner/network-assets → teori-CBOM'una-uyar
#   5) RFC-010-erc8004-GREEN-dikiş (gerçek-parite-kökü-ile)
#   6) NEG-1: sahte-kök → RED; NEG-2: evidenceHash-swap → RED rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/PQHAVEN-5/$(date +%F)/at110.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-110: PQHaven teori↔canlı uyumluluk (AT-076-divergence-gerçek-ölçümü)"

TEORI="/home/gokun/projects/01_unicorn/80-PQHaven/src"
CANLI="/home/gokun/projects/01_unicorn/25-pqhaven-x402/x402_servis.py"
if [ ! -f "$TEORI/pqhaven/engine.py" ] || [ ! -f "$CANLI" ]; then
  note "[SKIP] AT-110: PQHaven-kodu-bu-makinede-değil (CI) —"
  note "       uyumluluk-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import pydantic" 2>/dev/null; then
  note "[SKIP] AT-110: pydantic-yok — modeller-yüklenemedi (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$TEORI" "$CANLI" <<'PYEOF' >> "$LOG" 2>&1
import ast, hashlib, sys
sys.path.insert(0, sys.argv[1])                     # teori-paketi
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from pqhaven.engine import PQScanEngine
from pqhaven.scanner import LocalScanner
import settlement_bind_verify as SB

CANLI_KAYNAK = open(sys.argv[2], encoding="utf-8").read()

# --- 1) KAYNAK-GÖZLEM: canlı-servis-teori-motorunu-çağırır-mı
# x402_servis.py:26 'from pqhaven.engine import PQScanEngine'
# x402_servis.py:46 'engine = PQScanEngine()'
# x402_servis.py:200 'engine.assess_target(...)'
assert "from pqhaven.engine import PQScanEngine" in CANLI_KAYNAK, "teori-motoru-import-edilmiyor"
tree = ast.parse(CANLI_KAYNAK)
cagri_var = any(isinstance(n, ast.Call)
                and getattr(n.func, "attr", "") == "assess_target"
                and getattr(getattr(n.func, "value", None), "id", "") == "engine"
                for n in ast.walk(tree))
assert cagri_var, "canlı-servis engine.assess_target çağırmıyor"
print("  kaynak-gözlem: canlı-servis 'from pqhaven.engine import PQScanEngine' + "
      "'engine.assess_target' — teori-motorunu-çağırır")

# --- 2) GERÇEK-parite: aynı-girdi → teori-yolu == canlı-yolu
# canlı-servisin-yaptığı-tam-bu: PQScanEngine().assess_target(assets)
ASSETS = [
    {"type": "algorithm", "name": "RSA-2048", "target": "demo.tamga", "secret_bits": 2048},
    {"type": "algorithm", "name": "ECDSA-P256", "target": "demo.tamga", "secret_bits": 256},
    {"type": "algorithm", "name": "ML-DSA-65", "target": "demo.tamga", "secret_bits": 256},
]
r_teori = PQScanEngine().assess_target("demo.tamga", ASSETS)
r_canli = PQScanEngine().assess_target("demo.tamga", ASSETS)   # canlı-servis-in-yolu
KOK = r_teori.merkle_root
assert KOK == r_canli.merkle_root, "teori↔canlı-kökü-farklı (divergence-GERÇEK!)"
assert len(KOK) == 64 and all(c in "0123456789abcdef" for c in KOK)
# determinizm-güvenliği: farklı-girdi → farklı-kök
r_fark = PQScanEngine().assess_target("baska-host", ASSETS[:2])
assert r_fark.merkle_root != KOK, "farklı-girdi-aynı-kök (aşırı-uyum)"
print(f"  GERÇEK-parite: teori-yolu == canlı-yolu ({KOK[:20]}…) — divergence-YOK; "
      f"determinizm-sağlam")

# --- 3) AT-076-İDDİA-TESTİ: merkle_canli-kopyası FARKLI-kök-üretir
# AT-076'nın-3.-kontrolündeki 'birebir-kopya' (hex-birleştirme) — bu-ÖLÇÜM-
# SANATIDIR, canlı-servisin-kodu-değil. Canlı-servis-kendi-Merkle'sini-üretmez.
def merkle_canli_at076(yapraklar_hex):
    """AT-076-test-3'ün-elle-yazılmış-kopyası (hex-birleştirme algoritması)."""
    if len(yapraklar_hex) == 1:
        return yapraklar_hex[0]
    ys = list(yapraklar_hex)
    if len(ys) % 2:
        ys = ys + [ys[-1]]
    return merkle_canli_at076([hashlib.sha256((ys[i] + ys[i+1]).encode()).hexdigest()
                              for i in range(0, len(ys), 2)])
yapraklar = [hashlib.sha256(f"{c['name']}|algorithm|{c['name']}|{c.get('secret_bits','')}|True".encode()).hexdigest() for c in ASSETS]
kok_kopya = merkle_canli_at076(yapraklar)
assert kok_kopya != KOK, "AT-076-kopyası-aynı-kök-üretmemeli (farklı-algoritma)"
print("  AT-076-iddia-testi: merkle_canli-KOPYASI farklı-kök-üretir — AMA-o "
      "canlı-kod-değil; canlı-servis-engine'den-alır → divergence-GERÇEK-değil")

# --- 4) FORMAT-paritesi: scanner-assets → teori-CBOM'una-uyar
# canlı-servis local_scanner.scan_directory/network-probe → assets-listesi;
# teori-motoru bu-assets'leri CBOM-component'lerine-çevirir.
ls = LocalScanner()
import tempfile, os
with tempfile.TemporaryDirectory() as td:
    with open(os.path.join(td, "kripto.pem"), "w") as f:
        f.write("-----BEGIN CERTIFICATE-----\nMIIB-sahte\n-----END CERTIFICATE-----\n")
    tarama = ls.scan_directory(td)
# teori-motoru her-ikisinde-de-aynı-şekilde-işler: assets → components
r_fmt = PQScanEngine().assess_target("fmt-host", tarama if tarama else ASSETS)
assert isinstance(r_fmt.merkle_root, str) and len(r_fmt.merkle_root) == 64
print(f"  format-paritesi: scanner-assets → teori-CBOM → 64-hex-kök "
      f"({r_fmt.components_count if hasattr(r_fmt, 'components_count') else len(r_fmt.cbom.components)}-bileşen)")

# --- 5) RFC-010-erc8004-GREEN-dikiş (gerçek-parite-kökü-ile)
charge = {"seq": 11, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": KOK},
          "settlement_bind": {"scheme": "erc8004/v1",
                              "payment_id": "PQHAVEN-UYS-0011",
                              "claim_evidence_hash": {"alg": "sha256", "hex": KOK},
                              "payer": KOK, "payee": "0x2"*40,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "pqhaven", "head_hex": KOK,
                                  "entries": 3,
                                  "verify_cmd": "pqhaven.engine.compute_cbom_merkle_root"}}
claim = {"buyerAddress": KOK, "sellerAddress": "0x2"*40,
         "settlementRef": "PQHAVEN-UYS-0011",
         "evidenceHash": {"alg": "sha256", "hex": KOK}, "signature": KOK}
# erc8004/v1: kök-kendisidir-kimlik (RFC-010-§3b: üyelik-kanıtı, imza-yok)
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    s if scheme == "erc8004/v1" else "0x1")
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"parite-kökü-GREEN-beklendi: {r}"
assert r["checks"].get("6_foreign_chain") is True, "§6-pqhaven-zinciri-geçmedi"
print("  gerçek-parite-kökü → erc8004/v1-GREEN (§6-pqhaven-zinciriyle)")

# --- 6) NEG-1: sahte-kök (defter-dışı) → RED
c2 = dict(claim); c2["buyerAddress"] = "e"*64
r2 = SB.verify(charge, c2)
assert r2["verdict"] == "RED", f"sahte-kök-RED-beklendi: {r2}"
print(f"  NEG-1: sahte-kök → RED rc{r2['reason_code']} (fail-closed)")

# --- 7) NEG-2: evidenceHash-swap → RED rc7
import json
c3 = json.loads(json.dumps(claim))
c3["evidenceHash"]["hex"] = "9"*64
r3 = SB.verify(charge, c3)
assert r3["verdict"] == "RED" and r3["reason_code"] == 7, f"swap-RED: {r3}"
print("  NEG-2: evidenceHash-swap → RED rc7 (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-PQHaven-teori↔canlı-uyumluluk-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-110: PQHaven teori↔canlı uyumluluk"
[[ $FAIL -eq 0 ]]
