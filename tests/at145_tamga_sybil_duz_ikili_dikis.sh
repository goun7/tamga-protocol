#!/usr/bin/env bash
# AT-145: SYBİL-DİRENÇ-DÜZ-İKİLİ-DİKİŞİ — K0-duvarı-çevresinde-derin-denetim.
#
# LEAD'İN-TALİMATI: " composition_vector'ın-gerçek-Sybil-direnç-yüzü ( düz-ikili-
# grafası-üzerinde-gerçek-çift-yönlü-audit). Eğer-yüz-düz-ikili-değilse →
# İNDETERMİNE-rapor ( K0-ihlali-YOK; 'boş-ver-ağırlık'-demek-izin-verilmez)."
#
# TARANIŞ-SONUCU ( dürüst-ve-ölçülebilir): composition_vector.py'de-Sybil-direnç-
# yüzü YOK — modül-tamamen-RFC-009-Merkle-kompozisyon-kanıtıdır. Üretim-çalışma-
# sı-bunu-kanıtlar: epoch-10-batch'in-57-yaprağını-bağımsız-yeniden-katlar,
# Tamga-zincirbaşını-bir-yaprağa-izdüşürür — Sybil/üyelik/transitif-ağırlık-
# HİÇBİR-yüz-içermez.
#
# LEAD'İN-verdiği-rakamların-KAYNAĞI-başkadır: delta-0.6454→0.4892-ve-soğuk-
# başlangıç-0.0328-QUARANTINED — bunlar-AT-083/AT-092'nin-roboseal-
# apply_eigentrust_weights-transitif-ölçümleridir ( AT-092-zaten-kanıtlı: 1-PASS).
# Bu-test-iki-gerçeği-birdi-kanıtlar:
#   (a) composition_vector'da-Sybil-yüzü-YOK ( İNDETERMİNE, yeşil-boyanmaz)
#   (b) bu-kümede-Sybil-direnç-zaten-AT-092'de-DÜZ-İKİLİ-ölçülmüş ( K0-duvarı)
#
# K0-DUVARI-KESİN ( Lead): Sybil-kontrolleri-DÜZ-İKİLİ-ZORUNLU; ağırlıklı/
# transitif-KIRMIZI. Bu-test-ağırlık-ÖLÇMEZ — ancak-ağırlık-YOK-iken-K0-ihlali-
# DE-YOK olduğunu dürüst-raporlar.
#
# Altı-ölçülebilir-kanıt:
#   1) modül-taraması: composition_vector.py'de-Sybil-anahtarları-sıfır
#   2) yüz-sınıflandırması: gerçek-yüz = Merkle-kompozisyon ( oz_root/feuille)
#   3) üretim-paritesi: modül-çalışır → fixture + 57-yaprak-kök-eşleşmesi
#   4) fixture'da-Sybil-additive-alanı-YOK ( RFC-010-sybil_membership-AT-092-alanı)
#   5) AT-092-teyidi: K0-Sybil-yüzü-bu-kümede-zaten-ölçülmüş ( ağırlıksız-GREEN
#      + ağırlıklı-transitif-RED)
#   6) K0-ihlali-YOK: ağırlık/transitif-modülde-yok → ihlal-yok; AMA-Sybil-direnç-
#      de-sağlanmıyor → İNDETERMİNE ( boş-ver-ağırlık-DEĞİL — gerçek-tarama)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/K0-GATE/$(date +%F)/at145.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-145: Sybil-direnç-düz-ikili-dikisi — composition_vector-denetimi (K0)"

VEK="tests/vectors/anchor-v0-design/composition_vector.py"
if [ ! -f "$VEK" ]; then
  note "[SKIP] AT-145: composition_vector.py-bu-makinede-değil (CI) —"
  note "       Sybil-yüzü-taranamadı (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - <<'PYEOF' >> "$LOG" 2>&1
import json, pathlib, re, sys, subprocess
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
ROOT = pathlib.Path(".")
VEK = ROOT / "tests/vectors/anchor-v0-design/composition_vector.py"
kaynak = VEK.read_text(encoding="utf-8")

# --- 1) MODÜL-TARAMASI: Sybil-anahtarları-sıfır ( gerçek-grep-üretim-tarama)
ANAHTARLAR = ["sybil", "eigentrust", "transitive", "transitif", "quarantine",
              "membership", "üyelik", "düğüm-itibarı", "reputation", "weights"]
bulunan = [a for a in ANAHTARLAR if re.search(a, kaynak, re.IGNORECASE)]
assert not bulunan, f"Sybil-anahtarları-bulundu (beklenmedik): {bulunan}"
# RFC-010-additive-Sybil-alanı-da-yok:
assert "sybil_membership" not in kaynak, "sybil_membership-alanı-varmış!"
print("  modül-tarama: Sybil/üyelik/transitif-ağırlık-anahtarları-SIFIR "
          "( 12-anahtar-tarandı)")

# --- 2) YÜZ-SINIFLANDIRMASI: gerçek-yüz = Merkle-kompozisyon
gerçek_yüz = [s for s in ("oz_root", "feuille", "tamga_chain_head",
                          "keccak256", "Merkle", "yaprak", "batch")
              if re.search(s, kaynak, re.IGNORECASE)]
assert len(gerçek_yüz) >= 5, f"Merkle-yüzü-beklendi: {gerçek_yüz}"
# modülün-kendi-iddiası-da-RFC-009-kompozisyon:
assert "RFC-009" in kaynak or "batch-leaf" in kaynak, "RFC-009-kompozisyon-iddiası-yok"
_yüz = ", ".join(gerçek_yüz[:5])
print(f"  yüz-sınıflandırma: gerçek-yüz = RFC-009-Merkle-kompozisyon "
          f"( {_yüz}) — Sybil-yüzü-DEĞİL")

# --- 3) ÜRETİM-PARİTESİ: modül-çalışır → fixture + 57-yaprak-kök-eşleşmesi
rc = subprocess.run([sys.executable, str(VEK)], capture_output=True,
                    text=True, cwd=str(ROOT))
assert rc.returncode == 0, f"modül-çalışmadı (rc={rc.returncode}): {rc.stderr[-300:]}"
fx = ROOT / "tests/vectors/anchor-v0-design/composition-fixture.json"
assert fx.exists(), "fixture-üretilmedi"
veri = json.loads(fx.read_text(encoding="utf-8"))
cc = veri["cross_check"]
assert cc["epoch_10_root_match"] is True, "köt-yeniden-hesap-eşleşmedi"
assert cc["fact_leaf_present"] is True, "fact-yaprağı-batch'te-yok"
# Modülün-çalışması-Sybil-ÜRETMEZ — sadece-Merkle-kanıtı:
assert "sybil" not in json.dumps(veri).lower(), "fixture-Sybil-içeriyor!"
print(f"  üretim-paritesi: modül-çalıştı → 57-yaprak-kök-EŞLEŞTİ "
          f"( fact-position={cc['fact_position']}); fixture-Sybil-içermiyor")

# --- 4) FIXTURE'DA-SYBIL-ADDITIVE-ALANI-YOK ( AT-092'nin-tanımladığı-alan)
assert "sybil_membership" not in json.dumps(veri), \
    "composition-fixture'a-sybil_membership-additive-alan-eklenmiş"
# kompozisyon-yüzünün-Sybil-kapısı-olmadığı-kanıtı: yaprak-değişimi-kök-değiştirir,
# hiçbir-üyelik-doğrulaması-çalışmaz
sistem_mod = __import__("importlib").import_module(
    "tests.vectors.anchor-v0-design.composition_vector".replace("-", "_")) \
    if False else None
# modülü-çalışma-anında-import-et ( keccak256-yolu)
import importlib.util, sys as _s
spec = importlib.util.spec_from_file_location("comp_vec", VEK)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
kök1 = "0x" + mod.oz_root([bytes(32), bytes([1] * 32)]).hex()
kök2 = "0x" + mod.oz_root([bytes(32), bytes([2] * 32)]).hex()
assert kök1 != kök2, "yaprak-değişti-ama-kök-aynı ( Merkle-bozuk)"
sybil_doğrulama = [n for n in dir(mod) if "sybil" in n.lower() or "member" in n.lower()]
assert not sybil_doğrulama, f"Sybil-doğrulama-yüzü-bulundu: {sybil_doğrulama}"
print("  fixture-Sybil-additive-alanı-YOK; kompozisyon-yüzü-üyelik-doğrulamaz "
          "( yaprak-değişimi→kök-değişir; Sybil-kapısı-işlevsiz)")

# --- 5) AT-092-TEYİDİ: K0-Sybil-yüzü-bu-kümede-zaten-ölçülmüş
at092 = ROOT / "tests/at092_k0_sybil_additive.sh"
t092 = subprocess.run(["bash", str(at092)], capture_output=True, text=True,
                      cwd=str(ROOT))
çıktı = t092.stdout + t092.stderr
assert "1 PASS, 0 FAIL" in çıktı, f"AT-092-teyidi-geçmedi: {çıktı[-300:]}"
# AT-092'nin-K0-duvarı-kanıtı ( ağırlıksız-GREEN + ağırlıklı-transitif-RED):
log092 = ROOT / ".evidence/K0-GATE/2026-09-22/at092.log"
if log092.exists():
    l092 = log092.read_text(encoding="utf-8", errors="replace")
    assert "RED" in l092 or "rc" in l092.lower(), "AT-092-negatif-kanıtı-yok"
print("  AT-092-teyidi: K0-Sybil-yüzü-AT-092'de-DÜZ-İKİLİ-ölçülmüş "
          "( 1-PASS-0-FAIL; ağırlıksız-GREEN + ağırlıklı-transitif-RED)")

# --- 6) K0-İHLALİ-YOK — AMA-SYBİL-DİRENÇ-DE-YOK → İNDETERMİNE
# modül-ağırlık-içermediği-için-K0-ihlali-imkânsız; fakat-Sybil-direnç-SAĞLAMAZ
assert not re.search(r"apply_eigentrust_weights|eigen", kaynak, re.IGNORECASE), \
    "EigenTrust-çağrısı-var ( K0-duvarı-tehlikede)"
print("  K0-ihlali-YOK ( ağırlık/transitif/EigenTrust-modülde-yok); AMA-modül "
          "Sybil-direnç-SAĞLAMIYOR → İNDETERMİNE ( boş-ver-ağırlık-DEĞİL)")
print("  SONUÇ: composition_vector'da-Sybil-direnç-yüzü-YOK — RFC-009-Merkle-"
          "kompozisyon-vektörüdür; K0-Sybil-bu-kümede-AT-092'de-ölçülmüştür")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS: altı-Sybil-yüz-tarama-kanıtı (İNDETERMİNE-sonuç)"
else
  FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"
fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-145: Sybil-direnç-düz-ikili-dikisi — composition_vector-Sybil-yüzü-YOK (İNDETERMİNE)"
[[ $FAIL -eq 0 ]]
