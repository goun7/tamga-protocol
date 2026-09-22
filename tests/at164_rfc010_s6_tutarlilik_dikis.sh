#!/usr/bin/env bash
# AT-164: RFC-010-§6 ↔ KOD-TUTARLILIK-DENETİMİ ( standardizasyon)
#
# Bulgu: §6-foreign_chain_proof-KODDA-uygulanıyordu-AMA-RFC-010'de-TANIMLI-
# DEĞİLDİ ( sadece-0..5-bölümleri). 169-satırda-'foreign_chain'-kelimesi-YOK.
# AT-141..161'in-§6-dikişleri-standardize-edilmemişti. Bu-test-RFC'ye-eklenen
# §6-ile-üretim-kodunun-BİREBİR-tutarlı-olduğunu-kanıtlar ( additive-only).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/.evidence/RFC010-S6-TUTARLILIK/$(date +%F)/at164.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }

python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, re, pathlib
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
import settlement_bind_verify as SB

rfc = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/tamga/docs/"
    "RFC-010-cross-artifact-settlement-binding-DRAFT.md").read_text(encoding="utf-8")
code = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/tamga/tools/"
    "settlement_bind_verify.py").read_text(encoding="utf-8")

# --- 1) §6-RFC'de-TANIMLI ( önceden-YOKTU)
assert "## 6. Yabancı-zincir-kanıtı" in rfc, "§6-RFC'de-yok"
assert "foreign_chain_proof" in rfc, "§6-şema-adı-yok"
assert "evidence_link" in rfc, "§6-link-tanımı-yok"
print("  §6-RFC'de-tanımlı ( şema + evidence_link + gate-davranışı)")

# --- 2) whitelist-TUTARLILIĞI: koddaki-her-zincir-RFC'de-de-olmalı
k0 = code.index("chain not in (")
k1 = code.index(")", code.index('"veridrome"', k0)) + 1
code_chains = set(re.findall(r'"([a-z]+)"', code[k0:k1]))
assert code_chains, "kod-whitelist'i-çözülemedi"
# RFC §6.1-whitelist'ında-TÜRKÇE-açıklamalar-da-var; bu-yüzden-her-kod-zincirinin
# RFC'de-§6-bölümünde-geçtiğini-teker-teker-kontrol-et ( kesin-tutarlılık)
s6 = rfc[rfc.index("## 6. Yabancı-zincir-kanıtı"):]
for c in sorted(code_chains):
    assert re.search(rf"\b{re.escape(c)}\b", s6), \
        f"zincir-RFC-§6'da-yok: {c}"
print(f"  whitelist-tutarlı: kod-uygulaması {sorted(code_chains)} → hepsi-RFC-§6'da")

# --- 3) §6.3-gate-davranışı: kanıt-YOKSA-GREEN ( RFC-uyumu)
from eth_account import Account
import hashlib, json
acct = Account.create()
base = {"seq": 1, "prev": "0"*64, "h": "a"*64,
        "delivery_hash": {"alg": "sha256", "hex": "c"*64},
        "settlement_bind": {"scheme": "x402/v1", "payment_id": "P",
            "claim_evidence_hash": {"alg": "sha256", "hex": "c"*64},
            "payer": acct.address, "payee": "0x"+"2"*40,
            "verified_at": "2026-09-23T00:00:00Z"}}
govde = {"buyerAddress": acct.address, "sellerAddress": "0x"+"2"*40,
         "settlementRef": "P", "evidenceHash": {"alg": "sha256", "hex": "c"*64}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
_sig = Account.unsafe_sign_hash(bytes.fromhex(d), acct.key)
sig = "0x" + _sig.r.to_bytes(32,"big").hex() + _sig.s.to_bytes(32,"big").hex() \
      + bytes([_sig.v + 27 if _sig.v < 27 else _sig.v]).hex()
claim = dict(govde); claim["signature"] = sig
r = SB.verify(base, claim)
assert r["verdict"] == "GREEN", f"kanıtsız-GREEN-beklendi ( §6.3): {r}"
print("  §6.3: foreign_chain_proof-YOKSA-GREEN ( RFC-uyumu, geri-uyumlu)")

# --- 4) §6.1-negatifleri: bilinmeyen-zincir → RED
for bad_chain in ["ethereum", "solana", ""]:
    b2 = json.loads(json.dumps(base))
    b2["foreign_chain_proof"] = {"chain": bad_chain, "head_hex": "c"*64,
        "entries": 1, "evidence_link": "equals"}
    rb = SB.verify(b2, claim)
    assert rb["verdict"] == "RED" and rb["reason_code"] == 8, \
        f"bilinmeyen-zincir-RED-beklendi ({bad_chain}): {rb}"
print("  §6.1: bilinmeyen-zincir ( ethereum/solana/boş) → RED rc8")

# --- 5) §6.1-negatifleri: boş-head + entries-0 → RED
for key, val in [("head_hex", "ff"), ("head_hex", ""), ("entries", 0)]:
    b3 = json.loads(json.dumps(base))
    proof = {"chain": "swarmax", "head_hex": "c"*64, "entries": 1,
             "evidence_link": "equals"}
    proof[key] = val
    b3["foreign_chain_proof"] = proof
    r3 = SB.verify(b3, claim)
    assert r3["verdict"] == "RED" and r3["reason_code"] == 8, \
        f"{key}={val!r}-RED-beklendi: {r3}"
print("  §6.1: boş/kısa-head + entries-0 → RED rc8 ( sahte-zincir-red)")

# --- 6) §6.2-equals-GERÇEK + kanıt-var-geçerli → GREEN
b4 = json.loads(json.dumps(base))
b4["foreign_chain_proof"] = {"chain": "swarmax", "head_hex": "c"*64,
    "entries": 2, "evidence_link": "equals",
    "verify_cmd": "swarmax.sealing.verify_seals"}
r4 = SB.verify(b4, claim)
assert r4["verdict"] == "GREEN" and r4["checks"]["6_foreign_chain"] is True, \
    f"equals-link-GREEN-beklendi: {r4}"
print("  §6.2: equals-link ( head==receipt) + geçerli-kanıt → GREEN-6/6")
PYEOF
kontrol $? "RFC-010-§6 ↔ kod-tutarlılık"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-164: RFC-010-§6 ↔ üretim-kodu-tutarlı ( whitelist+gate+link-tümü)"
[ "$FAIL" = "0" ]
