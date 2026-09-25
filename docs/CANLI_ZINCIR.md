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

## 6. Canlı-kanıt (Base mainnet, 2026-09-25)

Tam döngü AT-204 + AT-205 ile **gerçek Base mainnet** üzerinde koşuldu:

| Adım | Sonuç |
|---|---|
| Emitter deploy | `status=1 gasUsed=124936` — [`0x897D7abD…`](https://basescan.org/address/0x897D7abDe35124EEB41F0BC0d04d2cF81653442f) |
| `RequestExecution` emit | 1 log, topic `0x1bf6f1fa…` — [tx](https://basescan.org/tx/0xcc9365af8ca17ac6588416730173e90293eb114c287c4e99289bed66b94d2ade) |
| **daemon canlı RPC** | `fulfilled=[205]`, crash-YOK |
| **`fulfillExecution`** | `status=1 gasUsed=68150` — [tx](https://basescan.org/tx/0x391f4ea94789a171437916e075dc8adb34863cbe3b5d7283db8a76ef1c20ce73) |
| calldata paritesi | selector `0xe266d3c7` (fulfillExecution), outputData 1026 bayt |
| **delivery keccak canlıda** | zincir outputData'sından keccak = log'daki `delivery=dc6f72f2…` — **birebir** |

> Toplam maliyet: ~$0.001 — Base mainnet baseFee ~0.005 gwei.

**Üretime-geçiş bulguları** (canlı zincirde-çıktı, AT-205 ile-düzeltildi):

1. **Public RPC account'ları unlock-ETMEZ** — `send_transaction` → `unknown account`.
   Çözüm: `sign_transaction` + `send_raw_transaction` (relayer'ın kullandığı yol).
2. **`eth_getLogs` block-limiti** — daemon `from_block=0` ile 51M block-taramaya
   kalkar (public sağlayıcı reddeder). **daemon_loop artık cursor-takibi-yapar**:
   başlangıç `latest-100`, her-cycle `block_number`'a-güncellenir — hiçbir request
   kaçırılmaz, tüm-zincir-taranmaz.
3. **Log-indeks gecikmesi** — load-balanced RPC'lerde receipt'te-log varken
   `get_logs` stale-dönebilir; daemon çok-cycle'lı-poll ile-aşar (receipt'ten
   okuma tercih edilir).

## Başarısızlık kipleri (fail-closed)

| Durum | Sonuç | Test |
|---|---|---|
| Registry'de OLMAYAN `wasiModuleHash` | RED-20, modül spawn'suz — relayer RCE vektörü DEĞİL | AT-198 N1, AT-199 K7 |
| `maxCpuMsAllowed` [1,60000] dışında | RED-21, sandbox'a-ulaşmadan | AT-198 K1–K5 |
| Ledger secret None / dev-secret | RED-24 / RED-25 | AT-197 |
| Gas yetersiz / tx revert | RED-28, daemon crash-ETMEZ | AT-203 |
| Aynı request tekrar (process-ömrü) | fulfilled-seti atlar, TEKRAR fulfill-ETMEZ | AT-202 |
| Ağ/RPC hatası | message-RED ile-devam, `Restart=always` ile çift-katman | AT-203 K2 |
