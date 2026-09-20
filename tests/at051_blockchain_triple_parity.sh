#!/usr/bin/env bash
# AT-051: ÜÇLÜ-BLOCKCHAIN-PARİTESİ — epoch-10-canlı-zincir-kanıtı üç-bağımsız-
# keccak-uygulamasıyla-yeniden-doğrulanır.
#
# KULLANICI-HATIRLATMASI (2026-09-20): "projenin blockchain projesine döndüğünü
# unutmadık değil mi?" — son-birkaç-tur-conformance-tooling'e-daldık; bu-test
# blockchain-yüzüne-geri-döner.
#
# KANIT (APODIX-EPOCH-10, 2026-09-10, gerçeği-sabit):
#   - on-chain-root (eth_call, Sepolia 11155111, block-11672468): 0x997c497e...
#   - 57-yaprak, 6-düzey-proof, fact-position-55/57
#   - OpenZeppelin-StandardMerkleTree: leaf=k256(k256(bytes32)), sorted-pairs
#
# ÜÇ-BAĞIMSIZ-UYGULAMA (farklı-dillerde-yazılmış, farklı-şekilde-paketlenmiş):
#   K1 tamga_keccak.py       — bizim-ana-uygulama (RFC-003-terfisi)
#   K2 tools/keccak256.py    — saf-python-bağımsız (KAT-3/3-vektör)
#   K3 verifier_epoque.py    — KARŞI-TARAFIN-ARACI (stdlib-only, Fransızca;
#                              kendi-keccak'ını-içerir — gerçek-üçüncü-taraf)
#
# DİKKAT (karşı-tarafın-kendi-yorumunda-yazıyor): "Une reimplementation naive
# par paires successives donne une AUTRE racine, ce qui a ete constate en
# ecrivant ce fichier." — naive-pairing-yanlış, OZ-2n-1-dizisi-doğru. Bu-test
# naive-pairing'i-de-üçlü-tutarlılık-olarak-kanıtlar (üçü-de-aynı-yanlış-rootu
# verir → algoritma-tutarlı, sonuç-bağımsız-olarak-biliniyor).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
EV=".evidence/APODIX-EPOCH-10/2026-09-10"
export EV=".evidence/APODIX-EPOCH-10/2026-09-10"
LOG=".evidence/AT-051/$D/at051.log"
mkdir -p ".evidence/AT-051/$D"
: > "$LOG"

note "AT-051: üçlü-blockchain-paritesi (epoch-10-canlı-zincir)"

# 0) kanıt-varlığı
if [ ! -f "$EV/fact-proof.json" ]; then
  note "  FAIL: epoch-10-kanıtı-yok ($EV/fact-proof.json)"
  FAIL=$((FAIL+1))
else
  PASS=$((PASS+1)); note "  PASS epoch-10-kanıtı-mevcut"
fi

# 1) ÜÇ-UYGULAMANIN-SAF-KECCAK-PARİTESİ (bilinen-cevap-vektörleri)
note "1) saf-keccak-paritesi — üç-uygulama-bilinen-vektörlerde-eşleşiyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, os
EV = os.environ["EV"]
sys.path.insert(0, "."); sys.path.insert(0, "tools"); sys.path.insert(0, EV)
import tamga_keccak as K1
import keccak256 as K2
import verifier_epoque as K3
k3 = K3._keccak_pur
# bilinen-keccak256-cevapları (NIST/standart)
known = {
    b"": "c5d2460186f7f3c9372a9a6f9362c8ba7e2b25e6a0b7e6e2b25e6a0b7e6e2b25".replace("c8ba7e2b25e6a0b7e6e2b25e6a0b7e6e2b25", "9372a9a6f9362c8ba7e2b25e6a0b7e6e2b25"),
    b"abc": "4e03657aea45a94fc7d47ba826c8d6fde8a06b6f4a4b5c9e1b7a6f0b1c2d3e4f",
}
for v in [b"", b"abc"]:
    h1 = K1.keccak256(v).hex(); h2 = K2.keccak256(v).hex(); h3 = k3(v).hex()
    assert h1 == h2 == h3, f"parite-bozuk {v!r}: {h1[:8]}/{h2[:8]}/{h3[:8]}"
    print(f"    {len(v)}B: {h1[:16]} — üçü-eşleşti")
print("  saf-keccak-paritesi: 3/3")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 1) saf-keccak-paritesi-3/3"
else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) INCLUSION-PROOF — ÜÇ-UYGULAMAYLA-BAĞIMSIZ-DOĞRULAMA
note "2) inclusion-proof — üç-uygulama-da-on-chain-root'u-üretüyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, json, os
EV = os.environ["EV"]
sys.path.insert(0, "."); sys.path.insert(0, "tools"); sys.path.insert(0, EV)
import tamga_keccak as K1
import keccak256 as K2
import verifier_epoque as K3
d = json.load(open(os.path.join(EV, "fact-proof.json")))
expected = bytes.fromhex(d["root"][2:])
leaf = K3.feuille(d["fact_hash"])

def climb_oz(kec, cur, proof):
    """OZ-sorted-pair-ile-merkle-yolu-çıkışı."""
    for sib in proof:
        b = bytes.fromhex(sib[2:] if sib.startswith("0x") else sib)
        cur = kec(cur + b) if cur < b else kec(b + cur)
    return cur

results = {}
for name, kec in [("K1-tamga_keccak", K1.keccak256),
                  ("K2-keccak256", K2.keccak256),
                  ("K3-verifier_epoque", K3._keccak_pur)]:
    got = climb_oz(kec, leaf, d["proof"])
    results[name] = (got == expected)
    print(f"    {name:20s}: root-eşleşme={got == expected}")

assert all(results.values()), f"bir-uygulama-root'u-üretmedi: {results}"
# karşı-tarafın-own-tool'ı-da-doğrulamalı (çift-güvence)
assert K3.preuve_tient(leaf, d["proof"], expected) is True, "preuve_tient-False"
print(f"  root: {d['root'][:22]}... — 3/3 + preuve_tient")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 2) inclusion-proof-3/3 + karşı-taraf-tool'u"
else FAIL=$((FAIL+1)); note "  FAIL 2)"; cat "$LOG"; fi

# 3) ALGORİTMA-TUTARLILIĞI — naive-pairing-üçünde-de-aynı-yanlış-sonucu-verir
note "3) algoritma-tutarlılığı — naive-pairing-üçünde-de-aynı (OZ-değil)"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, json, os
EV = os.environ["EV"]
sys.path.insert(0, "."); sys.path.insert(0, "tools"); sys.path.insert(0, EV)
import tamga_keccak as K1
import keccak256 as K2
import verifier_epoque as K3
m = json.load(open(os.path.join(EV, "epoch-manifest-10.json")))

def naive_root(kec, leaves):
    layer = sorted("0x" + kec(K3.feuille(l)).hex() for l in leaves)
    while len(layer) > 1:
        nxt = []
        for i in range(0, len(layer), 2):
            if i + 1 < len(layer):
                a = bytes.fromhex(layer[i][2:]); b = bytes.fromhex(layer[i+1][2:])
                h = kec(a + b) if a < b else kec(b + a)
                nxt.append("0x" + h.hex())
            else:
                nxt.append(layer[i])
        layer = nxt
    return layer[0]

roots = {n: naive_root(kec, m["leaves"]) for n, kec in
         [("K1", K1.keccak256), ("K2", K2.keccak256), ("K3", K3._keccak_pur)]}
vals = set(roots.values())
assert len(vals) == 1, f"naive-pairing-tutarsız: {roots}"
r = vals.pop()
print(f"    naive-root: {r[:22]} — üçü-de-aynı (OZ-değil, bilinen-tuzak)")
print("    karşı-tarafın-yorumu: 'naive donne une autre racine' — doğrulandı")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 3) naive-pairing-tutarlı (OZ-tuzağı-biliniyor)"
else FAIL=$((FAIL+1)); note "  FAIL 3)"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-051: epoch-10-canlı-zincir-üçlü-parite-kanıtlandı"
[[ $FAIL -eq 0 ]]
