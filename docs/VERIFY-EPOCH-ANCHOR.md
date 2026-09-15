# Bir dış epoch-mührünü kendin doğrula (verify-it-yourself)

> Bu sayfa, Tamga'yı bilmeden, bize güvenmeden, tek Python yorumlayıcısıyla bir **dış
> epoch-mührünün** (örnek: Apodix/Vauban kayıt-çapası) nasıl doğrulanacağını anlatır.
> Yöntem, 2026-09-13'te epoch-13 mühür-flip'i için bizim kendi tarafımızda koştuğumuz
> replay ile birebir aynıdır (kanıt: `.evidence/APODIX-EPOCH-13/2026-09-13/seal-flip-replay.log`).
> Çıkarılacak ders iki bacaklıdır: **dahil-etme** ve **çapa**.

## Neden bu sayfa var

Kanıt kültürümüzün tek kuralı: **kimsenin sözü, başkası koşmadan yeşil değildir.** Bir dış
kayıt-mührü "var" deninceye kadar, dört sorunun cevabını KENDİ makinende üretmelisin:

1. Verilen fact, iddia edilen epoch ağacının **gerçekten yaprağı mı?** (dahil-etme)
2. Ağacın kökü, **zincire yazılmış kökle aynı mı?** (çapa)
3. Kökü kim yazdı, hangi blokta? (kaynak-okuma — mührün kendisini de doğrula)
4. Bunların HİÇBİRİ, fact'ın *içeriğinin* doğru olduğunu kanıtlamaz — dahil-etme ile
   doğruluk ayrı sorulardır ve karıştırılmaz. (dürüstlük-notu)

## Gereksinim

- `python3` (stdlib yeterli — keccak'i kendin yazacaksın ya da tek-dosya referansımızı
  kullan: [`tools/keccak256.py`](../tools/keccak256.py) — keccak İÇERİDE yazılıdır, hiçbir
  paket ithal edilmez; üç bilinen-yanıt vektörüyle öz-doğrular)
- Merkle tarifi: OpenZeppelin merkle-tree — `sort_leaves:true`, `sorted_pairs:true`,
  yaprak = `keccak256(keccak256(bytes32(fact)))`

## Adım 1 — kanıt-verisini al

```bash
curl -sS "https://explorer.testnet.apodix.vauban.tech/v1/anchors/proof/<fact-hash>" -o proof.json
```

Dönen alanlar: `epoch_id`, `fact_hash`, `position`, `leaf_count`, `proof[]`, `root`, `l1`,
`tree`, `how_to_verify`.

## Adım 2 — dahil-etmeyi yeniden hesapla

```python
import json, sys
sys.path.insert(0, "tools")
from keccak256 import keccak256 as k

d = json.load(open("proof.json"))
node = k(k(bytes.fromhex(d["fact_hash"][2:])))   # yaprak: double-keccak(bytes32(fact))
for p in d["proof"]:                             # sorted-pairs yürüyüşü
    sib = bytes.fromhex(p[2:])
    lo, hi = sorted([node, sib])
    node = k(lo + hi)
print("dahil-etme GREEN:", "0x" + node.hex() == d["root"])
```

Sonuç `True` ise fact, o epoch ağacının yaprağıdır. (Bizim gerçek koşumun ham hali:
`seal-flip-replay.log` — satır-satır aynı yolu izler.)

## Adım 3 — kökü zincir üzerinde kendin oku

```python
import json, urllib.request, sys
sys.path.insert(0, "tools")
from keccak256 import keccak256 as k

data = "0x" + k(b"epoch(uint64)").hex()[:8] + f"{13:064x}"   # epoch(uint64) selector
corps = {"jsonrpc": "2.0", "id": 1, "method": "eth_call",
         "params": [{"to": "0x48421a2e448cb2E3fA66af2E047F86ee755cFB14", "data": data}, "latest"]}
req = urllib.request.Request("https://ethereum-sepolia-rpc.publicnode.com",
                             data=json.dumps(corps).encode(),
                             headers={"content-type": "application/json",
                                      "user-agent": "verify-it-yourself/1"})
ret = json.load(urllib.request.urlopen(req, timeout=60))["result"][2:]
print("root  :", "0x" + ret[0:64])
print("count :", int(ret[64:128], 16))
```

Kendi RPC'ni SEÇ (publicnode, alchemy, kendi node'un) — mührü doğrulayan, sana cevabı
veren değil. Kök, Adım 2'nin sonucuyla birebir eşleşmeli; `factsCount == leaf_count` da
eşleşmeli. **Ama seçtiğin RPC'nin İDDİA-EDİLEN zincir olduğunu da doğrula:** RPC'ne bir
`eth_chainId` at, beklediğin zincirle eşleşmiyorsa okuduğun kök BAŞKA bir dünyanın köküdür
(sepolia `0xaa36a7`=11155111; x402 #2887'deki payee-mismatch sınıfının zincir-versiyonu).
CLI bu-bağı artık varsayılan-yapar: `--rpc` verildiğinde `--expect-chainid` (default sepolia)
önsorgusu koşar; `--expect-chainid 0` bilinçli-atlamadır ve dürüst-notu basar.

## Yeşil demek için

- Adım 2 `True` **ve** Adım 3 kökü eşit **ve** sayılar eşit → **GREEN** (dahil-etme + çapa).
- RPC cevap vermezse **İNDETERMİNE** de — "bakamadım" ile "yeşil" asla karıştırılmaz.
- RPC cevap verir ama zincir-bağı tutmazsa (chainId ≠ beklenen) **İNDETERMİNE** — *yanlış-yerde
  bakmak*, doğru-yerde-bakamamakla aynı-sonuçtur: hüküm-yok.
- Kök tutmazsa veya kanıt yürümezse **RED**.

## Bu sayfanın ölçülü-sözü (dürüst-sınırlar)

Bu prosedür, fact'ın **mühür-sever bir epoch-ağacına dahil edildiğini** ve o mührün zincirde
durduğunu kanıtlar. Fact'ın kendi içeriğinin (örn. bir STARK kabulünün) doğruluğunu
KANITLAMAZ — o, mührü basan tarafın kendi dürüstlük-notudur ve ek sorulardır. İki soru
karıştığı anda bu sayfa amacını kaybeder; bu yüzden bu ayrım sayfanın kendisinin bir parçasıdır.

---

Kaynak-olay: 2026-09-13 epoch-13 seal-flip — kanıt logu `seal-flip-replay.log`
(fact `0x0236…36e2`, position 55/60, root `0xaaf21f36…c458e`, Sepolia block 11693440).
Kamu raporu: x402 #3389, [issuecomment-5653083752](https://github.com/x402-foundation/x402/issues/3389#issuecomment-5653083752).
