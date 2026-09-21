#!/usr/bin/env bash
# AT-077: YIELDIX → RFC-010-DİKİŞİ (B-sınıfı — gerçek-Ed25519-imza).
#
# 99-Yieldix (46-py): src/yieldix/crypto/signer.py — Ed25519ReportSigner,
# PyCA-cryptography-ile-gerçek-RFC-8032-imzası (sign_dict → (sha256-digest,
# ed25519-signature); verify_signature → bool). src/yieldix/crypto/hasher.py
# — canonical_json_bytes (sorted+compact-JSON) + sha256_digest_hex.
# Canlı-kullanım: telemetry/reporter.py:52 (aylık-SLA-raporu-mühürleme),
# server/app.py:407 (onçalık-kayıt-imzası), server/app.py:521 (doğrulama).
#
# YIELDIX-ÖZELLİĞİ: imza-GERÇEK-Ed25519'dur (simnet-yerine-standart) →
# RFC-010'ın-tamga/native-scheme'inde-üretilebilir. Bu-test-altı-kanıt:
#   1) gerçek-anahtarla-(digest,signature)-üretimi (128-hex-imza, 64-hex-digest)
#   2) üretici-tarafı-sağlam (yanlış-anahtar → False)
#   3) tamga/native-GREEN-dikiş — GERÇEK-imza-doğrulaması-ile
#   4) canonical-JSON-paritesi (Tamga-serialization ↔ Yieldix-serialization)
#   5) NEGATİF-1: sahte-imza → RED rc4
#   6) NEGATİF-2: evidenceHash-swap → RED rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-077/$(date +%F)/at077.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-077: Yieldix-gerçek-Ed25519 → RFC-010 tamga/native dikişi"

YX="/home/gokun/projects/01_unicorn/99-Yieldix/src"
if [ ! -f "$YX/yieldix/crypto/signer.py" ] || [ ! -f "$YX/yieldix/crypto/hasher.py" ]; then
  note "[SKIP] AT-077: Yieldix-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# cryptography-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz, SKIP-geçilir.
if ! python3 -c "import cryptography" 2>/dev/null; then
  note "[SKIP] AT-077: cryptography-kütüphanesi-yok —"
  note "       gerçek-imza-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$YX" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from yieldix.crypto.signer import Ed25519ReportSigner
from yieldix.crypto.hasher import canonical_json_bytes, sha256_digest_hex
import settlement_bind_verify as SB

# --- 1) GERÇEK-Ed25519-üretimi: Yieldix'in-gerçek-anahtarı-ile (RFC-8032)
signer = Ed25519ReportSigner()                  # cryptography-ed25519, gerçek
PUB = signer.public_key_hex                     # 32-byte-genel-anahtar
assert len(PUB) == 64 and all(c in "0123456789abcdef" for c in PUB)

# kanıt-payload'u-gerçek-bir-Yieldix-SLA-raporu-şeklinde (reporter.py:36-50)
RAPOR = {"report_id": "yrpt_20260901_tamga", "tenant_id": "tamga",
         "period_start": "2026-09-01", "period_end": "2026-09-30",
         "total_leads": 128, "qualified_sql": 42,
         "p95_speed_to_lead_seconds": 37.5, "cost_per_lead_try": "96.50",
         "error_rate_pct": 0.8, "escalation_rate_pct": 4.2,
         "circuit_breaker_triggered": False,
         "active_components": ["receptionist", "speed_to_lead", "cold_email_l2"],
         "engine_version": "16.0.0"}
kanit_digest = sha256_digest_hex(RAPOR)          # gerçek-hasher, gerçek-özüt
assert len(kanit_digest) == 64

# RFC-010-talep-gövdesi (imzasız):-buyerAddress-imzalayan-genel-anahtardır
PAYEE = "0x71C8A18174415cC92067749eb3544DFFD3F87884"
PID = "YLDX-RPT-2026-09"
govde = {"buyerAddress": PUB, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": kanit_digest}}
c_digest, c_sig = signer.sign_dict(govde)        # GERÇEK-(digest,signature)-ikilisi
assert len(c_digest) == 64, f"digest-64-hex-beklendi: {len(c_digest)}"
assert len(c_sig) == 128, f"imza-128-hex-beklendi: {len(c_sig)}"
claim = dict(govde); claim["signature"] = c_sig
print(f"  Yieldix-Ed25519-üretildi: pub={PUB[:16]}… digest={c_digest[:16]}… "
      f"sig={c_sig[:16]}… (64+128-hex)")

# --- 2) Üretici-tarafı-sağlam: yanlış-anahtar/yanlış-payload → False
assert Ed25519ReportSigner.verify_signature(govde, c_sig, PUB) is True, \
    "gerçek-imza-gerçek-anahtarla-doğrulanmalı"
assert Ed25519ReportSigner.verify_signature(govde, c_sig, "0"*64) is False, \
    "yanlış-anahtar-doğrulamamalı"
assert Ed25519ReportSigner.verify_signature(
    {**govde, "settlementRef": "SAHTE"}, c_sig, PUB) is False, \
    "yanlış-payload-doğrulamamalı (değişmezlik)"
print("  verify_signature: doğru-anahtar-True, yanlış-anahtar/yanlış-payload-False")

# --- 3) nacl↔cryptography-paritesinin-açık-ölçümü + stock-branch-ölçümü
# RFC-010-İMZA-SÖZLEŞMESİ (AT-077'nin-keşfettiği-gerçek): Ed25519-imzası-gövde-
# metninin-DEĞİL, sha256-digest'ın-HAM-BAYTLARI-üzerine-atılmalıdır (x402/v1'in
# z=raw-sha256-kuralıyla-AYNI-giriş-şekli — AT-075'in-EIP-191-dersiyle-paralel).
# Nedeni: gate-ile-producer-aynı-JSON-serialization'ı-kullanamayabilir (boşluk-
# separatorleri); ama-digest-bayt-eşit-olduğunda-imza-kanalı-tam-tutarlıdır.
STOCK = SB._claim_signer                        # değiştirmeden-önce-ölç
d_stock = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
# RFC-010-sözleşmeli-imza: digest-baytları-üzerine (naclSigningKey-ile)
# cryptography-Ed25519-privkey'in-32-byte-seed'i-nacl-anahtarı-ile-aynı (RFC-8032)
from nacl.signing import SigningKey as _SK
_seed = signer._private_key.private_bytes_raw()
_nacl_sk = _SK(_seed)
sig_sozlesme = _nacl_sk.sign(bytes.fromhex(d_stock)).signature.hex()
assert len(sig_sozlesme) == 128
r_stock = STOCK(d_stock, sig_sozlesme, "tamga/native", PUB)
STOCK_OK = r_stock == PUB
try:
    from nacl.signing import VerifyKey
    from nacl.encoding import HexEncoder
    VerifyKey(PUB, encoder=HexEncoder).verify(
        bytes.fromhex(d_stock), bytes.fromhex(sig_sozlesme))
    NACL_PARITE = "DOĞRULADI"
except ImportError:
    NACL_PARITE = "nacl-YOK"
except Exception as e:
    NACL_PARITE = f"BAŞARISIZ:{type(e).__name__}"
print(f"  RFC-010-sözleşmeli-imza (digest-baytları-üzerine) stock-ile-doğrulandı: {STOCK_OK}")
print(f"  nacl↔cryptography-paritesi: {NACL_PARITE} (RFC-8032-standardı)")
# eski-hata-sınama: R-noktasını-anahtar-sanan-eski-stock-bu-imzayı-RED-geri-
# getirirdi (gerçek-boşluk-kanıtı): sig[:64]≠PUB
assert sig_sozlesme[:64] != PUB, "imza-R-noktası-genel-anahtar-OLAMAZ (eski-hata)"

# --- DİKİŞ: RFC-010-sözleşmeli-talep → gate (STOCK-yol, test-double-YOK) -----
# AT-077'nin-asıl-sonucu: stock-_claim_signer-artık-GERÇEK-doğrulama-yapar
# (eski-iki-boşluk-kapandı: R-noktası≠anahtar, mesaj≠gövde-metni). Bu-nedenle
# test-double-YERİNE-stock-branch-koşulur — AT-075'in-öğrettiği-disiplin:
# gerçek-yol-unittest-double-ile-asla-gizlenmez.
claim_sozlesme = dict(govde); claim_sozlesme["signature"] = sig_sozlesme

charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": kanit_digest},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": kanit_digest},
                              "payer": PUB, "payee": PAYEE,
                              "verified_at": "2026-09-30T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": kanit_digest,
                                  "entries": 1,
                                  "verify_cmd": "yieldix.crypto.signer"}}
r = SB.verify(charge, claim_sozlesme)
assert r["verdict"] == "GREEN", f"Yieldix-dikişi-GREEN-beklendi (STOCK): {r}"
assert r["checks"].get("2_claim_sig") is True, "imza-kontrolü-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  RFC-010-sözleşmeli-talep → GREEN (STOCK-yol, double-YOK)")

# --- 4) Canonical-JSON-paritesi: Tamga ↔ Yieldix serialization-ilişkisi
# settlement_bind_verify: json.dumps(..., sort_keys=True) — varsayılan-
# separatorler-(", ",": ")-ile. Yieldix: separators=(",",":") — compact.
# Ölçüm-sonucu: bayt-düzeyde-FARKLIdırlar (boşluklar), ANCAK-aynı-JSON-
# nesnesini-tamser-ederler-ve-boşluk-normalleştirmesi-birebir-eşittir.
t_ser = json.dumps(govde, sort_keys=True).encode()    # Tamga'nın-yolu
y_ser = canonical_json_bytes(govde)                    # Yieldix'in-yolu
assert json.loads(t_ser) == json.loads(y_ser), "aynı-JSON-nesli-değil"
assert json.dumps(json.loads(t_ser), sort_keys=True,
                  separators=(",", ":")).encode() == y_ser, \
    "boşluk-normalleştirilmiş-bayt-eşitsizliği"
# gate'in-çalıştığı-digest-kanalı-kesin-tutarlı (GREEN-üzerinden-kanıtlandı:
# (a)-adımı-aynı-serialization'ı-yeniden-hesaplayıp-karşılaştırdı).
d_tamga = hashlib.sha256(t_ser).hexdigest()
d_yieldix = hashlib.sha256(y_ser).hexdigest()
assert d_tamga == d_stock, "gate-digest'i-Tamga-kanalıyla-birebir-olmalı"
assert d_yieldix == c_digest, "üretici-digest'i-Yieldix-kanalıyla-birebir-olmalı"
print(f"  canonical-JSON-paritesi: semantik+normalleştirilmiş-bayt-AYNI, "
      f"separator-boşlukları-NEDENİYLE-bayt/digest-FARKLI")
print(f"    tamga-digest={d_tamga[:20]}… yieldix-digest={d_yieldix[:20]}…")

# --- 5) NEGATİF-1: sahte-imza → RED rc4 (geçersiz-uzunluk + rastgele-64-byte)
for sahte in ("ff"*33,                            # 66-hex — geçersiz-uzunluk
              os.urandom(64).hex()):              # rastgele-64-byte
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
print("  sahte-imza (geçersiz-uzunluk + rastgele-64-byte) → RED rc4")

# --- 6) NEGATİF-2: evidenceHash-swap → RED rc7 (safal207-negatif-kontrolü)
# saldırgan-aynı-anahtarla-geçerli-imzalar-AMA-kanıtı-başka-bir-özüte-
# yönlendirir: imza-kontrolü-geçer,-evidenceHash-delivery_hash'e-uymaz.
govde2 = {k: v for k, v in govde.items()}
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9"*64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
s2 = _nacl_sk.sign(bytes.fromhex(d2)).signature.hex()  # aynı-gerçek-anahtarla
claim2 = dict(govde2); claim2["signature"] = s2
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r2}"
print("  evidenceHash-swap (yeni-imzalı) → RED rc7 (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Yieldix-Ed25519-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-077: Yieldix-gerçek-Ed25519 → RFC-010"
[[ $FAIL -eq 0 ]]
