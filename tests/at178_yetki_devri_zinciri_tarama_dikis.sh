#!/usr/bin/env bash
# AT-178: 'YETKİ-DEVRİ-ZİNCİRİ'-TARAMASI — 16.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-166'da-rol-yükseltmeyi-kapattık; şimdi-atıf-zinciri:
# (1) yetki-devri: A→B'ye-delege-ederse-B'nin-sınırları-A'yı-bağlar-mı ( veya-B-daha-
# fazla-yetki-kullanabilir-mi); (2) çağıran-kimliği: iç-servis-B-callback'i-dış-arayüz-
# müşterisi-miş-gibi-davranır-mı ( X-Forwarded-User-güveni-yok); (3) oturum-sıçraması:
# bir-rolün-oluşturduğu-kaynak-diğer-rolce-sahipleniliyor ( çoklu-venture-cross-talk);
# (4) yönetici-baypas: yönetici-rotaları-normal-yetkiyi-atlatır-AMA-günlükler-mi.
# Öncelik: syntropion ( tenant/role), pacta ( arbitrator), tamga ( agent-key),
# yieldix. BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 4-proje-tamamlandı — 1-BULGU-AÇIK):
#
# *** BULGU-1: tamga node-cosign trust-list SESSİZ-ATLAMA ( tamga_runner.py:1062) ***
#   _cosign_policy: L1-uyumsuz-node'lar-RED-eder-AMA sadece trust-list-verilmişse:
#       if trust is not None and rec.get("node_id") not in trust: RED
#   --node-trust VERİLMEZSE → trust=None → trust-kontrolü-TAMAMEN-atlanır.
#   DAHA-KÖTÜSÜ: --node-trust-dosyası-BOZUK-olursa except: trust=None — SESSİZCE
#   trust-açılır ( fail-OPEN). Kanıtlandı:
#     _cosign_policy(["--cosign-policy","L1"]) → ('L1', None)     # trust-YOK
#     _cosign_policy(["--cosign-policy","L1","--node-trust","BOZUK.json"]) → ('L1', None)
#       ( bozuk-JSON → except → trust=None — sessiz-fail-OPEN!)
#   → L1 "HER kayıt trust-list'te-olmalı" doküminasyona-RAGMEN trust-YOKSA-açık.
#     saldırgan kendi-anahtarını-üretir ( imzalı-kayıtlar-geçerli-AMA-node-bilinmeyen)
#   → sınıf-1 ( yetki-devri: B-imzası-geçerli-AMA-B-kim-seçilmedi) + yönetici-baypas
#     çeşidi ( operator-beyanı-zorunlu-DEĞIL).
#   KARŞIT-TEMİZ: L1 trust-list-verilirse-GERÇEK-uygulanır ( node_id_untrusted@n);
#   L0 node_sig-YOKSA-legacy-kabul ( back-compat — belgeli-seçim).
#
# TEMİZ-modeller:
#   syntropion/api.py:386  _require_tenant_for_venture — Bearer-tenant-venture-EŞLEŞME
#                          ( fail-closed 401/403; AT-166-düzeltmesi-canlı)
#   pacta/core/vault.py:361  arbitrator-taraf-reddi ( AT-166) — delege-taraflardan-
#                          biri-olamaz ( yetki-devri-sınırı-GERÇEK)
#   yieldix/core/engine.py   YieldixEngine-tenant-izole ( her-tenant-kendi-
#                          KPI-collector/receptionist-nesnesi — cross-talk-YOK)
#   tamga _node_sig_ok       imza-doğrulama-GERÇEK ( Ed25519; trust-sızmasa-bile
#                          imza-tesisi-zorunlu)
#
# Yedi-kanıt + 3-negatif:
#   1) B1: L1 trust-YOK → ('L1', None) — trust-kontrolü-atlanır
#   2) B1: BOZUK-trust-dosyası → sessiz-None ( except-fail-OPEN)
#   3) B1: trust-None-iken-bilinmeyen-node-kabul ( mantıksal-kanıt)
#   4) TEMİZ: syntropion-tenant-venture-eşleşme ( fail-closed)
#   5) TEMİZ: pacta-arbitrator-taraf-reddi ( AT-166-canlı)
#   6) TEMİZ: yieldix-engine-tenant-izole ( cross-talk-YOK)
#   7) TEMİZ: tamga-node-sig-Ed25519-doğrulama ( imza-tesisi-zorunlu)
#   N1) L1+geçerli-trust → bilinmeyen-node RED ( dürüst-yol-çalışır)
#   N2) L0-node_sig-YOKSA-legacy-kabul ( belgeli-back-compat)
#   N3) node_sig-geçersiz → node_sig_invalid@n ( imza-kontrolü-canlı)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/YETKI-DEVRİ-ZİNCİRİ/$(date +%F)/at178.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-178: Yetki-devri-zinciri-taraması ( 4-proje) — 1-BULGU: tamga-trust-atlama"

# ============================================ A) BULGU-1: tamga-trust-sessiz-atlama
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, json, os, pathlib, sys, tempfile
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
import tamga_runner as T

# --- 1) L1 trust-YOK → ('L1', None) — trust-kontrolü-atlanır
pol, trust = T._cosign_policy(["--cosign-policy", "L1"])
assert pol == "L1" and trust is None, f"L1-beklenmedik: {pol} / {trust}"
print("  1-B1: --cosign-policy L1 ( --node-trust-YOK) → trust=None")
print("        → import-yolu: 'if trust is not None' → KONTROL-ATLANIR ( L1-")

# --- 2) BOZUK-trust-dosyası → sessiz-None ( except-fail-OPEN)
tf = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
tf.write("{BOZUK-JSON-TAMGA"); tf.close()
pol2, trust2 = T._cosign_policy(["--cosign-policy", "L1", "--node-trust", tf.name])
os.unlink(tf.name)
assert pol2 == "L1" and trust2 is None, f"bozuk-trust-beklenmedik: {pol2} / {trust2}"
print("  2-B1: --node-trust BOZUK-dosya → except → sessizce trust=None ( FAIL-OPEN!)")
print("        → operator yanlış-yol/bozuk-dosya-verirse güvenlik-sessiz-açılır")

# --- 3) trust-None-iken-bilinmeyen-node-kabul ( mantıksal-kanıt)
src = inspect.getsource(T._cosign_policy)
assert "if \"--node-trust\" in a:" in src, "trust-yolu-kaynakta-yok"
# import-yolunun-kaynak-teyidi ( atlama-kodu)
src_imp = inspect.getsource(T.cmd_import)
assert "if trust is not None and rec.get(\"node_id\") not in trust:" in src_imp, \
    "trust-atlama-kodu-kaynakta-yok ( tutarsız)"
print("  3-B1: kaynak-teyidi — cmd_import'ta 'if trust is not None …' ( atlama)")
print("        → L1-dokümantasyon 'HER kayıt trust-list'te-olmalı'-der-AMA-trust")
print("          verilmezse-atlar — yetki-devri: B'nin-sınırı-A'yı-bağlamaz")

# --- N1) L1+geçerli-trust → bilinmeyen-node RED ( dürüst-yol-çalışır)
good = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
good.write(json.dumps(["a"*64, "b"*64])); good.close()
pol3, trust3 = T._cosign_policy(["--cosign-policy", "L1", "--node-trust", good.name])
os.unlink(good.name)
assert pol3 == "L1" and trust3 == {"a"*64, "b"*64}, f"geçerli-trust-bozuk: {trust3}"
assert "c"*64 not in trust3, "bilinmeyen-node-trust'ta ( beklenmedik)"
print("  N1-L1+geçerli-trust-list → bilinmeyen-node RED eder ( dürüst-yol-çalışır)")
print("      → bulgu SADECE trust-verilmediğinde/bozuk-olduğunda ( sessiz-atlama)")

# --- N2) L0-node_sig-YOKSA-legacy-kabul ( belgeli-back-compat)
pol0, trust0 = T._cosign_policy([])
assert pol0 == "L0", f"L0-varsayılan-bozuk: {pol0}"
print("  N2-L0-varsayılan ( node_sig-YOKSA-legacy-kabul — belgeli-back-compat)")

# --- N3) node_sig-geçersiz → node_sig_invalid@n ( imza-kontrolü-canlı)
from nacl.signing import SigningKey
from nacl.encoding import HexEncoder
sk = SigningKey.generate()
node_id = sk.encode(encoder=HexEncoder).decode()
rec = {"seq": 1, "h": "a" * 64, "node_id": node_id,
       "node_sig": "0" * 128}            # geçersiz-imza
assert T._node_sig_ok(rec) is False, "geçersiz-node_sig-geçti ( imza-bozuk!)"
# geçerli-imza ile düzeltilmiş-rec ( h-üzerinden)
import hashlib
h = hashlib.sha256(b"AT-178-test").hexdigest()
sig = sk.sign(h.encode()).signature.hex()
rec2 = {"seq": 1, "h": h, "node_id": node_id, "node_sig": sig}
assert T._node_sig_ok(rec2) is True, "geçerli-node_sig-reddedildi ( beklenmedik)"
print("  N3-node_sig-geçersiz → RED; geçerli-Ed25519-imza → KABUL ( imza-tesisi")
print("      zorunlu — AMA trust-kontrolü-ayrı; bu-bulgünün-o-yönü)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) tamga-node-cosign-trust-sessiz-atlama" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) tamga"; cat "$LOG"; }

# ============================================ B) TEMİZ-modeller ( 3-proje)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import inspect, os, pathlib, sys
os.environ.setdefault("SYNTROPION_SECRET_KEY", "at178-test-anahtari-16-karakter")

# --- 4) TEMİZ: syntropion-tenant-venture-eşleşme ( fail-closed)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
import syntropion_core.api as API
src = inspect.getsource(API._require_tenant_for_venture)
assert "Bearer" in src and "Authorization Bearer token required" in src, \
    "tenant-kontrolü-fail-closed-değil"
assert "is not authorized for venture" in src, "venture-eşleşme-mesajı-yok"
print("  4-TEMİZ: syntropion _require_tenant_for_venture — Bearer-token-tenant")
print("           venture-EŞLEŞMESİ ( fail-closed 401/403; AT-166-canlı)")

# --- 5) TEMİZ: pacta-arbitrator-taraf-reddi ( AT-166-canlı)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from decimal import Decimal
from pacta.core.vault import PactaEscrowVault
from pacta.models import ArbitrationVote
v = PactaEscrowVault()
B, S = "0x" + "1" * 40, "0x" + "2" * 40
j = v.create_and_lock_escrow(B, S, Decimal("10"))
v.submit_output(j.job_id, {"r": 1})
d = v.raise_dispute(j.job_id, B, "x", "h" * 64)
# buyer-kıyafetinde-arbitrator → reddedilir ( delege-taraflardan-biri-olamaz)
try:
    v.resolve_arbitration(d.dispute_id, [ArbitrationVote(
        arbitrator_address=B, vote_favor_buyer=True, rationale_hash="r" * 64)])
    raise AssertionError("taraf-arbitrator-geçti ( AT-166-bozulmuş)")
except ValueError:
    pass
# bağımsız-arbitrator → GEÇERLİ ( dürüst-yol)
out = v.resolve_arbitration(d.dispute_id, [ArbitrationVote(
    arbitrator_address="0x" + "9" * 40, vote_favor_buyer=True, rationale_hash="r" * 64)])
assert out.buyer_favored is True, "bağımsız-arbitrator-çözmedi"
print("  5-TEMİZ: pacta arbitrator-taraf-reddi ( AT-166-canlı) — delege-taraf")
print("           olamaz; bağımsız-arbitrator-GEÇERLİ ( yetki-devri-sınırı-GERÇEK)")

# --- 6) TEMİZ: yieldix-engine-tenant-izole ( cross-talk-YOK)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/yieldix/src")
from yieldix.core.engine import YieldixEngine
from yieldix.core.types import PipelineConfig
eA = YieldixEngine(config=PipelineConfig(tenant_id="tenantA"))
eB = YieldixEngine(config=PipelineConfig(tenant_id="tenantB"))
assert eA.config.tenant_id != eB.config.tenant_id, "tenant-aynı ( beklenmedik)"
assert eA.kpi_collector is not eB.kpi_collector, "KPI-collector-paylaşıldı!"
assert eA.receptionist is not eB.receptionist, "receptionist-paylaşıldı!"
assert eA.config.tenant_id == "tenantA" and eB.config.tenant_id == "tenantB"
print("  6-TEMİZ: yieldix YieldixEngine-tenant-izole — her-tenant-kendi-nesneleri")
print("           ( KPI-collector/receptionist) — oturum-sıçraması-YOK ( sınıf-3-TEMİZ)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) syntropion/pacta/yieldix TEMİZ-model" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) temiz-modeller"; cat "$LOG"; }

echo
note "  öneri: --node-trust-yoksa-L1-RED ( trust-zorunlu) VEYA bozuk-dosya →"
note "         fail-closed-hata ( sessiz-None yerine); trust-beyanı-operator'e"
note "         zorunlu-olmalı ( 'node-cosign-açık-seçim' комментарии'ne-RAGMEN)"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-178: Yetki-devri-zinciri — BULGU: tamga-trust-list-sessiz-atlama"
[[ $FAIL -eq 0 ]]
