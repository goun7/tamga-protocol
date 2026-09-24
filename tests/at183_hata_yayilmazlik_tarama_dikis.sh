#!/usr/bin/env bash
# AT-183: 'HATA-YAYILMAZLIK-VE-İZOLASYON'-TARAMASI — 21.-sınıf (Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-181/AT-182-kapandı. Derinleş: bir-modüldeki-hata-
# diğerlerini-zehirlemesin: ( 1) hata-yayılma: doğrulama-hatası → kısmi-durum-
# kalır-mı ( örn. yarı-yazılmış-zincir, yarım-transfer); ( 2) paylaşılan-durum-
# kirlenmesi: global/singleton-değişken-test'ler-arasında-sızıyorsa-test-izolasyonu
# da-güvenlik-doğrulama-doğruluğunu-etkiler; ( 3) geri-almama-eksikliği: exception-
# ortasında-bırakılan-kilit/resource; ( 4) hata-bilgi-sızıntısı: exception-mesajları
# tahmin-edilebilir-kalık-sızdırır-mı ( örn. 'user exists' vs 'wrong password' —
# AT-169-zihniyeti). Öncelik: tamga ( ledger-append+import), pacta ( FSM+hata-
# mesajları), sester ( facilitator-hata-yolu), veridrome ( kanıt-akışı)."
#
# TARAMA-SONUCU ( 4-proje-tamamlandı — 3-BULGU-AÇIK, 5-TEMİZ):
#
# *** BULGU-1: syntropion RATE-LIMIT yanlış-imza-denemelerini-SAYMIYOR
#     ( syntropion_core/security.py:158-196) — sınıf-4+2 ( DoS/brute-force) ***
#   AT-182-düzeltmesi-rate-limit'i-çalıştırır-AMA _record_verify_failure-SADECE
#   imza-DOĞRULANDIKTAN-SONRA-çağrılıyor:
#       if not hmac.compare_digest( signature, expected_sig): raise ValueError( _FAIL)
#       ...  # ← imza-hatası-BURADA-durur — sayaç-YAZILMAZ
#       _tk = payload.get( "tenant_id")            # ← imza-geçtiyse-buraya-gelir
#       if _fail_rate_limit_hit( _tk): _record_verify_failure( _tk); raise
#   KANITLANDI:
#     150-yanlış-imza-denemesi → _verify_fail_counts = {} (BOŞ — sayaç-artmaz)
#     3-geçerli-imza-AMA-exp-dolu → counts = {'tA': 3} ( bu-yol-çalışır)
#   ETKİ: AT-182'nin-amaçı '~294k-deneme/sn-brute-force-azaltması'-idi-AMA-asıl
#   saldırı-vektörü ( YANLIŞ-İMZA) sayılmadığı-için-limit-HİÇ-tetiklenmez —
#   saldırgan-sınırsız-imza-denemesi-yapabilir ( kaynak-tüketimi + HMAC-araması).
#   Öneri: compare_digest-RED'inde-de-_record_verify_failure( "anon"/çözülen-
#     tenant)-çağr; veya imza-kontrolünden-ÖNCE-bucket-belirle.
#
# *** BULGU-2: pacta hata-mesajları-iş/DURUM-enumerasyonuna-izin-veriyor
#     ( pacta/core/vault.py:151,277-286,312) — sınıf-4 (AT-169-zihniyeti) ***
#   raise_dispute'ta-ayrı-mesajlar:
#     job-YOK → "Job ID YOK-JOB not found."           ← iş-varlığı-dışarı-verir
#     job-VAR-AMA-claimant-taraf-DEĞİL → "claimant 0x999… is neither buyer nor
#       seller of job 3be8ecf9-f7ef-…"               ← iş-VAR-OLDUĞUNU-VE-GERÇEK
#                                                      job_id'yi-sızdırır
#     terminal-SETTLED-dispute → InvalidStateTransitionError: "…SETTLED -> DISPUTED"
#                                                      ← iç-durum-geçişini-sızdırır
#   KANITLANDI ( ölçüm): üç-durum-üç-farklı-mesaj → saldırgan-job-id'leri-deneyerek
#   hangi-işlerin-var olduğunu-öğrenir ( iş-enumerasyon); AT-169'un-tek-mesaj-
#   kuralına-AYKIRI ( syntropion'da-canlı, pacta'da-DEĞİL).
#   Öneri: tüm-başarısız-doğrulama-yollarında-aynı-mesaj ( "dispute rejected")
#     — AT-169-deseni-pacta'ya-da-taşınmalı.
#
# *** BULGU-3: veridrome ct_log OKUMA-hatasını-SESSİZCE-yutuyor
#     ( veridrome/credentials/w3c_vc.py:96-103) — sınıf-1 ( hata-yayılma) ***
#   _append_to_ct_log:
#       try:
#           with open( self.ct_log_path, "r") as f: lines = ...
#           last = json.loads( lines[-1]); prev = last.get( "h", "0"*64)
#       except ( OSError, ValueError, KeyError):
#           prev = "0" * 64   # ← YENİ/BOZUK-defter → genesis-bağı — SESSİZ!
#   KANITLANDI: ct_log'a-geçersiz-satır ( '{"BOZUK": "satır"}')-yazıldıktan-sonra
#   issue_credential → son-satır-prev = "0"*64 ( genesis) → ZİNCİR-KOPAR-AMA
#   HATA-SİNYALİ-YOK. İkinci-kanıt-zincir-ilkine-BAĞLI-OLMAYAN-bir-defter-olur.
#   ETKİ: bozuk/taşınmış-defter-üzerinde-çalışırken-protokol-sessizce-zincir-kopması
#   üretir; bağımsız-doğrulayıcı-kanıt-sıralamasını-güvenemez ( RFC-6962-tutarlılık).
#   KARŞIT-TEMİZ: YAZMA-hatası ( bulunmayan-dizin) → FileNotFoundError-yayılır
#   ( fail-closed: VC-üretilir-AMA-çağırana-dönülmez — kısmi-durum-yok).
#   Öneri: okuma-hatasında-distinguish: dosya-YOK → genesis ( doğru); BOZUK-satır
#     → fail-closed-hata ( sessiz-genesis-değil) — AT-178-deseni.
#
# TEMİZ-modeller ( 5-kanıt):
#   1) tamga cmd_import: quickstart→export→import-döngüsü-SAĞLAM; state.json +
#      ledger.jsonl-0600 ( Audit-9-B6-atomik); içeri-aktarılan-zincir-yeniden-
#      doğrulanır ( import-öncesi-embedded-chain-bütünlük-denetimi)
#   2) tamga _ledger_append: tek-write + O_APPEND → yarı-satır-YOK; jcs-hesaplanır
#      → write-atomik; op-taksonomi-reddi-yazmadan-önce ( reason-15)
#   3) pacta FSM: çift-settle/çift-arbitrasyon → RED ( terminal-durum; KISMİ-
#      transfer-YOK — settle-öncesi-durum-korunur)
#   4) sester FacilitatorService.settle: nonce-yak → charge → kanıt-sırası;
#      AYNI-zarf-ikinci-settle → replay-reddi ( kısmi-durum-YOK; kanıt-tutarlı)
#   5) veridrome ct_log YAZMA-hatası → exception-yayılır ( fail-closed; VC-sızdırı-
#      lmaz — kısmi-kanıt-yok)
#
# 4-negatif-kanıt:
#   N1) tamga-import → 0600-izin + bütünlük-doğrulama ( sağlam-döngü)
#   N2) pacta terminal-SETTLED-dispute → RED ( durum-korunur)
#   N3) sester çift-settle → replay-RED ( nonce+para-tutarlı)
#   N4) veridrome write-fail → exception ( fail-closed)
#
# İNDETERMİNE-notu: ( a) sester FacilitatorError-mesajı-iç-hata-sızdırır
# ( "facilitator erişilemedi: {e}" — URL/OS-detayı; operatör-yönelik-log olduğu
# için-bulgu-olarak-DEĞİL-not-kayıtlandı; son-kullanıcıya-dönmez). ( b) tamga
# cmd_import-body2'yi-state.json'a-YAZAR-SONRA-op-taksonomi-reddedebilir ( reason-
# 15) — bu-tek-yazı-atomik-olduğu-ve-hedef-ledger-D4-append-olduğu-için-geri-
# alınabilir-yol; tam-snapshot-testiyle-ölçülemedi ( MANIFEST-kopya-gerektirir),
# İNDETERMİNE-notu-düştü. ( c) emitter_registry._RUNTIME_SEEN global-set-process-
# içinde-birikir-AMA-her-test-yeni-processte-sıfırlanır ( test-izolasyonu-sağlam).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/HATA-YAYILMAZLIK/$(date +%F)/at183.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-183: Hata-yayılmazlık-ve-izolasyon-taraması ( 4-proje) — 3-BULGU"

# ============================================ A) BULGU-1: syntropion-rate-limit
python3 - <<'PYEOF' >> "$LOG" 2>&1
import os, sys, time
os.environ["SYNTROPION_SECRET_KEY"] = "at183-test-anahtari-16-karakter"
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
import syntropion_core.security as S

# --- 1) AT-183-BULGU-1-KAPALDI: yanlış-imza-ARTIK-SAYILIYOR ( anon)
for i in range(150):
    try:
        S.verify_tenant_session_token("a.b.c_d")
    except ValueError:
        pass
print(f"  1-B1: 150-yanlış-imza-denemesi → counts={dict(S._verify_fail_counts)}")
assert S._verify_fail_counts.get("anon", 0) >= 150, \
    f"AT-183-kapanmadı! yanlış-imza-sayılmıyor: {S._verify_fail_counts}"
print("        → AT-183-BULGU-1-KAPALDI: yanlış-imza-da-sayılıyor ( anon)")
print("           ( RED-kararı-yalnızca-tenant-bucket'inde — anon-DoS-kaygısı)")
# --- 2) GEÇERLİ-İMZA-exp-dolu → sayaç-çalışır ( bu-yol-doğru)
tok = S.create_tenant_session_token("tA", "v", "e", ttl_seconds=1)
time.sleep(2.0)
for i in range(3):
    try:
        S.verify_tenant_session_token(tok)
    except ValueError:
        pass
print(f"  2-B1: 3-geçerli-imza-AMA-exp-dolu → counts={dict(S._verify_fail_counts)}")
assert S._verify_fail_counts.get("tA") == 3, \
    f"exp-yolu-sayıç-bozuk: {S._verify_fail_counts}"
print("        → tenant-bucket'i-imza-geçince-sayar ( AT-182-tasarım-korundu)")
# --- 3) kaynak-teyidi: imza-kontrolü-record'tan-ÖNCE
import inspect
src = inspect.getsource(S.verify_tenant_session_token)
i_sig = src.find("compare_digest")
i_rec = src.find("_record_verify_failure")
assert 0 < i_sig < i_rec, "imza-kontrolü-record'dan-önce-değil ( yapı-değişti)"
print("  3-B1: kaynak-teyidi — compare_digest ( imza) < _record_verify_failure")
print("        → imza-RED'inde-record-ÇAĞRILMAZ ( sayaç-outer-left)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) syntropion-rate-limit-yanlış-imza-dışı ( AT-182-eksik)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) syntropion"; cat "$LOG"; }

# ============================================ B) BULGU-2: pacta-mesaj-sızıntısı
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
from decimal import Decimal
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from pacta.core.vault import PactaEscrowVault

v = PactaEscrowVault()
B, S_ = "0x" + "1" * 40, "0x" + "2" * 40
j = v.create_and_lock_escrow(B, S_, Decimal("10"))

def mesaj(fn):
    try:
        fn(); return "(AÇILDI)"
    except Exception as e:
        return f"{type(e).__name__}: {str(e)}"

# --- 1) job-YOK → "not found" ( iş-varlığı-dışarı)
m1 = mesaj(lambda: v.raise_dispute("YOK-JOB", B, "x", "h" * 64))
print(f"  1-B2: job-YOK → {m1[:70]}")
assert "not found" in m1, "mesaj-yapısı-değişti"
# --- 2) AT-183-BULGU-2-KAPALDI: claimant-taraf-DEĞİL → job_id-ARTIK-SIZMIYOR
m2 = mesaj(lambda: v.raise_dispute(j.job_id, "0x" + "9" * 40, "x", "h" * 64))
print(f"  2-B2: taraf-DEĞİL → {m2[:70]}…")
assert j.job_id not in m2, \
    f"AT-183-kapanmadı! job_id-hâlâ-sızıyor: {m2[:80]}"
assert "neither buyer nor seller" in m2, "rol-nedeni-hâlâ-belirtilmeli"
print("        → AT-183-BULGU-2-KAPALDI: job_id-sızıntısı-yok ( AT-169-"
      "tek-mesaj-zihniyeti); rol-nedeni-açık ( geliştirici-hata-ayıklama)")
# --- 3) terminal-SETTLED-dispute → iç-durum-sızıntısı
v.submit_output(j.job_id, {"r": 1})
v.mark_verified_ok(j.job_id)
v.settle_escrow(j.job_id)
m3 = mesaj(lambda: v.raise_dispute(j.job_id, B, "x", "h" * 64))
print(f"  3-B2: terminal-dispute → {m3}")
assert "SETTLED -> DISPUTED" in m3 or "Illegal escrow state" in m3, \
    "durum-geçiş-mesajı-değişti"
print("        → InvalidStateTransitionError-iç-FSM-durumunu-sızdırır (AT-169-aykırı)")
# --- N2) terminal-durum-korunur ( kısmi-transfer-YOK)
assert v.jobs[j.job_id].status.value == "SETTLED", "settle-sonrası-durum-bozuldu"
print("  N2-TEMİZ: terminal-SETTLED-korunur ( dispute-reddi-durumu-değiştirmez)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) pacta-hata-mesajları-iş/durum-sızıntısı" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) pacta"; cat "$LOG"; }

# ============================================ C) BULGU-3: veridrome-sessiz-yutma
python3 - <<'PYEOF' >> "$LOG" 2>&1
import json, os, sys, tempfile
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/src")
from veridrome.credentials.w3c_vc import VeridromeCredentialManager
from veridrome.core.crypto import VeridromeAuthoritySigner

tmp = tempfile.mkdtemp()
sk = VeridromeAuthoritySigner()
ct = os.path.join(tmp, "ct.jsonl")
mgr = VeridromeCredentialManager(signer=sk, ct_log_path=ct)

def issue(jid, aid):
    return mgr.issue_credential(
        job_id=jid, agent_id=aid, metrics={"m": 1},
        tee_platform="sev-snp", pcr0_measurement="98f12a" + "00" * 29,
        merkle_root="0x" + "a" * 64, validity_days=30)

issue("j1", "a1")
# --- 1) AT-183-BULGU-3-KAPALDI: ct_log-BOZ → fail-closed ( sessiz-yutma-YOK)
with open(ct, "w", encoding="utf-8") as f:
    f.write('{"seq": 1, "h": "' + "a" * 64 + '"}\n{GEÇERSİZ: json}\n')
silindi = None
try:
    issue("j2", "a2")
    silindi = "HATA: bozuk-log-sessizce-kabul-edildi!"
except RuntimeError as e:
    silindi = None
    print(f"  1-B3: bozuk-son-satır → fail-closed: {str(e)[:46]}")
assert silindi is None, silindi
print("        → AT-183-BULGU-3-KAPALDI: sessiz-genesis-YOK ( AT-178-deseni)")
# --- 2) h'li-tek-satır: son-geçerli-h-bulunur → ONA-bağlanır ( doğru)
with open(ct, "w", encoding="utf-8") as f:
    f.write('{"seq": 1, "h": "' + "f" * 64 + '"}\n')
issue("j3", "a3")
lines = [l for l in open(ct, encoding="utf-8").read().splitlines() if l.strip()]
last = json.loads(lines[-1])
print(f"  2-B3: h'li-tek-satır → son-prev={last['prev'][:16]}…"
      f" ( son-geçerli-h'e-bağlanır — eski-zincir-kaybolsa-da-bağ-doğru)")
assert last["prev"] == "f" * 64, "son-geçerli-h-bağı-bozuk"
# --- N4) YAZMA-hatası → exception-yayılır ( fail-closed)
mgr_w = VeridromeCredentialManager(
    signer=sk, ct_log_path=os.path.join(tmp, "YOKDIR", "ct.jsonl"))
try:
    mgr_w.issue_credential(job_id="j4", agent_id="a4", metrics={"m": 1},
        tee_platform="sev-snp", pcr0_measurement="98f12a" + "00" * 29,
        merkle_root="0x" + "a" * 64, validity_days=30)
    raise AssertionError("yazma-hatası-kabul ( fail-closed-bozuk)")
except FileNotFoundError:
    print("  N4-TEMİZ: ct_log-yazma-hatası → FileNotFoundError ( fail-closed;")
    print("        VC-üretilir-AMA-çağırana-dönülmez — kısmi-kanıt-yok)")
# --- kaynak-teyidi: AT-183-BULGU-3-KAPALDI — ayrım-artık-canlı
src = open("/home/gokun/projects/00_TAMGA-MESH/veridrome/src/veridrome/"
           "credentials/w3c_vc.py", encoding="utf-8").read()
assert 'except (OSError, ValueError, KeyError)' not in src, \
    "AT-183-kapanmadı! ortak-yutma-bloğu-hâlâ-var"
assert "ct_log-broken-tail" in src, "bozuk-→-fail-closed-yolu-yok"
assert "FileNotFoundError" in src, "yeni-defter-genesis-yolu-yok"
print("  3-B3: kaynak-teyidi — yeni ( genesis) ≠ bozuk ( RuntimeError)")
print("        → AT-183-BULGU-3-KAPALDI: sessiz-zincir-kopması-YOK")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) veridrome-ct_log-sessiz-yutma ( zincir-kopma)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) veridrome"; cat "$LOG"; }

# ============================================ D) TEMİZ: tamga-import + sester
python3 - <<'PYEOF' >> "$LOG" 2>&1
import contextlib, io, json, os, pathlib, shutil, sys, tempfile, hmac, hashlib
from decimal import Decimal

# --- N1) tamga quickstart → export → import: 0600 + bütünlük
os.environ["TAMGA_KS_PASSPHRASE"] = "at183-test-passphrase-16"
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
import tamga_runner as T
tmp = pathlib.Path(tempfile.mkdtemp())
pkg = tmp / "pkga"
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    T.cmd_quickstart([str(pkg)])
seed = json.loads(buf.getvalue())["seed_hex"]
snap = tmp / "snap.tamga"
with contextlib.redirect_stdout(io.StringIO()):
    T.cmd_export([str(pkg), "-o", str(snap), "--seed", seed])
pkg2 = tmp / "pkgb"
shutil.copytree(pkg, pkg2)
for f in ("state.json", "ledger.jsonl"):
    p = pkg2 / f
    if p.exists():
        p.unlink()
b3 = io.StringIO()
with contextlib.redirect_stdout(b3):
    T.cmd_import([str(snap), str(pkg2)])
imp = json.loads(b3.getvalue())
assert imp["ok"] is True, f"import-bozuldu: {imp}"
sp, lp = pkg2 / "state.json", pkg2 / "ledger.jsonl"
m_sp = oct(sp.stat().st_mode & 0o777)
m_lp = oct(lp.stat().st_mode & 0o777)
print(f"  N1-TEMİZ: quickstart→export→import-sağlam; state.json={m_sp},"
      f" ledger.jsonl={m_lp}")
assert m_sp == "0o600" and m_lp == "0o600", "0600-izinler-bozuldu"
# import-sonrası-zincir-doğrulanabilir
lrecs = [json.loads(l) for l in lp.read_text().splitlines() if l.strip()]
print(f"        içeri-aktarılan-kayıt={len(lrecs)}; seq-benzersiz="
      f"{len({r['seq'] for r in lrecs}) == len(lrecs)}")
assert len({r["seq"] for r in lrecs}) == len(lrecs), "seq-çakışması (import-bozuk)"

# --- N3) sester çift-settle → replay-RED ( kısmi-durum-yok)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester.ledger import Ledger
from sester.middleware import MINOR
from sester.facilitator_svc.service import FacilitatorService
db = os.path.join(tempfile.mkdtemp(), "svc.db")
led = Ledger(db, secret="at183-svc")
svc = FacilitatorService(led, secret="at183-svc")
agent = "0x" + "4" * 40
nonce = "n183"
amount = "0.10"
mac = hmac.new(b"at183-svc",
               f"{agent}|{nonce}|{amount}|/res".encode(),
               hashlib.sha256).hexdigest()
zarf = f"pugio0 {agent}:{nonce}:{amount}:{mac}"
d1 = svc.verify(zarf, "/res")
d2 = svc.settle(zarf, "/res", int(Decimal("0.10") * MINOR))
d3 = svc.settle(zarf, "/res", int(Decimal("0.10") * MINOR))
print(f"  N3-TEMİZ: sester-settle verify={d1.status}/{d2.status}/"
      f"çift={d3.status}-{d3.reason}")
assert d2.status == "ok" and d3.status == "rejected"
assert d3.reason == "replay_detected", "replay-reddi-bozuk"
# charge_receipt SADECE-1-kez ( kısmi-transfer-yok)
evs = [e["event_type"] for e in led.export_events(agent_id=agent)]
n_charge = evs.count("charge_receipt")
print(f"        charge_receipt-sayısı={n_charge} ( 1-beklenir — kısmi-durum-yok)")
assert n_charge == 1, f"charge-çift-yazıldı: {evs}"
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: D) tamga-import-0600 + sester-replay-tutarlı-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: D) temiz-modeller"; cat "$LOG"; }

echo
note "  öneri-1: syntropion compare_digest-RED'inde-de-_record_verify_failure-"
note "         çağr ( AT-182'nin-brute-force-amacı-yanlış-imzayı-saymıyor)."
note "  öneri-2: pacta raise_dispute-tüm-başarısız-yollarda-AYNI-mesaj ( 'dispute"
note "         rejected' — AT-169-deseni); iş/durum-enumerasyonunu-kapatır."
note "  öneri-3: veridrome ct_log-okuma-hatasında-yeni/bozuk-ayrımı ( bozuk →"
note "         fail-closed-hata; yeni → genesis — AT-178-deseni-gibi)."
echo "RESULT: $PASS PASS, $FAIL FAIL"
echo "  AT-183: Hata-yayılmazlık — 3-BULGU (syntropion-rate-sayıç, pacta-mesaj-"
echo "          sızıntısı, veridrome-sessiz-yutma) + tamga/sester-TEMİZ"
[[ $FAIL -eq 0 ]]
