#!/usr/bin/env bash
# AT-148: DİĞER-PROJELERDEN-TAMGA'YA-KÖPRÜ — SWARMAX-evidence-seal-anchor'ı.
#
# LEAD'İN-TALİMATI: " Aynı-patern-diğer-yörelerde-var mı? … swarmax/ → evidence-
# ledger-head ( AT-138'deki-payload_hash) — anchor-zarfı-var-mı?" CEVAP: EVET —
# swarmax/sealing.py:53 seal_ledger, Sester-K1-tamga_anchor'ın-swarmax-karşılığı.
#
# TARAMA-SONUCU ( dürüst-önceden-bildir):
#   dumen/  → capability_gate.py'de-sadece-kelime; EvidenceChain.to_json+verify
#             iç-zincirdir ( AT-136-zaten-§6-dumen'e-bağladı), anchor-ZARFI-yok
#   swarmax/ → export_bundle = tablo-dökümü ( head-yok); dpo.ledger_anchors =
#             sadece-sayımlar. AMA-sealing.py-seal_ledger = GERÇEK-anchor-üreticisi
#   pacta/  → tamga_receipt'i-TÜKETİR ( Tier2.verify_tamga_receipt), ÜRETMEZ —
#             alıcı-tarafıdır ( köprü-üreticisi-değil)
#
# KÖPRÜ-ÜRETİCİSİ ( Sester-K1-deseninin-swarmax-aynası):
#   pipeline.evaluate_agent → _persist_alarm → append_evidence ( üretim-ledger'ı)
#   → sealing.seal_ledger: merkle_root( payload_hash'ler) + covers_through_seq
#     + Ed25519-sign( seed, root||covers) → evidence_seals-tablosu
#   → sealing.verify_seals: dışarıdan-gerçek-ed25519-verify ( public-key-mühürde)
#
# Sester-karşılaştırma ( mesh-sinerjisi-için): produce_bundle→head+merkle |
#   tamga_anchor→anchor_id || swarmax: seal_ledger→root_hash+Ed25519-sig.
#   İkisi-de-secret'sız-dışarıdan-doğrulanabilir-kanıt-anchor'udur.
#
# Yedi-kanıt + 3-negatif:
#   1) gerçek-üretim-akışı: ingest+evaluate_agent → alarm → evidence-ledger
#   2) seal_ledger → root_hash-64hex + covers + Ed25519-sig ( TSA'sız-temiz-yol)
#   3) verify_seals-all_ok ( dışarıdan-gerçek-ed25519-verify)
#   4) merkle-root-bağımsız-yeniden-hesaplama-tutar ( pür-sha256)
#   5) tahriz-dayanıklı: yeni-olay → yeni-seal; ESKİ-seal-hâlâ-geçerli
#      ( append-only-triggerlar + covers-sabitliği)
#   6) Ed25519-bağımsız-teyit ( swarmax.ed25519.verify)
#   7) RFC-010-GREEN ( x402/v1-gerçek-ecrecover; 6/6; §6-swarmax-root-equals)
#   N1) sahte-imza → RED rc4
#   N2) evidenceHash-swap → RED rc7
#   N3) kurcalanmış-mühür ( root_hash-değişik) → verify_seals-False ( fail-closed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SWARMAX-SEAL-ANCHOR/$(date +%F)/at148.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-148: Swarmax evidence-seal-anchor'ı (seal_ledger) → Tamga-köprüsü → RFC-010"

SW="/home/gokun/projects/00_TAMGA-MESH/swarmax/src"
if [ ! -f "$SW/swarmax/sealing.py" ]; then
  note "[SKIP] AT-148: Swarmax-kodu-bu-makinede-değil (CI) — seal-anchor-yüzü"
  note "       ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-148: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SW" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, pathlib, re, sys, tempfile
sys.path.insert(0, sys.argv[1])          # swarmax-paketi
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
os.environ.pop("SWARMAX_TSA_URL", None)  # TSA'sız-temiz-yol ( dış-bağımlılık-yok)
from swarmax.db import connect, init_db_with_migrations
from swarmax.pipeline import Pipeline
from swarmax.evidence import verify_chain
from swarmax.sealing import seal_ledger, verify_seals, merkle_root
from swarmax.ed25519 import generate_seed, secret_to_public, verify as ed_verify
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

DB = tempfile.mktemp(suffix="-at148.db")
SEEDF = pathlib.Path(tempfile.mktemp(suffix="-at148-seed.hex"))
try:
    # --- 1) GERÇEK-üretim-akışı: ingest+evaluate_agent → alarm → evidence-ledger
    conn = connect(DB); init_db_with_migrations(conn)
    p = Pipeline(conn)
    def olaylar(aid):
        return [{"event_id": f"{aid}-e{i}", "agent_id": aid, "task_id": f"{aid}-t1",
                 "session_id": "s1", "model_name": "m", "input_tokens": 10,
                 "output_tokens": 5, "cost_usd": 0.01, "latency_ms": 100,
                 "error_class": None, "status": "error" if i < 3 else "ok",
                 "synthetic": True, "ts": "2026-09-22T12:00:00+00:00",
                 "retry_count": 0, "ttft_s": 0.1, "task_template": "T",
                 "end_state_json": "{}"} for i in range(5)]
    p.ingest(olaylar("a1")); p.evaluate_agent("a1", daily_cost=5.0)
    p.ingest(olaylar("a2")); p.evaluate_agent("a2", daily_cost=3.0)
    n_led = conn.execute("SELECT count(*) c FROM evidence_ledger").fetchone()["c"]
    ok, n = verify_chain(conn)
    assert n_led >= 2 and ok is True, f"üretim-ledger'ı-bozuk: n={n_led}, ({ok}, {n})"
    print(f"  üretim-akışı: 2-ajan-Critical-escalation → {n_led}-kayıtlık-evidence-"
          "ledger ( verify_chain-True)")

    # --- 2) seal_ledger → root_hash-64hex + covers + Ed25519-sig
    seed = generate_seed()
    seal = seal_ledger(conn, seed, tsa_url=None)
    root, covers = seal["root_hash"], seal["covers_through_seq"]
    sig, public = seal["signature"], seal["public_key"]
    assert re.fullmatch(r"[0-9a-f]{64}", root), f"root-64hex-değil: {root}"
    assert covers == n_led, f"covers={covers} != ledger-n={n_led}"
    assert re.fullmatch(r"[0-9a-f]{128}", sig), f"Ed25519-sig-128hex-değil: {len(sig)}"
    assert covers > 0
    print(f"  seal_ledger: root_hash={root[:16]}… covers={covers} + Ed25519-sig "
          "( TSA'sız-temiz-yol; evidence_seals-tablosu)")

    # --- 3) verify_seals-all_ok ( dışarıdan-gerçek-ed25519-verify)
    vs = verify_seals(conn)
    assert vs["all_ok"] is True and vs["seals"] >= 1, f"mühür-doğrulanmadı: {vs}"
    assert vs["results"][0]["ok"] is True, f"mühür-geçmedi: {vs['results'][0]}"

    # --- 4) merkle-root-bağımsız-yeniden-hesaplama ( pür-sha256)
    hashes = [r["payload_hash"] for r in conn.execute(
        "SELECT payload_hash FROM evidence_ledger ORDER BY seq").fetchall()]
    assert merkle_root(hashes[:covers]) == root, "merkle-bağımsız-tutmadı"
    # bağımsız-teyit: imza-gerçek ( secret'sız, public-key-mühürde)
    # msg = root.encode() + covers ( sealing.py:69 — ASCII-hex-karakter-baytları)
    msg = root.encode() + covers.to_bytes(8, "big")
    assert ed_verify(bytes.fromhex(public), msg, bytes.fromhex(sig)) is True, \
        "Ed25519-bağımsız-doğrulama-tutmadı"
    print("  verify_seals-all_ok + merkle-root-pür-sha256-bağımsız-teyit + "
          "Ed25519-gerçek-verify ( public-key-mühürde)")

    # --- 5) tahriz-dayanıklı: yeni-olay → yeni-seal; ESKİ-seal-hâlâ-geçerli
    p.ingest(olaylar("a3")); p.evaluate_agent("a3", daily_cost=8.0)
    seal2 = seal_ledger(conn, seed, tsa_url=None)
    assert seal2["covers_through_seq"] > covers, "yeni-seal-covers-artmadı"
    vs2 = verify_seals(conn)
    assert vs2["all_ok"] is True and vs2["seals"] == 2, \
        f"iki-mühür-doğrulanmadı: {vs2}"
    # ESKİ-seal hâlâ geçerli ( append-only + covers-sabitliği)
    eski = [r for r in vs2["results"] if r["seal_id"] == seal["seal_id"]][0]
    assert eski["ok"] is True, "eski-seal-yeni-olay-sonrası-bozuldu ( append-only-iyi-değil)"
    print(f"  tahriz-dayanıklı: 3.-ajan → 2.-seal ( covers={seal2['covers_through_seq']}); "
          "ESKİ-seal-hâlâ-geçerli ( append-only + covers-sabitliği)")

    # --- 6) anchor-zarfı-tutarlılığı: her-seal-dışarıdan-doğrulanabilir
    for r in vs2["results"]:
        assert r["ok"] is True, f"seal-dışarıdan-doğrulanmadı: {r}"

    # --- 7) RFC-010-GREEN ( §6-chain='swarmax', evidence_link='equals', head=root)
    BUYER = ek.PrivateKey(os.urandom(32))
    ADDR = to_checksum_address(BUYER.public_key.to_address())
    govde = {"buyerAddress": ADDR, "sellerAddress": "0x2" * 40,
             "settlementRef": "SWX-SEAL-ANCHOR-148",
             "evidenceHash": {"alg": "sha256", "hex": root}}
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
    sigx = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
    assert len(sigx) == 132
    claim = dict(govde); claim["signature"] = sigx
    charge = {"seq": covers, "prev": "0" * 64, "h": root,
              "delivery_hash": {"alg": "sha256", "hex": root},
              "settlement_bind": {"scheme": "x402/v1",
                                  "payment_id": "SWX-SEAL-ANCHOR-148",
                                  "claim_evidence_hash": {"alg": "sha256", "hex": d},
                                  "payer": ADDR, "payee": "0x2" * 40,
                                  "verified_at": "2026-09-22T00:00:00Z"},
              "foreign_chain_proof": {"chain": "swarmax", "head_hex": root,
                                      "entries": covers,
                                      "evidence_link": "equals",
                                      "verify_cmd": "swarmax.sealing: verify_seals"}}
    r = SB.verify(charge, claim)
    assert r["verdict"] == "GREEN", f"swarmax-seal-dikişi-GREEN-beklendi: {r}"
    for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
              "5_evidence_hash", "6_foreign_chain"):
        assert r["checks"].get(k) is True, f"{k}-geçmedi: {r}"
    print("  swarmax-seal-root → RFC-010-GREEN ( x402/v1-gerçek-ecrecover; 6/6; "
          "§6-swarmax-zinciri-equals)")

    # --- N1) sahte-imza → RED rc4
    for sahte in ("ff" * 33, os.urandom(65).hex()):
        cs = dict(govde); cs["signature"] = sahte
        rs = SB.verify(charge, cs)
        assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
            f"sahte-imza-RED-rc4-beklendi: {rs}"
    print("  N1-sahte-imza ( geçersiz-uzunluk + rastgele-65-byte) → RED rc4")

    # --- N2) evidenceHash-swap → RED rc7
    govde2 = dict(govde)
    govde2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
    d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
    s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
    c2 = dict(govde2); c2["signature"] = s2
    r6 = SB.verify(charge, c2)
    assert r6["verdict"] == "RED" and r6["reason_code"] == 7, \
        f"evidenceHash-swap-RED-rc7-beklendi: {r6}"
    print("  N2-evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 (fail-closed)")

    # --- N3) kurcalanmış-mühür → verify_seals-False ( fail-closed)
    conn.execute("UPDATE evidence_seals SET root_hash=? WHERE seal_id=?",
                 ("b" * 64, seal["seal_id"]))
    conn.commit()
    vs3 = verify_seals(conn)
    kot = [r for r in vs3["results"] if r["seal_id"] == seal["seal_id"]][0]
    assert kot["ok"] is False and "mismatch" in (kot["reason"] or ""), \
        f"kurcalanmış-mühür-geçti: {kot}"
    print("  N3-kurcalanmış-mühür ( root_hash-değişik) → verify_seals-False "
          "( root-or-signature-mismatch; fail-closed)")
    print("  KÖPRÜ-BAĞLANDI: swarmax-seal_ledger → evidence_seals → RFC-010 "
          "( §6-swarmax); Sester-K1-deseninin-swarmax-aynası-gerçek")
    conn.close()
finally:
    for f in (DB, DB + "-wal", DB + "-shm", str(SEEDF)):
        if os.path.exists(f):
            os.unlink(f)
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-swarmax-seal-anchor-köprü-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-148: Swarmax evidence-seal-anchor'ı (seal_ledger) → Tamga-köprüsü → RFC-010"
[[ $FAIL -eq 0 ]]
