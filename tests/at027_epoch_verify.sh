#!/usr/bin/env bash
# AT-027 - epoch-mührü doğrulama CLI'ı (tamga epoch-verify; RFC-009 genel-dış-kanıt yüzeyi)
# offline-deterministik: sentetik OZ-sorted merkle kanıtı üretir; ağ GEREKMEZ.
# Kaynak-olay: epoch-13 seal-flip (2026-09-13); el-rehberi: docs/VERIFY-EPOCH-ANCHOR.md.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-027/$(date +%F)}/at027.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# 0) selftest: yaprak-şekli/boş-kanıt/sorted-pairs (ağ YOK)
python3 tamga_epoch_verify.py --selftest > "$W/st.out" 2>&1
ok $? "selftest: yaprak-şekli + boş-kanıt + sorted-pairs"

# sentetik 64-yapraklı (tam-ikili) OZ-sorted ağaç + position-55 kanıtı üret (deterministik)
# Apodix tarifi: yaprak = keccak(keccak(bytes32(fact))) — modülün çift-hash sözleşmesiyle birebir
python3 - > "$W/gen.out" 2>&1 <<PYEOF
import json, pathlib
import tamga_keccak as k

facts = [k.keccak256(f"at027-fact-{i}".encode()) for i in range(64)]
leaves = [k.keccak256(k.keccak256(f)) for f in facts]
level = sorted(leaves)
while len(level) > 1:
    nxt = []
    for i in range(0, len(level), 2):
        a, b = sorted([level[i], level[i+1]])
        nxt.append(k.keccak256(a + b))
    level = nxt
root = "0x" + level[0].hex()

def make_proof(idx):
    proof = []
    lvl = sorted(leaves); pos = lvl.index(leaves[idx])
    while len(lvl) > 1:
        sib = pos ^ 1
        proof.append("0x" + lvl[sib].hex())
        nxt = []
        for i in range(0, len(lvl), 2):
            a, b = sorted([lvl[i], lvl[i+1]])
            nxt.append(k.keccak256(a + b))
        lvl = nxt; pos //= 2
    return proof

payload = {"epoch_id": 27, "fact_hash": "0x" + facts[55].hex(),
           "position": 55, "leaf_count": 64, "proof": make_proof(55), "root": root}
pathlib.Path("$W/temiz.json").write_text(json.dumps(payload, sort_keys=True))
print("root:", root)
PYEOF
ok $? "sentetik-64-yaprak OZ-ağacı + p55 kanıtı üretildi"

# 1) temiz payload → dahil-etme GREEN (rc-0; --rpc yok → offline)
python3 tamga_epoch_verify.py "$W/temiz.json" > "$W/temiz.out" 2>&1
[ $? -eq 0 ] && grep -q "\[GREEN\] dahil-etme" "$W/temiz.out"
ok $? "temiz-kanıt: dahil-etme GREEN (offline; rc-0)"

# 2) kök-kurcalama (root-açılımında 1-bayt): hesaplanan kök uyamaz → RED rc-1
python3 - <<PYEOF
import json, pathlib
d = json.loads(pathlib.Path("$W/temiz.json").read_text())
r = d["root"]; d["root"] = ("0x" + "00" + r[4:]); pathlib.Path("$W/bozuk-kok.json").write_text(json.dumps(d))
PYEOF
python3 tamga_epoch_verify.py "$W/bozuk-kok.json" > "$W/bk.out" 2>&1
[ $? -eq 1 ] && grep -q "\[RED\]" "$W/bk.out"
ok $? "kök-kurcalama → RED rc-1"

# 3) kanıt-kesme: proof son-elemanı düşür → RED (fail-loud; sessiz-yeşil yok)
python3 - <<PYEOF
import json, pathlib
d = json.loads(pathlib.Path("$W/temiz.json").read_text())
d["proof"] = d["proof"][:-1]
pathlib.Path("$W/kesik.json").write_text(json.dumps(d))
PYEOF
python3 tamga_epoch_verify.py "$W/kesik.json" > "$W/kk.out" 2>&1
[ $? -eq 1 ] && grep -q "\[RED\]" "$W/kk.out"
ok $? "kanıt-kesme → RED (yaprak-üstü yolçapı bozulur)"

# 4) yanlış-fact: aynı ağaç, başka yaprak → kök tutmaz → RED
python3 - <<PYEOF
import json, pathlib
d = json.loads(pathlib.Path("$W/temiz.json").read_text())
d["fact_hash"] = "0x" + "ab" * 32
pathlib.Path("$W/yanlis-fact.json").write_text(json.dumps(d))
PYEOF
python3 tamga_epoch_verify.py "$W/yanlis-fact.json" > "$W/yf.out" 2>&1
[ $? -eq 1 ]
ok $? "yanlış-fact → RED"

# 5) zarf-eksik: 'proof' alanı yok → mesajlı RED (traceback YOK)
python3 - <<PYEOF
import json, pathlib
d = json.loads(pathlib.Path("$W/temiz.json").read_text()); del d["proof"]
pathlib.Path("$W/eksik.json").write_text(json.dumps(d))
PYEOF
python3 tamga_epoch_verify.py "$W/eksik.json" > "$W/ek.out" 2>&1
[ $? -eq 1 ] && grep -q "zarf-eksik" "$W/ek.out" && ! grep -q "Traceback" "$W/ek.out"
ok $? "zarf-eksik → mesajlı-RED (fail-loud; Traceback-YOK)"

# 6) non-obje girdisi → mesajlı RED (traceback YOK)
printf '[]' > "$W/bos.json"
python3 tamga_epoch_verify.py "$W/bos.json" > "$W/bj.out" 2>&1
[ $? -eq 1 ] && grep -q "\[RED\]" "$W/bj.out" && ! grep -q "Traceback" "$W/bj.out"
ok $? "non-obje-payload → mesajlı-RED (O3-ders-parite)"

# 7) ölü-RPC: --rpc verilir ama adres ölür → İNDETERMİNE rc-2 (bakamadım ≠ yeşil ≠ kırmızı)
python3 tamga_epoch_verify.py "$W/temiz.json" --rpc "http://127.0.0.1:9/olur" --contract 0x0000000000000000000000000000000000000000 > "$W/olur.out" 2>&1
[ $? -eq 2 ] && grep -q "İNDETERMİNE" "$W/olur.out"
ok $? "ölü-RPC → İNDETERMİNE rc-2 (üç-sonuç-sözleşmesi)"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]
