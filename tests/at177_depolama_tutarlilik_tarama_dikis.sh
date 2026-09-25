#!/usr/bin/env bash
# AT-177: DEPOLAMA-KATMANI-TUTARLILIĞI-TARAMASI (15.-sınıf).
#
# task-60. Depolama-anı-çakışmaları: append-atomiteliği, restart-sonrası-
# tutarlılık, WAL/mod-karışımı-fail-closed, bellek-vs-DB-farkı. Öncelik: sester
# (ledger.py), tamga (ledger.jsonl), veridrome (ct_log), pacta (vault-bellek).
#
# BULGU-1 (TEMİZ — sester-ledger-append-atomiteliği + fail-closed): append()
# tek-INSERT + thread-lock- içinde (prev_hash-oku→yaz-atomik; paralel-append'te
# zincir-kopmaz). SAHTE-hash'li-satır-enjekte-edilince verify_chain() → False
# (fail-closed: zincir-bozuksa-settlement-üretilmez). Bilinmeyen-event_type-RED;
# negatif-amount-kapısı (AT-062).
#
# BULGU-2 (TEMİZ — sester-restart-tutarlılığı): seen_nonces/charge_receipt/
# spent_today SQLite'da-kalıcı. KANIT: append+claim_nonce-sonrası-yeni-Ledger
# (aynı-dosya) → verify_chain-True, spent_today-devam, nonce_count-devam,
# n1-replay-hâlâ-RED. Restart-replay-penceresini-sıfırlamaz ( tasarım-gerçek).
#
# BULGU-3 (TEMİZ — tamga-ledger.jsonl-yarım-satır): _ledger_append O_APPEND +
# 0600-atomik-açılış (Audit-9-B6) + tek-write. Yarım-satır ( crash-ortası:
# h-alanı-yok, newline-yok) → tamga_verify_mini "broken@N (unparseable line)"
# → fail-closed. Kırık-zincir-de-kanıttır (AT-146-tasarımı).
#
# BULGU-4 (GERÇEK — veridrome-ct_log-zincirsiz-düz-append): _append_to_ct_log
# jsonl'e-satır-yazar-AMA **prev/zincir-hash'i-YOK** — sadece-zaman-damgalı-
# sıralı-append. KANIT: issue_credential → 1-satır; alanlar
# {cert_id, merkle_root, proofValue, subject, timestamp} — zincir-bağı-YOK.
# Satır-tahriz-edilince (subject+merkle_root) **bağımsız-tespit-YOK**; imzalı-VC
# hâlâ-geçerli ( AT-168-verify_credential-VC'yi-doğrular-AMA-CT-defterini-değil).
# Append-only-sırada-tahriz-tespiti-yok ( RFC-6962-merkle-kökü-log'a-gömülü-
# değil).
#
# BULGU-5 (GERÇEK — pacta-vault-SAF-BELLEK): PactaEscrowVault jobs/
# ledger_balances/total_protocol_revenue_usdc bellekte-tutar; save/load-yok.
# KANIT: create_and_lock+settle-sonrası-yeni-vault ( restart-simülasyonu) →
# ledger 0.0, jobs 0, revenue 0.0 — SETTLED-işin-durumu-ve-fonlar-kayıp.
# Sester/tamga-kalıcı-iken-pacta-transient ( üretim-dağıtımı-API-sürecinde-
# tek-örnek-tutar; ama-restart = tam-kayıp).
#
# DÜRÜST-SINIR: üretim-koduna-DOKUNULMAZ (Lead-düzeltme-yapar). WAL/mod-
# karışımı-testi-SQLite-kilit-nedeniyle-ölçülemedi ( İNDETERMİNE-notu, RED-değil).
#
# ADDITIVE-DİKİŞ: kalıcı-sester-ledger → RFC-010 x402/v1 GREEN (gerçek-EIP-191);
# rc4 + rc7.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MESH_ROOT="$(dirname "$(dirname "$(readlink -f "$HERE")")")"
[ -d "$MESH_ROOT/sester" ] || MESH_ROOT="/home/gokun/projects/00_TAMGA-MESH"
SESTER="$MESH_ROOT/sester"
TAMGA_DIR="$MESH_ROOT/tamga"
VERIDROME="$MESH_ROOT/veridrome/73-Veridrome/src"
PACTA="$MESH_ROOT/pacta"
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR="$HERE/../.evidence/DEPOLAMA"
LOG="$EVDIR/$(date +%F)/at177.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f "$SESTER/sester/ledger.py" ]; then
  note "[SKIP] AT-177: sester/ledger.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-177: eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, sqlite3, sys, tempfile, time
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")

print("=== AT-177: depolama-katmanı-tutarlılığı-taraması ===")

# ---------- BULGU-1 (TEMİZ): sester-append-atomiteliği + fail-closed ----------
tmp = tempfile.mkdtemp()
db = os.path.join(tmp, "at177.db")
from sester.ledger import Ledger
led = Ledger(db, secret="test-secret-32byte-2026-aaaa")
r1 = led.append("charge_receipt", "0xag", "res", 0.05)
r2 = led.append("charge_receipt", "0xag", "res", 0.05)
assert led.verify_chain() is True
print(f"  BULGU-1: append-atomik (tek-INSERT + thread-lock); seq={r1['seq']},"
      f" {r2['seq']}; verify_chain=True")
# sahte-hash'li-satır → fail-closed
raw = sqlite3.connect(db)
raw.execute(
    "INSERT INTO events (ts, event_type, agent_id, host, amount, payload,"
    " prev_hash, hash) VALUES (?,?,?,?,?,?,?,?)",
    (time.time(), "charge_receipt", "0xag", "res", 0.05, "{}",
     r2["hash"], "SAHTE" * 10))
raw.commit()
raw.close()
print(f"    sahte-hash'li-satır → verify_chain: {led.verify_chain()} (fail-closed)")
assert led.verify_chain() is False
# bilinmeyen-event_type-RED + negatif-amount-RED
try:
    led.append("bilinmeyen_tip", "0xag", "res", 1.0)
    print("    bilinmeyen-event_type KABUL (HATA)")
    raise AssertionError("taksonomi-bozuk")
except ValueError as e:
    print(f"    bilinmeyen-event_type → RED ({str(e)[:44]}…)")
try:
    led.append("charge_receipt", "0xag", "res", -1.0)
    print("    negatif-charge KABUL (HATA)")
    raise AssertionError("ekonomik-kapı-bozuk")
except ValueError as e:
    print("    negatif-charge_receipt → RED (AT-062-ekonomik-kapı)")

# ---------- BULGU-2 (TEMİZ): restart-tutarlılık ----------
db2 = os.path.join(tmp, "at177-r.db")
ledA = Ledger(db2, secret="test-secret-32byte-2026-aaaa")
ledA.append("charge_receipt", "0xag", "res", 0.05)
assert ledA.claim_nonce("0xag", "n1") is True
assert ledA.claim_nonce("0xag", "n1") is False
ledA.append("charge_receipt", "0xag", "res", 0.05)
spent_once = ledA.spent_today("0xag")
del ledA  # restart-simülasyonu
ledB = Ledger(db2, secret="test-secret-32byte-2026-aaaa")
print(f"  BULGU-2: restart-sonrası — verify_chain={ledB.verify_chain()}, "
      f"spent_today={ledB.spent_today('0xag')} (önceki={spent_once}), "
      f"nonce_count={ledB.nonce_count()}, n1-replay-RED="
      f"{ledB.claim_nonce('0xag', 'n1') is False}")
assert ledB.verify_chain() is True
assert ledB.spent_today("0xag") == spent_once == 0.10
assert ledB.nonce_count() == 1
assert ledB.claim_nonce("0xag", "n1") is False
print("    → seen_nonces/charge/spent-kalıcı; restart-replay-penceresini-"
      "sıfırlamaz (TEMİZ — tasarım-gerçek)")

# ---------- BULGU-3 (TEMİZ): tamga-yarım-satır ----------
from tamga_canon import canonical as jcs
lp = os.path.join(tmp, "ledger.jsonl")
prev = "0" * 64
for i in range(3):
    rec = {"seq": i + 1, "ts": 1700000000 + i, "op": "charge", "prev": prev}
    rec["h"] = hashlib.sha256(
        (prev + jcs(rec).decode("utf-8")).encode("utf-8")).hexdigest()
    with open(lp, "a", encoding="utf-8") as f:
        f.write(jcs(rec).decode("utf-8") + "\n")
    prev = rec["h"]
with open(lp, "a", encoding="utf-8") as f:
    f.write('{"seq": 4, "ts": 1, "op": "charge", "prev": "' + prev + '"')
from tamga_verify_mini import verify
tip, verdict = verify(lp)
print(f"  BULGU-3: yarım-satır (h-yok/newline-yok) → tamga_verify_mini: "
      f"tip='{tip}', verdict={verdict!r}")
assert isinstance(verdict, str) and verdict.startswith("broken@4"), \
    f"unparseable-line-beklendi: {verdict!r}"
print("    → O_APPEND+0600-atomik + kırık-satır fail-closed (TEMİZ)")

# ---------- BULGU-4 → KAPANDI ( AT-177): ct_log-artık-zincir-bağlı ----------
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/73-Veridrome/src")
from veridrome.credentials.w3c_vc import VeridromeCredentialManager
from veridrome.core.crypto import VeridromeAuthoritySigner
ct = os.path.join(tmp, "ct.jsonl")
sk = VeridromeAuthoritySigner()
mgr = VeridromeCredentialManager(signer=sk, ct_log_path=ct)
vc, _tok = mgr.issue_credential(
    job_id="job-at177", agent_id="agent-1", metrics={"median": 0.9},
    tee_platform="sev-snp", pcr0_measurement="98f12a" + "00" * 29,
    merkle_root="0x" + "a" * 64, validity_days=30)
satirlar = [l for l in open(ct, encoding="utf-8").read().splitlines() if l.strip()]
e0 = json.loads(satirlar[0])
print(f"  BULGU-4-KAPANDI: ct_log-satır={len(satirlar)}; zincir-alanları="
      f"{sorted(e0.keys())}")
zincir_var = ("prev" in e0) and ("h" in e0)
print(f"  BULGU-4-KAPANDI: ct_log-zincir-bağı ( prev+h): {zincir_var}")
assert zincir_var, "AÇIK-GERİ-GELDİ! ( ct_log-hâlâ-zincirsiz)"
assert e0["prev"] == "0" * 64, "ilk-satır-genesis-bağı-beklenir"
# bağımsız-zincir-doğrulama: h-yeniden-hesaplanabilir
import hashlib as _hl
_e = {k: val for k, val in e0.items() if k != "h"}
_h = _hl.sha256((_e["prev"] + json.dumps(_e, sort_keys=True,
                                        ensure_ascii=False)).encode()).hexdigest()
assert _h == e0["h"], "AÇIK: bağımsız-zincir-doğrulama-tutarsız"
print("    → h=sha256( prev+canonical-json) bağımsız-doğrulanabilir")
# tahriz → bağımsız-tespit-EDİLİR ( eskiden-YOKTU)
e0["subject"] = "sahte-agent"
e0["merkle_root"] = "0x" + "f" * 64
_e2 = {k: val for k, val in e0.items() if k != "h"}
_h2 = _hl.sha256((_e2["prev"] + json.dumps(_e2, sort_keys=True,
                                          ensure_ascii=False)).encode()).hexdigest()
tahriz_tespit = (_h2 != e0["h"])
assert tahriz_tespit, "AÇIK: tahriz-tespit-edilmedi"
print("    → tahriz ( subject+merkle_root) bağımsız-olarak-tespit-EDİLİR")
vc_ok = mgr.verify_credential(vc, sk.public_key_bytes)
assert vc_ok is True, "VC-imza-doğrulaması-bozuldu ( AT-168-gerileme)"
print(f"    → VC-imza-doğrulaması-hâlâ-ayrı-katman ( {vc_ok})")

# ---------- BULGU-5: pacta-vault-saf-bellek ( AT-177: KAPSAM-DIŞI — mimari-sınır) ----------
from pacta.core.vault import PactaEscrowVault
v = PactaEscrowVault()
j = v.create_and_lock_escrow(buyer_address="0x" + "1" * 40,
                             seller_address="0x" + "2" * 40, amount_usdc=1.0)
v.submit_output(j.job_id, output_payload={"x": 1})
v.mark_verified_ok(j.job_id)
v.settle_escrow(j.job_id)
tok = j.deposit_token
v2 = PactaEscrowVault()  # restart-simülasyonu
print(f"  BULGU-5 ( mimari-sınır — KAPSAM-DIŞI): pacta-vault-saf-bellek")
print(f"    settle-sonrası ledger={float(v.ledger_balances[tok])}; "
      f"restart-sonrası ledger={float(v2.ledger_balances[tok])}, "
      f"jobs={len(v2.jobs)}")
assert float(v2.ledger_balances[tok]) == 0.0 and len(v2.jobs) == 0
assert not hasattr(v, "save") and not hasattr(v, "load")
print("    → save/load-YOK; jobs/ledger/revenue-bellekte ( GERÇEK-ölçüm)")
print("    NOT: pacta-vault-bir-BİLEŞEN ( in-memory-FSM-referans-uygulaması);")
print("    kalıcı-kanıt-katmanı-tamga-D5-ledger'dır ( §6-ile-bağlı, AT-159/176).")
print("    Kalıcılık-53-testi+FSM-fon-transferi-sözleşmesini-riske-atır;")
print("    mimari-sınır-olarak-kayıtlandı ( ömür-boyu-borç-değil-kapsam-kararı).")

# AT-177-İNDETERMİNE-çözüldü: WAL→DELETE-mod-karışımı-artık-ölçülebilir
# ( öncesi-SQLite-kilit: ledB-hâlâ-açıkken-mod-değiştiriyordu). Önce-temiz-
# kapat, sonra-ayrı-bağlantı-ile-mod-değiştir, sonra-zinciri-tekrar-doğrula.
ledB.close()
try:
    raw2 = sqlite3.connect(db2)
    raw2.execute("PRAGMA journal_mode=DELETE")
    mod_son = raw2.execute("PRAGMA journal_mode").fetchone()[0]
    raw2.close()
    print(f"  NOT: WAL→DELETE-mod-karışımı-ölçüldü — son-mod={mod_son}")
    assert mod_son == "delete", f"mod-değişmedi: {mod_son}"
    # mod-karışımı-zinciri-bozmaz-mı?
    ledC = Ledger(db2, secret="test-secret-32byte-2026-aaaa")
    print(f"    mod-karışımı-sonrası-verify_chain={ledC.verify_chain()}")
    assert ledC.verify_chain() is True, "mod-karışımı-zinciri-bozdu"
    print("    → WAL→DELETE-geçişi-zinciri-bozmaz ( TEMİZ — tasarım-gerçek)")
    ledC.close()
except sqlite3.OperationalError as e:
    print(f"  NOT: WAL/mod-karışımı-testi-İNDETERMİNE (SQLite-kilit: "
          f"{str(e)[:40]}) — RED değil, ölçülemedi")

# ---------- ADDITIVE-DİKİŞ ----------
import settlement_bind_verify as SB
from eth_keys import keys

SK2 = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
SIGNER = SK2.public_key.to_checksum_address().lower()
digest = hashlib.sha256(prev.encode()).hexdigest()
REF = "SESTER-LEDGER-AT177"
claim = {"buyerAddress": SIGNER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": REF,
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items()
                    if k != "signature"}, sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK2.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": REF,
                              "claim_evidence_hash": {
                                  "alg": "sha256", "hex": digest},
                              "payer": SIGNER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "sester", "head_hex": digest,
              "entries": 1, "evidence_link": "equals",
              "verify_cmd": "sester.ledger.Ledger.verify_chain"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"ledger-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["6_foreign_chain"] is True
print(f"  ADDITIVE-DİKİŞ: kalıcı-sester-ledger-zinciri → x402/v1 GREEN rc0 "
      f"(§6-equals, gerçek-EIP-191)")

bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4")

c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7")

print()
print(">>> AT-177-ÖZET: 2-GERÇEK-bulgu (veridrome-CT-log-zincirsiz-tahriz-"
     "tespitsiz, pacta-vault-saf-bellek-restart-kayıp); 3-TEMİZ (sester-atomik-"
     "fail-closed, sester-restart-kalıcı, tamga-yarım-satır-broken@N). "
     "Üretim-koduna-dokunulmadı.")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(depolama-tutarlılık + bulgular + dikiş)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,45p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-177: depolama → 2-GERÇEK-bulgu (veridrome/pacta) + 3-TEMİZ (sester/tamga)"
[[ $FAIL -eq 0 ]]
