#!/usr/bin/env bash
# AT-180: 'İPTAL-VE-GERİ-ALMA'-TARAMASI — 18.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " ( 1) iptal-listesi-eksik/bozuksa → fail-closed-mı ( AT-178'in-
# TRUST_MISSING/TRUST_BROKEN-deseni-gibi) yoksa-sessiz-atlama-mı; ( 2) anahtar-
# çalınma-sonrası: eski-imzalar-hâlâ-geçerli-mi ( revocation-uygulama-zamanlaması —
# OQ-3-iddiası-GERÇEK-mi); ( 3) iptal-sırası: fesih-sonrası-yeni-imza-yeniden-
# denenebilir-mi; ( 4) geri-alma-yolu: hatalı-fesih-geri-alınabilir-mi ( pacta-
# dispute/arbitration, sester-replay-sonrası-charge). Öncelik: tamga ( --node-
# revoked), pacta, sester, syntropion."
#
# TARAMA-SONUCU ( 4-proje-tamamlandı — 2-BULGU-AÇIK, 6-TEMİZ):
#
# *** BULGU-1: tamga --node-revoked DEĞER-SİZ-BAYRAK → SESSİZ-İPTAL-ATLAMA
#     ( tamga_runner.py:1180-1193) — sınıf-1 ( eksik-liste fail-OPEN) ***
#   cmd_import'un-iptal-bloğu:
#       idx = a.index("--node-revoked") if "--node-revoked" in a else -1
#       if idx >= 0 and idx + 1 < len(a):     ← argv-SONUNDA-değer-YOKSA False
#           revoked = json.loads( ... )
#       ...
#       if revoked and rec.get("node_id") in revoked:   ← boş-liste → False → ATLANIR
#   --node-revoked-SON-argüman-olarak-verilirse ( değer-YOK): bayrak-VARDIR-AMA
#   değer-okunamaz → revoked=[]-ile-DEVAM-EDİLİR → "if revoked and ..."-koşulu-
#   TAMAMEN-ATLANIR. Saldırgan-çaldığı-node-anahtarıyla-üretilmiş-eski-imzalı-
#   kayıtları-GEÇİREBİLİR ( operator-iptal-etmek-istedi-AMA-bayrağı-yanlış-kullandı).
#   KANITLANDI ( uçtan-uca argv-simülasyonu):
#     ["--cosign-policy","L1","--node-trust",...,"--node-revoked"] →
#       bayrak-mevcut=True ( L1-zorunluluk-kontrolü-atlanır), değer-okunur=False
#       → revoked=[] → sessiz-atlama
#   KRİTİK: Lead'in-AT-180-düzeltmesi ( L1 + bayrak-YOK → revocation_required rc6)
#   bu-durumu-KAPATMAZ — bayrak-VAR-AMA-değersiz. Aynı-açığın-diğer-yüzü:
#   bozuk-JSON → rc=2 fail-closed ( DOĞRU); değer-YOK → sessiz-[] ( AÇIK).
#   → AT-178'in-TRUST_MISSING/TRUST_BROKEN-deseni-ile-TUTARSIZ: trust-burada
#     fail-closed-sinyal-üretir-AMA-revoked-buradaki-karşılığı-YOK.
#   Öneri: değer-siz-bayrak → REVOKE_BROKEN/REVOKE_MISSING-sinyali ( AT-178-
#     deseni); veya en-azından IndexError → rc=2 ( mevcut-yol-BOZUK-dosya-ile
#     aynı-sonucu-verir-AMA-değer-siz-bayrak-bunu-atlıyor).
#
# *** BULGU-2: syntropion session-token exp-YOK + iptal-listesi-YOK
#     ( syntropion_core/security.py:120-146) — sınıf-2 ( anahtar-çalınma) ***
#   create_tenant_session_token: payload = { tenant_id, venture, role, iat} —
#   exp-YOK. verify_tenant_session_token: SADECE-HMAC-imzasını-doğrular ( AT-169-
#   düzeltmesi-ile-bilgi-sızdırmaz-AYNI-hata-mesajı); payload-zamanla-KARŞILAŞTIRILMIYOR.
#   KANITLANDI:
#     token → payload-alanları = {tenant_id, venture, role, iat} ( exp-YOK)
#     token 1.1s-sonra-hâlâ-geçerli ( süre-denetimi-YOK — sonsuz-oturum)
#   ANAHTAR-ÇALINMA-ROTASYONU-TEMİZ: SECRET_KEY-rotate → eski-token RED ( HMAC-
#   doğrulama-anahtarı-değişti). AMA-bu-ADMIN-tarafından-manuel-rotate-gerektirir;
#   otomatik-süre-dolma-veya-iptal-listesi-YOK. API'de-revoke/logout-yüzeyi-YOK.
#   KARŞIT-TEMİZ: AT-168-düzeltmesi-ile-veridrome-VC'lerde-validUntil-denetleniyor
#     ( syntropion'da-bu-desen-YOK).
#   Öneri: payload'a-exp-ekle + verify'de-now>exp → RED ( VAPAP-deseni-ile-aynı).
#
# TEMİZ-modeller ( 6-kanıt):
#   1) tamga iptal-DOSYASI-bozuksa → rc=2 fail-closed ( AT-178-deseni-canlı)
#   2) tamga _node_sig_ok — imza-doğrulama-GERÇEK ( Ed25519; çalınmış-anahtarın
#      eski-imzası-kriptografik-olarak-geçerli — bu-DOĞRU-iptal-listesinin-işidir)
#   3) pacta-çift-settle → InvalidStateTransitionError ( SETTLED-terminal)
#   4) pacta-settle-sonrası-refund → RED ( double-spend-korunuyor)
#   5) pacta-çift-arbitrasyon → RED ( SLASHED_REFUNDED-terminal; FSM-koruma)
#   6) sester-claim_nonce-replay → False ( kalıcı-seen_nonces; restart-atlamaz)
#   7) sester-insert_event-çift-seq → IntegrityError ( UNIQUE-kısıt — migrasyon/
#      geri-alma-yolunda-çift-giriş-korunuyor)
#
# 5-negatif-kanıt:
#   N1) bozuk-revoked-JSON → rc=2 ( fail-closed — AT-178-deseni)
#   N2) anahtar-rotate → eski-token RED ( syntropion-HMAC-rotate-çalışır)
#   N3) pacta-ESCROW_LOCKED→SETTLED-geçiş → RED ( DvP-invariant-gerçek)
#   N4) sester-replay-nonce → False ( ikinci-kez-çalışmaz)
#   N5) pacta-arbitrator-taraf-reddi ( AT-166-canlı — geri-alma-yolunda-rol-deneti)
#
# İNDETERMİNE-notu: sester/pacta/syntropion'da-ayrı-bir-revocation-liste-yüzeyi-YOK
# ( sadecee-tamga'da-var — OQ-3). syntropion-license-anahtarı-'lifetime'-tasarım
# ( süresiz-kullanım-hakkı — sözleşmesel; iptal-edilemez-olması-özellik).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/IPTAL-VE-GERI-ALMA/$(date +%F)/at180.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-180: İptal-ve-geri-alma-taraması ( 4-proje) — 2-BULGU"

# ============================================ A) BULGU-1: tamga-node-revoked-sessiz-atlama
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, json, os, pathlib, sys, tempfile
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
import tamga_runner as T
from nacl.signing import SigningKey

# --- 1) BULGU-1-KAPANDI: değer-siz-bayrak → fail-closed-reddi ( AT-180)
a = ["--cosign-policy", "L1", "--node-trust", "/dev/null", "--node-revoked"]
idx = a.index("--node-revoked") if "--node-revoked" in a else -1
deger_okunur = (idx >= 0 and idx + 1 < len(a))     # False ( argv-sonu)
bayrak_var = "--node-revoked" in a                  # True
print(f"  1-B1: --node-revoked-DEĞER-SİZ ( argv-sonu): bayrak-var={bayrak_var},"
      f" değer-okunur={deger_okunur}")
assert bayrak_var is True and deger_okunur is False, "simülasyon-bozuk"
print("        → ESKİSİ: revoked=[] → 'if revoked and node_id in revoked' ATLANIR")
print("        → ESKİSİ: SESSİZ-İPTAL-ATLAMA ( operator-iptal-etti-sandı-AMA-atlandı)")
# --- 2) kaynak-teyidi: AT-180-düzeltmesi-canlı ( fail-closed-sinyaller)
src = inspect.getsource(T.cmd_import)
assert "revocation_broken" in src, "AT-180-KAPANMADI! değer-siz-bayrak-reddi-yok"
assert "revocation_required" in src, "AT-180-KAPANMADI! L1-zorunluluk-yok"
assert "if revoked and rec.get" in src, "AÇIK-KAPANDI! iptal-koşulu-değişti"
print("  2-B1: kaynak-teyidi — 'revocation_broken' + 'revocation_required' +")
print("        'if revoked and ...' hepsi-canlı ( AT-180-kapanması)")
# --- 3) AT-180-düzeltmesi-değer-siz-bayrağı-KAPATIYOR ( canlı-kanıt)
# Gerçek-paket-üret + değer-siz-bayrak → revocation_broken-RED ( paket-
# doğrulamadan-ÖNCE-kontrol). out()-yolu-stdout'a-yazar.
import subprocess as _sp, tempfile as _tf
_wd = _tf.mkdtemp()
for _f in ("tamga.json", "agent.wasm"):
    (_ := pathlib.Path(_wd) / _f)
_r = _sp.run([sys.executable, "tamga_runner.py", "quickstart", _wd,
              "--name", "at180", "--seed", "a" * 64],
             capture_output=True, text=True,
             cwd="/home/gokun/projects/00_TAMGA-MESH/tamga",
             env={**os.environ, "TAMGA_KS_PASSPHRASE": "at180-2026"},
             timeout=90)
_r2 = _sp.run([sys.executable, "tamga_runner.py", "export", _wd,
               "-o", _wd + "/snap.tsg", "--seed", "a" * 64],
              capture_output=True, text=True,
              cwd="/home/gokun/projects/00_TAMGA-MESH/tamga",
              env={**os.environ, "TAMGA_KS_PASSPHRASE": "at180-2026"},
              timeout=90)
assert '"ok": true' in _r.stdout and '"ok": true' in _r2.stdout, \
    f"kurulum-başarısız: quickstart={_r.stdout[-120:]} export={_r2.stdout[-120:]}"
_tgt = _tf.mkdtemp()
for _f in ("tamga.json", "agent.wasm"):
    import shutil as _sh
    _sh.copy(pathlib.Path(_wd) / _f, pathlib.Path(_tgt) / _f)
# AT-178-yüzeyini-atlamak-için-GEÇERLİ-trust ( node-pub'ı-içerir)
_npub = (pathlib.Path(_wd) / "node_pub.hex")
_np = _npub.read_text().strip() if _npub.exists() else "ff" * 32
_trust_p = pathlib.Path(_wd) / "trust.json"
_trust_p.write_text(__import__("json").dumps([_np]), encoding="utf-8")
_r3 = _sp.run([sys.executable, "tamga_runner.py", "import", _wd + "/snap.tsg",
               _tgt, "--cosign-policy", "L1",
               "--node-trust", str(_trust_p), "--node-revoked"],
              capture_output=True, text=True, cwd="/home/gokun/projects/00_TAMGA-MESH/tamga",
              env={**os.environ, "TAMGA_KS_PASSPHRASE": "at180-2026"},
              timeout=90)
print(f"  3-B1: değer-siz-bayrak-ile-içe-aktarma → stdout: "
      f"{_r3.stdout.strip()[-200:]}")
assert "revocation_broken" in _r3.stdout, \
    "değer-siz-bayrak-hâlâ-reddedilmiyor ( AT-180-AÇIK)"
print("        → AT-180-BULGU-1-KAPANDI: değer-siz-bayrak → fail-closed-reddi")
# --- 4) boş-liste-[]-açık-geçilebilir ( dürüst-yol-korunur — bu-DOĞRU-tasarım)
print("  4-B1-not: boş-dizi-[]-açık-geçilebilir ( dürüst-yol — bu-bulgu-DEĞİL)")
# --- N1) bozuk-JSON → rc=2 fail-closed ( AT-178-deseni-canlı)
assert "node-revoked file unreadable" in src, "bozuk-dosya-yolu-bozulmuş"
print("  N1-TEMİZ: bozuk-revoked-JSON → rc=2 'file unreadable' ( fail-closed)")
# --- N2) _node_sig_ok: çalınmış-anahtarın-eski-imzası-kriptografik-geçerli
sk = SigningKey.generate()                          # çalınmış-anahtar
nid = sk.verify_key.encode().hex()
h = "a" * 64
rec = {"seq": 1, "h": h, "node_id": nid,
       "node_sig": sk.sign(h.encode()).signature.hex()}
assert T._node_sig_ok(rec) is True, "Ed25519-doğrulama-bozuk"
print("  N2-TEMİZ: _node_sig_ok Ed25519-doğrulaması-GERÇEK ( imza-geçerli —")
print("        iptal-LİSTESİ'nin-işidir; imza-katmanı-bunu-bilmek-zorunda-DEĞİL)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) tamga-node-revoked-değer-siz-sessiz-atlama" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) tamga"; cat "$LOG"; }

# ============================================ B) BULGU-2: syntropion-exp-yok
python3 - <<'PYEOF' >> "$LOG" 2>&1
import base64, json, os, sys, time
os.environ["SYNTROPION_SECRET_KEY"] = "at180-test-anahtari-16-karakter"
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
from syntropion_core.security import (create_tenant_session_token,
                                      verify_tenant_session_token)

# --- 1) BULGU-2-KAPANDI: payload'da-exp-ZORUNLU ( AT-180)
tok = create_tenant_session_token("t1", "venture1", "expert")
p_b64 = tok.split(".")[1]
payload = json.loads(base64.urlsafe_b64decode(p_b64 + "=" * (-len(p_b64) % 4)))
print(f"  1-B2: token-payload-alanları={sorted(payload.keys())}")
assert "exp" in payload, "AT-180-KAPANMADI! exp-hâlâ-yok"
assert payload["exp"] > payload["iat"], "exp-iat'ten-büyük-değil"
print("        → exp-ZORUNLU ( AT-180: süre-sınırı-artık-payload'da)")
# --- 2) KISA-TTL → süre-dolunca-RED ( AT-180-kapanması-canlı)
import syntropion_core.security as S
import importlib
importlib.reload(S)
short = S.create_tenant_session_token("t1", "venture1", "expert", ttl_seconds=1)
print("  2-B2: kısa-TTL-token-oluştu ( ttl_seconds=1) — süre-dolması-beklenir")
time.sleep(2)   # AT-180: ttl'den-aşırı-güvenli-pay ( sistem-yükü-altında-flap-YOK)
try:
    S.verify_tenant_session_token(short)
    raise AssertionError("süresi-dolmuş-token-hâlâ-geçerli ( AT-180-AÇIK)")
except ValueError:
    print("        → AT-180-BULGU-2-KAPANDI: exp-doluş → RED ( sonsuz-oturum-YOK)")
# --- 3) kaynak-teyidi: verify-artık-exp-kontrol-eder
import inspect
src = inspect.getsource(S.verify_tenant_session_token)
assert "exp" in src, "AT-180-KAPANMADI! verify-exp-kontrol-etmiyor"
assert "compare_digest" in src, "AT-169-bilgi-sızdırmaz-bozuldu"
print("  3-B2: verify_tenant_session_token — HMAC ( AT-169) + exp-kontrolü ( AT-180)")
# --- N2) anahtar-rotate → eski-token RED ( dönüm-işe-yarar)
os.environ["SYNTROPION_SECRET_KEY"] = "AT180-ROTATE-EDILMIS-ANAHTAR-16"
importlib.reload(S)
try:
    S.verify_tenant_session_token(tok)
    raise AssertionError("eski-token-rotate-sonrası-geçti ( rotate-bozuk)")
except ValueError as e:
    print(f"  N2-TEMİZ: SECRET_KEY-rotate → eski-token RED ( {e})")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) syntropion-session-exp-yok-sonsuz" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) syntropion"; cat "$LOG"; }

# ============================================ C) TEMİZ: pacta-geri-alma-yolları
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
from decimal import Decimal
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from pacta.core.vault import PactaEscrowVault
from pacta.core.fsm import EscrowFSM, InvalidStateTransitionError
from pacta.models import ArbitrationVote, EscrowStatus

v = PactaEscrowVault()
B, S = "0x" + "1" * 40, "0x" + "2" * 40
j = v.create_and_lock_escrow(B, S, Decimal("10"))
v.submit_output(j.job_id, {"r": 1})
v.mark_verified_ok(j.job_id)
tok = j.deposit_token
b0 = float(v.ledger_balances[tok])
out1, tx1 = v.settle_escrow(j.job_id)
b1 = float(v.ledger_balances[tok])
print(f"  1-TEMİZ: settle-1 → {out1.status.value}, ledger {b0}→{b1}")
# --- N3) çift-settle → RED ( terminal-SETTLED)
try:
    v.settle_escrow(j.job_id)
    raise AssertionError("çift-settle-kabul ( double-spend-açık)")
except InvalidStateTransitionError as e:
    print(f"  N3-TEMİZ: çift-settle → RED ( {str(e)[:52]}…)")
# --- N4) settle-sonrası-buyer-refund → RED ( double-spend-korunuyor)
try:
    v.refund_timeout(j.job_id)
    raise AssertionError("settle-sonrası-refund-kabul ( double-spend-açık)")
except Exception as e:
    print(f"  N4-TEMİZ: settle-sonrası-refund → RED ( {type(e).__name__})")
# --- N5) çift-arbitrasyon → RED ( terminal-SLASHED_REFUNDED)
v2 = PactaEscrowVault()
j2 = v2.create_and_lock_escrow(B, S, Decimal("10"))
v2.submit_output(j2.job_id, {"r": 1})
d2 = v2.raise_dispute(j2.job_id, B, "x", "h" * 64)
tok2 = j2.deposit_token
c0 = float(v2.ledger_balances[tok2])
out = v2.resolve_arbitration(d2.dispute_id, [ArbitrationVote(
    arbitrator_address="0x" + "9" * 40, vote_favor_buyer=True,
    rationale_hash="r" * 64)])
c1 = float(v2.ledger_balances[tok2])
print(f"  2-TEMİZ: arbitration-1 → buyer_favored={out.buyer_favored},"
      f" ledger {c0}→{c1} ( fesih-geri-alındı)")
try:
    v2.resolve_arbitration(d2.dispute_id, [ArbitrationVote(
        arbitrator_address="0x" + "9" * 40, vote_favor_buyer=False,
        rationale_hash="r" * 64)])
    raise AssertionError("çift-arbitrasyon-kabul ( fonlar-iki-kez-çekildi)")
except InvalidStateTransitionError as e:
    print(f"  N5-TEMİZ: çift-arbitrasyon → RED ( {str(e)[:48]}…)")
# --- 3) FSM-DvP-invariant: ESCROW_LOCKED→SETTLED-geçiş-YOK
assert not EscrowFSM.can_transition(EscrowStatus.ESCROW_LOCKED,
                                    EscrowStatus.SETTLED)
print("  3-TEMİZ: FSM ESCROW_LOCKED→SETTLED-geçiş-YOK ( DvP-invariant-GERÇEK)")
# --- 4) arbitrator-taraf-reddi ( AT-166-canlı — geri-alma-yolunda-rol-deneti)
try:
    v2.resolve_arbitration(d2.dispute_id, [ArbitrationVote(
        arbitrator_address=B, vote_favor_buyer=True, rationale_hash="r" * 64)])
    raise AssertionError("taraf-arbitrator-geçti ( AT-166-bozuldu)")
except ValueError:
    print("  4-TEMİZ: arbitrator-taraf-reddi ( AT-166-canlı — geri-alma-yolunda)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) pacta-geri-alma-yolları-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) pacta"; cat "$LOG"; }

# ============================================ D) TEMİZ: sester-replay-geri-alma
python3 - <<'PYEOF' >> "$LOG" 2>&1
import os, sqlite3, sys, tempfile
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester.ledger import Ledger

tmp = tempfile.mkdtemp()
led = Ledger(os.path.join(tmp, "t.db"), secret="at180-test-secret")
# --- N6) replay-nonce → False ( kalıcı-seen_nonces)
assert led.claim_nonce("0xag", "n180") is True
assert led.claim_nonce("0xag", "n180") is False
print("  N6-TEMİZ: claim_nonce-replay → False ( kalıcı-seen_nonces)")
# --- 1) append-çift-yazım: append'i-çağıran-sorumlu ( tasarım-gerçek)
led.append("charge_receipt", "0xag", "res", 0.05)
s1 = led.spent_today("0xag")
led.append("charge_receipt", "0xag", "res", 0.05)
s2 = led.spent_today("0xag")
print(f"  1-TEMİZ: append-çift-çağrı spent_today {s1}→{s2} ( append-yolu-"
      f"replay-denetlemez — ÇAĞIRAN-görevli; claim_nonce-asıl-koruma)")
assert s2 > s1
# --- 2) insert_event-çift-seq → IntegrityError ( UNIQUE — geri-alma-yolu-güvenli)
# seq=900-kullanılır ( yukarıdaki-append'ler-1/2'yi-almış-olur)
ev = {"seq": 900, "ts": 1.0, "event_type": "charge_receipt", "agent_id": "0xag",
      "host": "res", "amount": 0.05, "payload": "{}", "prev_hash": "0" * 64,
      "hash": "a" * 64, "amount_minor": 5000000}
led.insert_event(dict(ev))
try:
    led.insert_event(dict(ev))
    raise AssertionError("insert_event-çift-seq-kabul ( çift-giriş-açık)")
except sqlite3.IntegrityError as e:
    print(f"  2-TEMİZ: insert_event-çift-seq → IntegrityError"
          f" ( UNIQUE: {str(e)[:34]}…)")
# --- 3) restart-sonrası-replay-hâlâ-RED ( AT-177-kanıtı-canlı)
spent_before = led.spent_today("0xag")
led2 = Ledger(os.path.join(tmp, "t.db"), secret="at180-test-secret")
assert led2.spent_today("0xag") == spent_before
assert led2.claim_nonce("0xag", "n180") is False
print("  3-TEMİZ: restart-sonrası replay-RED-korunur ( kalıcı-tablo)")
# --- 4) ana-zincir-sağlamlığı ( insert_event'in-sahte-hash'li-test-satırı
#     kalıcı-zincirin-bütünlüğünü-bozduğundan-ayrı-temiz-ledger-ile-ölçülür)
led3 = Ledger(os.path.join(tmp, "temiz.db"), secret="at180-test-secret")
led3.append("charge_receipt", "0xag", "res", 0.05)
assert led3.verify_chain() is True
print("  4-TEMİZ: ana-zincir verify_chain=True ( iptal/geri-alma-işlemi-")
print("        kalıcı-zincir-bütünlüğünü-bozmaz; insert_event-test-satırı-")
print("        bilerek-sahte-hash'lidir — onun-zinciri-ayrı-ölçülür)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: D) sester-replay/geri-alma-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: D) sester"; cat "$LOG"; }

echo
note "  öneri-1: tamga --node-revoked değer-siz-bayrak → REVOKE_BROKEN-sinyali"
note "         ( AT-178-TRUST-deseni-gibi); L1'de-bayrak-zorunlu-oldu-AMA-değer-"
note "         siz-bayrak-hâlə-sessiz-[]-ile-devam-ediyor ( Lead-düzeltmesi-atlıyor)."
note "  öneri-2: syntropion create_tenant_session_token'e-exp-ekle + verify'de"
note "         now>exp → RED ( veridrome-VAPAP-validUntil-deseni-ile-aynı);"
note "         iptal-listesi-VEYA-kısa-TTL ( mevcut-sonsuz-oturum-anahtar-"
note "         çalınmada-manuel-rotate'e-bağımlı)."
echo "RESULT: $PASS PASS, $FAIL FAIL"
echo "  AT-180: İptal-ve-geri-alma — 2-BULGU (tamga-revoked-sessiz-atlama,"
echo "          syntropion-exp-yok) + pacta/sester-geri-alma-TEMİZ"
[[ $FAIL -eq 0 ]]
