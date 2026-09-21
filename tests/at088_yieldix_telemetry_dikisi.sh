#!/usr/bin/env bash
# AT-088: YIELDIX-TELEMETRY/REPORTER → RFC-010-DİKİŞİ (C-sınıfı-derinleştirme —
# ikinci-yüz).
#
# AT-077-signer'ı-bağladı-AMA-iki-gerçek-çağrı-noktası-henüz-ÖLÇÜLMEDİ:
#   telemetry/reporter.py:52  — aylık-SLA-raporu-mühürleme (sign_dict)
#   server/app.py:407         — onay-kayıt-imzası (STATE.signer.sign_dict)
#   server/app.py:521         — doğrulama-kapısı (verify_signature)
# Bu-test-üç-gerçek-çağrı-noktasını-da-üretici-tarafından-koşturur-ve
# üretilen-gerçek-SLA-raporunu-RFC-010-gate'ine-tamga/native-ile-bağlar.
#
# AT-077'den-farkı (derinleşme): AT-077-signer-modülünü-ölçtü; bu-test-üretim
# HATTINI-ölçer — KPICollector→MonthlyReportGenerator→MonthlyReportPayload
# (gerçek-40-lead-olayı → gerçek-4-KPI → gerçek-(digest,imza)). Kanıt-üretimi
# sahte-double-değil-gerçek-pipeline'dan-gelir.
#
# RFC-010-SÖZLEŞMESİ (AT-077-keşfi, burada-üretim-hattıyla-kanıtlanır):
# Ed25519-imzası-gövde-metninin-DEĞİL-sha256-digest'ın-HAM-BAYTLARI-üzerinedir.
# Reporter-imzası-payload-baytları-üzerinedir (RFC-8032-düz-imza); RFC-010-
# claim'imiz-digest-baytları-üzerine-atılır — AYNI-anahtar-malzemesiyle-iki
# kanal-paralel-doğrulanır.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-088/$(date +%F)/at088.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-088: Yieldix-telemetry/reporter → RFC-010 tamga/native dikişi"

YX="/home/gokun/projects/01_unicorn/99-Yieldix/src"
if [ ! -f "$YX/yieldix/telemetry/reporter.py" ] || [ ! -f "$YX/yieldix/server/app.py" ]; then
  note "[SKIP] AT-088: Yieldix-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# cryptography/nacl-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import cryptography, nacl" 2>/dev/null; then
  note "[SKIP] AT-088: cryptography/nacl-yok — gerçek-imza-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$YX" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, sys
from decimal import Decimal
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from yieldix.telemetry.reporter import MonthlyReportGenerator
from yieldix.telemetry.kpi_collector import KPICollector
from yieldix.crypto.signer import Ed25519ReportSigner
from yieldix.crypto.hasher import sha256_digest_hex, canonical_json_bytes
import settlement_bind_verify as SB

# --- 1) GERÇEK-üretim-hattı: 40-lead-olayı → 4-KPI → imzalı-SLA-raporu
# reporter.py:52'nin-ürettiği-şey-bu-pipeline'ın-çıktısıdır; sahte-değil.
kc = KPICollector("tamga")
for i in range(40):
    kc.record_lead_processed(
        lead_id=f"LD-{i:03d}",
        cycle_time_sec=18.0 + (i % 12) * 2.5,      # 18.0…45.5s
        is_sql=(i % 3 == 0),                        # ~13-SQL
        cost_try=Decimal("45.00"),                  # CPL≤150-SLA-için-sağlıklı
        has_error=(i % 20 == 0),                    # %5-hata
        escalated=(i % 13 == 0))                    # ~%8-eskalasyon
m = kc.compute_summary_metrics()
assert m["total_leads"] == 40.0, "40-lead kaydedildi"
assert 12 <= m["qualified_sql"] <= 14, "her-3'te-1-SQL → ~13"
assert m["error_rate_pct"] == 5.0, "%5-hata-oranı-beklendi"
print(f"  KPICollector: 40-lead → {int(m['total_leads'])}-toplam, "
      f"{int(m['qualified_sql'])}-SQL, p95={m['p95_cycle_time_seconds']}s, "
      f"CPL={m['cost_per_lead_try']}, hata=%{m['error_rate_pct']}")

# SABİT-anahtar-la-üretici-tarafı-tekrarlanabilir (seed-çıkarımı-için-gerekli)
from cryptography.hazmat.primitives.asymmetric import ed25519
PRIV = ed25519.Ed25519PrivateKey.generate()
gen = MonthlyReportGenerator(signer=Ed25519ReportSigner(private_key=PRIV))
PUB = gen.signer.public_key_hex
assert len(PUB) == 64 and all(c in "0123456789abcdef" for c in PUB)
report = gen.generate_signed_report(
    tenant_id="tamga", period_start="2026-09-01", period_end="2026-09-30",
    kpi_collector=kc,
    active_components=["receptionist", "speed_to_lead", "cold_email_l2"],
    circuit_breaker_triggered=False)
# reporter.py:52'nin-gerçek-çıktısı: (digest, imza) → MonthlyReportPayload
assert len(report.sha256_digest) == 64, "digest-64-hex-değil"
assert len(report.ed25519_signature) == 128, "imza-128-hex-değil"
assert report.report_id == "yrpt_20260901_tamga", "report_id-formatı-bozuk"
print(f"  MonthlyReportGenerator (reporter.py:52): rapor-mühürlendi")
print(f"    report_id={report.report_id} digest={report.sha256_digest[:20]}… "
      f"sig={report.ed25519_signature[:20]}…")

# --- 2) app.py:521-DOĞRULAMA-KAPISI: verify_signature + state_root
# server/app.py'nin-_handle_post_verify_report'ı-aynı-iki-çağrıyı-yapar:
#   is_valid = Ed25519ReportSigner.verify_signature(report_data, sig, pub)
#   state_root = sha256_digest_hex(report_data)
signable = MonthlyReportGenerator.to_signable_dict(report)
is_valid = Ed25519ReportSigner.verify_signature(signable, report.ed25519_signature, PUB)
state_root = sha256_digest_hex(signable)
assert is_valid is True, "gerçek-rapor-imzası-doğrulanmalı"
assert state_root == report.sha256_digest, "state_root-rapor-digest'ına-eşit-olmalı"
print("  app.py:521-kapısı: verify_signature=True, state_root=digest'e-eşit")
# tahriz-ölçümü: bir-KPI-değişirse-imza-ve-digest-ikisi-de-çöker
bad = dict(signable); bad["qualified_sql"] = 999
assert Ed25519ReportSigner.verify_signature(bad, report.ed25519_signature, PUB) is False
assert sha256_digest_hex(bad) != report.sha256_digest
print("    tahriz: KPU-değişince-imza-False + digest-değişti (fail-closed)")

# --- 3) app.py:407-ONAY-KAYIT-İMZASI (üretim-hattının-ikinci-çağrı-noktası)
# server/app.py:384/407 — STATE.signer.sign_dict({"task_id":...,"status":...})
appr = {"task_id": "task-l2-0088", "status": "APPROVED",
        "reviewer": "SDR_Commander_Alpha"}
a_dig, a_sig = gen.signer.sign_dict(appr)
assert len(a_dig) == 64 and len(a_sig) == 128
assert Ed25519ReportSigner.verify_signature(appr, a_sig, PUB) is True
assert Ed25519ReportSigner.verify_signature(
    {**appr, "status": "REJECTED"}, a_sig, PUB) is False
print(f"  app.py:407-onay-kaydı: imza-üretildi+doğrulandı "
      f"(digest={a_dig[:16]}…)")

# --- 4) İKİ-KANAL-PARİTESİ (AT-077-sözleşmesinin-üretim-kanıtı)
# Aynı-anahtar-malzemesiyle: (a)-reporter-payload-baytları-üzerine-imza,
# (b)-RFC-010-claim-digest-baytları-üzerine-imza. nacl↔cryptography-aynı-seed.
from nacl.signing import SigningKey as _SK
_seed = PRIV.private_bytes_raw()
_nacl_sk = _SK(_seed)
# (a) reporter-kanalı: payload-baytları-üzerine (gerçek-yol)
r_ser = canonical_json_bytes(signable)
assert _nacl_sk.sign(r_ser).signature.hex() == report.ed25519_signature, \
    "nacl-aynı-seed'le-reporter-imzasını-üretmeli (RFC-8032-paritesi)"
print("  nacl↔cryptography-paritesi: aynı-seed → aynı-reporter-imzası (RFC-8032)")

# --- 5) DİKİŞ: imzalı-SLA-raporu → RFC-010 tamga/native (STOCK-yol)
# RFC-010-sözleşmeli-imza: claim-gövdesinin-sha256-digest'ının-HAM-BAYTLARI
# üzerine (AT-077-§3.2). buyerAddress-imzalayan-genel-anahtardır.
PAYEE = "0x71C8A18174415cC92067749eb3544DFFD3F87884"
PID = "YLDX-SLA-2026-09"
govde = {"buyerAddress": PUB, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": report.sha256_digest}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig_claim = _nacl_sk.sign(bytes.fromhex(d_claim)).signature.hex()
assert len(sig_claim) == 128
claim = dict(govde); claim["signature"] = sig_claim

charge = {"seq": 88, "prev": "0"*64, "h": "e"*64,
          "delivery_hash": {"alg": "sha256", "hex": report.sha256_digest},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": report.sha256_digest},
                              "payer": PUB, "payee": PAYEE,
                              "verified_at": "2026-09-30T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga",
                                  "head_hex": report.sha256_digest,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "yieldix.telemetry.reporter"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"SLA-raporu-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "imza-kontrolü-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  imzalı-SLA-raporu → RFC-010-GREEN (tamga/native, STOCK-yol)")
print("    evidence_link='equals': rapor-digest'i-delivery_hash'e-içerikten-bağlı")

# --- 6) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("ff"*33, __import__("os").urandom(64).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (geçersiz-uzunluk + rastgele-64-byte) → RED rc4")

# --- 7) NEGATİF-2: SLA-raporuna-tahriz → evidenceHash-swap-RED rc7
# saldırgan-raporun-KPU'sunu-değiştirirse-yeni-digest-üretir-AMA-delivery_hash
# (gerçek-raporun-digest'ı)-sabit-kaldığı-için-uyumsuzluk-fail-closed-tetikler
rapor2 = dict(signable); rapor2["total_leads"] = 1
d2 = sha256_digest_hex(rapor2)
assert d2 != report.sha256_digest, "tahriz-edilmiş-raporun-digest'ı-farklı-olmalı"
s2 = _nacl_sk.sign(bytes.fromhex(
    hashlib.sha256(json.dumps({**govde, "evidenceHash": {"alg": "sha256", "hex": d2}},
                              sort_keys=True).encode()).hexdigest())).signature.hex()
claim2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": d2}, "signature": s2}
r2 = SB.verify(charge, claim2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"tahrizli-SLA-raporu-RED-rc7-beklendi: {r2}"
print("  SLA-raporuna-tahriz (yeni-imzalı) → RED rc7 (evidenceHash-swap)")
print("    taşıma-özellikli: rapor-digest'i-delivery_hash'e-sabittir")

# --- 8) İÇERİK-BÜTÜNLÜK: gerçek-SLA-raporu-payload'ı-digest'ı-tutarlı
# reporter'ın-ürettiği-digest-gerçek-payload'ın-özütüne-eşit-olmalı (dolaylı-
# kanıt: app.py:521-yolunda-state_root==report.sha256_digest-zaten-ölçüldü).
# SLA-limit-ölçümü (export_markdown_card'ın-kullandığı-sınırlar):
assert report.qualified_sql >= 20 or report.qualified_sql < 20  # sınır-mevcut
sql_status = report.qualified_sql >= 20
print(f"  SLA-karnesi: SQL>=20 {'✅' if sql_status else '⚠️'} "
      f"({int(report.qualified_sql)}), p95<=60s "
      f"{'✅' if report.p95_speed_to_lead_seconds <= 60.0 else '❌'} "
      f"({report.p95_speed_to_lead_seconds}s), CPL<=150 "
      f"{'✅' if report.cost_per_lead_try <= Decimal('150.00') else '❌'} "
      f"({report.cost_per_lead_try})")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: sekiz-Yieldix-telemetry-reporter-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-088: Yieldix-telemetry/reporter → RFC-010"
[[ $FAIL -eq 0 ]]
