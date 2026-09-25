# Canlı Zincir Kullanımı (Base mainnet / sepolia)

Bu rehber `tamga-relayer`'ı **gerçek bir EVM zincirinde** çalıştırmak içindir.
Dağıtımın tamamı için [DEPLOYMENT.md](DEPLOYMENT.md); güvenlik duruşu için
oradaki §5'e bakın.

## 0. Önkoşullar

- Relayer ve bağımlılıklar: `pip install .[relayer]` (yalnızca `web3<7`)
- `ITamgaOracle` kontratı hedef zincirde **deploy edilmiş** olmalı
- WASI modülü `relayer.registry.json`'a **kayıtlı** olmalı (fail-closed)

## 1. Anahtar ve RPC yönetimi

**Özel anahtar bir sır olarak yönetilir — asla log'a, payload'a veya komut
satırına yazılmaz.** Relayer üç yol kabul eder, öncelik sırasıyla:

```bash
# (a) EnvironmentFile (üretim — systemd; 0600 root)
TAMGA_RELAYER_KEY=0x<imzalama-anahtarı>
TAMGA_RELAYER_RPC_URL=https://mainnet.base.org            # veya Alchemy/Infura
TAMGA_RELAYER_ORACLE=0x<ITamgaOracle-adresi>
TAMGA_RELAYER_LEDGER_SECRET=<32+ bayt rastgele>

# (b) CLI bayrakları (anahtar shell-geçmişine-düşer — yalnızca geliştirme)
# tamga-relayer daemon ... --key 0x… --rpc-url … --oracle 0x… --ledger-secret …
```

Yeni bir relayer-cüzdanı için anahtar üretimi:

```bash
python3 -c "from eth_account import Account; a=Account.create()
            print('key:', a.key.hex()); print('addr:', a.address)"
python3 -c "import secrets;print('ledger-secret:', secrets.token_urlsafe(32))"
```

> **Güvenlik notu:** anahtar `--key` bayrağıyla verilirse `sys.argv`'de kalır —
> `/proc/<pid>/cmdline` ile okunabilir. Üretimde **mutlaka** env
> (`EnvironmentFile`, 0600 root) kullanın. Log yolları (daemon log satırları,
> message-RED `reason` alanları) anahtarı **asla** içermez; bu AT-202/203
> evidence log'larında ve `submit_fulfillment`'ın istisna-sarma yolunda
> doğrulanmıştır.

## 2. Cüzdanı fonla

```bash
# mainnet: Base cüzdanınıza gerçek ETH gönderin (gas için)
# sepolia (test-ağı): faucet — ana para gerekmez, test-ETH ücretsizdir
```

Yeterlilik kontrolü (anahtarı ifşa-etmeden):

```bash
python3 -c "
from web3 import Web3
w3 = Web3(Web3.HTTPProvider('$TAMGA_RELAYER_RPC_URL'))
import os
a = w3.eth.account.from_key(os.environ['TAMGA_RELAYER_KEY']).address
print('cüzdan:', a, '| bakiye:', w3.from_wei(w3.eth.get_balance(a), 'ether'), 'ETH')"
```

## 3. Registry ve oracle hazırlığı

```bash
# registry doğrula (fail-closed: kayıt-dışı hash → RED-20, modül spawn YOK)
tamga-relayer registry-check /etc/tamga/relayer.registry.json

# oracle kontratının fulfillExecution'ı replay-korumalı imzalamalıdır
# (daemon fulfilled-seti process-ömrü-koruması-sağlar; restart-sonrası
#  dayanıklı-koruma zincir-tarafındadır — AT-202 K4 sınır-notu)
```

## 4. Çalıştır

**Tek request (daemon olmadan):**

```bash
tamga-relayer run-request --registry relayer.registry.json \
    --seed "$TAMGA_SEED_HEX" \
    --module-hash 6129007a280fcee3845532d38e4be3ecf9fddb03809c35a335e0b1b9c2b142a5 \
    --ledger-secret "$TAMGA_RELAYER_LEDGER_SECRET"
```

**Daemon (üretim — systemd için [DEPLOYMENT.md §4](DEPLOYMENT.md)):**

```bash
tamga-relayer daemon --registry /etc/tamga/relayer.registry.json \
    --seed "$TAMGA_SEED_HEX" \
    --rpc-url "$TAMGA_RELAYER_RPC_URL" --oracle "$TAMGA_RELAYER_ORACLE" \
    --key "$TAMGA_RELAYER_KEY" --ledger-secret "$TAMGA_RELAYER_LEDGER_SECRET" \
    --interval 15
```

Log çıkışı (anahtar YOK):

```
[relayer] request 42 fulfilled: tx=0x1fb49a4a3fb013af… status=1 gasUsed=39935
          digest=87ab8c35… delivery=9cec8dbc…
[relayer] request 43 RED: 28 fulfill-tx-hata: ValidationError: Insufficient gas
```

İkinci satır başarısızlık kipidir: daemon **crash-ETMEZ** — RC-28 ile
fail-closed kalır ve bir sonraki poll ile devam eder (AT-203).

## 5. Kanıtı bağımsız doğrula (karşı taraf)

Zincire gönderilen kanıtı relayer'ı **kurmadan** doğrulayabilirsiniz
([IVerifier — DEPLOYMENT.md §8](DEPLOYMENT.md#8-counterparty-verification-iverifier)):

```bash
tamga-verify verify-bundle bundle.json
# {"ok": true, "checks": 6, "verified": ["payload","stamp","snapshot","charge","delivery","input"]}
```

## Başarısızlık kipleri (fail-closed)

| Durum | Sonuç | Test |
|---|---|---|
| Registry'de OLMAYAN `wasiModuleHash` | RED-20, modül spawn'suz — relayer RCE vektörü DEĞİL | AT-198 N1, AT-199 K7 |
| `maxCpuMsAllowed` [1,60000] dışında | RED-21, sandbox'a-ulaşmadan | AT-198 K1–K5 |
| Ledger secret None / dev-secret | RED-24 / RED-25 | AT-197 |
| Gas yetersiz / tx revert | RED-28, daemon crash-ETMEZ | AT-203 |
| Aynı request tekrar (process-ömrü) | fulfilled-seti atlar, TEKRAR fulfill-ETMEZ | AT-202 |
| Ağ/RPC hatası | message-RED ile-devam, `Restart=always` ile çift-katman | AT-203 K2 |
