#!/usr/bin/env bash
# AT-176: TAMGA-KENDİ-ZİNCİRİ-§6'YA-BAĞLANIR — self-chain-parite
#
# RFC-010-§6-whitelist'i-"tamga"-içerir-AMA hiçbir-test KENDİ-zincirimizi-
# §6'ya-bağlamadı: AT-152-diğer-projeleri-bağladı, AT-159-swarmax'ı, AT-161-
# veridrome'u-bağladı. Bu-test-tamga'nın-kendi-D5-ledger'ının-GREEN-yüzünü
# üretir — head=chain_head( pkg)-GERÇEK-üretim-kökü.
#
# Önemli-parite: head-ve-receiptHash-AYNI-nesne ( equals); ama-bu-çözümsel-
# döngü-DEĞİL: D5-head-prev+seq-ile-hesaplanır, §6-bağı-ONSE-ödemenin-kanıtına
# bağlanır. entries=gerçek-satır-sayısı.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/.evidence/TAMGA-SELF-CHAIN/$(date +%F)/at176.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }

export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
SBX="$(mktemp -d /tmp/at176.XXXXXX)"

python3 - "$SBX" "$ROOT" >> "$LOG" 2>&1 <<'PYEOF'
import sys, json, pathlib, hashlib, subprocess, os
sbx, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
sys.path.insert(0, str(root / "tools"))
sys.path.insert(0, str(root))
import tamga_project_head as th
import settlement_bind_verify as SB
from eth_account import Account

RUNNER = root / "tamga_runner.py"

def sh(*args):
    env = dict(os.environ)
    return subprocess.run([sys.executable, str(RUNNER), *args],
                          cwd=str(sbx), capture_output=True, text=True,
                          env=env)

# --- 1) GERÇEK-üretim-D5-zinciri-oluştur
seed = json.loads(sh("keygen").stdout)["seed_hex"]
sh("quickstart", "pkg", "--name", "at176", "--seed", seed)
sh("run", "pkg", "--seed", seed, "--note", "at176-1")
pkg = sbx / "pkg"

# --- 2) GERÇEK-chain_head ( üretim-kökü) — grant'ten-ÖNCE-okunur
head, lines = th.chain_head(pkg)
assert len(head) == 64 and lines >= 3, f"head-üretim-hatalı: {head!r}/{lines}"
print(f"  1) GERÇEK-D5-chain_head: {head[:24]}… ( {lines}-satır; prev+seq-ile)")

# --- head'i-okuduktan-SONRA-bağımsızlık-için-grant-ekle ( head-değişecek)
sh("grant", "pkg", "0.02", "at176-ikinci-grant", "--seed", seed)

# --- 3) head-öncesi-zincir-KEŞKE-bağlanamaz ( receipts-independent)
# delivery_hash=head-ile-x402-imzala
acct = Account.create()
govde = {"buyerAddress": acct.address, "sellerAddress": "0x"+"2"*40,
         "settlementRef": "AT-176", "evidenceHash": {"alg": "sha256", "hex": head}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
_s = Account.unsafe_sign_hash(bytes.fromhex(d), acct.key)
_v = _s.v if _s.v >= 27 else _s.v + 27
sig = "0x" + _s.r.to_bytes(32,"big").hex() + _s.s.to_bytes(32,"big").hex() \
      + bytes([_v]).hex()
claim = dict(govde); claim["signature"] = sig

def make(chain, head_hex, link="equals", entries=None):
    return {"seq": 176, "prev": "0"*64, "h": "b"*64,
            "delivery_hash": {"alg": "sha256", "hex": head},
            "settlement_bind": {"scheme": "x402/v1", "payment_id": "AT-176",
                "claim_evidence_hash": {"alg": "sha256", "hex": head},
                "payer": acct.address, "payee": "0x"+"2"*40,
                "verified_at": "2026-09-23T00:00:00Z"},
            "foreign_chain_proof": {"chain": chain, "head_hex": head_hex,
                "entries": entries if entries else lines, "evidence_link": link,
                "verify_cmd": "at176-tamga-self"}}

# --- 4) chain:"tamga"-GERÇEK-head → GREEN ( self-chain-parite)
r = SB.verify(make("tamga", head), claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"tamga-self-chain-GREEN-beklendi: {r}"
assert r["checks"]["6_foreign_chain"] is True
print(f"  2) chain:'tamga' + GERÇEK-head → GREEN 6/6 ( whitelist-üyesi-"
      f"olduğu-gibi; ödeme-kanıtı-üretim-zincirine-bağlanır)")

# --- 5) NEG-1: sahte-head ( gerçek-olmayan-kök) → RED rc8
r = SB.verify(make("tamga", "e"*64), claim)
assert r["verdict"] == "RED" and r["reason_code"] == 8, \
    f"sahte-tamga-head-RED-beklendi: {r}"
print("  3) NEG-1: chain:'tamga' + sahte-head → RED rc8 ( sahte-kök-geçmez)")

# --- 6) NEG-2: whitelist-dışı-zincir-adı → RED rc8
r = SB.verify(make("unknown-chain", head), claim)
assert r["verdict"] == "RED" and r["reason_code"] == 8, \
    f"whitelist-dışı-RED-beklendi: {r}"
print("  4) NEG-2: whitelist-dışı-zincir → RED rc8 ( §6.1-beyaz-liste-gerçek)")

# --- 7) head-BAĞIMSIZ: grant-ekle → head-DEĞİŞİR-AMA-receiptHash-AYNI
# ( zincir-özü-ile-ödeme-özü-bağımsız; AT-158-kanıtı-ile-tutarlı)
h2, lines2 = th.chain_head(pkg)
assert h2 != head, "grant-head'i-değiştirmedi"
r2 = SB.verify(make("tamga", h2, entries=lines2), claim)
assert r2["verdict"] == "RED" and r2["reason_code"] == 8, \
    f"eski-receipt-yeni-head-RED-beklendi: {r2}"
print(f"  5) head-bağımsızlığı: grant-head'i-değiştirdi ( {head[:10]}…→"
      f"{h2[:10]}…) → eski-receiptHash-artık-uyuşmaz ( RED rc8)")
print("     → zincir-özü-ödeme-özünden-bağımsız ( AT-158-tutarlı)")
PYEOF
kontrol $? "AT-176: tamga-self-chain-§6-parite"

rm -rf "$SBX"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-176: tamga-D5-zinciri-§6'ya-bağlanır ( 2-kanıt + 2-negatif)"
[ "$FAIL" = "0" ]
