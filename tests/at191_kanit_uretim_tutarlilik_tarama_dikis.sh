#!/usr/bin/env bash
# AT-191: 'KANIT-ÜRETİM-TUTARLILIK'-TARAMASI — 29.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-189/AT-190-kapandı. Kanıt-üretim-tutarlılığını-tara
# ( cross-artifact-bütünlük): ( 1) kanıt-referans-çözümü: evidence_hash/kanıt-
# adı-başka-depo-veya-dizine-işaret-ediyorsa-çözülebilir-mi ( dangling-reference);
# ( 2) yinelenen-kanıt-adı: aynı-ad-2-depodaysa-çakışma ( kanıt-karışıklığı);
# ( 3) tarih-dizisi: YYYY-MM-DD-dizini-gerçek-tarihle-uyumlu-mu ( gelecek-tarih);
# ( 4) RFC-010 §4-bağlama: settlement-bind-gerçekten-evidence-hash'i-bağladı-mı
# ( sadece-dize-olarak-değil). Öncelik: tamga/.evidence/, 05_acik_kaynak/
# TamgaProtocol/.evidence/, RFC-010-§6.1-whitelist-13-zincir. BULGU → DÜRÜST-
# rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 2-kanıt-deposu + RFC-010-yolu — 2-BULGU-AÇIK, 2-TEMİZ):
#
# *** BULGU-1: foreign_chain_proof kanıt-adı GERÇEK-DEPOYA-ÇÖZÜLMÜYOR
#     ( tamga/tools/settlement_bind_verify.py:22-63 _foreign_chain_ok) — sınıf-1 ***
#   §6.1-whitelist-13-zincir ( swarmax|dumen|pqhaven|tamga|fleksa|sester|veridict|
#   pacta|pactiva|yieldix|syntropion|tenderix|veridrome) DENETLENİR-AMA:
#       head_hex → 64-hex-FORMAT-Denetimi ( içerik-DEĞİL)
#       evidence_link "derived" → head == sha256( receipt-bytes) — FORMÜL-tutarlı
#       verify_cmd → "ÇALIŞTIRILMAZ, yalnızca-denetim-izi-için-kaydedilir"
#   KANITLANDI: swarmax-deposuna-HİÇ-BAŞVURMADAN sahte-kanıt:
#       {"chain":"swarmax", "head_hex":sha256(receipt), "entries":1,
#        "evidence_link":"derived", "verify_cmd":"swarmax verify --db YOK.db"}
#     → _foreign_chain_ok=True → check-6-GREEN. GERÇEK-zincir-varlığı/çürük-lüğü
#       SORGULANMADI ( kanıt-adı-dangling-by-design).
#   ETKİ: cross-artifact-bütünlük-iddiası-zayıf — "swarmax-kanıtlı-dikiş"
#     aslında-sadece-formül-tutarlı; swarmax-zinciri-kırık-olsa-BİLE-GREEN.
#     ( RFC-010-bunu-açıkça-itiraf-eder: "biz-yabancı-zinciri-kendimiz-yeniden-
#     doğrulamayız, onun-kanıtını-kabul-ederiz" — üçüncü-seçenek-yasak-tasarımı;
#     AMA-AT-191'in-sorusuna-cevap: HAYIR, kanıt-adı-çözülemez → dangling.)
#   ÜRETİM-TEST'lerinde verify_cmd="n/a" ( at069) — komut-HİÇ-çalıştırılmıyor.
#   Öneri: verify_cmd'ı-denetim-modunda-ÇALIŞTIR ( subprocess; kullanıcı-izni-ile)
#     VEYA head_hex'i-chain'e-göre-gerçek-lookup-ile-doğrula ( swarmax-db-aç).
#
# *** BULGU-2: kanıt-deposu-İKİZ-ERİŞİM — 209/209-ad-aynı-inode
#     ( tamga/.evidence/ ↔ 05_acik_kaynak/TamgaProtocol/.evidence/) — sınıf-2 ***
#   KANITLANDI: iki-dizin-AYNI-inode ( stat-%i-ile):
#       4196152 = 4196152 ( hardlink/mount-ikizi)
#       ls-karşılaştırma: 209/209-ad-kesişir ( comm-12)
#   ETKİ: "aynı-ad-2-depodaysa-çakışma" senaryosu-BURADA-GERÇEK-çakışma-DEĞİL
#     ( tek-fiziksel-depo-iki-isimle); AMA-denetim-iz'de-bir-kanıt-iki-yoldan
#     kayıtlı-gibi-görünür → kanıt-karışıklığı-riski ( hangi-depo-sorumlu?).
#     Üretim-doğrulama-yolu-bunu-fark-edecek-mekanizma-YOK ( yol-bağımı).
#   → İKİZ-ERİŞİM-olarak-raporlandı ( veri-tutarsızlığı-DEĞİL, erişim-yolu-
#     ikizliği); güvenlik-açığı-derecesi-düşük-AMA-kanıt-karışıklığı-sınıfında.
#   Öneri: erişimi-tek-yola-sabitle ( symlink-veya-tek-kaynak-yolu); denetim-
#     araçlarında-inode-tutarlılık-kontrolü.
#
# TEMİZ-modeller ( 2-kanıt):
#   1) tarih-dizisi: .evidence/<SINIF>/YYYY-MM-DD/ — 2026-09-24'ten-İLERİ-tarih
#      YOK ( awk-ile-tam-tarama); tarihler-gerçek-zamanla-uyumlu
#   2) RFC-010-§4-bağlama: settlement_bind_verify-check-5 BAYT-EŞİT-bağlar —
#      evidenceHash.alg-DA-BAĞLI ( sha256-vs-keccak256-alg-swap, hex-AYNI → RED
#      rc7); hex-swap → RED rc7; doğru-bağlama → GREEN
#
# 2-negatif-kanıt:
#   N1) §4 alg-swap ( hex-aynı) → RED rc7 ( sadece-dize-değil, algoritma-da)
#   N2) whitelist-dışı-chain → RED ( 13-zincir-dışı-çürüktür)
#
# İNDETERMİNE-notları: ( a) BULGU-1 RFC-010-§6.1'de-AÇIKÇA-belgeli-tasarım-
#     kararı ( "üçüncü-seçenek-yasak: yabancı-zinciri-kendimiz-doğrulamayız") —
#     self-documented-limitation; AMA-AT-191-alt-sınıf-1'in-sorusuna-dürüst-cevap
#     "çözülemez" olduğu için BULGU-olarak-raporlandı ( bulgu-uydurma-değil,
#     sorulan-yüzeyde-ölçüldü). ( b) foreign_chain_proof-YOK → GREEN ( geri-
#     uyumluluk; eski-dikişler-kırılmaz) — TASARIM, açıklıkla-belgeli. ( c)
#     §6.2-derived-halkası: head_hex == sha256(bytes.fromhex(receipt)) — bu-
#     formül-DOĞRU-çalışır ( ölçüldü); sorun-yalnızca-gerçek-zincire-bağlanmaması.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/KANIT-URETIM-TUTARLILIK/$(date +%F)/at191.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-191: Kanıt-üretim-tutarlılık-taraması — 2-BULGU"

# ============================================ A) BULGU-1: foreign_chain dangling
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, hashlib, json, os
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
import settlement_bind_verify as SB

# --- 1) AT-191-BULGU-1-KAPALDI: head_source-YOKSA-eski-davranış ( RFC-010
#     §6.1-sözleşmesi-korunur: yabancı-zinciri-kendimiz-yeniden-doğrulamayız)
receipt_hex = "c" * 64
sahte = {"chain": "swarmax",
         "head_hex": hashlib.sha256(bytes.fromhex(receipt_hex)).hexdigest(),
         "entries": 1, "evidence_link": "derived",
         "verify_cmd": "swarmax verify --db /yol/yok.db"}
ok = SB._foreign_chain_ok(sahte, "0x1", receipt_hex, "x402/v1")
print(f"  1-B1: head_source-YOK → eski-davranış ok6={ok} ( RFC-010 §6.1-korunur)")
assert ok is True, "geri-uyumlu-yol-bozuk ( eski-dikişler-kırılır)"
print("        → AT-191-KAPALDI: head_source-VERİLİNCE-gerçek-zincire-çözülür")

# --- 1b) AT-191-KAPALDI: head_source-VAR-AMA-yanlış-kök → RED ( dangling-YOK)
import pathlib as _P, tempfile as _TF
_bad = _P.Path(_TF.mktemp(suffix=".head")); _bad.write_text("0" * 64)
sahte2 = dict(sahte); sahte2["head_source"] = str(_bad)
ok2 = SB._foreign_chain_ok(sahte2, "0x1", receipt_hex, "x402/v1")
print(f"  1b-B1: head_source-yanlış-kök → {ok2} ( dangling-artık-RED)")
assert ok2 is False, "AT-192-kapanmadı! head_source-yanlış-kök-kabul"
# --- 1c) head_source-DOĞRU-kök → GREEN ( dürüst-yol)
_bad.write_text(sahte["head_hex"])
ok3 = SB._foreign_chain_ok(sahte2, "0x1", receipt_hex, "x402/v1")
print(f"  1c-B1: head_source-DOĞRU-kök → {ok3} ( gerçek-zincire-çözüldü)")
assert ok3 is True, "dürüst-head_source-yolu-bozuk"
_bad.unlink(missing_ok=True)

# --- 2) equals-link: head_source-YOK → eski-davranış ( geri-uyumlu)
ok_eq = SB._foreign_chain_ok({"chain": "pacta", "head_hex": receipt_hex,
    "entries": 5, "evidence_link": "equals"}, "0x1", receipt_hex, "x402/v1")
print(f"  2-B1: equals-link ( head_source-YOK) → {ok_eq} ( geri-uyumlu-yol)")
assert ok_eq is True

# --- N2) whitelist-dışı → RED ( bu-yol-sağlam)
ok_wl = SB._foreign_chain_ok({"chain": "SAYISAL-ZINCIR", "head_hex": "d" * 64,
    "entries": 1}, "0x1", receipt_hex, "x402/v1")
print(f"  N2-TEMİZ: whitelist-dışı-chain → {ok_wl} ( RED-beklenir)")
assert ok_wl is False

# --- 3) verify_cmd-HİÇ-ÇALIŞTIRILMIYOR ( kaynak-teyidi)
src = open("/home/gokun/projects/00_TAMGA-MESH/tamga/tools/settlement_bind_verify.py",
           encoding="utf-8").read()
assert "çalıştırılmaz" in src or "ÇALIŞTIRILMAZ" in src, "verify_cmd-yorumu-değişti"
assert "subprocess" not in src.split("def _foreign_chain_ok")[1].split("def verify")[0], \
    "AÇIK-KAPANDI! verify_cmd-artık-çalıştırılıyor"
print("  3-B1: kaynak-teyidi — verify_cmd 'ÇALIŞTIRILMAZ' ( subprocess-yok)")
print("        → kanıt-komutu-denetim-izinde-kayıtlı-AMA-uygulanmıyor")

# --- 4) üretim-test'inde-verify_cmd="n/a" ( at069)
t = open("/home/gokun/projects/00_TAMGA-MESH/tamga/tests/at069_foreign_chain_gate.sh",
         encoding="utf-8").read()
assert '"verify_cmd": "n/a"' in t, "at069-verify_cmd-yapısı-değişti"
print('  4-B1: üretim-testinde verify_cmd="n/a" — komut-HİÇ-çalıştırılmıyor')
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) foreign_chain-kanıt-adı-dangling ( BULGU)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) foreign_chain"; cat "$LOG"; }

# ============================================ B) BULGU-2: ikiz-erişim
python3 - <<'PYEOF' >> "$LOG" 2>&1
import os, pathlib

P1 = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/tamga/.evidence")
P2 = pathlib.Path("/home/gokun/projects/05_acik_kaynak/TamgaProtocol/.evidence")

# --- 1) inode-karşılaştırması ( aynı-fiziksel-depo-mu)
s1 = P1.stat().st_ino
s2 = P2.stat().st_ino if P2.exists() else None
print(f"  1-B2: inode-1={s1}, inode-2={s2}, AYNI={s1 == s2}")
assert s1 == s2 and s2 is not None, "ikiz-erişim-değişti ( ayrı-depo-oldu)"
print("        → iki-yol AYNI-fiziksel-depo ( hardlink/mount-ikizi)")

# --- 2) ad-kesişmesi
n1 = {p.name for p in P1.iterdir()}
n2 = {p.name for p in P2.iterdir()} if P2.exists() else set()
kesisim = n1 & n2
print(f"  2-B2: depo-1={len(n1)}-ad, depo-2={len(n2)}-ad, kesişen={len(kesisim)}")
assert len(kesisim) == len(n1) == len(n2)
print("        → 209/209-ad-kesişir ( 'aynı-ad-2-depo' görüntüsü)")

# --- 3) içerik-tutarlılık-kanıtı ( aynı-dosyaya-iki-yol)
f1 = (P1 / "AT-001").iterdir()
sub1 = next(f1)
f2 = P2 / "AT-001" / sub1.name
print(f"  3-B2: AT-001/{sub1.name}: inode-1={sub1.stat().st_ino},"
      f" inode-2={f2.stat().st_ino}, AYNI={sub1.stat().st_ino == f2.stat().st_ino}")
assert sub1.stat().st_ino == f2.stat().st_ino
print("        → dosya-düzeyinde-de-aynı ( gerçek-çakışma-DEĞİL, erişim-ikizliği)")
print("        → BULGU: denetim-iz'de-tek-kanıt-iki-yoldan-kayıtlı-gibi-görünür")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) kanıt-deposu-ikiz-erişim ( BULGU-notu)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) ikiz"; cat "$LOG"; }

# ============================================ C) TEMİZ: tarih-dizisi
python3 - <<'PYEOF' >> "$LOG" 2>&1
import os, datetime
from pathlib import Path

EV = Path("/home/gokun/projects/00_TAMGA-MESH/tamga/.evidence")
bugun = datetime.date.today()
gelecek = []
toplam = 0
for sinif in EV.iterdir():
    if not sinif.is_dir():
        continue
    for gun in sinif.iterdir():
        if not gun.is_dir():
            continue
        toplam += 1
        try:
            d = datetime.date.fromisoformat(gun.name)
        except ValueError:
            continue
        if d > bugun:
            gelecek.append(f"{sinif.name}/{gun.name}")

print(f"  1-C-TEMİZ: {toplam}-tarih-dizini-tarandı, gelecek-tarih={len(gelecek)}")
assert len(gelecek) == 0, f"GELECEK-TARİH-BULUNDU: {gelecek[:5]}"
print("        → 2026-09-24'ten-İLERİ-tarih-YOK ( tarihler-gerçek-zamanla-uyumlu)")

# --- format-tutarlılığı: hepsi-YYYY-MM-DD ( sonekli-alt-dizinler-ayrı-sayılır)
from collections import Counter
fmt = Counter()
for sinif in EV.iterdir():
    for gun in sinif.iterdir():
        if not gun.is_dir():
            continue
        try:
            datetime.date.fromisoformat(gun.name)
            fmt["iso"] += 1
        except ValueError:
            fmt[f"sonekli:{gun.name.split('-', 3)[-1] if gun.name.count('-') > 2 else gun.name}"] += 1
print(f"  2-C-TEMİZ: tarih-formatları={dict(fmt)}")
print("        → ana-format-ISO-YYYY-MM-DD; sonekli-alt-dizinler ( reprod-vb) ek-sürümler")
# sonekli-olanlar-ana-tarihten-ayrılabilir: ilk-10-karakter-ISO-olmalı
for k in fmt:
    if k.startswith("sonekli:"):
        continue
    assert k == "iso", f"format-dışı-tarih-dizini: {k}"
print("        → ISO-dışı-ana-tarih-formatı-YOK ( sonekli-sürümler-hariç)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) tarih-dizisi-gelecek-tarih-YOK-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) tarih"; cat "$LOG"; }

# ============================================ D) TEMİZ: RFC-010-§4-bağlama
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
import settlement_bind_verify as SB
SB._claim_signer = lambda d, s, scheme="x402/v1": "0x" + "1" * 40

def base():
    c = {"op": "charge", "seq": 1, "prev": "0" * 64, "h": "a" * 64,
         "stdout_sha256": "b" * 64,
         "delivery_hash": {"alg": "sha256", "hex": "c" * 64},
         "settlement_bind": {"scheme": "x402/v1", "payment_id": "PAY-1",
             "claim_evidence_hash": {"alg": "sha256", "hex": "c" * 64},
             "payer": "0x" + "1" * 40, "payee": "0x" + "2" * 40,
             "verified_at": "2026-09-21T00:00:00Z"}}
    cl = {"buyerAddress": "0x" + "1" * 40, "sellerAddress": "0x" + "2" * 40,
          "settlementRef": "PAY-1", "evidenceHash": {"alg": "sha256", "hex": "c" * 64},
          "signature": "0xsig"}
    return c, cl

# --- 1) doğru-bağlama → GREEN
c, cl = base()
r = SB.verify(c, cl)
print(f"  1-D-TEMİZ: doğru-bağlama → {r['verdict']},"
      f" check5={r['checks'].get('5_evidence_hash')}")
assert r["ok"] is True and r["checks"]["5_evidence_hash"] is True

# --- N1) alg-swap ( hex-AYNI, alg-farklı) → RED rc7
c2, cl2 = base()
cl2["evidenceHash"] = {"alg": "keccak256", "hex": "c" * 64}
r2 = SB.verify(c2, cl2)
print(f"  N1-TEMİZ: alg-swap ( sha256→keccak, hex-aynı) → {r2['verdict']},"
      f" rc={r2['reason_code']}")
assert r2["verdict"] == "RED" and r2["reason_code"] == 7
print("        → ALG-da-bağlanıyor ( sadece-dize-DEĞİL — §4-bağlama-sağlam)")

# --- 3) hex-swap → RED rc7
c3, cl3 = base()
cl3["evidenceHash"]["hex"] = "d" * 64
r3 = SB.verify(c3, cl3)
print(f"  N1b-TEMİZ: hex-swap → {r3['verdict']}, rc={r3['reason_code']}")
assert r3["reason_code"] == 7
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: D) RFC-010-§4-bağlama-alg+hex-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: D) §4"; cat "$LOG"; }

echo
note "  öneri-1: foreign_chain_proof verify_cmd'ı-denetim-modunda-ÇALIŞTIR ( subprocess;"
note "         kullanıcı-izni-ile) VEYA head_hex'i-chain'e-göre-gerçek-lookup-ile-doğrula"
note "         ( swarmax-db-aç) — kanıt-adı-şu-an-dangling ( formül-tutarlı-yeterli)."
note "  öneri-2: kanıt-deposu-erişimini-tek-yola-sabitle ( iki-yol-aynı-inode;"
note "         denetim-iz'de-kanıt-karışıklığı-riski); araçlarda-inode-kontrolü."
echo "RESULT: $PASS PASS, $FAIL FAIL"
echo "  AT-191: Kanıt-tutarlılık — 2-BULGU (foreign_chain-dangling, ikiz-erişim)"
echo "          + tarih-dizisi/§4-bağlama-TEMİZ"
[[ $FAIL -eq 0 ]]
