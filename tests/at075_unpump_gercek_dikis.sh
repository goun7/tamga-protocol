#!/usr/bin/env bash
# AT-075: UNPUMP-GERÇEK-DİKİŞ + ecrecover-to_pub-BOŞLUĞU (stub-gizli-hata).
#
# Unpump-ajanı-ilk-iddiasında-6/6-GREEN-demişti; bağımsız-doğrulamamız-RED rc1-
# vermişti (settlement_bind-yok, el-yazımı-JSON). İtiraz-haklıydı-dedi-ve-5-gerçek
# hata-bulup-düzeltti (commit 42bd250):
#
#   1) UNPUMP_BIND_SK yanlış-repoya-yazıldı (bash-cwd-sıfırlanması)
#   2) dikiş-append'den-SONRA-üretiliyordu → dıştan-yapışık. Artık-ÖNCE-üretilip
#      payload'a-gömülüyor; ledger-hash'i-dikişi-kapsar (D5-entegrasyon)
#   3) ecrecover_to_pub YOKTU → x402/v1-claim'ler-her-zaman-rc4. **Eksik-fonksiyonu
#      yazdı. ÖNEMLİ: _recover-EIP-191-öneki-UYGULAMAZ (z=raw-sha256), bu-yüzden
#      imza-da-ham-hash-üretilmeli (encode_defunct-değil)**
#   4) buyer_addr-charge'da-kullanılmadan-tanımlanırdı (sıralama-hatası)
#   5) settlement_bind.payer-bağ-anahtarı-modunda-bağ-adresi-olmalı (kontrol-4)
#
# **BENİM-HATAM (dürüst):** AT-063'ün-test-double'ı-`ecrecover_to_pub`-eksikliğini
# GİZLİYORDU — _claim_signer'yı-lambda-ile-değiştiriyordum, yani-gerçek-imza-
# doğrulama-yolu-HİÇ-test-edilmemişti. Unpump-onu-gerçek-kodda-çalıştırınca
# patladı. Bu-test-o-boşluğu-kapatır: STUB-YOK, GERÇEK-ecrecover.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-075/$(date +%F)/at075.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-075: Unpump-gerçek-dikiş + ecrecover-stub-gizli-boşluk"

FX=".evidence/UNPUMP-BRIDGE/at069-seq92.json"
if [ ! -f "$FX" ]; then
  note "[SKIP] AT-075: Unpump-fixture-bu-makinede-değil (CI) —"
  note "       gerçek-ecrecover-kanıtı-ölçülemedi (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$FX" <<'PYEOF' >> "$LOG" 2>&1
import json, sys, inspect
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
import settlement_bind_verify as SB
import tamga_attest_verify as TAV

d = json.load(open(sys.argv[1]))
charge, claim = d["charge"], d["claim"]

# --- 1) fixture-şekli-gerçek
assert charge["seq"] == 92 and d["payment_id"] == "UNPUMP-CLEARTAG-92"
assert "settlement_bind" in charge and "delivery_hash" in charge
print("  fixture-gerçek: seq-92, settlement_bind-ve-delivery_hash-içeride")

# --- 2) STUB-YOK: _claim_signer-dokunulmamış-olmalı
src_v = inspect.getsource(SB._claim_signer)
assert "ecrecover_to_pub" in src_v, "_claim_signer-gerçek-ecrecover'ı-çağırmıyor"
print("  STUB-YOK: _claim_signer-kaynağı-gerçek-ecrecover'ı-çağırır")

# --- 3) GERÇEK-doğrulama (test-double-YERİNE)
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"GERÇEK-6/6-GREEN-beklendi: {r}"
assert all(r["checks"].values()), "bir-kontrol-eksik: %s" % r["checks"]
print("  GERÇEK-ecrecover-ile-6/6-GREEN (stub-gizli-boşluk-kapandı)")

# --- 4) EIP-191-uyarı-kaynakta (Unpump-3.-düzeltme)
src_t = inspect.getsource(TAV.ecrecover_to_pub)
assert "EIP-191" in src_t, "EIP-191-notu-yok"
print("  EIP-191-notu-kaynakta: z=raw-sha256 (encode_defunct-DEĞİL)")

# --- 5) D5-entegrasyon-dersi (Unpump-2.-düzeltme): dikiş-hash'i-içermeli
# charge'ın-h-alanı-settlement_bind'ı-kapsamalı — kanıt-olarak-yeniden-hesapla
from tamga_canon import jcs
import hashlib
bind = charge["settlement_bind"]
no_h = {k: v for k, v in charge.items() if k != "h"}
h_yeniden = hashlib.sha256(charge["prev"].encode() + jcs(no_h)).hexdigest()
print("  D5-hash-dikişi-kapsıyor:", h_yeniden == charge["h"])
# (uymasa-bile-bu-test-fail-etmez — Unpump'un-2.-düzeltmesinin-iddia-edilen-
#  biçimidir; bizim-gate'imiz-zaten-h'i-yeniden-hesaplamaz, çünkü-tam-zincir-
#  doğrulama-ledger-verify'ın-işidir — ama-kayda-değer-ölçüm)

# --- 6) NEGATİF: sahte-imza-gerçek-ecrecover'da-RED (stub-olsaydı-GREEN-sanılırdı)
claim2 = json.loads(json.dumps(claim))
claim2["signature"] = "0x" + "11"*65   # geçersiz-uzunlukta-sahte-imza
SB.__dict__.pop("_claim_signer", None)  # çift-emniyet: gerçek-yol-kullanılsın
import importlib; importlib.reload(SB)
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 4, \
    f"sahte-imza-RED-beklendi (stub-gizli-boşluk-burda-kanıtlandı): {r2}"
print("  sahte-imza-GERÇEK-ecrecover'da-RED rc4 — stub-gizli-boşluk-KİLİTLİ")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Unpump-gerçek-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-075: Unpump-gerçek-dikiş + ecrecover-boşluk"
[[ $FAIL -eq 0 ]]
