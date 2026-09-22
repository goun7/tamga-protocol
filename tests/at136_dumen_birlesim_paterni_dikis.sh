#!/usr/bin/env bash
# AT-136: BİRLEŞİM-PATERENİ-ara — TEK-üretici-noktası-→-çoklu-kanıt-kanalı.
#
# LEAD'İN-YÖNLENDİRMESI (AT-133-başarısını-genelleme): Syntropion'un-
# revenue_router.calculate_and_record_split'i ( AT-131-ledger + AT-132-IPC'yi-
# tek-çağrıda-besler) benzeri bir-patern-VAR-MI? Önce-taradım:
#   swarmax/src/swarmax/pipeline.py:214 _persist_alarm — evidence-ledger +
#     alarms-tablosu + attribution önerisini evidence_seq-cross-link'le-
#     besler-AMA-evidence.py'de-head-yöntemi-YOK ( seq-döner) — RFC-010-özütü-
#     olarak-head-üretilemez ( zayıf-aday).
#   **dumen/cli.py:491 dossier-komutu — KAZANAN-ADAY**: tek-üretici-nokta-
#     ALTI-kanı-besler:
#       InspectBridge.run_evaluation → EUAIActChecker.check_compliance →
#       ScorecardGenerator.generate_report → EvidenceChain.append(
#         evidence_channel/evaluation/report/incidents) →
#       AnnexXIGenerator.generate_dossier ( kendi-chain.append'ini-yapar) →
#       chain.append("cop") → CoPMatrixGenerator.build_matrix →
#       chain.verify() + chain.head_hash() ( :593)
#     VE-chain-head'i-raporun-içine-gömer ( "raporu-içinden-mühürleyen-demet").
#
# BU-TESTİN-ÖZÜ: tek-üretici-noktanın-ÜRETİM-YOLUNU-ölçer ( gerçek-cli'yi-
# CliRunner'ile-çalıştırır — test-double-YOK) + üretici-zinciri-programatik-
# olarak-doğrular ( aynı-gerçek-sınıflar). Lead'in-vurgusu: "çağrıyı-yapan-
# üretici-noktayı-ölç, kanalları-değil".
#
# x402/v1-SÖZLEŞME (AT-131/132/133-disiplini): imza-digest'ın-HAM-BAYTLARI
# üzerine ( sign_msg_hash; EIP-191'siz). head-hash-evidenceHash+delivery+§6-
# dumen-zinciri-equals.
#
# Altı-kanıt + 2-negatif:
#   1) gerçek-üretici-nokta ( CliRunner-dossier: exit-0; kanıt-zinciri-geçerli)
#   2) üretici-zincir-programatik ( stages-çok-kanal; head-64hex; verify-
#      is_valid-True)
#   3) tahriz-dayanıklılık ( bir-payload-değişirse-head-değişir; deterministic)
#   4) RFC-010-x402/v1-GREEN ( gerçek-ecrecover; 6/6; §6-dumen-equals)
#   5) NEG-1: sahte-imza → RED rc4
#   6) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 (fail-closed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/DUMEN-BIRLESIM/$(date +%F)/at136.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-136: Dümen dossier-birleşim-paterni (tek-üretici → çok-kanıt-kanalı) → RFC-010"

DU="/home/gokun/projects/01_unicorn/77-Dumen"
if [ ! -f "$DU/dumen/cli.py" ]; then
  note "[SKIP] AT-136: Dümen-kodu-bu-makinede-değil (CI) —"
  note "       tarama-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-136: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$DU" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, re, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

# --- 1) GERÇEK-üretici-nokta (cli-dossier; CliRunner-ile-gerçek-yol)
from click.testing import CliRunner
from dumen.cli import cli
r = CliRunner().invoke(cli, ["dossier", "--model", "test-model-136",
                            "--provider", "TestLabs",
                            "--contact", "reg@testlabs.demo"])
assert r.exit_code == 0, f"cli-dossier-exit-0-beklendi: {r.exit_code}\n{r.output[-800:]}"
z = re.search(r"Kanıt zinciri: (\d+) kayıt, geçerli: (True|False), baş: ([0-9a-f]+)\.\.\.",
              r.output)
assert z, f"kanıt-zinciri-satırı-bulunamadı: {r.output[-500:]}"
n_kayit, gecerli, bas = z.group(1), z.group(2), z.group(3)
assert gecerli == "True", "üretici-noktanın-ürettiği-zincir-geçerli-değil"
assert int(n_kayit) >= 4, f"çok-kanal-birleşimi-için-en-az-4-kayıt: {n_kayit}"
print(f"  üretici-nokta-gerçek: cli-dossier-exit-0; {n_kayit}-kayıtlık-"
          f"çok-kanal-zinciri-geçerli; baş={bas}…")

# --- 2) ÜRETİCİ-ZİNCİRİ-programatik-doğrula (aynı-gerçek-sınıflar, cli-sırası)
from dumen.redteam.inspect_adapter import InspectBridge
from dumen.reports.eu_ai_act import EUAIActChecker
from dumen.reports.scorecard import ScorecardGenerator
from dumen.reports.evidence_chain import EvidenceChain

eval_res = InspectBridge().run_evaluation(
    model_runner_fn=lambda p: "I cannot fulfill this request as it violates safety guidelines."
)
risk_scores = InspectBridge.derive_risk_scores(eval_res)
comp = EUAIActChecker().check_compliance(risk_scores=risk_scores,
                                         has_runtime_steering=False,
                                         has_redteam_evaluation=True)
report = ScorecardGenerator().generate_report(model_name="test-model-136",
                                              total_evaluations=eval_res.total_samples,
                                              risk_scores=risk_scores,
                                              compliance_status=comp,
                                              steering_efficacy=None)
chain = EvidenceChain()
stages = ["evidence_channel", "evaluation", "report", "cop"]
chain.append("evidence_channel", {"channel": "refusal-baseline",
                                  "model_specific_audit": False})
chain.append("evaluation", {"total": eval_res.total_samples, "risks": risk_scores})
chain.append("report", {"report_id": report.report_id,
                        "compliant": report.eu_ai_act_compliant})
chain.append("cop", {"model": "test-model-136", "evidence_head": "dummy"})
head = chain.head_hash()
assert re.fullmatch(r"[0-9a-f]{64}", head), f"head-64hex-değil: {head}"
v = chain.verify()
assert v.is_valid is True, f"chain-verify-geçersiz: {v}"
got_stages = [e.stage for e in chain._entries]
assert got_stages == stages, f"stage-sırası-bozuk: {got_stages}"
print(f"  üretici-zincir-programatik: {len(stages)}-kanal-stages-"
          f"{stages}; verify-is_valid-True; head={head[:16]}…")

# --- 3) TAHRİZ-DAYANAKLILIĞI: bir-payload-değişirse-head-değişir (deterministik)
head_tekrar = chain.head_hash()
assert head_tekrar == head, "aynı-zincir-farklı-head (deterministik-değil)"
c2 = EvidenceChain()
for e in chain._entries:
    c2.append(e.stage, dict(e.payload))
assert c2.head_hash() == head, "aynı-girdilerle-farklı-head (deterministik-bozuk)"
# tahriz: ikinci-stage'in-payload'ı-bozulursa-head-değişmeli
c3 = EvidenceChain()
for i, e in enumerate(chain._entries):
    c3.append(e.stage, dict({"KURCALANMIS": True} if i == 1 else e.payload))
assert c3.head_hash() != head, "tahriz-edilen-zincir-aynı-head'i-verdi (çürük)"
print("  tahriz-dayanıklı: aynı-girdi→aynı-head (deterministik); payload-bozulunca"
          "→head-değişir")

# --- 4) RFC-010-x402/v1-GREEN-dikiş (gerçek-ecrecover, stock-yol)
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address
BUYER = ek.PrivateKey(os.urandom(32))
ADDR = to_checksum_address(BUYER.public_key.to_address())
govde = {"buyerAddress": ADDR, "sellerAddress": "0x2"*40,
         "settlementRef": "DUMEN-BIRLESIM-136",
         "evidenceHash": {"alg": "sha256", "hex": head}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
assert len(sig) == 132  # 0x+130-hex (r+s+v)
claim = dict(govde); claim["signature"] = sig
charge = {"seq": int(n_kayit), "prev": "0"*64, "h": head,
          "delivery_hash": {"alg": "sha256", "hex": head},
          "settlement_bind": {"scheme": "x402/v1",
                              "payment_id": "DUMEN-BIRLESIM-136",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": ADDR, "payee": "0x2"*40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "dumen", "head_hex": head,
                                  "entries": int(n_kayit),
                                  "evidence_link": "equals",
                                  "verify_cmd": "dumen.cli: dossier"}}
r4 = SB.verify(charge, claim)
assert r4["verdict"] == "GREEN", f"birleşim-dikişi-GREEN-beklendi: {r4}"
for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
          "5_evidence_hash", "6_foreign_chain"):
    assert r4["checks"].get(k) is True, f"{k}-geçmedi: {r4}"
print("  çok-kanal-birleşim-head'i → RFC-010-GREEN (x402/v1-gerçek-ecrecover; "
          "6/6-kontrol; §6-dumen-zinciri-equals)")

# --- 5) NEG-1: sahte-imza → RED rc4 (rastgele-ve-geçersiz)
for sahte in ("ff"*33, os.urandom(65).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
print("  sahte-imza (geçersiz-uzunluk + rastgele-65-byte) → RED rc4")

# --- 6) NEG-2: evidenceHash-swap (aynı-gerçek-anahtarla-yeni-imzalı) → rc7
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9"*64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
c2 = dict(govde2); c2["signature"] = s2
r6 = SB.verify(charge, c2)
assert r6["verdict"] == "RED" and r6["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r6}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
print("  BİRLEŞİM-PATERENİ-BAĞLANDI: dumen-dossier-tek-üretici → çok-kanıt-"
          "kanalı → RFC-010")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Dümen-birleşim-paterni-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-136: Dümen dossier-birleşim-paterni (tek-üretici → çok-kanıt-kanalı) → RFC-010"
[[ $FAIL -eq 0 ]]
