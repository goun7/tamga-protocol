#!/usr/bin/env bash
# AT-143: TAMGA/NATIVE-KANIT-ÜRETİM-ÇEKİRDİĞİ — tamga_bundle.py-build() →
# RFC-010-DİKİŞİ.
#
# Yönelim: TAMGA-PROTOCOL-BLOCKCHAIN'e-dönüş. Bu-test-çekirdeğin-kendisini-
# ölçer: bir-işin-TÜM-kanıtını-tek-bundle'da-toplayan-üretim-yolunu.
#
# tamga/tamga_bundle.py — build(pkg, out_dir):
#   :51 build — D5-zincirini-gerçek-zamanlı-doğrular ( :25 _chain_head:
#     h = sha256( prev + jcs( rec-{h,node_sig})), seq-1'den-başlar, prev-
#     bağı) ve-kopya-kanıt-bundle'ı-üretir:
#     · chain.head = GERÇEK-SHA-256-mührü ( DERIVED — yeniden-hesaplanır,
#       kopyalanmaz)
#     · package.manifest_sha256 = sha256( tamga.json-bytes)
#     · jobs = op="charge"-kayıtları ( RFC-003-D5: iş-kayıtı-tek-şekil)
#   :131 main — tek-komut-CLI: rc-0 (ok) / rc-1 ( kırık-zincir-de-kanıttır:
#     bundle-yine-de-üretilir)
#
# TASARIM-KURALI ( üretim-kendi-sözü): bundle-YENİ-iddia-ÜRETMEZ — yalnızca
# varolan-zincir-kayıtlarını-KOPYALAR-ve-her-alanı-kaynak-etiketler ( OBSERVED/
# DERIVED). İmza-ÜRETİLMEZ — AMA-head-GERÇEK-SHA-256-özüttür ( RFC-8785-JCS
# canonicalization-ile-mühürlenmiş-D5-hash-chain). Bu-yüzden-dikiş-yapılabilir:
# §6-foreign-chain "tamga"-zinciri-artık-whitelist'te.
#
# KARŞI-TARAF-ÇOĞALTILABİLİRLİK ( bu-testin-asıl-kanıtı): bundle'ı-üçüncü-taraf
# tamga_verify_mini.py-ile-tek-komutla-doğrular — temiz-bundle-GREEN,
# T AHRİF-EDİLMİŞ-bundle-RED ( broken@n). Kanıt-sızıntısı-yok.
#
# Yedi-kanıt + 3-negatif:
#   1) GERÇEK-D5-zinciri-üretimi + build → verdict-ok, head, bundle.json+md
#   2) Üretici-tarafı: head == bağımsız-D5-yeniden-hesap; manifest_sha256-birebir
#   3) op-filtresi: charge-dışı-kayıt-jobs'da-yok
#   4) CLI-tek-komut: rc-0 ( ok) / tahrifli-rc-1 ( bundle-yine-de-üretilir)
#   5) Mini-verify-çoğaltma: temiz-GREEN ( --expect-tip) / tahrifli-RED
#   6) RFC-010-tamga/native-GREEN ( §6-tamga-zinciri, gerçek-Ed25519)
#   7) NEG-1: sahte-imza → RED rc4
#   8) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7
#   9) NEG-3: bundle-tahrifi ( records-payload'ı-değişti) → mini-verify-RED
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/TAMGA-BUNDLE/$(date +%F)/at143.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-143: tamga/native kanıt-üretim-çekirdeği (bundle) → RFC-010 dikişi"

TM="/home/gokun/projects/00_TAMGA-MESH/tamga"
if [ ! -f "$TM/tamga_bundle.py" ] || [ ! -f "$TM/tamga_canon.py" ] \
   || [ ! -f "$TM/tamga_verify_mini.py" ]; then
  note "[SKIP] AT-143: Tamga-çekirdek-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import nacl" 2>/dev/null; then
  note "[SKIP] AT-143: PyNaCl-yok — gerçek-Ed25519-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$TM" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, pathlib, subprocess, sys, tempfile
TM = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(TM))                 # tamga/tamga_bundle.py
sys.path.insert(0, str(TM / "tools")); sys.path.insert(0, str(TM))

from tamga_canon import jcs                # RFC 8785 ( python≡node-paritesi)
import tamga_bundle as TB
import settlement_bind_verify as SB

TMP = pathlib.Path(tempfile.mkdtemp(prefix="at143-"))
PKG = TMP / "at143-pkg"; PKG.mkdir()
OUT = TMP / "out"; OUT.mkdir()

# --- 0) GERÇEK-D5-zinciri ( üretim-kuralı-ile-mühürlü)
MF = {"package": {"name": "at143-pkg", "version": "0.1"},
      "signature": {"key": "a" * 64}}
(PKG / "tamga.json").write_text(json.dumps(MF), encoding="utf-8")

def d5_kayit(seq, prev, **alanlar):
    """Üretim-D5-kuralı: h = sha256( prev + jcs( rec-{h,node_sig}))."""
    rec = {"seq": seq, "prev": prev, "op": "charge"}
    rec.update(alanlar)
    no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
    rec["h"] = hashlib.sha256(
        (prev + jcs(no_h).decode("utf-8")).encode("utf-8")).hexdigest()
    return rec

KAYITLAR = []
prev = "0" * 64
for i, (sess, eng) in enumerate([("s1", "node20"), ("s2", "node20"),
                                 ("s3", "deno")], 1):
    r = d5_kayit(i, prev, session=sess, engine=eng,
                 stdout_sha256=hashlib.sha256(f"cikti{i}".encode()).hexdigest(),
                 wall_ms=100 + i, fee_sim=0.01 * i, fee_birebir=0.01 * i,
                 delivery_hash={"alg": "sha256",
                                "hex": hashlib.sha256(f"teslim{i}".encode()).hexdigest()},
                 net_decl_sha256=hashlib.sha256(f"net{i}".encode()).hexdigest())
    KAYITLAR.append(r); prev = r["h"]
BEKLENEN_HEAD = prev

def ledger_yaz(kayitlar, yol):
    with open(yol, "w", encoding="utf-8") as f:
        for r in kayitlar:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

LEDGER = PKG / "ledger.jsonl"
ledger_yaz(KAYITLAR, LEDGER)

# --- 1) build(): GERÇEK-bundle-üretimi
out, md, bundle = TB.build(PKG, OUT)
ch = bundle["chain"]
assert ch["verdict"] == "ok" and ch["lines"] == 3, \
    f"ok/3-beklendi: {ch['verdict']}/{ch['lines']}"
assert len(ch["head"]) == 64 and ch["head"] == BEKLENEN_HEAD
assert bundle["bundle_format"] == "tamga-evidence-bundle/1"
assert out.exists() and md.exists()
assert bundle["package"]["name"] == "at143-pkg"
print(f"  build(): verdict-ok, 3-kayıt, head={ch['head'][:16]}… "
      f"( bundle.json+md-üretildi)")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: bağımsız-D5-yeniden-hesap + manifest-özütü
h = "0" * 64
for n, r in enumerate(KAYITLAR, 1):
    no_h = {k: v for k, v in r.items() if k not in ("h", "node_sig")}
    exp = hashlib.sha256(
        (r["prev"] + jcs(no_h).decode("utf-8")).encode("utf-8")).hexdigest()
    assert exp == r["h"], f"kayıt-{n}-hash-yanlış-hesaplanmış"
    assert r["seq"] == n and r["prev"] == h, f"kayıt-{n}-zincir-bağı-bozuk"
    h = r["h"]
assert h == ch["head"], "head-bağımsız-yeniden-hesapla-eşleşmedi"
assert bundle["package"]["manifest_sha256"] == hashlib.sha256(
    (PKG / "tamga.json").read_bytes()).hexdigest(), "manifest-özütü-yanlış"
assert bundle["package"]["agent_pubkey"] == "a" * 64
print("  üretici-tarafı: head-bağımsız-D5-ile-birebir; manifest_sha256-"
      "sha256(bytes)-birebir; agent-pubkey-kopyalandı")

# --- 3) op-FİLTRESİ: charge-dışı-kayıt-jobs'da-YOK ( RFC-003-D5-tek-şekil)
HB = d5_kayit(4, prev, op="heartbeat", session="s4", engine="node20")
KAYITLAR2 = KAYITLAR + [HB]
ledger_yaz(KAYITLAR2, LEDGER)
_, _, b2 = TB.build(PKG, OUT)
assert len(b2["jobs"]) == 3, "jobs-yalnızca-charge-kayıtlarını-içermeli"
assert b2["chain"]["lines"] == 4 and b2["chain"]["verdict"] == "ok"
BEKLENEN_HEAD2 = HB["h"]
ledger_yaz(KAYITLAR, LEDGER)                  # temiz-ledger'a-dön
print("  op-filtresi: heartbeat-kayıtı-zincirde-4-AMA-jobs=3 (iş=charge)")

# --- 4) CLI-tek-komut: rc-0 ( ok) / tahrifli-rc-1 ( bundle-yine-de-üretilir)
cli = subprocess.run([sys.executable, str(TM / "tamga_bundle.py"),
                      str(PKG), "-o", str(OUT)],
                     capture_output=True, text=True)
assert cli.returncode == 0, f"CLI-rc-0-beklendi: {cli.returncode} {cli.stdout}"
cj = json.loads(cli.stdout)
assert cj["ok"] is True and cj["head"] == BEKLENEN_HEAD
# tahrifli-ledger → rc-1-AMA-bundle-üretilir ( kırık-zincir-de-kanıttır)
TAHRIF = [dict(r) for r in KAYITLAR]; TAHRIF[1]["wall_ms"] = 999999
ledger_yaz(TAHRIF, LEDGER)
cli2 = subprocess.run([sys.executable, str(TM / "tamga_bundle.py"),
                       str(PKG), "-o", str(OUT)],
                      capture_output=True, text=True)
assert cli2.returncode == 1, f"kırık-zincir-rc-1-beklendi: {cli2.returncode}"
cj2 = json.loads(cli2.stdout)
assert cj2["ok"] is True and cj2["chain_verdict"].startswith("broken@2")
assert (OUT / "at143-pkg-bundle.json").exists(), "kırık-zincirde-de-bundle-üretilmeli"
ledger_yaz(KAYITLAR, LEDGER)                  # temiz-ledger'a-dön
print("  CLI: temiz-rc-0; tahrifli-rc-1-AMA-bundle-üretilir ( kırık-de-kanıttır)")

# --- 5) MİNİ-VERIFY-ÇOĞALTMA ( üçüncü-taraf-tek-komut)
def mini(records, expect=None):
    yol = TMP / "records.jsonl"
    with open(yol, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    argv = [sys.executable, str(TM / "tamga_verify_mini.py"), str(yol)]
    if expect:
        argv.append(f"--expect-tip={expect}")
    return subprocess.run(argv, capture_output=True, text=True)

rm = mini(bundle["chain"]["records"])
assert rm.returncode == 0
rmj = json.loads(rm.stdout)
assert rmj["ok"] is True and rmj["head"] == BEKLENEN_HEAD, \
    f"mini-verify-temiz-GREEN-beklendi: {rmj}"
# --expect-tip-uyuşmazlığı-yakalanır
rm_bad = mini(bundle["chain"]["records"], expect="9" * 64)
assert rm_bad.returncode == 1 and "tip-mismatch" in rm_bad.stdout
print("  mini-verify: temiz-bundle-GREEN ( head-eşleşti); --expect-tip-"
      "uyuşmazlığı-yakalandı")

# --- 6) RFC-010-TAMGA/NATIVE-DİKİŞİ ( §6-tamga-zinciri-whitelist'te)
from nacl.signing import SigningKey
sk = SigningKey(os.urandom(32))
PUB_HEX = bytes(sk.verify_key).hex()
assert len(PUB_HEX) == 64
EV = hashlib.sha256(out.read_bytes()).hexdigest()   # gerçek-bundle-özütü
govde = {"buyerAddress": PUB_HEX, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "TMGA-BUNDLE-143",
         "evidenceHash": {"alg": "sha256", "hex": EV}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig_hex = sk.sign(bytes.fromhex(d)).signature.hex()
assert len(sig_hex) == 128
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 143, "prev": "0" * 64, "h": "d" * 64,
          "delivery_hash": {"alg": "sha256", "hex": EV},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "TMGA-BUNDLE-143",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": PUB_HEX, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": ch["head"],
                                  "entries": ch["lines"], "evidence_link": None,
                                  "verify_cmd": "tamga_bundle.build + "
                                                "tamga_verify_mini"}}
rs = SB.verify(charge, claim)
assert rs["verdict"] == "GREEN", f"bundle-dikişi-GREEN-beklendi: {rs}"
assert rs["checks"].get("6_foreign_chain") is True, "§6-tamga-zinciri-geçmedi"
print(f"  gerçek-bundle-özütü + D5-head → RFC-010-tamga/native-GREEN "
      f"( §6-chain=tamga, gerçek-Ed25519)")

# --- 7) NEG-1: sahte-imza → RED rc4
for sahte in ("ff" * 64, os.urandom(64).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rx = SB.verify(charge, cs)
    assert rx["verdict"] == "RED" and rx["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rx}"
print("  sahte-imza (128-heks-sıfır/rastgele) → RED rc4 (fail-closed)")

# --- 8) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
c2 = dict(govde2); c2["signature"] = sk.sign(bytes.fromhex(d2)).signature.hex()
ry = SB.verify(charge, c2)
assert ry["verdict"] == "RED" and ry["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {ry}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")

# --- 9) NEG-3: BUNDLE-TAHRİFİ → mini-verify-RED ( karşı-taraf-tespit-eder)
recs_t = [dict(r) for r in bundle["chain"]["records"]]
recs_t[0]["stdout_sha256"] = "e" * 64           # payload-tahrifi ( h-eski)
rt = mini(recs_t)
rtj = json.loads(rt.stdout)
assert rt.returncode == 1 and rtj["ok"] is False and "broken@" in rtj["reason"], \
    f"tahrifli-bundle-RED-beklendi: {rtj}"
print(f"  bundle-tahrifi ( records-payload'ı) → mini-verify-RED "
      f"({rtj['reason']}) — karşı-taraf-tespit-eder")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: dokuz-tamga-bundle-kanıt-üretim-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-143: tamga/native kanıt-üretim-çekirdeği (bundle) → RFC-010"
[[ $FAIL -eq 0 ]]
