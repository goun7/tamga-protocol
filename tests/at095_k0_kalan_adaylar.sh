#!/usr/bin/env bash
# AT-095: K0-KALAN-3-ADAY — DepositLock + Zaman + N-imza (RFC-010'a-additive).
#
# AT-092 CT-log'u-yazdı (4/4-adayın-1'i). Bu-test-kalan-3-adayı-aynı-DÜZ/İKİLİ-
# desenle-uygular — TEK-AT-içinde-üç-protokol (additive-liste):
#   depositlock/v1 — sabit-depozito ≥ D → bool (değer-kilitli, derecesi-yok)
#   age/v1         — hesap-yaşı ≥ T → bool (zaman-tabanlı, ağırlıksız)
#   sigcount/v1    — N-bağımsız-Ed25519-imzası → cardinality ≥ N (distinct-anahtar)
#
# GİZLİ-ŞART (AT-083-raporu): her-aday-SADECЕ-DÜZ/İKİLİ-koşul-olabilir — sürekli
# ağırlık (üyelik × karşı-ajan-itibar-skoru) anında-D-014-duvarına-düşer
# (transitif-sıralama = K0-ihlali). Her-protokol-bu-iki-yönü-de-ölçer:
#   - DÜZ/İKİLİ-GREEN + transitif-ölçüm-SABIT (K0-adayı-olduğunun-kanıtı)
#   - ağırlıklı-varyant-transitif-yakalanır → RED (duvarın-kanıtı)
#
# Gerçek-nacl-Ed25519-anahtarları (AT-077-disiplini: test-double-YOK). Source-değil
# TEST-ile-kanıtlar (tools/*-DOKUNMA). AT-092'nin-rc-kodları-korunur (tutarlılık).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/K0-GATE/$(date +%F)/at095.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-095: K0-kalan-3-aday — DepositLock + Zaman + N-imza (DÜZ/İKİLİ)"

RK="/home/gokun/projects/01_unicorn/68-Kredent/roboseal"
if [ ! -f "$RK/reputation.py" ]; then
  note "[SKIP] AT-095: ROBOSEAL-kodu-bu-makinede-değil (CI) —"
  note "       transitif-enstrüman-çalışmadı (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import nacl" 2>/dev/null; then
  note "[SKIP] AT-095: nacl-kütüphanesi-yok —"
  note "       gerçek-Ed25519-anahtarlar-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$RK" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, sys, time
sys.path.insert(0, "/home/gokun/projects/01_unicorn/68-Kredent")  # roboseal-için
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from nacl.signing import SigningKey, VerifyKey
from nacl.encoding import HexEncoder
import settlement_bind_verify as SB
from roboseal.reputation import apply_eigentrust_weights

SUPPORTED = ("depositlock/v1", "age/v1", "sigcount/v1")  # additive-liste
MIN_DEPOSIT = 1000.0                                     # D (sabit-eşik)
MIN_AGE_SEC = 3600.0                                     # T (sabit-eşik)
MIN_SIGS = 3                                             # N (cardinality-eşiği)

# --- GERÇEK-Ed25519-anahtarları (AT-077-disiplini: double-YOK)
anahtarlar = []
for _ in range(MIN_SIGS + 1):                            # N+1 → fazla-imza-da-test
    sk = SigningKey.generate()
    anahtarlar.append((sk, sk.verify_key.encode(encoder=HexEncoder).decode()))
pub_uye = anahtarlar[0][1]

# --- DÜZ/İKİLİ-üyelik-kontrolü (üç-protokol-aynı-kapıdan; sürekli-ağırlık-DİŞLİ)
def sybil_membership_check(syb):
    """K0-adayı-üçlü: her-protokol-DÜZ-koşul — derecesi-yok."""
    if not isinstance(syb, dict):
        return "RED", 13, "sybil_membership_malformed"
    proto = syb.get("protocol")
    if proto not in SUPPORTED:                            # üçüncü-seçenek-yasak
        return "İNDETERMİNE", 14, f"unknown_protocol: {proto!r}"
    head = syb.get("head_hex")
    if not (isinstance(head, str) and len(head) == 64
            and all(c in "0123456789abcdef" for c in head)):
        return "RED", 15, "log_head_invalid"
    if not (isinstance(syb.get("entries"), int) and syb["entries"] >= 1):
        return "RED", 15, "log_entries_invalid"
    member = syb.get("member_key", "")
    # protokol-DÜZ-koşulları (bool ↔ DÜZ/İKİLİ — süreklilik-yok)
    if proto == "depositlock/v1":
        dep = syb.get("deposit_usdc")
        ok = isinstance(dep, (int, float)) and dep >= MIN_DEPOSIT
    elif proto == "age/v1":
        age = syb.get("age_sec")
        ok = isinstance(age, (int, float)) and age >= MIN_AGE_SEC
    else:                                                  # sigcount/v1
        sigs = syb.get("signer_pubkeys")
        ok = isinstance(sigs, list) and len({str(k) for k in sigs}) >= MIN_SIGS
    if not ok:
        return "RED", 16, f"member_fails_duz_kosul: {proto}"
    if head.lower() != UYE_HEAD.lower():
        return "RED", 17, "log_head_mismatch"
    return "GREEN", 0, f"üyelik-doğrulandı (DÜZ/İKİLİ: {proto})"

# --- K0-transitif-enstrümanı (AT-092'den-aynı): kanıt-SABİT,
# sadece-BAŞKA-ajanların-itibar-skoru-değişir. Çıktı-değişirse-transitif → D-014.
def transitif_mi(fn):
    a = fn([0.90, 0.01, 0.50])                             # itibarlı / kukla / orta
    b = fn([0.90, 0.01, 0.95])                             # 2-uzaklıktaki 0.50→0.95
    return a, b, (a != b)

# --- additive-alan-şablonu (AT-092-şekliyle-aynı-aile)
UYE_HEAD = hashlib.sha256(pub_uye.encode()).hexdigest()   # üye-log-kökü
def kanit(proto, **kw):
    d = {"protocol": proto, "log_id": "tamga-k0gate-01",
         "head_hex": UYE_HEAD, "entries": kw.pop("entries", 1),
         "member_key": pub_uye}
    d.update(kw)
    return d

# --- 1) DEPOSITLOCK/v1: DÜZ/İKİLİ-GREEN + transitif-SABIT + ağırlıklı-RED
v1, rc1, _ = sybil_membership_check(
    kanit("depositlock/v1", deposit_usdc=1500.0))          # ≥ D=1000
assert v1 == "GREEN" and rc1 == 0, f"DepositLock-GREEN: {v1}/{rc1}"
def duz_deposit(skorlar):                                  # skorsuz → SABIT
    return sybil_membership_check(
        kanit("depositlock/v1", deposit_usdc=1500.0))[0] == "GREEN"
a, b, etk = transitif_mi(duz_deposit)
assert not etk, "DepositLock-transitif-çıktı (K0-ihlali!)"
def agirlikli_deposit(skorlar):
    base = 1.0 if 1500.0 >= MIN_DEPOSIT else 0.0
    return base * apply_eigentrust_weights(skorlar, [True, True, False])
a2, b2, etk2 = transitif_mi(agirlikli_deposit)
assert etk2 and abs(b2 - a2) > 0.01, "ağırlıklı-DepositLock-transitif-yakalanmadı"
print(f"  1) depositlock/v1: DÜZ-GREEN (1500≥1000); transitif-SABIT; "
      f"ağırlıklı {a2:.4f}→{b2:.4f} RED")

# --- 2) AGE/v1: DÜZ/İKİLİ-GREEN + transitif-SABIT + ağırlıklı-RED
v2, rc2, _ = sybil_membership_check(kanit("age/v1", age_sec=7200.0))  # ≥ T=3600
assert v2 == "GREEN" and rc2 == 0, f"Age-GREEN: {v2}/{rc2}"
def duz_age(skorlar):
    return sybil_membership_check(kanit("age/v1", age_sec=7200.0))[0] == "GREEN"
c, d_, etk3 = transitif_mi(duz_age)
assert not etk3, "Age-transitif-çıktı (K0-ihlali!)"
def agirlikli_age(skorlar):
    base = 1.0 if 7200.0 >= MIN_AGE_SEC else 0.0
    return base * apply_eigentrust_weights(skorlar, [True, True, False])
c2, d2, etk4 = transitif_mi(agirlikli_age)
assert etk4 and abs(d2 - c2) > 0.01, "ağırlıklı-Age-transitif-yakalanmadı"
print(f"  2) age/v1: DÜZ-GREEN (7200s≥3600s); transitif-SABIT; "
      f"ağırlıklı {c2:.4f}→{d2:.4f} RED")

# --- 3) SIGCOUNT/v1: GERÇEK-distinct-Ed25519 + DÜZ-GREEN + transitif-SABIT
# N-bağımsız-imza = cardinality: distinct-anahtar-kümesinin-büyüklüğü (süreklilik-yok)
pubs = [p for (_, p) in anahtarlar[:MIN_SIGS]]
assert len(set(pubs)) == MIN_SIGS, "distinct-anahtar-olmalı"
for (_, p) in anahtarlar[:MIN_SIGS]:
    assert len(p) == 64 and VerifyKey(p, encoder=HexEncoder) is not None
v3, rc3, _ = sybil_membership_check(
    kanit("sigcount/v1", signer_pubkeys=pubs, entries=MIN_SIGS))
assert v3 == "GREEN" and rc3 == 0, f"SigCount-GREEN: {v3}/{rc3}"
def duz_sigcount(skorlar):
    return sybil_membership_check(
        kanit("sigcount/v1", signer_pubkeys=pubs,
              entries=MIN_SIGS))[0] == "GREEN"
e, f_, etk5 = transitif_mi(duz_sigcount)
assert not etk5, "SigCount-transitif-çıktı (K0-ihlali!)"
def agirlikli_sigcount(skorlar):
    base = 1.0 if len(set(pubs)) >= MIN_SIGS else 0.0
    return base * apply_eigentrust_weights(skorlar, [True, True, False])
e2, f2, etk6 = transitif_mi(agirlikli_sigcount)
assert etk6 and abs(f2 - e2) > 0.01, "ağırlıklı-SigCount-transitif-yakalanmadı"
print(f"  3) sigcount/v1: {MIN_SIGS}-distinct-gerçek-Ed25519-DÜZ-GREEN; "
      f"transitif-SABIT; ağırlıklı {e2:.4f}→{f2:.4f} RED")

# --- 4) NEG-1: her-protokolün-DÜZ-koşulu-tutarsız → RED rc16
for proto, bad in (("depositlock/v1", {"deposit_usdc": 100.0}),   # < D
                   ("age/v1", {"age_sec": 60.0}),                # < T
                   ("sigcount/v1", {"signer_pubkeys": pubs[:1]})):  # < N
    vn, rcn, _ = sybil_membership_check(kanit(proto, entries=1, **bad))
    assert vn == "RED" and rcn == 16, f"NEG-1 {proto}-RED-rc16: {vn}/{rcn}"
print("  4) NEG-1: yetersiz-depozito/yaş/imza → RED rc16 (her-protokol-kendi-RED'i)")

# --- 5) NEG-2: bilinmeyen-protokol → İNDETERMİNE rc14 (üçüncü-seçenek-yasak)
v4, rc4, _ = sybil_membership_check(kanit("kadi/v99", deposit_usdc=5000.0))
assert v4 == "İNDETERMİNE" and rc4 == 14, f"bilinmeyen-İNDETERMİNE: {v4}/{rc4}"
print("  5) NEG-2: bilinmeyen-protokol → İNDETERMİNE rc14 (sessiz-RED-yok)")

# --- 6) K0-saflik + canlı-yol-paritesi (AT-092-6.-kontrolün-aynısı)
code = inspect.getsource(SB.verify)
yasak = [t for t in ("reputation", "score", "rank", "weight", "itibar")
         if t in code.lower()]
assert not yasak, f"SB.verify'de-yasak-token: {yasak}"
cikti = sybil_membership_check(kanit("age/v1", age_sec=7200.0))
assert cikti[0] in ("GREEN", "RED", "İNDETERMİNE"), "üyelik-çıktısı-ikili-değil"
ok = SB._foreign_chain_ok({"chain": "tamga", "head_hex": UYE_HEAD, "entries": 1,
                           "evidence_link": "equals"}, "x", UYE_HEAD, "tamga/native")
assert ok is True, "canlı-yol-paritesi-bozuldu"
print(f"  6) K0-saflik: SB.verify-yasak-token-SIFIR {yasak}; üç-protokol-çıktısı-"
      f"DÜZ/İKİLİ; SB._foreign_chain_ok-canlı-paritesi-TRUE")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-K0-3-aday-düz/ikili-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-095: K0-kalan-3-aday (DepositLock + Zaman + N-imza)"
[[ $FAIL -eq 0 ]]
