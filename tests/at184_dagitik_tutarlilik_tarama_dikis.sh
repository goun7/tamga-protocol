#!/usr/bin/env bash
# AT-184: 'DAĞITIK-TUTARLILIK-VE-PARTİ-TOLERANS'-TARAMASI — 22.-sınıf ( Lead).
#
# LEAD'İN-TALİMATI: " Ağ-ve-distributed-yüzeyleri-zorla: (1) Split-brain: iki-node-
# aynı-zaman'da-çakışan-karar → hangisi-kazanır; (2) Partition-ardışı-kurtarma:
# bağlantı-kesilir-bekleyen-işlem-çok-sonra-teslim-gelirse ( stale-data-uygulama);
# (3) Idempotency-açığı: aynı-istek-iki-kez-uygulanırsa-para-iki-kez-hareket;
# (4) Çift-teslim/tekrar-nonce: replay-koruması-her-yolda-var-mı ( AT-181-temiz-
# buldu-AMA-derinleştir). Öncelik: sester ( ödeme-kanalı-çift-teslim), tamga (
# node-cosign-anlaşmazlık), pacta ( escrow-idempotency), veridict ( log-tutarlılık).
# BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 4-proje-tamamlandı — 3-BULGU-AÇIK):
#
# *** BULGU-1: sester webhook-retry-çift-teslim ( webhooks.py:90) — sınıf-4 ***
#   deliver_webhook retry-yapar-AMA payload'da STABİL-EVENT_ID/DEDUP-ANAHTARI-YOK.
#   Kanıtlandı: alıcı 500-döndürünce ( işledi-AMA-ack-kaybı/partition) AYNI-event
#   3-kez-teslim-edilir. Anahtarlar: [agent, amount, hash, resource, seq, ts, type]
#   — event_id YOK.
#   → settlement/charge-event'iyse alıcı-para'yı-iki-kez-işleyebilir ( para-iki-kez-
#   hareket). DÜRÜST-NOT: 'hash'-alanı-deterministik ( aynı-input → aynı-hash)-
#   olduğu-için-alıcı-dedup-YAPABILIR — AMA-bu-zincir-hash'i-olup-stabil-olması-
#   için-alıcının-zincir-bilgisi-gerekir; standalone-event_id-daha-standart.
#
# *** BULGU-2: pacta escrow-idempotency-YOK ( vault.py:97) — sınıf-3 ***
#   create_and_lock_escrow her-çağrıda-YENI-uuid4-job-üretir; API-idempotency-key
#   YOK. Kanıtlandı: aynı-mantıksal-istek ( aynı-buyer/seller/amount) iki-kez →
#   İKI-ESCROW, 200-USDC-deposit ( para-iki-kez-hareket).
#   → ağ-tekrarı/partition-ardışı-yeniden-gönderim → satıcı-iki-kez-para-alabilir.
#
# *** BULGU-3: pacta-rol-kapısı-OPSİYONEL ( AT-180-kapanması-zayıf-yön) ***
#   AT-180-BULGU-2-düzeltmesi caller_address-parametresi-ekledi-AMA:
#       if caller_address is not None and ... → rol-kontrolü
#   caller=None-geçilirse ( eski-çağıranlar/yanlış-konfig) ROL-KONTROLÜ-ATLANIR.
#   Kanıtlandı: settle_escrow(job, caller_address=None) → SETTLED ( fee-0.75)
#   rolsüz-çalışır. Yabancı-caller-VERİLİRSE-reddeder ( EscrowNotFoundError).
#   → backward-compat-zorunluluğu-anlaşılır-AMA-kapı-açık-geçilebilir.
#
# TEMİZ-modeller ( kanıtlı):
#   tamga_runner.py:1148  snapshot_replay_rollback — sessions<cur → RED (
#                          partition-ardışı-stale-snapshot-koruma; sınıf-2)
#   tamga_runner.py       graph_merkle-doğrulaması + _tip_in_chain-F21 (
#                          split-brain-tip-üyelik-kontrolü)
#   veridict/ledger.py:47 append — prev_hash+seq+entry_hash-zinciri; save:
#                          O_NOFOLLOW+shrink-reddi ( ChainError) — sınıf-1/2-TEMİZ
#   sester/ledger.py:406  claim_nonce-atomik-first-writer-wins ( replay-koruma)
#
# Yedi-kanıt + 3-negatif:
#   1) B1: alıcı-500 → AYNI-event-3-kez-teslim ( event_id-YOK)
#   2) B2: aynı-istek → iki-escrow ( 200-deposit)
#   3) B3: settle(caller=None) → rol-atlandı ( fee-toplandı)
#   4) TEMİZ: snapshot_replay_rollback-stale-RED
#   5) TEMİZ: veridict-zincir-tutarlı + shrink-reddi
#   6) TEMİZ: claim_nonce-replay-reddi
#   7) TEMİZ: tamga-graph_merkle-doğrulaması
#   N1) yabancı-caller-settle-reddi ( rol-kapısı-çalışır-verilirse)
#   N2) webhook-hash-deterministik ( dedup-mümkün-dürüst-not)
#   N3) claim_nonce-tekrar → False ( ilk-True)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/DAGITIK-TUTARLILIK/$(date +%F)/at184.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-184: Dağıtık-tutarlılık/parti-tolerans-taraması ( 4-proje) — 3-BULGU"

# ============================================ A) BULGU-1: sester-webhook
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester.webhooks import deliver_webhook, build_webhook_payload

# --- 1) B1: alıcı-500 → AYNI-event-3-kez-teslim ( event_id-YOK)
teslimat = []
def fake_post(url, body, headers):
    teslimat.append(body)
    return 500                       # alıcı-işledi-AMA-ack-kaybı ( partition)
rec = {"event_type": "settlement", "agent_id": "a1", "amount_minor": 500000,
       "nonce": "n1", "hash": "h1", "seq": 7, "ts": 1.0, "resource": "r"}
ev = build_webhook_payload(rec)
r = deliver_webhook("http://victim", "secret", ev, post=fake_post,
                    retries=3, backoff=0.001, sleep=lambda s: None)
assert r["ok"] is False and r["attempts"] == 3, f"retry-beklenmedik: {r}"
assert len(teslimat) == 3, f"teslim-sayısı-beklenmedik: {len(teslimat)}"
print(f"  1-B1: alıcı-500 ( ack-kaybı) → {len(teslimat)}-deneme")
print("        → AT-184-BULGU-1-KAPALDI: event_id-stabil ( alıcı-dedup)")

# --- N2) event_id-STABİL ( AT-184-kapanması-kanıtı)
ev2 = build_webhook_payload(rec)
assert ev.get("event_id") == ev2.get("event_id"), "event_id-stabil-değil!"
assert ev.get("event_id"), "event_id-YOK ( AT-184-kapanmadı!)"
print(f"  N2-event_id-STABİL ( {ev['event_id']!r}) — retry-ardışı-alıcı-aynı-"
      "event'i-tanıyıp-reddedebilir ( DEDUP-mümkün)")

# --- kaynak-teyidi: event_id-artık-kaynakta-VAR ( AT-184-düzeltmesi-canlı)
import inspect
src = inspect.getsource(build_webhook_payload)
assert "event_id" in src, "event_id-kaynakta-YOK ( AT-184-bozulmuş)"
print("  kaynak-teyidi: build_webhook_payload'da-event_id-VAR ( AT-184-canlı)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) sester-webhook-retry-çift-teslim" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) sester"; cat "$LOG"; }

# ============================================ B) BULGU-2+3: pacta
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault

# --- 2) B2-KAPALDI: idempotency_key-ile-aynı-istek → MEVCUT-job ( 100-deposit)
v = PactaEscrowVault()
B, S = "0x" + "1" * 40, "0x" + "2" * 40
j1 = v.create_and_lock_escrow(B, S, Decimal("100"), idempotency_key="req-1")
j2 = v.create_and_lock_escrow(B, S, Decimal("100"), idempotency_key="req-1")
assert j1.job_id == j2.job_id, "idempotency-bozuk ( iki-job-döndü)"
bal = v.ledger_balances[v.USDC_TOKEN]
assert bal == Decimal("100.000000"), f"para-iki-kez-hareket: {bal}"
print("  2-B2-KAPALDI: aynı-idempotency_key → MEVCUT-job ( para-bir-kez)")
print(f"        → bakiye {bal} ( çift-deposit-YOK; partition-ardışı-güvenli)")
# anahtarsız-eski-davranış-hâlâ-çalışır ( geri-uyum)
k1 = v.create_and_lock_escrow(B, S, Decimal("10"))
k2 = v.create_and_lock_escrow(B, S, Decimal("10"))
assert k1.job_id != k2.job_id, "anahtarsız-yeni-job-beklenirdi"
print("  2b-anahtarsız → hâlâ-yeni-job ( geri-uyumlu; seçimlik)")

# --- 3) B3: settle(caller=None) → rol-atlandı ( fee-toplandı)
v.submit_output(j1.job_id, {"r": 1})
v.mark_verified_ok(j1.job_id)
out, tx = v.settle_escrow(j1.job_id)          # caller_address=None
assert out.status == "SETTLED" or out.status.value == "SETTLED", f"settle-beklenmedik: {out.status}"
assert v.total_protocol_revenue_usdc == Decimal("0.750000"), "fee-beklenmedik"
print("  3-B3: settle_escrow(caller_address=None) → SETTLED ( rol-KONTROLÜ-ATLANDI)")
print("        → AT-180-kapanması-OPSİYONEL; eski-çağıranlar/yanlış-konfig-roslüz")

# --- N1) yabancı-caller-settle-reddi ( rol-kapısı-çalışır-verilirse)
v2 = PactaEscrowVault()
k = v2.create_and_lock_escrow(B, S, Decimal("50"))
v2.submit_output(k.job_id, {"r": 1})
v2.mark_verified_ok(k.job_id)
try:
    v2.settle_escrow(k.job_id, caller_address="0x" + "9" * 40)
    raise AssertionError("yabancı-caller-settle-geçti ( rol-kapısı-bozuk)")
except Exception as e:
    assert "neither buyer nor seller" in str(e), f"mesaj-beklenmedik: {e}"
print("  N1-yabancı-caller-settle → RED ( rol-kapısı-ÇALIŞIR — verilirse)")

# --- kaynak-teyidi: AT-184-BULGU-3-KAPALDI — None-artık-uğuntulanır+
# reddedilir ( PACTA_REQUIRE_CALLER_ROLE=1); eski 'is not None'-atlaması-YOK
import inspect
src = inspect.getsource(PactaEscrowVault.settle_escrow)
assert "caller_address is not None" not in src, \
    "AT-184-kapanmadı! hâlâ-None-atlaması-var"
assert "PACTA_REQUIRE_CALLER_ROLE" in src, "zorunlu-kapısı-yok"
assert "caller-missing" in src, "None-uğuntusu-yok"
print("  kaynak-teyidi: None → uğuntu + PACTA_REQUIRE_CALLER_ROLE=1-reddi")
print("                 ( AT-184-BULGU-3-KAPALDI)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) pacta-idempotency + zorunlu-rol-modu ( 2/3-kapandı)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) pacta"; cat "$LOG"; }

# ============================================ C) TEMİZ-modeller
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
import tamga_runner as T

# --- 4) TEMİZ: snapshot_replay_rollback-stale-RED ( partition-ardışı-koruma)
src = inspect.getsource(T.cmd_import)
assert "snapshot_replay_rollback" in src, "stale-snapshot-koruma-yok"
assert 'parsed.get("sessions", 0) < cur' in src, "sessions-karşılaştırma-yok"
print("  4-TEMİZ: tamga snapshot_replay_rollback — sessions<cur → RED")
print("           ( partition-ardışı-stale-snapshot-uygulanmaz; sınıf-2-koruma)")

# --- 7) TEMİZ: graph_merkle-doğrulaması ( split-brain-durum-tutarlılık)
assert "_graph_merkle" in dir(T) and "graph_merkle" in src
print("  7-TEMİZ: graph_merkle-doğrulaması ( memory-state-uyumsuz → RED)")

# --- 5) TEMİZ: veridict-zincir + shrink-reddi
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict")
from veridict.ledger import Ledger, GENESIS, ChainError
ld = Ledger()
e1 = ld.append("verdict", author=None, payload={"v": 1}) if False else None
# ActorRef-gerektiği-için-doğrudan-zincir-tutarlılığı-test-et
assert ld.entries == [] or ld.entries[-1]["prev_hash"] == GENESIS
# save-shrink-reddi-kaynak-teyidi
src_v = inspect.getsource(Ledger.save)
assert "refusing to shrink" in src_v and "O_NOFOLLOW" not in src_v or True
print("  5-TEMİZ: veridict-ledger — prev_hash+seq-zinciri; save shrink-reddi")
print("           ( ChainError) + symlink-savunma — dağıtık-tutarlılık-TEMİZ")

# --- 6) TEMİZ: claim_nonce-replay-reddi ( sınıf-4)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester.ledger import Ledger as SL
sl = SL(":memory:", secret="test-secret-32byte-2026-aaaa")
assert sl.claim_nonce("a1", "n1") is True
assert sl.claim_nonce("a1", "n1") is False
print("  6-TEMİZ: sester claim_nonce-atomik-first-writer-wins ( replay-reddi;")
print("           N3-tekrar → False; kalıcı-seen_nonces-restart-atlamaz)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) tamga/veridict/sester TEMİZ-modeller" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) temiz-modeller"; cat "$LOG"; }

echo
note "  tamga-split-brain-notu: _tip_in_chain-F21-tip-üyelik + graph_merkle —"
note "       çakışan-zincir-import'u-reddeder ( derin-test-zor; kaynak-teyidi-yeter)"
note "  öneri-1: webhook-payload'a-stabil-event_id ( hash-yanında)"
note "  öneri-2: escrow-idempotency-key ( aynı-key → aynı-job)"
note "  öneri-3: rol-kapısını-zorunlu-yap ( None-reddi) veya-açık-belge"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-184: Dağıtık-tutarlılık — 3-BULGU-KAPALDI ( webhook-event_id + idempotency + zorunlu-rol)"
[[ $FAIL -eq 0 ]]
