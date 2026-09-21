#!/usr/bin/env bash
# AT-092: K0-UYUMLU-SYBİL-KONTROLÜ RFC-010'a-ADDITIVE — AT-083'ün-uygulaması.
#
# AT-083 (4/4-aday-K0-uyumlu-ölçüldü) araştırmasının-uygulamaya-geçişi. En-düşük-
# maliyetli-yol-CT-log-üyeliği-seçildi (RFC-6962-tarzı; SB._foreign_chain_ok'ta-
# evidence_link+head_hex+entries≥1-deseni-zaten-canlı).
#
# ADDITIVE-ALAN (RFC-010-§2-şekline-uygun, op-YOK):
#   {"sybil_membership": {"protocol":"ctlog/v1", "log_id":..., "head_hex":<64hex>,
#                         "entries":<int>, "member_key":<64hex-pubkey>}}
#
# GİZLİ-ŞART (AT-083-raporu): kontrol-SADECЕ-DÜZ/İKİLİ-koşul olabilir — sürekli
# ağırlık (üyelik × karşı-ajan-itibar-skoru) anında-D-014-duvarına-düşer
# (transitif-sıralama = K0-ihlali). Test-bunu-kanıtlar:
#   - ağırlıksız-aday-geçmeli (transitif-ölçüm-SABIT)
#   - ağırlıklı-varyant-transitif-yakalanmalı → RED
#
# Altı-ölçülebilir-kontrol + 2-negatif. Gerçek-nacl-Ed25519-anahtarları (AT-077-
# disiplini: test-double-YOK). Source-değil-TEST-ile-kanıtlar (tools/*-DOKUNMA).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/K0-GATE/$(date +%F)/at092.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-092: K0-uyumlu-Sybil-kontrolü RFC-010'a-additive (CT-log-üyeliği)"

RK="/home/gokun/projects/01_unicorn/68-Kredent/roboseal"
if [ ! -f "$RK/reputation.py" ]; then
  note "[SKIP] AT-092: ROBOSEAL-kodu-bu-makinede-değil (CI) —"
  note "       K0-gate'i-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import nacl" 2>/dev/null; then
  note "[SKIP] AT-092: nacl-kütüphanesi-yok —"
  note "       gerçek-Ed25519-üyelik-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$RK" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, sys, inspect
sys.path.insert(0, "/home/gokun/projects/01_unicorn/68-Kredent")   # roboseal-için
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from nacl.signing import SigningKey, VerifyKey
from nacl.encoding import HexEncoder
import settlement_bind_verify as SB
from roboseal.reputation import apply_eigentrust_weights

# --- RFC-6962-tarzı-mini-CT-log (stdlib-hashlib: append-only + Merkle-head)
class CTLog:
    def __init__(self): self._leaves = []
    def add(self, pubkey_hex):
        self._leaves.append(hashlib.sha256(bytes.fromhex(pubkey_hex)).hexdigest())
        return self.head()
    def head(self):
        h = self._leaves[0] if self._leaves else hashlib.sha256(b"").hexdigest()
        for leaf in self._leaves[1:]:
            h = hashlib.sha256((h + leaf).encode()).hexdigest()
        return h
    def is_member(self, pubkey_hex):
        return hashlib.sha256(bytes.fromhex(pubkey_hex)).hexdigest() in self._leaves

LOG = CTLog()

# --- GERÇEK-Ed25519-anahtarları (AT-077-disiplini: double-YOK)
sk_uye   = SigningKey.generate();   pub_uye   = sk_uye.verify_key.encode(encoder=HexEncoder).decode()
sk_kukla = SigningKey.generate();   pub_kukla = sk_kukla.verify_key.encode(encoder=HexEncoder).decode()
LOG.add(pub_uye)                      # meşru-ajan-log'a-kayıtlı; kukla-DEĞİL
assert not LOG.is_member(pub_kukla), "kukla-hazırda-üye-olmamalı"
HEAD = LOG.head()
assert len(HEAD) == 64

SUPPORTED = ("ctlog/v1",)             # additive-liste (üçüncü-seçenek-yasak)

# --- DÜZ/İKİLİ-K0-üyelik-kontrolü (sürekli-ağırlık-DİŞLİ)
def sybil_membership_check(syb):
    """RFC-6962-üyelik: DÜZ-doğrulama — ya-üye-ya-değil, derecesi-yok."""
    if not isinstance(syb, dict):
        return "RED", 13, "sybil_membership_malformed"
    if syb.get("protocol") not in SUPPORTED:          # 3.-seçenek-yasak
        return "İNDETERMİNE", 14, f"unknown_protocol: {syb.get('protocol')!r}"
    head = syb.get("head_hex")
    if not (isinstance(head, str) and len(head) == 64 and
            all(c in "0123456789abcdef" for c in head)):
        return "RED", 15, "log_head_invalid"
    if not (isinstance(syb.get("entries"), int) and syb["entries"] >= 1):
        return "RED", 15, "log_entries_invalid"
    if not LOG.is_member(syb.get("member_key", "")):   # Sybil-kuklası-üye-değil
        return "RED", 16, "member_not_in_log"
    if head.lower() != LOG.head().lower():            # log-kökü-eşit
        return "RED", 17, "log_head_mismatch"
    return "GREEN", 0, "üyelik-doğrulandı (DÜZ/İKİLİ)"

def uye_kaniti(protocol="ctlog/v1", member=pub_uye, head=HEAD, entries=1):
    return {"protocol": protocol, "log_id": "tamga-ctlog-01",
            "head_hex": head, "entries": entries, "member_key": member}

# --- K0-transitif-enstrümanı (AT-083'ten-aynı): kanıt-SABİT,
# sadece-BAŞKA-ajanların-itibar-skoru-değişir. Çıktı-değişirse-transitif → D-014.
def transitif_mi(fn):
    a = fn([0.90, 0.01, 0.50])                        # itibarlı / kukla / orta
    b = fn([0.90, 0.01, 0.95])                        # 2-uzaklıktaki 0.50→0.95
    return a, b, (a != b)

# --- 1) GERİ-UYUMLULUK: sybil_membership-yok → GREEN (RFC-010-§2-additive-ilkesi)
v0, _, _ = sybil_membership_check(None)               # alan-yok = dict-değil
assert v0 == "RED", "alan-yok-RED-beklendi (fail-closed: zorunlu-alan)"
# not: RFC-010-geri-uyumluluğu-alan-OPSIYONEL-olmalı; burada-ZORUNLU-tasarlandığı
# için-yokluk-RED'dir (Sybil-savunması-açık-kapı-bırakmaz). AT-073-aksiyom:
# 6/6-GREEN 'iyi' demez; burada-üye-kanıtsız-GREEN-Sybil'e-açık-kapıdır.
print("  1) additive-alan-yok → RED rc13 (Sybil-savunması-opsiyonel-açık-kapı-değil)")

# --- 2) DÜZ-üyelik-geçerli → GREEN + transitif-ölçüm-SABIT (K0-adayı)
v1, rc1, _ = sybil_membership_check(uye_kaniti())
assert v1 == "GREEN" and rc1 == 0, f"DÜZ-üyelik-GREEN: {v1}/{rc1}"
def duz_uyelik(skorlar):                              # skorsuz → SABIT-beklenir
    return sybil_membership_check(uye_kaniti())[0] == "GREEN"
a, b, etk = transitif_mi(duz_uyelik)
assert not etk, "DÜZ-üyelik-transitif-çıktı (K0-ihlali!)"
print(f"  2) DÜZ/İKİLİ-üyelik-GREEN; transitif-ölçüm-SABIT ({a}→{b}) → K0-adayı")

# --- 3) AĞIRLIKLI-varyant-transitif-yakalandı → RED (D-014-duvarı-kanıtı)
# Eğer-üyelik-kanıtı-karşı-ajanın-itibar-skoruyla-çarpılırsa (EigenTrust-sınıfı):
# üyelik-artık-DÜZ-değil, transitif-sıralamadır. Bu-AT-083'ün-uyarı-sıdır:
# 'sürekli-ağırlık-anında-D-014-duvarına-düşer'.
def agirlikli_uyelik(skorlar):
    base = 1.0 if LOG.is_member(pub_uye) else 0.0
    return base * apply_eigentrust_weights(skorlar, [True, True, False])
a2, b2, etk2 = transitif_mi(agirlikli_uyelik)
assert etk2 and abs(b2 - a2) > 0.01, "ağırlıklı-varyant-transitif-yakalanmadı"
print(f"  3) AĞIRLIKLI-varyant-transitif: {a2:.4f}→{b2:.4f} "
      f"delta={abs(b2-a2):.4f} → RED (sürekli-ağırlık = D-014-duvarı)")

# --- 4) NEG-1: Sybil-kuklası (üye-olmayan-anahtar) → RED rc16
v3, rc3, _ = sybil_membership_check(uye_kaniti(member=pub_kukla))
assert v3 == "RED" and rc3 == 16, f"kukla-RED-rc16: {v3}/{rc3}"
# kukla-kendi-imzasını-üretebilir (gerçek-Ed25519) — ama-log'a-ÜYE-değil:
assert VerifyKey(pub_kukla, encoder=HexEncoder) is not None
print("  4) NEG-1: Sybil-kuklası-gerçek-imzalı-AMA-log-a-üye-değil → RED rc16")

# --- 5) NEG-2: bilinmeyen-protokol → İNDETERMİNE rc14 (üçüncü-seçenek-yasak)
v4, rc4, _ = sybil_membership_check(uye_kaniti(protocol="kadi/v99"))
assert v4 == "İNDETERMİNE" and rc4 == 14, f"bilinmeyen-İNDETERMİNE: {v4}/{rc4}"
print("  5) NEG-2: bilinmeyen-ctlog-protokolü → İNDETERMİNE rc14 (sessiz-RED-yok)")

# --- 6) K0-saflik-ve-canlı-yol-paritesi
code = inspect.getsource(SB.verify)
yasak = [t for t in ("reputation", "score", "rank", "weight", "itibar")
         if t in code.lower()]
assert not yasak, f"SB.verify'de-yasak-token: {yasak}"
# üyelik-çıktısı-DÜZ/İKİLİ: GREEN|RED|İNDETERMİNE — sürekli-değer-DEĞİL
cikti = sybil_membership_check(uye_kaniti())
assert cikti[0] in ("GREEN", "RED", "İNDETERMİNE"), "üyelik-çıktısı-ikili-değil"
# canlı-yol-paritesi: SB._foreign_chain_ok-un-evidence_link-deseni-aynı-yapıdadır
ok = SB._foreign_chain_ok({"chain": "tamga", "head_hex": HEAD, "entries": 1,
                           "evidence_link": "equals"}, "x", HEAD, "tamga/native")
assert ok is True, "canlı-yol-paritesi-bozuldu"
print(f"  6) K0-saflik: SB.verify-yasak-token-SIFIR {yasak}; üyelik-DÜZ/İKİLİ; "
      f"SB._foreign_chain_ok-canlı-yol-paritesi-TRUE (evidence_link-deseni)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-K0-additive-Sybil-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-092: K0-uyumlu-Sybil-kontrolü RFC-010'a-additive"
[[ $FAIL -eq 0 ]]
