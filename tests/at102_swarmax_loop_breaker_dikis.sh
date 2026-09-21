#!/usr/bin/env bash
# AT-102: SWARMAX-LOOP-BREAKER (üçüncü-yüz) → RFC-010-DİKİŞİ (tamga/native — gerçek-Ed25519).
#
# İki-yüzü-bağladık (AT-067-evidence, AT-099-sealing). Kalan-üçüncü-yüz:
# metrics/loop_breaker.py — runaway-loop-breaker (paper-§3.2-3) — guard-plane
# fault-tolerance + SHA256-kanıt-üretimi; metrics/statistics.py — MAD-robust-z
# (§3.2-4) cost-anomalisi. Bu-test-ikisini-birleştirir: döngü-istismarı-ekonomik-
# güvenlik-yüzü.
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   swarmax/metrics/loop_breaker.py:25  call_hash — sha256(tool‖canonical-JSON)
#   swarmax/metrics/loop_breaker.py:35  LoopBreaker.feed — DÜZ/İKİLİ-quarantine
#   swarmax/metrics/loop_breaker.py:17  LOOP_RUN_THRESHOLD=3 (ardışık-özdeş)
#   swarmax/metrics/statistics.py:128   mad_robust_z — cost-anomali-kanıtı
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate
#   tamga/tools/settlement_bind_verify.py:80   tamga/native-Ed25519-sözleşmesi
#
# EKONOMİK-GÜVENLİK-HİKÂYESİ: bir-ajan-aynı-İŞİ-özdeş-argümanlarla-3-kez-çağırırsa
# (ücret-faturalama-döngüsü) — bu-bir-para-tahliye-döngüsüdür. LoopBreaker-3-ardışık-
# özdeş-SHA256'i-tespit-edip-KILL_CIRCUIT_OPEN-quarantine-kararı-verir (DÜZ/İKİLİ —
# süreklilik-yok, K0-ruhuyla-uyumlu). RFC-010-dikişi: quarantine-kanıtı-(call_hash)
# evidenceHash'e-bağlanır; alıcı-kanonik-JSON'ı-bağımsız-yeniden-üretüp-aynı-hash'i
# hesaplayabilir (machine-checkable). mad_robust_z-cost-anomali-kanıtı-üretici-tarafı
# sağlamlığında-ölçülür (1.0,1.1,0.9,1.0,9.5 → robust-z≈57 → alarm).
#
# §3b-ŞEMA-SEÇİMİ: tamga/native — AT-099-sealing-ile-aynı-aile (Swarmax-Ed25519-
# operatör-anahtarı; §4d-iki-kanal-notunun-bir-uygulaması-daha).
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-breaker: 3-özdeş-çağrı → opened=True (KILL_CIRCUIT_OPEN) + 3×64hex
#   2) ÜRETİCİ-TARAFI-SAĞLAMLIK: canonical-yeniden-üretim + duyarlılık + mad-anomali
#   3) DİKİŞ-GREEN: call_hash=evidenceHash + tamga/native (STOCK-nacl) → 6-kontrol
#   4) §6-foreign_chain: head=call_hash, evidence_link='equals' → GREEN
#   5) NEGATİF-1: sahte-call_hash (uydurma-64hex) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SWARMAX-3/$(date +%F)/at102.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-102: Swarmax-loop-breaker (üçüncü-yüz) → RFC-010 tamga/native dikişi"

SW="/home/gokun/projects/00_TAMGA-MESH/swarmax/src/swarmax/metrics/loop_breaker.py"
if [ ! -f "$SW" ]; then
  note "[SKIP] AT-102: Swarmax-kodu-bu-makinede-değil (CI) —"
  note "       loop-breaker-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

if ! python3 -c "import nacl" 2>/dev/null; then
  note "[SKIP] AT-102: nacl-kütüphanesi-yok —"
  note "       stock-Ed25519-doğrulama-koşmadı (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sys, tempfile
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/swarmax/src")

LOG = sys.argv[1]                                  # kanıt-dizini (shell-değişkeni-değil)

from swarmax.metrics.loop_breaker import (LoopBreaker, call_hash, normalize_arguments,
                                          KILL_CIRCUIT_OPEN, LOOP_RUN_THRESHOLD)
from swarmax.metrics.statistics import mad_robust_z
import settlement_bind_verify as SB
from nacl.signing import SigningKey as NaclSigningKey
from nacl.encoding import HexEncoder as NaclHexEncoder

# STUB-YOK (AT-075-disiplini): gate'in-tamga/native-yolu-gerçek-nacl-çağırır
assert "VerifyKey" in inspect.getsource(SB._claim_signer)

# --- 1) GERÇEK-breaker: 3-özdeş-tool-call → quarantine (DÜZ/İKİLİ-karar)
lb = LoopBreaker()
ARG = {"url": "svc-repricing", "qty": 100, "price": 0.05}   # özdeş-iş-argümanı
opened = None
for _ in range(LOOP_RUN_THRESHOLD):                          # 3-ardışık-özdeş-çağrı
    opened = lb.feed("scrape", ARG)
assert opened is True and lb.opened is True, "3-özdeş-çağrı-quarantine-açmalı"
assert lb.hashes[0] == lb.hashes[1] == lb.hashes[2], "hashler-özdeş-olmalı"
h = lb.hashes[0]
assert len(h) == 64 and all(c in "0123456789abcdef" for c in h)
# quarantine-sonrası-feed-True-kalır (fail-safe: bir-açık-devre-kapanmaz)
assert lb.feed("scrape", {"url": "baska"}) is True, \
    "KILL_CIRCUIT_OPEN-sonrası-çağrılar- reddedilir (fail-safe)"
print(f"  GERÇEK-breaker: 3-özdeş-çağrı → KILL_CIRCUIT-open; call_hash {h[:20]}…")
print(f"    threshold={LOOP_RUN_THRESHOLD}; quarantine-sonrası-çağrı-reddedildi (fail-safe)")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: canonical + duyarlılık + mad-anomali
assert call_hash("scrape", ARG) == h, "alıcı-bağımsız-yeniden-üretim-aynı-hash"
assert call_hash("scrape", {"price": 0.05, "qty": 100, "url": "svc-repricing"}) == h, \
    "anahtar-sırası-bağımsız-canonical-JSON"
assert normalize_arguments({"b": 2, "a": 1}) == '{"a":1,"b":2}', \
    "canonical-JSON-şekli-kanonik"
assert call_hash("scrape", dict(ARG, price=0.06)) != h, \
    "argüman-değişince-hash-değişmeli (kanıt-bağımsızlığı)"
# duyarlılık: 2-özdeş-+-1-farklı → quarantine-AÇILMAMALI (gerçek-3-şartı)
lb2 = LoopBreaker()
lb2.feed("scrape", ARG); lb2.feed("scrape", ARG)
lb2.feed("scrape", dict(ARG, price=0.06))
assert lb2.opened is False, "3-ardışık-özdeş-YOKSA-quarantine-açılmaz"
# mad_robust_z: cost-dizisi-anomalisi (§3.2-4) — quarantine'nin-istatistiksel-tamamı
r_mad = mad_robust_z([1.0, 1.1, 0.9, 1.0, 9.5])
assert r_mad.alarm is True and r_mad.robust_z is not None and abs(r_mad.robust_z) > 3.0
r_ok = mad_robust_z([1.0, 1.1, 0.9])
assert r_ok.alarm is False, "sağlıklı-cost-dizisi-alarm-vermemeli (yanlış-pozitif-yok)"
assert mad_robust_z([1.0, 1.0]).alarm is False, "n<3-kanıtsız-alarm-yok (R3)"
print(f"    canonical-yeniden-üretim-aynı; 2+1-farklı→açılma-yok; "
      f"mad-anomali robust_z≈{r_mad.robust_z:.1f} (alarm)")

# --- 3) DİKİŞ-GREEN: call_hash=evidenceHash + tamga/native (STOCK-nacl, §3b)
PID = "SWX-LOOP-0001"
SELLER = "0x" + "2" * 40
nacl_sk = NaclSigningKey.generate()
PUB = nacl_sk.verify_key.encode(encoder=NaclHexEncoder).decode()  # 64-hex (AT-099-yolu)
assert len(PUB) == 64
govde = {"buyerAddress": PUB, "sellerAddress": SELLER, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": h}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig_hex = nacl_sk.sign(bytes.fromhex(digest_hex)).signature.hex()
assert len(sig_hex) == 128
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 102, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": h},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": h},
                              "payer": PUB, "payee": SELLER,
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"loop-breaker-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: quarantine-call_hash=evidenceHash, tamga/native 6-kontrol (STOCK-nacl)")

# --- 4) §6-foreign_chain: call_hash-ledger-head'i-olarak
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                             # whitelist-kısıtı (AT-079-dersi)
    "head_hex": h,                                # guard-plane-kanıtı
    "entries": LOOP_RUN_THRESHOLD,
    "evidence_link": "equals",                    # head == delivery_hash (içerik-bağı)
    "verify_cmd": "swarmax.metrics.loop_breaker.call_hash"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
print(f"  §6-foreign_chain: head=call_hash, evidence_link='equals' → GREEN "
      f"({LOOP_RUN_THRESHOLD}-çağrı)")

# --- kanıt-fixture'ı-kalıcı-la
FX = os.path.join(os.path.dirname(LOG), "at102-swarmax-loop.json")
json.dump({"test": "AT-102", "scheme": "tamga/native", "project": "swarmax/metrics",
           "call_hash": h, "loop_run_threshold": LOOP_RUN_THRESHOLD,
           "kill_state": KILL_CIRCUIT_OPEN, "mad_robust_z": r_mad.robust_z,
           "mad_alarm": r_mad.alarm, "operator_pubkey": PUB, "payment_id": PID,
           "charge": charge6, "claim": claim, "verdict": r6["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-call_hash (uydurma-64hex) → RED rc7
# saldırgan-gerçek-3-özdeş-çağrı-üretmeden-uydurma-hash-yazar; alıcı-call_hash'ı
# yeniden-hesaplayınca-tutmaz → evidenceHash-uyuşmazlığı (rc7).
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-call_hash-RED-rc7-beklendi: {rN1}"
print("  sahte-call_hash (uydurma-64hex) → RED rc7 — kanıtsız-ödeme-alınamaz")

# --- 6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
govde2 = dict(govde)
govde2["sellerAddress"] = "0x" + "9" * 40           # başkası
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
claim2 = dict(govde2)
claim2["signature"] = nacl_sk.sign(bytes.fromhex(d2)).signature.hex()
rN2 = SB.verify(charge, claim2)
assert rN2["verdict"] == "RED" and rN2["reason_code"] == 6, \
    f"party-swap-RED-rc6-beklendi: {rN2}"
assert rN2["checks"].get("2_claim_sig") is True, \
    "negatif-imza-GEÇERLİ-olmalı (saldırı-imzada-değil-party-bağında-yakalanmalı)"
print("  party-swap (imza-geçerli, satıcı-değişti) → RED rc6 (party_mismatch)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Swarmax-loop-breaker-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-102: Swarmax-loop-breaker (üçüncü-yüz) → RFC-010 tamga/native"
[[ $FAIL -eq 0 ]]
