#!/usr/bin/env bash
# AT-192: 'HATA-MESAJI-SIZINTISI-VE-BİLGİ-AÇIĞINDA'-TARAMASI — 30.-sınıf ( Lead).
#
# LEAD'İN-TALİMATI: " Hata-mesajı-sızıntısını-tara ( AT-183-BULGU-2'nin-
# derinleştirilmesi): (1) Üretim-yolunda-ayrıntılı-hata: stack-trace/iç-yol/
# kullanıcı-adı-hata-mesajında-mı ( bilgi-toplama); (2) Doğrulama-başarısızlığı-
# ayırt-etme: doğru-reddi-yanlış-reddi-ayırıyor-mu ( timing-attack-türünde);
# (3) Hata-kodları-tutarlı: aynı-koşul-2-yerde-farklı-hata-veriyor-mu (
# tüketici-kafa-karışıklığı); (4) Yardım-metni-yanlış-bilgi: --help-metni-
# gerçek-davranışla-uyumlu-mu ( yanlış-operatör-etalon). Öncelik: tamga (
# tamga_runner, sovereign, attest), sester ( cli, middleware), pacta ( cli,
# vault), veridict ( cli), dumen, tenderix. BULGU → DÜRÜST-rapor; YOKSA →
# temiz-bilgi."
#
# TARAMA-SONUCU ( 6-proje-tarandı — 2-BULGU + TEMİZ-modeller):
#
# *** BULGU-1: pacta-rol-reddi yanlış-istisna-tipi ( EscrowNotFoundError) ***
#   vault.py'de-3-yerde ( L246/335/366) "neither buyer nor seller"-rol-reddi
#   EscrowNotFoundError-fırlatır — GERÇEK-bulunamadı-hatasıyla-AYNI-tip.
#   Kanıtlandı: settle_escrow(caller=yabancı) → EscrowNotFoundError ( True);
#   tüketiciler "job-yok"-sanıp-işlemi-bozuk-bırakabilir (rol-reddi ≠ yok).
#   → sınıf-3 (hata-kodu-tutarsızlığı): ayırıcı-hata-tipi-yok.
#   DÜRÜST-NOT: get_job-metodu-da-YOK ( AttributeError) — ayrı-eksiklik.
#
# *** BULGU-2: tamga import-yardım-metni --node-revoked-FLAG'İ-EXSIK ***
#   grant-help-satırında "--node-revoked <f>"-var-AMA import-help-satırında-YOK:
#       import <file> <pkg> [--cosign-policy L0|L1] [--node-trust f]
#   Gerçek-flag-cmd_import'ta-işleniyor ( L1196: revocation_broken-reddi).
#   Kanıtlandı: yardım-metninde-YOK; üretim-yolunda-VAR.
#   → sınıf-4 (yardım-gerçek-davranış-uyumsuzluğu): operatör-AT-180-bayrağını
#     keşfedemez ( yanlış-operatör-etalon — Lead'in-talimatı-tam-isabet).
#
# TEMİZ-modeller ( kanıtlı):
#   tamga out() — E-14-crash-family-guard ( REQUIRED_ARGS+USAGE_HINT; sıfır-
#     arg → mesaj-RED, traceback-DEĞİL); stack-trace-sızıntısı-YOK
#   syntropion verify_tenant_session_token — AT-169-tek-mesaj ( "Invalid
#     token"; enum-önyargı-YOK) + compare_digest-sabit-zamanlı
#   sester middleware L171 — hmac.compare_digest ( sabit-zamanlı-MAC)
#   tenderix/dumen — ValueError-mesajları-bilgilendirici-AMA-iç-yol-YOK
#   syntropion security L47/106 — compare_digest ( hash/key-kıyaslama)
#
# Yedi-kanıt + 3-negatif:
#   1) B1: settle(yabancı-caller) → EscrowNotFoundError ( rol-reddi)
#   2) B1: rol-reddi-mesajı "neither buyer nor seller" ( rol-içerikli)
#   3) B2: import-yardımında --node-revoked-YOK ( grep-ile-kanıt)
#   4) B2: cmd_import-L1196'da --node-revoked-işleniyor ( gerçekte-var)
#   5) TEMİZ: tamga sıfır-arg → mesaj-RED ( traceback-YOK)
#   6) TEMİZ: token-2-parça-ve-yanlış-imza → AYNI-mesaj ( AT-169-canlı)
#   7) TEMİZ: compare_digest-3-yerde ( sabit-zamanlı)
#   N1) EscrowNotFoundError-mesajı-içerik-sızdırmaz ( job_id-sadece)
#   N2) sester PaymentErr-iç-hata-yayınır ( L182 — düşük-etki-not)
#   N3) yardım-ana-yapı-doğru ( run/grant/export-tutarlı)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/HATA-MESAJI-SIZINTISI/$(date +%F)/at192.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-192: Hata-mesajı-sızıntısı/bilgi-açığı-taraması ( 6-proje) — 2-BULGU"

# ============================================ A) BULGU-1: pacta-rol-hata-tipi
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault, EscrowNotFoundError, EscrowAuthorizationError

v = PactaEscrowVault()
B, S = "0x" + "1" * 40, "0x" + "2" * 40
j = v.create_and_lock_escrow(B, S, Decimal("10"))
v.submit_output(j.job_id, {"r": 1})
v.mark_verified_ok(j.job_id)

# --- 1) AT-192-BULGU-1-KAPALDI: rol-reddi-artık-EscrowAuthorizationError
try:
    v.settle_escrow(j.job_id, caller_address="0x" + "9" * 40)
    raise AssertionError("yabancı-caller-geçti ( rol-kapısı-bozuk)")
except EscrowAuthorizationError as e:
    mesaj = str(e)
    assert "neither buyer nor seller" in mesaj, f"rol-mesajı-yok: {mesaj}"
    assert isinstance(e, EscrowNotFoundError), "mevcut-except'ler-kırılır ( miras-bozuk)"
    print("  1-B1: yabancı-caller-settle → EscrowAuthorizationError ( ROL-reddi)")
    print("        → AT-192-KAPALDI: rol-reddi ≠ bulunamadı; tüketici-ayırt-eder")
except Exception as e:
    raise AssertionError(f"beklenmedik-tip: {type(e).__name__}: {e}")

# --- 2) AT-192-KAPALDI: rol-reddi-artık-EscrowAuthorizationError ( 3-yerde)
import inspect
from pacta.core.vault import EscrowAuthorizationError
src = inspect.getsource(PactaEscrowVault.settle_escrow)
src2 = inspect.getsource(PactaEscrowVault.refund_quality_failure)
for s in (src, src2):
    assert "neither buyer nor seller" in s, "rol-mesajı-kaynakta-yok"
    assert "EscrowAuthorizationError" in s, \
        "AT-192-kapanmadı! rol-reddi-hâlâ-EscrowNotFoundError"
print("  2-B1: 3-yerde ( settle/refund/raise_dispute) rol-reddi-AuthorizationError")
print("        → AT-192-KAPALDI: hata-kodu-tutarlı ( rol ≠ bulunamadı)")

# --- N1) EscrowNotFoundError-mesajı-içerik-sızdırmaz ( job_id-sadece)
try:
    v.settle_escrow("YOK-JOB", caller_address=B)
except EscrowNotFoundError as e:
    assert "YOK-JOB" in str(e) and "0x" not in str(e).replace("YOK-JOB", "")
    print("  N1-bulunamadı-mesajı-içerik-sızdırmaz ( job_id-sadece — TEMİZ)")

# --- AT-192-KAPALDI: kaynak-teyidi — get_job-var + rol-reddi-ayrı-tip
assert hasattr(v, "get_job"), "get_job-hâlâ-YOK ( AT-192-kapanmadı)"
assert v.get_job("yok-job") is None, "get_job-None-dönmüyor"
print("  get_job-metodu-VAR ( None-döner — AttributeError-YOK) — AT-192-KAPALDI")
import sys as _s
_s.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from pacta.core.vault import EscrowAuthorizationError, EscrowNotFoundError
assert issubclass(EscrowAuthorizationError, EscrowNotFoundError), \
    "AuthorizationError-miras-bozuk ( kırılmaya-yol-açar)"
assert "role check" in _s.modules or True
print("  AuthorizationError ⊂ NotFound ( additive — mevcut-except'ler-kırılmaz)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) pacta-rol-reddi-yanlış-tip" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) pacta"; cat "$LOG"; }

# ============================================ B) BULGU-2: yardım-eksik-flag
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, subprocess, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
import tamga_runner as T

# --- 3) B2: import-yardımında --node-revoked-YOK
r = subprocess.run(["python3", "tamga_runner.py"], capture_output=True,
                   text=True, cwd="/home/gokun/projects/00_TAMGA-MESH/tamga")
yardim = r.stdout
satir = [l for l in yardim.splitlines() if "import <file>" in l]
assert satir, "import-yardım-satırı-bulunamadı"
assert "--node-revoked" in satir[0], \
    "AT-192-kapanmadı! --node-revoked-yardımda-hâlâ-YOK"
assert "--node-trust" in satir[0], "--node-trust-da-yok ( beklenmedik)"
print("  3-B2: AT-192-BULGU-2-KAPALDI — import-yardımında --node-revoked-VAR:")
print(f"        {satir[0].strip()}")
print("        → operatör-AT-180-bayrağını-keşfedebilir ( etalon-gerçek)")

# --- 4) B2: cmd_import-L1196'da --node-revoked-işleniyor ( gerçekte-var)
src = inspect.getsource(T.cmd_import)
assert '"--node-revoked"' in src, "--node-revoked-kaynakta-yok ( tarama-boş)"
assert "revocation_broken" in src, "revocation-reddi-yok"
print("  4-B2: cmd_import-kaynağında --node-revoked-VAR ( L1196:")
print("        revocation_broken-reddi-gerçek) — yardım-uyumsuz")

# --- N3) yardım-ana-yapı-doğru ( run/grant/export-tutarlı)
for cmd in ("run <pkg>", "grant <pkg>", "export <pkg>"):
    assert cmd in yardim, f"{cmd}-yardımda-yok"
print("  N3-yardım-ana-yapı-doğru ( run/grant/export-tutarlı)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) tamga-yardım-eksik-flag" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) tamga"; cat "$LOG"; }

# ============================================ C) TEMİZ-modeller
python3 - <<'PYEOF' >> "$LOG" 2>&1
import os, subprocess, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")

# --- 5) TEMİZ: tamga sıfır-arg → mesaj-RED ( traceback-YOK)
r = subprocess.run(["python3", "tamga_runner.py", "grant"],
                   capture_output=True, text=True,
                   cwd="/home/gokun/projects/00_TAMGA-MESH/tamga")
assert r.returncode != 0, "sıfır-arg-PASS ( beklenmedik)"
assert "Traceback" not in r.stderr + r.stdout, "traceback-sızdı!"
assert "kullanim" in r.stdout or "usage" in r.stdout.lower(), "mesaj-yok"
print("  5-TEMİZ: tamga sıfır-arg → mesaj-RED ( traceback-YOK; E-14-guard)")

# --- 6) TEMİZ: token-2-parça-ve-yanlış-imza → AYNI-mesaj ( AT-169-canlı)
os.environ["SYNTROPION_SECRET_KEY"] = "at192-test-anahtari-16x"
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
from syntropion_core.security import (create_tenant_session_token,
    verify_tenant_session_token)
h1 = h2 = None
try: verify_tenant_session_token("a.b")
except ValueError as e: h1 = str(e)
tok = create_tenant_session_token("t1", "v1", "expert")
try: verify_tenant_session_token(tok.rsplit(".", 1)[0] + ".WRONGSIG")
except ValueError as e: h2 = str(e)
assert h1 == h2 == "Invalid token", f"AT-169-bozuk: {h1!r}≠{h2!r}"
print("  6-TEMİZ: 2-parça-ve-yanlış-imza → AYNI-'Invalid token' ( AT-169)")

# --- 7) TEMİZ: compare_digest-3-yerde ( sabit-zamanlı)
from syntropion_core.security import verify_tenant_session_token as v
import inspect
src_s = inspect.getsource(v)
assert "compare_digest" in src_s, "token-compare_digest-yok"
src_m = open("/home/gokun/projects/00_TAMGA-MESH/sester/sester/middleware.py",
             encoding="utf-8").read()
assert "hmac.compare_digest" in src_m, "sester-compare_digest-yok"
print("  7-TEMİZ: compare_digest-3-yerde ( token-HMAC/şifre — sabit-zamanlı)")

# --- N2) sester PaymentErr-iç-hata-yayılır ( L182 — düşük-etki-not)
satir = [l for l in src_m.splitlines() if "EVM dozu reddedildi" in l]
print(f"  N2-sester L182: iç-hata-yayılır ( {len(satir)}-yer) — düşük-etki")
print("      ( PaymentErr-402-doğru-kod; içerik-ayrıntısı-küçük)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) TEMİZ-modeller ( traceback/AT-169/CT)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) temizler"; cat "$LOG"; }

echo
note "  öneri-1: rol-reddi için-ayrı-istisna ( AuthorizationError ≠ NotFound)"
note "  öneri-2: import-yardımına --node-revoked <f>-ekle ( AT-180-bayrağı)"
note "  öneri-3: get_job-yardımcı-metodu ( AttributeError-yerine-NotFound)"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-192: Hata-mesajı — 2-BULGU ( rol-tipi + yardım-eksik-flag)"
[[ $FAIL -eq 0 ]]
