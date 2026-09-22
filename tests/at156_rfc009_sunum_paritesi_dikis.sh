#!/usr/bin/env bash
# AT-156: RFC-009-SUNUM-PARİTESİ-uzmanlaşması → RFC-010'a-bağlama-dikişi
# ( AT-145'in-keşfinin-devamı: composition_vector'ın-RFC-009-Merkle-yüzü).
#
# LEAD'İN-TALİMATI: " composition_vector'ın-ürettiği-kök → RFC-010-evidenceHash.
# §6-chain='tamga'-AMA-evidence_link='derived'-olabilir ( kompozisyon-kökü-tek-bir-
# zincir-head'i-DEĞİL-çok-yapraklı-özet). DİKKAT: derived-link-gerçekten-
# doğrulanabilir-olmalı ( §6-tanım: head == sha256( kanıt-türevi)) —
# türetilemiyorsa-İNDETERMİNE. NEG: rc4 + rc7 + yaprak-değişimi→kök-değişir."
#
# ARAŞTIRMA-SONUCU ( iki-bulgulu-dürüst-rapor — Lead'in-uyarısı-doğru-çıktı):
#
# BULGU-1 ( NEGATİF): derived-link-GERÇEK-BAĞLANAMAZ — türetme-halkası-YOK.
#   §6-derived: head == sha256( bytes.fromhex( receipt_hex)). Kompozisyon-kökü
#   keccak-tabanlı-OZ-StandardMerkleTree'dir ( feuille = k256(k256(bytes32)));
#   sha256( receipt) hiçbir-zaman-kompozisyon-köküne-eşit-olamaz ( ölçüldü:
#   sha256(comp-root)≠comp-root; sha256(tamga-head)≠comp-root). Yani-derived-
#   kuralı-uygulanabilir-AMA-anlamsız — receipt'in-özütü-kompozisyon-yapraklarına
#   kriptografik-bağlanmaz. SAĞLAM-çözüm: derived-DEĞİL, RFC-010'a-MİROR-değil.
#
# BULGU-2 ( ANA-BAĞLAMA): equals-link-GERÇEK-bağ-kuruldu — receipt-hash'i
#   kompozisyon-köküne-BAYT-EŞİTlenir → RFC-010-GREEN-6/6. ANCAK-dürüst-sınır:
#   bu-bağda-head_hex bir Merkle-köküdür ( tek-zincir-head'i-DEĞİL) — §6'nın-
#   chain:'tamga'-adı-altında-zincir-head-sunumu-yerine, RFC-010-KONTROL-5
#   ( evidenceHash == delivery_hash) semantiğine-uygun. Test-ikisini-de-ölçer:
#   (a) derived-uyumsuzluk ( gerçek-türetme-yok)
#   (b) equals-GERÇEK-bağ → GREEN ( §6-equals + kontrol-5-bayt-eşit)
#   (c) izdüşüm-paritesi: tamga-head → feuille → batch'te-gerçekten-var
#       ( AT-145-iddia-1-canlı: 57-yaprak, fact-position)
#
# Yedi-kanıt + 3-negatif:
#   1) fixture-üretim-paritesi: composition_vector-çalışır → 57-yaprak-kök-eşleşmesi
#   2) derived-uyumsuzluk: sha256( receipt) ≠ comp-root ( keccak-yapı-ölçümü)
#   3) equals-GERÇEK-bağ: RFC-010-GREEN ( 6/6; §6-tamga-equals; kontrol-5)
#   4) izdüşüm-paritesi: feuille( tamga-head) batch'in-57-yaprağında-gerçekten-var
#   5) yaprak-değişimi → kök-değişir ( Merkle-tek-yönlülük)
#   N1) sahte-imza → rc4
#   N2) evidenceHash-swap → rc7
#   N3) yaprak-değişimi-sonrası-eski-charge → rc7 ( fail-closed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/RFC009-SUNUM-PARITESI/$(date +%F)/at156.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-156: RFC-009-sunum-paritesi → RFC-010-bağlama (derived-uyumsuz + equals-GERÇEK)"

VEK="tests/vectors/anchor-v0-design/composition_vector.py"
if [ ! -f "$VEK" ]; then
  note "[SKIP] AT-156: composition_vector.py-bu-makinede-değil (CI) —"
  note "       RFC-009-yüzü-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-156: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, importlib.util, json, os, subprocess, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

# --- 1) FIXTURE-ÜRETİM-PARİTESİ ( modül-gerçek-çalışır)
rc = subprocess.run([sys.executable, "tests/vectors/anchor-v0-design/composition_vector.py"],
                    capture_output=True, text=True)
assert rc.returncode == 0, f"composition_vector-çalışmadı: {rc.stderr[-300:]}"
fx = json.loads(open("tests/vectors/anchor-v0-design/composition-fixture.json").read())
cc = fx["cross_check"]
assert cc["epoch_10_root_match"] is True, "57-yaprak-kök-eşleşmedi"
assert cc["fact_leaf_present"] is True, "fact-yaprağı-batch'te-yok"
comp_root_66 = fx["composition"]["composition_root"]
comp_root = comp_root_66[2:]                    # 64hex ( §6-head_hex-alanı)
tamga_head = fx["tamga_chain_head"]
pos = cc["fact_position"]
print(f"  fixture-üretim: 57-yaprak-kök-EŞLEŞTİ; comp-root={comp_root[:16]}…; "
          f"tamga-head={tamga_head[:16]}…; fact-position={pos}")

# --- 2) DERIVED-UYUMSUZLUK ( türetme-halkası-YOK — dürüst-ölçüm)
for ad, hexp in (("comp-root", comp_root), ("tamga-head", tamga_head)):
    turev = hashlib.sha256(bytes.fromhex(hexp)).hexdigest()
    assert turev != comp_root, f"sha256({ad})-tesadüfen-comp-root'a-eşit ( imkânsız-olmalı)"
# kompozisyon-yaprak-kodlaması-keccak'tır ( sha256-değil) — yapısal-uyumsuzluk:
yaprak_kod = fx["leaf_encoding"]
assert "keccak256" in yaprak_kod, "yaprak-kodlaması-keccak-değil ( beklenmedik)"
print("  derived-UYUMSUZ: sha256(receipt)≠comp-root ( keccak-Merkle-yapısı); "
          "§6-derived-gerçek-türetme-halkası-YOK → BAĞLANAMAZ (Lead-uyarısı-doğru)")

# --- 3) EQUALS-GERÇEK-BAĞ: RFC-010-GREEN ( §6-tamga-equals + kontrol-5-bayt-eşit)
def _govid(head_hex):
    b = ek.PrivateKey(os.urandom(32))
    a = to_checksum_address(b.public_key.to_address())
    g = {"buyerAddress": a, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "RFC009-COMP-156",
         "evidenceHash": {"alg": "sha256", "hex": head_hex}}
    d = hashlib.sha256(json.dumps(g, sort_keys=True).encode()).hexdigest()
    s = b.sign_msg_hash(bytes.fromhex(d)).to_hex()
    c = dict(g); c["signature"] = s
    return b, a, g, c
BUYER, ADDR, govde, claim = _govid(comp_root)
dg = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
charge = {"seq": 3, "prev": "0" * 64, "h": comp_root,
          "delivery_hash": {"alg": "sha256", "hex": comp_root},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "RFC009-COMP-156",
                              "claim_evidence_hash": {"alg": "sha256", "hex": dg},
                              "payer": ADDR, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": comp_root,
                                  "entries": 57, "evidence_link": "equals",
                                  "verify_cmd": "composition_vector: oz_root"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"equals-bağ-GREEN-beklendi: {r}"
for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
          "5_evidence_hash", "6_foreign_chain"):
    assert r["checks"].get(k) is True, f"{k}-geçmedi: {r}"
print("  equals-GERÇEK-bağ: RFC-010-GREEN ( 6/6; §6-tamga-equals; "
          "kontrol-5-bayt-eşit — RFC-009-kökü-receipt-hash'ine-bağlandı)")

# --- 4) İZDÜŞÜM-PARİTESİ: tamga-head → feuille → kompozisyon-batch'inde-GERÇEK-VAR
#     ( modülün-akışı: orijinal-57-batch'te-FACT-yaprağı-var; kompozisyon-adımı
#      o-yaprağı-tamga-head-izdüşümüyle-DEĞİŞTİRİR)
spec = importlib.util.spec_from_file_location(
    "cv", "tests/vectors/anchor-v0-design/composition_vector.py")
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
yaprak_tamga = mod.feuille(tamga_head)
import pathlib
ep = json.loads(open(".evidence/APODIX-EPOCH-10/2026-09-10/epoch-manifest-10.json").read())
batch = [mod.feuille(f) for f in ep["leaves"]]
assert len(batch) == 57, f"57-yaprak-beklendi: {len(batch)}"
# (a) orijinal-kök-bağımsız-teyit ( modülün-kendi-yoluyla)
assert "0x" + mod.oz_root(batch).hex() == ep["root"], "bağımsız-orijinal-kök-eşleşmedi"
# (b) FACT-yaprağı-orijinal-batch'te-gerçekten-var ( fixture-cross-check-canlı)
fp = json.loads(open(".evidence/APODIX-EPOCH-10/2026-09-10/fact-proof.json").read())
assert mod.feuille(fp["fact_hash"]) in batch, "fact-yaprağı-orijinal-batch'te-yok"
# (c) kompozisyon-batch'inde-tamga-head-izdüşümü-POS'ta-var + kök-.fixture'a-eşit
komp = list(batch); komp[pos] = yaprak_tamga
assert komp[pos] == yaprak_tamga
b_kok = "0x" + mod.oz_root(komp).hex()
assert b_kok == comp_root_66, "bağımsız-kompozisyon-kökü-fixture'a-eşleşmedi"
print("  izdüşüm-paritesi: feuille(tamga-head)-kompozisyon-batch'inde-POS'ta-GERÇEK-"
          "VAR; fact-yaprağı-orijinal-57-batch'te; her-iki-kök-bağımsız-doğrulandı "
          "( RFC-009-iddia-1/3-canlı)")

# --- 5) YAPRAK-DEĞİŞİMİ → KÖK-DEĞİŞİR ( Merkle-tek-yönlülük)
b2 = list(batch); b2[pos] = mod.feuille("a" * 64)
yeni_kok = mod.oz_root(b2).hex()
assert yeni_kok != comp_root, "yaprak-değişti-ama-kök-aynı ( Merkle-bozuk)"
print("  yaprak-değişimi → kök-DEĞİŞİR ( Merkle-tek-yönlülük; eski-charge-artık-geçmez)")

# --- N1) sahte-imza → rc4
for sahte in ("ff" * 33, os.urandom(65).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"N1-sahte-imza-rc4-beklendi: {rs}"
print("  N1-sahte-imza ( geçersiz-uzunluk + rastgele-65-byte) → RED rc4")

# --- N2) evidenceHash-swap → rc7
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
c2 = dict(govde2); c2["signature"] = s2
r6 = SB.verify(charge, c2)
assert r6["verdict"] == "RED" and r6["reason_code"] == 7, \
    f"N2-evidenceHash-swap-rc7-beklendi: {r6}"
print("  N2-evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 ( fail-closed)")

# --- N3) yaprak-değişimi-sonrası-eski-charge → rc7 ( eski-kök-artık-geçersiz)
#     ( AYNI-buyer — party-mismatch(rc6)-değil-evidenceHash(rc7)-gelsin)
g3 = {"buyerAddress": ADDR, "sellerAddress": "0x" + "2" * 40,
      "settlementRef": "RFC009-COMP-156",
      "evidenceHash": {"alg": "sha256", "hex": yeni_kok}}
d3 = hashlib.sha256(json.dumps(g3, sort_keys=True).encode()).hexdigest()
s3 = BUYER.sign_msg_hash(bytes.fromhex(d3)).to_hex()
c3 = dict(g3); c3["signature"] = s3
r7 = SB.verify(charge, c3)          # charge-hâlâ-eski-comp-root'ta
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"N3-yaprak-değişimi-sonrası-rc7-beklendi: {r7}"
print("  N3-yaprak-değişimi-sonrası-eski-charge → RED rc7 ( kök-tahriz-edilmiş- "
          "gibi-fail-closed)")
print("  SONUÇ: RFC-009-sunum-paritesi-§6-derived'a-BAĞLANAMAZ (türetme-halkası-yok); "
          "equals-GERÇEK-bağ-GREEN-6/6 ( RFC-010-§5-semantiği)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-RFC-009-sunum-paritesi-dikişi" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-156: RFC-009-sunum-paritesi → RFC-010 (derived-uyumsuz + equals-GERÇEK)"
[[ $FAIL -eq 0 ]]
