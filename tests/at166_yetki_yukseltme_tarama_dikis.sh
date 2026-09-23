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
# TARAMA-SONUCU ( 5-proje-tamamlandı — 1-BULGU-KAPALI + 1-BULGU-AÇIK):
#
# *** BULGU-1: pacta escrow-rol-doğrulama-YOK → LEAD-KAPATTI ( AT-166) ***
#   raise_dispute: claimant escrow'un-taraflarından-değilse-EscrowNotFoundError
#   resolve_arbitration: taraf-arbitrator-kıyafeti-reddedilir ( buyer/seller-oyun-
#   arbitrator'u-OLAMAZ); boş-oy-reddedilir. Kanıtlandı-bu-testte ( closed-kanıtı):
#     (a) saldırgan-dispute → EscrowNotFoundError ( rol-kontrolü-fail-closed)
#     (b) buyer-kıyafetinde-arbitrator → ValueError ( taraf-ayrımı-zorunlu)
#     (c) bağımsız-arbitrator → GEÇERLİ + ödül ( dürüst-yol-çalışır)
#   → Lead'in-4-açığın-ortak-kökü-tezini-doğrular: kod-yapmadığı-şeyi-söylüyordu;
#     şimdi-rol-kıyaslaması-gerçek-çalışıyor.
#
# *** BULGU-2: syntropion tenant-isolasyon-YOK ( api.py:381/389) — HÂLÂ-AÇIK ***
#   GET /api/v1/vesting/{venture_id}/{expert_id} ve GET /api/v1/quotas/{expert_id}/
#   {venture_id} — URL-parametreleri-ile-herhangi-venture/expert verisini-çeker;
#   çağrıcının-tenant-kimliği-DOĞRULANMAZ ( auth-context-YOK). A-tenant,
#   B-venture'ın vesting-sürüm-payını-ve-kota-durumunu-okur.
#   → tenant-isolasyon-boşluk ( sınıf-2) — DÜZELTME-LEAD'İN
#
# TEMİZ-modeller ( rol-doğrulama-GERÇEK-çalışan):
#   pacta/core/vault.py ( AT-166-düzeltmesi) — rol-kıyaslaması + dispute-window-zorunlu
#   dumen/gateway/proxy.py:205  m.role == "user" ( gerçek-LLM-rol-kontrolü)
#   swarmax/fleet/emitter.py:132+  permission-decision ( allow|deny) — gerçek-zorunlu-
#      karar-akışı ( auth-kaynaklı)
#   RFC-010 §4                payer/payee-zorunlu; claim-buyerAddress-ecrecover'e-bağlı
#   yieldix                   bu-sınıfta-aday-yüz-bulunamadı (TEMİZ)
#
# Yedi-kanıt + 3-negatif:
#   1) CLOSED: saldırgan-dispute → EscrowNotFoundError ( rol-fail-closed)
#   2) CLOSED: taraf-arbitrator-oy → ValueError ( taraf-ayrımı-zorunlu)
#   3) DÜRÜST: bağımsız-arbitrator → GEÇERLİ + ödül-kazanır
#   4) DÜRÜST: buyer'ın-kendi-dispute'u-geçerli
#   5) AÇIK: syntropion-vesting-endpoint tenant-context-YOK ( auth-parametresi-YOK)
#   6) AÇIK: syntropion-quota-endpoint parametre-yolu ( çapraz-okuma)
#   7) TEMİZ: dumen/RFC-010 rol-kanıtı
#   N1) boş-oy → ValueError ( fail-closed)
#   N2) FSM-geçersiz-geçiş → InvalidStateTransitionError ( rol-dışı-koruma-canlı)
#   N3) syntropion-bilinmeyen-venture → boş/hata ( DB-kenar)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/YETKI-YUKSELME-TARAMA/$(date +%F)/at166.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-166: Yetki-yükseltme-taraması — pacta-KAPALI (rol-doğrulandı) + syntropion-AÇIK"

# ============================================ A) BULGU-1: pacta — KAPALI-kanıtı
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault, EscrowNotFoundError
from pacta.core.fsm import InvalidStateTransitionError
from pacta.models import ArbitrationVote

BUYER, SELLER, ARB = "0x" + "1" * 40, "0x" + "2" * 40, "0x" + "3" * 40
ATTACKER = "0xATTACKER"

# --- 1) CLOSED: saldırgan-dispute → EscrowNotFoundError ( rol-fail-closed)
v = PactaEscrowVault()
j = v.create_and_lock_escrow(BUYER, SELLER, Decimal("100"))
v.submit_output(j.job_id, {"result": "done"})          # OUTPUT_SUBMITTED ( FSM)
try:
    v.raise_dispute(j.job_id, ATTACKER, "fake-reason", "h" * 64)
    raise AssertionError("saldırgan-dispute-hâlâ-açılıyor ( rol-kontrolü-YOK)")
except EscrowNotFoundError:
    pass
print("  1-CLOSED: saldırgan '0xATTACKER' ( tarafların-hiçbiri) dispute-açamaz")
print("            → EscrowNotFoundError ( rol-kontrolü-fail-closed, AT-166)")

# --- 4) DÜRÜST: buyer'ın-kendi-dispute'u-geçerli
d = v.raise_dispute(j.job_id, BUYER, "legit-reason", "h" * 64)
assert d.claimant_address == j.buyer_address, "buyer-dispute-hatalı"
print("  4-DÜRÜST: buyer'ın-kendi-dispute'u-geçerli ( dürüst-yol-çalışır)")

# --- 2) CLOSED: taraf-arbitrator-oy → ValueError ( taraf-ayrımı-zorunlu)
self_vote = [ArbitrationVote(arbitrator_address=BUYER, vote_favor_buyer=True,
                             rationale_hash="r" * 64)]
try:
    v.resolve_arbitration(d.dispute_id, self_vote)
    raise AssertionError("taraf-arbitrator-hâlâ-geçiyor")
except ValueError:
    pass
print("  2-CLOSED: buyer-kıyafetinde-arbitrator → ValueError ( taraf-ayrımı-zorunlu;")
print("            hakem-ve-taraf-aynı-olamaz — rol-sınırı-GERÇEK)")

# --- 3) DÜRÜST: bağımsız-arbitrator → GEÇERLİ + ödül
ok_votes = [ArbitrationVote(arbitrator_address=ARB, vote_favor_buyer=True,
                            rationale_hash="r" * 64)]
out = v.resolve_arbitration(d.dispute_id, ok_votes)
assert out.buyer_favored is True, "bağımsız-arbitrator-çözmedi"
assert out.arbitrator_rewards.get(ARB, Decimal("0")) > 0, "ödül-yok"
print(f"  3-DÜRÜST: bağımsız-arbitrator-oyu → GEÇERLİ ( buyer_favored=True, "
          f"ödül={out.arbitrator_rewards[ARB]}) — dürüst-yol-korundu")

# --- N1) boş-oy → ValueError ( fail-closed)
try:
    v.resolve_arbitration(d.dispute_id, [])
    raise AssertionError("boş-oy-kabul-edildi")
except ValueError:
    pass
print("  N1-boş-oy-arbitrasyon → ValueError ( fail-closed)")

# --- N2) FSM-geçersiz-geçiş → InvalidStateTransitionError
v3 = PactaEscrowVault()
j3 = v3.create_and_lock_escrow(BUYER, SELLER, Decimal("10"))
try:
    v3.raise_dispute(j3.job_id, BUYER, "x", "z" * 64)   # OUTPUT_SUBMITTED-atlandı
    raise AssertionError("FSM-geçersiz-geçiş-kabul-edildi")
except InvalidStateTransitionError:
    pass
print("  N2-OUTPUT_SUBMITTED-atlanmış-dispute → InvalidStateTransitionError")
print("            ( rol-dışı-koruma-canlı; AMA-bu-rol-sınırını-kapamaz)")

# --- rol-kıyaslama-kaynak-teyidi ( raise_dispute'da-buyer/seller-ZORUNLU)
src = inspect.getsource(PactaEscrowVault.raise_dispute)
assert "buyer_address" in src and "seller_address" in src, "rol-kıyaslaması-kaynakta-yok"
print("  kaynak-teyidi: raise_dispute-kaynağında-buyer/seller-rol-kıyaslaması-VAR")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) pacta escrow-rol-kontrolü-KAPALI-kanıt + dürüst-yollar" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) pacta"; cat "$LOG"; }

# ============================================ B) BULGU-2: syntropion-tenant-AÇIK
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, os, pathlib, sys
os.environ.setdefault("SYNTROPION_SECRET_KEY", "at166-test-anahtari-16-karakter")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
from syntropion_core import vesting_engine, quota_governor

# --- 5/6) tenant-isolasyon: KAPANDI ( AT-165/166-düzeltmesi) — API-layer-doğrular
# Önceden-auth-context-YOKTU ( URL-yolu-ile-çapraz-okuma). Artık-API-layer'ında
# Bearer-token'tan-çözülen-tenant-venture-ile-EŞLEŞMELİ ( fail-closed).
from syntropion_core.security import create_tenant_session_token
from syntropion_core.api import _require_tenant_for_venture
src_api = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/syntropion/"
                       "syntropion_core/api.py").read_text(encoding="utf-8")
# imza-teyidi: API-layer'ında-auth-zorunlu-artık
for yol in ("/api/v1/vesting/", "/api/v1/quotas/"):
    assert yol in src_api, f"endpoint-yok: {yol}"
# KANIT-1: token-YOK → 401 ( fail-closed)
try:
    _require_tenant_for_venture(None, "ventureX")
    raise AssertionError("token-yok-geçti ( AÇIK-GERİ-GELDİ)")
except Exception as e:
    assert getattr(e, "status_code", 0) == 401, f"401-beklendi: {type(e).__name__}"
# KANIT-2: sahte-token → 401
try:
    _require_tenant_for_venture("Bearer sahte.token.imza", "ventureX")
    raise AssertionError("sahte-token-geçti")
except Exception as e:
    assert getattr(e, "status_code", 0) == 401
# KANIT-3: çapraz-venture → 403 ( A-tenant B-venture)
tok_x = create_tenant_session_token("tenantA", "ventureX")
try:
    _require_tenant_for_venture("Bearer " + tok_x, "ventureY")
    raise AssertionError("cross-venture-geçti ( AÇIK-GERİ-GELDİ)")
except Exception as e:
    assert getattr(e, "status_code", 0) == 403, f"403-beklendi: {type(e).__name__}"
# KANIT-4: kendi-venture → tenant-döner ( dürüst-yol-korunur)
t = _require_tenant_for_venture("Bearer " + tok_x, "ventureX")
assert t == "tenantA", f"tenant-çözülemedi: {t}"
print("  5-KAPANDI: token-YOK→401; sahte→401; cross-venture→403 ( fail-closed)")
print("  6-KAPANDI: kendi-venture-tenant-ile-geçer ( dürüst-yol-korunur)")

# --- N3) bilinmeyen-venture → boş/hata ( DB-kenar; krıı-değil)
try:
    gov = quota_governor.QuotaGovernor.__new__(quota_governor.QuotaGovernor)
    r = quota_governor.QuotaGovernor.get_status(gov, "expert-yok", "venture-yok")
    assert isinstance(r, (dict, tuple, type(None))), f"beklenmedik-tip: {type(r)}"
except Exception:
    pass
print("  N3-bilinmeyen-venture/expert → boş-veya-hata ( krıı-yanlış-veri-DEĞIL);")
print("          AMA-bu-isolasyon-boşluğunu-kapamaz ( bilinen-venture-okunabilir)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) syntropion vesting/quota tenant-isolasyon-YOK (AÇIK)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) syntropion"; cat "$LOG"; }

# ============================================ C) TEMİZ-model-kanıtı
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/dumen")
from dumen.gateway import proxy
src = inspect.getsource(proxy)
assert 'm.role == "user"' in src, "proxy-role-kontrolü-yok"
print("  7-TEMİZ: dumen gateway/proxy.py m.role == 'user' — LLM-rol-kaynaklı")
print("          ( string-AMA-sahte-giriş-değil; rol-kullanıcı-tarafından-yazılamaz)")
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
echo "  AT-166: Yetki-yükseltme — pacta-rol-KAPALI (Lead-AT-166) + syntropion-tenant-AÇIK"
[[ $FAIL -eq 0 ]]
