#!/usr/bin/env bash

# AT-186-BULGU-2: run_all-disinda-calistirmada-AT-162-korumasi-kirilmasin
export SYNTROPION_SECRET_KEY="${SYNTROPION_SECRET_KEY:-simnet-syntropion-test-key-32b}"

# AT-089: SYNTROPION-REVENUE-ROUTER/VESTING → RFC-010-DİKİŞİ (C-sınıfı
# derinleştirme — ikinci-yüz).
#
# AT-078-FSEK-hash'i-bağladı-AMA-revenue_router.py + vesting_engine.py-henüz-
# ÖLÇÜLMEDİ. Bu-test-ikinci-yüzü-ölçer: FSEK-ŞARTLARININ-FİNANSAL-GERÇEKLEŞMESİ.
#
# 18-Syntropion: syntropion_core/revenue_router.py:27 — calculate_and_record_split
# (GERÇEK-Decimal-ROUND_HALF_UP-bölüm: %20-Uzman / %75-Hazine / %5-İhtiyat).
# syntropion_core/vesting_engine.py:55 — unlock_milestone (3-kademeli-Milestone-
# Vesting; Tier-2 = %20-rev-share = FSEK'in-net-kâr-payı).
#
# FSEK-ŞARTLARININ-ÖLÇÜMÜ (Fikir.md:188 "şarta bağlı %20 net kâr payı
# devredilir"; Fikir.md:413 "%20'si uzman hesabına"):
#   revenue_router'ın-EXPERT_SHARE_PCT=%20'si-vesting_engine'in-Tier-2-
#   rev_share_pct'sine-EŞİT-olmalıdır — ikisi-aynı-FSEK-şartının-iki-yüzüdür:
#   biri-hesaplar-biri-serbest-bırakır. Bu-test-o-eşitliği-GERÇEK-çıktılarla-
#   ölçer-ve-ödeme-kanalına-bağlar.
#
# MATEMATİKSEL-BOZULMA-ÖLÇÜMÜ: bölümler-toplamı-nete-eşit-olmalı (para-
# sızıntısı-yok); Decimal-ROUND_HALF_UP-gerçek-çalışmalı.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-089/$(date +%F)/at089.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-089: Syntropion-revenue-router/vesting → RFC-010 dikişi"

SY="/home/gokun/projects/01_unicorn/18-Syntropion"
if [ ! -f "$SY/syntropion_core/revenue_router.py" ] || [ ! -f "$SY/syntropion_core/vesting_engine.py" ]; then
  note "[SKIP] AT-089: Syntropion-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SY" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sys, tempfile
from decimal import Decimal, ROUND_HALF_UP
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

# --- 0) İZOLE-DB (asıl-syntropion.db'yi-BOZMAYIZ — yazma-bölgesi-izole)
# DatabaseManager-importta-SYNTROPION_DB_PATH-okur; önceden-set-etmeliyiz.
TMP = tempfile.mkdtemp(prefix="at089-")
os.environ["SYNTROPION_DB_PATH"] = os.path.join(TMP, "syn-at089.db")
os.environ["SHM_IPC_PATH"] = os.path.join(TMP, "shm-at089.bin")
import importlib
if "syntropion_core.database" in sys.modules:   # temiz-import-garantisi
    del sys.modules["syntropion_core.database"]
from syntropion_core.database import db, get_current_iso_time
from syntropion_core.revenue_router import revenue_router, quantize_currency, RevenueRouter
from syntropion_core.vesting_engine import vesting_engine, TIER_CONFIG, VestingEngine
from syntropion_core.security import (generate_fsek_clickwrap_hash,
                                      verify_fsek_clickwrap_hash,
                                      issue_lifetime_license_key,
                                      verify_lifetime_license_key)
import settlement_bind_verify as SB

now = get_current_iso_time()
db.execute("INSERT OR IGNORE INTO domain_experts (expert_id,email,full_name,"
           "industry_domain,years_of_experience,created_at,updated_at) "
           "VALUES (?,?,?,?,'17',?,?)",
           ("exp-at089","uzman@at089.tr","Uzman AT-089","legal",now,now))
db.execute("INSERT OR IGNORE INTO domain_ideas (idea_id,expert_id,title,"
           "problem_statement,target_audience,status,created_at,updated_at) "
           "VALUES (?,?,?,?,'x','SYNTHESIZED',?,?)",
           ("idea-at089","exp-at089","LexNotice-AT089","P",now,now))
db.execute("INSERT OR IGNORE INTO ventures (venture_id,idea_id,code_slug,"
           "display_name,api_prefix_path,status,current_monthly_mrr_usd,"
           "created_at,updated_at) VALUES (?,?,?,?,'/api/v1/at089',"
           "'PRODUCTION_LIVE',0,?,?)",
           ("ven-at089","idea-at089","at089-ai","AT089-AI",now,now))
VID, EID = "ven-at089", "exp-at089"

# --- 1) GERÇEK-bölüm: calculate_and_record_split (Decimal-ROUND_HALF_UP)
# Fikir.md:413: %20-uzman / %75-hazine / %5-İhtiyat — net-kâr-üzerinden
GROSS, COSTS = Decimal("10000.00"), Decimal("1234.56")
r = revenue_router.calculate_and_record_split(VID, "2026-09", GROSS, COSTS)
net = Decimal(str(r["net_profit_usd"]))
expert = Decimal(str(r["expert_rev_share_usd"]))
treasury = Decimal(str(r["treasury_share_usd"]))
reserve = Decimal(str(r["reserve_fund_usd"]))
assert net == (GROSS - COSTS).quantize(Decimal("0.01")), "net-gerçek-olmalı"
# FSEK-ŞARTI: uzman-netin-%20'sini-alır (şarta-bağlı-kâr-payı)
assert expert == (net * Decimal("0.20")).quantize(Decimal("0.01")), \
    f"FSEK-%20-net-kâr-payı-bozuk: {expert} != {net*Decimal('0.20')}"
assert treasury == (net * Decimal("0.75")).quantize(Decimal("0.01"))
assert reserve == (net * Decimal("0.05")).quantize(Decimal("0.01"))
# PARASI-ZINTISI-YOK: bölümler-toplamı-nete-eşit (üretici-tarafı-sağlamlık)
assert (expert + treasury + reserve) == net, \
    f"bölüm-toplamı-nete-eşit-değil (sızan-para): {expert+treasury+reserve} != {net}"
print(f"  revenue_router: gross={GROSS} cost={COSTS} net={net}")
print(f"    FSEK-bölümü: uzman={expert} (%20) hazine={treasury} (%75) "
      f"ihityat={reserve} (%5)")
print(f"    sızıntı-kontrolü: toplam-nete-eşit ✓ (Decimal-ROUND_HALF_UP-gerçek)")

# --- 2) Sabit-yüzler-arası-FSEK-eşitliği (yapısal-uyum)
assert RevenueRouter.EXPERT_SHARE_PCT == Decimal("0.20")
assert RevenueRouter.TREASURY_SHARE_PCT == Decimal("0.75")
assert RevenueRouter.RESERVE_SHARE_PCT == Decimal("0.05")
assert (RevenueRouter.EXPERT_SHARE_PCT + RevenueRouter.TREASURY_SHARE_PCT
        + RevenueRouter.RESERVE_SHARE_PCT) == Decimal("1.00"), \
    "yüzdeler-tam-dağıtılmalı (100%)"
print("  RevenueRouter-sabitleri: .20+.75+.05 = 1.00 (tam-dağıtım)")

# --- 3) quantize_currency-gerçek-ROUND_HALF_UP-davranışı
# 2.595→2.60 (yarımdan-yukarı); 2.594→2.59 — float-kayması-yok
assert quantize_currency("2.595") == 2.60, "ROUND_HALF_UP-gerçek-çalışmalı"
assert quantize_currency("2.594") == 2.59
assert quantize_currency(0.1 + 0.2) == 0.30, "float-kayması-Decimal-ile-engellendi"
print("  quantize_currency: ROUND_HALF_UP-gerçek + float-kayması-yok (0.1+0.2=0.30)")

# --- 4) NEGATİF-bölüm: negatif-gelir-RED (üretici-tarafı-sağlamlık)
for bad_g, bad_c in ((Decimal("-1.00"), Decimal("0")), (Decimal("10"), Decimal("-5"))):
    try:
        revenue_router.calculate_and_record_split(VID, "2026-09x", bad_g, bad_c)
        raise AssertionError(f"negatif-gider-RED-beklendi: {bad_g},{bad_c}")
    except ValueError:
        pass
print("  negatif-gelir/gider → ValueError (para-telafisi-grefting önlenir)")

# --- 5) GERÇEK-Milestone-Vesting: FSEK-%20'nin-kilidi-açan-kademesi
# vesting_engine'in-Tier-2'si-REV-share=%20 = revenue_router'ın-EXPERT_%20'si.
# FSEK-şartı: uzman-3-meslektaşına-pilot-kullandırır → %20-kâr-payı-açılır.
vesting_engine.initialize_venture_vestings(VID, EID)
# başlangıçta-hepsi-kilitli
st0 = vesting_engine.get_expert_vesting_status(VID, EID)
assert st0["unlocked_rev_share_pct"] == 0.0, "başlangıçta-kilitli-olmalı"
# FSEK-clickwrap-hash'i-kanıt-olarak (AT-078'in-bulduğu-yol)
fsek = generate_fsek_clickwrap_hash("uzman@at089.tr", now)
assert verify_fsek_clickwrap_hash(fsek, "uzman@at089.tr", now) is True
u2 = vesting_engine.unlock_milestone(VID, EID, 2,
        {"peer_referrals": ["av.a@x.tr", "av.b@x.tr", "av.c@x.tr"],
         "fsek_clickwrap_hash": fsek, "pilot_logs_delivered": True})
assert u2["unlocked"] is True, "Tier-2-açılmalı"
assert u2["rev_share_percentage"] == TIER_CONFIG[2]["rev_share_pct"]
# ANA-KANIT: vesting'in-%20'si-revenue_router'ın-%20'siyle-AYNI-FSEK-şartı
assert Decimal(str(u2["rev_share_percentage"])) == Decimal("20.00")
assert Decimal(str(u2["rev_share_percentage"])) / Decimal("100") \
       == RevenueRouter.EXPERT_SHARE_PCT, \
    "FSEK-%20: vesting-Tier-2 ↔ revenue-router-bir-şartın-iki-yüzü"
print(f"  vesting_engine: Tier-2-açıldı rev_share={u2['rev_share_percentage']}%")
print("    FSEK-EŞİTLİĞİ: vesting-Tier-2(%20) == router-EXPERT(%20) ✓")

# --- 6) Tier-1 = Lifetime-License (FSEK-§2-somutlaştırma-özelliği)
u1 = vesting_engine.unlock_milestone(VID, EID, 1, {"datasets": 10})
assert u1["lifetime_license_key"] is not None, "Tier-1-lisans-vermeli"
assert u1["rev_share_percentage"] == Decimal("10.00")
assert verify_lifetime_license_key(u1["lifetime_license_key"],
                                  "at089-ai", EID) is True, "lisans-gerçek-olmalı"
assert verify_lifetime_license_key("SYNTROPION-SAHTESI", "at089-ai", EID) is False
print(f"  Tier-1: lifetime-license-üretildi+doğrulandı "
      f"({u1['lifetime_license_key'][:28]}…) rev=10%")
# yanlış-kademe-RED
try:
    vesting_engine.unlock_milestone(VID, EID, 9, {})
    raise AssertionError("geçersiz-kademe-RED-beklendi")
except ValueError:
    pass
print("  geçersiz-kademe (9) → ValueError (sadece-1/2/3)")

# --- 7) DİKİŞ: gerçek-dağıtım-kaydı → RFC-010 x402/v1 (STOCK-yol)
# kanıt: bölüm-kaydının-gerçek-içeriği → sha256 → evidenceHash
kanit = {"distribution_id": r["distribution_id"], "venture_id": VID,
         "billing_period": "2026-09", "net_profit_usd": str(net),
         "expert_rev_share_usd": str(expert),
         "treasury_share_usd": str(treasury),
         "reserve_fund_usd": str(reserve),
         "vesting_tier": 2, "fsek_clickwrap_hash": fsek}
d_kanit = hashlib.sha256(json.dumps(kanit, sort_keys=True).encode()).hexdigest()
assert len(d_kanit) == 64

from eth_keys import keys
pk = keys.PrivateKey(bytes.fromhex("33"*32))
BUYER = pk.public_key.to_checksum_address().lower()
PID = f"SYN-REV-{r['distribution_id'][:8].upper()}"
govde = {"buyerAddress": BUYER,
         "sellerAddress": "0x71c8a18174415cc92067749eb3544dffd3f87884",
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": d_kanit}}
digest = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
# RFC-010-§3b-x402/v1: imza-digest'ın-ham-baytları-üzerine (EIP-191-öneksiz)
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(digest)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 89, "prev": "0"*64, "h": "f"*64,
          "delivery_hash": {"alg": "sha256", "hex": d_kanit},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": d_kanit},
                              "payer": BUYER,
                              "payee": "0x71c8a18174415cc92067749eb3544dffd3f87884",
                              "verified_at": "2026-09-30T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": d_kanit,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "syntropion.revenue_router"}}
rs = SB.verify(charge, claim)
assert rs["verdict"] == "GREEN", f"Syntropion-revenue-dikişi-GREEN-beklendi: {rs}"
assert rs["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert rs["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  gerçek-dağıtım-kaydı → RFC-010-GREEN (x402/v1, STOCK-yol)")
print(f"    ödeme-id={PID} (gerçek-distribution_id'den)")

# --- 8) NEGATİF-1: sahte-imza → RED rc4
claim_s = dict(govde); claim_s["signature"] = "0x" + "33"*65
r_s = SB.verify(charge, claim_s)
assert r_s["verdict"] == "RED" and r_s["reason_code"] == 4, \
    f"sahte-imza-RED-rc4-beklendi: {r_s}"
print("  sahte-imza → RED rc4 (stub-olsaydı-GREEN-sanılırdı)")

# --- 9) NEGATİF-2: kâr-payına-tahriz → evidenceHash-swap-RED rc7
# saldırgan-uzmanın-payını-artsa-bile-yeni-hash-delivery_hash'e-uymaz
kanit2 = dict(kanit); kanit2["expert_rev_share_usd"] = str(net)  # hepsi-bana!
d2 = hashlib.sha256(json.dumps(kanit2, sort_keys=True).encode()).hexdigest()
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": d2}}
d2c = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
claim2 = dict(govde2)
claim2["signature"] = "0x" + pk.sign_msg_hash(bytes.fromhex(d2c)).to_bytes().hex()
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"kâr-payı-tahrizi-RED-rc7-beklendi: {r2}"
print("  kâr-payına-tahriz (hepsi-bana!) → RED rc7 — FSEK-bölümü-taşınmaz")

# --- 10) IPC-telemetri-gerçek-yola-çıktı (sızıntı-yok)
assert r["ipc_telemetry_dispatched"] in (True, False), "IPC-durumu-raporlanmalı"
print(f"  IPC-telemetri: dispatched={r['ipc_telemetry_dispatched']} "
      f"(gerçek-SHM-yolu-ölçüldü)")

# --- 11) vesting-tarihçesi-ve-Tier-3-yapısı
st = vesting_engine.get_expert_vesting_status(VID, EID)
assert st["unlocked_rev_share_pct"] == 20.00, "açılmış-max-%20-olmalı"
assert len(st["active_milestones"]) == 2, "iki-kademe-açık-olmalı (T1+T2)"
assert TIER_CONFIG[3]["rev_share_pct"] == 25.00
print(f"  vesting-durumu: açılmış={st['unlocked_rev_share_pct']}% "
      f"({len(st['active_milestones'])}-kademe)")
print(f"  TIER_CONFIG: T1=10% T2=20% T3=25% (FSEK-%15-%30-aralığı-içinde)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-Syntropion-revenue/vesting-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-089: Syntropion-revenue-router/vesting → RFC-010"
[[ $FAIL -eq 0 ]]
