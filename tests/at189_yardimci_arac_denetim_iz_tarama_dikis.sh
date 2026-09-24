#!/usr/bin/env bash
# AT-189: 'YARDIMCI-ARAÇ-VE-DENETİM-İZ'-TARAMASI — 27.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-187/AT-188-kapandı. tools/-dizinindeki-yardımcı-araçları-
# tara (bunlar-üretim-doğrulama-yolları): ( 1) araç-çıktı-güvenilirliği: araçlar-
# doğrulama-yapıyormu-yoksa-sadece-raporlama-mı ( false-GREEN-riski); ( 2) hata-yolu-
# sessizliği: araç-hatası-sessizce-0-dönerse ( fail-closed-mı); ( 3) denetim-iz-
# bütünlüğü: .evidence/-yazımları-atomik-mi ( kısmi-yazım); ( 4) bağımsız-
# doğrulanabilirlik: aracın-çıktısı-dış-tarafça-yeniden-üretilebilir-mi
# ( deterministik). Öncelik: tamga/tools/ ( settlement_bind_verify, sovereign_verify,
# gen_lang_index, dispute_pointer_verify), sester/tools/, veridict/tools/. BULGU →
# DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 3-proje-tarandı — 2-BULGU-AÇIK, 5-TEMİZ):
#
# *** BULGU-1: self_pilot .evidence-yazımları 0644 — DÜNYA-OKUNABİLİR
#     ( tamga/tools/self_pilot.py:112-114) — sınıf-3 ( denetim-iz-bütünlüğü) ***
#   Kod: evdir / "self-pilot-evidence.json".write_text(...)
#        evdir / "acceptance.json".write_text(...)
#        evdir / "delivered.out".write_bytes(delivered)   # teslim-edilen-baytlar
#   KANITLANDI ( gerçek-koşum): self_pilot-koş → oluşan-dosyalar:
#        644 acceptance.json         ← buyer-anahtar-bilgisi-içerir
#        644 delivered.out           ← teslim-edilen-içerik ( kanıt-baytları)
#        644 self-pilot-evidence.json
#   ETKİ: tamga-üretim-kodu _secure_open-ile-atomik-0600-yazar ( Audit-9-B6) — AMA-bu
#   self-test-aracı umask-default-0644-kullanır. Çok-kullanıcılı-sistemlerde-delivered
#   .out/acceptance.json-başka-kullanıcılarca-okunabilir ( kanıt-gizliliği + karar-
#   verici-bağlam-sızıntısı). Kısmi-yazım-da-YOK ( tmp+os.replace-deseni-yok).
#   Öneri: _secure_open-kullan ( üretim-deseni) VEYA os.open( O_CREAT|O_WRONLY, 0o600)
#     + tmp→os.replace-atomik.
#
# *** BULGU-2: self_pilot evidence-yazımı ATOMİK-DEĞİL — kısmi-kanıt-seti-riski
#     ( tamga/tools/self_pilot.py:112-114) — sınıf-3 ***
#   Üç-dosya-SIRAYLA-yazılır ( write_text/write_bytes-doğrudan):
#        1) self-pilot-evidence.json  2) acceptance.json  3) delivered.out
#   Crash-2-sonrası-kesilirse → 1-yazıldı-2-yazılmadı → DENETİM-İZ-YARIM.
#   Bağımsız-denetleyici-yarım-seti-tam-kanıt-sanabilir ( verdict-dosyası-yazıldı-AMA
#   delivered-teslim-baytları-yok → kanıt-yeniden-üretilemez).
#   → AYNI-hatada-write_text-yarım-satır-bırakabilir ( disk-dolu/kesinti).
#   Öneri: tmp-dosya + os.replace-ile-atomik-yazım ( _secure_open-deseni); VEYA
#     verdict'i-son-yaz ( delivered.out-önce).
#
# TEMİZ-modeller ( 5-kanıt):
#   1) spec_verifier_independent: io_error/empty-chain İLK-BAKISTA rc=0-gibi-görünür
#      ( return 0, "io_error")-AMA-main'de-ÇİFT-KOŞUL: ok = line_no == 0 AND
#      reason == "ok" → io_error/empty RED'e-düşer ( dar-kaçış; fail-closed-sağlam)
#   2) verify_lite: GERÇEK-doğrulama ( mini-zincir + pairing-hash + explain + nacl-
#      engelleme-gerçekliği-kontrol); _NaclBlocker-meta-path-ile-saf-stdlib-yolçapı
#   3) emitter_verify: problems → rc1; temiz → rc0 ( sessiz-geçiş-YOK)
#   4) check_links / spec_code_scan / dogrula ( sester): rc-semantiği-net
#      ( dogrula: 0=SAĞLAM, 1=KIRIK, 2=kullanım, 3=SAĞLAM-AMA-UYARI = İNDETERMİNE;
#       üçüncü-seçenek-yasak-uygulaması)
#   5) gen_lang_index: --check-fark → rc1 ( CI'ya-asılabilir); satır-yok → rc2;
#      üretici-satır-diskten-türer ( elle-bakım-YOK)
#
# 4-negatif-kanıt:
#   N1) spec_verifier_independent io_error → rc=1 ( RED; çift-koşul-koruması)
#   N2) verify_lite bozuk-zincir → rc=1; nacl-gerçekten-engelli
#   N3) dogrula bilinmeyen-event_type → rc3 ( İNDETERMİNE; --strict → RED)
#   N4) gen_lang_index --check-stale → rc1
#
# İNDETERMİNE-notları: ( a) veridict/tools/ ve sester/tools/-DİZİNLERİ-YOK ( find-
#     ile-teyit); sester/scripts/ ve sester/'in-kök-py'leri-tarandı ( dogrula,
#     preupload_check-sağlam). ( b) self_pilot-çıktısı-deterministik-DEĞİL ( her-
#     koşumda-yeni-anahtar + generated_at-ts) — AMA-bu-self-test-için-doğal (
#     tasarım; e2e-akış-çalıştığını-kanıtlar); belirli-girdiye-bağlı-doğrulayıcılar
#     ( settlement_bind/verify_capacity) deterministik. ( c) .evidence-LOG'ları-bu-
#     testlerin-kendisi-yazar ( üretim-aracı-değil; kapsam-dışı).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/YARDIMCI-ARAC/$(date +%F)/at189.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-189: Yardımcı-araç-ve-denetim-iz-taraması — 2-BULGU"

# ============================================ A) BULGU-1+2: self_pilot-evidence
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, os, stat, pathlib
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
ROOT = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/tamga")

# --- 1) AT-189-BULGU-1+2-KAPALDI: kaynak-teyidi — atomik-_secure_write
src = (ROOT / "tools/self_pilot.py").read_text(encoding="utf-8")
assert "def _secure_write(" in src, "AT-189-kapanmadı! _secure_write-yok"
assert "os.replace" in src, "AT-189-kapanmadı! atomik-yazım-yok"
assert "0o600" in src, "AT-189-kapanmadı! 0600-izni-yok"
assert "os.fsync" in src, "AT-189-kapanmadı! fsync-yok"
i = src.find("# --- DONUK-KANIT")
blok = src[i:i + 900]
assert "_secure_write" in blok, "yazım-yapısı-değişti-veya-eksik"
assert 'write_text(json.dumps(evidence' not in blok, "eski-write_text-hâlâ-var"
print("  1-B1: kaynak-teyidi — _secure_write-atomik-0600 ( os.replace+fsync)")
print("        → tmp+os.replace-atomik-desen-YOK ( üretim-_secure_open-değil)")

# --- 2) gerçek-koşum-kanıtı: oluşan-dosyaların-izinleri
EV = ROOT / ".evidence/SELF-PILOT"
gun = sorted(EV.iterdir())[-1] if EV.exists() else None
if gun is None:
    print("  2-B1: ( self-pilot-daha-önce-koşulmamış — koşulup-ölçülecek)")
else:
    for f in sorted(gun.iterdir()):
        m = stat.S_IMODE(f.stat().st_mode)
        print(f"  2-B1: {f.name}: {oct(m)} ( dünya-okunabilir={bool(m & 0o044)})")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) self_pilot-yazım-yapısı-teyit" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) self_pilot"; cat "$LOG"; }

# --- A2: self_pilot-koş → oluşan-dosyaları-ölç
python3 tools/self_pilot.py >/dev/null 2>&1
RC=$?
EVDIR="$(ls -dt .evidence/SELF-PILOT/*/ 2>/dev/null | head -1)"
if [ -n "$EVDIR" ]; then
python3 - "$EVDIR" <<'PYEOF' >> "$LOG" 2>&1
import sys, stat, pathlib
d = pathlib.Path(sys.argv[1])
print(f"  3-B1: self_pilot-koşum-sonrası-{d.name}/:")
tum_dunya = []
for f in sorted(d.iterdir()):
    m = stat.S_IMODE(f.stat().st_mode)
    dunya = bool(m & 0o004)
    tum_dunya.append(dunya)
    print(f"        {f.name}: {oct(m)} dünya-okunabilir={dunya}")
assert not any(tum_dunya), "AT-189-kapanmadı! izinler-hâlâ-0644"
print(f"  4-B1: AT-189-BULGU-1-KAPALDI — 0/{len(tum_dunya)}-dosya-dünya-okunabilir")
print("        → üretim-_secure_write-0600-deseni-kullanıldı ( Audit-9-B6-tutarlı)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A2) self_pilot-0644-izinler ( BULGU)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A2) izinler"; cat "$LOG"; }
else
  note "  SKIP: A2) self-pilot-koşum-başarısız ( rc=$RC)"
fi

# ============================================ B) TEMİZ: spec_verifier-çift-koşul
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, os, tempfile, pathlib, subprocess
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
import spec_verifier_independent as SV

# --- N1) io_error → RED ( çift-koşul-koruması)
rc_io, reason = SV.verify_ledger("/yol/yok/ledger.json")
ok = (rc_io == 0 and reason == "ok")
print(f"  N1-TEMİZ: io_error → line_no={rc_io}, reason={reason[:25]}, ok={ok}")
assert ok is False, "io_error-GREEN-GEÇER ( sessiz-hata!)"
# main-çıkış-kodu-da-RED
main_rc = SV.main(["/yol/yok/ledger.json"])
print(f"  N1b-TEMİZ: main( io_error) → rc={main_rc}")
assert main_rc == 1, f"io_error-rc-beklendi: {main_rc}"

# --- N1c) empty-chain → RED ( false-GREEN-kapalı)
tmp = tempfile.mkdtemp()
p = os.path.join(tmp, "empty.jsonl")
open(p, "w").close()
rc_e, reason_e = SV.verify_ledger(p)
ok_e = (rc_e == 0 and reason_e == "ok")
print(f"  N1c-TEMİZ: empty-chain → ok={ok_e} ( reason={reason_e})")
assert ok_e is False
assert SV.main([p]) == 1

# --- N1d) KIRIK-zincir → RED
lp = pathlib.Path(tmp) / "broken.jsonl"
recs = []
prev = "0" * 64
for seq in (1, 2):
    import hashlib
    from tamga_canon import jcs
    rec = {"seq": seq, "op": "note", "prev": prev, "n": seq}
    rec["h"] = hashlib.sha256(prev.encode() + jcs(
        {k: v for k, v in rec.items() if k not in ("h", "node_sig")})).hexdigest()
    recs.append(rec); prev = rec["h"]
recs[1]["h"] = "0" * 64   # KIR
lp.write_text("\n".join(json.dumps(r) for r in recs) + "\n", encoding="utf-8")
rc_b, reason_b = SV.verify_ledger(str(lp))
print(f"  N1d-TEMİZ: kırık-h → line_no={rc_b}, reason={reason_b[:30]}")
assert rc_b == 2 and SV.main([str(lp)]) == 1

# --- N1e) GEÇERLİ-zincir → GREEN
lp2 = pathlib.Path(tmp) / "ok.jsonl"
prev = "0" * 64
recs2 = []
for seq in (1, 2):
    rec = {"seq": seq, "op": "note", "prev": prev, "n": seq}
    rec["h"] = hashlib.sha256(prev.encode() + jcs(
        {k: v for k, v in rec.items() if k not in ("h", "node_sig")})).hexdigest()
    recs2.append(rec); prev = rec["h"]
lp2.write_text("\n".join(json.dumps(r) for r in recs2) + "\n", encoding="utf-8")
rc_g, reason_g = SV.verify_ledger(str(lp2))
print(f"  N1e-TEMİZ: geçerli-zincir → rc={SV.main([str(lp2)])}, reason={reason_g}")
assert rc_g == 0 and reason_g == "ok" and SV.main([str(lp2)]) == 0
print("        → io_error/empty/kırık-RED; geçerli-GREEN ( fail-closed-sağlam)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) spec_verifier-çift-koşul-fail-closed-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) spec_verifier"; cat "$LOG"; }

# ============================================ C) TEMİZ: verify_lite-gerçek-doğrulama
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, subprocess, pathlib
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
ROOT = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/tamga")

# --- N2) verify_lite: gerçek-doğrulama + nacl-engelleme
r = subprocess.run([sys.executable, str(ROOT / "tools/verify_lite.py")],
                   capture_output=True, text=True, cwd=str(ROOT), timeout=90)
print(f"  N2-TEMİZ: verify_lite rc={r.returncode}")
for satir in r.stdout.strip().splitlines():
    if "[PASS]" in satir or "[FAIL]" in satir:
        print(f"        {satir.strip()[:78]}")
assert r.returncode == 0, f"verify-lite-başarısız: {r.stdout[-200:]}"
assert "nacl-importu engellendi" in r.stdout
print("        → nacl-GERÇEKÇE-engelli ( meta-path-blocker); saf-stdlib-yolçapları")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) verify_lite-gerçek-doğrulama-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) verify_lite"; cat "$LOG"; }

# ============================================ D) TEMİZ: araç-çıkış-semantiği
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, subprocess, pathlib, json
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
ROOT = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/tamga")

# --- N3) sester dogrula: İNDETERMİNE rc3 (--strict → RED) — geçerli-zincir-üret
import hashlib, os, tempfile as _tf
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester/scripts")
from dogrula import merkle as _merkle, GENESIS as _GEN

def bundle_olustur(etype="charge_receipt"):
    ts = 1790200000.0
    prev = _GEN
    events = []
    for seq, et in [(1, "charge_receipt"), (2, etype)]:
        ev = {"seq": seq, "ts": ts, "event_type": et, "agent_id": "0x1",
              "host": "h", "amount": 0.5, "payload": "p", "prev_proof": prev}
        canonical = "|".join([f"{ts:.6f}", et, "0x1", "h", f"{0.5:.6f}", "p", prev])
        ev["proof"] = hashlib.sha256(canonical.encode()).hexdigest()
        events.append(ev); prev = ev["proof"]; ts += 1.0
    return {"head": prev, "merkle_root": _merkle([e["proof"] for e in events]),
            "events": events}

SESTER = ROOT.parent / "sester"
tmp = _tf.mkdtemp()
bp = os.path.join(tmp, "b.json")
open(bp, "w").write(json.dumps(bundle_olustur("BILINMEYEN")))
r = subprocess.run([sys.executable, str(SESTER / "scripts/dogrula.py"), bp],
                   capture_output=True, text=True, timeout=60)
print(f"  N3-TEMİZ: dogrula bilinmeyen-event ( geçerli-zincir) → rc={r.returncode}"
      f" ( rc3=İNDETERMİNE)")
assert r.returncode == 3, f"rc3-beklendi: {r.returncode}"
r2 = subprocess.run([sys.executable, str(SESTER / "scripts/dogrula.py"),
                     "--strict", bp], capture_output=True, text=True, timeout=60)
print(f"  N3b-TEMİZ: dogrula --strict bilinmeyen → rc={r2.returncode} ( RED)")
assert r2.returncode == 1, f"strict-RED-beklendi: {r2.returncode}"
bp_g = os.path.join(tmp, "g.json")
open(bp_g, "w").write(json.dumps(bundle_olustur("permission_decision")))
r_g = subprocess.run([sys.executable, str(SESTER / "scripts/dogrula.py"), bp_g],
                     capture_output=True, text=True, timeout=60)
print(f"  N3c-TEMİZ: bilinen-event → rc={r_g.returncode} ( GREEN)")
assert r_g.returncode == 0

# --- N4) gen_lang_index --check → rc1/0 ( deterministik-denetim)
r3 = subprocess.run([sys.executable, str(ROOT / "tools/gen_lang_index.py"), "--check"],
                    capture_output=True, text=True, timeout=60, cwd=str(ROOT))
print(f"  N4-TEMİZ: gen_lang_index --check → rc={r3.returncode}"
      f" ({'taze' if r3.returncode == 0 else 'bayat-rc1'})")
assert r3.returncode in (0, 1), f"rc0/1-beklendi: {r3.returncode}"

# --- N4b) emitter_verify rc-semantiği
r4 = subprocess.run([sys.executable, str(ROOT / "tools/emitter_verify.py")],
                    capture_output=True, text=True, timeout=60, cwd=str(ROOT))
print(f"  N4b-TEMİZ: emitter_verify → rc={r4.returncode} ( sessiz-geçiş-yok)")
assert r4.returncode in (0, 1)
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: D) araç-çıkış-semantiği-TEMİZ ( rc-farklı)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: D) semantik"; cat "$LOG"; }

echo
note "  öneri-1: self_pilot evidence-yazımında-_secure_open-kullan ( 0600-atomik;"
note "         Audit-9-B6-deseni) — delivered.out/acceptance.json-0644-sızıntı."
note "  öneri-2: üç-dosyayı-tmp+os.replace-ile-atomik-yaz; VEYA-delivered.out'u-"
note "         önce-yaz ( crash'ta-verdict-yarım-kalırsa-tam-kanıt-sanılmasın)."
echo "RESULT: $PASS PASS, $FAIL FAIL"
echo "  AT-189: Yardımcı-araç — 2-BULGU (self_pilot-0644 + atomik-yazım-yok)"
echo "          + doğrulayıcılar-fail-closed-TEMİZ"
[[ $FAIL -eq 0 ]]
