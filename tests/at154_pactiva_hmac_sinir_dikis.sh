#!/usr/bin/env bash
# AT-154: PACTİVA-HMAC-SINIRI-VE-AÇIK-ZİNCİR-DİKİŞİ — AT-152'nin-dürüst-dışlamasının-
# derinleştirilmesi ( Lead'in-hipotez-testi).
#
# LEAD'İN-TALİMATI: " AT-152'de-dürüst-dışladın: pactiva-attestation-HMAC-secret-
# tabanlı → dışarıdan-secret'siz-değil. AMA-mesh-sinerjisi-için-bu-yüzü-de-anlamalıyız:
# webhook-HMAC'ı-secret-ile-doğrulayan-üçüncü-taraf-§6-evidence_link='derived'-
# olabilir ( HMAC-özüt-türevi). YOKSA → İNDETERMİNE ( HMAC-sınırı-belgelenmiş)."
#
# ARAŞTIRMA-SONUCU ( iki-bulgulu-dürüst-rapor):
#
# BULGU-1 ( NEGATİF-hipotez-reddi): webhook-HMAC §6-'derived'-BAĞLANAMAZ.
#   compute_webhook_signature = HMAC-SHA256( secret, payload) — KEY-BAĞLIDIR:
#   aynı-payload-farklı-secret→farklı-özet. §6-derived: head == sha256( receipt) —
#   bu-key'siz-türetilmez. Doğrulama-secret-ZORUNLU-parametre ( verify_webhook_signature
#   secret_key-istersiz-çağrılamaz) → üçüncü-taraf-secret'siz-doğrulayamaz.
#   Yani-HMAC-sınırı-GERÇEK ( Lead'in-hipotezi-doğru-yönde-ama-bağlanamaz).
#
# BULGU-2 ( ANA-KEŞİF): pactiva'da-HMAC-yanı-SIRA-açık-anahtarlı/SECRET'SIZ-kanıt-
#   yüzü-VAR → audit_ledger.py-Proof-of-Audit-zinciri:
#     record_audit_event → block_hash = sha256( idx:ts:type:payload_hash:prev)
#     GENESIS-kökü ( 64×'0'), prev-bağı-ile-zincir
#     verify_audit_ledger_integrity — SECRET'SIZ ( açık-sha256-yeniden-hesaplama;
#     üçüncü-taraf-pür-stdlib-ile-doğrular) → §6-BAĞLANABİLİR ( equals)
#
# Yedi-kanıt + 3-negatif:
#   1) HMAC-sınırı: secret-ZORUNLU + key-bağımlı-özet ( üçüncü-taraf-sınırlaması)
#   2) HMAC-§6-derived-uyumsuzluk ( sha256( receipt)≠HMAC — key'siz-türetilmez)
#   3) açık-zincir-üretim: 2-olay → block_hash + GENESIS-kökü + prev-bağı
#   4) verify_audit_ledger_integrity-secret'suz-True + head=son-block_hash
#   5) tahriz-1: payload-değişimi → PAYLOAD_TAMPERED ( fail-closed)
#   6) tahriz-2: block_hash-değişimi → BLOCK_HASH_INVALID
#   7) RFC-010-GREEN ( §6-pactiva-equals; head=block_hash; 6/6)
#   N1) sahte-imza → rc4
#   N2) evidenceHash-swap → rc7
#   N3) zincir-kopması → CHAIN_DISCONTINUITY
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/PACTIVA-HMAC-SINIR/$(date +%F)/at154.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-154: Pactiva-HMAC-sınırı + açık Proof-of-Audit-zincir → RFC-010"

PA="/home/gokun/projects/00_TAMGA-MESH/pactiva"
if [ ! -f "$PA/pactiva_core/audit_ledger.py" ]; then
  note "[SKIP] AT-154: Pactiva-kodu-bu-makinede-değil (CI) — kanıt-yüzü"
  note "       ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-154: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$PA" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, hmac, json, os, sqlite3, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from pactiva_core.audit_ledger import (record_audit_event,
    verify_audit_ledger_integrity, compute_block_hash, GENESIS_PREV_HASH)
from pactiva_core.webhooks import (compute_webhook_signature,
    verify_webhook_signature)
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

DB = tempfile.mktemp(suffix="-at154.db")
def _schema(c):
    c.execute("""CREATE TABLE IF NOT EXISTS audit_blocks (
        block_index INTEGER PRIMARY KEY, action_type TEXT, payload_json TEXT,
        payload_hash TEXT, prev_block_hash TEXT, block_hash TEXT UNIQUE,
        created_at TEXT)""")
with sqlite3.connect(DB) as c:
    _schema(c)

try:
    # --- 1) HMAC-SINIRI: secret-ZORUNLU + key-bağımlı-özet
    payload = '{"event":"payment","amount":90}'
    sig1 = compute_webhook_signature(payload, "s3cret-1")
    sig2 = compute_webhook_signature(payload, "s3cret-2")
    assert sig1 != sig2, "farklı-secret-aynı-özet ( key-bağımlılık-yok)"
    assert verify_webhook_signature(payload, sig1, "s3cret-1") is True
    assert verify_webhook_signature(payload, sig1, "s3cret-2") is False, \
        "yanlış-secret-imzayı-geçirdi"
    # secret-ZORUNLU: verify-fonksiyonu-secret_key-olmadan-çağrılamaz
    import inspect
    params = list(inspect.signature(verify_webhook_signature).parameters)
    assert "secret_key" in params, "verify-secret_key-parametresi-yok"
    # zamanlama-güvenli-kıyaslama ( compare_digest) — sabit-zamanlı
    src = inspect.getsource(verify_webhook_signature)
    assert "compare_digest" in src, "sabit-zamanlı-kıyaslama-yok ( timing-saldırısı)"
    print("  HMAC-sınırı: secret-ZORUNLU + key-bağımlı-özet + compare_digest; "
              "üçüncü-taraf-secret'siz-doğrulayamaz")

    # --- 2) HMAC-§6-derived-UYUMSUZLUK ( Lead'in-hipotezi-reddi — dürüst-ölçüm)
    # §6-derived: head == sha256( bytes.fromhex( receipt_hex)). HMAC-bu-formda-değil:
    receipt_hex = hashlib.sha256(b"receipt").hexdigest()
    derived = hashlib.sha256(bytes.fromhex(receipt_hex)).hexdigest()
    assert sig1 != derived, "HMAC-özet-sha256( receipt)'e-tesadüfen-eşit ( imkânsız-olmalı)"
    # HMAC-key'siz-türetilmez ( key-üzerinden-bağımlı):
    assert hmac.compare_digest(sig1, compute_webhook_signature(payload, "s3cret-1"))
    print("  HMAC-§6-derived-UYUMSUZ: HMAC( key) ≠ sha256( receipt-türevi) — "
              "key'siz-türetilmez → §6'ya-BAĞLANAMAZ ( hipotez-dürüst-reddi)")

    # --- 3) AÇIK-ZİNCİR-ÜRETİM ( secret'suz-kanıt-yüzü)
    r1 = record_audit_event("escrow_lock", {"escrow_id": "E1", "amount": 100},
                            db_path=DB)
    r2 = record_audit_event("payment_release", {"escrow_id": "E1", "amount": 90},
                            db_path=DB)
    assert r1["block_index"] == 1 and r1["prev_block_hash"] == GENESIS_PREV_HASH, \
        "ilk-blok-GENESIS-kökünde-değil"
    assert r2["prev_block_hash"] == r1["block_hash"], "prev-bağı-kopuk"
    assert len(r2["block_hash"]) == 64, "block_hash-64hex-değil"
    print(f"  açık-zincir: 2-olay → GENESIS-kökü + prev-bağı; head(block_hash)="
              f"{r2['block_hash'][:16]}… ( secret-YOK)")

    # --- 4) verify_audit_ledger_integrity-SECRET'SUZ-True
    v = verify_audit_ledger_integrity(db_path=DB)
    assert v["is_valid"] is True and v["total_blocks"] == 2, \
        f"zincir-doğrulanmadı: {v}"
    head = v["latest_block_hash"]
    assert head == r2["block_hash"], "head-son-block_hash-değil"
    # bağımsız-teyit: pür-sha256-ile-blokları-yeniden-hesapla
    with sqlite3.connect(DB) as c:
        c.row_factory = sqlite3.Row
        rows = c.execute("SELECT * FROM audit_blocks ORDER BY block_index").fetchall()
    prev = GENESIS_PREV_HASH
    for rw in rows:
        ph = hashlib.sha256(rw["payload_json"].encode()).hexdigest()
        assert ph == rw["payload_hash"], "payload-hash-bağımsız-tutmadı"
        bh = compute_block_hash(rw["block_index"], rw["created_at"],
                                rw["action_type"], ph, prev)
        assert bh == rw["block_hash"], "block-hash-bağımsız-tutmadı"
        prev = bh
    print("  integrity-secret'suz-True ( 2/2-blok); bağımsız-pür-sha256-teyit-tam-tutar")

    # --- 5) tahriz-1: payload-değişimi → PAYLOAD_TAMPERED
    with sqlite3.connect(DB) as c:
        c.execute("UPDATE audit_blocks SET payload_json='{\"amount\":999}' "
                  "WHERE block_index=1")
    v2 = verify_audit_ledger_integrity(db_path=DB)
    assert v2["is_valid"] is False and v2["error_code"] == "PAYLOAD_TAMPERED", \
        f"payload-tahrizi-yakalanmadı: {v2}"
    print("  tahriz-1: payload-değişimi → PAYLOAD_TAMPERED ( fail-closed, secret'suz)")

    # --- 6) tahriz-2: block_hash-değişimi → BLOCK_HASH_INVALID
    with sqlite3.connect(DB) as c:
        c.execute("UPDATE audit_blocks SET payload_json='{\"escrow_id\":\"E1\","
                  "\"amount\":100}' WHERE block_index=1")   # orijinal-geri
        c.execute("UPDATE audit_blocks SET block_hash='f'*64 WHERE block_index=2")
    v3 = verify_audit_ledger_integrity(db_path=DB)
    assert v3["is_valid"] is False and v3["error_code"] == "BLOCK_HASH_INVALID", \
        f"hash-tahrizi-yakalanmadı: {v3}"
    print("  tahriz-2: block_hash-değişimi → BLOCK_HASH_INVALID ( üç-katmanlı-koruma)")

    # --- 7) RFC-010-GREEN ( §6-pactiva-equals; head=block_hash)
    with sqlite3.connect(DB) as c:
        # orijinal-2-blokluk-zinciri-geri-yükle ( block_hash-2'yi-geri-al)
        bh2 = compute_block_hash(2, rows[1]["created_at"], "payment_release",
            hashlib.sha256(rows[1]["payload_json"].encode()).hexdigest(),
            compute_block_hash(1, rows[0]["created_at"], "escrow_lock",
                hashlib.sha256(rows[0]["payload_json"].encode()).hexdigest(),
                GENESIS_PREV_HASH))
        c.execute("UPDATE audit_blocks SET block_hash=? WHERE block_index=2", (bh2,))
    v4 = verify_audit_ledger_integrity(db_path=DB)
    assert v4["is_valid"] is True and v4["latest_block_hash"] == bh2, "onarım-sonrası-zincir-geçersiz"
    head = bh2
    BUYER = ek.PrivateKey(os.urandom(32))
    ADDR = to_checksum_address(BUYER.public_key.to_address())
    govde = {"buyerAddress": ADDR, "sellerAddress": "0x" + "2" * 40,
             "settlementRef": "PCT-AUDIT-154",
             "evidenceHash": {"alg": "sha256", "hex": head}}
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
    sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
    claim = dict(govde); claim["signature"] = sig
    charge = {"seq": 2, "prev": "0" * 64, "h": head,
              "delivery_hash": {"alg": "sha256", "hex": head},
              "settlement_bind": {"scheme": "x402/v1", "payment_id": "PCT-AUDIT-154",
                                  "claim_evidence_hash": {"alg": "sha256", "hex": d},
                                  "payer": ADDR, "payee": "0x" + "2" * 40,
                                  "verified_at": "2026-09-22T00:00:00Z"},
              "foreign_chain_proof": {"chain": "pactiva", "head_hex": head,
                                      "entries": 2, "evidence_link": "equals",
                                      "verify_cmd": "pactiva.audit_ledger: verify_audit_ledger_integrity"}}
    r = SB.verify(charge, claim)
    assert r["verdict"] == "GREEN", f"§6-pactiva-GREEN-beklendi: {r}"
    for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
              "5_evidence_hash", "6_foreign_chain"):
        assert r["checks"].get(k) is True, f"{k}-geçmedi: {r}"
    print("  açık-zincir-head → RFC-010-GREEN ( §6-pactiva-equals; 6/6; "
              "AT-152'nin-HMAC-dışlamasının-tamamlayıcısı)")

    # --- N1) sahte-imza → rc4
    for sahte in ("ff" * 33, os.urandom(65).hex()):
        cs = dict(govde); cs["signature"] = sahte
        rs = SB.verify(charge, cs)
        assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
            f"N1-sahte-imza-rc4-beklendi: {rs}"
    print("  N1-sahte-imza ( geçersiz-uzunluk + rastgele-65-byte) → RED rc4")

    # --- N2) evidenceHash-swap → rc7
    govde2 = dict(govde)
    govde2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
    d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
    s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
    c2 = dict(govde2); c2["signature"] = s2
    r6 = SB.verify(charge, c2)
    assert r6["verdict"] == "RED" and r6["reason_code"] == 7, \
        f"N2-evidenceHash-swap-rc7-beklendi: {r6}"
    print("  N2-evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 (fail-closed)")

    # --- N3) zincir-kopması → CHAIN_DISCONTINUITY
    with sqlite3.connect(DB) as c:
        c.execute("UPDATE audit_blocks SET prev_block_hash='e'*64 "
                  "WHERE block_index=2")
    v5 = verify_audit_ledger_integrity(db_path=DB)
    assert v5["is_valid"] is False and v5["error_code"] == "CHAIN_DISCONTINUITY", \
        f"N3-zincir-kopması-yakalanmadı: {v5}"
    print("  N3-zincir-kopması ( prev-bağı-değişimi) → CHAIN_DISCONTINUITY")
    print("  SONUÇ: pactiva'da-HMAC-sınırı-GERÇEK ( §6'ya-bağlanamaz) — AMA-açık "
              "Proof-of-Audit-zinciri-§6-pactiva'ya-BAĞLANDI ( secret'suz-doğrulanabilir)")
finally:
    if os.path.exists(DB):
        os.unlink(DB)
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-pactiva-HMAC-sınırı+açık-zincir-dikişi" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-154: Pactiva-HMAC-sınırı + açık Proof-of-Audit-zincir → RFC-010 (§6-pactiva)"
[[ $FAIL -eq 0 ]]
