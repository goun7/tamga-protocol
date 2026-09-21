#!/usr/bin/env bash
# AT-114: YIELDIX-DÖRDÜNCÜ-YÜZ (circuit_breaker + hasher) → RFC-010 x402/v1.
#
# Yieldix-üç-yüzü-bağlandı: AT-077 (crypto/signer), AT-088 (telemetry/reporter),
# AT-097 (server/app.py-HTTP). DÖRDÜNCÜ-YÜZ:
#   core/circuit_breaker.py — Circuit-Breaker-ve-Bileşen-Koparma-Motoru
#     (Theorem-3: Bounded-Error-Propagation-ve-Dynamic-Component-Isolation)
#     record_interaction:51  hatayı/escalation'ı-kaydeder
#     evaluate_cycle:64      %20-escalation × 7-ardışık-ihlal → shed (fail-closed)
#     reset_component:104    manuel-iyileştirme
#   crypto/hasher.py — Yieldix'in-KENDİ-kripto-modülü
#     sha256_digest_hex:29   kanonik-json → SHA-256-özet (kanıt-kaynağı)
#
# YIELDIX-ÖZELLİĞİ: bu-test-iki-modülü-BİRLEŞTİRİR — circuit_breaker'ın
# döngü-telemetrisi hasher'la-özetlenir. AT-077'de-signer-sadece-imzalı;
# burada-ÜRETİM-YOLU-özetin-kaynağı-da-Yieldix'in-kendi-modülüdür (double-YOK:
# sha256_digest_hex-gerçek-çağrılır, test-double-değil).
#
# ÖDEME-SEMANTİĞİ: "hizmet-sağlıklı"-kanıtı = N-döngüde-hiçbir-bileşen-shed
# edilmemiş. Fail-closed-TRIPPING: %20-escalation × 7-ardışık → bileşen
# aktif-pipelineden-koparılır → kanıt-ancak-iyileşme-sonrası-yeşillenir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/YIELDIX-4/$(date +%F)/at114.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-114: Yieldix-circuit_breaker+hasher (dördüncü-yüz) → RFC-010 x402/v1"

YX="/home/gokun/projects/01_unicorn/99-Yieldix/src"
if [ ! -f "$YX/yieldix/core/circuit_breaker.py" ] || [ ! -f "$YX/yieldix/crypto/hasher.py" ]; then
  note "[SKIP] AT-114: Yieldix-kodu-bu-makinede-değil (CI) —"
  note "       sağlıklı-döngü-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-114: eth_keys-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$YX" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from yieldix.core.circuit_breaker import CircuitBreaker, ComponentMetrics
from yieldix.crypto.hasher import sha256_digest_hex, canonical_json_bytes
import settlement_bind_verify as SB

from eth_keys import keys

# --- 0) ÜRETİM-yapılandırması (Theorem-3-varsayılanları)
cb = CircuitBreaker(max_escalation_pct=20.0, max_consecutive_breaches=7)
assert cb.max_escalation_pct == 20.0 and cb.max_consecutive_breaches == 7

# --- 1) SAĞLIKLI-döngü: 10-etkileşim, sıfır-escalation → aktif-kalır
for _ in range(10):
    cb.record_interaction("web_qualifier", has_error=False, was_escalated=False)
    assert cb.evaluate_cycle("web_qualifier") is False, "sağlıklı-shed-edilmemeli"
assert cb.is_component_active("web_qualifier") is True
m = cb._metrics["web_qualifier"]
assert m.total_calls == 10 and m.escalation_count == 0
assert m.escalation_rate_pct == 0.0 and m.error_rate_pct == 0.0
assert cb.get_shed_components() == []
print("  sağlıklı-döngü: 10-etkileşim sıfır-escalation → aktif (shed-listesi-boş)")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: tripping-gerçek (Theorem-3)
cb2 = CircuitBreaker(max_escalation_pct=20.0, max_consecutive_breaches=7)
# 5/20-escalation = %25 > %20-eşiği
for d in range(1, 8):
    for _ in range(20):
        cb2.record_interaction("inbox_triage", was_escalated=True)
    shed = cb2.evaluate_cycle("inbox_triage")
    # 7-ardışık-ihlal-sadece-son-döngüde-shed
    expected_shed = (d >= 7)
    assert shed is expected_shed, f"döngü-{d}: shed={shed} expected={expected_shed}"
    ihlal = cb2._metrics["inbox_triage"].consecutive_breaches
    if d < 7:
        assert ihlal == d, f"ihlal-birikmeli: döngü-{d} ihlal={ihlal}"
assert cb2.is_component_active("inbox_triage") is False, "sh'ed-sonrası-aktif-değil"
assert cb2.get_shed_components() == ["inbox_triage"]
mm = cb2._metrics["inbox_triage"]
assert mm.escalation_rate_pct == 100.0 and mm.consecutive_breaches == 7
print(f"  tripping: %100-escalation × 7-ardışık → shed (döngü-7'de)")
print(f"    ihlal-birikimi: 1→2→3→4→5→6→7 (eşik-sadece-7'de-aşılır)")

# --- 3) FAIL-CLOSED-davranış: shed-bileşen-yeniden-değerlendirmede-kapalı
assert cb2.evaluate_cycle("inbox_triage") is False, \
    "sh'ed-bileşen-yeniden-değerlendirmede-False-kalmalı"
# başka-sağlıklı-bileşen-etkilenmez (izolasyon)
cb2.record_interaction("web_qualifier")
assert cb2.evaluate_cycle("web_qualifier") is False
assert cb2.is_component_active("web_qualifier") is True
print("  fail-closed: sh'ed-bileşen-kapalı-kalır | diğerleri-etkilenmez (izolasyon)")

# --- 4) İYİLEŞTİRME: reset_component → manuel-geri-alma
cb2.reset_component("inbox_triage")
assert cb2.is_component_active("inbox_triage") is True
assert cb2.get_shed_components() == []
assert cb2._metrics["inbox_triage"].total_calls == 0, "metrikler-sıfırlanmalı"
print("  reset_component: sh'ed-bileşen-geri-alındı (metrikler-sıfırlandı)")

# --- 5) EŞIK-DİSİPLİNİ: %19-escalation-shed-etmez (sınır-gerçek)
cb3 = CircuitBreaker(max_escalation_pct=20.0, max_consecutive_breaches=3)
for d in range(5):
    # 19/100 = %19 < %20 → ihlal-birikmez
    for _ in range(19):
        cb3.record_interaction("receptionist", was_escalated=True)
    for _ in range(81):
        cb3.record_interaction("receptionist", was_escalated=False)
    assert cb3.evaluate_cycle("receptionist") is False
    assert cb3._metrics["receptionist"].escalation_rate_pct < 20.0
    assert cb3._metrics["receptionist"].consecutive_breaches == 0, \
        "eşik-altı-ihlal-birikmemeli (sıfırlanır)"
assert cb3.is_component_active("receptionist") is True
print("  eşik-disiplini: %19-escalation → shed-YOK (sınır-gerçek, 3-döngüde)")

# --- 6) DİKİŞ: sağlıklı-döngü-kanıtı → RFC-010 x402/v1 (STOCK-yol)
# kanıt-özetini-Yieldix'in-KENDİ-kripto-modülü-üretir (hasher.sha256_digest_hex)
proof = {
    "shed_components": cb.get_shed_components(),
    "cycles_evaluated": 10,
    "components": sorted(cb._metrics.keys()),
    "thresholds": {"max_escalation_pct": cb.max_escalation_pct,
                   "max_consecutive_breaches": cb.max_consecutive_breaches},
    "all_active": all(cb.is_component_active(c) for c in cb._metrics),
    "total_interactions": sum(x.total_calls for x in cb._metrics.values()),
}
assert proof["all_active"] is True and proof["shed_components"] == []
EH = sha256_digest_hex(proof)   # ÜRETİM-YOLU: Yieldix'in-hasher'ı
assert len(EH) == 64 and all(c in "0123456789abcdef" for c in EH)
# kanonikleştirme-gerçek: aynı-içerik-aynı-özet (deterministik)
assert sha256_digest_hex(proof) == EH
raw = canonical_json_bytes(proof)
assert isinstance(raw, bytes) and raw == json.dumps(proof, sort_keys=True,
        separators=(",", ":"), ensure_ascii=False).encode()
print(f"  sağlıklı-döngü-kanıtı → sha256_digest_hex (Yieldix'in-kendi-hasher'ı)")
print(f"    evidenceHash: {EH[:20]}… | all_active=True | 10-döngü")

# --- 7) RFC-010-gate (x402/v1, gerçek-ecrecover)
pk = keys.PrivateKey(bytes.fromhex("99" * 32))
BUYER = pk.public_key.to_checksum_address().lower()
PAYEE = "0x71c8a18174415cc92067749eb3544dffd3f87884"
PID = "YIELDIX-HEALTH-114"
govde = {"buyerAddress": BUYER, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": EH}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(d_claim)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 114, "prev": "0"*64, "h": "c"*64,
          "delivery_hash": {"alg": "sha256", "hex": EH},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": EH},
                              "payer": BUYER, "payee": PAYEE,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": EH,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "yieldix.core.circuit_breaker + crypto.hasher"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Yieldix-sağlık-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  sağlıklı-döngü-kanıtı → RFC-010-GREEN (x402/v1, STOCK-yol)")
print(f"    ödeme-id={PID} | Theorem-3-sağlıklı-pipeline-ödeme-kanıtı")

# --- 8) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("0x" + "99"*65, os.urandom(65).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (65-bayt-sahte + rastgele) → RED rc4")

# --- 9) NEGATİF-2: kanıt-özetine-tahriz → evidenceHash-swap-RED rc7
# saldırgan-shed-listesini-gizler (kötü-bileşeni-aktif-miş-gibi)
proof_bad = {**proof, "shed_components": ["inbox_triage"], "all_active": False}
EH2 = sha256_digest_hex(proof_bad)
assert EH2 != EH, "tahriz-kanıtı-farklı-özet-üretmeli"
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": EH2}}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
sig2 = "0x" + pk.sign_msg_hash(bytes.fromhex(d2)).to_bytes().hex()
claim2 = dict(govde2); claim2["signature"] = sig2
r7 = SB.verify(charge, claim2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"kanıt-tahrizi-RED-rc7-beklendi: {r7}"
print("  kanıt-özetine-tahriz (shed-gizlenen-gerçek-imzalı-özet) → RED rc7")
print("    taşıma-ölçüldü: sağlıklı-özet-delivery_hash'e-sabittir")

# --- 10) MODÜL-BİRLEŞİMİ: AT-077 (signer) × AT-114 (breaker+hasher)
# AT-077-imzaladı-raporu; AT-114-kanıtlar-raporun-arkasındaki-pipeline-sağlığı.
# Üç-Yieldix-kripto-yüzü: Ed25519-imza + SHA-256-özet + Theorem-3-izolasyon.
assert r["checks"]["2_claim_sig"] and r["checks"]["6_foreign_chain"]
assert sha256_digest_hex(proof_bad) != EH
print("  modül-birleşimi: AT-077 (signer) × AT-114 (breaker+hasher)")
print("    imza-raporu-bağlar, sağlıklı-pipeline-ödeme-yetkilendirir")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-Yieldix-circuit_breaker+hasher-sağlık-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-114: Yieldix-circuit_breaker+hasher (dördüncü-yüz) → RFC-010"
[[ $FAIL -eq 0 ]]
