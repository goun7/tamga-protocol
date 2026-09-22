#!/usr/bin/env bash
# AT-131: SYNTROPION-DÖRDÜNCÜ-YÜZ → RFC-010-DİKİŞİ (C-sınıfı — Merkle-audit-ledger).
#
# 18-Syntropion: üç-yüz-bağlandı — AT-078 ( security.py-FSEK-hash + stake_gate.
# py-$10-escrow), AT-096 ( api.py:236-proposals/submit + cli.py:49-submit-idea),
# AT-112 ( security.py-license-key-HMAC + session-token-HS256). KALAN-YÜZ:
#   syntropion_core/database.py:117 — DatabaseManager.log_audit_event —
#     **immutable-Merkle-hash-chain-audit-ledger**: her-olay
#     curr_hash=sha256(prev_hash:event_type:actor:ts:payload)-ile-zincirlenir,
#     SQLite-audit_ledger-tablosuna ( previous_hash,current_hash)-olarak-yazılır,
#     run_transaction-ile-locked-retry'le ( WAL, 60s-busy-timeout).
#
# BU-TESTİN-ÖZÜ: audit-ledger'in-chain-head'i ( son-current_hash) RFC-010'ın-
# evidenceHash'ının-DOĞAL-KAYNAĞIDIR — tahrize-dayanıklı-bütünlük-özütü. Üç-yüz
# anlaşma-hakkı/ödeme-kanıtı-üretirdi; bu-yüz "ne-oldu"-sorusunu-yanıtlar (
# history-proofs): her-üretim-olayı-geri-alamaz-bir-zincire-yazılır.
#
# x402/v1-SÖZLEŞME (AT-080/AT-112-disiplini): imza-digest'ın-HAM-BAYTLARI
# üzerine-atılır ( sign_msg_hash; EIP-191'siz, z=raw-sha256). Test-double-YOK:
# gerçek-eth_keys-ecrecover-gerçek-yoldan-koşar; gerçek-DatabaseManager-gerçek-
# izole-SQLite'a-yazar.
#
# Altı-kanıt + 2-negatif:
#   1) gerçek-chain-üretimi ( izole-SQLite, GENESIS-kökünden-3-olay, head-64hex)
#   2) ledger-zincir-tutarlılığı ( previous==önceki-current; stored-hash'ler
#      yeniden-hesaplanıp-EŞİT — gerçek-bütünlük-doğrulaması)
#   3) tahriz-dayanıklılığı ( bir-satırın-payload'ı-değişirse-yeniden-hesap
#      uyuşmaz → tahriz-TESPİT-EDİLDİ) + retry/run_transaction-yüzü
#   4) RFC-010-x402/v1-GREEN-dikiş ( gerçek-ecrecover, stock-yol, §6-chain)
#   5) NEG-1: sahte-imza → RED rc4
#   6) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 (fail-closed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SYNTROPION-4/$(date +%F)/at131.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-131: Syntropion dördüncü-yüz (database.py-Merkle-audit-ledger) → RFC-010 dikişi"

SY="/home/gokun/projects/01_unicorn/18-Syntropion"
if [ ! -f "$SY/syntropion_core/database.py" ]; then
  note "[SKIP] AT-131: Syntropion-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# eth_keys/eth_utils-yokluğu-eksiklik-değil-İNDETERMİNE (AT-078/112-disiplini)
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-131: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SY" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, re, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from syntropion_core.database import DatabaseManager
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

# --- 1) GERÇEK-chain-üretimi (izole-SQLite; gerçek-üretim-modülü)
ACTOR = "uzman@syntropion.demo"
DBP = tempfile.mktemp(suffix="-at131.db")
try:
    db = DatabaseManager(db_path=DBP)   # _ensure_schema-schema.sql'i-uygular
    h1 = db.log_audit_event("proposal_submitted", ACTOR,
                            {"venture": "yapay-zeka-studyosu", "amount_try": 10})
    h2 = db.log_audit_event("stake_held_in_escrow", ACTOR, {"amount_try": 10})
    h3 = db.log_audit_event("lifetime_license_issued", ACTOR,
                            {"venture": "yapay-zeka-studyosu"})
    GENESIS = "GENESIS_HASH_" + "0" * 64  # database.py:122 sabiti (77-karakter)
    assert re.fullmatch(r"[0-9a-f]{64}", h1), f"head-64hex-değil: {h1}"
    assert h1 != h2 != h3 != h1, "zincir-ilerlemiyor (aynı-hash)"
    rows = db.fetchall("SELECT id,event_type,actor,timestamp,payload_json,"
                       "previous_hash,current_hash FROM audit_ledger ORDER BY id")
    assert len(rows) == 3, f"3-olay-yazılmalı: {len(rows)}"
    assert rows[0]["previous_hash"] == GENESIS, "ilk-satırın-kökü-GENESIS-değil"
    print(f"  chain-üretildi: GENESIS→{h1[:12]}…→{h2[:12]}…→{h3[:12]}… (head-64hex)")
    HEAD = h3

    # --- 2) LEDGER-ZİNCİR-TUTARLILIĞI: previous==önceki-current + stored-hash
    # yeniden-hesaplanır-EŞİT-olmalı (gerçek-bütünlük-doğrulaması)
    for i, r in enumerate(rows):
        if i > 0:
            assert r["previous_hash"] == rows[i-1]["current_hash"], \
                f"satır-{r['id']}: previous-önceki-current'a-eşit-değil"
        to_hash = f"{r['previous_hash']}:{r['event_type']}:{r['actor']}:" \
                  f"{r['timestamp']}:{r['payload_json']}"
        assert hashlib.sha256(to_hash.encode("utf-8")).hexdigest() \
               == r["current_hash"], \
               f"satır-{r['id']}: stored-hash-yeniden-hesapla-eşit-değil"
    print("  zincir-tutarlı: previous==önceki-current (3/3); stored-current_hash'"
          "ler-bağımsız-yeniden-hesapla ile-EŞİT")

    # --- 3) TAHRİZ-DAYANAKLILIĞI: bir-satırın-payload'ı-değişirse-yeniden-hesap
    # uyuşmaz (tahriz-tespit); retry/run_transaction-yüzü-aynı-izole-DB'de-canlı
    assert callable(db.run_transaction) and db.run_transaction(
        lambda c: c.execute("SELECT 1").fetchone()[0]) == 1, \
        "retry-transaction-yüzü-çalışmıyor"
    db.execute("UPDATE audit_ledger SET payload_json=? WHERE id=?",
               (json.dumps({"venture": "KURCALANMIS"}), 2))
    r2 = db.fetchone("SELECT * FROM audit_ledger WHERE id=2")
    to_hash = f"{r2['previous_hash']}:{r2['event_type']}:{r2['actor']}:" \
              f"{r2['timestamp']}:{r2['payload_json']}"
    recomputed = hashlib.sha256(to_hash.encode("utf-8")).hexdigest()
    assert recomputed != r2["current_hash"], \
        "tahriz-edilen-satır-hâlâ-eşit (zincir-çürük)"
    print("  tahriz-tespit: satır-2-payload'ı-değiştirildi → stored-hash-artık-"
          "yeniden-hesapla'ya-uymuyor (canlı-zincirde-bu-tahriz-sonraki-tüm-"
          "head'leri-de-geçersiz-kılardı); run_transaction-retry-yüzü-canlı")

    # --- 4) RFC-010-x402/v1-GREEN-dikiş (gerçek-ecrecover, stock-yol)
    # chain-head'i ( HEAD) hem-evidenceHash hem-delivery hem-§6-yabancı-zincir
    # kökü-olarak-sunulur ( evidence_link=equals → head==receipt_hex).
    BUYER = ek.PrivateKey(os.urandom(32))
    ADDR = to_checksum_address(BUYER.public_key.to_address())
    govde = {"buyerAddress": ADDR, "sellerAddress": "0x2"*40,
             "settlementRef": "SYN-AUDIT-131",
             "evidenceHash": {"alg": "sha256", "hex": HEAD}}
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
    sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
    assert len(sig) == 132  # 0x+130-hex (r+s+v)
    claim = dict(govde); claim["signature"] = sig
    charge = {"seq": 3, "prev": "0"*64, "h": HEAD,
              "delivery_hash": {"alg": "sha256", "hex": HEAD},
              "settlement_bind": {"scheme": "x402/v1", "payment_id": "SYN-AUDIT-131",
                                  "claim_evidence_hash": {"alg": "sha256", "hex": d},
                                  "payer": ADDR, "payee": "0x2"*40,
                                  "verified_at": "2026-09-22T00:00:00Z"},
              "foreign_chain_proof": {"chain": "syntropion", "head_hex": HEAD,
                                      "entries": 3,
                                      "evidence_link": "equals",
                                      "verify_cmd": "syntropion_core.database"}}
    r = SB.verify(charge, claim)
    assert r["verdict"] == "GREEN", f"audit-ledger-dikişi-GREEN-beklendi: {r}"
    for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
              "5_evidence_hash", "6_foreign_chain"):
        assert r["checks"].get(k) is True, f"{k}-geçmedi: {r}"
    print(f"  audit-ledger-chain-head → RFC-010-GREEN (x402/v1-gerçek-ecrecover; "
          f"6/6-kontrol; §6-syntropion-zinciri-equals-bağlı)")

    # --- 5) NEG-1: sahte-imza → RED rc4 (rastgele-ve-geçersiz)
    for sahte in ("ff"*33, os.urandom(65).hex()):
        cs = dict(govde); cs["signature"] = sahte
        rs = SB.verify(charge, cs)
        assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
            f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
    print("  sahte-imza (geçersiz-uzunluk + rastgele-65-byte) → RED rc4")

    # --- 6) NEG-2: evidenceHash-swap (aynı-gerçek-anahtarla-yeni-imzalı) → rc7
    # saldırgan-aynı-anahtarla-geçerli-imza-üretir-AMA-kanıtı-başka-özüte-yönlendirir:
    # imza-kontrolü-geçer, evidenceHash-delivery_hash'e-uymaz → fail-closed.
    govde2 = dict(govde)
    govde2["evidenceHash"] = {"alg": "sha256", "hex": "9"*64}
    d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
    s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
    c2 = dict(govde2); c2["signature"] = s2
    r2v = SB.verify(charge, c2)
    assert r2v["verdict"] == "RED" and r2v["reason_code"] == 7, \
        f"evidenceHash-swap-RED-rc7-beklendi: {r2v}"
    print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
    print("  DÖRDÜNCÜ-YÜZ-BAĞLANDI: database.py-Merkle-audit-ledger → RFC-010")
finally:
    for f in (DBP, DBP+"-wal", DBP+"-shm"):
        if os.path.exists(f):
            os.unlink(f)
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Syntropion-audit-ledger-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-131: Syntropion dördüncü-yüz (database.py-Merkle-audit-ledger) → RFC-010"
[[ $FAIL -eq 0 ]]
