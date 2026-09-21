#!/usr/bin/env bash
# AT-118: YIELDIX-HASHER+CIRCUIT-BREAKER (dördüncü-yüz) → RFC-010-DİKİŞİ
# (tamga/native — gerçek-Ed25519, AT-077/088-ile-aynı-aile).
#
# Üç-yüzü-bağlandı (AT-077-signer, AT-088-reporter/SLA-mührü, AT-097-server).
# Kalan-dördüncü-yüz (Lead'in-önerdiği-reporter/collector-arkası-VEYA-
# storage/snapshot-yok; onun-yerine-gerçek-kalan-kripto-yüzleri):
#   - crypto/hasher.py — canonical-JSON-deterministik-serialization + sha256
#   - core/circuit_breaker.py — Teorem-3: Bounded-Error-Propagation-ve-Dynamic
#     Component-Isolation (şihştirilmiş-telemetri → bileşen-shed)
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   yieldix/.../crypto/hasher.py:13  canonical_json_bytes (sort+compact+UTF-8)
#   crypto/hasher.py:29              sha256_digest_hex — özüt-üretici-yüz
#   yieldix/.../core/circuit_breaker.py:34 CircuitBreaker (Teorem-3)
#   circuit_breaker.py:51/64/98/101  record_interaction/evaluate_cycle/active/list
#   tamga/tools/settlement_bind_verify.py:74/86 _claim_signer (tamga/native)
#   tamga/tamga_keccak.py + nacl (RFC-8032)
#
# §3b-ŞEMA-SEÇİMİ: tamga/native — AT-077/088'in-Veridict/Yieldix-kararı:
# Yieldix'in-kendi-Ed25519-imzalayıcısı-var (crypto/signer.py); ödeme-kanalında
# da-aynı-aile → gerçek-RFC-8032-nacl. x402/v1-değil (Yieldix-EVM-değil).
# Test-double-YOK: gerçek-nacl-SigningKey + gate'in-kendi-VerifyKey-yolu.
#
# İKİ-YÜZÜN-BİRLİKTE-ANLAMI: hasher-kanıtı-ÜRETİR (canonical-JSON-deterministik
# hashing — Türkçe-UTF8-ve-Decimal-para-birimlerini-bozmadan); circuit-breaker
# kanıtın-GEÇERLİLİĞİNİ-korur (Teorem-3: şiştirilmiş-telemetri-üreten-kötü-
# bileşeni-izoleler — shed'lenmiş-bileşenin-özetinde-active=False-yazılıdır,
# alıcı-bağımsız-görür). Ödeme-layer'ı-bu-ikisini-birlikte-yer:
#   kanıt-özütü = sha256_digest_hex(telemetri{component,calls,escalations,active})
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-hasher: determinizm + Decimal + non-ASCII + TypeError-fail-closed
#   2) ÜRETİCİ-TARAFI-SAĞLAMLIK: Teorem-3-trip + breach-sıfırlama + shed+reinstate
#   3) DİKİŞ-GREEN: telemetri-özütü=evidenceHash + tamga/native → 6-kontrol
#   4) §6-foreign_chain: evidence_link='derived' → GREEN
#   5) NEGATİF-1: sahte-telemetri-özütü (uydurma-64hex) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/YIELDIX-HASHER/$(date +%F)/at118.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-118: Yieldix-hasher+circuit-breaker (dördüncü-yüz) → RFC-010 tamga/native"

YH="/home/gokun/projects/00_TAMGA-MESH/yieldix/src/yieldix/crypto/hasher.py"
if [ ! -f "$YH" ]; then
  note "[SKIP] AT-118: Yieldix-kodu-bu-makinede-değil (CI) —"
  note "       hasher+breaker-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import nacl" 2>/dev/null; then
  note "[SKIP] AT-118: pynacl-yok —"
  note "       gerçek-Ed25519-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, logging, os, sys
# uyarı-loglarını-test-çıkışından-uzak-tut (trip-kanıtı-LOG-dosyasında-kalır)
logging.basicConfig(level=logging.CRITICAL)
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/yieldix/src")

LOG = sys.argv[1]                                  # kanıt-dizini (shell-değişkeni-değil)

from decimal import Decimal
from yieldix.crypto.hasher import canonical_json_bytes, sha256_digest_hex
from yieldix.core.circuit_breaker import CircuitBreaker, ComponentMetrics
import settlement_bind_verify as SB
from nacl.signing import SigningKey, VerifyKey
from nacl.encoding import HexEncoder

# STUB-YOK (AT-075-disiplini): gate'in-imza-yoluna-dokunmadık
assert "ecrecover_to_pub" in inspect.getsource(SB._claim_signer)

# --- 1) GERÇEK-hasher: canonical-JSON-determinizmi + ayırıcılar
# (a) anahtar-sırası-ne-olursa-olsun-aynı-baytlar (sort_keys)
a = {"b": 2, "a": 1, "amount": Decimal("99.25")}
b = {"a": 1, "b": 2, "amount": Decimal("99.25")}
assert canonical_json_bytes(a) == canonical_json_bytes(b), \
    "sort_keys-determinizmi-bozuk"
assert canonical_json_bytes(a) == b'{"a":1,"amount":"99.25","b":2}'
# (b) Decimal → str (para-birimleri-kaymadan — compact-separators)
assert "99.25" in canonical_json_bytes(a).decode()
# (c) ensure_ascii=False: Türkçe-UTF-8-baytları-korunur (ASCII-kaçışında-bozulmaz)
tr = {"ad": "Gökgöz", "il": "İstanbul"}
assert canonical_json_bytes(tr).decode("utf-8") == '{"ad":"Gökgöz","il":"İstanbul"}'
assert len(canonical_json_bytes(tr)) == 34          # kaçışsız-UTF-8-bayt-sayısı
                                                  # (ö/İ-2-byte × 3 + ASCII-28)
# (d) özüt-64-hex + bağımsız-yeniden-üretim
ph0 = sha256_digest_hex(a)
assert len(ph0) == 64
assert sha256_digest_hex(b) == ph0                  # aynı-içerik → aynı-özüt
assert hashlib.sha256(canonical_json_bytes(a)).hexdigest() == ph0
# (e) fail-closed: bilinmeyen-tür → TypeError (sessiz-geçiş-yok)
try:
    canonical_json_bytes({"x": object()})
    raise AssertionError("TypeError-beklendi (fail-closed-serialize)")
except TypeError:
    pass
# (f) farklı-içerik → farklı-özüt (zıt-taraf-negatif)
assert sha256_digest_hex({"a": 1}) != sha256_digest_hex({"a": 2})
print(f"  GERÇEK-hasher: sort+compact+UTF-8-deterministik; Decimal→str; "
      f"özüt {ph0[:20]}… (bağımsız-yeniden-üretim)")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: Teorem-3 — Bounded-Error-Propagation
cb = CircuitBreaker(max_escalation_pct=20.0, max_consecutive_breaches=7)
# (a) şiştirilmiş-telemetri: 10-çağrı-5-escalation → %50 > %20-eşiği
for i in range(10):
    cb.record_interaction("crm_reactivation",
                          has_error=False, was_escalated=(i % 2 == 0))
m = cb._metrics["crm_reactivation"]
assert m.escalation_rate_pct == 50.0 and m.total_calls == 10
# (b) 7-ardışık-döngü → trip → shed (izolasyon)
tripped_at = None
for cycle in range(1, 8):
    if cb.evaluate_cycle("crm_reactivation"):
        tripped_at = cycle
assert tripped_at == 7, f"Teorem-3-7-döngüde-trip-etmeli: {tripped_at}"
assert cb.is_component_active("crm_reactivation") is False
assert cb.get_shed_components() == ["crm_reactivation"]   # sorted
# (c) shed-sonrası-evaluate-False (izolasyon-ısrarcı — tekrar-koşma-yok)
assert cb.evaluate_cycle("crm_reactivation") is False
# (d) sağlıklı-bileşen: %0-escalation → breach-sayaç-sıfır-kalır → aktif
for i in range(10):
    cb.record_interaction("inbox_triage", was_escalated=False)
assert cb._metrics["inbox_triage"].escalation_rate_pct == 0.0
for _ in range(10):
    cb.evaluate_cycle("inbox_triage")
assert cb.is_component_active("inbox_triage") is True
# (e) eşik-altı-salınımlar breach'i-sıfırlar (geçici-dalgalanma-izolasyon-etmez)
for i in range(10):                                  # 10-çağrı-1-escalation → %10
    cb.record_interaction("web_qualifier", was_escalated=(i == 0))
assert cb._metrics["web_qualifier"].escalation_rate_pct == 10.0
for _ in range(20):
    cb.evaluate_cycle("web_qualifier")
assert cb.is_component_active("web_qualifier") is True
# (f) manuel-reinstate (operatör-müdahalesi)
cb.reset_component("crm_reactivation")
assert cb.is_component_active("crm_reactivation") is True
assert cb.get_shed_components() == []
# (g) metrics-rate-sıfır-bölünme-güvenliği
assert ComponentMetrics().error_rate_pct == 0.0 and \
    ComponentMetrics().escalation_rate_pct == 0.0
print("    Teorem-3: %50-escalation→7-döngü-trip→shed (ısrarcı); "
      "%10-ve-%0-aktif-kalır; breach-sıfırlama; reinstate")

# --- 3) DİKİŞ-GREEN: telemetri-özütü=evidenceHash + tamga/native
# özüt-üreticisi-GERÇEK-hasher'dır; alıcı-bağımsız-yeniden-üretir
# (shed-kararı-özütün-içinde — alıcı-izolasyonu-görür, üretici-gizleyemez)
TELEM = {"component": "crm_reactivation", "total_calls": 10,
         "escalations": 5, "active": cb.is_component_active("crm_reactivation")}
ph = sha256_digest_hex(TELEM)
assert ph != ph0 and len(ph) == 64
SK = SigningKey(bytes.fromhex("7a" * 31 + "01"))    # test-only-anahtar
# 64-hex-pubkey (AT-099-dersi: .hex()-değil-.decode())
PUB = SK.verify_key.encode(HexEncoder).decode()
assert len(PUB) == 64
SELLER = "0x" + "2" * 40
PID = "YIELDIX-AT118-0001"
govde = {"buyerAddress": PUB, "sellerAddress": SELLER, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": ph}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
# RFC-010-§3.2 (AT-077-keşfi): imza-digest'ın-HAM-BAYTLARI-üzerine
sig_hex = SK.sign(bytes.fromhex(digest_hex)).signature.hex()
# STOCK-doğrulama: nacl-VerifyKey-gate'in-yolundan
VerifyKey(PUB, encoder=HexEncoder).verify(
    bytes.fromhex(digest_hex), bytes.fromhex(sig_hex))
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 118, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": ph},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": ph},
                              "payer": PUB, "payee": SELLER,
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"hasher-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: telemetri-özütü(hasher)=evidenceHash, tamga/native "
      "6-kontrol (STOCK-Ed25519)")

# --- 4) §6-foreign_chain: derived-bağı (AT-085-deseni)
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                             # whitelist-kısıtı (AT-079-dersi)
    "head_hex": hashlib.sha256(bytes.fromhex(ph)).hexdigest(),
    "entries": 1,
    "evidence_link": "derived",
    "verify_cmd": "yieldix.core.circuit_breaker.evaluate_cycle"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
print("  §6-foreign_chain: evidence_link='derived' (head=sha256(özüt)) → GREEN")

# --- kanıt-fixture'ı-kalıcı-la
FX = os.path.join(os.path.dirname(LOG), "at118-yieldix-hasher.json")
json.dump({"test": "AT-118", "scheme": "tamga/native",
           "project": "yieldix/crypto/hasher + core/circuit_breaker",
           "component": TELEM["component"], "telemetry": TELEM,
           "evidence_sha256": ph, "payment_id": PID,
           "charge": charge6, "claim": claim, "verdict": r6["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-telemetri-özütü (uydurma-64hex) → RED rc7
# saldırgan-gerçek-hasher-üretmeden-uydurma-64hex-yazar; alıcı-özütü
# bağımsız-hashle(yip-tutmaz → evidenceHash-uyuşmazlığı.
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-telemetri-RED-rc7-beklendi: {rN1}"
print("  sahte-telemetri-özütü (uydurma-64hex) → RED rc7 — kanıtsız-ödeme-alınamaz")

# --- 6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
govde2 = dict(govde)
govde2["sellerAddress"] = "0x" + "9" * 40           # başkası
sig2 = SK.sign(bytes.fromhex(
    hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest())
).signature.hex()
claim2 = dict(govde2); claim2["signature"] = sig2
rN2 = SB.verify(charge, claim2)
assert rN2["verdict"] == "RED" and rN2["reason_code"] == 6, \
    f"party-swap-RED-rc6-beklendi: {rN2}"
assert rN2["checks"].get("2_claim_sig") is True, \
    "negatif-imza-GEÇERLİ-olmalı (saldırı-imzada-değil-party-bağında-yakalanmalı)"
print("  party-swap (imza-geçerli, satıcı-değişti) → RED rc6 (party_mismatch)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Yieldix-hasher+breaker-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-118: Yieldix-hasher+circuit-breaker (dördüncü-yüz) → RFC-010 tamga/native"
[[ $FAIL -eq 0 ]]
