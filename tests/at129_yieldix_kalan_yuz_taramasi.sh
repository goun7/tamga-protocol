#!/usr/bin/env bash
# AT-129: YIELDIX-BEŞİNCİ-YÜZ — kalan-ölçülmemiş-yüzlerin-DÜRÜST-taraması.
#
# 99-Yieldix: 5-yüz-bağlandı — AT-077 ( crypto/signer+hasher), AT-088 (
# telemetry/reporter+server/app+to_signable_dict+iki-kanal-paritesi), AT-097 (
# server/app.py-HTTP-endpoint'leri), AT-114 ( core/circuit_breaker), AT-118 (
# crypto/hasher-2). Bu-test-KALAN-modülleri-tarar:
#   core/engine.py        — YieldixEngine (orchestrator)
#   core/types.py         — dataclass'lar ( AT-088'in-ölçtüğü sha256_digest/
#                           ed25519_signature-alanları-dahil)
#   telemetry/kpi_collector.py — metrik-üretimi (istatistik)
#   cli/main.py           — status/ingest/simulate/report/serve (delegasyon)
#   cylinders/*.py (6)    — receptionist/speed_to_lead/web_qualifier/
#                           crm_reactivation/cold_email_l2/inbox_triage
#
# SONUÇ: **İNDETERMİNE** — kalan-modüllerin-hiçbiri-kripto-kanıt-üretmez
# ( imza/hash/doğrulama-yok); hepsi-iş-mantığıdır ( orchestrator, istatistik,
# e-posta-kuyruğu, CRM-reaktivasyon, intent-yönlendirme, BANT-heuristiği).
# RFC-010'a-bağlanacak-yeni-kanıt-yüzü-YOKTUR — yeşil-boya-YOK: boş-bir-yüzü
# bağlamak-imza-üretmeden-İMKANSIZDIR ( RFC-010'ın-5.-kontrolü-gerçek-özüt-
# ister). Bu-test-olumsuz-sonucu-6/6-ölçülebilir-kanıtla-belgeler ( AT-083-
# negatif-sonuç-disiplini).
#
# Altı-ölçülebilir-kanıt:
#   1) kapsam-çıkartma: 5-bağlı-AT'nin-modülleri + kalan-modüllerin-listesi
#   2) engine: gerçek-orchestrator-çalışır-AMA-kripto-import'u-YOK (kaynak-kanıtı)
#   3) kpi_collector: gerçek-metrik-üretimi-çalışır-AMA-imza/hash-üretmez
#   4) cylinders: 6-silindirin-yöntem-yüzü-iş-mantığı (kanıt-üretmez)
#   5) cli: report→reporter'a/serve→server'a-delegasyon ( AT-088/097'de-ölçüldü)
#   6) özüt-üretme-denemesi: kalan-modüllerden-özüt-ÜRETİLEMEZ → İNDETERMİNE
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/YIELDIX-5/$(date +%F)/at129.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-129: Yieldix beşinci-yüz — kalan-modüllerin-dürüst-taraması (İNDETERMİNE-ölçümü)"

YX="/home/gokun/projects/01_unicorn/99-Yieldix/src"
if [ ! -d "$YX/yieldix" ]; then
  note "[SKIP] AT-129: Yieldix-kodu-bu-makinede-değil (CI) —"
  note "       tarama-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$YX" <<'PYEOF' >> "$LOG" 2>&1
import ast, sys
sys.path.insert(0, sys.argv[1])

# --- 1) KAPSAM-ÇIKARTMA: 5-bağlı-AT + kalan-modüller
BAGLI = {  # AT → modül
    "AT-077": {"crypto/signer.py", "crypto/hasher.py"},
    "AT-088": {"telemetry/reporter.py", "telemetry/kpi_collector.py",
               "server/app.py", "crypto/signer.py", "crypto/hasher.py"},
    "AT-097": {"server/app.py"},
    "AT-114": {"core/circuit_breaker.py", "crypto/hasher.py"},
    "AT-118": {"crypto/hasher.py", "core/circuit_breaker.py"},
}
KALAN = {
    # not: core/-bir-namespace-package'dir ( __init__.py-YOK) — gerçek-dosya
    # listesi-çokludur; eksik-dosya-taramayı-kesmesin-diye-var-olanlar-listelendi
    "core/types.py", "core/engine.py",
    "cylinders/receptionist.py", "cylinders/speed_to_lead.py",
    "cylinders/web_qualifier.py", "cylinders/crm_reactivation.py",
    "cylinders/cold_email_l2.py", "cylinders/inbox_triage.py",
    "cli/main.py", "server/__init__.py", "__init__.py",
}
bagli_moduller = set()
for mod in BAGLI.values():
    bagli_moduller |= mod
# kalan-liste-bağlı-listede-değil
for m in KALAN:
    assert m not in bagli_moduller, f"kalan-Modül-zaten-bağlı: {m}"
print(f"  kapsam: 5-AT → {len(bagli_moduller)}-bağlı-modül; "
      f"kalan-tarama: {len(KALAN)}-modül (ayrık)")

# --- 2) ENGINE: gerçek-orchestrator-çalışır-AMA-kripto-YOK
from yieldix.core.engine import YieldixEngine
from yieldix.core.types import PipelineConfig
eng = YieldixEngine(PipelineConfig(tenant_id="tamga"))
assert eng.config.tenant_id == "tamga"
kaynak = open(sys.argv[1] + "/yieldix/core/engine.py", encoding="utf-8").read()
tree = ast.parse(kaynak)
kripto_import = [n.module for n in ast.walk(tree)
                 if isinstance(n, ast.ImportFrom) and n.module
                 and any(t in n.module for t in ("crypto", "hasher", "signer"))]
assert not kripto_import, f"engine-kripto-import-bulundu: {kripto_import}"
print("  YieldixEngine: orchestrator-gerçek-çalışır (tenant=tamga); "
      "crypto/signer/hasher-import'u-YOK (kaynak-kanıtı)")

# --- 3) KPI_COLLECTOR: gerçek-metrik-üretimi-çalışır-AMA-kanıt-üretmez
kc = eng.kpi_collector
kc.record_lead_processed("lead-1", 32.5, is_sql=True, cost_try=__import__(
    "decimal").Decimal("15.00"))
m = kc.compute_summary_metrics()
assert m["total_leads"] == 1.0, "metrik-üretimi-bozuk"
assert "sha256_digest" not in m and "signature" not in m, \
    "kpi-metriklerinde-özüt/imza-var (beklenmeyen-kanıt-yüzü!)"
# types'taki-özüt-alanları-AT-088'in-reporter-payload'ına-ait
# ( MonthlyReportPayload-pydantic-BaseModel'dir: __dataclass_fields__.yerine
#   pydantic-v2-model_fields-kullanılır)
from yieldix.core.types import MonthlyReportPayload
alanlar = set(MonthlyReportPayload.model_fields.keys())
assert "sha256_digest" in alanlar and "ed25519_signature" in alanlar
print(f"  KPICollector: metrik-gerçek ( total_leads=1); özüt/imza-ÜRETMEZ — "
      f"types'taki-alanlar-AT-088'in-payload'ına-ait ({len(alanlar)}-alan)")

# --- 4) CYLINDERS: 6-silindirin-yüzü-iş-mantığı (kanıt-üretmez)
from yieldix.core.types import BANTScore, InboundLeadPayload, LeadSource
from yieldix.cylinders.cold_email_l2 import ColdEmailL2Manager
from yieldix.cylinders.web_qualifier import WebQualifier
from yieldix.cylinders.inbox_triage import InboxTriageRouter
l2 = ColdEmailL2Manager(tenant_id="tamga")
wq = WebQualifier(tenant_id="tamga")
tr = InboxTriageRouter(tenant_id="tamga")
# gerçek-çalışırlar-AMA-çıktıları-iş-kararıdır (kanıt-değil)
dd = l2.verify_domain_deliverability("tamga.org")
assert isinstance(dd, dict) and all(isinstance(v, bool) for v in dd.values()), \
    "deliverability-bulgu-dönmeli"
lead = InboundLeadPayload(
    tenant_id="tamga", lead_id="lead-bant", contact_name="Test Ajan",
    contact_phone="+905555555555", contact_email="a@b.com",
    source=LeadSource.WEB_FORM, intent_summary="Kurumsal teklif",
    company_name="Tamga A.Ş.",
)
bant = wq.evaluate_initial_bant(lead, budget_answer="100k kurumsal",
                                authority_answer="kurucu",
                                need_answer="acil ihtiyaç",
                                timeline_answer="bu çeyrek")
assert isinstance(bant, BANTScore), "BANT-score-dönmeli (gerçek-imza)"
assert 0.0 <= bant.total_score <= 100.0, "BANT-toplamı-aralık-dışı"
rot = tr.classify_and_route("Teklif", "Merhaba, fiyat?", "a@b.com")
assert isinstance(rot, dict), "yönlendirme-dönmeli"
for ad, mod in (("cold_email_l2", "cylinders/cold_email_l2.py"),
                ("web_qualifier", "cylinders/web_qualifier.py"),
                ("inbox_triage", "cylinders/inbox_triage.py")):
    src = open(sys.argv[1] + "/yieldix/" + mod, encoding="utf-8").read()
    assert "sign(" not in src and "verify_detached" not in src and \
           "sha256_digest_hex" not in src, f"{ad}-kripto-üretim-yolu-var!"
print("  cylinders: 3-örnek-gerçek-çalışır ( deliverability/BANT/route); "
      "6-silindirin-hiçbiri-imza/özüt-üretmez (kaynak-kanıtı)")

# --- 5) CLI: report→reporter/serve→server-delegasyon ( zaten-ölçüldü)
cli_src = open(sys.argv[1] + "/yieldix/cli/main.py", encoding="utf-8").read()
assert "MonthlyReportGenerator" in cli_src and "create_server" in cli_src
assert "sign_detached" not in cli_src and "sha256_digest_hex" not in cli_src
print("  cli/main.py: report→MonthlyReportGenerator (AT-088), "
      "serve→create_server (AT-097) — kendi-kripto-yüzü-YOK (delegasyon)")

# --- 6) ÖZÜT-ÜRETME-DENEMESİ: kalan-modüllerden-kanıt-ÜRETİLEMEZ
# RFC-010'ın-5.-kontrolü-gerçek-evidenceHash-ister. İş-mantığı-modülleri
# deterministik-bir-özüt-üretebilir-AMA-o-özüt-gerçek-bir-KANIT-DEĞİLDİR
# ( tahrize-dayanıklı-imza-üreticisi-yok). Bu- yüzden-dikiş-İMKANSIZDIR.
import hashlib
ozut_is = hashlib.sha256(str(m).encode()).hexdigest()  # sahte-özüt
assert len(ozut_is) == 64
# AMA bu-özütü-üreten-herhangi-bir-gerçek-imzalama-yolu-kalan-modüllerde-YOK:
# (bu-kanıt-bütünlüğü-değil-rastgele-hash'tir — RFC-010-kabul-etmez)
# Filtre-somut-kripto-üretim-adları-arar: verify_domain_deliverability-gibi
# adlar-e-posta-iş-mantığıdır ( kripto-kanıt-DEĞİL) — dışlanırlar.
KRIPTO_URET = ("sign", "digest", "attest", "proof", "verify_signature",
               "verify_report", "verify_detached", "verify_signed")
for mod in sorted(KALAN):
    src = open(sys.argv[1] + "/yieldix/" + mod, encoding="utf-8").read()
    t = ast.parse(src)
    uret = [n.name for n in ast.walk(t)
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
            and any(k in n.name.lower() for k in KRIPTO_URET)]
    assert not uret, f"{mod}-kanıt-üretim-yöntemi-bulundu: {uret}"
print(f"  özüt-denemesi: iş-metriklerinin-hash'i-64hex-AMA-gerçek-kanıt-DEĞİL; "
      f"{len(KALAN)}-kalan-modülün-hiçbirinde-kripto-üretim-yöntemi-YOK "
      "( sign/digest/attest/proof/verify-signature) → dikiş-İMKANSIZ")
print("  DÜRÜST-SONUÇ: İNDETERMİNE — beşinci-yüz-olarak-bağlanacak-gerçek-"
      "kripto-kanıtı-YOK ( yeşil-boya-YAPILMAZ)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Yieldix-tarama-kanıtı-İNDETERMİNE" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-129: Yieldix beşinci-yüz — İNDETERMİNE (kripto-yüz-kalmadı)"
[[ $FAIL -eq 0 ]]
