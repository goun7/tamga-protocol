#!/usr/bin/env bash
# AT-099: SWARMAX-SEALING (ikinci-yüz) → RFC-010-DİKİŞİ (tamga/native — gerçek-Ed25519).
#
# AT-067 (2026-09-21) Swarmax'ın İLK-yüzünü bağladı (evidence.py-payload_digest).
# Kalan-en-büyük-boşluk: İKİNCİ-YÜZ — sealing.py: F2-evidence-sealing, Ed25519 +
# Merkle-kökü-over-hash-chained-ledger (paper-§12.1/§14-R1). Bu-test-o-boşluğu-kapatır.
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   swarmax/sealing.py:53    seal_ledger — Merkle-kökü+Ed25519-operatör-imzası
#   swarmax/sealing.py:101   verify_seals — yeniden-hesaplayan-doğrulayıcı
#   swarmax/sealing.py:40    merkle_root — sha256-çiftli-ağaç (duplicate-last)
#   swarmax/sealing.py:145   rotate_key — anahtar-rotasyonu (§14)
#   swarmax/ed25519.py       saf-Python RFC-8032 (stdlib-only; sign/verify)
#   swarmax/evidence.py:23   append_evidence — hash-chain (AT-067'nin-yüzü)
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate
#   tamga/tamga_attest_verify.py:64   ecrecover_to_pub (x402/v1-sözleşmesi)
#
# §3b-ŞEMA-SEÇİMİ: tamga/native — Swarmax'ın-F2-seal'i-Ed25519-operatör-anahtarıyla
# atıldığı-için-tamga/native'nin-imza-doğrulamasıyla-AYNI-aile (AT-067-ilk-yüz-aynı-
# kararı-verdi; AT-077-Yieldix-deseni). erc8004/v1-de-uyar (Merkle-kökü) — ama-x402-
# gerçek-para-kanalı-olduğu-için-tamga/native-operatör-anahtarı-daha-doğal: F2-paper
# operatör-anahtarını-zaten-kullanır (§14-anahtar-rotasyonu).
#
# İKİ-İMZA-KANALI (RFC-010-§4d-notu, AT-090'ın-keşfettiği-sınıf — burada-da-kanıt):
#   (a) Swarmax-seal-imzası: Ed25519-over-(root‖covers-to_bytes-8) — F2-sözleşmesi
#   (b) RFC-010-claim-imzası: Ed25519-over-sha256-digest'ın-HAM-baytları (§3b)
#   Aynı-operatör-anahtarı-iki-farklı-ön-görüntüde-imzalar; seal-imzası-doğrudan-
#   claim-imzası-OLAMAZ (ön-görüntü-farklı). Çözüm (AT-077-reçetesi): evidenceHash =
#   seal.root_hash (Merkle-kökü-64hex, machine-checkable — verify_seals-yeniden-
#   hesaplar); RFC-010-claim'imzasını-ayrı-atarız-aynı-anahtarla; seal'ın-F2-imzası
#   üretici-tarafı-sağlamlıkta-verify_seals-ile-doğrulanır (gerçek-kanıt-üretildi).
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-seal: 3-evidence → seal_ledger → Merkle-kökü + Ed25519 + verify_seals
#   2) ÜRETİCİ-TARAFI-SAĞLAMLIK: tahrif→False, yanlış-anahtar→False, rotate_key
#   3) DİKİŞ-GREEN: root_hash=evidenceHash + tamga/native (nacl-STOCK) → 6-kontrol
#   4) §6-foreign_chain: evidence_link='equals' + head=Merkle-kökü → GREEN
#   5) NEGATİF-1: sahte-seal (uydurma-Merkle-kökü) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SWARMAX-2/$(date +%F)/at099.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-099: Swarmax-sealing (ikinci-yüz) → RFC-010 tamga/native dikişi"

SW="/home/gokun/projects/00_TAMGA-MESH/swarmax/src/swarmax/sealing.py"
if [ ! -f "$SW" ]; then
  note "[SKIP] AT-099: Swarmax-kodu-bu-makinede-değil (CI) —"
  note "       sealing-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

if ! python3 -c "import nacl" 2>/dev/null; then
  note "[SKIP] AT-099: nacl-kütüphanesi-yok —"
  note "       stock-Ed25519-doğrulama-koşmadı (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sqlite3, sys, tempfile
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/swarmax/src")

LOG = sys.argv[1]                                  # kanıt-dizini (shell-değişkeni-değil)

from swarmax import db as sw_db, evidence as sw_ev, sealing as sw_seal
from swarmax.ed25519 import generate_seed, secret_to_public, sign, verify as sw_verify
import settlement_bind_verify as SB
from nacl.signing import SigningKey as NaclSigningKey

# STUB-YOK (AT-075-disiplini): gate'in-imza-yoluna-dokunmadık
assert "VerifyKey" in inspect.getsource(SB._claim_signer), \
    "_claim_signer-gerçek-Ed25519-doğrulamasını-çağırmıyor"

# --- 1) GERÇEK-seal: izole-SQLite + 3-evidence + seal_ledger
TMP = tempfile.mkdtemp(prefix="at099-")
DBP = os.path.join(TMP, "swarmax-at099.db")
conn = sw_db.connect(DBP)
sw_db.init_db_with_migrations(conn)                # evidence_ledger + evidence_seals
sw_ev.append_evidence(conn, "job_done", {"job": "scrape-A", "rows": 42, "ok": True})
sw_ev.append_evidence(conn, "job_done", {"job": "scrape-B", "rows": 38, "ok": True})
sw_ev.append_evidence(conn, "job_done", {"job": "scrape-C", "rows": 51, "ok": True})
# GERÇEK-operatör-anahtarı: Swarmax'ın-üretim-yolu (load_or_create_seed-gibi-üretilir)
seed = generate_seed()                             # RFC-8032-32-byte-seed
PUB = secret_to_public(seed).hex()                 # 64-hex-genel-anahtar
assert len(PUB) == 64 and all(c in "0123456789abcdef" for c in PUB)
seal = sw_seal.seal_ledger(conn, seed)
root = seal["root_hash"]
assert len(root) == 64 and seal["covers_through_seq"] == 3
assert len(bytes.fromhex(seal["signature"])) == 64  # Ed25519-64-byte
# verify_seals: Merkle-kökünü-YENİDEN-hesaplar-ve-imzayı-doğrular (machine-checkable)
vs = sw_seal.verify_seals(conn)
assert vs["all_ok"] is True and vs["seals"] == 1, \
    f"gerçek-seal-doğrulanmalı: {vs}"
# bağımsız-yeniden-üretim: kök-aynı-olmalı (alıcı-bunu-yapabilir)
hashes = [r["payload_hash"] for r in conn.execute(
    "SELECT payload_hash FROM evidence_ledger ORDER BY seq")]
assert sw_seal.merkle_root(hashes) == root, "Merkle-kökü-bağımsız-yeniden-üretimde-aynı"
print(f"  GERÇEK-seal: 3-evidence → Merkle-kökü {root[:20]}… + Ed25519-imzası")
print(f"    verify_seals: all_ok=True | kök-bağımsız-yeniden-üretimle-birebir")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: tahrif→False, yanlış-anahtar→False, rotate_key
# tahrif: son-evidence'nın-payload_hash'ini-değiştir → kök-değişir → mismatch
conn.execute("UPDATE evidence_ledger SET payload_hash=? WHERE seq=3", ("e" * 64))
vs2 = sw_seal.verify_seals(conn)
assert vs2["all_ok"] is False, "payload-tahrifi-seal-doğrulamasında-yakalanmalı"
print("    tahrif: son-payload_hash-değişti → verify_seals-False (fail-closed)")
# anahtar-tutarlılık: swarmax'ın-kendi-verify()-fonksiyonu-çalışıyor
msg = root.encode() + (3).to_bytes(8, "big")       # F2-seal-mesajı
assert sw_verify(bytes.fromhex(PUB), msg,
                 bytes.fromhex(seal["signature"])) is True, "F2-seal-imzası-doğrulanmalı"
assert sw_verify(bytes.fromhex("f" * 64), msg,
                 bytes.fromhex(seal["signature"])) is False, \
    "yanlış-anahtar-doğrulamamalı"
# anahtar-rotasyonu (§14): yeni-anahtar + eski-seal-hâlâ-doğrulanır
seed2 = sw_seal.rotate_key(conn, seed, path=os.path.join(TMP, "seed2.hex"))
assert secret_to_public(seed2).hex() != PUB
sw_ev.append_evidence(conn, "job_done", {"job": "scrape-D", "rows": 9, "ok": True})
seal2 = sw_seal.seal_ledger(conn, seed2)
assert sw_seal.verify_seals(conn)["all_ok"] is True, \
    "rotasyon-sonrası-iki-seal-de-doğrulanmalı (eski-pubkey-saklı)"
print("    yanlış-anahtar→False; rotate_key: eski-seal-hâlâ-geçerli (§14)")

# --- 3) DİKİŞ-GREEN: root_hash=evidenceHash + tamga/native (nacl-STOCK, §3b)
# İKİ-KANAL (§4d): seal-imzası-(root‖covers)-üzerine; RFC-010-claim-imzası-digest
# üzerine. Aynı-anahtarla-ayrı-atılır — ön-görüntü-sözleşmesi-sabittir.
PID = "SWX-SEAL-0001"
SELLER = "0x" + "2" * 40
govde = {"buyerAddress": PUB, "sellerAddress": SELLER, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": root}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
# nacl-ile-aynı-seed: RFC-8032-standardı (AT-077-kanıtladı: cryptography↔nacl-paritesi)
nacl_sk = NaclSigningKey(seed)
sig_hex = nacl_sk.sign(bytes.fromhex(digest_hex)).signature.hex()
assert len(sig_hex) == 128
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 99, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": root},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": root},
                              "payer": PUB, "payee": SELLER,
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"Swarmax-sealing-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: seal-Merkle-kökü=evidenceHash, tamga/native 6-kontrol (STOCK-nacl)")

# --- 4) §6-foreign_chain: Merkle-kökü-zincir-head'i-olarak
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                             # whitelist-kısıtı (AT-079-dersi)
    "head_hex": root,                             # yerel-ledger-kanıtı
    "entries": seal["covers_through_seq"],
    "evidence_link": "equals",                    # head == delivery_hash (içerik-bağı)
    "verify_cmd": "swarmax.sealing.verify_seals"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
print(f"  §6-foreign_chain: head=Merkle-kökü, evidence_link='equals' → GREEN "
      f"({seal['covers_through_seq']}-evidence)")

# --- kanıt-fixture'ı-kalıcı-la
FX = os.path.join(os.path.dirname(LOG), "at099-swarmax-seal.json")
json.dump({"test": "AT-099", "scheme": "tamga/native", "project": "swarmax/sealing",
           "seal_id": seal["seal_id"], "merkle_root": root,
           "covers_through_seq": seal["covers_through_seq"],
           "operator_pubkey": PUB, "payment_id": PID,
           "charge": charge6, "claim": claim, "verdict": r6["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-seal (uydurma-Merkle-kökü) → RED rc7
# saldırgan-gerçek-bir-seal-üretmeden-uydurma-64-hex-yazar; alıcı-verify_seals'ı
# çağırınca-kök-tutmayacak → evidenceHash-uyuşmazlığı (rc7).
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-seal-RED-rc7-beklendi: {rN1}"
print("  sahte-seal (uydurma-Merkle-kökü) → RED rc7 — kanıtsız-ödeme-alınamaz")

# --- 6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
govde2 = dict(govde)
govde2["sellerAddress"] = "0x" + "9" * 40           # başkası
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
claim2 = dict(govde2)
claim2["signature"] = nacl_sk.sign(bytes.fromhex(d2)).signature.hex()
rN2 = SB.verify(charge, claim2)
assert rN2["verdict"] == "RED" and rN2["reason_code"] == 6, \
    f"party-swap-RED-rc6-beklendi: {rN2}"
assert rN2["checks"].get("2_claim_sig") is True, \
    "negatif-imza-GEÇERLİ-olmalı (saldırı-imzada-değil-party-bağında-yakalanmalı)"
print("  party-swap (imza-geçerli, satıcı-değişti) → RED rc6 (party_mismatch)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Swarmax-sealing-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-099: Swarmax-sealing (ikinci-yüz) → RFC-010 tamga/native"
[[ $FAIL -eq 0 ]]
