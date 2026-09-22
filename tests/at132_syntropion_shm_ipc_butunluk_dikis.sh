#!/usr/bin/env bash
# AT-132: SYNTROPION-BEŞİNCİ-YÜZ → RFC-010-DİKİŞİ (C-sınıfı — shm-IPC-bütünlüğü).
#
# 18-Syntropion: dört-yüz-bağlandı — AT-078 ( FSEK+escrow), AT-096 ( api/cli),
# AT-112 ( license-HMAC), AT-131 ( database.py-Merkle-audit-ledger). KALAN-YÜZ:
#   syntropion_core/shared_memory_ipc.py — SharedMemoryIPCBridge —
#     **zero-copy POSIX /dev/shm telemetry-köprüsü**: push_revenue_telemetry
#     ( :50) bir-paketin-SHA-256-özütünü üretir ( chksum=sha256(ts:slug:
#     gross:net:treasury)), struct-pack'leyip flock( LOCK_EX)-ile-atomik-yazar;
#     read_latest_telemetry ( :90) özütü-bağımsız-yeniden-hesaplayıp
#     checksum-valid-ile-doğrular ( tahriz-tespiti).
#
# BU-TESTİN-ÖZÜ: IPC-özütü bir CANLI-VERİ-KANITIDIR — "bu-anda-bu-venture-bu
# nakit-akışını-üretti"-der ( Project-15-NeoBank-Treasury'ye-sıfır-kopya).
# AT-131 tarihsel-olayları zincirlerken, bu-yüz ANLIK-telemetri-bütünlüğünü
# kriptografik-kanıta-dönüştürür. RFC-010 evidenceHash'ının-üçüncü-doğal-kaynağı.
#
# x402/v1-SÖZLEŞME (AT-080/AT-131-disiplini): imza-digest'ın-HAM-BAYTLARI
# üzerine-atılır ( sign_msg_hash; EIP-191'siz, z=raw-sha256). Test-double-YOK:
# gerçek-eth_keys-ecrecover + gerçek-SharedMemoryIPCBridge-gerçek-mmap'a-yazar.
#
# Altı-kanıt + 2-negatif:
#   1) gerçek-IPC-push ( izole-shm-dosyası; packet-128B; chksum-64hex; flock)
#   2) gerçek-IPC-read ( checksum-valid-True; değerler-birebir-round-trip)
#   3) tahriz-tespiti ( treasury-byte'ı-bozulunca-checksum-valid-False; kodun
#      LOCK_EX/LOCK_SH-atomiklik-yüzü-kaynak-kanıtı)
#   4) RFC-010-x402/v1-GREEN-dikiş ( gerçek-ecrecover; §6-syntropion-equals)
#   5) NEG-1: sahte-imza → RED rc4
#   6) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 (fail-closed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SYNTROPION-5/$(date +%F)/at132.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-132: Syntropion beşinci-yüz (shm-IPC-bütünlüğü) → RFC-010 dikişi"

SY="/home/gokun/projects/01_unicorn/18-Syntropion"
if [ ! -f "$SY/syntropion_core/shared_memory_ipc.py" ]; then
  note "[SKIP] AT-132: Syntropion-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-132: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SY" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, re, struct, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from syntropion_core.shared_memory_ipc import (SharedMemoryIPCBridge,
                                              PACKET_FORMAT, PACKET_SIZE)
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

# --- 1) GERÇEK-IPC-push (izole-shm-dosyası; üretim-modülü)
SLUG = "yapay-zeka-studyosu"
GROSS, NET, TREAS = 1234.50, 310.25, 50000.00
SHM = tempfile.mktemp(suffix="-at132.shm")
kaynak = open(sys.argv[1] + "/syntropion_core/shared_memory_ipc.py",
              encoding="utf-8").read()
assert "fcntl.flock" in kaynak and "LOCK_EX" in kaynak and "LOCK_SH" in kaynak, \
    "flock-atomiklik-yüzü-kaynakta-yok"
br = SharedMemoryIPCBridge(shm_path=SHM)
try:
    ok = br.push_revenue_telemetry(SLUG, GROSS, NET, TREAS)
    assert ok is True, "push-başarısız-döndü"
    assert PACKET_SIZE == 128, f"packet-128B-beklendi: {PACKET_SIZE}"
    # özütü-bağımsız-yeniden-üret ( push'un-ürünüyle-birebir):
    ts_cek = br.read_latest_telemetry()["timestamp"]
    ozut = hashlib.sha256(
        f"{ts_cek}:{SLUG}:{GROSS:.2f}:{NET:.2f}:{TREAS:.2f}".encode("utf-8")
    ).hexdigest()
    assert re.fullmatch(r"[0-9a-f]{64}", ozut), f"özüt-64hex-değil: {ozut}"
    print(f"  IPC-push-gerçek: packet-128B-chksum-64hex; flock(LOCK_EX)-atomik-"
          f"kaynakta; özüt={ozut[:16]}…")

    # --- 2) GERÇEK-IPC-read ( checksum-valid-True; birebir-round-trip)
    r = br.read_latest_telemetry()
    assert r is not None, "boş-buffer'dan-None"
    assert r["checksum_valid"] is True, "gerçek-paketin-özütü-doğrulanmadı"
    assert r["venture_slug"] == SLUG and r["gross_usd"] == GROSS \
        and r["net_profit_usd"] == NET and r["treasury_usd"] == TREAS, \
        "telemetri-değerleri-round-trip-bozuldu"
    print("  IPC-read-gerçek: checksum-valid-True; gross/net/treasury/slug-"
          "birebir-round-trip")

    # --- 3) TAHRİZ-TESPİTİ: treasury-byte'ı-bozulunca-özüt-artık-uymaz
    br._mmap_obj.seek(0)
    raw = br._mmap_obj.read(PACKET_SIZE)
    b2 = bytearray(raw)
    # treasury-double'ının-YÜKSEK-anlamlı-byte'ı-bozulursa-değer-çok-farklı
    # olur ( düşük-byte-xor .2f-yuvarlamasında-kaybolurdu — yüksek-byte-gerekli):
    b2[63] ^= 0x01  # treasury-double'ı-high-byte ( ofset-56..63)
    br._mmap_obj.seek(0)
    br._mmap_obj.write(bytes(b2)); br._mmap_obj.flush()
    rt = br.read_latest_telemetry()
    assert rt is not None and rt["checksum_valid"] is False, \
        "tahriz-edilen-paket-hâlâ-geçerli-sayıldı (bütünlük-çürük)"
    print("  tahriz-tespit: treasury-byte-xor → checksum-valid-False (özüt-"
          "yeniden-hesapla'ya-uymaz); LOCK_EX/LOCK_SH-atomiklik-kaynakta")

    # --- 4) RFC-010-x402/v1-GREEN-dikiş (gerçek-ecrecover, stock-yol)
    # IPC-özütü hem-evidenceHash hem-delivery hem-§6-zincir-kökü (equals).
    BUYER = ek.PrivateKey(os.urandom(32))
    ADDR = to_checksum_address(BUYER.public_key.to_address())
    govde = {"buyerAddress": ADDR, "sellerAddress": "0x2"*40,
             "settlementRef": "SYN-SHMIPC-132",
             "evidenceHash": {"alg": "sha256", "hex": ozut}}
    d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
    sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
    assert len(sig) == 132  # 0x+130-hex (r+s+v)
    claim = dict(govde); claim["signature"] = sig
    charge = {"seq": 1, "prev": "0"*64, "h": ozut,
              "delivery_hash": {"alg": "sha256", "hex": ozut},
              "settlement_bind": {"scheme": "x402/v1",
                                  "payment_id": "SYN-SHMIPC-132",
                                  "claim_evidence_hash": {"alg": "sha256", "hex": d},
                                  "payer": ADDR, "payee": "0x2"*40,
                                  "verified_at": "2026-09-22T00:00:00Z"},
              "foreign_chain_proof": {"chain": "syntropion", "head_hex": ozut,
                                      "entries": 1,
                                      "evidence_link": "equals",
                                      "verify_cmd":
                                          "syntropion_core.shared_memory_ipc"}}
    r4 = SB.verify(charge, claim)
    assert r4["verdict"] == "GREEN", f"shm-IPC-dikişi-GREEN-beklendi: {r4}"
    for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
              "5_evidence_hash", "6_foreign_chain"):
        assert r4["checks"].get(k) is True, f"{k}-geçmedi: {r4}"
    print(f"  IPC-telemetri-özütü → RFC-010-GREEN (x402/v1-gerçek-ecrecover; "
          f"6/6-kontrol; §6-syntropion-zinciri-equals-bağlı)")

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
    print("  BEŞİNCİ-YÜZ-BAĞLANDI: shared_memory_ipc.py-shm-bütünlüğü → RFC-010")
finally:
    br.close()
    if os.path.exists(SHM):
        os.unlink(SHM)
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Syntropion-shm-IPC-bütünlük-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-132: Syntropion beşinci-yüz (shm-IPC-bütünlüğü) → RFC-010"
[[ $FAIL -eq 0 ]]
