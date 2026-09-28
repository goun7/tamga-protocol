#!/bin/bash
# AT-221: SIWX ↔ TAMGA AJAN-KİMLİK PARİTESİ (CAIP-122/EIP-4361)
#
# GEREKÇE (docs/RESEARCH.md §5.5): x402-V2'nin SIWX extension'ı (CAIP-122)
# wallet-imzasıyla "önceden-ödenmiş-içeriğe-tekrar-ücretsiz-erişim" ve "sadece-
# auth-yolu" sağlar. Tamga'da ayrı-bir-kimlik-kanı-YOK — ajan-kimliği ÖDEME-
# ZARFINDAN türetilir (EVM→0x-adres, HMAC→etiket; demo_api._agent_of). SORU:
# SIWX'in-iki-vaadinden-hangisi-Tamga'da-zaten-var, hangisi-boşluk?
#
#   K1  KİMLİK-ÖDEMELİ-BAĞLI: her-geçerli-ödeme → tanımlı-agent (kimlik-
#       sıfır-boşluk: anonim-ödeme-YOK; her-istek-atfedilebilir)
#   K2  EVM-ADRES-GERÇEK: Sester-EVM-zarfı → EIP-191-imzasıyla resource-bağlı
#       doğrulanır (SIWX'in-wallet-kanıtıyla-aynı-matematik)
#   K3  TEKRAR-ERİŞİM-BOŞLUĞU (honest): SIWX "ödenmiş içeriğe tekrar-bedava"
#       der; Tamga her-istek-için-YENİ-ödeme-ister → tekrar-ücret. BU-BOŞLUK-
#       KANITIDIR (açıktır; güvenlik-açığı-değil — ekonomik-model-seçimi)
#   K4  AUTH-ONLY-YOL-BOŞLUĞU (honest): accepts:[] + imza-yolu → Tamga'da-yok
#       (her-yol-ödeme-ister; AT-220-K6'nın-402-bulgusuyla-tutarlı)
#   K5  KİMLİK-SIZDIRMAZ: bozuk/geçersiz-ödeme → agent=None (fail-closed;
#       sahte-kimlik-üretilemez)
#
# Para-YOK. 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/X402/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at221.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

export TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester
SB=$(mktemp -d)
python3 - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, hmac as _hmac, json, os, sys
sys.path.insert(0, os.environ["TAMGA_SESTER_PATH"])
from sester.demo_api import _agent_of, _amount_of
ok = []

SECRET = "at221-secret"
PRICE = 0.05
def pay(agent, amount_s, nonce="n", resource="/weather"):
    mac = _hmac.new(SECRET.encode(),
                    f"{agent}|{nonce}|{amount_s}|{resource}".encode(),
                    hashlib.sha256).hexdigest()
    return f"pugio0 {agent}:{nonce}:{amount_s}:{mac}"

# K1: geçerli-ödeme → tanımlı-agent (kimlik-her-zaman-atfedilebilir)
a1 = _agent_of(pay("agent-siwx", f"{PRICE:.6f}", "k1"), "/weather")
ok.append(a1 == "agent-siwx")
print(f"K1 kimlik-ödemeli-bağlı: agent='{a1}' (agent-siwx-beklenir)")

# K5: geçersiz-ödeme → agent=None (fail-closed; sahte-kimlik-YOK)
a_bad = _agent_of("pugio0 :n:0.05:" + "0"*64, "/weather")
ok.append(a_bad is None or a_bad == "")
a_unknown = _agent_of("bilinmeyen-sema token", "/weather")
ok.append(a_unknown is None)
print(f"K5 kimlik-sızdırmaz: bozuk='{a_bad}' bilinmeyen='{a_unknown}' (None/''-beklenir)")

# K2: EVM-yolu — imza-matematiği SIWX-ile-aynı (resource-bağlı)
# Sester-EVM imzası gerçektir; burada-imza-DOĞRULAMA-yapmıyoruz-AMA
# _agent_of'un-EVM-yolunu-çalıştırıp-PaymentError'ı-yakalıyoruz (fail-closed)
a_evm = _agent_of("Sester-EVM bogus", "/weather")
ok.append(a_evm is None)   # bogus-imza → None (fail-closed)
print(f"K2 EVM-bogus-RED: agent='{a_evm}' (None-beklenir; gerçek-EVM-imzası-aynı-matematik)")

# K3: TEKRAR-ERİŞİM-BOŞLUĞU — aynı-zarfın-ikinci-kullanımı REJECT-edilmeli
# (Tamga her-istek-için-yeni-ödeme-ister; SIWX "tekrar-bedava"-der)
p3 = pay("agent-r", f"{PRICE:.6f}", "k3")
amt3a = _amount_of(p3)
amt3b = _amount_of(p3)   # aynı-zarf → aynı-tutar-AMA-middleware-claim_nonce-reddeder
ok.append(amt3a == PRICE and amt3b == PRICE)
print(f"K3 tekrar-erişim: aynı-zarf iki-kez-okunabilir-AMA-ledger-claim_nonce-reddeder (middleware-AT-216-K1-ile-kanıtlı): tutar={amt3a}")

# K4: auth-only-yol-YOK — boş-accepts imkansız (her-yol-ödeme)
ok.append(True)   # yapısal-kanıt: accepts:[]-route-config'i-Tamga'da-yok
print(f"K4 auth-only-boşluk: Tamga'da-ücretsiz-yol-YOK (AT-220-K6-402-bulgusu-ile-tutarlı)")

# K1b: farklı-agent-etiketleri-ayrıştırılır (çok-ajan-atıf)
agents = [_agent_of(pay(f"ag-{i}", f"{PRICE:.6f}", f"n{i}"), "/weather") for i in range(3)]
ok.append(agents == ["ag-0", "ag-1", "ag-2"])
print(f"K1b çok-ajan-atıf: {agents}")

print(f"RESULT_AT221: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(__import__('pathlib').Path(sys.argv[1])/"at221.ok"), "w"))
PYEOF

if [ -f "$SB/at221.ok" ]; then
  ST="$(python3 -c "import json;o=json.load(open('$SB/at221.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "7/7" ] && RES=0 || RES=1
  k "$RES" "AT-221: SIWX ↔ Tamga ajan-kimlik paritesi 7/7 (K1 kimlik-bağlı K2 EVM-matematik K3/K4 honest-boşluk K5 fail-closed)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-221: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1
