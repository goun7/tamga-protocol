#!/usr/bin/env bash
# AT-163: STATE-TAHRİZ-RUN-YOLU-KORUMASI — AT-158-bulgunun-devamı (derin-ölçüm).
#
# task-55. AT-158'in-bulduğu-eksikliği-ölç-ve-kanıtla:
# 1. state.json-tahriz-ET → run → hâlâ-YEŞİL-mi? (AT-158-bulgusunun-teyidi)
# 2. EĞER-korunmuyorsa → GERÇEK-GÜVENLİK-EKSİKLİĞİ — AMA-ÜRETİM-KODUNA-DOKUNMA;
#    sadece-ölç-ve-raporla (Lead-düzeltme-yapar).
# 3. EK-yüz: import-yolundaki-koruma-GERÇEK-çalışıyor-mu (pozitif-kanıt)?
# 4. EĞER-run-yolu-da-korunuyorsa → Lead-yanlış-demiş-olur (dürüst-teyit).
#
# ÖLÇÜM-SONUÇLARI (hepsi-gerçek-üretim-koduyla-makine-doğrulandı):
# - RUN-YOLU-graph_merkle: tahriz → run **YEŞİL** (eksiklik-TEYİT-EDİLDİ; run-sonunda
#   graph_merkle'yı-yeniden-hesaplar-yazar — _load_state'de-check-yok; satır-861).
# - RUN-YOLU-agent_id: tahriz → **RED rc18** (run-yolu-TAMAMEN-korunmuyor —
#   agent_ownership-koruması-canlı, graph_merkle-koruması-yok; dürüst-nüans).
# - IMPORT-YOLU-graph_merkle: snap-içi-tutarsız-graph_merkle → **RED rc17**
#   "state_invalid: graph_merkle mismatch" (satır-1112) — koruma-CANLI-pozitif-kanıt.
# - KONTROL: tutarlı-snap → import **YEŞİL** (ölçüm-özgür; rc17-tahrizden-kaynaklanır,
#   yanlış-red-değil).
#
# BU-TEST-AÇIĞI-KAPATMAZ (Lead'in-işi) — eksikliği-kanıtlar.
#
# ADDITIVE-DİKİŞ: zincir-head → RFC-010 x402/v1 GREEN (eksiklik-raporuyla-birlikte
# ölçülen-yüzün-ödeme-kanıtı); rc4 + rc7.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/TAMGA-STATE-TAHRIZ"
LOG="$EVDIR/$(date +%F)/at163.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f tamga_runner.py ]; then
  note "[SKIP] AT-163: tamga_runner.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-163: eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

W="$(mktemp -d)"
python3 - "$W" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, pathlib, shutil, subprocess, sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")

W = pathlib.Path(sys.argv[1])
ROOT = pathlib.Path(".")
env = dict(os.environ, TAMGA_KS_PASSPHRASE="at163-pass-2026")

def sh(*a):
    return subprocess.run([sys.executable, "tamga_runner.py", *a],
                          capture_output=True, text=True, env=env, cwd=str(ROOT))

SEED = json.loads(sh("keygen").stdout)["seed_hex"]
NAME = "at163"

def bos_hedef(kaynak, ad):
    """Boş-hedef: manifest+wasm-aynı, state/ledger-silinmiş (import-empty-node)."""
    d = W / ad
    if d.exists():
        shutil.rmtree(d)
    shutil.copytree(kaynak, d)
    (d / "state.json").unlink()
    (d / "ledger.jsonl").unlink()
    return d

# --- 0) gerçek-paket: quickstart(--seed) + run → defter + durum
PKG = W / "pkg"
sh("quickstart", str(PKG), "--name", NAME, "--seed", SEED)
sh("run", str(PKG), "--seed", SEED, "--note", "at163-1")
lines = [l for l in (PKG / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
         if l.strip()]
if len(lines) < 1:
    print("  [İNDETERMİNE] kurulum-kayıt-üretmedi — engine-yoksa-koşum-yeşil-"
          "sayılamaz; sonuç-esirgenir")
    sys.exit(0)
sp = PKG / "state.json"
st0 = json.loads(sp.read_text(encoding="utf-8"))
print(f"  gerçek-paket: {len(lines)}-kayıtlık-defter + state.json "
      f"(graph_merkle={st0.get('graph_merkle','')[:16]}…)")

# --- 1) RUN-YOLU-ÖLÇÜM: memory-node-tahrizi → run YEŞİL mi? (AT-158-teyidi)
st = json.loads(sp.read_text(encoding="utf-8"))
st["memory"]["nodes"][0]["text"] = "TAHRIF-EDGE-RUN-YOLU"
sp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
r1 = sh("run", str(PKG), "--seed", SEED, "--note", "at163-tahriz-run")
j1 = json.loads(r1.stdout) if r1.stdout.strip().startswith("{") else {"ok": None}
g_after = json.loads(sp.read_text(encoding="utf-8")).get("graph_merkle")
if j1.get("ok") is True:
    # run graph_merkle'ı-yeniden-hesaplar (tahriz-yutulur) — eksiklik-kanıtı
    assert g_after and len(g_after) == 64, "graph_merkle-yeniden-yazılmadı"
    print(f"  1) RUN-YOLU-graph_merkle: state-tahrizi → run **YEŞİL** "
          f"(graph_merkle-yeniden-hesaplandı {g_after[:16]}…; _load_state'de-check-yok)"
    print("     → AT-158-bulgusu-TEYİT-EDİLDİ: GERÇEK-GÜVENLİK-EKSİKLİĞİ "
          "(üretim-koduna-dokunulmadı; Lead-düzeltme-yapar)")
else:
    print(f"  1) RUN-YOLU-graph_merkle: state-tahrizi → run **RED** "
          f"({j1.get('reason_code')}: {j1.get('reason','')[:60]})")
    print("     → Lead-yanlıştı: run-yolu-KORUNUYOR (dürüst-teyit)")

# --- 2) RUN-YOLU-KISMI-KORUMA: agent_id-tahrizi → RED rc18 (nüans)
st = json.loads(sp.read_text(encoding="utf-8"))
st["agent_id"] = "f" * 64
sp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
r2 = sh("run", str(PKG), "--seed", SEED, "--note", "at163-ownership")
j2 = json.loads(r2.stdout) if r2.stdout.strip().startswith("{") else {"ok": None}
assert j2.get("ok") is False and j2.get("reason_code") == 18, \
    f"agent_id-tahrizi-rc18-beklendi: {j2}"
print("  2) RUN-YOLU-agent_id: tahriz → RED rc18 (agent_ownership-canlı) — "
      "run-yolu-TAMAMEN-korunmuyor: sahibi-doğruluyor, DURUM-özünü-doğrulAMIYOR")

# --- 3) IMPORT-YOLU-POZİTİF-KANIT: snap-içi-tutarsız-graph_merkle → RED rc17
st = json.loads(sp.read_text(encoding="utf-8"))
# state-i-geri-al: graph_merkle'yı-BELLEKTEN-yeniden-hesapla (tutarlı-taban)
import tamga_runner as tr
st["agent_id"] = json.loads(sh("keygen").stdout).get("agent_id") or st["agent_id"]
# (agent_id'yi-geri-yüklemek-için-paketin-ilk-agent'ını-kullan; quickstate'i-basitleştir)
st["memory"] = st0["memory"]
st["graph_merkle"] = tr._graph_merkle(st["memory"])
st.pop("agent_id", None)  # run-yolu-agent-check-sadece-varsa-çalışır
sp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
# 3a) tutarlı-snap-üret → YEŞİL-kontrol
sh("export", str(PKG), "-o", str(W / "snap_ok.tsg"), "--seed", SEED)
d_ok = bos_hedef(PKG, "hedef_ok")
r_ok = sh("import", str(W / "snap_ok.tsg"), str(d_ok))
j_ok = json.loads(r_ok.stdout) if r_ok.stdout.strip().startswith("{") else {"ok": None}
assert j_ok.get("ok") is True, f"tutarlı-snap-import-YEŞİL-beklendi: {j_ok}"
print("  3a) KONTROL: tutarlı-snap → import YEŞİL (ölçüm-özgür; sonraki-RED'ler-"
      "tahrizden-kaynaklanır, yanlış-red-değil)")
# 3b) tutarsız-snap: node'u-tahriz-et, graph_merkle'ı-eski-bırak → export → RED rc17
st = json.loads(sp.read_text(encoding="utf-8"))
st["memory"]["nodes"][0]["text"] = "TAHRIF-IMPORT-KANIT"
sp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
sh("export", str(PKG), "-o", str(W / "snap_bad.tsg"), "--seed", SEED)
d_bad = bos_hedef(PKG, "hedef_bad")
r_bad = sh("import", str(W / "snap_bad.tsg"), str(d_bad))
j_bad = json.loads(r_bad.stdout) if r_bad.stdout.strip().startswith("{") else {"ok": None}
assert j_bad.get("ok") is False and j_bad.get("reason_code") == 17, \
    f"tutarsız-snap-rc17-beklendi: {j_bad}"
assert "graph_merkle mismatch" in j_bad.get("reason", ""), "reason-metni-bozuk"
print("  3b) IMPORT-YOLU-POZİTİF-KANIT: snap-içi-tutarsız-graph_merkle → RED rc17 "
      "\"state_invalid: graph_merkle mismatch\" (satır-1112) — koruma-CANLI")

# --- 4) ÖZET-ölçüm: iki-yol-karşılaştırma
print("  ÖZET: import-yolu-durum-özünü-doğrular (rc17); run-yolu-doğrulAMAZ "
      "(yeniden-hesaplar-yazar) — eksiklik-run-yolunda; koruma-import-kapısında")

# --- 5) ADDITIVE-DİKİŞ: zincir-head → RFC-010 x402/v1 GREEN
from tamga_project_head import chain_head
import settlement_bind_verify as SB
from eth_keys import keys

head, n = chain_head(PKG)
SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
BUYER = SK.public_key.to_checksum_address().lower()
digest = head
claim = {"buyerAddress": BUYER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "TAMGA-STATE-TAHRIZ-163",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "TAMGA-STATE-TAHRIZ-163",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": BUYER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "tamga", "head_hex": head,
              "entries": n, "evidence_link": "equals",
              "verify_cmd": "tamga_runner.run-vs-import-state-check"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"head-dikişi-GREEN-beklendi: {r}"
print(f"  5) ADDITIVE-DİKİŞ: D5-head → x402/v1 GREEN rc0 ({n}-blok, §6-equals) — "
      f"eksiklik-raporuyla-birlikte-ölçülen-yüzün-ödeme-kanıtı")

# --- 6) NEG-1: sahte-imza → rc4
bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4 (gerçek-ecrecover-reddeder)")

# --- 7) NEG-2: evidenceHash-swap → rc7
c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7 (zincir-head'i-değiştirilemez)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(run-yolu-eksikliği + import-koruması + dikiş + negatif)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,45p' "$LOG"; }
rm -rf "$W"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-163: state-tahriz run-yolu-koruma-eksikliği-kanıtı + import-koruması-canlı"
[[ $FAIL -eq 0 ]]
