#!/usr/bin/env bash
# AT-133: SYNTROPION-ALTINCI-YÜZ → RFC-010-DİKİŞİ (C-sınıfı — revenue-router para-akışı).
#
# 18-Syntropion: beş-yüz-bağlandı — AT-078 ( FSEK+escrow), AT-096 ( api/cli),
# AT-112 ( license-HMAC), AT-131 ( database.py-Merkle-audit-ledger), AT-132 (
# shared_memory_ipc.py-shm-bütünlüğü). LEAD'İN-SEÇENEK-2-YÖNLENDİRMESİYLE-bu-
# test-derinleştirme-yapar: **revenue_router.py — Autonomous-Revenue-Distribution
# Engine** ( :27-calculate_and_record_split) TEK-çağrıda-İKI-kanıt-tabanını-
# besler:
#   :80 shm_ipc_bridge.push_revenue_telemetry ( AT-132'nin-IPC-özütünü-üretir)
#   :87 db.log_audit_event( "REVENUE_SPLIT_PROCESSED") ( AT-131'in-Merkle-
#      zincirine-para-akış-olayı-yazar; payload'da-ipc_dispatched-bayrağı-ile)
#
# BU-TESTİN-ÖZÜ: RevenueRouter-üçüncü-taraf-para-akışını-sistem-içindeki-iki
# kripto-kanıt-kanalına-BESLER — "20/75/5-dağıtımı-gerçekten-oldu"-iddiasını
# AT-131'in-tarih-zinciri-ve-AT-132'nin-anlık-telemetrisi-aynı-anda-kanıtlar.
# Üç-kanalı-tek-RFC-010-GREEN-gate'te-birleştirir ( kanıt-tabanları-beslendi).
#
# x402/v1-SÖZLEŞME (AT-131/132-disiplini): imza-digest'ın-HAM-BAYTLARI-üzerine
# ( sign_msg_hash; EIP-191'siz). Test-double-YOK: gerçek-RevenueRouter-gerçek-
# izole-SQLite'a + gerçek-mmap'e-yazar ( SYNTROPION_DB_PATH/SHM_IPC_PATH-env).
#
# Altı-kanıt + 2-negatif:
#   1) gerçek-para-akışı ( Decimal-20/75/5-birebir: 1000→net900→180/675/45;
#      negatif-gelir-ValueError-ile-reddi)
#   2) AT-132-beslenir ( IPC-telemetry-checksum-valid-True; treasury-split'e-
#      eşit-675.00)
#   3) AT-131-beslenir ( REVENUE_SPLIT_PROCESSED-zincire-yazıldı; head-64hex;
#      payload'da-ipc_dispatched-bayrağı)
#   4) RFC-010-x402/v1-GREEN ( gerçek-ecrecover; §6-syntropion-equals; 6/6)
#   5) NEG-1: sahte-imza → RED rc4
#   6) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 (fail-closed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SYNTROPION-6/$(date +%F)/at133.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-133: Syntropion altıncı-yüz (revenue-router para-akışı → AT-131/132 kanıt-tabanları) → RFC-010"

SY="/home/gokun/projects/01_unicorn/18-Syntropion"
if [ ! -f "$SY/syntropion_core/revenue_router.py" ]; then
  note "[SKIP] AT-133: Syntropion-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-133: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SY" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, re, sys, tempfile
# --- izolasyon: env'leri-IMPORTTAN-ÖNCE-set-et ( modül-seviyesi-DEFAULT'lar)
DB = tempfile.mktemp(suffix="-at133.db")
SHM = tempfile.mktemp(suffix="-at133.shm")
os.environ["SYNTROPION_DB_PATH"] = DB
os.environ["SHM_IPC_PATH"] = SHM
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from syntropion_core.database import get_current_iso_time
from syntropion_core.revenue_router import revenue_router
from syntropion_core import database as dbmod
from syntropion_core import shared_memory_ipc as ipc
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

try:
    # --- 1) GERÇEK-para-akışı (Decimal-20/75/5-birebir)
    now = get_current_iso_time()
    dbmod.db.execute("INSERT INTO domain_experts (expert_id,email,full_name,"
                     "industry_domain,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                     ("exp-133", "uzman@syntropion.demo", "Test-Uzman", "AI", now, now))
    dbmod.db.execute("INSERT INTO domain_ideas (idea_id,expert_id,title,"
                     "problem_statement,target_audience,created_at,updated_at) "
                     "VALUES (?,?,?,?,?,?,?)",
                     ("idea-133", "exp-133", "Yapay-Zeka-Stüdyosu", "P", "A", now, now))
    dbmod.db.execute("INSERT INTO ventures (venture_id,idea_id,code_slug,"
                     "display_name,api_prefix_path,status,created_at,updated_at) "
                     "VALUES (?,?,?,?,?,?,?,?)",
                     ("ven-133", "idea-133", "yapay-zeka-studyosu",
                      "Yapay Zeka Stüdyosu", "/v1/ai", "PRODUCTION_LIVE", now, now))
    r = revenue_router.calculate_and_record_split("ven-133", "2026-09",
                                                  1000.00, 100.00)
    # Decimal-kesinlik: 1000-100=900-net; 20%→180.00, 75%→675.00, 5%→45.00
    assert r["status"] == "PROCESSED", "dağıtım-PROCESSED-değil"
    assert r["net_profit_usd"] == 900.00, f"net-bozuk: {r['net_profit_usd']}"
    assert r["expert_rev_share_usd"] == 180.00, "expert-20%-bozuk"
    assert r["treasury_share_usd"] == 675.00, "treasury-75%-bozuk"
    assert r["reserve_fund_usd"] == 45.00, "reserve-5%-bozuk"
    # negatif-gelir-ekonomik-sınıf-reddi (fail-closed)
    try:
        revenue_router.calculate_and_record_split("ven-133", "2026-09x", -1.00)
        raise AssertionError("negatif-gelir-reddedilmedi (ekonomik-sınıf-açık)")
    except ValueError:
        pass
    print("  para-akışı-gerçek: 1000gross→100maliyet→900net→180/675/45 "
          "(Decimal-20/75/5-birebir); negatif-gelir-ValueError-ile-reddedildi")

    # --- 2) AT-132-BESLENİR: IPC-telemetry-checksum-valid-True
    assert r["ipc_telemetry_dispatched"] is True, "IPC-gönderimi-başarısız"
    t = ipc.shm_ipc_bridge.read_latest_telemetry()
    assert t is not None and t["checksum_valid"] is True, "IPC-özütü-doğrulanmadı"
    assert t["venture_slug"] == "yapay-zeka-studyosu" \
        and t["gross_usd"] == 1000.00 and t["net_profit_usd"] == 900.00 \
        and t["treasury_usd"] == 675.00, "IPC-telemetrisi-split'e-eşit-değil"
    ipc_ozut = hashlib.sha256(
        f"{t['timestamp']}:{t['venture_slug']}:{t['gross_usd']:.2f}:"
        f"{t['net_profit_usd']:.2f}:{t['treasury_usd']:.2f}".encode("utf-8")
    ).hexdigest()
    assert re.fullmatch(r"[0-9a-f]{64}", ipc_ozut)
    print(f"  AT-132-beslendi: IPC-telemetry-checksum-valid-True; treasury-"
          f"675.00-split'e-eşit; özüt={ipc_ozut[:16]}…")

    # --- 3) AT-131-BESLENİR: REVENUE_SPLIT_PROCESSED-zincire-yazıldı
    ev = dbmod.db.fetchall("SELECT event_type,actor,payload_json,previous_hash,"
                           "current_hash FROM audit_ledger ORDER BY id")
    assert len(ev) >= 1, "audit-ledger'a-para-akış-olayı-yazılmadı"
    olay = [x for x in ev if x["event_type"] == "REVENUE_SPLIT_PROCESSED"]
    assert len(olay) == 1, "REVENUE_SPLIT_PROCESSED-birebir-olmalı"
    payload = json.loads(olay[0]["payload_json"])
    assert payload["ipc_dispatched"] is True, "ipc-bayrağı-zincirde-False"
    assert payload["treasury_share"] == "675.00", "zincir-payload'ı-yanlış"
    head = olay[0]["current_hash"]
    assert re.fullmatch(r"[0-9a-f]{64}", head), f"chain-head-64hex-değil: {head}"
    # chain-bütünlüğü: stored-head-bağımsız-yeniden-hesapla-EŞİT (AT-131-disiplini)
    ts_satir = dbmod.db.fetchone(
        "SELECT timestamp FROM audit_ledger WHERE event_type=?",
        ("REVENUE_SPLIT_PROCESSED",))["timestamp"]
    to_hash = f"{olay[0]['previous_hash']}:{olay[0]['event_type']}:" \
              f"{olay[0]['actor']}:{ts_satir}:{olay[0]['payload_json']}"
    assert hashlib.sha256(to_hash.encode("utf-8")).hexdigest() == head, \
        "audit-chain-head-yeniden-hesapla'ya-uymuyor (AT-131-zinciri-çürük)"
    print(f"  AT-131-beslendi: REVENUE_SPLIT_PROCESSED-zincire-yazıldı; "
          f"head={head[:16]}…; payload-ipc_dispatched=True (iki-kanal-birleşti)")

    # --- 4) RFC-010-x402/v1-GREEN-dikiş (gerçek-ecrecover, stock-yol)
    # kanıt-tabanı: AT-131-chain-head ( para-akış-olayının-özütü) hem-
    # evidenceHash hem-delivery hem-§6-yabancı-zincir-kökü ( equals).
    BUYER = ek.PrivateKey(os.urandom(32))
    ADDR = to_checksum_address(BUYER.public_key.to_address())
    govde = {"buyerAddress": ADDR, "sellerAddress": "0x2"*40,
             "settlementRef": "SYN-REV-133",
             "evidenceHash": {"alg": "sha256", "hex": head}}
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
    sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
    assert len(sig) == 132  # 0x+130-hex (r+s+v)
    claim = dict(govde); claim["signature"] = sig
    charge = {"seq": 1, "prev": "0"*64, "h": head,
              "delivery_hash": {"alg": "sha256", "hex": head},
              "settlement_bind": {"scheme": "x402/v1", "payment_id": "SYN-REV-133",
                                  "claim_evidence_hash": {"alg": "sha256", "hex": d},
                                  "payer": ADDR, "payee": "0x2"*40,
                                  "verified_at": "2026-09-22T00:00:00Z"},
              "foreign_chain_proof": {"chain": "syntropion", "head_hex": head,
                                      "entries": 1,
                                      "evidence_link": "equals",
                                      "verify_cmd":
                                          "syntropion_core.revenue_router"}}
    r4 = SB.verify(charge, claim)
    assert r4["verdict"] == "GREEN", f"para-akış-dikişi-GREEN-beklendi: {r4}"
    for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
              "5_evidence_hash", "6_foreign_chain"):
        assert r4["checks"].get(k) is True, f"{k}-geçmedi: {r4}"
    print("  para-akış-kanıt-tabanı → RFC-010-GREEN (x402/v1-gerçek-ecrecover; "
          "6/6-kontrol; AT-131-zincir-head'i-+ AT-132-IPC'i-besleyen-router)")

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
    print("  ALTINCI-YÜZ-BAĞLANDI: revenue_router-para-akışı → AT-131+AT-132 "
          "kanıt-tabanları-beslendi → RFC-010")
finally:
    for f in (DB, DB + "-wal", DB + "-shm", SHM):
        if os.path.exists(f):
            os.unlink(f)
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Syntropion-revenue-router-para-akış-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-133: Syntropion altıncı-yüz (revenue-router → AT-131/132 kanıt-tabanları) → RFC-010"
[[ $FAIL -eq 0 ]]
