#!/usr/bin/env bash
# AT-030 — DIŞ delivery-attestation doğrulayıcısı (tamga_attest_verify / `tamga attest-verify`).
# Kanon: offline-deterministik. İki-kanıt-kaynağı vendored: (1) capacity-attest@0.6.0 fixture
# vektörleri — referans-hükmü ONLARIN ethers-uygulamasından (bu-makinede-koşturuldu, 2026-09-15);
# (2) gerçek üretim claim'i (holistis/tokenizen data-selftest) — referans-hükmü OLMADAN.
# Bizim-modül saf-python (secp256k1+EIP-191+canonical-JSON; stdlib-only) aynı-hükmü KENDİ
# başına üretmek zorunda: 7/7 uyuşma + üretim-claim GREEN. Negatifler: unknown-registry →
# rc2 İNDETERMİNE (RFC-009 foreign_registry-deseni), bozuk-JSON → mesajlı-RED, sıfır-arg → rc1.
set -u
cd "$(dirname "$0")/.."
D=".evidence/AT-030/$(date +%F)"; mkdir -p "$D"; LOG="$D/at030.log"
PASS=0; FAIL=0
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }

# 0) corpus sha-pin DENETİMİ: üç-dosyanın-kendi-bütünlüğü, VENDOR-NOTE'taki-pinlerle-kapanır-bağ
#    (beklenen-değerler-note'ta-YAZILI-olsa-da buraya-SABİT-GÖMÜLÜ: note'a-yazılan-pin-ometadadır,
#    kontrolün-doğruladığı-dataolmalıdır — kendini-doğrulayan-not asla kanıt değildir)
for pair in "1f88e843545e6be640eadea4df8b470fe5d04dd1b47a32c4cc753341e22a8ddd golden-vectors.json" \
            "2c6292a296a5d9feef4ea2f301968523488f0a95621fc4a94ce770b66f38cf5c production-claim.jsonl" \
            "b8dae2d9ea4b83ef6b0a85ecf56a46b23d18584f2eb731f197c19caeb6b6ee74 completeness-claims.jsonl"; do
  set -- $pair
  echo "$1  tests/vendor-capacity-attest/$2" | sha256sum -c --status || { echo "  corpus-pin İHLALİ: $2"; exit 1; }
done

# 1) golden-vektör bağımsız-koşumu (7 vektör; referans-hükümle birebir)
python3 -m tamga_attest_verify --vectors tests/vendor-capacity-attest/golden-vectors.json > "$D/vectors.out" 2>&1
[ $? -eq 0 ] && grep -q "7/7" "$D/vectors.out" && ! grep -q Traceback "$D/vectors.out"
ok $? "AT-030 fixture: 7/7 bağımsız-koşum uyuştu (5-GREEN + forged/tampered negatif-hükümleri)"

# 2) üretim claim (vendored tek-satır-jsonl; referans-hükmü OLMADAN): GREEN + signer==buyer
head -1 tests/vendor-capacity-attest/production-claim.jsonl > "$D/prod1.json"
python3 -m tamga_attest_verify "$D/prod1.json" > "$D/prod.out" 2>&1; RC=$?
[ $RC -eq 0 ] && grep -q '"verdict": "GREEN"' "$D/prod.out"
ok $? "AT-030 üretim-claim: bağımsız-GREEN (nested-object preimage derin-sıralamada)"

# 2b) completeness-fixture üretimi 8 claim (taze-imzalı-vektör-olmayan-set; sha-pin; satır-sabit)
sha256sum tests/vendor-capacity-attest/completeness-claims.jsonl | grep -q "^b8dae2d9ea4b83ef" \
  && [ "$(python3 - <<'PY'
import json, hashlib, sys
sys.path.insert(0, ".")
from tamga_attest_verify import _canonical_preimage, verify_capacity_attest
n = g = 0
for line in open("tests/vendor-capacity-attest/completeness-claims.jsonl"):
    c = json.loads(line); n += 1
    okid, reason, _ = verify_capacity_attest(c)
    # claimId öz-tutarlılık: preimage→sha256 == claim.claimId
    cid = "0x" + hashlib.sha256(_canonical_preimage(c)).hexdigest()
    g += bool(okid) and cid == c.get("claimId")
print(f"{g}/{n}")
PY
)" = "8/8" ]
ok $? "AT-030 completeness-set: 8/8 GREEN + claimId öz-tutarlı (üreticinin-canlı-imza-yolunda, sabit-vektör-değil)"

# 3) unknown-registry → İNDETERMİNE rc2 (sonuç-esirgeme; RFC-009-desen)
head -1 tests/vendor-capacity-attest/production-claim.jsonl > "$D/u.json"
python3 -m tamga_attest_verify "$D/u.json" --registry HOLISTIS_X9 > "$D/unk.out" 2>&1
[ $? -eq 2 ] && grep -q "İNDETERMİNE" "$D/unk.out"
ok $? "AT-030 unknown-registry → rc2 İNDETERMİNE ('yokluk-değil' satırıyla)"

# 4) bozuk-JSON → mesajlı-RED rc1 (bakamadım-değil: girdi-bozuk)
printf '{"bozuk":' > "$D/broken.json"
python3 -m tamga_attest_verify "$D/broken.json" > "$D/brk.out" 2>&1
[ $? -eq 1 ] && grep -q "bozuk-JSON" "$D/brk.out" && ! grep -q Traceback "$D/brk.out"
ok $? "AT-030 bozuk-JSON → mesajlı-RED (traceback-yok)"

# 5) konsol-yolu (bootstrap): sıfır-arg → kullanim rc1 — E-14 ailesi
python3 tamga_bootstrap.py attest-verify > "$D/zero.out" 2>&1
[ $? -eq 1 ] && grep -q "kullanim" "$D/zero.out"
ok $? "AT-030 konsol sıfır-arg → kullanım-RED (E-14 ailesi)"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]
