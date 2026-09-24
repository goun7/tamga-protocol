#!/usr/bin/env bash
# AT-186-BULGU-2: run_all-dışı-bağımsız-çalıştırmada-AT-162-koruması-kırılıyordu
export SYNTROPION_SECRET_KEY="${SYNTROPION_SECRET_KEY:-simnet-syntropion-test-key-32b}"
# AT-112: SYNTROPION-ÜÇÜNCÜ-YÜZ → RFC-010-DİKİŞİ (C-sınıfı — license-key-HMAC).
#
# 18-Syntropion: AT-078 FSEK-clickwrap-hash'i ( security.py:27) + AT-089
# revenue_router'ı + AT-096 API/CLI'yi-bağladı. KALAN-YÜZ: security.py'nin
# **Lifetime-License-Key + Tenant-Session-Token-HMAC-yüzü** (ölçülmemiş):
#   issue_lifetime_license_key (:80) — HMAC-SHA256 ile-üretilebilen
#      "SYNTROPION-{SLUG}-{EXPERT8}-{HMAC12}"-biçimli-kurumsal-lisans-anahtarı
#   verify_lifetime_license_key (:92) — hmac.compare_digest-ile-sabit-zamanlı
#   create/verify_tenant_session_token (:100/:115) — JWT-tarzı-HS256
#
# FSEK-İLE-BÜTÜNLEŞME (bu-testin-özü): FSEK-5846-terms'ı "onaylanan-nihai-mikro-
# SaaS-için-ömür-boyu-ücretsiz-kurumsal-kullanım-hakkı"-sözü-veriyor; license-key
# o-hakkın-kriptografik-kanıtıdır. AT-078-anlaşmayı-kanıtladı ( attribution);
# AT-112-o-anlaşmadan-doğan-HAKKI-kanıtlar. RFC-010-ikisini-tek-fail-closed-
# gate'te-ödeme-kanıtına-bağlar.
#
# x402/v1-SÖZLEŞME (AT-080/AT-077-disiplini): imza-sha256-digest'ın-HAM-bAYTLARI
# üzerine-atılır (z=raw-sha256, EIP-191-öneksiz) — sign_msg_hash-yolu.
# Test-double-YOK: gerçek-eth_keys-ecrecover-gerçek-yoldan-koşar.
#
# Altı-kanıt + 2-negatif:
#   1) gerçek-license-key-üretimi (HMAC-SHA256, biçim)
#   2) üretici-tarafı-sağlam: doğru-True / yanlış-venture-False / değiştirilmiş-False
#   3) FSEK↔license-bütünleşmesi + session-token-HMAC-yüzü
#   4) RFC-010-x402/v1-GREEN-dikiş (gerçek-ecrecover, stock-yol)
#   5) NEG-1: sahte-imza → RED rc4
#   6) NEG-2: evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SYNTROPION-3/$(date +%F)/at112.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-112: Syntropion üçüncü-yüz (license-key-HMAC) → RFC-010 dikişi"

SY="/home/gokun/projects/01_unicorn/18-Syntropion"
if [ ! -f "$SY/syntropion_core/security.py" ]; then
  note "[SKIP] AT-112: Syntropion-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# eth_keys/eth_utils-yokluğu-eksiklik-değil-İNDETERMİNE (AT-078-disiplini)
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-112: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SY" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, re, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from syntropion_core.security import (
    issue_lifetime_license_key, verify_lifetime_license_key,
    generate_fsek_clickwrap_hash, verify_fsek_clickwrap_hash,
    create_tenant_session_token, verify_tenant_session_token)
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

# --- 1) GERÇEK-license-key-üretimi (HMAC-SHA256, kurumsal-biçim)
VENTURE = "yapay-zeka-studyosu"
EXPERT = "uzman@syntropion.demo"
LIC = issue_lifetime_license_key(VENTURE, EXPERT)
assert re.match(r"^SYNTROPION-[A-Z0-9]+-[A-F0-9]{8}-[A-F0-9]{12}$", LIC), \
    f"license-biçimi-bozuk: {LIC!r}"
parca = LIC.split("-")
assert parca[0] == "SYNTROPION" and len(parca) == 4
# expert-hash-8 = sha256(expert_id)[:8]-UPPER
eh = hashlib.sha256(EXPERT.encode()).hexdigest()[:8].upper()
assert parca[2] == eh, "expert-hash-8-yanlış-hesaplandı"
print(f"  license-key-üretildi: {LIC} (HMAC-SHA256; expert8={parca[2]})")

# --- 2) Üretici-tarafı-sağlam (sabit-zamanlı-doğrulama)
assert verify_lifetime_license_key(LIC, VENTURE, EXPERT) is True, \
    "gerçek-anahtar-gerçek-parametreyle-doğrulanmalı"
assert verify_lifetime_license_key(LIC, "baska-venture", EXPERT) is False, \
    "yanlış-venture-doğrulamamalı (venture-attributionsu)"
assert verify_lifetime_license_key(LIC + "X", VENTURE, EXPERT) is False, \
    "değiştirilmiş-anahtar-doğrulamamalı (HMAC-değişmezlik)"
assert verify_lifetime_license_key(LIC, VENTURE, "baska@uzman.demo") is False, \
    "yanlış-expert-doğrulamamalı (expert-attributionsu)"
print("  verify_lifetime_license_key: doğru-True; yanlış-venture/expert/değiştirilmiş-False")

# --- 3) FSEK↔license-bütünleşmesi + session-token-HMAC-yüzü
# FSEK-5846-terms'ı "ömür-boyu-ücretsiz-kurumsal-kullanım-hakkı"-sözü-verir;
# license-key o-hakkın-kriptografik-kanıtıdır (FSEK-metni-güvenli-yoldan-okunur).
ZD = "2026-09-21T00:00:00+03:00"
FSEK = generate_fsek_clickwrap_hash(EXPERT, ZD)
assert verify_fsek_clickwrap_hash(FSEK, EXPERT, ZD) is True
assert len(FSEK) == 64
# session-token-yüzü-de-aynı-HMAC-güvenliği-ile-ölçülür (JWT-tarzı-HS256)
TOK = create_tenant_session_token("tenant-7", VENTURE, role="expert")
payload = verify_tenant_session_token(TOK)
assert payload["tenant_id"] == "tenant-7" and payload["venture"] == VENTURE
try:
    verify_tenant_session_token(TOK + "0")  # 4-parça → ValueError
    raise AssertionError("bozuk-token-doğrulanmamalı")
except ValueError:
    pass
print(f"  FSEK↔license-bütünleşmesi: FSEK-5846-{FSEK[:12]}… + session-token-HS256-yüzü-gerçek")

# --- 4) RFC-010-x402/v1-GREEN-dikiş (gerçek-ecrecover, stock-yol)
# AT-080-yolu: imza-digest'ın-HAM-BAYTLARI-üzerine (sign_msg_hash; EIP-191'siz).
BUYER = ek.PrivateKey(os.urandom(32))
ADDR = to_checksum_address(BUYER.public_key.to_address())
EV = hashlib.sha256(LIC.encode()).hexdigest()   # license-key'in-özütü=kanıtı
govde = {"buyerAddress": ADDR, "sellerAddress": "0x2"*40,
         "settlementRef": "SYN-LIC-112",
         "evidenceHash": {"alg": "sha256", "hex": EV}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
assert len(sig) == 132  # 0x+130-hex (r+s+v)
claim = dict(govde); claim["signature"] = sig
charge = {"seq": 12, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": EV},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "SYN-LIC-112",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": ADDR, "payee": "0x2"*40,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "dumen", "head_hex": FSEK,
                                  "entries": 1,
                                  "verify_cmd": "syntropion_core.security"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"license-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-ecrecover-imzası-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-dumen-zinciri-geçmedi"
print("  license-key-özütü → RFC-010-GREEN (x402/v1-gerçek-ecrecover, §6-FSEK-zinciriyle)")

# --- 5) NEG-1: sahte-imza → RED rc4 (rastgele-ve-geçersiz)
for sahte in ("ff"*33, os.urandom(65).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
print("  sahte-imza (geçersiz-uzunluk + rastgele-65-byte) → RED rc4")

# --- 6) NEG-2: evidenceHash-swap (aynı-gerçek-anahtarla-yeni-imzalı) → RED rc7
# saldırgan-aynı-anahtarla-geçerli-imza-üretir-AMA-kanıtı-başka-özüte-yönlendirir:
# imza-kontrolü-geçer, evidenceHash-delivery_hash'e-uymaz → fail-closed.
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9"*64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
c2 = dict(govde2); c2["signature"] = s2
r2 = SB.verify(charge, c2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r2}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Syntropion-license-key-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-112: Syntropion üçüncü-yüz (license-key-HMAC) → RFC-010"
[[ $FAIL -eq 0 ]]
