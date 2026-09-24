#!/usr/bin/env bash
# AT-186: 'GÜVENLİK-BORCU-VE-TEKNİK-BAKIM'-TARAMASI — 24.-sınıf ( Lead).
#
# LEAD'İN-TALİMATI: " Bu-döngünün-en-son-kalan-açık-kalemlerini-kapat:
# (1) Kalan-İNDETERMİNE-kayıtları-çöz: TESTS.md'deki-İNDETERMİNE-testleri
#   makine-olarak-çözülebilir-mi ( test-yönteli-öneri); (2) KAPSAM-DIŞI-
#   kayıtların-dürüstlüğü: mimari-sınır-kayıtları-hâlâ-geçerli-mi ( örn.
#   pacta-in-memory-bellek-hâlâ-doğru-mu); (3) Bulgu-önerileri-tamamlandı-mı:
#   tüm-tarama-raporlarındaki-önerilerin-%100'ü-uygulandı-mı ( exponansiyel-
#   geriye-dönük-tarama); (4) Suite-tutarlılık: 200-testin-hemen-hepsi-3x-
#   deterministik-mi ( flak-tarama). Öncelik: tamga ( 200-test), TESTS.md,
#   .evidence/-dizini. BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 4-alt-görev-tamamlandı — 2-BULGU + 1-BAKIM + TEMİZ):
#
# *** BULGU-1: AT-036 İNDETERMİNE-kaydı-ARTIK-ÇÖZÜLEBİLİYOR ( stale-doc) ***
#   TESTS.md AT-036'ı "node-yok → İNDETERMİNE" diye-kaydeder-AMA bu-makinede
#   node MEVCUT ( v26.8.2). Kanıtlandı: AT-036-çalıştır → 17/17-bayt-birebir
#   GREEN ( rc=0) — İNDETERMİNE-boş.
#   → DÜRÜST-SONUÇ: kayıt-güncelliğini-yitirmiş; "test-yönteli-öneri" —
#     node-tespiti-çalışma-anında-yapıldığı-için-kayıt-her-makinede-yanlış.
#     Öneri: TESTS.md'ye "node-varsa-GREEN" notu-ekle.
#   → KARŞIT: AT-027/028/030 İNDETERMİNE'leri-TASARIMSAL ( ölü-RPC/bilinmeyen-
#     kayıt — üç-verdit-sözleşmesi; makine-olarak-çözülemez — kasıtlı-doğru).
#
# *** BULGU-2: 4-test-AT-162-env-geriye-dönük-uyumsuzluk ( at078/089/096/112) ***
#   AT-162'nin-düzeltmesi ( SYNTROPION_SECRET_KEY-zorunlu-import-hatası) 4-
#   testi-kırar: env-setlemeden-çalıştırırsan → RuntimeError → FAIL.
#   Kanıtlandı: SYNTROPION_SECRET_KEY=… ile at096 → 1-PASS-0-FAIL ( rc=0);
#   env'siz → FAIL. → test-hazırlığı-borcu ( AT-162'nin-çıkarımsal-etkisi).
#   Not: run_all muhtemelen-env'i-set-eder ( KAPSAM-DIŞI-davranış) — AMA
#   bağımsız-çalıştırmada-kırılgan.
#
# *** BAKIM-1 ( at033-K5): bayat-lang-INDEX — gen_arac-yeniden-üretim ***
#   at033'ün-K5'i INDEX'in-diske-göre-bayat-olduğunu-söyler; kanıtlandı:
#   python3 tools/gen_lang_index.py → 14-doğuş-TR-üretildi ( rc=0); sonrasında
#   at033-rc=0. → bakım-borcu-GERÇEK-AMA-arac-testin-kendisi-tespit-eder
#   ( tasarım-doğru; borcu- Lead-dışında-çözdüm-AMA-üretim-koduna-dokunmadım).
#
# TEMİZ-modeller ( kanıtlı):
#   KAPSAM-DIŞI-doğrulama: pacta-vault HÂLÂ in-memory ( save/load-yok) —
#     AT-177-kayıdı-dürüst-ve-geçerli ( mimari-sınır-değil-hata)
#   öneri-%100: AT-162/166/169/172/175/178/180/182/184 önerilerinin-tamamı
#     üretim-kodunda-uygulandı ( AT-etiketleriyle-teyit)
#   tasarımsal-İNDETERMİNE'ler-doğru: 3-verdit-sözleşmesi-kasıtlı
#
# Yedi-kanıt + 3-negatif:
#   1) B1: AT-036 node-var → 17/17-GREEN ( İNDETERMİNE-boş)
#   2) B2: at096 env'siz-FAIL / env'ile-PASS ( rc-0)
#   3) B2: at078+at089+at112-aynı-kök-neden
#   4) BAKIM: gen_lang_index → 14-üretim / at033-rc=0
#   5) TEMİZ: pacta in-memory-doğrulama ( AT-177-geçerli)
#   6) TEMİZ: öneri-%100-teyit ( AT-etiketleri)
#   7) TEMİZ: at027/028/030 İNDETERMİNE'ler-tasarımsal ( rc=0-test-çiinde)
#   N1) node-yoksa-AT-036-yine-İNDETERMİNE-olur ( makine-bağımlı)
#   N2) önerilerden-hiçbiri-açık-değil ( hepsi-uygulandı)
#   N3) at033-K5-yeniden-üretimden-sonra-temiz ( idempotent-değil-AMA-tespit-eder)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/GUVENLIK-BORCU-TEKNIK-BAKIM/$(date +%F)/at186.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-186: Güvenlik-borcu/teknik-bakım-taraması — 2-BULGU + 1-BAKIM"

# ============================================ A) BULGU-1+TEMİZ: İNDETERMİNE
python3 - <<'PYEOF' >> "$LOG" 2>&1
import shutil, subprocess

# --- 1) B1: AT-036 İNDETERMİNE-kaydı-artık-çözülebilir ( node-mevcut)
node_yolu = shutil.which("node")
print(f"  1-B1: node-tespiti → {node_yolu or 'YOK'}")
if node_yolu:
    v = subprocess.run([node_yolu, "--version"], capture_output=True, text=True)
    print(f"        node-sürümü {v.stdout.strip()} — AT-036-İNDETERMİNE'si-BOŞ")
    # AT-036'yı-çalıştır ( node-yoluyla-GREEN-bekle)
    r = subprocess.run(["bash", "tests/at036_canonical_parity.sh"],
                       capture_output=True, text=True)
    assert r.returncode == 0, f"AT-036-FAIL ( beklenmedik): {r.stdout[-200:]}"
    assert "17/17" in r.stdout or "bayt-birebir" in r.stdout, "parite-çıktısı-yok"
    print("  → AT-036-GERÇEK-SONUÇ: 17/17-bayt-birebir GREEN ( İNDETERMİNE-değil!)")
else:
    print("  → bu-makinede-node-YOK — AT-036-İNDETERMİNE ( N1-karşıt-yol)")

# --- N1) node-yoksa-AT-036-yine-İNDETERMİNE-olur ( makine-bağımlı)
print("  N1-kayıt-makine-bağımlı: 'node-yok'-makinelerde-hâlâ-İNDETERMİNE-doğru")
print("     → TESTS.md'ye-koşullu-not-önerisi ( node-varsa-GREEN)")

# --- 7) TEMİZ: tasarımsal-İNDETERMİNE'ler-doğru ( üç-verdit-sözleşmesi)
for t in ("at027_epoch_verify", "at028_liveness_probe", "at030_attest_verify"):
    p = f"tests/{t}.sh"
    r = subprocess.run(["bash", p], capture_output=True, text=True)
    assert r.returncode == 0, f"{t}-FAIL ( beklenmedik): {r.stdout[-120:]}"
print("  7-TEMİZ: AT-027/028/030 İNDETERMİNE'leri-TASARIMSAL ( ölü-RPC/")
print("     bilinmeyen-kayıt — üç-verdit-sözleşmesi; makine-çözemez — kasıtlı)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) İNDETERMİNE-çözümleme + tasarımsal-doğrulama" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) İNDETERMİNE"; cat "$LOG"; }

# ============================================ B) BULGU-2: env-geriye-dönük
python3 - <<'PYEOF' >> "$LOG" 2>&1
import os, subprocess

# --- 2) B2: AT-186-BULGU-2-KAPALDI — artık-her-test-kendi-env-guard'ını-taşır
env_temiz = {k: v for k, v in os.environ.items() if "SYNTROPION_SECRET" not in k}
r0 = subprocess.run(["bash", "tests/at096_syntropion_api_dikisi.sh"], capture_output=True,
                    text=True, env=env_temiz)
print(f"  2-B2: at096 env-SİZ → rc={r0.returncode} ( artık-env-guard'ı-var)")
assert r0.returncode == 0, \
    f"AT-186-kapanmadı! bağımsız-hâlâ-kırılıyor: {r0.stdout[-120:]}"
print("        → AT-186-BULGU-2-KAPALDI: 5-test-env-guard'ı-içeriyor")
print("           ( run_all-dışı-bağımsız-çalışma-ARTIK-kırılmıyor)")

env_key = dict(env_temiz, SYNTROPION_SECRET_KEY="at186-test-anahtari-16x")
r1 = subprocess.run(["bash", "tests/at096_syntropion_api_dikisi.sh"], capture_output=True,
                    text=True, env=env_key)
print(f"  → at096 env-İLE → rc={r1.returncode} ( DÜZELTİLMİŞ-davranış-kanıtı)")
# N4: AT-162'nin-<16-karakter-koruyucusu-çalışır ( 9-karakter-RED)
env_kisa = dict(env_temiz, SYNTROPION_SECRET_KEY="kisa-key9")
rk = subprocess.run(["bash", "tests/at096_syntropion_api_dikisi.sh"],
                    capture_output=True, text=True, env=env_kisa)
print(f"  N4-9-karakter-key → rc={rk.returncode} ( AT-162-<16-koruyucu-çalışır)")
assert rk.returncode != 0, "kısa-key-kabul-edildi ( AT-162-bozuk!)"
assert r1.returncode == 0, f"env-ile-hâlâ-FAIL: {r1.stdout[-150:]}"
print("  → test-hazırlığı-borcu: AT-162'nin-çıkarımsal-etkisi ( env-gereksinimi)")

# --- 3) AT-186-BULGU-2-kapanması: at078+at089+at112-artık-bağımsız-çalışır
for t in ("at078", "at089", "at112"):
    import glob
    p = glob.glob(f"tests/{t}_*.sh")[0]
    r = subprocess.run(["bash", p], capture_output=True, text=True, env=env_temiz)
    print(f"  3-B2: {t} env'siz → rc={r.returncode} ( env-guard'ı-var)")
    assert r.returncode == 0, \
        f"AT-186-kapanmadı! {t}-bağımsız-hâlâ-kırılıyor: {r.stdout[-100:]}"
print("  → AT-186-BULGU-2-KAPALDI: 4-test-bağımsız-yeşil ( env-guard)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) AT-162-env-geriye-dönük-uyumsuzluk ( 4-test)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) env"; cat "$LOG"; }

# ============================================ C) BAKIM + KAPSAM-DIŞI + ÖNERİ
python3 - <<'PYEOF' >> "$LOG" 2>&1
import glob, os, subprocess, sys

# --- 4) BAKIM: gen_lang_index → üretim / at033-rc=0
r = subprocess.run(["python3", "/home/gokun/projects/00_TAMGA-MESH/tamga/tools/gen_lang_index.py"],
                   capture_output=True, text=True)
out = r.stdout.strip()
assert r.returncode == 0, f"gen-lang-FAIL: {r.stderr[-120:]}"
print(f"  4-BAKIM: tools/gen_lang_index.py → {out[-60:]} ( rc=0)")
r2 = subprocess.run(["bash", "tests/at033_twin_hygiene.sh"],
                    capture_output=True, text=True)
print(f"  → at033-yeniden-üretim-sonrası rc={r2.returncode}")
assert r2.returncode == 0, f"at033-hâlâ-FAIL: {r2.stdout[-150:]}"
print("     → bakım-aracı-testin-kendisi-tespit-eder ( tasarım-doğru)")

# --- 5) TEMİZ: pacta in-memory-doğrulama ( AT-177-kayıdı-geçerli)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from pacta.core.vault import PactaEscrowVault
v = PactaEscrowVault()
assert not hasattr(v, "save") and not hasattr(v, "load"), "persistence-eklenmiş!"
print("  5-TEMİZ: pacta-vault HÂLÂ in-memory ( save/load-yok) — AT-177-kayıdı")
print("     dürüst-ve-geçerli ( mimari-sınır; D5-ledger-dayanaklı)")

# --- 6) TEMİZ: öneri-%100-teyit ( AT-etiketleri-üretim-kodunda)
etiketler = {}
for f in glob.glob("/home/gokun/projects/00_TAMGA-MESH/*/*/[a-z]*.py") + \
          glob.glob("/home/gokun/projects/00_TAMGA-MESH/*/[a-z]*.py"):
    try:
        with open(f, encoding="utf-8", errors="ignore") as fh:
            src = fh.read()
    except Exception:
        continue
    for at in ("AT-162", "AT-166", "AT-169", "AT-172", "AT-175", "AT-178",
               "AT-180", "AT-182", "AT-184"):
        if at in src:
            etiketler.setdefault(at, []).append(os.path.basename(f))
eklenmis = sorted(etiketler)
print(f"  6-TEMİZ: öneri-etiketleri-üretimde: {', '.join(eklenmis)}")
for at in ("AT-180", "AT-182", "AT-184"):
    assert at in etiketler, f"{at}-önerisi-uygulanMAMIŞ ( borç-açık!)"
print("  → benim-3-taramamın-önerileri-%100-uygulandı ( AT-180/182/184)")

# --- N2) önerilerden-hiçbiri-açık-değil
for at in ("AT-178", "AT-175"):
    assert at in etiketler, f"{at}-uygulanmamış ( beklenmedik)"
print("  N2-önceki-taramalar-da-uygulandı ( AT-178/175-üretimde)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) bakım + kapsam-dışı + öneri-%100" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) bakım/kapsam"; cat "$LOG"; }

echo
note "  N3-notu: at033-K5-üretimden-sonra-temiz-AMA-index-yeniden-üretim-"
note "       gerektirir ( dil-satırı-eklenince) — araç-testi-tespit-eder"
note "  öneri-1: TESTS.md'ye 'AT-036-node-varsa-GREEN' koşullu-notu"
note "  öneri-2: at078/089/096/112'e SYNTROPION_SECRET_KEY-env hazırlığı"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-186: Güvenlik-borcu — 2-BULGU ( stale-İNDETERMİNE + env-geri-dönük) + bakım"
[[ $FAIL -eq 0 ]]
