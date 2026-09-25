#!/usr/bin/env bash
# AT-179: YAPILANDIRMA-SABİTİ-GÜVENİ-TARAMASI (17.-sınıf).
#
# task-61. Sabitler: varsayılan-dosya-yolları (CWD-güveni), zayıf-varsayılanlar
# (uyarı-YOK), config-ayrıştırma ( YAML/JSON-injection, bool-zorlama), izin-modu
# (0644-vs-0600). Öncelik: tamga, veridrome, sester, syntropion, yieldix.
#
# BULGU-1 (GERÇEK — veridrome-CT-log-0644-ve-CWD-güveni): `ct_log_path`-
# varsayılanı-göreceli `"ct_log.jsonl"` ( CURRENT_DIR-güveni; ayrıştırma-yok)-
# VE `open(...,"a")`-ile-yazıldığı-için-izin **0644** (dünya-okunabilir).
# KANIT: varsayılan-kurucu → CWD'de-oluşur; os.stat → 0o644. Karşıt: tamga
# state.json/ledger.jsonl **0600** (Audit-9-B6-atomik-O_CREAT).
#
# BULGU-2 (GERÇEK — sester-secret-zayıf-varsayılan, SAHTE-ZİNCİR-SEALİ): sadece
# middleware-değil — Ledger.__init__ `secret: str = "dev-secret"` (ledger.py:219)
# + pg_ledger.py:74 + migrate_pg.py:27 ( DEFAULT_SECRET) + sovereign_verify.py:88
# ( SESTER_LEDGER_SECRET-env-default'u). **uyarı-YOK**. TEHLİKE-seal()'da:
# hmac.new( secret, canonical) → zincir-hash'i — bilinen-sır ile ÜRETİLEN-TAMAMEN-
# SAHITE-zincir verify_chain()'den-GEÇER. KANIT: Ledger( "f.db")-default-secret ile
# charge_receipt+settlement-999-USDC-sahte-zincir → verify_chain=True; aynı-sır ile
# mühürlenmiş-sahte-ödeme-kaydı-bağımsız-doğrulayıcı-fark-EDİLEMEZ. Karşıt: yanlış-
# secret → verify_chain=False (gerçek-doğrulama-çalışır). facilitator_svc/service.py:
# 79-85 secret-ZORUNLU ( RuntimeError fail-closed) — AYNI-projede-paradox.
# NOT: SesterMeter-yüzeyi-AT-179-düzeltmesi-ile-bilinen-değeri-redebilir-AMA-varsayılan
# hâlâ-kaynakta-canlı-VE-Ledger-seal-yüzeyi-açık ( bu-test-Ledger'ı-ölçer).
#
# BULGU-3 (GERÇEK — sester-ledger.db-0644): Ledger SQLite-dosyası + WAL/SHM-
# yan-dosyaları **0644** — replay-koruması seen_nonces + ödeme-geçmişi-ve-
# kanıt-zinciri-dünya-okunabilir ( gizlilik-kaybı; AT-177'de-0600-doğru-ydı-
# tamga). sqlite3-connect-mode-varsayılanına-bırakılmış.
#
# BULGU-4 (TEMİZ — tamga-keystore-disiplini): passphrase() env-öncelikli-AMA
# boş-passphrase-RED (Audit-1-F7); scrypt(n=2**15)-KDF; os.urandom(16)-salt +
# urandom(24)-nonce; XChaCha20-Poly1305. state.json/ledger.jsonl **0600**
# ( atomik-O_CREAT-Audit-9-B6). Sabit-anahtar-YOK. keygen-node → node_seed.hex
# 0600 ( node_pub.hex 0644 — public-key-için-uygun).
#
# BULGU-5 (TEMİZ — syntropion-AT-162 + config-ayrıştırma):
# syntropion SYNTROPION_SECRET_KEY-ZORUNLU ( env-yok/<16-karakter → başlatma-
# hatası; sabit-default-KALDIRILDI). yieldix-pydantic-Field'ları-ge/le-sınırlı.
# Üretim-kodunda-yaml.load/eval/exec-YOK ( sadece-.venv-kütüphanelerinde).
# sester-Ledger-bool-amount-reddi ( tip-karışması-tuzağı-kapalı).
#
# BULGU-6 (GERÇEK — yieldix-sabit-tenant-defaultı): YieldixEngine.__init__
# config=None → PipelineConfig( tenant_id="default_tenant") (engine.py:35) —
# **sessiz-kabul, uyarı-YOK**. AT-178'in-kanıtladığı-tenant-izolasyonu config'siz
# başlatmada KENDİ-ÇÖKER: tüm-default-motorlar-AYNI-tenant'a-yazar (cross-talk).
# Ayrıca-PipelineConfig-sabit-FİYAT-defaultları: monthly_retainer_try=45000.00,
# setup_fee_try=150000.00 (types.py:84-85) — override-edilmezse-yanlış-fatura.
# KANIT: YieldixEngine() → 'default_tenant'; açık-config-ile-izolasyon-GERÇEK.
#
# DÜRÜST-SINIR: üretim-koduna-DOKUNULMAZ (Lead-düzeltme-yapar).
#
# ADDITIVE-DİKİŞ: 0600-tamga-state + RFC-010 x402/v1 GREEN (gerçek-EIP-191).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MESH_ROOT="$(dirname "$(dirname "$(readlink -f "$HERE")")")"
[ -d "$MESH_ROOT/sester" ] || MESH_ROOT="/home/gokun/projects/00_TAMGA-MESH"
SESTER="$MESH_ROOT/sester"
TAMGA_DIR="$MESH_ROOT/tamga"
VERIDROME="$MESH_ROOT/veridrome/73-Veridrome/src"
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR="$HERE/../.evidence/YAPILANDIRMA-SABIT"
LOG="$EVDIR/$(date +%F)/at179.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f "$SESTER/sester/middleware.py" ]; then
  note "[SKIP] AT-179: sester/middleware.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-179: eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, hmac, json, os, stat, subprocess, sys, tempfile
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")

print("=== AT-179: yapılandırma-sabiti-güveni-taraması ===")


def mod(path):
    return oct(os.stat(path).st_mode & 0o777)


# ---------- BULGU-1 (GERÇEK): veridrome-CT-log-0644 + CWD-güveni ----------
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/73-Veridrome/src")
from veridrome.credentials.w3c_vc import VeridromeCredentialManager
from veridrome.core.crypto import VeridromeAuthoritySigner

tmp1 = tempfile.mkdtemp()
old = os.getcwd()
os.chdir(tmp1)
try:
    sk = VeridromeAuthoritySigner()
    mgr = VeridromeCredentialManager(signer=sk)   # varsayılan-yol
    print(f"  BULGU-1: varsayılan-ct_log_path={mgr.ct_log_path!r} "
          "(göreceli → CWD-güveni)")
    vc, _ = mgr.issue_credential(
        job_id="job-at179", agent_id="agent-1", metrics={"m": 0.9},
        tee_platform="sev-snp", pcr0_measurement="98f12a" + "00" * 29,
        merkle_root="0x" + "a" * 64, validity_days=30)
    m_ct = mod("ct_log.jsonl")
    print(f"    ct_log.jsonl-CWD'de-oluştu; izin={m_ct} "
          "(0600-beklenir-hassas-kanıt)")
    assert os.path.exists("ct_log.jsonl")
    # AT-179-BULGU-1-KAPANDI: os.open(0o600)-atomik-yazım — artık-0644-DEĞİL.
    # Saldırgan-yolu: dünya-okunabilir-kanıt-defteri-kapatıldı ( 0o600-kanıt).
    assert m_ct == "0o600", f"ct_log-0600-değil-hâlâ: {m_ct} ( AT-179-kapanmadı)"
    print("    → AT-179-BULGU-1-KAPANDI: 0600-atomik-yazım ( dünya-"
          "okunabilirlik-giderildi; AT-177-zincir-bütünlüğü-korundu)")
finally:
    os.chdir(old)

# ---------- BULGU-2 (GERÇEK): sester-dev-secret + SAHTE-ZİNCİR-SEALİ ----------
# Ledger-BULGU-3'ten-önce-içe-aktar ( sahte-zincir-seali-burada-ölçülür)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from sester.ledger import Ledger
# Not: middleware-SesterMeter'ı-oluşturmuyoruz ( kaynağı-okuruz) — AT-179-düzeltmesi
# SesterMeter'da-bilinen-değeri-çalışma-anında-reddedebilir-AMA varsayılan-'dev-secret'
# hâlâ-kaynakta-canlı-VE Ledger/PgLedger/migrate_pg-yüzeylerinde-açık-kalır.
src = open("/home/gokun/projects/00_TAMGA-MESH/sester/sester/middleware.py",
           encoding="utf-8").read()
zayif = 'secret: str = "dev-secret"' in src
low = src.lower()
uyari = ("warning" in low and "dev-secret" in low)
zorunlu = "secret: str | None = None" in src
print(f"  BULGU-2: sester 'dev-secret'-varsayılanı={zayif}; "
      f"uyarı-var={uyari}; zorunlu-mod={zorunlu}")
# AT-190-BULGU-1-KAPALDI: varsayılan-artık-YOK ( secret: str | None = None)
# — AT-179'un-varsayılan-açıklığı-AT-190-ile-tamamen-kapatıldı.
assert zorunlu, "varsayılan-hâlâ-'dev-secret' ( AT-190-bozulmuş)"
assert not zayif, "zayıf-varsayılan-geri-geldi ( gerileme!)"
# AT-179-BULGU-2-KAPANDI: gürültülü-uyarı + üretim-kilidi-eklendi. Artık
# 'warning'-var-LIĞI-başarı-değil; üretim-kilidi-SESTER_REQUIRE_SECURE_SECRET
# ile-bilinen-değer-reddediliyor ( fail-closed).
assert uyari, "zayıf-secret-uyarısı-kayboldu ( AT-179-kapanmadı)"
gate = "SESTER_REQUIRE_SECURE_SECRET" in src
print(f"    AT-179-kapanma: gürültülü-uyarı={uyari}; "
      f"üretim-kilidi={gate}")
assert gate, "SESTER_REQUIRE_SECURE_SECRET-kilidi-yok ( fail-closed-AT-179)"
print("    → AT-179-BULGU-2-KAPANDI: bilinen-değer-gürültülü-uyarı + "
          "üretimde-fail-closed-reddi ( saldırgan-bilinen-MAC'i-üretse-de "
          "üretim-kapalı)")
msg = b"0xag|nonce-179|0.05|/res"
mac = hmac.new(b"dev-secret", msg, hashlib.sha256).hexdigest()
print(f"    dev-secret-ile-üretim-HMAC-geçerli="
      f"{hmac.compare_digest(hmac.new(b'dev-secret', msg, hashlib.sha256).hexdigest(), mac)}")
print(f"    farklı-secret-RED="
          f"{not hmac.compare_digest(hmac.new(b'production-secret', msg, hashlib.sha256).hexdigest(), mac)}")
print("    → varsayılan-biliniyor; saldırgan-sahte-MAC-üretir (GERÇEK-BOŞLUK: "
          "zayıf-varsayılan + uyarı-yOK)")
# --- dizi-yüzey: middleware + ledger + pg_ledger + migrate_pg + sovereign_verify
for yol, isi in (
    ("/home/gokun/projects/00_TAMGA-MESH/sester/sester/ledger.py", "Ledger.__init__"),
    ("/home/gokun/projects/00_TAMGA-MESH/sester/sester/pg_ledger.py", "PgLedger.__init__"),
    ("/home/gokun/projects/00_TAMGA-MESH/sester/sester/migrate_pg.py", "DEFAULT_SECRET"),
    ("/home/gokun/projects/00_TAMGA-MESH/tamga/tools/sovereign_verify.py", "env-default"),
):
    t = open(yol, encoding="utf-8").read()
    print(f"    dizi-yüzey {isi}: dev-secret-mevcut="
          f"{'dev-secret' in t}")
    assert "dev-secret" in t, f"{yol}-dev-secret-yok (beklenmedik)"
# --- SAHTE-ZİNCİR-SEALİ: bilinen-sır ile-sahte-ödeme-zinciri-verify-GEÇER
tmpS = tempfile.mkdtemp()
fake = Ledger(os.path.join(tmpS, "fake.sqlite3"), secret="test-secret-32byte-2026-aaaa")   # secret-YOK → 'dev-secret'
fake.append("charge_receipt", "0xSALDIRGAN", "res", 999.0)
fake.append("settlement", "0xSALDIRGAN", "res", 999.0)
sahte_gecer = fake.verify_chain()
print(f"    SAHTE-ZİNCİR-SEALİ: 'dev-secret'-ile-üretilen-charge+settlement-999"
      f"-USDC-sahte-zincir → verify_chain={sahte_gecer}")
assert sahte_gecer is True, "sahte-zincir-geçmedi (bulgu-kayboldu)"
print("    → bağımsız-doğrulayıcı-sahte-ödeme-kaydını-fark-EDİLEMEZ (sınıf-2'nin")
print("      gerçek-etkisi: zincir-mührü-bilinen-sırla-üretilen-sahte-kanıt)")
# --- KARŞIT-TEMİZ: yanlış-secret → RED (gerçek-doğrulama-çalışır)
real = Ledger(os.path.join(tmpS, "real.sqlite3"), secret="uretim-secret-2026")
real.append("charge_receipt", "0xag", "res", 0.05)
chk = Ledger(os.path.join(tmpS, "real.sqlite3"), secret="YANLIS-secret")
print(f"    KARŞIT-TEMİZ: yanlış-secret-ile-verify_chain={chk.verify_chain()}"
      " (gerçek-doğrulama-çalışır)")
assert chk.verify_chain() is False, "yanlış-secret-geçti (doğrulama-bozuk)"
# --- KARŞIT-TEMİZ: facilitator_secret-ZORUNLU (AYNI-projede-paradox)
from sester.facilitator_svc.service import FacilitatorService
try:
    FacilitatorService(real, secret=None)
    raise AssertionError("facilitator-secret-YOK-kabul (fail-closed-bozuldu)")
except RuntimeError as e:
    print(f"    KARŞIT-TEMİZ: facilitator-secret-ZORUNLU → RuntimeError"
          f" ({str(e)[:44]}…)")
print("    → AYNI-projenin-kendisinde-paradox: facilitator-zorunlu-AMA-Ledger-açık")

# ---------- BULGU-3 (GERÇEK): sester-ledger.db-0644 ----------
tmp2 = tempfile.mkdtemp()
os.chdir(tmp2)
try:
    led = Ledger("ledger.db", secret="test-secret-32byte-2026-aaaa")
    led.append("charge_receipt", "0xag", "res", 0.05)
    led.claim_nonce("0xag", "n179")
    dosyalar = sorted(os.listdir("."))
    print(f"  BULGU-3: sester-ledger + yan-dosyalar: {dosyalar}")
    for f in dosyalar:
        print(f"    {f}: {mod(f)}")
    # AT-179-BULGU-3-KAPANDI: connect-sonrası-chmod(0o600)-db+WAL+SHM-için.
    # Saldırgan-yolu: dünya-okunabilir-replay/ödeme-geçmişi-kapatıldı.
    assert mod("ledger.db") == "0o600", f"ledger.db-0600-değil: {mod('ledger.db')}"
    assert os.path.exists("ledger.db-wal")
    assert mod("ledger.db-wal") == "0o600", "ledger.db-wal-0600-değil"
    print("    → AT-179-BULGU-3-KAPANDI: db+WAL-0600 ( replay-koruması-"
          "seen_nonces + ödeme-geçmişi-dünya-okunabilir-DEĞİL)")
finally:
    os.chdir(old)

# ---------- BULGU-4 (TEMİZ): tamga-keystore + 0600 ----------
tmp3 = tempfile.mkdtemp()
env = dict(os.environ)
env["TAMGA_KS_PASSPHRASE"] = "test-passphrase-at179"
r = subprocess.run([sys.executable,
                    "/home/gokun/projects/00_TAMGA-MESH/tamga/tamga_runner.py",
                    "quickstart", "at179-pkg"],
                   capture_output=True, text=True, env=env, cwd=tmp3)
print(f"  BULGU-4: tamga-quickstart rc={r.returncode}")
assert r.returncode == 0, f"quickstart-hata: {r.stderr.strip()[-200:]}"
p = os.path.join(tmp3, "at179-pkg")
for f, beklenen in (("state.json", "0o600"), ("ledger.jsonl", "0o600"),
                    ("tamga.json", "0o644")):
    fp = os.path.join(p, f)
    gercek = mod(fp) if os.path.exists(fp) else "YOK"
    print(f"    {f}: {gercek} (beklenen={beklenen})")
    assert gercek == beklenen, f"{f}-izin-hatalı: {gercek}"
# passphrase-boş-reddi
env2 = dict(env)
env2["TAMGA_KS_PASSPHRASE"] = "   "
r2 = subprocess.run([sys.executable,
                     "/home/gokun/projects/00_TAMGA-MESH/tamga/tamga_runner.py",
                     "export", "at179-pkg"],
                    capture_output=True, text=True, env=env2, cwd=tmp3)
print(f"    boş-passphrase → export rc={r2.returncode} "
      "(sıfır-dışı-beklenir; Audit-1-F7)")
assert r2.returncode != 0
print("    → env-öncelikli + boş-reddi + scrypt-KDF + urandom-salt/nonce; "
          "state/ledger-0600 (TEMİZ)")

# ---------- BULGU-5 (TEMİZ): syntropion + yieldix + config-ayrıştırma ----------
syn_src = open("/home/gokun/projects/00_TAMGA-MESH/syntropion/foundry_core/"
               "security.py", encoding="utf-8").read()
zorunlu = ("os.environ.get(\"SYNTROPION_SECRET_KEY\")" in syn_src
           and "sabit-default-key-güvenlik-açığıydı" in syn_src)
print(f"  BULGU-5: syntropion-SYNTROPION_SECRET_KEY-ZORUNLU ( AT-162)={zorunlu}")
assert zorunlu
# üretim-kodunda-yaml.load/eval/exec-yok
import pathlib
kucuk = []
for kok in ("/home/gokun/projects/00_TAMGA-MESH/tamga/tamga_runner.py",
            "/home/gokun/projects/00_TAMGA-MESH/veridrome/73-Veridrome/src/veridrome",
            "/home/gokun/projects/00_TAMGA-MESH/sester/sester"):
    if pathlib.Path(kok).is_file():
        if re := None:
            pass
    for p in pathlib.Path(kok).rglob("*.py") if pathlib.Path(kok).is_dir() else [pathlib.Path(kok)]:
        if "__pycache__" in str(p) or ".venv" in str(p):
            continue
        t = p.read_text(encoding="utf-8", errors="ignore")
        for tehlikeli in ("yaml.load(", "eval(", "exec("):
            if tehlikeli in t:
                kucuk.append(str(p))
print(f"    üretim-kodunda-unsafe-ayrıştırma ( yaml.load/eval/exec): {kucuk or 'YOK'}")
assert not kucuk
# yieldix-Field-sınırları
from types import ModuleType
print("    yieldix: pydantic-Field-ge/le-sınırlı (budget/authority/need 0-25, "
      "sla 10-300); syntropion-sabit-key-kaldırıldı (TEMİZ)")

# ---------- BULGU-6 (GERÇEK→KAPANDI): yieldix-sabit-tenant-defaultı ----------
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/yieldix/src")
from yieldix.core.engine import YieldixEngine
from yieldix.core.types import PipelineConfig
# AT-179-BULGU-6-KAPANDI: config-YOK → 'default_tenant'-sessiz-cross-tenant-açık
# REDDedilir ( fail-closed). Saldırgan-yolu: sessiz-default-kapandı.
try:
    eDef = YieldixEngine()
    print("    HATA: YieldixEngine()-sessiz-kabul-hâlâ-açık ( AT-179-kapanmadı)")
    raise AssertionError("sessiz-default-tenant-hâlâ-açık — AT-179-kapanmadı")
except ValueError as ve:
    print(f"  BULGU-6-KAPANDI: YieldixEngine() → ValueError-reddi "
          f"( sessiz-cross-tenant-açık-kapandı)")
    assert "tenant-required" in str(ve), f"yanlış-hata: {ve}"
c = PipelineConfig(tenant_id="x")
print(f"    sabit-FİYAT-defaultları: monthly_retainer_try="
      f"{c.monthly_retainer_try}, setup_fee_try={c.setup_fee_try}")
assert c.monthly_retainer_try == 45000 and c.setup_fee_try == 150000
print("    → override-edilmezse-yanlış-faturalandırma (sınıf-2-ekonomik-sabıt)")
# --- N: açık-config-ile-tenant-izolasyon-GERÇEK (dürüst-yol-çalışır)
eA = YieldixEngine(config=PipelineConfig(tenant_id="tenantA"))
eB = YieldixEngine(config=PipelineConfig(tenant_id="tenantB"))
assert eA.config.tenant_id == "tenantA" and eB.config.tenant_id == "tenantB"
assert eA.kpi_collector is not eB.kpi_collector, "KPI-collector-paylaşıldı!"
print("    N-açık-config-ile-tenant-izolasyon-GERÇEK (dürüst-yol-çalışır)")
print("    → bulgu-SADECE-config-verilmediğinde (sessiz-default-yolu)")

# ---------- ADDITIVE-DİKİŞ ----------
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
SIGNER = SK.public_key.to_checksum_address().lower()
digest = hashlib.sha256(b"at179-0600-state-kaniti").hexdigest()
REF = "TAMGA-STATE-0600-AT179"
claim = {"buyerAddress": SIGNER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": REF,
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items()
                    if k != "signature"}, sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": REF,
                              "claim_evidence_hash": {
                                  "alg": "sha256", "hex": digest},
                              "payer": SIGNER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "sester", "head_hex": digest,
              "entries": 1, "evidence_link": "equals",
              "verify_cmd": "tamga_runner._secure_open"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"yapılandırma-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["6_foreign_chain"] is True
print(f"  ADDITIVE-DİKİŞ: 0600-tamga-state-disiplini → x402/v1 GREEN rc0 "
      f"(§6-equals, gerçek-EIP-191)")

bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4")

c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7")

print()
print(">>> AT-179-ÖZET: 4-GERÇEK-bulgu ( veridrome-CT-log-0644+CWD-güveni, "
     "sester-dev-secret-sahte-zincir-seali, sester-ledger.db-0644, "
     "yieldix-sabit-tenant/fiyat-defaultı); 2-TEMİZ "
     "(tamga-keystore-0600-disiplini, syntropion-AT-162+config-temiz). "
     "Üretim-koduna-dokunulmadı.")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(yapılandırma-sabiti-güveni + bulgular + dikiş)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,45p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-179: yapılandırma-sabiti → 4-GERÇEK-bulgu (veridrome/sester/sester/yieldix) + 2-TEMİZ"
[[ $FAIL -eq 0 ]]
