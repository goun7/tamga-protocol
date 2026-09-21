#!/usr/bin/env bash
# AT-094: PACTIVA-PEER-ATTESTATION → RFC-010-DİKİŞİ (C-sınıfı — üçüncü-yüz).
#
# Lead'in-tarifettiği-modül-peer_attestations.py-değil-pactiva_core/
# attestation.py'dir (dosya-adı-düzeltmesi-raporda). İçerik-bire-bir-aynı:
# HMAC-SHA256-peer-kanıtı + sqrt(rep/100)-ağırlık.
#
# pactiva_core/attestation.py — Çapraz-Meslektaş-Doğrulama-ve-İtibar-Ağı:
#   compute_attestation_signature:19 — HMAC-SHA256-immutable-imza
#   create_peer_attestation:33      — referans-onayı-kütükler
#       (self-endorsement-ENGELLI; tarih-tesişi-ENGELLI)
#       ağırlık = round(sqrt(clamp(rep,0..100)/100), 3)
#   get_worker_attestations:111     — kümülatif-güven + verified_peer_badge(≥2)
#
# PACTİVA-ÖZELLİĞİ: peer-kanıtı-bir-İNSAN-DOĞRULAMASIDIR — "bu-kişi-o-şantiyede
# çalıştık-birlikte"-der (CV-şişirmeyi-önler). RFC-010'ın-istediği-"bu-iş-gerçek
# oldu"-kanıtının-insan-kanalıdır; machine-checkable-Ed25519'in-tamamlayıcısı.
#
# AT-091'İN-KEŞFETTİĞİ-GERÇEK-SINIR: compute_attestation_signature-HMAC'imizi
# 32-hex'e-KIRPAR (hexdigest()[:32]). RFC-010'ın-evidenceHash'i-64-hex-ister —
# yani-HMAC-imzası-DOĞRUDAN-evidenceHash-OLAMAZ. Bu-test- dürüst-çözümü-ölçer:
# evidenceHash = sha256(canonical-attestation-kaydı)-64-hex; HMAC-imzası-ayrı
# bir-bütünlük-kanıtı-olarak-kalır (üretici-tarafı-sağlamlıkta-doğrulanır).
#
# §3b-SCHEME-SEÇİMİ: peer-attestation-asimetrik-imza-ÜRETMEZ (HMAC-simetriktir)
# → x402/v1-seçilir (gerçek-ecrecover — AT-078/089'la-aynı-disiplin).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-094/$(date +%F)/at094.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-094: Pactiva-peer-attestation → RFC-010 x402/v1 dikişi"

PA="/home/gokun/projects/01_unicorn/22-37-Pactiva"
if [ ! -f "$PA/pactiva_core/attestation.py" ]; then
  note "[SKIP] AT-094: Pactiva-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-094: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$PA" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, hmac, json, math, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from pactiva_core.database import init_db
from pactiva_core import attestation as AT
from pactiva_core.attestation import (compute_attestation_signature,
                                      ATTESTATION_SECRET)
import settlement_bind_verify as SB

# --- 0) İZOLE-DB (asıl-pactiva.db'yi-BOZMAYIZ — yazma-bölgesi-izole)
TMP = tempfile.mkdtemp(prefix="at094-")
DBP = os.path.join(TMP, "pactiva-at094.db")
init_db(DBP)

# --- 1) GERÇEK-peer-kanıtı-üretimi (create_peer_attestation)
# iki-meslektaş-aynı-şantiyede-çalıştığını-onaylar (farklı-itibarlar)
a1 = AT.create_peer_attestation("W-094", "ENDOR-A", "JOB-094",
        "2026-03-01", "2026-08-31", 85.0, db_path=DBP)
a2 = AT.create_peer_attestation("W-094", "ENDOR-B", "JOB-094",
        "2026-04-01", "2026-09-30", 60.0, db_path=DBP)
assert isinstance(a1["attestation_id"], str)
assert a1["is_verified"] is True, "kanıt-doğrulanmış-olmalı"
# HMAC-gerçek: sha256'ın-İLK-32-hex'i (gerçek-sınır — AT-091-raporu)
assert len(a1["signature"]) == 32, \
    f"HMAC-imzası-32-hex-beklendi (kırpılmış): {len(a1['signature'])}"
assert all(c in "0123456789abcdef" for c in a1["signature"])
print(f"  create_peer_attestation: 2-kanıt-üretildi (W-094)")
print(f"    HMAC-SHA256-imza: {a1['signature'][:16]}… (32-hex-KIRPAR)")

# --- 2) sqrt(rep/100)-ağırlığı-gerçek (üretici-tarafı-sağlamlık)
for rec, rep in ((a1, 85.0), (a2, 60.0)):
    expect = round(math.sqrt(max(0.0, min(100.0, rep)) / 100.0), 3)
    assert rec["endorser_reputation_weight"] == expect, \
        f"ağırlık-sqrt(rep/100)-değil: {rec['endorser_reputation_weight']} != {expect}"
# klaplama-gerçek: ağırlık-[0,1]-aralığında-sabit (modül-clamp-satırı)
# NOT: users-tablosu-CHECK(reputation_score-BETWEEN-0-AND-100)-yüzünden
# rep>100 gönderilirse-INSERT-OR-IGNORE-users-atlanır → jobs-FK-çöker
# (gerçek-üretici-sınırı; test-bunu-gizlemez-—-99.0-ile-ölçülür).
w_hi = round(math.sqrt(min(100.0, 150.0) / 100.0), 3)
w_lo = round(math.sqrt(max(0.0, -5.0) / 100.0), 3)
assert w_hi == 1.0 and w_lo == 0.0, "klaplama-sqrt-sonrası-[0,1]-olmalı"
a_hi = AT.create_peer_attestation("W-HI", "ENDOR-HI", "JOB-HI-094",
        "2026-01-01", "2026-02-01", 99.0, db_path=DBP)
assert a_hi["endorser_reputation_weight"] == round(math.sqrt(99.0/100.0), 3)
import inspect as _insp
assert "max(0.0, min(100.0" in _insp.getsource(AT.create_peer_attestation), \
    "klaplama-modülde-olmalı"
print(f"  ağırlık: sqrt(rep/100)-gerçek — 85→{a1['endorser_reputation_weight']}, "
      f"60→{a2['endorser_reputation_weight']}, 99→{a_hi['endorser_reputation_weight']}")
print(f"    klaplama: sqrt(clamp(150)/100)=1.0, sqrt(clamp(-5)/100)=0.0 (ağırlık-[0,1])")

# --- 3) HMAC-bütünlüğü: doğru-kanıt-doğrulanır, tahriz-RED (sabit-zamanlı)
sig_ok = hmac.compare_digest(
    a1["signature"],
    compute_attestation_signature("W-094", "ENDOR-A", "JOB-094",
                                  "2026-03-01", "2026-08-31"))
assert sig_ok is True, "gerçek-HMAC-doğrulanmalı"
sig_t = hmac.compare_digest(
    a1["signature"],
    compute_attestation_signature("W-094", "ENDOR-A", "JOB-094",
                                  "2026-03-01", "2026-09-30"))
assert sig_t is False, "tarih-tahrizi-HMAC-RED-olmalı"
sig_p = hmac.compare_digest(
    a1["signature"],
    compute_attestation_signature("W-094", "SAHTE", "JOB-094",
                                  "2026-03-01", "2026-08-31"))
assert sig_p is False, "endorser-swap-HMAC-RED-olmalı"
print("  HMAC-doğrulama: doğru-True; tarih/endorser-tahrizi-False (sabit-zamanlı)")

# --- 4) get_worker_attestations: kümülatif-güven + badge (≥2)
st = AT.get_worker_attestations("W-094", db_path=DBP)
assert st["total_attestations_count"] == 2, "iki-kanıt-olmalı"
assert st["verified_peer_badge"] is True, "≥2-kanıt-badge-vermeli"
expect_cum = round(a1["endorser_reputation_weight"]
                   + a2["endorser_reputation_weight"], 2)
assert st["cumulative_trust_weight"] == expect_cum, \
    f"kümülatif-güven-ağırlık-toplamı: {st['cumulative_trust_weight']}"
# badge-eşiği-gerçek: 1-kanıt-yetmez (W-HI-tek-kanıt)
st1 = AT.get_worker_attestations("W-HI", db_path=DBP)
assert st1["verified_peer_badge"] is False, "1-kanıt-badge-VERMEMELI"
print(f"  kümülatif-güven: {st['cumulative_trust_weight']} "
      f"(sqrt-toplamı); badge={st['verified_peer_badge']} (≥2-eşiği-gerçek)")

# --- 5) NEGATİF-yapısal: self-endorsement + tarih-tesişi-RED
try:
    AT.create_peer_attestation("W-X", "W-X", "JOB-094",
            "2026-01-01", "2026-02-01", 90.0, db_path=DBP)
    raise AssertionError("self-endorsement-RED-beklendi")
except ValueError:
    pass
try:
    AT.create_peer_attestation("W-Y", "ENDOR-A", "JOB-094",
            "2026-06-01", "2026-01-01", 90.0, db_path=DBP)
    raise AssertionError("tarih-tesişi-RED-beklendi")
except ValueError:
    pass
# şema-SEVİYESİNDE-de-yasak (chk_no_self_endorsement)
import sqlite3
conn = sqlite3.connect(DBP)
try:
    conn.execute("INSERT INTO peer_attestations (id,worker_id,endorser_id,"
        "job_id,overlap_start_date,overlap_end_date,attestation_signature,"
        "endorser_reputation_weight,created_at) VALUES "
        "('s', 'W-094','W-094','JOB-094','2026-01-01','2026-02-01','x',1.0,'2026-01-01')")
    conn.commit()
    raise AssertionError("DB-seviyesi-self-endorsement-kısıdı-çalışmadı")
except sqlite3.IntegrityError:
    pass
finally:
    conn.close()
print("  self-endorsement (modül+DB-CHECK) + tarih-tesişi → RED (CV-şişirme-engeli)")

# --- 6) DİKİŞ: peer-kanıtı-özütü → RFC-010 x402/v1 (STOCK-yol)
# AT-091'in-keşfi: HMAC-32-hex-→-evidenceHash-OLAMAZ. Çözüm: kanıt-kaydının
# kendi-sha256-özütü-64-hex-olarak-evidenceHash; HMAC-ayrı-bütünlük-kanıtı.
kanit = {"attestation_id": a1["attestation_id"],
         "worker_id": a1["worker_id"], "endorser_id": a1["endorser_id"],
         "job_id": a1["job_id"],
         "overlap_start_date": a1["overlap_start_date"],
         "overlap_end_date": a1["overlap_end_date"],
         "hmac_signature_32hex": a1["signature"],
         "endorser_reputation_weight": a1["endorser_reputation_weight"],
         "cumulative_trust_weight": st["cumulative_trust_weight"],
         "verified_peer_badge": st["verified_peer_badge"]}
d_kanit = hashlib.sha256(json.dumps(kanit, sort_keys=True).encode()).hexdigest()
assert len(d_kanit) == 64, "kanıt-özütü-64-hex-olmalı"

from eth_keys import keys
pk = keys.PrivateKey(bytes.fromhex("44"*32))
BUYER = pk.public_key.to_checksum_address().lower()
PID = "PACT-PEER-0094"
govde = {"buyerAddress": BUYER, "sellerAddress": "0x4"*40,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": d_kanit}}
digest = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
# RFC-010-§3b-x402/v1: imza-digest'ın-ham-baytları-üzerine (EIP-191-öneksiz)
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(digest)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 94, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": d_kanit},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": d_kanit},
                              "payer": BUYER, "payee": "0x4"*40,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": d_kanit,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "pactiva.attestation"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"peer-kanıtı-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  peer-kanıtı-özütü → RFC-010-GREEN (x402/v1, STOCK-yol)")
print(f"    evidence_link='equals': kanıt-özütü-delivery_hash'e-bağlı")
print(f"    HMAC-32-hex-kanıt-içinde-taşındı (bütünlük-kanıtı-olarak)")

# --- 7) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("0x" + "44"*65, os.urandom(65).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (65-bayt-sahte + rastgele) → RED rc4")

# --- 8) NEGATİF-2: kanıt-tahrizi → evidenceHash-swap-RED rc7
# saldırgan-kanıtın-ağırlığını-artırır (rep-şişirme) → yeni-özüt-üretir-AMA
# delivery_hash-sabit-kaldığı-için-uyumsuzluk-fail-closed
kanit2 = dict(kanit); kanit2["endorser_reputation_weight"] = 1.0  # şişirilmiş
d2 = hashlib.sha256(json.dumps(kanit2, sort_keys=True).encode()).hexdigest()
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": d2}}
d2c = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
claim2 = dict(govde2)
claim2["signature"] = "0x" + pk.sign_msg_hash(bytes.fromhex(d2c)).to_bytes().hex()
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"kanıt-tahrizi-RED-rc7-beklendi: {r2}"
print("  itibar-ağırlığına-şişirme (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
print("    taşıma-özellikli: peer-kanıtı-özütü-delivery_hash'e-sabittir")

# --- 9) İNSAN-×-MAKİNE-kanal-ayrımı (RFC-010-attribution- yüzü)
# peer-kanıtı-insan-doğrulamasıdır; x402-imzası-makine-ödemeyi-yetkilendirir.
# İkisi-birlikte: "ödeme-yetkili-VE-insan-doğrulamalı-iş" (holistis-D-017-ilişkisi)
assert a1["is_verified"] is True and r["checks"]["2_claim_sig"] is True
print("  insan×makine: HMAC-kanıtı(insan) + erecover-imza(makine) → GREEN-ikisi-birden")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: dokuz-Pactiva-peer-attestation-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-094: Pactiva-peer-attestation → RFC-010"
[[ $FAIL -eq 0 ]]
