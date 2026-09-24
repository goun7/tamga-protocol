#!/usr/bin/env bash
# AT-187: 'DOĞRULAMA-YOLU-VE-KANCA-NOKTASI'-TARAMASI — 25.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-185/AT-186-kapandı. Doğrulama-yolunun-tamamlanmamış-
# kanca-noktalarını-tara: ( 1) verify-öncesi-koşul-atlaması: verify-gate'i-bazı-
# koşullarda-atlanıyor-mu ( kısa-devre-döngü: örn. debug/verbose-bayrağı-ile);
# ( 2) negatif-kontrol-gerçek-yolu: negatif-testler-gerçek-üretim-yolunu-koşuyor-mu
# ( test-double-gizli-boşluk-AT-075/AT-077-sınıfı-bul-mu); ( 3) hata-mesajı-sızdırma:
# RED-mesajları-iç-durum-sızdırıyor-mu ( AT-183-sınıfı); ( 4) fail-closed-tutarlılık:
# tüm-RED-yolları-gerçekten-fail-closed-mı ( bazıları-None-döndürerek-geçebilir).
# Öncelik: tamga ( settlement_bind_verify, sovereign_verify, ledger), sester
# ( middleware), veridict ( ledger), swarmax ( TSA). BULGU → DÜRÜST-rapor;
# YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 4-proje-tamamlandı — 1-BULGU-AÇIK, 5-TEMİZ):
#
# *** BULGU-1: swarmax TSA token-imzası-DOĞRULANMIYOR — verify_token_binding
#     SADECE-imprint-substring-arıyor ( src/swarmax/tsa.py:114-127) — sınıf-4 ***
#   Kod:
#       def verify_token_binding( token, data, *, nonce=None) -> bool:
#           imprint = hashlib.sha256( data).digest()
#           if imprint not in token: return False   # ← SUBSTRING-ARAMA
#           return True
#   Modül-docstring'i-dürüst: "Full PKI signature-chain verification of the
#   token is left to standard tooling ( openssl ts -verify -CAfile) — that is
#   an external audit step, wired into the compliance drill, not silently
#   re-invented here."
#   AMA-iki-kanca-noktası-bu-dürüst-scope'u-aşar:
#     ( a) seal_ledger ( sealing.py:83): TSA-outage-hatasında-rollback-YAPAR
#         ( sağlam) — AMA-başarılı-yanıtta verify_token_binding(token, msg)
#         ile-token'ı-KABUL-EDER; imza-katmanı-yok.
#     ( b) verify_seals ( sealing.py:133): "countersign_ok" = verify_token_binding
#         → KULLANICIYA-İNDETERMİNE-yerine-geçerli-gibi-raporlanır.
#     ( c) trust_drill ( scripts/trust_drill.py:99): openssl-PKI-adımı "extra
#         proof"-olarak-işaretli: verdict = ok_local  # PKI step is extra proof
#         when network allows → ağ/cert-alınamazsa SKIP-ile-drill-PASS-döner.
#   KANITLANDI ( bu-testin-A-bölümü): TSA'ya-HİÇ-BAŞVURMADAN üretilmiş sahte-DER
#   token ( sadece-içine-SHA256-imprint'i-gömülmüş) → verify_token_binding=True;
#   verify_seals üzerinden countersign_ok=True-olarak-raporlanır.
#   ETKİ: RFC-3161-countersigned-seal'in-TSA-tarafından-İMZALANDIĞI-güvencesi-YOK
#   — herhangi-bayt-dizisi-imprint'i-içerirse-geçer. Zaman-damgası-iddiası
#   ( kanıt-üretim-tarihi) sahtelenebilir; saldırgan-kendi-TSA'sını-taklit-eder.
#   → KISA-DEVRE-YOK: debug/verbose-bayrağı-ile-atlama-bulunamadı ( grep-boş);
#     bu-bir-eksik-doğrulama-kanca-noktası ( fail-OPEN-yol), atlama-DEĞİL.
#   Öneri: verify_token_binding'e-openssl-çıkış-yolu-ekle ( subprocess openssl
#     ts -verify -CAfile) VEYA DER-imza-alanını-açıkça-parsing-ile-doğrula;
#     trust_drill'de-verdict'i-ok_pki'ye-BAĞLA ( skip-yalnızca-loose-modda).
#
# TEMİZ-modeller ( 5-kanıt):
#   1) tamga cmd_ledger_verify: "could not look never green" ( eksik-dizin → RED
#      reason_code=19); boş-zincir = kurallı-pre-genesis ( GREEN); delivery_hash
#      shape-gate ( alg/hex-kuralı); D12-üçlü-bütünlük ( net_decl/events/mb-beraber)
#   2) tamga settlement_bind_verify: beş-kontrol-fail-closed ( ilk-RED-döner);
#      BİLİNMEYEN-şema → İNDETERMİNE ( üçüncü-seçenek-yasak; RED-DEĞİL);
#      evidenceHash-swap → rc7; party-swap → rc6
#   3) tamga sovereign_verify: RISK-1 ( var-olmayan-yol → RED; sahte-GREEN-
#      koruması) + RISK-2 ( dev-secret-uyarısı; üretim-zinciri-RED-düşürür);
#      eksik-argüman → ok=False ( fail-closed)
#   4) tamga verify_capacity_attest: her-hata-yolu-RED ( zarf-eksik/claimId-
#      mismatch/imza-bozuk/recover-edilemedi/buyer-mismatch); EIP-2 low-s
#      ( malleability-kapalı); golden-vectors 7/7 ( 5-GREEN + 2-NEGATİF-gerçek-
#      üretim-yolu: forged/tampered)
#   5) sester middleware: facilitator-unknown → fail-closed-RED ( "ödeme
#      doğrulanamadı — fail-closed" + ledger'da-deny-olayı); policy_denied → RED;
#      debug/verbose-atlama-bayrağı-YOK ( grep ile-teyit)
#
# 4-negatif-kanıt:
#   N1) sahte-TSA-token → verify_token_binding=True ( BULGU-1)
#   N2) settlement_bind evidenceHash-swap → RED rc7 ( fail-closed-çalışıyor)
#   N3) sovereign-verify var-olmayan-sester-db → RED ( sahte-GREEN-kapalı)
#   N4) sester facilitator-unknown-durumu → 402 fail-closed ( NONE-geçişi-yok)
#
# İNDETERMİNE-notları: ( a) at063-negatif-testleri-_claim_signer-TEST-DOUBLE
#     kullanıyor ( SB._claim_signer = lambda ...). AMA-bu-bilinçli-dağıtım:
#     yorum-ve-kod-açıkça-belirtiyor "imza-kontrolü-test-sürümünde-atla ( gerçek
#     ecrecover-AT-012'de)". AT-075/AT-077-sınıfı-gizli-boşluk-DEĞİL — gerçek
#     imza-yolu-AT-012-ve-attest_verify_bagimsiz.py-tarafından-koşülüyor.
#   ( b) verify_seals: tsa_token=None ( pre-T3.1-seal) → "absence-reported-NOT-
#     failed" ( countersign_ok=None) — bu-TASAARIM ( geri-uyumluluk); token-VAR-
#     AMA-imza-yanlış-olsaydı-BULGU-1-nedeniyle-True-döner ( asıl-açık).
#   ( c) veridict-ledger: AT-185-BULGU-2-düzeltmesi-canlı ( ts-monotonluk ±5s-
#     tolerans; geriye-ts → RED) — bu-test-onaylar; yeni-bulgu-YOK.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/DOGRULAMA-YOLU/$(date +%F)/at187.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-187: Doğrulama-yolu-ve-kanca-noktası-taraması ( 4-proje) — 1-BULGU"

# ============================================ A) BULGU-1: swarmax-TSA-imzası-yok
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, hashlib, sqlite3, tempfile, os
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/swarmax/src")
from swarmax.tsa import verify_token_binding
from swarmax.sealing import verify_seals, seal_ledger, merkle_root
from swarmax.evidence import append_evidence
from swarmax.db import init_db_with_migrations
from swarmax.ed25519 import generate_seed

# --- 1) SAHTE-token: TSA'ya-HİÇ-BAŞVURULMADAN
msg = b"fake-seal-message"
imprint = hashlib.sha256(msg).digest()
fake = b"\x30\x82\x00\x40" + b"FAKE-TSA-NO-SIGNATURE" + imprint + b"\x00" * 20
# AT-187-BULGU-1-KAPALDI: PEM-ayarlıysa-sahte-token-RED ( fail-closed)
os.environ["SWARMAX_TSA_PEM"] = "/tmp/at187-yok-cert.pem"
ok = verify_token_binding(fake, msg)
print(f"  1-B1: SAHTE-token ( PEM-ayarlı, imza-YOK): {ok}")
assert ok is False, "AT-187-kapanmadı! sahte-token-hâlâ-kabul ( fail-OPEN)"
print("        → AT-187-BULGU-1-KAPALDI: PKI-doğrulaması-openssl-ile-çalışır")
print("           ( geçersiz-cert → fail-closed; binding-tek-başına-yetmez)")

# --- 2) tam-hat: sahte-token-ile-seal "countersigned"-raporlanır-mı
tmp = tempfile.mkdtemp()
conn = sqlite3.connect(os.path.join(tmp, "e.db")); conn.row_factory = sqlite3.Row
init_db_with_migrations(conn)
seed = generate_seed()
for i in range(3):
    append_evidence(conn, "test", {"i": i})
conn.commit()
r = seal_ledger(conn, seed)
# SAHTE-token: SEAL'İN-GERÇEK-msg'si-üzerine ( TSA-çağrısı-YAPMADAN)
real_msg = r["root_hash"].encode() + r["covers_through_seq"].to_bytes(8, "big")
real_imprint = hashlib.sha256(real_msg).digest()
fake_seal = b"\x30\x82\x00\x40" + b"FAKE-TSA-NO-SIGNATURE" + real_imprint + b"\x00" * 20
# seals-tablosuna-sahte-TSA-token'ı-enjekte ( TSA-çağrısı-YAPMADAN)
conn.execute("UPDATE evidence_seals SET tsa_token=? WHERE seal_id=?",
             (fake_seal, r["seal_id"]))
conn.commit()
v = verify_seals(conn)
res = v["results"][0]
print(f"  2-B1: sahte-token'lı-seal → all_ok={v['all_ok']},"
      f" countersigned={res['countersigned']}, countersign_ok={res['countersign_ok']}")
# AT-187-BULGU-1-KAPALDI: PEM-ayarlı-olduğundan-sahte-token-artık-RED
assert res["countersign_ok"] is not True, \
    "AT-187-kapanmadı! sahte-token-hâlâ-countersigned-raporlanır ( fail-OPEN)"
print("        → AT-187-BULGU-1-KAPALDI: sahte-TSA-token-artık-reddedilir")
print("           ( kanıt-üretim-tarihi-iddiası-sahtelenemez)")

# --- 3) AT-187-BULGU-1-KAPALDI: kaynak-teyidi — PKI-doğrulama-artık-var
src = open("/home/gokun/projects/00_TAMGA-MESH/swarmax/src/swarmax/tsa.py",
           encoding="utf-8").read()
assert "imprint not in token" in src, "binding-yapısı-değişti"
assert "openssl ts -verify" in src, "AT-187-kapanmadı! PKI-yolu-yok"
assert "_verify_pki" in src, "PKI-yardımcı-işlevi-yok"
assert "SWARMAX_TSA_PEM" in src, "operatör-sözleşmesi-yok"
print("  3-B1: kaynak-teyidi — openssl ts -verify + SWARMAX_TSA_PEM")
print("        → AT-187-BULGU-1-KAPALDI: DER-imza-artık-doğrulanır ( PEM-ile)")

# --- N1) karşıt: YANLIŞ-imprint → RED ( binding-yolu-doğru-çalışır)
os.environ.pop("SWARMAX_TSA_PEM", None)   # binding'i-izole-et ( PKI'sız)
import warnings as _W
with _W.catch_warnings():
    _W.simplefilter("ignore")
    _v1 = verify_token_binding(b"\x30" + hashlib.sha256(b"different-data").digest()
                               + b"\x00" * 10, msg)
    _v2 = verify_token_binding(b"\x30" + hashlib.sha256(msg).digest()
                               + b"\x00" * 10, msg)
print(f"  N1-TEMİZ: yanlış-imprint → {_v1}; doğru-imprint ( PEM'siz) → {_v2}")
assert _v1 is False
assert _v2 is True   # binding-dürüst-yolu ( PEM'siz-uyarı-ile)
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) swarmax-TSA-token-imzası-doğrulanmıyor ( BULGU)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) swarmax"; cat "$LOG"; }

# ============================================ B) TEMİZ: tamga-cmd_ledger_verify
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, pathlib, tempfile, os, contextlib, io
os.environ["TAMGA_KS_PASSPHRASE"] = "at187-test-passphrase-16"
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
import tamga_runner as T

tmp = pathlib.Path(tempfile.mkdtemp())

def run(args):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = T.cmd_ledger_verify(args)
    try:
        return rc, json.loads(buf.getvalue())
    except json.JSONDecodeError:
        return rc, {"raw": buf.getvalue()[:80]}

# --- N2a) eksik-dizin → RED ( "could not look never green")
rc, d = run([str(tmp / "YOK")])
print(f"  N2a-TEMİZ: eksik-dizin → rc={rc}, ok={d.get('ok')},"
      f" reason_code={d.get('reason_code')}")
assert rc == 1 and d.get("ok") is False and d.get("reason_code") == 19
print("        → 'could not look' never-green ( sahte-GREEN-kapalı)")

# --- N2b) boş-zincir = kurallı-pre-genesis ( GREEN — doğru-kural)
pkg = tmp / "pkg"
pkg.mkdir()
(pkg / "tamga.json").write_text("{}", encoding="utf-8")
rc2, d2 = run([str(pkg)])
print(f"  N2b-TEMİZ: boş-zincir ( pre-genesis) → rc={rc2}, ok={d2.get('ok')},"
      f" note={str(d2.get('note'))[:40]}")
assert rc2 == 0 and d2.get("ok") is True
print("        → boş-zincir-geçerli ( pre-genesis-kurallı)")

# --- N2c) delivery_hash-SHAPE-hatası → RED rc10 ( h-geçerli-sonra-shape-boz)
import hashlib as _hl
from tamga_canon import jcs as _jcs
lp = pkg / "ledger.jsonl"
def _h(rec):
    no_h = {k: v for k, v in rec.items()}
    body = "0" * 64 + _jcs(no_h).decode("utf-8") if isinstance(_jcs(no_h), bytes) \
           else "0" * 64 + _jcs(no_h)
    return _hl.sha256(body.encode("utf-8")).hexdigest()
rec2 = {"op": "charge", "seq": 1, "prev": "0" * 64,
       "delivery_hash": {"alg": "md5", "hex": "c" * 64}}
rec2["h"] = _h(rec2)
lp.write_text(json.dumps(rec2) + "\n", encoding="utf-8")
rc3b, d3b = run([str(pkg)])
print(f"  N2c-TEMİZ: delivery_hash-alg=md5 ( hex-geçerli) → rc={rc3b},"
      f" reason_code={d3b.get('reason_code')}")
assert rc3b == 1 and d3b.get("reason_code") == 10, \
    f"shape-gate-beklendi: {d3b}"
print("        → shape-gate-RED ( yanlış-alg-etiketi-fake-cross-ledger)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) tamga-ledger-verify-fail-closed-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) tamga"; cat "$LOG"; }

# ============================================ C) TEMİZ: settlement+sovereign
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, pathlib, tempfile, os, warnings
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
import settlement_bind_verify as SB

def base_charge():
    return {"op": "charge", "seq": 1, "prev": "0" * 64, "h": "a" * 64,
            "stdout_sha256": "b" * 64,
            "delivery_hash": {"alg": "sha256", "hex": "c" * 64},
            "settlement_bind": {"scheme": "x402/v1", "payment_id": "PAY-1",
                                "claim_evidence_hash": {"alg": "sha256", "hex": "c"*64},
                                "payer": "0x" + "1" * 40,
                                "payee": "0x" + "2" * 40,
                                "verified_at": "2026-09-21T00:00:00Z"}}

def base_claim():
    return {"buyerAddress": "0x" + "1" * 40, "sellerAddress": "0x" + "2" * 40,
            "settlementRef": "PAY-1", "evidenceHash": {"alg": "sha256", "hex": "c"*64},
            "signature": "0xsig"}

SB._claim_signer = lambda d, s, scheme="x402/v1": "0x" + "1" * 40  # test-double

# --- 1) İNDETERMİNE: bilinmeyen-şema → RED-DEĞİL-İNDETERMİNE
c = base_charge(); c["settlement_bind"]["scheme"] = "tanimsiz/v9"
r = SB.verify(c, base_claim())
print(f"  1-C-TEMİZ: bilinmeyen-şema → verdict={r['verdict']}, rc={r['reason_code']}")
assert r["verdict"] == "İNDETERMİNE" and r["reason_code"] == 2
print("        → üçüncü-seçenek-yasak ( RED-DEĞİL, sonuç-esirgenir)")

# --- 2) evidenceHash-swap → RED rc7 ( fail-closed)
c2 = base_charge(); cl2 = base_claim(); cl2["evidenceHash"]["hex"] = "d" * 64
r2 = SB.verify(c2, cl2)
print(f"  N2-TEMİZ: evidenceHash-swap → verdict={r2['verdict']}, rc={r2['reason_code']}")
assert r2["verdict"] == "RED" and r2["reason_code"] == 7

# --- 3) party-swap → RED rc6 ( double- swapped-buyer'a-eşitlenir)
c3 = base_charge(); cl3 = base_claim()
cl3["buyerAddress"], cl3["sellerAddress"] = cl3["sellerAddress"], cl3["buyerAddress"]
SB._claim_signer = lambda d, s, scheme="x402/v1": cl3["buyerAddress"]
r3 = SB.verify(c3, cl3)
print(f"  N2b-TEMİZ: party-swap → verdict={r3['verdict']}, rc={r3['reason_code']}")
assert r3["verdict"] == "RED" and r3["reason_code"] == 6

# --- 4) settlement_bind-yok → RED rc1 ( ilk-RED-döner)
r4 = SB.verify({"op": "charge"}, base_claim())
print(f"  N2c-TEMİZ: bind-alanı-yok → verdict={r4['verdict']}, rc={r4['reason_code']}")
assert r4["verdict"] == "RED" and r4["reason_code"] == 1

# --- 5) sovereign RISK-1: var-olmayan-sester-db → RED ( sahte-GREEN-kapalı)
import sovereign_verify as SV
r5 = SV.verify_sester_ledger("/yol/yok/ledger.db")
print(f"  N3-TEMİZ: sovereign var-olmayan-db → ok={r5['ok']}, verdict={r5.get('verdict')}")
assert r5["ok"] is False
print("        → RISK-1-kapalı ( boş-DB-yaratıp-sahte-GREEN-RED)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) settlement+sovereign-fail-closed-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) tamga-tools"; cat "$LOG"; }

# ============================================ D) TEMİZ: verify_capacity+sester
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, os
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
from tamga_attest_verify import verify_capacity_attest

# --- N4) her-hata-yolu-RED ( fail-closed; None-geçişi-yok)
cases = [
    ("zarf-eksik", {}, "zarf-eksik"),
    ("claimId-yanlış", {"claimId": "0xabc", "signature": "0x" + "00"*65,
                        "buyerAddress": "0x" + "1"*40}, "claimId_mismatch"),
]
for name, claim, beklenen in cases:
    ok, reason, _ = verify_capacity_attest(claim)
    print(f"  N4a-TEMİZ: {name} → ok={ok}, reason={reason}")
    assert ok is False and beklenen in reason, f"{name}-RED-beklendi"

# yüksek-s ( EIP-2-malleability) → RED
sig_high_s = "0x" + "00"*32 + "ff"*32 + "1b"
ok, reason, _ = verify_capacity_attest({"claimId": "0x" + "0"*64,
    "signature": sig_high_s, "buyerAddress": "0x" + "1"*40})
print(f"  N4b-TEMİZ: yüksek-s-imza → ok={ok}, reason={reason}")
assert ok is False

# --- golden-vectors 7/7 ( negatifler-gerçek-yol)
vp = "/home/gokun/projects/00_TAMGA-MESH/tamga/tests/vendor-capacity-attest/golden-vectors.json"
d = json.load(open(vp, encoding="utf-8"))
vs = d["vectors"]
neg = [v for v in vs if not v["expect_ok"]]
print(f"  N4c-TEMİZ: golden-vectors {len(vs)}-toplam, {len(neg)}-negatif"
      f" ( {[v['name'] for v in neg]})")
for v in vs:
    ok, reason, _ = verify_capacity_attest(v["content"])
    hit = (ok == v["expect_ok"]) and (reason == (v["expect_reason"] or "ok"))
    assert hit, f"vektör-{v['name']}-uyumsuz: ok={ok} reason={reason}"
print("        → 7/7 bağımsız-koşum; negatifler-GERÇEK-yolu-koşer ( double-DEĞİL)")

# --- sester-middleware: facilitator-unknown → fail-closed ( kaynak-teyidi)
mw = open("/home/gokun/projects/00_TAMGA-MESH/sester/sester/middleware.py",
          encoding="utf-8").read()
assert 'fail-closed' in mw and "facilitator_unknown" in mw
print("  N4d-TEMİZ: sester-middleware 'unknown → fail-closed-RED' kaynakta-canlı")
# debug/verbose-atlama-bayrağı-YOK ( tüm-öncelik-yüzeylerde)
for f in ["/home/gokun/projects/00_TAMGA-MESH/sester/sester/middleware.py",
          "/home/gokun/projects/00_TAMGA-MESH/tamga/tamga_attest_verify.py",
          "/home/gokun/projects/00_TAMGA-MESH/tamga/tools/sovereign_verify.py",
          "/home/gokun/projects/00_TAMGA-MESH/tamga/tools/settlement_bind_verify.py"]:
    src = open(f, encoding="utf-8").read()
    assert "DEBUG_BYPASS" not in src and "skip_verify" not in src.lower(), \
        f"atlama-bayrağı-bulundu: {f}"
print("  N4e-TEMİZ: debug/verbose-verify-atlama-bayrağı-YOK ( 4-yüzey)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: D) verify_capacity+sester-middleware-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: D) temiz-modeller"; cat "$LOG"; }

echo
note "  öneri: swarmax verify_token_binding'e-openssl-PKI-çıkış-yolu-ekle ( subprocess"
note "         openssl ts -verify -CAfile <tsa.crt>) VEYA DER-imza-alanını-açıkça-"
note "         doğrula; trust_drill'de-verdict'i-ok_pki'ye-BAĞLA ( skip-loose-modda)."
echo "RESULT: $PASS PASS, $FAIL FAIL"
echo "  AT-187: Doğrulama-yolu — 1-BULGU (swarmax-TSA-imzası-doğrulanmıyor) +"
echo "          tamga/sester-fail-closed-TEMİZ"
[[ $FAIL -eq 0 ]]
