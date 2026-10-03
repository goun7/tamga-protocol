#!/usr/bin/env bash
# AT-103: DÜMEN-İKİNCİ-YÜZ (signing.py) → RFC-010 tamga/native dikişi.
#
# AT-068-sadece-İLK-yüzü-bağladı (evidence_chain.py — SHA-256-prev_hash-zinciri,
# GENESIS=64-sıfır, bizim-D5-zincirinin-aynı-şekli; rfc8785-kanonikleştirme-
# düzeyinde-zaten-bağlıydı). İKİNCİ-YÜZ-henüz-ölçülmedi:
#
#   dumen/reports/signing.py — GERÇEK-Ed25519-zincir-kanıt-imzalama
#     generate_keypair:62  Ed25519-çifti-üretir (0600-PEM-gizli + pub)
#     sign_chain_file:114   zincir-DOSYASINI-imzalar (bütünlük-kapısı-ile-yükler)
#                           imza = Ed25519(MAGIC ‖ head_hash) — kaynak-bağ
#     verify_chain_file:142 ÜÇLÜ-doğrulama: (1) zincir-sağlam, (2) imza-bu-
#                           anahtardan, (3) imzalanan-head = bugünkü-head
#                           Her-başarısızlık-AYRIK-gerekçeyle (fail-closed)
#
# DÜMEN-ÖZELLİĞİ: imza-bir-KİMLİK-BAĞIDIR — "kimlik = anahtarı-taşıyan"
# (honest-boundary). Zincir-kendi-başına-tutarlılık-kanıtlar; imza-üstüne
# "bunu-kim-mühürledi"-bağlar. AT-068'in-hash-zinciri-ne-YAPAMADIĞI-budur:
# tahrif-edilmiş-zincir-yeniden-hash'lenebilir-AMA-imza- taşınamaz.
#
# §3b-SCHEME-SEÇİMİ: Ed25519PrivateKey-gerçek-RFC-8032 (cryptography) →
# tamga/native (AT-091/097'yle-aynı-gerçek-Ed25519-ailesi).
#
# İMZA-SÖZLEŞMESİ-KEŞFİ: Dümen-imzası Ed25519(MAGIC‖head) üzerinedir —
# RFC-010-claim'imiz-ise-Ed25519(sha256(govde))-baytları-üzerine-ister.
# AYNI-gerçek-anahtarla-iki-kanal-paralel-koşar (AT-077/097-disiplini):
# Dümen-imzası-üretici-tarafı-sağlamlıkta-doğrulanır; RFC-010-imzası-gate'te.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/DUMEN-2/$(date +%F)/at103.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-103: Dümen-signing (ikinci-yüz) → RFC-010 tamga/native dikişi"

DU="/home/gokun/projects/01_unicorn/77-Dumen"
if [ ! -f "$DU/dumen/reports/signing.py" ]; then
  note "[SKIP] AT-103: Dümen-kodu-bu-makinede-değil (CI) —"
  note "       imza-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# [Fix-2026-10-02] dumen-import-zinciri torch ister; torch user-site'te
# ($HOME/.local) — HOME_degisince ImportError ile fail. Dumen WIP/ayri-proje
# oldugu icin onun kodunu degil, burada SKIP-guard ekliyoruz (at149/at174
# deseniyle: bagimlilik-yok = INDETERMINE, yeşil-boyanmaz).
if ! python3 -c "import torch" 2>/dev/null; then
  note "[SKIP] AT-103: torch-yok (user-site) — Dümen-import-zinciri"
  note "       koşamadı (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$DU" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from dumen.reports.evidence_chain import EvidenceChain
from dumen.reports import signing
import settlement_bind_verify as SB

from cryptography.hazmat.primitives.serialization import (
    Encoding, PublicFormat, load_pem_public_key, load_pem_private_key)

# --- 0) İZOLE-çalışma-dizini (kaynak-defteri-BOZMAYIZ)
TMP = tempfile.mkdtemp(prefix="at103-")

# --- 1) GERÇEK-Ed25519-anahtar-çifti (signing.py:62)
kp = signing.generate_keypair("at103-auditor", TMP)
PRIV_PATH, PUB_PATH = kp["private_key_path"], kp["public_key_path"]
assert os.path.exists(PRIV_PATH) and os.path.exists(PUB_PATH)
# 0600-disk-izni-gerçek (anahtar-muhafazası-disiplini)
assert oct(os.stat(PRIV_PATH).st_mode)[-3:] == "600", \
    "gizli-anahtar-0600-olmalı (anahtar-muhafazası)"
FP = kp["fingerprint"]
# fingerprint-gerçek-özüt: ed25519:sha256(raw-pub)[:16]
_pub_obj = load_pem_public_key(open(PUB_PATH, "rb").read())
PUB = _pub_obj.public_bytes(Encoding.Raw, PublicFormat.Raw).hex()
assert len(PUB) == 64 and all(c in "0123456789abcdef" for c in PUB)
expect_fp = "ed25519:" + hashlib.sha256(bytes.fromhex(PUB)).hexdigest()[:16]
assert FP == expect_fp, f"fingerprint-özüt-uyuşmadi: {FP} != {expect_fp}"
print(f"  generate_keypair: gerçek-Ed25519-çifti (gizli-0600-PEM)")
print(f"    fingerprint: {FP} (= ed25519:sha256(pub)[:16])")
print(f"    genel-anahtar: {PUB[:20]}… (64-hex, RFC-8032)")

# --- 2) GERÇEK-kanıt-zinciri + imzalı-mühür (AT-068'in-zinciri-üstüne)
ch = EvidenceChain()
ch.append("denetim", {"hedef": "auth-modulu", "bulgu": "eval-kullanimi",
                      "severity": "high"})
ch.append("düzeltme", {"fix": "eval-kaldirildi", "pr": "#42"})
assert len(ch) == 2
assert ch.GENESIS_PREV == "0"*64, "GENESIS-64-sıfır (D5-aynı-aile)"
CHAIN_PATH = os.path.join(TMP, "denetim.json")
open(CHAIN_PATH, "w", encoding="utf-8").write(ch.to_json())

rec = signing.sign_chain_file(CHAIN_PATH, PRIV_PATH, "at103-auditor")
HEAD = rec.head_hash
assert len(HEAD) == 64 and all(c in "0123456789abcdef" for c in HEAD)
# imza-gerçek-Ed25519: 128-hex (64-bayt); MAGIC-öneki-ile-head üzerine
assert len(rec.signature_hex) == 128
assert rec.chain_length == 2 and rec.magic == "dumen-ed25519-chain-sig-v1"
print(f"  sign_chain_file: zincir-mühürlendi (bütünlük-kapısı-ile-yüklendi)")
print(f"    head: {HEAD[:20]}… | imza: {rec.signature_hex[:20]}… (128-hex)")
print(f"    imza-ön-görüntü: Ed25519(MAGIC‖head) — kaynak-bağ")

# --- 3) ÜÇLÜ-doğrulama-gerçek (signing.py:142): valid=True
vo = signing.verify_chain_file(CHAIN_PATH, CHAIN_PATH + ".sig", PUB_PATH)
assert vo.valid is True, f"üçlü-doğrulama-geçmeli: {vo.reason}"
assert vo.head_hash == HEAD and vo.pubkey_fingerprint == FP
assert vo.signer_name == "at103-auditor"
print(f"  verify_chain_file: valid=True (üçlü: zincir + imza + head)")

# --- 4) ÜRETİCİ-TARAFI-SAĞLAMLIK: üç-saldırı-sınıfı-AYRIK-gerekçeyle
# (a) sahte-imza — AYNI-zincirle (head-sabit) → imza-GEÇERSİZ
sig_bad = json.loads(open(CHAIN_PATH + ".sig").read())
sig_bad["signature_hex"] = "ff" * 64
BAD_PATH = CHAIN_PATH + ".bad.sig"
open(BAD_PATH, "w").write(json.dumps(sig_bad))
vo_bad = signing.verify_chain_file(CHAIN_PATH, BAD_PATH, PUB_PATH)
assert vo_bad.valid is False and "GEÇERSİZ" in vo_bad.reason, \
    f"sahte-imza-yakalanmali: {vo_bad.reason}"
# (b) yanlış-genel-anahtar → imza-bu-anahtardan-değil
other = signing.generate_keypair("baska", TMP)
vo_wrong = signing.verify_chain_file(CHAIN_PATH, CHAIN_PATH + ".sig",
                                     other["public_key_path"])
assert vo_wrong.valid is False and "GEÇERSİZ" in vo_wrong.reason, \
    f"yanlış-anahtar-yakalanmali: {vo_wrong.reason}"
# (c) imza-sonrası-zincire-ekleme → head-değişti → imza-bozuldu
ch2 = EvidenceChain.from_json(open(CHAIN_PATH).read())
ch2.append("ek-bulg", {"not": "sonradan"})
open(CHAIN_PATH + ".tmp", "w", encoding="utf-8").write(ch2.to_json())
vo_head = signing.verify_chain_file(CHAIN_PATH + ".tmp", CHAIN_PATH + ".sig",
                                    PUB_PATH)
assert vo_head.valid is False and "head uyuşmuyor" in vo_head.reason, \
    f"head-değişimi-yakalanmali: {vo_head.reason}"
print("  üretici-sağlamlığı: sahte-imza/yanlış-anahtar/head-değişimi → False")
print("    üçü-de-AYRIK-gerekçe-verir (fail-closed — append-only-tasarım)")

# --- 5) DİKİŞ: imzalı-head → RFC-010 tamga/native (STOCK-yol)
# evidenceHash = imzalı-head (machine-checkable: verify_chain_file-yeniden-
# hesaplar). RFC-010-claim-imzası = Ed25519(sha256(govde))-baytları-üzerine
# AYNI-gerçek-anahtarla (AT-077/097-disiplini).
PAYEE = "0x71c8a18174415cc92067749eb3544dffd3f87884"
PID = "DUMEN-CHAIN-SIG-103"
govde = {"buyerAddress": PUB, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": HEAD}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
_pk = load_pem_private_key(open(PRIV_PATH, "rb").read(), password=None)
sig_claim = _pk.sign(bytes.fromhex(d_claim)).hex()
assert len(sig_claim) == 128, "claim-imzası-128-hex-olmalı"
claim = dict(govde); claim["signature"] = sig_claim

charge = {"seq": 103, "prev": "0"*64, "h": "e"*64,
          "delivery_hash": {"alg": "sha256", "hex": HEAD},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": HEAD},
                              "payer": PUB, "payee": PAYEE,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": HEAD,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "dumen.reports.signing"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Dümen-dikişi-GREEN-beklendi (STOCK): {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  imzalı-denetim-zinciri → RFC-010-GREEN (tamga/native, STOCK-yol)")
print(f"    ödeme-id={PID}; buyerAddress=auditor-genel-anahtarı")

# --- 6) İKİ-KANAL-PARİTESİ: Dümen-imzası-ile-claim-imzası-aynı-anahtardan
# Dümen: Ed25519(MAGIC‖head); RFC-010: Ed25519(sha256(govde)). Ön-görüntü-farklı
# AMA-anahtar-aynı — gerçek-kaynak-bağı-iki-kanalda-da-taşınır.
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
_pub_check = load_pem_public_key(open(PUB_PATH, "rb").read())
_magic = "dumen-ed25519-chain-sig-v1"
_pub_check.verify(bytes.fromhex(rec.signature_hex),
                  _magic.encode() + HEAD.encode("ascii"))
_pub_check.verify(bytes.fromhex(sig_claim), bytes.fromhex(d_claim))
print("  iki-kanal-paritesi: AYNI-anahtarla-her-iki-ön-görüntü-doğrulandı")

# --- 7) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("ff"*64, os.urandom(64).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (64-hex-sabit + rastgele) → RED rc4")

# --- 8) NEGATİF-2: imzalı-zincire-tahriz → evidenceHash-swap-RED rc7
# saldırgan-denetime-yeni-bulgu-ekler (head-değişir) → yeni-head-üzerine-yeni
# GERÇEK-imza-üretir-AMA-delivery_hash-eski-head'e-sabit → fail-closed
ch3 = EvidenceChain.from_json(open(CHAIN_PATH).read())
ch3.append("salcidir-bulgu", {"sahte": True})
cp3 = os.path.join(TMP, "tahrif.json")
open(cp3, "w", encoding="utf-8").write(ch3.to_json())
rec3 = signing.sign_chain_file(cp3, PRIV_PATH, "at103-auditor")
HEAD3 = rec3.head_hash
assert HEAD3 != HEAD, "tahrif-head'i-değiştirmeli"
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": HEAD3}}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
sig2 = _pk.sign(bytes.fromhex(d2)).hex()
claim2 = dict(govde2); claim2["signature"] = sig2
r7 = SB.verify(charge, claim2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"zincir-tahrizi-RED-rc7-beklendi: {r7}"
print("  zincire-ekleme-tahrizi (yeni-gerçek-imzalı-head) → RED rc7")
print("    taşıma-ölçüldü: imzalı-head-delivery_hash'e-sabittir")

# --- 9) KANONİKLEŞTİRME-BAĞI (AT-068'in-keşfi-devam): rfc8785-şeması-canlı
ch_rfc = EvidenceChain(canon_scheme="rfc8785")
ch_rfc.append("jcs", {"b": 2, "a": 1})   # sıralama-önemsiz (kanonik)
h_jcs = ch_rfc.head_hash()
assert len(h_jcs) == 64 and h_jcs != EvidenceChain.GENESIS_PREV
print(f"  rfc8785-kanonik-şema-canlı: head={h_jcs[:16]}… (AT-068-bağı-sürüyor)")

# --- 10) KİMLİK=ANAHTAR-MUHAFAZASI-DOKTRİNİ (signing.py-docstring'in-uygulaması)
# mevcut-anahtar-sessizce-ezilmez (rotasyon-yasak) — imzalar-anahtara-bağlı
try:
    signing.generate_keypair("at103-auditor", TMP)   # overwrite=False
    raise AssertionError("mevcut-anahtar-ezilmemeli (rotasyon-yasak)")
except FileExistsError:
    pass
print("  anahtar-muhafazası: mevcut-anahtar-sessizce-ezilmez (FileExistsError)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-Dümen-signing-ikinci-yüz-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-103: Dümen-signing (ikinci-yüz) → RFC-010"
[[ $FAIL -eq 0 ]]
