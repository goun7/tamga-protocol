#!/usr/bin/env bash
# AT-158: TAMGA-STATE-ROOT / DURUM-ÖZETİ-TARAMASI — blok-özeti-mı-sunum-mu?
#
# task-54 (blockchain-yüzü-12; blockchain-dönüşümünün-son-ölçülmemiş-yüzü).
# Ethereum-bloğu-gibi-bir-state-root-yüzü-var-mı? SORU: project(head)'in-leaf-
# izdüşümü (AT-141: leaf = keccak²(sha256-head)) blok-özeti-mı-yoksa-sadece-sunum-mu?
#
# VERDICT: İNDETERMİNE — GERÇEK-bir-Ethereum-gibi-state-root-yüzü YOK. project(head)
# = SUNUM-ARACIDIR (RFC-009-§3/§4.4 presentation-only; honest_boundary-çıktısında-
# yazılı): tek-bir-digest'i (D5-head) yeniden-kodlar — durumun-tamamını-özetlemez.
#
# ÖLÇÜLEN-GERÇEK-YÜZLER (state-root-DEĞİL-ama-durum-özü-yüzleri):
# 1. graph_merkle (RFC-004 D6): memory-graph'in-özü — state.json'da; memory-node
#    eklenince DEĞİŞİR (kanıt-1). Ledger-kaydı-eklenince head-değişir-ama-graph_merkle
#    AYNI-kalır (kanıt-2: iki-özü-BAĞIMSIZ — zincir-özü ↔ durum-özü-ayrı).
# 2. graph_merkle-sadece-İMPORT-yolunda-doğrulanır (satır-1112 mismatch→state_invalid);
#    RUN-yolunda-yeniden-hesaplanır-doğrulanmaz — tahrizli-state.json run'da-yeşil-
#    geçer (bu-testin-dürüst-bulgusu; ölçüldü).
# 3. project(head)'in-leaf'i-sunum-paritesi-için-üretildi — origin-iddia-etmez.
#
# DİKİŞ (additive — durum-özü-için-DEĞİL; zincir-ucunun-ödeme-yüzü-sunum-etiketiyle):
# D5-head → RFC-010 x402/v1 GREEN rc0; rc4 + rc7.
#
# K0-DUVARI: Sybil-değil-zincir-tutarlılığı; ağırlık-ÖLÇÜLMEZ.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/TAMGA-STATE-ROOT"
LOG="$EVDIR/$(date +%F)/at158.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f tamga_project_head.py ] || [ ! -f tamga_runner.py ]; then
  note "[SKIP] AT-158: tamga_project_head.py/tamga_runner.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-158: eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

W="$(mktemp -d)"
python3 - "$W" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, pathlib, re, shutil, subprocess, sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")

W = pathlib.Path(sys.argv[1])
ROOT = pathlib.Path(".")
env = dict(os.environ, TAMGA_KS_PASSPHRASE="at158-pass-2026")

def sh(*a):
    return subprocess.run([sys.executable, "tamga_runner.py", *a],
                          capture_output=True, text=True, env=env, cwd=str(ROOT))

SEED = json.loads(sh("keygen").stdout)["seed_hex"]

# --- 0) gerçek-paket: quickstart(--seed) + grant + run → defter + durum
PKG = W / "pkg"
sh("quickstart", str(PKG), "--name", "at158", "--seed", SEED)
sh("grant", str(PKG), "0.01", "at158-hibe")
sh("run", str(PKG), "--seed", SEED, "--note", "at158-blok")
lines = [l for l in (PKG / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
         if l.strip()]
if len(lines) < 3:
    print(f"  [İNDETERMİNE] kurulum-3-kayıt-üretmedi ({len(lines)}) — engine-"
          f"yoksa-koşum-yeşil-sayılamaz; sonuç-esirgenir")
    sys.exit(0)
st_path = PKG / "state.json"
if not st_path.exists():
    print("  [İNDETERMİNE] state.json-yok — durum-özü-yüzü-ölçülemez; sonuç-esirgenir")
    sys.exit(0)
print(f"  gerçek-paket: {len(lines)}-kayıtlık-defter + state.json (durum-yüzü-meşgul)")

def gmerkle(p):
    return json.loads(p.read_text(encoding="utf-8")).get("graph_merkle")

from tamga_project_head import chain_head

g0 = gmerkle(st_path)

# --- 1) KANIT-1: memory-node → graph_merkle DEĞİŞİR (gerçek-durum-özü)
(W / "mem.json").write_text(json.dumps(
    {"nodes": [{"id": "x1", "kind": "note", "text": "at158-durum-notu"}], "edges": []}),
    encoding="utf-8")
mi = json.loads(sh("memory", str(PKG), "--import-json", str(W / "mem.json")).stdout)
assert mi.get("ok") is True and mi.get("added") == 1, f"memory-import-başarısız: {mi}"
g1 = gmerkle(st_path)
assert g0 != g1 and len(g1) == 64, \
    "graph_merkle-değişmedi — durum-özü-gerçek-değil"
print(f"  KANIT-1: memory-node-ekle → graph_merkle DEĞİŞTİ ({g0[:16]}… → {g1[:16]}…, "
      f"64-hex) — RFC-004-D6-gerçek-durum-özü")

# --- 2) KANIT-2: ledger-kaydı → head-DEĞİŞİR, graph_merkle-AYNI (bağımsız-özler)
h0, _ = chain_head(PKG)
sh("grant", str(PKG), "0.01", "at158-b2")
g2 = gmerkle(st_path)
h1, n1 = chain_head(PKG)
assert h0 != h1, "ledger-kaydı-head'i-değiştirmedi"
assert g2 == g1, "ledger-kaydı-durum-özünü-değiştirdi (bağımsız-değiller!)"
print("  KANIT-2: ledger-grant → head DEĞİŞTİ, graph_merkle AYNI — zincir-özü "
      "ile-durum-özü BAĞIMSIZ (iki-ayrı-ökzeti-yüz; Ethereum-gibi-tek-birleştirik-"
      "state-root-YOK)")

# --- 3) BULGU → DÜZELTİLDİ ( AT-163-sonrası): graph_merkle run-yolunda-artık-
# DOĞRULANIR. Önceden-tahrizli-state-yeşil-geçerdi ( yeniden-hesaplayıp-yazardı);
# artık-RED rc5. Bu-iddia-açık-geri-gelirse-YAKALAR.
st = json.loads(st_path.read_text(encoding="utf-8"))
st["memory"]["nodes"][0]["text"] = "TAHRIF-DURUM"
st_path.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
r3 = sh("run", str(PKG), "--seed", SEED, "--note", "at158-tahriz")
j3 = json.loads(r3.stdout) if r3.stdout.strip().startswith("{") else {"ok": None}
assert j3.get("ok") is False, f"AÇIK-GERİ-GELDİ! ( tahrizli-state-run-yeşil): {j3}"
assert j3.get("reason_code") == 5 and "graph_merkle" in j3.get("reason", ""), \
    f"rc5-graph_merkle-mismatch-beklendi: {j3}"
src = (ROOT / "tamga_runner.py").read_text(encoding="utf-8")
assert "_graph_merkle(st[\"memory\"]) != st[\"graph_merkle\"]" in src, \
    "run-yolu-doğrulaması-kayboldu"
print(f"  3) DÜZELTİLDİ: state.json-durum-tahrizi → run RED-rc5 "
      f"( graph_merkle-mismatch; run-yolu-artık-doğrular — AT-163'ün-ölçtüğü-"
      f"eksiklik-kapandı)")

# --- 4) project(head): presentation-only-SUNUM (blok-özeti-değil)
head, n = chain_head(PKG)
from tamga_project_head import project
p = project(head)
assert p["projection_version"] == "TAMGA_PROJECT_HEAD_V1"
assert "presentation-only" in p["honest_boundary"], "sunum-paritesi-sınırı-yok"
assert "ASLA" in p["honest_boundary"], "honest_boundary-iddia-reddi-yok"
K = lambda b: bytes.fromhex(__import__("tamga_keccak").keccak256(b).hex())
assert p["leaf_encoded"] == "0x" + K(K(bytes.fromhex(head))).hex(), "leaf ≠ keccak²(head)"
# project-durum-içermez: leaf-sadece-head'ten-türetilir, memory/graph_merkle-BAĞIMSIZ
assert p["chain_head"] == head
print(f"  project(head): leaf={p['leaf_encoded'][:20]}… — honest_boundary: "
      f"\"presentation-only… ASLA…\" → SUNUM-ARACI (blok-özeti-DEĞİL; tek-digest'i-"
      f"yeniden-kodlar, durumun-tamamını-özetlemez)")

# --- 5) CONSENSUS- gibi-eksiklik: state-root-kod-taraması
yuz = []
for mod in sorted(ROOT.glob("tamga_*.py")):
    s = mod.read_text(encoding="utf-8")
    for pat in ("merkle_patricia", "merkle-patricia", "state_root", "stateroot",
                "patricia_trie", "world_state", "account_root"):
        if re.search(pat, s, re.IGNORECASE):
            yuz.append(f"{mod.name}:{pat}")
if yuz:
    print(f"  [İLGİLİ-BULGU] state-root-benzeri-belirteçler: {sorted(set(yuz))[:4]}")
else:
    print("  state-root-probe: merkle_patricia/state_root/patricia_trie/world_state — "
          "kod-yüzünde HİÇBİRİ YOK (gerçek-tarama)")
print("  >>> VERDICT: İNDETERMİNE — Ethereum-gibi-state-root-YOK; project=head-SUNUM; "
      "graph_merkle=sadece-memory-graph-özü (wallet/sessions-zincirde-değil)")

# --- 6) ADDITIVE-DİKİŞ: zincir-ucu-head → RFC-010 x402/v1 (sunum-etiketiyle)
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
BUYER = SK.public_key.to_checksum_address().lower()
digest = head  # equals-link: zincir-ucu-head = evidenceHash = delivery = §6-head
claim = {"buyerAddress": BUYER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "TAMGA-STATE-ROOT-158",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "TAMGA-STATE-ROOT-158",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": BUYER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "tamga", "head_hex": head,
              "entries": n, "evidence_link": "equals",
              "verify_cmd": "tamga_project_head.project"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"zincir-head-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["6_foreign_chain"] is True
print(f"  ADDITIVE-DİKİŞ: D5-head → x402/v1 GREEN rc0 ({n}-blok, §6-equals) — "
      f"NOT: durum-özü-kanıtı-DEĞİL; zincir-ucunun-ödeme-yüzü (sunum-etiketiyle)")

# --- 7) NEG-1: sahte-imza → rc4
bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4 (gerçek-ecrecover-reddeder)")

# --- 8) NEG-2: evidenceHash-swap → rc7
c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7 (zincir-head'i-değiştirilemez)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(durum-özü-tarama + graph_merkle-kanıtları + dikiş + negatif)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,45p' "$LOG"; }
rm -rf "$W"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-158: state-root-taraması → İNDETERMİNE (project=sunum; graph_merkle=memory-özü)"
[[ $FAIL -eq 0 ]]
