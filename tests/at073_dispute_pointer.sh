#!/usr/bin/env bash
# AT-073: RFC-011-DISPUTE-POINTER — anlaşmazlık-bacağı.
#
# holistis D-017 (x402#3379): "record_delivery yalnızca alıcı-imzalı iddia kabul
# eder; satıcı karşı-iddia mekanizması YOK — a dispute only ever shows one side,
# structurally. Signature proves who said it, never what actually happened;
# attribution, not truth."
#
# Pacta §5.3 aynı boşluğu doldurur: %20 itiraz teminatı + Schelling hakemliği.
# RFC-011 ikisini bağlar: Tamga HAKEM DEĞİL — çelişki ALGILAYICI + yönlendirici.
#
# ANA-İLKE: 6/6-GREEN "teslimat iyi oldu" DEMEZ; yalnızca "kimse itiraz etmedi"
# der. Çelişki İNDETERMİNE'dir — insan/hakem gerekir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-073/$(date +%F)/at073.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-073: RFC-011 dispute-pointer (anlaşmazlık-bacağı)"

python3 - <<'PYEOF' >> "$LOG" 2>&1
import json, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from dispute_pointer_verify import verify, MIN_BOND_PCT, SUPPORTED_PROTOCOLS
import settlement_bind_verify as SB

def base_charge(dp=None):
    c = {"seq": 1, "prev": "0"*64, "h": "a"*64,
         "delivery_hash": {"alg": "sha256", "hex": "c"*64},
         "settlement_bind": {"scheme": "tamga/native", "payment_id": "P1",
                             "claim_evidence_hash": {"alg": "sha256", "hex": "c"*64},
                             "payer": "agent-7", "payee": "0x2"*40,
                             "verified_at": "2026-09-21T00:00:00Z"}}
    if dp is not None:
        c["dispute_pointer"] = dp
    return c

# --- 1) GERİ-UYUMLULUK: dispute_pointer-yok → GREEN (RFC-010 ekleyen eski kayıtlar)
r = verify(base_charge(None))
assert r["verdict"] == "GREEN", f"yok-GREEN-beklendi: {r}"
print("  dispute_pointer-yok → GREEN (geri-uyumlu)")

# --- 2) status:none → GREEN (açık-çelişki-yok)
r2 = verify(base_charge({"status": "none"}))
assert r2["verdict"] == "GREEN", f"none-GREEN: {r2}"
print("  status:none → GREEN (itiraz-yok)")

# --- 3) status:resolved → GREEN (hakemlik-bitti)
r3 = verify(base_charge({"status": "resolved"}))
assert r3["verdict"] == "GREEN", f"resolved-GREEN: {r3}"
print("  status:resolved → GREEN (hakemlik-tamam)")

# --- 4) ÇELİŞKİ: alıcı delivered:no imzaladı + yönlendirme-sağlam → İNDETERMİNE
cc = {"buyer_signed": True, "delivered": False,
      "evidence_hash": {"alg": "sha256", "hex": "d"*64}}
arb = {"protocol": "pacta/v1", "case_ref": "PACTA-0001", "terms_hash": "e"*64}
r4 = verify(base_charge({"status": "contradiction", "counter_claim": cc,
                          "arbitration": arb, "bond_pct": 0.20}))
assert r4["verdict"] == "İNDETERMİNE" and r4["reason_code"] == 12, \
    f"çelişki-İNDETERMİNE-beklendi: {r4}"
print("  çelişki-+yönlendirme → İNDETERMİNE rc12 (insan/hakem-gerekir)")

# --- 5) NEGATİF: çelişki-var-ama-arbitration-YOK → RED rc9 (yönlendirme-kayıp)
bad = {"status": "contradiction", "counter_claim": cc, "bond_pct": 0.25}
r5 = verify(base_charge(bad))
assert r5["verdict"] == "RED" and r5["reason_code"] == 9, f"arb-yok-RED: {r5}"
print("  çelişki-+arbitration-yok → RED rc9 (yönlendirme-kaybolamaz)")

# --- 6) NEGATİF: bond <%20 (Pacta-§5.3-griefing) → RED rc10
r6 = verify(base_charge({"status": "contradiction", "counter_claim": cc,
                          "arbitration": arb, "bond_pct": 0.10}))
assert r6["verdict"] == "RED" and r6["reason_code"] == 10, f"düşük-bond-RED: {r6}"
print("  bond %10 < %20 → RED rc10 (griefing-önlenir)")

# --- 7) ÜÇÜNCÜ-SEÇENEK-YASAK: bilinmeyen-arbitration-protokolü → İNDETERMİNE
arb2 = dict(arb); arb2["protocol"] = "kadi/v99"
r7 = verify(base_charge({"status": "contradiction", "counter_claim": cc,
                          "arbitration": arb2, "bond_pct": 0.30}))
assert r7["verdict"] == "İNDETERMİNE" and r7["reason_code"] == 11, \
    f"bilinmeyen-protokol-İNDETERMİNE: {r7}"
print("  bilinmeyen-arbitration-protokolü → İNDETERMİNE (sessiz-RED-yok)")

# --- 8) ANA-İLKE-KANITI: 6/6-GREEN "iyi-teslimat"-değil
# RFC-010-GREEN-olan-aynı-kayıt-içinde-çelişki-bulunabilir:
SB._claim_signer = lambda d,s,scheme="x402/v1": "agent-7"
charge_full = base_charge({"status": "contradiction", "counter_claim": cc,
                            "arbitration": arb, "bond_pct": 0.25})
claim = {"buyerAddress":"agent-7","sellerAddress":"0x2"*40,"settlementRef":"P1",
         "evidenceHash":{"alg":"sha256","hex":"c"*64},"signature":"agent-7"}
r10 = SB.verify(charge_full, claim)
r11 = verify(charge_full)
assert r10["verdict"] == "GREEN" and r11["verdict"] == "İNDETERMİNE", \
    f"ana-ilke: RFC010={r10['verdict']} dispute={r11['verdict']}"
print("  ANA-İLKE: RFC-010-GREEN + dispute-İNDETERMİNE — GREEN 'iyi-teslimat' DEĞİL")

# --- 9) Pacta-§5.2-atfı-gerçek (önceden-var-bağ)
src = open("/home/gokun/projects/01_unicorn/03-Pacta/PROJE_KAGIDI.md",
           encoding="utf-8").read()
assert "TamgaVerifier.verify" in src and "TamgaReceipt" in src, \
    "Pacta-Tamga-atfı-yok"
print("  Pacta-§5.2-'TamgaVerifier.verify'+TamgaReceipt'-atfı-gerçek (önceden-var-bağ)")

# --- 10) MIN_BOND_PCT-ve-protokol-listesi-sabitleri
assert MIN_BOND_PCT == 0.20 and "pacta/v1" in SUPPORTED_PROTOCOLS
print("  sabitler: bond=%s protokoller=%s" % (MIN_BOND_PCT, SUPPORTED_PROTOCOLS))
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-RFC-011-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-073: RFC-011 dispute-pointer"
[[ $FAIL -eq 0 ]]
