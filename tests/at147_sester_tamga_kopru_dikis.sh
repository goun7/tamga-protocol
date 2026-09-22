#!/usr/bin/env bash
# AT-147: SESTER-TAMGA-KÖPRÜ-DİKİŞİ — blockchain-yüzeyi-7 ( sester/sester/bridges.py
# K1-Tamga-çıpası + evidence.py-81-kanıt-köprüsü).
#
# LEAD'İN-TALİMATI: " bridges'in-gerçek-tamga-zincir-head'ini-tüketip-tüketmediği
# VEYA sester-ledger'ını-tamga'ya-aktaran-yüz. Eğer-gerçek-kanıt-üretiyorsa →
# RFC-010'a-bağla ( §6-chain='tamga')." — bu-test-iki-yönü-de-ölçer:
#
#   K1 (Tamga-çıpası): bridges.tamga_anchor bundle'ı Tamga external-anchor
#   zarfına çevirir — alıcı yalnız sha256 ile bağlar ( secret'sız).
#   Kök-üretici: evidence.produce_bundle → head + merkle_root + event_count.
#
#   NOT: LEAD'in-DONUK-alan-notuna-uyuyorum — bridges.py'ye-DOKUNMADIM ( kaynak-
#   sikke-yerinde); sadece-gerçek-yoldan-çağırdım. Köprü-gerçek-kanıt-üretiyor.
#
# TAM-AKIŞ ( test-double-YOK — gerçek-modüller):
#   Ledger.append ( 3-gerçek-olay: quota-deny + replay-deny + charge_receipt)
#   → evidence.produce_bundle → head=proof-zinciri-ucu, merkle_root=merkle(
#   proofs), event_count
#   → verify_bundle ( alıcı-tarafı-SECRET'SIZ: sha256-zinciri + merkle-yeniden-
#     hesaplama)
#   → bridges.tamga_anchor → anchor_id=sha256( head|merkle|count)[:32]
#   → bridges.verify_tamga_anchor ( alıcı-tarafı-bağımsız-doğrulama)
#   → bridges.veridict_claims ( K2-yüzü: 3-reproducible-claim)
#   → RFC-010-x402/v1-GREEN ( §6-chain='sester', evidence_link='equals')
#
# Yedi-kanıt + 3-negatif:
#   1) gerçek-üretim-ledger'ı: 3-olay → bundle ( head-64hex + merkle-64hex)
#   2) verify_bundle-True ( secret'sız-bağımsız-doğrulama)
#   3) tamga_anchor-zarfı: anchor_id-deterministik + source=sikke ( DONUK)
#   4) verify_tamga_anchor-True + json-deterministik ( generated-dışarıda)
#   5) K2-veridict_claims: 3-claim + claim_id=sha256( task|summary|reproducible)
#      [:16] + evidence-head'i-bundle-head'ine-eşit
#   6) tahriz-dayanıklılığı: olay-değişince-head-ve-merkle-değişir
#   7) RFC-010-GREEN ( gerçek-ecrecover; 6/6; §6-sester-equals)
#   N1) sahte-imza → RED rc4
#   N2) evidenceHash-swap → RED rc7
#   N3) anchor_id-tahrizi → verify_tamga_anchor-False ( köprü-bütünlüğü)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SESTER-KOPRU/$(date +%F)/at147.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-147: Sester-Tamga köprüsü (produce_bundle → tamga_anchor) → RFC-010"

SESTER="/home/gokun/projects/00_TAMGA-MESH/sester"
if [ ! -f "$SESTER/sester/bridges.py" ] || [ ! -f "$SESTER/sester/evidence.py" ]; then
  note "[SKIP] AT-147: Sester-kodu-bu-makinede-değil (CI) — köprü-yüzü"
  note "       ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-147: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SESTER" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, re, sys, tempfile
sys.path.insert(0, sys.argv[1])          # sester-paketi
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from sester.ledger import Ledger
from sester.evidence import produce_bundle, verify_bundle, GENESIS, _merkle, proof_hash
from sester.bridges import (tamga_anchor, verify_tamga_anchor,
                            tamga_anchor_json, veridict_claims)
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

DB = tempfile.mktemp(suffix="-at147.db")
try:
    # --- 1) GERÇEK-üretim-ledger'ı: 3-olay → bundle
    led = Ledger(DB, secret="dev-at147")
    led.append("permission_decision", "agent-1", host="h1",
               payload={"decision": "deny", "rule_id": "quota_exceeded"})
    led.append("permission_decision", "agent-1", host="h1",
               payload={"decision": "deny", "rule_id": "replay"})
    led.append("charge_receipt", "agent-1", host="h1", amount=0.05,
               payload={"match_id": "m1"})
    b = produce_bundle(led)
    head, merkle = b["head"], b["merkle_root"]
    assert re.fullmatch(r"[0-9a-f]{64}", head), f"head-64hex-değil: {head}"
    assert re.fullmatch(r"[0-9a-f]{64}", merkle), f"merkle-64hex-değil: {merkle}"
    assert b["event_count"] == 3, f"event_count=3-beklendi: {b['event_count']}"
    print(f"  üretim-ledger: 3-olay → head={head[:16]}… merkle={merkle[:16]}… "
          "( evidence.produce_bundle)")

    # --- 2) verify_bundle-True ( alıcı-tarafı-SECRET'SIZ — pür-sha256)
    ok, msg = verify_bundle(b)
    assert ok is True, f"bundle-doğrulanmadı: {msg}"
    # bağımsız-teyit: merkle'yi-kanonik-yoldan-yeniden-hesapla
    proofs = []
    prev = GENESIS
    for ev in b["events"]:
        assert ev["prev_proof"] == prev, "proof-zinciri-kopuk"
        p = proof_hash(ev, prev)
        assert p == ev["proof"], "proof-uyuşmazlığı"
        proofs.append(p); prev = p
    assert _merkle(proofs) == merkle, "merkle-bağımsız-yeniden-hesaplama-tutmadı"
    print("  verify_bundle-True: alıcı secret'sız sha256-zinciri+merkle-yeniden-"
          "hesapladı (81-kanıt-köprüsü)")

    # --- 3) tamga_anchor-zarfı: anchor_id-deterministik + DONUK-alanlar
    a = tamga_anchor(b, agent_label="agent-1")
    assert a["type"] == "external_anchor" and a["source"] == "sikke", \
        "DONUK-zarf-alanları-bozuk (köprü-sözleşmesi)"
    expect = hashlib.sha256(f"{head}|{merkle}|3".encode()).hexdigest()[:32]
    assert a["anchor_id"] == expect, "anchor_id-deterministik-değil"
    assert a["head"] == head and a["merkle_root"] == merkle, "zarf-içeriği-bozuk"
    print(f"  tamga_anchor: anchor_id=sha256( head|merkle|count)[:32]={a['anchor_id'][:16]}… "
          "( K1-çıpası; source=sikke-DONUK)")

    # --- 4) verify_tamga_anchor-True + json-deterministik
    ok2, msg2 = verify_tamga_anchor(a)
    assert ok2 is True, f"çıpa-doğrulanmadı: {msg2}"
    assert tamga_anchor_json(b) == tamga_anchor_json(b), "json-deterministik-değil"
    j = json.loads(tamga_anchor_json(b))
    assert "generated" not in j, "generated-deterministik-satıra-sızdı"
    print("  verify_tamga_anchor-True: alıcı-tarafı-bağımsız ( tamga-node'a-"
          "tek-satır-yazılabilir; generated-dışarıda-deterministik)")

    # --- 5) K2-veridict_claims: 3-claim + claim_id-kuralı + evidence-bağı
    vc = veridict_claims(b, task_id="sestering")
    vals = [c["claim"] for c in vc["claims"]]
    assert vals == ["quota_enforced", "replay_denied", "chain_integrity"], \
        f"3-claim-beklendi: {vals}"
    for c in vc["claims"]:
        cid = hashlib.sha256(
            f"sestering|{c['summary']}|reproducible".encode()).hexdigest()[:16]
        assert c["claim_id"] == cid, f"claim_id-kuralı-tutmadı: {c['claim_id']}"
        assert c["evidence"]["head"] == head, "claim-evidence-head'i-bağlı-değil"
        assert c["verifiability"] == "reproducible", "verifiability-yanlış"
    print(f"  veridict_claims: 3-reproducible-claim ( quota/replay/chain); "
          "claim_id=sha256( task|summary|reproducible)[:16]; evidence-head-bağlı")

    # --- 6) tahriz-dayanıklılığı: olay-değişince-head-ve-merkle-değişir
    b2 = produce_bundle(led)
    assert b2["head"] == head and b2["merkle_root"] == merkle, "tekrar-üretim-sabit-değil"
    led.append("charge_receipt", "agent-1", host="h1", amount=0.03,
               payload={"match_id": "m2"})
    b3 = produce_bundle(led)
    assert b3["head"] != head and b3["merkle_root"] != merkle, \
        "yeni-olay-head'ı-değiştirmedi ( tahriz-yutuldu)"
    ok3, _ = verify_bundle(b3)
    assert ok3 is True, "genişletilmiş-bundle-doğrulanmadı"
    print("  tahriz-dayanıklı: aynı-ledger→aynı-head ( deterministik); yeni-olay→"
          "head+merkle-değişir")

    # --- 7) RFC-010-GREEN ( §6-chain='sester', evidence_link='equals')
    BUYER = ek.PrivateKey(os.urandom(32))
    ADDR = to_checksum_address(BUYER.public_key.to_address())
    govde = {"buyerAddress": ADDR, "sellerAddress": "0x2" * 40,
             "settlementRef": "SESTER-KOPRU-147",
             "evidenceHash": {"alg": "sha256", "hex": head}}
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
    sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
    assert len(sig) == 132, f"imza-132-karakter-değil: {len(sig)}"
    claim = dict(govde); claim["signature"] = sig
    charge = {"seq": b["event_count"], "prev": "0" * 64, "h": head,
              "delivery_hash": {"alg": "sha256", "hex": head},
              "settlement_bind": {"scheme": "x402/v1",
                                  "payment_id": "SESTER-KOPRU-147",
                                  "claim_evidence_hash": {"alg": "sha256", "hex": d},
                                  "payer": ADDR, "payee": "0x2" * 40,
                                  "verified_at": "2026-09-22T00:00:00Z"},
              "foreign_chain_proof": {"chain": "sester", "head_hex": head,
                                      "entries": b["event_count"],
                                      "evidence_link": "equals",
                                      "verify_cmd": "sester.evidence: verify_bundle"}}
    r = SB.verify(charge, claim)
    assert r["verdict"] == "GREEN", f"sester-köprü-dikişi-GREEN-beklendi: {r}"
    for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
              "5_evidence_hash", "6_foreign_chain"):
        assert r["checks"].get(k) is True, f"{k}-geçmedi: {r}"
    print("  sester-head → RFC-010-GREEN ( x402/v1-gerçek-ecrecover; 6/6-kontrol; "
          "§6-sester-zinciri-equals)")

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

    # --- N3) anchor_id-tahrizi → verify_tamga_anchor-False
    a_bad = dict(a); a_bad["anchor_id"] = "a" * 32
    okb, msgb = verify_tamga_anchor(a_bad)
    assert okb is False and "kopuk" in msgb, f"tahrizli-çıpa-geçti: {msgb}"
    a_bad2 = dict(a); a_bad2["head"] = "f" * 64
    okc, msgc = verify_tamga_anchor(a_bad2)
    assert okc is False, "head-değişince-anchor-geçti"
    print("  N3-anchor_id/head-tahrizi → verify_tamga_anchor-False ( köprü-"
          "bütünlüğü-fail-closed)")
    print("  KÖPRÜ-BAĞLANDI: sester-produce_bundle → tamga_anchor → RFC-010 "
          "( §6-sester); K2-veridict-claim'leri-gerçek")
    led.conn.close()
finally:
    for f in (DB, DB + "-wal", DB + "-shm"):
        if os.path.exists(f):
            os.unlink(f)
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-sester-tamga-köprü-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-147: Sester-Tamga köprüsü (produce_bundle → tamga_anchor) → RFC-010"
[[ $FAIL -eq 0 ]]
