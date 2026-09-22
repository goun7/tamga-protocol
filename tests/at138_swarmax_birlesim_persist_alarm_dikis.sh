#!/usr/bin/env bash
# AT-138: SWARMAX-BİRLEŞİM-PATERENİ — TEK-üretici-noktası-→-çoklu-kanıt-kanalı.
#
# LEAD'İN-AT-136-GENELLEME-GÖREVİ (AT-133-başarısını-genelleştir): Syntropion-
# revenue_router ( AT-131-ledger+AT-132-IPC) + Dümen-dossier ( 6-kanal)'dan-
# sonra-üçüncü-örnek. AT-136-taramamda-hata-yaptım ( "swarmax'te-head-yok"-
# demiştim) — Lead'in-düzeltmesiyle: evidence.py-her-kayda- payload_hash-
# yazar-ve- head = son-kaydın- payload_hash'idir.
#
# ÜRETİCİ-NOKTA: pipeline.py:289 evaluate_agent — gerçeK-üretim-akışında
#   ingest( events) → 7-fact-hesapla → FleetApd.evaluate → Alarm-listesi →
#   _persist_alarm ( :214) TEK-çağrıda-ÜÇ-kanalı-besler:
#     :224 append_evidence → evidence-ledger ( AT-067-kanalı; head-payload_hash)
#     :229 INSERT-alarms ( SLA-kuyruğu; evidence_seq-cross-link-ile)
#     :240 _attach_attribution → attribution_suggestions ( operatör-önerisi)
#   evidence_seq-üç-kanalı-birleştiren-zincir-anahtarıdır.
#
# BU-TESTİN-ÖZÜ: üretim-pipeline.ingest-yolundan-GERÇEK-olay-akışıyla-çalışır
# ( beş-olay-üç-hata-→ error.rate>0.20-Critical-escalation); test-double-YOK.
#
# x402/v1-SÖZLEŞME (AT-131/132/133/136-disiplini): imza-digest'ın-HAM-BAYTLARI
# üzerine ( sign_msg_hash; EIP-191'siz). head-payload_hash-evidenceHash+delivery
# +§6-swarmax-zinciri-equals.
#
# Altı-kanıt + 2-negatif:
#   1) gerçek-üretim-akışı ( ingest+evaluate_agent → Critical-escalation-ateşler)
#   2) head = son-payload_hash-64hex + verify_chain-( True,-N) ( Lead'in-şartı)
#   3) ÜÇ-kanal-birleşimi: alarms.evidence_seq == evidence-ledger-seq +
#      attribution-önerisi ( kanıtlar-zincirle-bağlanır)
#   4) RFC-010-x402/v1-GREEN ( gerçek-ecrecover; 6/6; §6-swarmax-equals)
#   5) NEG-1: sahte-imza → RED rc4
#   6) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 (fail-closed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SWARMAX-BIRLESIM/$(date +%F)/at138.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-138: Swarmax _persist_alarm-birleşimi (tek-üretici → 3-kanıt-kanalı) → RFC-010"

SW="/home/gokun/projects/01_unicorn/69-Swarmax/src"
if [ ! -f "$SW/swarmax/pipeline.py" ]; then
  note "[SKIP] AT-138: Swarmax-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-138: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SW" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, re, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from swarmax.db import connect, init_db_with_migrations
from swarmax.pipeline import Pipeline
from swarmax.evidence import verify_chain
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

DB = tempfile.mktemp(suffix="-at138.db")
try:
    # --- 1) GERÇEK-üretim-akışı (ingest+evaluate_agent; gerçek-olay-akışı)
    conn = connect(DB)
    init_db_with_migrations(conn)
    p = Pipeline(conn)
    # beş-olay-üç-hata: error.rate = 3/5 = 60% > 20% → Critical-escalation
    events = []
    for i in range(5):
        events.append({
            "event_id": f"e{i}", "agent_id": "a1", "task_id": "t1",
            "session_id": "s1", "model_name": "m", "input_tokens": 10,
            "output_tokens": 5, "cost_usd": 0.01, "latency_ms": 100,
            "error_class": None, "status": "error" if i < 3 else "ok",
            "synthetic": True, "ts": "2026-09-22T12:00:00+00:00",
            "retry_count": 0, "ttft_s": 0.1, "task_template": "T",
            "end_state_json": "{}"})
    p.ingest(events)
    alarms = p.evaluate_agent("a1", daily_cost=5.0)
    ates = [a for a in alarms if not a.suppressed
            and a.signal == "error.rate>0.20" and a.severity == "Critical"]
    assert len(ates) == 1, f"error.rate>0.20-Critical-ateşmeli: {[(a.signal, a.severity, a.suppressed) for a in alarms]}"
    print("  üretim-akışı-gerçek: ingest(5-olay/3-hata) → error.rate>0.20 → "
          "Critical-escalation-ateşledi (suppressed-değil)")

    # --- 2) HEAD = son-payload_hash + verify_chain (Lead'in-şartı)
    head = conn.execute(
        "SELECT payload_hash FROM evidence_ledger ORDER BY seq DESC LIMIT 1"
    ).fetchone()[0]
    assert re.fullmatch(r"[0-9a-f]{64}", head), f"head-64hex-değil: {head}"
    ok, n = verify_chain(conn)
    assert ok is True and n >= 1, f"verify_chain-True-beklendi: ({ok}, {n})"
    print(f"  head = son-payload_hash-64hex={head[:16]}…; verify_chain=(True, {n})")

    # --- 3) ÜÇ-KANAL-BİRLEŞİMİ: evidence_seq-cross-link + attribution
    arow = conn.execute(
        "SELECT alarm_id, signal, evidence_seq FROM alarms").fetchone()
    assert arow is not None, "alarms-tablosuna-yazılmamış (SLA-kuyruğu-eksik)"
    seq = arow[2]
    evrow = conn.execute(
        "SELECT seq, event_type, payload_hash FROM evidence_ledger"
        " WHERE seq=?", (seq,)).fetchone()
    assert evrow is not None, f"evidence_seq={seq}-ledger'da-yok (cross-link-kopuk)"
    assert evrow[1] == "alarm_created" or "created" in evrow[1], \
        f"beklenmedik-event_type: {evrow[1]}"
    # head = cross-link'li-olayın-özütü-olmalı ( son-yazan-bu-olaydır):
    assert evrow[2] == head, "head-cross-link'li-olayın-payload_hash'ine-eşit-değil"
    sug = conn.execute(
        "SELECT count(*) AS c FROM attribution_suggestions"
        " WHERE alarm_id=?", (arow[0],)).fetchone()[0]
    assert sug >= 1, "attribution-önerisi-üretilmedi (üçüncü-kanal-eksik)"
    print(f"  üç-kanal-birleşimi: alarms.evidence_seq={seq} ↔ evidence_ledger.seq="
          f"{seq} (event_type={evrow[1]}); attribution-önerileri={sug} — "
          "evidence_seq-üç-kanalı-bağlar")

    # --- 4) RFC-010-x402/v1-GREEN-dikiş (gerçek-ecrecover, stock-yol)
    BUYER = ek.PrivateKey(os.urandom(32))
    ADDR = to_checksum_address(BUYER.public_key.to_address())
    govde = {"buyerAddress": ADDR, "sellerAddress": "0x2"*40,
             "settlementRef": "SWX-BIRLESIM-138",
             "evidenceHash": {"alg": "sha256", "hex": head}}
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
    sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
    assert len(sig) == 132  # 0x+130-hex (r+s+v)
    claim = dict(govde); claim["signature"] = sig
    charge = {"seq": n, "prev": "0"*64, "h": head,
              "delivery_hash": {"alg": "sha256", "hex": head},
              "settlement_bind": {"scheme": "x402/v1",
                                  "payment_id": "SWX-BIRLESIM-138",
                                  "claim_evidence_hash": {"alg": "sha256", "hex": d},
                                  "payer": ADDR, "payee": "0x2"*40,
                                  "verified_at": "2026-09-22T00:00:00Z"},
              "foreign_chain_proof": {"chain": "swarmax", "head_hex": head,
                                      "entries": n,
                                      "evidence_link": "equals",
                                      "verify_cmd": "swarmax.pipeline: evaluate_agent"}}
    r4 = SB.verify(charge, claim)
    assert r4["verdict"] == "GREEN", f"swarmax-birleşim-dikişi-GREEN-beklendi: {r4}"
    for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
              "5_evidence_hash", "6_foreign_chain"):
        assert r4["checks"].get(k) is True, f"{k}-geçmedi: {r4}"
    print("  üç-kanal-head'i → RFC-010-GREEN (x402/v1-gerçek-ecrecover; 6/6-"
          "kontrol; §6-swarmax-zinciri-equals)")

    # --- 5) NEG-1: sahte-imza → RED rc4 (rastgele-ve-geçersiz)
    for sahte in ("ff"*33, os.urandom(65).hex()):
        cs = dict(govde); cs["signature"] = sahte
        rs = SB.verify(charge, cs)
        assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
            f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
    print("  sahte-imza (geçersiz-uzunluk + rastgele-65-byte) → RED rc4")

    # --- 6) NEG-2: evidenceHash-swap (aynı-gerçek-anahtarla-yeni-imzalı) → rc7
    govde2 = dict(govde)
    govde2["evidenceHash"] = {"alg": "sha256", "hex": "9"*64}
    d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
    s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
    c2 = dict(govde2); c2["signature"] = s2
    r6 = SB.verify(charge, c2)
    assert r6["verdict"] == "RED" and r6["reason_code"] == 7, \
        f"evidenceHash-swap-RED-rc7-beklendi: {r6}"
    print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
    print("  BİRLEŞİM-PATERENİ-BAĞLANDI: swarmax-_persist_alarm-tek-üretici → "
          "evidence+alarms+attribution → RFC-010")
    conn.close()
finally:
    for f in (DB, DB + "-wal", DB + "-shm"):
        if os.path.exists(f):
            os.unlink(f)
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Swarmax-birleşim-paterni-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-138: Swarmax _persist_alarm-birleşimi (tek-üretici → 3-kanıt-kanalı) → RFC-010"
[[ $FAIL -eq 0 ]]
