#!/usr/bin/env bash
# at034_zero_digest_counter.sh — reddin-önce-hash-olmadığını SAYAÇLA kanıtla (kontrol-56).
# Dış doğum yeri: giskard09'ün argentum doğrulayıcısı RED üretirken hashlib.sha256'ya hiç
# dokunmadığını sayaç-sarmasıyla iddia ediyor (T1b'de kabul ettiğimiz boyut). Bu kontrol aynı
# iddiayı KENDİ dış-lane'imize çevirir: yapısal-olarak-hash-öncesi-mümkün-olan-her-red gerçekten
# sıfır-hash'la olur; hash-GEREKTİREN red/yeşil yollarında sayaç tam-beklenen-değeri taşır
# (iki-yönlü: ne erken-hash, ne gereksiz-hash).
set -u
cd "$(dirname "$0")/.."
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
R=0
python3 - "$D" >"$D/out" 2>&1 <<'PY' || R=1
import hashlib, json, sys, io, contextlib
D = sys.argv[1]
calls = 0
_orig = hashlib.sha256
def counting(*a, **k):
    global calls
    calls += 1
    return _orig(*a, **k)
hashlib.sha256 = counting
import tamga_attest_verify as av

def run(fn):
    global calls
    calls = 0
    r = fn()
    return calls, r

# K1 zarf-eksik → RED, SIFIR-hash (yapısal-kanıt: satır-127 return, satır-130'a gelmeden)
c, (ok, reason, _) = run(lambda: av.verify_capacity_attest({"claimId": "0x00"}))
assert c == 0 and not ok and reason.startswith("zarf-eksik"), (c, ok, reason)
print("K1 zarf-eksik: 0-hash RED ✓")

# K2 bozuk-JSON konsol-yolu → rc1, SIFIR-hash
open(f"{D}/bozuk.json", "w").write("{olmayan json,,")
c, rc = run(lambda: av.main([f"{D}/bozuk.json"]))
assert c == 0 and rc == 1, (c, rc)
print("K2 bozuk-JSON: 0-hash rc1 ✓")

# K3 unknown-registry → rc2 İNDETERMİNE, SIFIR-hash (sonuç-esirgemeyen-nesil dahil!)
good = json.loads(open("tests/vendor-capacity-attest/production-claim.jsonl").readline())
open(f"{D}/iyi.json", "w").write(json.dumps(good))
c, rc = run(lambda: av.main([f"{D}/iyi.json", "--registry", "BİLİNMEYEN_X9"]))
assert c == 0 and rc == 2, (c, rc)
print("K3 unknown-registry: 0-hash rc2 ✓")

# K4 YEŞİL tam-yol → tam-olay-sayaç = 1 (yalnız claimId-derivasyonu; keccak saf-Python, hashlib'sız)
c, (ok, reason, _) = run(lambda: av.verify_capacity_attest(good))
assert ok and c == 1, (c, ok, reason)
print("K4 üretim-claim GREEN: tam-1-hash ✓ (gereksiz-ikinci-hash yok)")

# K5 claimId-tamper → RED, sayaç TAM 1: bu-red-hash-İSTER (iddia: mümkün-olan-önce-refusal;
#    mümkün-olmayanda-şişirme-değil-tam-kullanım)
t = dict(good); t["claimId"] = "0x" + "ab" * 32
c, (ok, reason, _) = run(lambda: av.verify_capacity_attest(t))
assert not ok and reason == "claimId_mismatch" and c == 1, (c, ok, reason)
print("K5 claimId-tamper: tam-1-hash RED ✓ (iki-yönlü-assert)")
PY
RC=$?
[ $RC -ne 0 ] && { cat "$D/out"; exit 1; }
cat "$D/out"
[ $R -eq 0 ] && echo "AT-034 zero-digest-counter: 5/5 PASS" || { echo "AT-034 FAIL"; exit 1; }
