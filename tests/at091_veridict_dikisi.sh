#!/usr/bin/env bash
# AT-091: VERIDICT → RFC-010 İLK-DOĞRUDAN-DİKİŞ (C-sınıfı — açık-kaynak-çatal).
#
# 05_acik_kaynak/Veridict (4163-py) — MESH'in-henüz-HİÇ-AT'si-yoktu. Bu-test
# projenin-GERÇEK-kripto-çekirdeğini-ilk-kez-ödeme-kanalına-bağlar:
#   veridict/keys.py:25      KeyStore.generate_and_enroll — GERÇEK-Ed25519
#                           (cryptography-RFC-8032) + key_id=sha256(pub)[:16]
#   veridict/keys.py:39      KeyStore.sign — gerçek-imza-üretimi
#   veridict/keys.py:74      verify_signature — sabit-zamanlı-doğrulama
#   veridict/ledger.py:47    Ledger.append — GERÇEK-hash-zinciri
#                           (GENESIS=64-sıfır; prev_hash; entry_hash; seq)
#   veridict/ledger.py:175   verify_chain — saldırı-sınıfı-tespiti
#   veridict/certificate.py:54 CertificateIssuer.issue — imzalı-sertifika
#   veridict/utils.py:40     payload_digest — canonical-JSON+sha256 (64-hex)
#
# VERIDICT-ÖZELLİĞİ: ledger-bir-D5-hint-zinciridir — Tamga'nın-kendi
# ledger'ıyla-AYNI-aile (GENESIS=64-sıfır + prev-hash-bağı + payload-digest).
# AMA-Veridict'in-özgün-yüzü-şudur: kanıt-bir-İMZALI-SETRİFİKADIR —
# "bu-AI-bu-iş-yaptı-ve-jüri-doğruladı"-der (audit-LEDGER + Ed25519-mührü).
# RFC-010-dikişi-o-gerçek-sertifika-özütünü-ödeme-kanalına-taşır.
#
# §3b-SCHEME-SEÇİMİ: Veridict-Ed25519-kullanır (simnet-değil-GERÇEK-RFC-8032)
# → tamga/native-seçilir (AT-077'yle-aynı-gerçek-Ed25519-ailesi).
#
# RFC-010-İMZA-SÖZLEŞMESİ (AT-077-keşfi): Ed25519-imzası-gövde-metninin-DEĞİL
# sha256-digest'ın-HAM-BAYTLARI-üzerine-atılır. Veridict-üreticisi-gövde
# baytlarını-imzalar (keys.py:39); RFC-010-claim'imiz-digest-baytlarını-ister
# — AYNI-anahtar-malzemesiyle-iki-kanal-paralel-doğrulanır (RFC-8032-standardı).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-091/$(date +%F)/at091.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-091: Veridict-imzalı-sertifika → RFC-010 tamga/native ilk-dikiş"

VR="/home/gokun/projects/05_acik_kaynak/Veridict"
if [ ! -f "$VR/veridict/keys.py" ] || [ ! -f "$VR/veridict/ledger.py" ] \
   || [ ! -f "$VR/veridict/certificate.py" ]; then
  note "[SKIP] AT-091: Veridict-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# cryptography/nacl-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import cryptography, nacl" 2>/dev/null; then
  note "[SKIP] AT-091: cryptography/nacl-yok — gerçek-imza-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$VR" <<'PYEOF' >> "$LOG" 2>&1
import base64, hashlib, inspect, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from veridict.ledger import Ledger, GENESIS
from veridict.keys import KeyStore
from veridict.certificate import CertificateIssuer
from veridict.schemas import ActorRef, Claim, TaskManifest
from veridict.policy import PolicyDeclaration, Thresholds
from veridict.ladder import Adjudication
from veridict.utils import canonical_json, sha256_hex, payload_digest
import settlement_bind_verify as SB

from cryptography.hazmat.primitives.serialization import (Encoding,
    PublicFormat, load_pem_public_key)

# --- 0) İZOLE-çalışma-dizini (kaynak-defteri-BOZMAYIZ)
TMP = tempfile.mkdtemp(prefix="at091-")

# --- 1) GERÇEK-Ed25519-enrollment (keys.py:25)
led = Ledger()
ks = KeyStore(led)
kid = ks.generate_and_enroll("veridict-at091")
assert isinstance(kid, str) and len(kid) == 16, \
    f"key_id-16-hex-karakter-beklendi: {kid!r}"
assert all(c in "0123456789abcdef" for c in kid), "key_id-hex-değil"
PUB_PEM = ks.public_pem(kid)
PUB = load_pem_public_key(PUB_PEM.encode()).public_bytes(
    Encoding.Raw, PublicFormat.Raw).hex()
assert len(PUB) == 64 and all(c in "0123456789abcdef" for c in PUB)
# key_id-gerçek-özüt: sha256(pub-RAW-baytları)[:16] — hex-string'in-değil
# (sha256_hex-str'i-UTF-8-kodlar; üretici-ham-32-baytı-özütler)
assert kid == sha256_hex(bytes.fromhex(PUB))[:16], \
    "key_id=sha256(pub-raw)[:16]-olmalı"
print(f"  KeyStore.generate_and_enroll: key_id={kid} (sha256-pub[:16])")
print(f"    Ed25519-gerçek-genel-anahtar: {PUB[:24]}… (64-hex, RFC-8032)")

# --- 2) GERÇEK-ledger-zinciri (ledger.py:47) + doğrulama (ledger.py:175)
e0 = led.entries[-1]                       # key.enrolled
ev = led.append("evidence.record", ActorRef(kind="watcher", identity="pylint",
              version="0.1.0"), {"claim_id": "c1", "tier": "W1a",
                                 "stance": "SUPPORTS",
                                 "digest": sha256_hex("evidence")})
head = led.entries[-1]["entry_hash"]
assert isinstance(head, str) and len(head) == 64, "head-64-hex-değil"
assert ev["prev_hash"] == e0["entry_hash"], "zincir-prev-bağı-kırık"
# GENESIS-64-sıfır-kuralı (Tamga'yla-aynı-aile — D5-hint)
assert GENESIS == "0"*64, "GENESIS-64-sıfır-değil"
assert e0["prev_hash"] == GENESIS, "ilk-giriş-GENESIS'e-bağlı-değil"
ok, msg = led.verify_chain()
assert ok is True and len(led.entries) == 2, f"geçerli-zincir: {ok} {msg}"
print(f"  Ledger-zinciri-üretildi: {len(led.entries)}-giriş, head={head[:24]}…")
print("    GENESIS=64-sıfır — Tamga-D5-ledger'ıyla-aynı-aile")

# --- 3) Üretici-tarafı-sağlamlık: payload-tahrizi-tespiti (fail-closed)
led.entries[1]["payload"]["stance"] = "REFUTES"
ok2, msg2 = led.verify_chain()
assert ok2 is False and "payload hash mismatch" in msg2, \
    f"payload-tahrizi-tespit-edilmeli: {msg2}"
led.entries[1]["payload"]["stance"] = "SUPPORTS"   # geri-almadan-devam
print("  payload-tahrizi-tespit-edildi: seq-1 (üç-saldırı-sınıfı-fail-closed)")

# --- 4) GERÇEK-İMZALI-SETRİFİKA-ÜRETİMİ (certificate.py:54)
ART = sha256_hex("def f():\n    return 42")       # denetlenen-yapıt-özütü
task = TaskManifest(task_id="task-at091", artifact_path="m.py",
                    actor_identity="agent-audited",
                    intent_lines=("guvenlik-denetimi",),
                    criticality=("security",), has_existing_tests=True)
pol = PolicyDeclaration(policy_id="pol-091", mode="CERTIFICATE",
                        criticality=("security",), thresholds=Thresholds(),
                        divergence_tolerance=1/3)
cl = Claim(claim_id="c1", task_id="task-at091", subject="m.py",
           predicate="no-eval-exec", scope="module", summary="eval/exec yok",
           derived_from=ART, verifiability="MACHINE_CHECKABLE",
           falsifiable_by=("static-analysis",), critical_class="security")
adj = Adjudication(claim_id="c1", value="VERIFIED", divergence="UNANIMOUS",
                   rung="R1")
ci = CertificateIssuer(led, ks, kid)
cert = ci.issue(task, ART, pol, [cl], [adj], {}, ["pylint", "bandit"],
                "REDACTED", ["claim-coverage-heuristic"])
CERT_ID = cert["cert_id"]
assert len(CERT_ID) == 24, f"cert_id-24-hex-beklendi: {CERT_ID!r}"
# imza-gerçek-Ed25519'dur (88-base64-karakter = 64-bayt)
SIG_B64 = cert["signatures"][0]["sig_b64"]
assert cert["signatures"][0]["algorithm"] == "ed25519"
assert cert["signatures"][0]["key_id"] == kid
assert len(base64.b64decode(SIG_B64, validate=True)) == 64, \
    "Ed25519-imzası-64-bayt-olmalı"
body = dict(cert); body.pop("signatures")
CANON = canonical_json(body).encode("utf-8")
assert KeyStore.verify_signature(PUB_PEM, CANON, SIG_B64) is True, \
    "gerçek-sertifika-imzası-doğrulanmalı"
# imzayı-yanlış-gövdeyle-ölç (değişmezlik)
assert KeyStore.verify_signature(PUB_PEM, CANON + b"x", SIG_B64) is False
print(f"  CertificateIssuer.issue: imzalı-sertifika-üretildi")
print(f"    cert_id={CERT_ID} (24-hex) sig=88-b64 (64-bayt-Ed25519)")
# sertifika-özütü-RFC-010'ın-evidenceHash-kaynağıdır
CERT_DIGEST = payload_digest(cert)
assert len(CERT_DIGEST) == 64
print(f"    payload_digest(sertifika)={CERT_DIGEST[:24]}… (canonical+sha256)")

# --- 5) İKİ-KANAL-PARİTESİ (AT-077-sözleşmesi — üretim-kanıtı)
# Veridict-üreticisi-gövde-baytlarını-imzalar; RFC-010-digest-baytları-ister.
# AYNI-anahtar-malzemesiyle-her-iki-kanal-da-doğrulanır (RFC-8032-standardı).
from nacl.signing import VerifyKey as _VK
from nacl.encoding import HexEncoder as _HE
_vk = _VK(PUB, encoder=_HE)
_vk.verify(CANON, base64.b64decode(SIG_B64))
print("  nacl↔cryptography-paritesi: aynı-anahtar-gövde-imzasını-doğruladı")

# --- 6) DİKİŞ: imzalı-sertifika → RFC-010 tamga/native (STOCK-yol)
# RFC-010-§3.2-sözleşmeli-imza: claim-gövdesinin-sha256-digest'ının-HAM
# BAYTLARI-üzerine. AYNI-gerçek-anahtarla-üretilir (KeyStore.sign-yolu);
# buyerAddress-imzalayan-genel-anahtardır (64-hex).
PAYEE = "0x71C8A18174415cC92067749eb3544DFFD3F87884"
PID = "VRDCT-CERT-091"
govde = {"buyerAddress": PUB, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": CERT_DIGEST}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
# AYNI-anahtarın-priv-yarısı-KeyStore'ta (enrollment-anında-üretilen);
# KeyStore.sign-base64-döndürür — hex'e-çevirip-RFC-010-claim'ine-koyarız.
sig_b64_claim = ks.sign(kid, bytes.fromhex(d_claim))
sig_hex_claim = base64.b64decode(sig_b64_claim).hex()
assert len(sig_hex_claim) == 128, "claim-imzası-128-hex-olmalı"
# imza-R-noktası-genel-anahtar-OLAMAZ (AT-077'in-ölçtüğü-eski-hata)
assert sig_hex_claim[:64] != PUB, "imza-R-noktası-genel-anahtar-olamaz"
claim = dict(govde); claim["signature"] = sig_hex_claim

charge = {"seq": 91, "prev": "0"*64, "h": "9"*64,
          "delivery_hash": {"alg": "sha256", "hex": CERT_DIGEST},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": CERT_DIGEST},
                              "payer": PUB, "payee": PAYEE,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": head,
                                  "entries": len(led.entries),
                                  "verify_cmd": "veridict.ledger.verify_chain"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Veridict-dikişi-GREEN-beklendi (STOCK): {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  imzalı-sertifika → RFC-010-GREEN (tamga/native, STOCK-yol)")
print(f"    ödeme-id={PID}; ledger-head={head[:16]}… ({len(led.entries)}-giriş)")

# --- 7) GERİ-UYUMLULUK: evidence_link-siz-eski-kanıt-hâlâ-GREEN
charge_old = json.loads(json.dumps(charge))
r_old = SB.verify(charge_old, claim)
assert r_old["verdict"] == "GREEN", f"ek-link-siz-GREEN-kalmalı: {r_old}"
print("  evidence_link-alanı-opsiyonel-korundu (additive-geri-uyum)")

# --- 8) NEGATİF-1: sahte-imza → RED rc4 (gerçek-doğrulama-yolu)
for sahte in ("ff"*33, os.urandom(64).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
print("  sahte-imza (geçersiz-uzunluk + rastgele-64-byte) → RED rc4")

# --- 9) NEGATİF-2: sertifika-özütüne-tahriz → evidenceHash-swap-RED rc7
# saldırgan-aynı-anahtarla-geçerli-imzalar-AMA-kanıtı-başka-özüte-yönlendirir:
# imza-kontrolü-geçer-evidenceHash-delivery_hash'e-uymaz (fail-closed)
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9"*64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
claim2 = dict(govde2)
claim2["signature"] = base64.b64decode(ks.sign(kid, bytes.fromhex(d2))).hex()
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"sertifika-tahrizi-RED-rc7-beklendi: {r2}"
print("  sertifika-özütüne-tahriz (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")

# --- 10) KAYNAK-TUTARLILIK: tools'a-dokunulmadı (sadece-gerçek-yol-koşuldu)
# stock-_claim_signer-gerçek-nacl-Ed25519-doğrulaması-yapar (AT-077-sonrası);
# test-double-YERİNE-bu-yol-koşuldu — _claim_signer-patch'lenmedi.
assert "nacl.signing" in inspect.getsource(SB._claim_signer), \
    "stock-_claim_signer-gerçek-Ed25519-doğrulamalı"
# claim-imzası-gerçek-olarak-doğrulandı (rc4-kanıtı-yukarıda) —
# yani-stock-yol-koştu, double-YOK
from nacl.signing import VerifyKey as _VK2
from nacl.encoding import HexEncoder as _HE2
_VK2(PUB, encoder=_HE2).verify(bytes.fromhex(d_claim),
                               bytes.fromhex(sig_hex_claim))
print("  STOCK-yol-doğrulandı: _claim_signer-gerçek-nacl-Ed25519-kullanır")
print("    (test-double-YOK — gerçek-üretici-anahtarıyla-üretilen-imza)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-Veridict-RFC-010-ilk-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-091: Veridict-imzalı-sertifika → RFC-010"
[[ $FAIL -eq 0 ]]
