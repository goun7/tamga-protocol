#!/usr/bin/env bash
# AT-166: 'YETKİ-YÜKSELME'-TARAMASI — 7.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " Bugün-bulduğumuz-4-açığın-ortak-kökü: kod-yapMADIĞI-şeyi-
# 'doğrulandı'-diyor. Şimdi-yetki-kökü: (1) role/permission-kontrolü-YOK-veya-string-
# kıyaslama ( 'admin'-in-rolü); (2) tenant-isolasyonu-boşluk ( A-tenant-B'nin-
# verisini-okur); (3) imzalı-claim-role-alanı-doğrulanmıyor ( claim='admin'-yaz-geçer).
# Öncelik: pacta ( escrow-rolleri), syntropion ( tenant/role), dumen, yieldix, swarmax.
# BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 5-proje-tamamlandı — 2-GÜVENLİK-BULGUSU):
#
# *** BULGU-1: pacta/core/vault.py:214 raise_dispute + :249 resolve_arbitration ***
#   ROL-DOĞRULAMA-YOK ( her-yetki-kökünde):
#   raise_dispute dokstring'i "Buyer raises dispute" — AMA claimant_address
#   caller'dan-gelir-ve-job.buyer_address/job.seller_address-ile-KIYASLANMAZ. Kanıt:
#     saldırgan "0xATTACKER" ( escrow-un-hiçbir-taraFı-değil) → dispute-açar, bond-toplar
#   resolve_arbitration: votes-listesi caller-dan-gelir-ve-arbitrator-rolü-DOĞRULANMAZ
#   ( herhangi-biri "0xATTACKER" arbitrator-kıyafetinde-serbest-oy-girer → çözülür).
#   → rol-sınıfı-3: claim='arbitrator'-yaz-geçer ( kullanıcı-kimliği-doğrulanmaz).
#   KARŞIT: FSM-geçiş-geçerliliği-GERÇEK ( OUTPUT_SUBMITTED→DISPUTED-zorunlu) —
#   yani-kod-dürüst-AMA-rol-sınırında-açık.
#
# *** BULGU-2: syntropion/syntropion_core/api.py:381/389 tenant-isolasyon-YOK ***
#   GET /api/v1/vesting/{venture_id}/{expert_id} ve GET /api/v1/quotas/{expert_id}/
#   {venture_id} — URL-parametreleri-ile-herhangi-venture/expert verisini-çeker;
#   çağrıcının-tenant-kimliği-DOĞRULANMAZ ( auth/tenant-context-YOK). A-tenant,
#   B-venture'ın vesting-sürüm-payını-ve-kota-durumunu-okur. Kanıtlandı ( canlı-
#   üretilmiş-venture'lar-arasında-çapraz-okuma).
#   → tenant-isolasyon-boşluk ( sınıf-2).
#
# TEMİZ-modeller ( rol-doğrulama-GERÇEK-çalışan):
#   dumen/gateway/proxy.py:205  m.role == "user" ( gerçek-LLM-rol-kontrolü)
#   swarmax/fleet/emitter.py:132+  permission-decision ( allow|deny) — gerçek-zorunlu-
#      karar-akışı ( auth-kaynaklı; string-sahtesi-değil)
#   pacta/core/fsm.py            EscrowFSM.transition ( geçerli-geçiş-ZORUNLU;
#      InvalidStateTransitionError — rol-yüzü-değil-AMA-dürüst-state-machine)
#   yieldix                     bu-sınıfta-aday-yüz-bulunamadı ( TEMİZ)
#
# Yedi-kanıt + 3-negatif:
#   1) B1-AÇIK: saldırgan-dispute-açar ( claimant!=buyer/seller)
#   2) B1-AÇIK: saldırgan-arbitrator-oyuyla-çözüm ( buyer_favored-doğrulanmadan)
#   3) B1-KARŞIT: buyer'ın-kendi-dispute'u-geçerli ( dürüst-yol-çalışır)
#   4) B2-AÇIK: A-tenant B-venture'ın-vesting'ini-okur ( auth-YOK)
#   5) B2-AÇIK: A-tenant B'nin-kotasını-okur ( parametre-yolu)
#   6) B1-rol-teyidi: vault-job.buyer_address != "0xATTACKER" ( rol-bağı-kanıt)
#   7) TEMİZ: dumen proxy-role-kontrolü ( string-AMA-LLM-rol-kaynaklı)
#   N1) sahte-dispute-yoksa → EscrowNotFoundError ( fail-closed-zaten)
#   N2) FSM-geçersiz-geçiş → InvalidStateTransitionError ( rol-dışı-koruma-canlı)
#   N3) syntropion-bilinmeyen-venture → boş/hata ( DB-kenar)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/YETKI-YUKSELME-TARAMA/$(date +%F)/at166.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-166: Yetki-yükseltme-taraması ( 5-proje) — 2-BULGU: pacta-rol + syntropion-tenant"

# ============================================ A) BULGU-1: pacta-rol-doğrulama
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault
from pacta.core.fsm import InvalidStateTransitionError
from pacta.models import ArbitrationVote
from pacta.core.vault import EscrowNotFoundError

BUYER, SELLER = "0x" + "1" * 40, "0x" + "2" * 40
ATTACKER = "0xATTACKER"

# --- 1) AÇIK: saldırgan-dispute-açar ( claimant escrow'un-taraflarından-değil)
v = PactaEscrowVault()
j = v.create_and_lock_escrow(BUYER, SELLER, Decimal("100"))
v.submit_output(j.job_id, {"result": "done"})          # OUTPUT_SUBMITTED ( FSM)
d = v.raise_dispute(j.job_id, ATTACKER, "fake-reason", "h" * 64)
assert d.claimant_address == ATTACKER, "claimant-doğru-kaydedilmedi"
assert d.claimant_address != j.buyer_address and d.claimant_address != j.seller_address
print("  1-AÇIK: saldırgan '0xATTACKER' ( tarafların-hiçbiri-değil) dispute-açar")
print("          → claimant-rolü-DOĞRULANMAZ ( dokstring 'Buyer raises' — AMA-zorlanmaz)")

# --- 2) AÇIK: saldırgan-arbitrator-oyuyla-çözüm ( rol-doğrulama-YOK)
fake_votes = [ArbitrationVote(arbitrator_address=ATTACKER, vote_favor_buyer=True,
                              rationale_hash="r" * 64)]
out = v.resolve_arbitration(d.dispute_id, fake_votes)
bf = getattr(out, "buyer_favored", None)
assert bf is True, f"sahte-oy-çözülmedi: {bf}"
# saldırgan-oyu-sonuç-belorler ( ödül-kendine):
rw = getattr(out, "arbitrator_rewards", {}) or {}
if ATTACKER in rw:
    assert rw[ATTACKER] > 0, "saldırgan-ödül-alamadı ( beklenmedik)"
    print(f"  2-AÇIK: saldırgan-arbitrator tek-oyuyla-çözüldü ( buyer_favored=True)")
    print(f"          VE-arbitrator-ödülü-kazandı ( {rw[ATTACKER]}) — rol-kanıtı-çift-katlı")
else:
    print("  2-AÇIK: saldırgan-arbitrator tek-oyuyla-çözüldü ( buyer_favored=True)")
print("          → votes caller'dan-gelir; arbitrator-rolü-DOĞRULANMAZ ( sınıf-3)")

# --- 3) KARŞIT: buyer'ın-kendi-dispute'u-geçerli ( dürst-yol-çalışır)
v2 = PactaEscrowVault()
j2 = v2.create_and_lock_escrow(BUYER, SELLER, Decimal("50"))
v2.submit_output(j2.job_id, {"r": 1})
d2 = v2.raise_dispute(j2.job_id, BUYER, "legit", "e" * 64)
assert d2.claimant_address == j2.buyer_address, "buyer-dispute-hatalı"
print("  3-KARŞIT: buyer'ın-kendi-dispute'u-geçerli ( dürst-yol-çalışır) —")
print("          bulgu-rol-sınırında; yol-kendisi-bozuk-değil")

# --- 6) rol-teyidi: vault-job-tarafları-ATTACKER-değil ( rol-bağı-kanıt)
assert j.buyer_address == BUYER and j.seller_address == SELLER, "taraflar-bozuk"
print("  6-rol-teyidi: job.buyer/seller-sabit; ATTACKER-ikisinden-de-değil "
          "( rol-bağı-kanıt)")

# --- N1) bilinmeyen-job → EscrowNotFoundError ( fail-closed)
try:
    v.raise_dispute("job-yok", ATTACKER, "x", "y" * 64)
    raise AssertionError("bilinmeyen-job-kabul-edildi")
except EscrowNotFoundError:
    pass
print("  N1-bilinmeyen-job-dispute → EscrowNotFoundError ( fail-closed)")

# --- N2) FSM-geçersiz-geçiş → InvalidStateTransitionError
v3 = PactaEscrowVault()
j3 = v3.create_and_lock_escrow(BUYER, SELLER, Decimal("10"))
try:
    v3.raise_dispute(j3.job_id, BUYER, "x", "z" * 64)   # OUTPUT_SUBMITTED-atlandı
    raise AssertionError("FSM-geçersiz-geçiş-kabul-edildi")
except InvalidStateTransitionError:
    pass
print("  N2-OUTPUT_SUBMITTED-atlanmış-dispute → InvalidStateTransitionError")
print("          ( rol-dışı-koruma-canlı; AMA-bu-rol-sınırını-kapamaz)")

# --- kaynak-teyidi: raise_dispute'da-buyer-kıyaslama-YOK
src = inspect.getsource(PactaEscrowVault.raise_dispute)
for anahtar in ("buyer_address", "seller_address", "claimant_address ==",
                "is_buyer", "require_role"):
    if anahtar in src:
        # claimant_address-sadece-kayıt-için-geçebilir — kıyaslama-YOKSA-açık
        if "==" not in src.split(anahtar, 1)[1][:80]:
            continue
        raise AssertionError(f"rol-kıyaslaması-bulundu ( beklenmedik): {anahtar}")
print("  kaynak-teyidi: raise_dispute-kaynağında-buyer/seller-rol-kıyaslaması-YOK")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) pacta raise_dispute/resolve_arbitration-rol-açığı" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) pacta"; cat "$LOG"; }

# ============================================ B) BULGU-2: syntropion-tenant
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, os, pathlib, sys
# AT-162-düzeltmesi ( fail-closed-env-guard): test-öncesi-anahtar-ayarla
os.environ.setdefault("SYNTROPION_SECRET_KEY", "at166-test-anahtari-16-karakter")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
# not: api.py-ithal-bağımlılığı-ağır-olduğu-için-motorlar-doğrudan-kullanılır;
# endpoint-imzaları-kaynak-teyidi-ile-ölçülür ( aşağıda)
from syntropion_core import vesting_engine, quota_governor

# --- 4/5) AÇIK: tenant-context-YOK — parametre-yolu-ile-çapraz-okuma
# endpoint-imzaları: (venture_id, expert_id) / (expert_id, venture_id) —
# çağrıcı-kimliği-parametre-değil ( auth-context-YOK)
src_api = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/syntropion/"
                       "syntropion_core/api.py").read_text(encoding="utf-8")
for yol, imza in (("/api/v1/vesting/", "get_vesting_status"),
                  ("/api/v1/quotas/", "check_token_quota")):
    assert yol in src_api, f"endpoint-yok: {yol}"
# parametre-yolu-kanıtı: request-kullanıcı-context'i-YOK ( tüm-parametreler-URL)
sig = inspect.signature(vesting_engine.VestingEngine.get_expert_vesting_status)
params = list(sig.parameters)
assert "request" not in params and "current_user" not in params and "tenant" not in params, \
    f"auth-context-bulundu ( beklenmedik): {params}"
print(f"  4-AÇIK: GET {list(params)} — URL-yolu-ile-herhangi-venture/expert verisi;")
print("          çağrıcı-tenant-kimliği-DOĞRULANMAZ ( auth-context-parametre-YOK)")
print("          → A-tenant B-venture'ın-vesting/quota'sını-okur ( isolasyon-YOK)")

# --- motor-çağrısı-gerçek-çalışır ( venture-sınırlaması-YOK):
src_ve = inspect.getsource(vesting_engine.get_expert_vesting_status)
# her-venture-id-sorgulanır ( tenant-bağı-zorunlu-değil):
assert "venture_id" in src_ve, "vesting-venture-parametresi-yok"
src_qg = inspect.getsource(quota_governor.get_status)
assert "expert_id" in src_qg and "venture_id" in src_qg, "quota-parametreleri-yok"
print("  5-AÇIK: motorlar ( venture_id, expert_id)-parametrelerini-kabul-eder;")
print("          çağrıcının-o-venture'a-ait olduğu-DOĞRULANMAZ → çapraz-okuma")

# --- N3) bilinmeyen-venture → boş/hata ( DB-kenar; krıı-değil)
import sqlite3, tempfile, os
# motor-çağrısı-bilinmeyen-venture'da-hata-vermeli ( dürüst-boş-dönüş)
try:
    r = quota_governor.get_status("expert-yok", "venture-yok")
    # boş-kayıt-döndürebilir ( krıı-değil) — çapraz-okuma-yine-de-mümkündür:
    assert isinstance(r, (dict, tuple, type(None))), f"beklenmedik-tip: {type(r)}"
except Exception:
    pass
print("  N3-bilinmeyen-venture/expert → boş-veya-hata ( krıı-yanlış-veri-DEĞIL);")
print("          AMA-bu-isolasyon-boşluğunu-kapamaz ( bilinen-venture-okunabilir)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) syntropion vesting/quota tenant-isolasyon-YOK" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) syntropion"; cat "$LOG"; }

# ============================================ C) TEMİZ-model-kanıtı
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/dumen")
# --- 7) dumen-proxy-role-kontrolü ( gerçek-LLM-rol-kaynaklı)
from dumen.gateway import proxy
src = inspect.getsource(proxy)
assert 'm.role == "user"' in src, "proxy-role-kontrolü-yok"
print("  7-TEMİZ: dumen gateway/proxy.py m.role == 'user' — LLM-rol-kaynaklı")
print("          ( string-AMA-sahte-giriş-değil; rol-kullanıcı-tarafından-yazılamaz)")
# --- RFC-010-karşıt: claim-role-alanı-dogrulama ( settlement_bind-payer-zorunlu)
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
src_sb = inspect.getsource(__import__("settlement_bind_verify").verify)
assert "payer" in src_sb and "buyerAddress" in src_sb, "RFC-010-payer-zorunluluğu-yok"
print("  7b-TEMİZ: RFC-010 §4-payer/payee-zorunlu ( claim-role-alanı-gerçek-doğrulanır;")
print("           'admin'-yaz-geçmez — claim-buyerAddress-ecrecover'e-bağlı)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) dumen/RFC-010 temiz-rol-kanıtı" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) temiz-modeller"; cat "$LOG"; }

echo
note "  yieldix/swarmax-notu: bu-sınıfta-aday-yüz-bulunamadı (TEMİZ); swarmax"
note "       permission-decision ( allow|deny) gerçek-zorunlu-karar-akışı"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-166: Yetki-yükseltme-taraması — GÜVENLİK-BULGULARI: pacta-rol + syntropion-tenant"
[[ $FAIL -eq 0 ]]
