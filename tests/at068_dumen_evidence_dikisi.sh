#!/usr/bin/env bash
# AT-068: DÜMEN-EVIDENCE-CHAIN → RFC-010-DİKİŞİ (B-sınıfı — bağlanMAMIŞ-kanıt-makinesi).
#
# 77-Dumen (103-py): dumen/reports/evidence_chain.py — SHA-256 prev_hash-zinciri
# (GENESIS=64-adet-'0'; bizim-D5-zincirinin-aynı-şekli), dumen/reports/cop_commitments.py
# — Code-of-Practice-commitment-matrisi.
#
# KEŞFEDİLEN-ÖNCEDEN-VAR-OLAN-BAĞ: Dümen'in-_hash_entry()'si-"rfc8785"-şeması-
# seçeneği-taşır-ve-YORUMUNDA-AÇIKÇA-"Tamga AT-036"-yazar. Yani-iki-proje-zaten
# KANONİKLEŞTİRME-düzeyinde-bağlı (21/21-vektör-doğrulandı). Bu-test-o-bağı
# ÖDEME-DİKİŞİ-düzeyine-taşır.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-068/$(date +%F)/at068.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-068: Dümen-evidence-chain → RFC-010 dikişi"

DU="/home/gokun/projects/01_unicorn/77-Dumen"
if [ ! -f "$DU/dumen/reports/evidence_chain.py" ]; then
  note "[SKIP] AT-068: Dümen-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$DU" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, sys, os
sys.path.insert(0, os.path.dirname(sys.argv[1]))   # dumen-paketi-üst-dizini
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from dumen.reports.evidence_chain import EvidenceChain
import settlement_bind_verify as SB

# --- 1) Dümen'in-gerçek-zinciri-üret (GENESIS=64-sıfır, bizim-aynı-şekil)
ec = EvidenceChain()
e1 = ec.append("madencilik", {"target":"dosya-1"," buluntu":3})
assert len(e1.prev_hash) == 64 and set(e1.prev_hash) == {"0"}, \
    f"GENESIS-64-sıfır-beklendi: {e1.prev_hash[:8]}"
assert len(e1.entry_hash) == 64
print(f"  Dümen-zinciri-üretildi: GENESIS-kök, entry_hash {e1.entry_hash[:16]}…")

# --- 2) KEŞFEDİLEN-BaĞI-KANITLA: rfc8785-şeması-Tamga'ya-atıf-yapar
src = open(os.path.join(sys.argv[1], "dumen/reports/evidence_chain.py"),
           encoding="utf-8").read()
assert "rfc8785" in src and "Tamga AT-036" in src, \
    "rfc8785/Tamga-AT-036-atfı-yok — bağ-kanıtlanmadı"
print("  KANITLANDI: Dümen-kodu-'Tamga AT-036'-atfı-taşır (önceden-var-bağ)")

# --- 3) DİKİŞ: Dümen-zincir-kökü → RFC-010-gate'ine
kok = ec.head_hash()
assert len(kok) == 64
charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": kok},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "AUDIT-0001",
                              "claim_evidence_hash": {"alg": "sha256", "hex": kok},
                              "payer": "dumen-auditor", "payee": "0x2222",
                              "verified_at": "2026-09-21T00:00:00Z"}}
claim = {"buyerAddress": "dumen-auditor", "sellerAddress": "0x2222",
         "settlementRef": "AUDIT-0001",
         "evidenceHash": {"alg": "sha256", "hex": kok}, "signature": "dumen-auditor"}
SB._claim_signer = lambda d, s, scheme="x402/v1": (
    s if scheme == "tamga/native" else "0x1")
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Dümen-dikişi-GREEN-beklendi: {r}"
print("  Dümen-zinciri → RFC-010-GREEN (üçüncü-B-sınıfı-bağlandı)")

# --- 4) NEGATİF: sahte-kök → RED
claim2 = json.loads(json.dumps(claim))
claim2["evidenceHash"]["hex"] = "e"*64
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, f"sahte-RED: {r2}"
print("  zincir-dışı-sahte-kök-RED")

# --- 5) NEGATİF: Dümen-zinciri-tampered-ise-head-hash-değişir → kanıt-RED
ec.append("degerlendirme", {"x":1})
kok2 = ec.head_hash()
assert kok2 != kok, "eklenen-kayıt-head'i-değiştirmedi (zincir-kırık)"
claim3 = json.loads(json.dumps(claim))
charge3 = json.loads(json.dumps(charge))
charge3["settlement_bind"]["claim_evidence_hash"]["hex"] = kok2
charge3["delivery_hash"]["hex"] = kok2
claim3 = json.loads(json.dumps(claim))
claim3["evidenceHash"]["hex"] = kok2            # claim-de-güncel-kökü-taşır
r3 = SB.verify(charge3, claim3)
assert r3["verdict"] == "GREEN", f"güncel-kök-GREEN-beklendi: {r3}"  # güncel-kök-geçer
# eski-charge'in-kökü-artık-geçerli-değil: claim'in-evidenceHash'ı
# yeni-kökte-ama-charge'ın-delivery_hash'ı-eski-kökte → 5.kontrol-RED
claim_old = json.loads(json.dumps(claim3))
claim_old["evidenceHash"]["hex"] = kok   # claim-eski-kökü-söylüyor
charge_old = json.loads(json.dumps(charge3))
charge_old["delivery_hash"]["hex"] = kok2  # charge-gerçek( yeni)-kökü-taşır
r4 = SB.verify(charge_old, claim_old)
assert r4["verdict"] == "RED", f"eski-kök-vs-gerçek-kök-RED-beklendi: {r4}"
print("  eski-kök-vs-gerçek-kök-RED (append-only-zincir-gerçek)")

# --- 6) İKİ-ZİNCİRİN-GENESIS-kökleri-aynı: 64-sıfır
gp = EvidenceChain.GENESIS_PREV
assert isinstance(gp, str) and len(gp) == 64 and set(gp) == {"0"}, \
    f"GENESIS_PREV-64-sıfır-beklendi: {gp[:8]}"
es = ec.get_entries()
assert es and es[0].prev_hash == gp, "ilk-kaydın-prev'i-GENESIS-değil"
print("  Dümen-GENESIS == Tamga-prev-başlangıcı (64-sıfır) — gerçek-parite")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Dümen-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-068: Dümen-evidence-chain → RFC-010"
[[ $FAIL -eq 0 ]]
