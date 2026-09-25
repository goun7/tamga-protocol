#!/usr/bin/env bash
# AT-194: 'GİRİŞ-TEMİZLİĞİ-VE-STANDART-YOL'-TARAMASI — 32.-sınıf ( Lead).
#
# LEAD'İN-TALİMATI: " Giriş-temizliği-yüzeylerini-tara ( injection-ve-bozulma):
# (1) Dış-giriş-doğrulama: kullanıcı/CLI-girişleri-temizleniyor-mu (
#   shell-injection-metin-birleştirmede); (2) Standart-yol-kullanımı:
#   pathlib/os.path-tutarlı-mı ( bu-oturumda-/tmp-yol-düzelttik — araçların-
#   geri-kalanı); (3) Meta-veri-güveni: JSON/manifest-güveni-bağlamadan-
#   doğrulanıyor-mu; (4) Tek-tip-hata-yolu: hata-kodları-tek-merkezde-mi (
#   dağınık-değil). Öncelik: tamga ( tools/, tamga_runner), sester ( cli),
#   dumen, tenderix, swarmax ( console). BULGU → DÜRÜST-rapor; YOKSA → temiz."
#
# TARAMA-SONUCU ( 5-proje-tarandı — TEMİZ-ÇIKTI + 2-zayıf-bakım-notu):
#
# *** TEMİZ-SONUÇ ( 4-alt-sınıf-tamamı-temiz) ***
#   (1) Dış-giriş-doğrulama: **shell=True-YOK** ( 5-projede-grep — sıfır);
#       tüm-subprocess-çağrılar LİSTE-form ( injection-mümkün-değil);
#       tamga_runner.py:731 WASMTIME: [WASMTIME,"run",str(pkg/"agent.wasm")]
#       + env={} ( host-env-sızıntısı-YOK) + RLIMIT_FSIZE ( kaynak-sınırı) —
#       AUDIT-3-F16/9-B6-sertleştirmesi-canlı
#   (2) Standart-yol: AT-190-düzeltmesi-canlı — /tmp/tamga-fixture +
#       /tmp/social-preview.svg → tempfile'a-geçti ( 2/4-kapandı);
#       kalan: spec_code_scan.py:185 ( /tmp/sahte.db) + mergen_batch ( /dev/shm)
#   (3) Meta-veri-güveni: registration_v1.py:82 manifest → NAME_RE.match-
#       doğrulaması + ValueError ( şema-dışı-reddi); verify()-sonrası-yük
#   (4) Tek-tip-hata: tamga out() TEK-merkez ( E-14-guard: REQUIRED_ARGS +
#       USAGE_HINT; sıfır-arg → mesaj-RED-traceback-DEĞİL); sester migrate_pg
#       --secret-ZORUNLU ( AT-179-canlı)
#
# *** BAKIM-1 (zayıf): kalan-2-sabit-/tmp-yolu ( araçlar-dış-yüz) ***
#   tools/spec_code_scan.py:185  "/tmp/sahte.db"  ( test-anchor-kaynağı)
#   private/mergen_batch.py:16-17  /dev/shm/mergen-batch + mergen-work
#   → düşük-etki ( araçlar; /dev/shm-Linux-özel-AMA-paylaşımlı-bellek-yerel)
#
# *** BAKIM-2 (zayıf): os.path/pathlib-karışımı ( tutarlılık-değil-hata) ***
#   tamga_net_shim.py:79 / tamga_runner.py:738 / tools/{3-dosya} — os.path.
#   kullanırken-diğer-yerler-pathlib. → stil-tutarlısızlığı ( işlevsel-temiz)
#
# TEMİZ-kanıtlar:
#   swarmax-console: input/eval/exec-YOK ( grep-boş)
#   dumen-cli: eval()-çağrısı = HF-model.eval() ( PyTorch-mod-modu — enjekte-değil)
#   tenderix: ValueError-şema-doğrulama ( "invalid y/point/seed size")
#
# Yedi-kanıt + 3-negatif:
#   1) TEMİZ: shell=True-sayısı=0 ( 5-proje-grep)
#   2) TEMİZ: subprocess-LİSTE-form ( wasmtime-örneği)
#   3) TEMİZ: env={} + RLIMIT ( host-sızıntısı-YOK)
#   4) TEMİZ: manifest-NAME_RE-doğrulama ( ValueError)
#   5) TEMİZ: out()-tek-merkez + sıfır-arg-mesaj-RED
#   6) BAKIM: 2-kalan-sabit-yol ( /tmp/sahte.db + /dev/shm)
#   7) TEMİZ: sester --secret-ZORUNLU ( AT-179-canlı)
#   N1) eval/exec-input-YOK ( enjekte-yüz-yok)
#   N2) JSON-yük-sonrası-verify ( bağlamadan-doğrulama)
#   N3) os.path-karışımı-işlevsel-temiz ( stil-notu)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/GIRIS-TEMIZLIGI-STANDART-YOL/$(date +%F)/at194.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-194: Giriş-temizliği/standart-yol-taraması ( 5-proje) — TEMİZ + 2-bakım"

# ============================================ A) TEMİZ: injection-taraması
python3 - <<'PYEOF' >> "$LOG" 2>&1
import glob, subprocess

# --- 1) TEMİZ: shell=True-sayısı=0 ( 5-proje-grep)
kokler = ["tamga", "sester", "dumen", "tenderix", "swarmax"]
toplam = 0
for kok in kokler:
    r = subprocess.run(
        ["grep", "-rnE", r"shell=True|os\.system\(|os\.popen\(",
         kok], capture_output=True, text=True,
        cwd="/home/gokun/projects/00_TAMGA-MESH")
    dosyalar = [l for l in r.stdout.splitlines()
                if ".venv" not in l and "__pycache__" not in l
                and "/build/" not in l and "/tests/" not in l
                and "/test_" not in l and ".sh:" not in l
                and ".md:" not in l and "progress" not in l
                and "/.evidence/" not in l and ".log:" not in l
                and "/.git/" not in l]
    # /32a (2026-09-25): .git/-metadata-üretim-kodu-değildir — commit-mesajları
    # "shell=True-yok"-gibi-tarama-kelimesi-içerebilir (false-positive); ayrıca
    # COMMIT_EDITMSG/packed-refs-gerçek-injection-yüzü-değil.
    toplam += len(dosyalar)
assert toplam == 0, f"shell-injection-yüzü-bulundu: {toplam}: {dosyalar[:3]}"
print(f"  1-TEMİZ: shell=True/os.system/os.popen-sayısı={toplam} ( 5-projede)")
print("        → tüm-subprocess-çağrılar LİSTE-form ( injection-imkânsız)")

# --- 2) TEMİZ: subprocess-LİSTE-form ( wasmtime-örneği)
src = open("/home/gokun/projects/00_TAMGA-MESH/tamga/tamga_runner.py",
           encoding="utf-8").read()
assert 'subprocess.run([WASMTIME, "run", str(pkg / "agent.wasm")]' in src, \
    "wasmtime-liste-formu-değişmiş ( tarama-boş)"
assert "shell=True" not in src, "shell=True-tamga'da-var ( beklenmedik)"
print("  2-TEMİZ: tamga_runner.py:731 wasmtime → LİSTE-form ( pkg-yolu-enjekte-")
print("        edilmez; arg-sınırlandırması-doğal)")

# --- 3) TEMİZ: env={} + RLIMIT ( host-sızıntısı-YOK + kaynak-sınırı)
assert "env={}," in src, "env={}-sertleştirmesi-yok ( AUDIT-3-F16)"
assert "RLIMIT_FSIZE" in src, "RLIMIT-sınırı-yok ( kaynak-koruması)"
print("  3-TEMİZ: env={} ( host-env-sızıntısı-YOK — AUDIT-3-F16) +")
print("        RLIMIT_FSIZE ( cpu_ms/io_limit-sınırı — AUDIT-9-B6)")

# --- N1) eval/exec-input-YOK ( enjekte-yüz-yok)
r2 = subprocess.run(["grep", "-rnE", r"\binput\(|\beval\(|\bexec\(",
                     "swarmax/src/swarmax", "dumen/dumen", "tenderix/src/tenderix"],
                    capture_output=True, text=True,
                    cwd="/home/gokun/projects/00_TAMGA-MESH")
sat = [l for l in r2.stdout.splitlines()
       if ".venv" not in l and "__pycache__" not in l]
# .eval() — PyTorch-mod-modu; "exec(" in response — REDTEAM-DETEKTÖRÜ
# ( dumen/judge.py kötü-amacı-FİLTRELER; enjekte-etmez); input()-YOK
eval_mod = [l for l in sat if ".eval()" in l or "model.eval" in l]
filtre = [l for l in sat if '"exec(" in' in l or '"rm -rf" in' in l
          or 'in model_response' in l or 'exec(\'payload\')' in l]
gercek = [l for l in sat if l not in eval_mod and l not in filtre]
print(f"  N1-eval/exec/input: {len(sat)}-eşleşme")
print(f"        PyTorch-mod.eval(): {len(eval_mod)} | redteam-filtre: {len(filtre)}")
print(f"        GERÇEK-enjekte-yüz: {len(gercek)}")
assert not gercek, f"enjekte-yüz-bulundu: {gercek[:2]}"
print("        → mod.eval() PyTorch; exec-detection — KÖTÜYÜ-FİLTRELER")
print("        ( enjeksiyon-değil-tespit) — TAMAMEN-TEMİZ")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) injection-taraması-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) injection"; cat "$LOG"; }

# ============================================ B) TEMİZ+BAKIM: yollar
python3 - <<'PYEOF' >> "$LOG" 2>&1
import glob, re

# --- 6) BAKIM: 2-kalan-sabit-yol ( /tmp/sahte.db + /dev/shm)
sabit = []
for f in (glob.glob("/home/gokun/projects/00_TAMGA-MESH/tamga/tools/*.py") +
          glob.glob("/home/gokun/projects/00_TAMGA-MESH/tamga/private/*.py")):
    with open(f, encoding="utf-8", errors="ignore") as fh:
        for i, line in enumerate(fh, 1):
            if re.search(r'"/tmp/|"/dev/shm/', line):
                sabit.append(f"{f.split('tamga/')[-1]}:{i}")
print(f"  6-BAKIM: kalan-sabit-yollar: {sabit}")
assert "/tmp/sahte.db" in str(sabit) or "spec_code_scan" in str(sabit), \
    "sabit-yol-bulunamadı ( tarama-boş)"
print("        → düşük-etki ( araçlar; AT-190-2/4-kapandı: fixture+preview)")

# --- AT-190-kapanış-teyidi: tempfile-kullanımı ( fixture/preview)
for f in ("make_pairing_fixture.py", "gen_social_preview.py"):
    src = open(f"/home/gokun/projects/00_TAMGA-MESH/tamga/tools/{f}",
               encoding="utf-8").read()
    assert "tempfile" in src or "tmpdir" in src, \
        f"{f}-tempfile'a-geçmemiş ( AT-190-bozulmuş)"
print("  AT-190-devamı-TEMİZ: make_pairing_fixture + gen_social_preview →")
print("        tempfile-kullanıyor ( /tmp-sabit-yolu-kalktı)")

# --- N3) os.path-karışımı-işlevsel-temiz ( stil-notu)
ospath = []
for f in glob.glob("/home/gokun/projects/00_TAMGA-MESH/tamga/*.py") + \
         glob.glob("/home/gokun/projects/00_TAMGA-MESH/tamga/tools/*.py"):
    with open(f, encoding="utf-8", errors="ignore") as fh:
        if "os.path." in fh.read():
            ospath.append(f.split("tamga/")[-1])
print(f"  N3-os.path/pathlib-karışımı: {len(ospath)}-dosya ( stil-notu;")
print("      işlevsel-temiz — pathlib'ye-geçiş-önerisi-düşük-öncelik)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) yol-bakım + AT-190-devamı-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) yollar"; cat "$LOG"; }

# ============================================ C) TEMİZ: meta-veri+merkez
python3 - <<'PYEOF' >> "$LOG" 2>&1
import subprocess

# --- 4) TEMİZ: manifest-NAME_RE-doğrulama ( ValueError)
src = open("/home/gokun/projects/00_TAMGA-MESH/tamga/tools/registration_v1.py",
           encoding="utf-8").read()
assert "NAME_RE.match" in src, "manifest-doğrulaması-yok"
assert "şemaya-uyumsuz" in src or "uyumsuz" in src, "şema-hatası-yok"
print("  4-TEMİZ: registration_v1.py:82 manifest → NAME_RE.match + ValueError")
print("        → JSON-yük-sonrası-BAĞLAMDAN-doğrulama ( N2)")

# --- 5) TEMİZ: out()-tek-merkez + sıfır-arg-mesaj-RED
src_r = open("/home/gokun/projects/00_TAMGA-MESH/tamga/tamga_runner.py",
             encoding="utf-8").read()
assert "def out(ok, **kw):" in src_r, "out()-tek-merkez-yok"
assert "REQUIRED_ARGS" in src_r and "USAGE_HINT" in src_r, "E-14-guard-yok"
r = subprocess.run(["python3", "tamga_runner.py", "grant"],
                   capture_output=True, text=True,
                   cwd="/home/gokun/projects/00_TAMGA-MESH/tamga")
assert r.returncode != 0 and "Traceback" not in r.stderr + r.stdout
assert "kullanim" in r.stdout, "mesaj-yok"
print("  5-TEMİZ: out()-TEK-merkez ( E-14-guard); sıfır-arg → mesaj-RED")
print("        → hata-kodları-dağınık-değil ( REQUIRED_ARGS+USAGE_HINT)")

# --- 7) TEMİZ: sester --secret-ZORUNLU ( AT-179-canlı)
src_s = open("/home/gokun/projects/00_TAMGA-MESH/sester/sester/migrate_pg.py",
             encoding="utf-8").read()
assert 'default=None' in src_s and "ZORUNLU" in src_s, "secret-zorunlu-değil"
print("  7-TEMİZ: sester migrate_pg --secret-ZORUNLU ( AT-179-canlı;")
print("        migrate-yüzünde-dev-secret-açığı-YOK)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) meta-veri + merkez-hata-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) meta-veri"; cat "$LOG"; }

echo
note "  DÜRÜST-SONUÇ: tarama-TEMİZ-çıktı — üretim-injection-yüzü-YOK"
note "  bakım-öneri: kalan-2-sabit-yol → tempfile; os.path→pathlib ( stil)"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-194: Giriş-temizliği — TEMİZ ( shell=YOK) + 2-zayıf-bakım"
[[ $FAIL -eq 0 ]]
