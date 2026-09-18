#!/usr/bin/env bash
# jcs-parity — Python tamga_canon vs Node reference (ECMAScript-native) byte-for-byte.
# Kanıt-önce: Python'ın number/anahtar-sıralama üretimi gerçek-ECMAScript'le-birebir-mi?
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, pathlib, sys
sys.path.insert(0, ".")
from tamga_canon import jcs
corpus = [
    {"a": 1.0, "b": 1},
    {"z": -0.0, "y": 0.0},
    {"big": 1e16, "huge": 1e21, "tiny": 1e-7, "edge": 1e-6},
    {"fee": 2.93e-07, "cpu": 2.983e-06},
    {"third": 0.3333333333333333},
    {"astronomical": 1.5e300},
    {"neg": -1.234e-10},
    {"i": 9007199254740991},
    {"ctrl": "a\bb\nc\u0001d"},
    {"q": "he said \"hi\" \\\\done", "x": 1.5},
    {"￿": 1, "𐀀": 2},
    {"x": [{"y": 1.5, "z": "é"}], "€": True},
    {"a": 1, "Ā": 2},                     # issue#2 (Rul1an): BMP-içi LE-bayt-tuzağı
    {"ÿ": 1, "Ā": 2},
    {"b": 1, "Ă": 2},
    {"max_safe": 9007199254740991},          # 2^53-1: son-I-JSON-güvenli-tamsayı (yeşil)
    {"over": 9007199254740993},              # 2^53+1: node yuvarlar, python RED (gvp-audit sınıfı)
    {"big": 1234567890123456789},            # I-JSON-dışı: node …6780 yuvarlar
    # NOT: NaN/Inf JSON-interchange'da taşınamaz (json.dumps NaN-literal-üretir,
    # JSON.parse-red-eder); bu sınıf vauban-selftest'te doğrudan-nesne-olarak-test-edilir.
    {"": "empty-key", "0": "digitish", "10": "x", "9": "y"},
]
pathlib.Path("/tmp/jcs-corpus.json").write_text(json.dumps(corpus, ensure_ascii=False), encoding="utf-8")
print("python:")
for i, c in enumerate(corpus):
    try:
        print(i, jcs(c).hex())
    except ValueError:
        print(i, "RED")
PY
node --input-type=module -e '
import { readFileSync } from "node:fs";
import { canon } from "./tools/jcs_ref.mjs";
const corpus = JSON.parse(readFileSync("/tmp/jcs-corpus.json", "utf-8"));
console.log("node:");
corpus.forEach((c, i) => console.log(i, Buffer.from(canon(c), "utf-8").toString("hex")));
' > /tmp/jcs-node.txt 2>&1 || { echo "node-hata"; cat /tmp/jcs-node.txt; exit 1; }
python3 - <<'PY'
import subprocess, sys
py = subprocess.run([sys.executable, "-c", '''
import json, sys; sys.path.insert(0, ".")
from tamga_canon import jcs
c = json.load(open("/tmp/jcs-corpus.json", encoding="utf-8"))
for i, x in enumerate(c):
    try:
        print(i, jcs(x).hex())
    except ValueError:
        print(i, "RED")   # I-JSON-dışı-değer: python-reddeder, node-yuvarlar → kıyas-dışı
'''], capture_output=True, text=True, cwd=".").stdout
node = subprocess.run(["node", "--input-type=module", "-e", '''
import { readFileSync } from "node:fs";
import { canon } from "./tools/jcs_ref.mjs";
const c = JSON.parse(readFileSync("/tmp/jcs-corpus.json", "utf-8"));
c.forEach((x, i) => console.log(i, Buffer.from(canon(x), "utf-8").toString("hex")));
'''], capture_output=True, text=True, cwd=".").stdout
pl, nl = {}, {}
red = set()
for line in py.strip().splitlines():
    i, h = line.split(); pl[int(i)] = h
    if h == "RED": red.add(int(i))
for line in node.strip().splitlines():
    i, h = line.split(); nl[int(i)] = h
# I-JSON-dışı değerler: python RED-der, node-yuvarlar → hash'ler-zaten-farklı;
# bu-beklenen-diverjans-değil-beklenen-RED'dir — RED'ler-iyi-sayılır, kötü-değil.
bad = [i for i in pl if i not in red and pl[i] != nl[i]]   # yeşil-görev-uyuşmazlığı → gerçek-fark
n = len(pl)
nred = len(red)
print(f"JCS-PARİTE: {n - nred - len(bad)}/{n - nred} bayt-birebir (python-canonical === node-ECMAScript)"
      + (f" + {nred} I-JSON-RED (python-reddeder/node-yuvarlar — beklenen-fark)" if nred else ""))
for i in bad:
    print(f"  #{i} divergence:\n    py : {pl[i]}\n    js : {nl[i]}")
sys.exit(1 if bad else 0)
PY
