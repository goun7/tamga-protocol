# ÜRETİM CHECKLİSTİ — Canlıya Çıkmadan Önce (Tamga)

**Durum:** relayer daemon'u Base mainnet'te hizmete almadan önce
**her maddeyi çalıştırın.** Her madde bir KOMUT'tur — yazıp geçmeyin.

---

## 1. Anahtar ve Bakiye

```bash
# funded key var mı, ETH yetiyor mu (relayer gas için > $0.01 önerilir)
$PY - <<'EOF'
from eth_utils import to_wei
import os, pathlib, re
env = pathlib.Path.home()/".tamga/relayer-live.env"
if not env.exists():
    raise SystemExit("YOK — önce keygen-node + fund yap")
txt = env.read_text()
print("env dosyası mevcut:", env)
EOF
```

**Kritik:** anahtar yoksa AT-204/205/207 **SKIP** olur (canlı-gas-korunuyor).
Hizmete alınmadan önce bakiyeyi kontrol edin:

```bash
# bakiye < 0.005 ETH → AT-207 yetersiz-bakiye SKIP der (güvenli)
$PY tamga_runner.py health-check
```

---

## 2. Registry Yedeği (AT-209)

**Registry = mayın dizini. Silinirse daemon ölür — yedek zorunlu.**

```bash
# atomik yedek (reg.json → reg.json.bak)
python3 tamga_runner.py registry-backup ./my-pkg

# test: registry sil → geri yükle → mayınlar hayatta
bash tests/at209_registry_restore.sh
# beklenen: 4 PASS, 0 FAIL
```

**Sonra:** crona veya systemd-timer'a bağlayın (günlük).

---

## 3. Daemon Başlangıç ve Sağlık

```bash
# daemon başlat (arka planda)
python3 tamga_oracle_relayer.py daemon &

# ---health (daemon canlı, zincir-yüksekliği, beklemede request sayısı)
python3 tamga_runner.py --health
```

**Beklenen:** JSON çıktısı, rc=0.

---

## 4. İlk Test Request

```bash
# fulfillsExecution — gerçek chain etkileşimi (para-harcar ~$0.008)
TAMGA_LIVE=1 bash tests/at205_canlı_oracle_fulfill_dikis.sh
# beklenen: 7/7
```

---

## 5. Batch Denetim (AT-208)

```bash
# N paketi TEK çağrıda denetle (müşteri: "100 paketi tek seferde")
python3 tamga_runner.py ledger-verify-batch pkg1 pkg2 pkg3 --summary-only

# beklenen: {"ok": true, "verified": 3, "failed": 0, ...}
```

---

## 6. Crash Testi (daemon dayanıklılığı)

```bash
# kill -9 → restart → ledger sağlam (chain-integrity bozulmaz)
kill -9 $(pgrep -f "oracle_relayer.py daemon")
sleep 2
python3 tamga_oracle_relayer.py daemon &
python3 tamga_runner.py ledger-verify ./my-pkg
# beklenen: ok, rc=0
```

---

## 7. Tüm Suite

```bash
# tam suite (canlı-gas HARİÇ — 220 PASS + 3 SKIP)
bash tests/run_all.sh

# canlı dahil (para-harcar ~$0.03)
TAMGA_LIVE=1 bash tests/run_all.sh
```

---

## İmza

Bu checklist'teki her madde **çalıştırılmış ve rc=0** olmadan
hizmete ALINMAYIN. Fail-closed garantileri (registry, replay-protection,
gas-limit) AT-202/203/207/208/209 ile kapsanmıştır.

| Test | Kapsam | Kriter |
|---|---|---|
| AT-202 | replay-protection | 4/4 |
| AT-203 | gas fail-closed | 5/5 |
| AT-206 | canlı-tx doğrulama | 5/5 |
| AT-208 | batch-verify | 5/5 |
| AT-209 | registry yedek | 4/4 |
