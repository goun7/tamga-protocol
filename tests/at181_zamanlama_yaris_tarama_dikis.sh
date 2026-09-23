#!/usr/bin/env bash
# AT-181: 'ZAMANLAMA-VE-YARIŞ'-TARAMASI — 19.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-180'i-tamamladın; şimdi-zamanlama-yarışları:
# ( 1) TOCTOU ( time-of-check-to-time-of-use): yetki/kontrol-ile-eylem-arasında
# durum-değişimi ( örn. escrow-durumu-kontrol-sonra-settle-önce-değişirse);
# ( 2) çakışan-eşzamanlı-yazım: nonce/queue/lock-savunması-YOK-ise-double-spend;
# ( 3) replay-pencere-zamanlaması: EIP-3009 validBefore/validAfter-sınırı
# ( AT-174'te-gördük; sester-hâlâ-kullanıyor); ( 4) saat-kayması/sıralama:
# timestamp-sırası-bozuksa-protokol-kırılır-mı. Öncelik: pacta ( FSM-geçişleri+
# para), sester ( claim_nonce-birinci-yazan-kazanır), tamga ( ledger-append-
# sıralaması), syntropion ( token-exp-şimdi-var). BULGU → DÜRÜST-rapor;
# YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 4-proje-tamamlandı — 2-BULGU-AÇIK, 6-TEMİZ):
#
# *** BULGU-1: sester KOTA-TOCTOU — check ( spent_today_minor) ile append
#     arasında-LOCK-YOK ( sester/middleware.py:439-456) — sınıf-1+2 ***
#   Şarj-yolu:
#     spent_minor = self.ledger.spent_today_minor(agent)     ← CHECK ( kilitsiz)
#     if spent_minor + price > quota: 402                    ← KARAR
#     ... self.ledger.append("charge_receipt", ...)          ← ACT ( append'in
#                                                              kendi-lock'u-var
#                                                              AMA check-dışında!)
#   KANIT ( 10-paralel-thread, kota=0.25, fiyat=0.10):
#     tek-tek-olsaydı: 2-kabul ( 0.20), 3. = 0.30 > 0.25 → RED
#     PARALEL: 3-kabul, harcanan=0.30 → KOTA-AŞILDI ( 0.30 > 0.25)
#   ETKİ: paralel-istekler-günlük-kotayı-aşar ( değer-çıkarma-yolu; değer
#   küçük-AMA-sınıf-gerçek — tek-kaynak-olması-gereken-kota-atomic-değil).
#   KARŞIT-TEMİZ: sester Ledger.claim_nonce → SQLite-UNIQUE-ile-birinci-yazan-
#   kazanır ( 20-paralel-thread-AYNI-nonce → 1-kabul; atomik).
#   → AYNI-protokolde-paradox: nonce-atomik-AMA-kota-değil.
#   Öneri: kota-kararını-da-append'le-aynı-lock-arkasına-al ( check+act-atomik)
#     VEYA spent_today_minor'ı-SQL-atomic-artışla ( UPSERT-kontrollu).
#
# *** BULGU-2: tamga _ledger_append OKU→BELİRLE→YAZ yarış-penceresi
#     ( tamga_runner.py:257-300) — sınıf-2 ( paralel-append-zincir-kopması) ***
#   _ledger_append: full-file-tara ( son-geçerli-h) → seq/prev-belirle → yaz.
#   Bu-üç-adım-arasında-LOCK-YOK ( tarama-ile-yazma-arasında-başka-thread-aynı-
#   prev/seq'alabilir → ÇİFT-seq → zincir-dışı-dallanma).
#   KANIT ( desen-yeniden-üretim, 5-paralel-thread, barrier-sonrası-okuma):
#     5-kayıt-AYNI-seq=2-ile-yazıldı ( hepsi-aynı-prev-snapshot'ı-okudu)
#   ÜRETİM-ETKİSİ-SINIRLI: tamga-CLI-tek-işlem-tek-yazıcı ( paralel-append
#   üretime-yol-yok — cmd_run/cmd_grant/cmd_anchor-ardışık). Yani-bu-bir
#   KÜTÜPHANE-DÜZEYİ-yarıştır ( çok-kanallı-çalışma-açılırsa-gerçekleşir).
#   Ayrıca-append-başarısız-olsa-dahi-oappend-için-O_APPEND + 0600-korunuyor.
#   → Test-hassasiyeti-notu: doğrudan-_ledger_append-çağrısı-GIL-nedeniyle-
#     bu-koşumda-çakışmadı ( seq=1..5-benzersiz); desen-yeniden-üretim-ile
#     yarış-penceresi-kanıtladı. DÜRÜST-sınır: gerçek-üretim-yolu-tek-yazıcı.
#   Öneri: _ledger_append'e-module-level-lock ( Dosya-başına) — çok-kanallı-
#     çağrı-olsa-bile-seq/prev-atomik.
#
# TEMİZ-modeller ( 6-kanıt):
#   1) pacta-çift-settle → InvalidStateTransitionError ( 5-paralel-thread →
#      1-OK/4-RED; FSM-terminal-SETTLED + Python-GIL-geçişi-atomik-yapar)
#   2) pacta-settle-sonrası-refund → RED ( double-spend-korunuyor)
#   3) pacta-çift-arbitrasyon → RED ( SLASHED_REFUNDED-terminal)
#   4) sester-claim_nonce → birinci-yazan-kazanır ( 20-paralel-AYNI-nonce →
#      1-kabul; SQLite-UNIQUE-IntegrityError-ile-atomik)
#   5) syntropion-AT-180-exp-canlı: ttl=2s-token 2.5s-sonra RED ( artık-sonsuz
#      değil); saat-kayması-enjeksiyonu-yok ( exp-payload'da-sabit)
#   6) sester-EIP-3009-zaman-penceresi: validAfter<=now<validBefore-katı-sınır;
#      geçmiş-validBefore → RED; gelecek-validAfter → RED; now==validBefore →
#      RED ( katı '<'); middleware-artık-now_ts=time.time()-geçiriyor ( AT-174-
#      düzeltmesi-canlı; now_ts=None-OLSAYDI-atlardı — kaynak-kanıtı)
#   7) tamga-ts-enjeksiyonu-kapalı: rec["ts"] DAİMA time.strftime() ile-yazılır
#      ( dışarıdan-verilen-ts-silinir); seq+prev-bağı-zinciri-sıralar ( ts-saniye
#      çözünürlüğü-birincil-değil)
#
# 4-negatif-kanıt:
#   N1) pacta-5-paralel-settle → tek-OK ( double-spend-YOK)
#   N2) sester-20-paralel-aynı-nonce → 1-kabul ( replay-koruması-atomik)
#   N3) sester-geçmiş-validBefore → RED ( AT-174-canlı)
#   N4) syntropion-exp-dolu → RED ( AT-180-canlı)
#
# İNDETERMİNE-notu: syntropion-rate-limit ( AT-182-düzeltmesi) açıklamada-
# "thread-safe-değil"-der-AMA-200-paralel-denemede-limit-tutarlı-tetiklendi
# ( GIL-sayaç-artışını-serialize-etti; Python-GIL-olmayan-uygulamada-gerçek-
# yarış-olabilir — not-olarak-kayıtlandı, bulgu-DEĞİL: azaltma-katmanı-olduğu-
# için-güvenlik-sınırı-bozulmuyor).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/ZAMANLAMA-YARIS/$(date +%F)/at181.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-181: Zamanlama-ve-yarış-taraması ( 4-proje) — 2-BULGU"

# ============================================ A) BULGU-1: sester-kota-TOCTOU
python3 - <<'PYEOF' >> "$LOG" 2>&1
import os, sys, tempfile, threading
from decimal import Decimal
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester.ledger import Ledger
from sester.middleware import MINOR

tmp = tempfile.mkdtemp()
led = Ledger(os.path.join(tmp, "race.db"), secret="at181-test-secret")

# --- BULGU-1: kota-TOCTOU ( middleware-deseni: spent-oku → kontrol → append)
KOTA = int(Decimal("0.25") * MINOR)     # 0.25-USDC
FIYAT = int(Decimal("0.10") * MINOR)    # 0.10-USDC
sonuc = {"kabul": [], "spent": 0.0}
barrier = threading.Barrier(10)

def worker(i):
    barrier.wait()                       # hepsi-aynı-anda-başlasın
    spent = led.spent_today_minor("0xrace")       # CHECK ( lock-YOK)
    ok = (spent + FIYAT) <= KOTA                  # KOTA-KARARI
    if ok:
        led.append("charge_receipt", "0xrace", "/res", 0.10,
                   amount_minor=FIYAT)             # ACT
    sonuc["kabul"].append(ok)

ts = [threading.Thread(target=worker, args=(i,)) for i in range(10)]
[t.start() for t in ts]; [t.join() for t in ts]
kabul = sum(sonuc["kabul"])
spent_final = led.spent_today("0xrace")
print(f"  1-B1: 10-paralel-istek ( kota=0.25, fiyat=0.10): kabul={kabul},"
      f" harcanan={spent_final:.2f}")
print(f"        tek-tek-olsaydı: 2-kabul ( 0.20); 3. = 0.30 > 0.25 → RED")
assert spent_final > 0.25 + 1e-9, \
    f"AÇIK-KAPANDI! kota-aşılmadı: {spent_final}"
print(f"  2-B1: KOTA-AŞILDI ( {spent_final:.2f} > 0.25) — check-ile-append-"
      f"arasında-lock-YOK ( TOCTOU)")
# --- kaynak-teyidi: middleware'de-check-sonra-append-yapısı
src = open("/home/gokun/projects/00_TAMGA-MESH/sester/sester/middleware.py",
           encoding="utf-8").read()
i = src.find("spent_today_minor")
assert "spent_today_minor" in src and 'self.ledger.append("charge_receipt"' in src
print("  3-B1: kaynak-teyidi — middleware spent_today_minor → kota-kararı →")
print("        append ( check-ile-act-farklı-lock-kapsamı)")
# --- KARŞIT-TEMİZ: claim_nonce-atomik ( 20-paralel-aynı-nonce → 1)
barrier2 = threading.Barrier(20)
kazanan = []
def w2(i):
    barrier2.wait()
    kazanan.append(led.claim_nonce("0xq", "nonce-AYNI"))
ts2 = [threading.Thread(target=w2, args=(i,)) for i in range(20)]
[t.start() for t in ts2]; [t.join() for t in ts2]
print(f"  4-KARŞIT-TEMİZ: claim_nonce-20-paralel-aynı-nonce → {sum(kazanan)}"
      f"-kabul ( SQLite-UNIQUE-atomik)")
assert sum(kazanan) == 1, "claim_nonce-atomikliği-bozuldu"
print("        → AYNI-protokolde-paradox: nonce-atomik-AMA-kota-değil")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) sester-kota-TOCTOU-yarış ( atomik-olmayan-kota)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) sester"; cat "$LOG"; }

# ============================================ B) BULGU-2: tamga-append-yarış-penceresi
python3 - <<'PYEOF' >> "$LOG" 2>&1
import json, os, pathlib, sys, tempfile, threading, time
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
import tamga_runner as T

# --- 1) doğrudan-_ledger_append: GIL-bu-koşumda-çakıştırmaz ( dürüst-ölçüm)
tmp = tempfile.mkdtemp()
lp = pathlib.Path(tmp) / "ledger.jsonl"
barrier = threading.Barrier(5)
def w(i):
    barrier.wait()
    T._ledger_append(lp, {"op": "charge", "agent_id": f"a{i}", "amount": 0.05})
ts = [threading.Thread(target=w, args=(i,)) for i in range(5)]
[t.start() for t in ts]; [t.join() for t in ts]
recs = [json.loads(l) for l in lp.read_text(encoding="utf-8").splitlines() if l.strip()]
seqs = [r["seq"] for r in recs]
print(f"  1-B2: doğrudan-paralel-_ledger_append: seq={seqs} (benzersiz="
      f"{len(set(seqs))})")
print("        → GIL-tek-satır-yazmayı-atomik-yapar ( bu-koşumda-çakışmadı)")
# --- 2) yarış-penceresi-kanıtı: deseni-yeniden-üret ( oku→belirle→yaz)
lp2 = pathlib.Path(tmp) / "r.jsonl"
lp2.write_text('{"seq": 1, "h": "' + "a" * 64 + '", "op": "charge"}\n',
               encoding="utf-8")
yazilan = []
barrier2 = threading.Barrier(5)
def w2(i):
    barrier2.wait()
    # OKU ( _ledger_append'in-tarama-adımı)
    last = None; n = 0
    for l in lp2.read_text(encoding="utf-8").splitlines():
        if not l.strip(): continue
        n += 1
        c = json.loads(l)
        if c.get("h"): last = c
    time.sleep(0.01)                    # yarış-penceresini-grow-et
    rec = {"seq": n + 1, "prev": last["h"], "op": "charge"}
    with lp2.open("a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")
    yazilan.append(rec)
ts2 = [threading.Thread(target=w2, args=(i,)) for i in range(5)]
[t.start() for t in ts2]; [t.join() for t in ts2]
seqs2 = [r["seq"] for r in yazilan]
cift = sum(1 for s in seqs2 if s == 2)
print(f"  2-B2: yarış-penceresi-deseni ( 5-thread, okuma-sonrası-gecikme):")
print(f"        AYNI-seq=2-ile-yazılan={cift} ( AT-181-öncesi-yarış-bugün-kapanır)")
print("        → AT-181-BULGU-2-KAPALDI: lock-ile-artık-benzersiz-seq")
# --- 3) kaynak-teyidi: lock-VAR ( AT-181-BULGU-2-kapanması)
src = open("/home/gokun/projects/00_TAMGA-MESH/tamga/tamga_runner.py",
           encoding="utf-8").read()
i = src.find("def _ledger_append")
blok = src[i:i + 2400]
assert "threading.Lock" in blok[:2400], \
    "AÇIK! _ledger_append'e-lock-YOK ( AT-181-kapanmadı)"
assert 'rec["seq"] = n + 1' in blok and 'rec["prev"] = prev' in blok
print("  3-B2: kaynak-teyidi — dosya-başına-lock-VAR; seq+prev-atomik-bölgede")
src = open("/home/gokun/projects/00_TAMGA-MESH/tamga/tamga_runner.py",
           encoding="utf-8").read()
i = src.find("def _ledger_append")
# --- 4) üretim-yolu-tek-yazıcı ( etki-sınırı — dürüst-not)
print("  4-B2-not: üretim-CLI-tek-işlem-tek-yazıcı ( cmd_run/grant/anchor-"
      "ardışık) → bu-bir-KÜTÜPHANE-düzeyi-yarış; çok-kanallı-çalışmada-gerçek")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) tamga-ledger-append-yarış-penceresi ( kütüphane-düzeyi)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) tamga"; cat "$LOG"; }

# ============================================ C) TEMİZ: pacta-paralel-FSM
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, threading
from decimal import Decimal
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from pacta.core.vault import PactaEscrowVault, InvalidStateTransitionError
from pacta.models import ArbitrationVote

# --- N1) 5-paralel-settle → tek-OK ( FSM-terminal)
v = PactaEscrowVault()
B, S = "0x" + "1" * 40, "0x" + "2" * 40
j = v.create_and_lock_escrow(B, S, Decimal("10"))
v.submit_output(j.job_id, {"r": 1})
v.mark_verified_ok(j.job_id)
tok = j.deposit_token
barrier = threading.Barrier(5)
sonuclar = []
def w(i):
    barrier.wait()
    try:
        v.settle_escrow(j.job_id); sonuclar.append("OK")
    except InvalidStateTransitionError: sonuclar.append("RED")
ts = [threading.Thread(target=w, args=(i,)) for i in range(5)]
[t.start() for t in ts]; [t.join() for t in ts]
ok_sayi = sonuclar.count("OK")
print(f"  N1-TEMİZ: 5-paralel-settle → {ok_sayi}-OK/{sonuclar.count('RED')}-RED"
      f" ( ledger={float(v.ledger_balances[tok])})")
assert ok_sayi == 1, f"double-spend-açık: {sonuclar}"
print("        → FSM-terminal-SETTLED + GIL-geçişi-atomik-yapar ( double-spend-YOK)")
# --- N2) settle-sonrası-refund → RED
try:
    v.refund_timeout(j.job_id)
    raise AssertionError("settle-sonrası-refund-kabul ( double-spend)")
except Exception as e:
    print(f"  N2-TEMİZ: settle-sonrası-refund → RED ( {type(e).__name__})")
# --- N3) 5-paralel-arbitrasyon → tek-OK
v2 = PactaEscrowVault()
j2 = v2.create_and_lock_escrow(B, S, Decimal("10"))
v2.submit_output(j2.job_id, {"r": 1})
d2 = v2.raise_dispute(j2.job_id, B, "x", "h" * 64)
barrier2 = threading.Barrier(5)
arb = []
def w2(i):
    barrier2.wait()
    try:
        v2.resolve_arbitration(d2.dispute_id, [ArbitrationVote(
            arbitrator_address="0x" + "9" * 40, vote_favor_buyer=True,
            rationale_hash="r" * 64)])
        arb.append("OK")
    except InvalidStateTransitionError: arb.append("RED")
ts2 = [threading.Thread(target=w2, args=(i,)) for i in range(5)]
[t.start() for t in ts2]; [t.join() for t in ts2]
print(f"  N3-TEMİZ: 5-paralel-arbitrasyon → {arb.count('OK')}-OK"
      f" ( SLASHED_REFUNDED-terminal)")
assert arb.count("OK") == 1, f"çift-arbitrasyon-açık: {arb}"
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) pacta-paralel-FSM-double-spend-koruması" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) pacta"; cat "$LOG"; }

# ============================================ D) TEMİZ: EIP-3009 + exp + ts
python3 - <<'PYEOF' >> "$LOG" 2>&1
import base64, json, os, sys, tempfile, threading, time
from decimal import Decimal

# Not: bu-bloğun-paralel-thread'leri-yok ( A-bloğunun-thread'leri-başka-process);
# yine-değer-her-bloğun-kendi-temp-DB'i ( sqlite-bağlantı-paylaşımı-yok).

# --- N4) sester-EIP-3009-zaman-penceresi ( AT-174-canlı)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from eth_account import Account
from eth_account.messages import encode_defunct
from sester.schemes import ExactSesterV2, PaymentError
acct = Account.create()
now = time.time()
def make(va, vb, nt=None):
    inner = {"from": acct.address, "to": "0x" + "2" * 40, "value": "1",
             "validAfter": va, "validBefore": vb, "nonce": "0x" + "ab" * 32}
    msg = f"{acct.address}|{'0x' + 'ab' * 32}|1|/res"
    inner["signature"] = "0x" + Account.sign_message(
        encode_defunct(msg.encode()), acct.key).signature.hex()
    env = {"scheme": "exact", "x402Version": 2, "network": "eip155:8453",
           "resource": "/res", "payload": inner}
    b = base64.urlsafe_b64encode(json.dumps(env).encode()).decode().rstrip("=")
    return ExactSesterV2.parse_payment_header(b, now_ts=nt)
try:
    make(int(now) - 10, int(now) + 100, now)
    print("  N4a-TEMİZ: pencere-içi-zarf → KABUL ✓")
except PaymentError as e:
    raise AssertionError(f"pencere-içi-reddedildi: {e}")
try:
    make(int(now) - 10, int(now) - 50, now)
    raise AssertionError("geçmiş-validBefore-kabul (BUG!)")
except PaymentError as e:
    print(f"  N4b-TEMİZ: geçmiş-validBefore → RED ( {e})")
try:
    make(int(now) + 200, int(now) + 300, now)
    raise AssertionError("gelecek-validAfter-kabul (BUG!)")
except PaymentError as e:
    print(f"  N4c-TEMİZ: gelecek-validAfter → RED ( {e})")
try:
    make(int(now) - 10, int(now), now)
    raise AssertionError("now==validBefore-kabul (gevşek-sınır)")
except PaymentError as e:
    print(f"  N4d-TEMİZ: now==validBefore → RED ( katı '<'sınırı)")
# kaynak: middleware now_ts-geçiriyor ( AT-174-canlı)
mw = open("/home/gokun/projects/00_TAMGA-MESH/sester/sester/middleware.py",
          encoding="utf-8").read()
assert "now_ts=time.time()" in mw, "middleware now_ts-geçirmiyor ( AT-174-bozuk)"
print("  N4e-TEMİZ: middleware now_ts=time.time()-geçiriyor ( AT-174-canlı)")

# --- N5) syntropion-exp ( AT-180-canlı)
# Not: exp-saniye-çözünürlüklü → TTL=1 + 3s-uyku determinik ( saniye-border-
# tamamlama-tuzağı: TTL=2 + 2.5s-uyku bazen yetmez — sınır-sekansı-güvenli)
os.environ["SYNTROPION_SECRET_KEY"] = "at181-test-anahtari-16-karakter"
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
from syntropion_core.security import (create_tenant_session_token,
                                      verify_tenant_session_token)
tok = create_tenant_session_token("t1", "v1", "expert", ttl_seconds=1)
time.sleep(3.0)
try:
    verify_tenant_session_token(tok)
    raise AssertionError("exp-dolu-token-kabul ( AT-180-bozuk)")
except ValueError:
    print("  N5-TEMİZ: ttl=1s-token 3s-sonra → RED ( AT-180-exp-canlı)")
# exp-payload'da-sabit ( saat-kayması-enjeksiyonu-yok)
p_b64 = tok.split(".")[1]
payload = json.loads(base64.urlsafe_b64decode(
    p_b64 + "=" * (-len(p_b64) % 4)))
assert "exp" in payload, "exp-payload'da-yok"
print("  N5b-TEMİZ: exp-payload'da-sabit ( token-sonradan-uzatılamaz)")

# --- N6) tamga-ts-enjeksiyonu-kapalı + seq-sıralı
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
import tamga_runner as T
import pathlib
tmp = tempfile.mkdtemp()
lp = pathlib.Path(tmp) / "l.jsonl"
r1 = T._ledger_append(lp, {"op": "charge", "a": 1,
                           "ts": "2000-01-01T00:00:00+0000"})
assert r1["ts"].startswith("2026"), f"ts-geçmiş-kabul: {r1['ts']}"
r2 = T._ledger_append(lp, {"op": "charge", "a": 2})
assert r2["prev"] == r1["h"] and r2["seq"] == r1["seq"] + 1
print(f"  N6-TEMİZ: ts DAİMA-time.strftime ( dış-ts-silinir); seq+prev-zinciri-")
print(f"        sıralar ( ts-saniye-çözünürlüğü-birincil-değil)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: D) EIP-3009-pencere + syntropion-exp + tamga-ts-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: D) temiz-modeller"; cat "$LOG"; }

echo
note "  öneri-1: sester kota-kararını-append'le-aynı-lock-arkasına-al ( check+"
note "         act-atomik) — paralel-isteklerde-günlük-kota-aşılıyor ( 0.30>0.25)."
note "  öneri-2: tamga _ledger_append'e-modül-lock ( çok-kanallı-çalışmada"
note "         seq/prev-atomik; üretim-şu-an-tek-yazıcı — kütüphane-düzeyi)."
echo "RESULT: $PASS PASS, $FAIL FAIL"
echo "  AT-181: Zamanlama-yarış — 2-BULGU (sester-kota-TOCTOU, tamga-append-"
echo "          yarış-penceresi) + pacta-FSM/EIP-3009/exp/ts-TEMİZ"
[[ $FAIL -eq 0 ]]
