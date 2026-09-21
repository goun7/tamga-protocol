#!/usr/bin/env bash
# AT-115: UNPUMP ÜÇÜNCÜ-YÜZ — tamga_bind.finalize_bind() settlement-arka-yüzü.
#
# task-33 (gece-otonomu). AT-075 (X-Bind-Signature) + AT-081 (gerçek-müşteri-
# imzası) sonrası Unpump'ın-ölçülmemiş-iç-yüzü:
#   tamga_bind.py:115 finalize_bind() — bridge'in ARKA-YÜZÜ:
#     (1) D5-kapsama-düzeltmesi :177-185 — h-artık-Sester-hash'i-DEĞİL,
#         sha256(prev ‖ jcs(gövde-h-siz)) olmalı (üretim-fix 8cc75e9)
#     (2) payment_id-onarımı :208-229 — append-öncesi-None-gömülen-id,
#         gerçek-seq-sonrası-UNPUMP-SVC-N'e-güncellenir (hash'e-etki-etmez)
#     (3) join-shape-tuzağı-koruması :10-13 — dikiş append-ÖNCESİ-gömülmeli;
#         sonradan-yapışan-dikiş-head-doğru-olsa-bile-geçersiz
#
# DİKİŞ-kanalı: x402/v1 (gerçek-EIP-191-ham-digest, encode_defunct-DEĞİL —
# SB'nin-ecrecover'ı-prefix-uygulamaz). test-double-YOK: finalize_bind'in-
# kendi-imzası-SB.verify'nin-gerçek-ecrecover'undan-geçer.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/UNPUMP-FINALIZE"
LOG="$EVDIR/$(date +%F)/at115.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

GW=/home/gokun/projects/01_unicorn/00-gateway
if [ ! -f "$GW/tamga_bind.py" ]; then
  note "[SKIP] AT-115: tamga_bind.py-bu-makinede-değil (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
for mod in eth_keys eth_account; do
  if ! python3 -c "import $mod" 2>/dev/null; then
    note "[SKIP] AT-115: $mod-yok (İNDETERMİNE)."
    echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
    exit 0
  fi
done

# UNPUMP_BIND_SK-yoksa-bilinen-sandbox-anahtarını-kullan (gerçek-EIP-191-üretir)
export UNPUMP_BIND_SK="${UNPUMP_BIND_SK:-0x110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857}"
export TAMGA_ROOT="${TAMGA_ROOT:-/home/gokun/projects/00_TAMGA-MESH/tamga}"

python3 - "$GW" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])                 # 00-gateway (tamga_bind)
sys.path.insert(0, "."); sys.path.insert(0, "tools")

from tamga_bind import build_bind_skeleton, finalize_bind
import settlement_bind_verify as SB

PAYER = "0x" + "1" * 40
PAYEE = "0x" + "2" * 40
DH = "c" * 64
SEQ = {"seq": 42, "ts": 1790018000, "hash": "a" * 64, "prev_hash": "b" * 64}

def kanon_h(charge):
    """Bağımsız D5-yeniden-hesaplama: sha256(prev ‖ jcs(gövde-h-siz))."""
    govde = {k: v for k, v in charge.items() if k != "h"}
    return hashlib.sha256(
        (charge["prev"] + json.dumps(govde, sort_keys=True,
                                     separators=(",", ":"))).encode()).hexdigest()

# --- 1) build_bind_skeleton: seq_hint'siz payment_id-None, iskelet-doğru
skel = build_bind_skeleton(service_name="testsvc", payer=PAYER, payee=PAYEE,
                           delivery_hash_hex=DH, amount=0.01)
sb = skel["charge"]["settlement_bind"]
assert sb["scheme"] == "x402/v1" and sb["payer"] == PAYER
assert skel["charge"]["delivery_hash"] == {"alg": "sha256", "hex": DH}
print("  build_bind_skeleton: iskelet-doğru (scheme/payer/delivery_hash),"
      " seq-bilinmiyor → payment_id-None")

# --- 2) finalize_bind: gerçek-seq-ile-tamamla → GREEN (gerçek-ecrecover)
payload = dict(skel["charge"])
tmp = tempfile.mkdtemp()
pair = finalize_bind(skel, SEQ, payload=payload, ev_dir=tmp)
ch, cl = pair["charge"], pair["claim"]
r = SB.verify(ch, cl)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"finalize-GREEN-beklendi: {r}"
assert r["checks"]["2_claim_sig"] is True   # gerçek-ecrecover, double-YOK
print("  finalize_bind: charge+claim üretildi → SB.verify GREEN rc0"
      " (gerçek-ecrecover, imza-modülün-kendisi)")

# --- 3) D5-kapsama-düzeltmesi: h bağımsız-yeniden-hesaplamayla-aynı
assert ch["h"] == kanon_h(ch), "D5-kapsama-hesabı-uyumsuz"
assert ch["h"] != SEQ["hash"], "h-hâlâ-Sester-hash'i (D5-düzeltmesi-yok)"
# dikiş-gövdede-ve-kapsanan: settlement_bind h'i-içeriyor
assert "settlement_bind" in json.dumps(
    {k: v for k, v in ch.items() if k != "h"}, sort_keys=True)
print(f"  D5-kapsama: h = sha256(prev‖jcs(gövde)) bağımsız-doğrulandı"
      f" (Sester-hash'i-DEĞİL, üretim-fix-8cc75e9-canlı)")

# --- 4) payment_id-onarımı: None → UNPUMP-TESTSVC-42
assert pair["payment_id"] == "UNPUMP-TESTSVC-42"
assert ch["settlement_bind"]["payment_id"] == "UNPUMP-TESTSVC-42"
assert payload["settlement_bind"]["payment_id"] == "UNPUMP-TESTSVC-42", \
    "payload'da-None-kaldı (onarım-yok)"
# onarım-hash'i-bozmaz: h-onarım-sonrası-hâlâ-D5-doğru
assert ch["h"] == kanon_h(ch)
print("  payment_id-onarımı: None → UNPUMP-TESTSVC-42 (seq-sonrası,"
      " hash'e-etki-etmez — öner-tutarlı)")

# --- 5) rc7-evidenceHash: claim.evidenceHash == delivery_hash (aynı-nesne)
assert cl["evidenceHash"] == {"alg": "sha256", "hex": DH}
assert cl["buyerAddress"] == ch["agent_id"]   # rc4-parties
print("  rc7-evidenceHash == delivery_hash + rc4-parties-tutarlı")

# --- 6) NEG-1: join-shape-tuzağı — append-SONRASI-yapışan-dikiş-geçersiz
# dikişsiz-kayıt-üret, settlement_bind'ı-sonradan-yapıştır, h'yi-dikişsiz-hesapla
govdesiz = {"seq": 7, "ts": 1790018000, "event_type": "charge_receipt",
            "agent_id": PAYER, "host": "/testsvc", "amount": 0.01,
            "prev": "b" * 64, "delivery_hash": {"alg": "sha256", "hex": DH}}
govdesiz["h"] = hashlib.sha256(
    (govdesiz["prev"] + json.dumps(govdesiz, sort_keys=True,
                                   separators=(",", ":"))).encode()).hexdigest()
sahte = dict(govdesiz)
sahte["settlement_bind"] = {"scheme": "x402/v1", "payment_id": "UNPUMP-X",
                            "payer": PAYER, "payee": PAYEE, "amount_usd": 0.01}
rs = SB.verify(sahte, cl)
assert rs["verdict"] == "RED", f"join-shape-tuzağı-yakalanmalı: {rs}"
print(f"  NEG-1 join-shape-tuzağı: sonradan-yapışan-dikiş → RED"
      f" rc{rs['reason_code']} (h-dikişi-kapsamıyor — :10-13-uyarısı)")

# --- 7) NEG-2: payment_id-uyumsuz → rc5 settlement_ref_mismatch
bad_pair = finalize_bind(build_bind_skeleton(
    service_name="testsvc", payer=PAYER, payee=PAYEE,
    delivery_hash_hex=DH, amount=0.01, seq_hint=43),
    {"seq": 43, "ts": 1790018000, "hash": "d" * 64, "prev_hash": "b" * 64},
    payload=dict(skel["charge"]), ev_dir=tempfile.mkdtemp())
bad = json.loads(json.dumps(bad_pair["claim"]))
bad["settlementRef"] = "UNPUMP-HATALI-999"   # charge'daki-ile-uyumsuz
rb = SB.verify(bad_pair["charge"], bad)
assert rb["verdict"] == "RED" and rb["reason_code"] == 5, \
    f"rc5-beklendi: {rb}"
print("  NEG-2 payment_id-uyumsuz → RED rc5 (settlement_ref_mismatch)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: yedi-Unpump-finalize-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-115: Unpump finalize_bind settlement-arka-yüz → RFC-010"
[[ $FAIL -eq 0 ]]
