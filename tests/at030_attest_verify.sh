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

# 1) golden-vektör bağımsız-koşumu (7 vektör; referans-hükümle birebir)
python3 -m tamga_attest_verify --vectors tests/vendor-capacity-attest/golden-vectors.json > "$D/vectors.out" 2>&1
[ $? -eq 0 ] && grep -q "7/7" "$D/vectors.out" && ! grep -q Traceback "$D/vectors.out"
ok $? "AT-030 fixture: 7/7 bağımsız-koşum uyuştu (5-GREEN + forged/tampered negatif-hükümleri)"

# 2) üretim claim (vendored tek-satır-jsonl; referans-hükmü OLMADAN): GREEN + signer==buyer
head -1 tests/vendor-capacity-attest/production-claim.jsonl > "$D/prod1.json"
python3 -m tamga_attest_verify "$D/prod1.json" > "$D/prod.out" 2>&1; RC=$?
[ $RC -eq 0 ] && grep -q '"verdict": "GREEN"' "$D/prod.out"
ok $? "AT-030 üretim-claim: bağımsız-GREEN (nested-object preimage derin-sıralamada)"

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
