#!/usr/bin/env python3
"""
AT-081 fixture-üreticisi: BAĞ-ANAHTARI-modu → GERÇEK-MÜŞTERİ-imzası-modu (RFC-010 §3b).

Ürettikleri (write-scope: .evidence/UNPUMP-BRIDGE/):
  at081-real-buyer.json  — gerçek-alıcı-ECDSA-imzalı, D5-hash-dikişi-kapsayan fixture

RFC-010 §3b x402/v1 imza-sözleşmesi (AT-075/AT-077-disiplini):
  z = raw-sha256(json.dumps(claim-imzasız-gövde, sort_keys=True))
  imza = secp256k1.sign_msg_hash(z)   — EIP-191/encode_defunct ÖNEKSİZ
  doğrulama = ecrecover_to_pub(digest, sig) == buyerAddress (gerçek, test-double YOK)

D5-hash-dikişi (AT-075'in-ölçtüğü-False'u-düzeltir):
  h = sha256(prev ‖ jcs(kayıt-h-dışı))   — settlement_bind DAHİL
  (gerçek ledger authority'si: tamga_runner._verify_chain, aynı kural)

Mod-1 (bağ-anahtarı): private-key servis-tutulur, payer = bağ-adresi (agent_id).
Mod-2 (gerçek-müşteri): private-key ASLA-servise-gelmez, imza X-Bind-Signature
  header'ı ile gelir; payer = gerçek-alıcı-adresi.
"""
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, ".")
from eth_keys import keys  # gerçek-secp256k1 (test-double YOK)
from tamga_canon import jcs

# Deterministik-gerçek-alıcı-anahtarı (fixture-tekrar-üretilebilir; üretim-değil).
BUYER_SK_HEX = "7c0d9f5f3c1e8a2b6d4c8e0f2a6b8d0c4e6f8a0b2c4d6e8f0a2b4c6d8e0f2a46"
_sk = keys.PrivateKey(bytes.fromhex(BUYER_SK_HEX))
BUYER = _sk.public_key.to_checksum_address()

PAYEE = "0xf3f0cc9de0df5a17a09bfcc62d21bfc9ba4f82c5"   # Unpump-PAY_TO (GENISLEME_ANALIZI.md:62)
PID = "UNPUMP-CLEARTAG-93"
PREV = "12df62ad9f06595305e2b737e0c0f2e12dc526b23698498c2938ea930bb5e249"  # at069-seq92'nin-prev'i (zincir-devamı)

# --- 1) kanıt-payload'u (ClearTag-şekli) → delivery_hash
payload = {
    "check_id": "check-at081-real-buyer",
    "offer_id": "AT081-REAL-BUYER",
    "sahte_indirim": False,
    "status": "verified",
    "payment_id": PID,
}
delivery = hashlib.sha256(jcs(payload)).hexdigest()

# --- 2) settlement_bind: ÖNCE-üret (dıştan-yapışık-DEĞİL) — D5-hash'i-kapsar
bind = {
    "scheme": "x402/v1",
    "payment_id": PID,
    "payer": BUYER,            # GERÇEK-ALICI (bağ-adresi DEĞİL) — mod-2
    "payee": PAYEE,
    "amount_usd": 0.1,
    "signed_via": "X-Bind-Signature",   # servis private-key'i TUTMAZ
}

# --- 3) charge-kaydı: settlement_bind gömülü, h EN-SON (kapsayıcı)
#    ÖNEMLİ: payload DAHİL tüm-alanlar-önce-kurulur, sonra h-hesaplanır —
#    aksi-halde payload dikiş-sonrası-eklenmiş-olur (D5-False, dıştan-yapışık).
charge = {
    "seq": 93,
    "prev": PREV,
    "delivery_hash": {"alg": "sha256", "hex": delivery},
    "settlement_bind": bind,
    # dikiş-sonrası-çakışma-YOK: tepe-settlement_bind == payload-settlement_bind
    # (at069-seq92'deki iki-yerde-farklı-değer-hatası düzeltilmiş)
    "payload": {
        **payload,
        "delivery_hash": {"alg": "sha256", "hex": delivery},
        "settlement_bind": bind,
    },
}
no_h = {k: v for k, v in charge.items() if k != "h"}
charge["h"] = hashlib.sha256((charge["prev"] + jcs(no_h).decode()).encode()).hexdigest()

# --- 4) RFC-010 §3b-claim: imzasız-gövde → digest → sign_msg_hash (EIP-191'siz)
govde = {
    "buyerAddress": BUYER,
    "sellerAddress": PAYEE,
    "settlementRef": PID,
    "evidenceHash": {"alg": "sha256", "hex": delivery},
}
digest = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = _sk.sign_msg_hash(bytes.fromhex(digest)).to_hex()   # z=raw-sha256
claim = dict(govde)
claim["signature"] = sig

fx = {
    "charge": charge,
    "claim": claim,
    "payment_id": PID,
    "mode": "real_customer_signature",
    "buyer_address": BUYER,
    "bind_address": "0x28c7f29f7641729ca016f216f0d528c64a449d28",
    "rfc": "RFC-010 §3b (x402/v1, z=raw-sha256, EIP-191-siz)",
    "d5_rule": "h = sha256(prev + jcs(kayıt-h-dışı)) — settlement_bind dahil",
}

out = Path(".evidence/UNPUMP-BRIDGE/at081-real-buyer.json")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(fx, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"yazıldı: {out}")
print(f"  gerçek-alıcı-adresi : {BUYER}")
print(f"  bağ-adresi (mod-1)  : {fx['bind_address']}")
print(f"  digest              : {digest[:24]}…")
print(f"  imza                : {sig[:24]}… (0x+130hex, v={sig[-2:]})")
print(f"  D5-hash-kapsama     : h-settlement_bind'ı-kapsar")
