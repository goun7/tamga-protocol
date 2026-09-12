# RFC-009 (TASLAK) — External Chain Anchor (dış-registry çapaları: zincirimiz dış-fact'i cite eder)

> **Durum: DRAFT — PILOT-PENDING.** Bu-başlık-yeni-bir-`anchor`-op'unun-const'a-girmesini
> iddia-ETMEZ: runner-op-(RFC-003-v0.2-dilimi)-ve-verifier-known-tags-terfisi-pilot-günü
> kapılarından-geçer (RFC-008-P8-1..3 ile-AYNI-kapı; kurucu-normatif-onayı-şart).
> Burada-dondurulan-şey: KAYIT-ŞEKLİNİN-MATEMATİĞİ-ve-doğrulama-SÖZLEŞMESİ — ikisi-de
> bugün-kanıtla-sabit (AT-017, kontrol-39). Düşünmek-bedava, kodla-değil (RFC-008-paraleli).

## 0. Özet (one-paragraph)

Bir-Tamga-ledger-kaydı-DIŞ-bir-registry'nin-fact'ini-CİTE-edebilir: "bu-zincirin-bu-başı,
o-sealed-epoch'un-bu-kanıtıyla-işaretlendi." Yeni-bir-hash-TANIMLANMAZ — anchor-kaydı-her-
diğer-kayıt-gibi-D5-zincir-matematiğine-girer; dış-fact'in-GEÇERLİLİĞİ-ise-ASLA-bizim-
verifier'ın-iddiası-OLMAZ (sunum-paritesi; kök-yeniden-hesap-origin-registry'nin-sözleşmesi).

## 1. Motivasyon

- Epoch-10-kanıtı-(2026-09-10)-elimizde-ÇALIŞAN-bir-dış-kanıt-var: 2-bağımsız-keccak-
  uygulaması-aynı-merkle-yolunda-eşleşti (tamga_keccak + verifier_epoque.py)
- Zincirler-arası-okunabilirlik: dış-dünya-bizim-zinciri-okurken-dış-durakları-çarpabilir;
  bizim-zincir-de-dış-sealed-fact'lere-referans-taşıyabilir
- İki-alanlı-iddia-kültürü: bir-anchor-'o-gün-doğrulanmış'tır; eskimesi-'yanlış'-değil

## 2. Kayıt-şekli (ledger'da YENİ-op: "anchor" — v0.2-adayı, FROZEN-DEĞİL)

```json
{"seq": N, "op": "anchor", "prev": "<64hex>",
 "anchor_version": "TAMGA_EXTERNAL_ANCHOR_V1",
 "foreign_registry": "apodix/epoch",
 "foreign_fact": "0x0236…36e2",        // cite-edilen-fact (merkle-leaf; 0x+64-lowercase)
 "foreign_digest": "0xabab…abab",      // registry'nin-own-digest'i (sunum-paritesi)
 "foreign_source": "https://…/v1/anchors/proof/0x0236…",
 "verified_at": "2026-09-10T07:32:08Z", // iki-alanlı-iddia: İDDİA-GÜNÜDÜR, süreklilik-DEĞİL
 "tool": "verifier_epoque.py + tamga_keccak (dual-impl)"}
```

**D5-uyumu (bugün-kanıtla-sabit):** `h = sha256(prev ‖ jcs(record − {h, node_sig}))` —
op-alanı-fark-etmez; anchor-kaydı-zincir-hash'ine-HER-kayıt-gibi-girer
(AT-017-1: yeniden-hesap=vector-h, kontrol-39).

**Kurallar (v-taslak):**
- R9-1: `anchor_version`-sabit-dize-`TAMGA_EXTERNAL_ANCHOR_V1`-(sürüm-terfisi-EXPLICIT)
- R9-2: `foreign_registry`-∈-registry-adları-(`apodix/epoch`-bugün-tek-örnek; liste-BÜYÜR,
  her-ek-additive-const-terfisiyle)
- R9-3: `foreign_fact`/`foreign_digest`-kanonik-0x+64-lowercase-(x402-#3377-disiplini)
- R9-4: `verified_at`-RFC3339-UTC-Z; **iki-alanlı-iddia**-(claim,-day)-olduğu-İÇİN-DEX-
  karşılaştırması-ASLA-geçersizleşmez — eski-anchor-'daha-eski'-okunur, 'yanlış'-DEĞİL
- R9-5: Dış-fact'in-geçerliliği-BİZİM-verifier'ın-iddiası-DEĞİL: foreign_registry-
  bilinse-BİLE-verifier-kök-yeniden-hesabı-registry'nin-sözleşmesine-BIRAKIR (§4.4-parite)

## 3. Doğrulama-sözleşmesi (mini-verifier; bugün-kanıtla-sabit)

| Durum | Verdict | Davranış |
|---|---|---|
| anchor-kaydının-D5-hash'i | zincir-matematiği | her-kayıt-gibi-doğrulanır |
| `foreign_registry`-boş/yok | `indeterminate`-"empty origin tag (§4.3 F1)" | etiketsiz-öz-bir-sayıdır |
| `foreign_registry`-bilinmiyor | `indeterminate`-`unknown origin tag` | **sonuç-esirgeme, yokluk-DEĞİL** |
| `foreign_registry`-bilinir | `indeterminate`-`presentation only (§4.4)` | çarpılabilir-nokta-yol-gösterilir; green-giydirilmez |

Bilinirlik-listesi: `KNOWN_FOREIGN_TAGS`-(bugün: `TAMGA_CHAIN_HEAD_V1`, `APODIX_EPOCH_ROOT_V1`;
terfisi-additive). Bu-davranış-kanonik-BEYANLI-davranıştır: tamga_verify_mini'da-canlıdır-ve
AT-017-3-ile-kilitlidir.

## 4. NE-ŞİMDİ / NE-SONRA

ŞİMDİ-(bu-doküman): (a) kamu-yüzeyli-tasarım-notu-(özel-F1-doc'tan-terfi; içerik-birebir);
(b) donmuş-matematik-ve-kanıt-linkleri-(aşağıda).
SONRA-(pilot-günü-kapıları): (c) runner'da-`anchor`-op-(RFC-003-v0.2-dilimi); (d) verifier-
known-tags+const-terfisi; (e) Vauban-ile-etiket-uyumu-teyidi-(pilot-günü-4-açık-kapıdan:
P8-1..3 + F1-etiket-uyumu).

## 5. Kanıt-linkleri

- **Dış-kanıt-(çalışan)**: `.evidence/APODIX-EPOCH-10/2026-09-10/` — epoch-10-manifest
  (root 0x997c…71d, 57-leaf-merkle, keccak256/@openzeppelin, L1-chain 11155111-block-11672468,
  tx-0x0d30…cea22) + fact-proof-(fact-0x0236…36e2, pozisyon-55, 6-adımlı-yol) +
  bağımsız-verifier-`verifier_epoque.py`
- **Çift-uygulama-kesişimi**: tamga_keccak-(KAT-3/3: empty/abc/fox) × verifier_epoque.py —
  aynı-merkle-yolunda-eşleşti-(gece-çapraz-kontrolü, 2026-09-10)
- **D5-ve-alan-donukluğu**: `tests/vectors/anchor-v0-design/anchor-design-vector.json` +
  AT-017-(kontrol-39; 3-koşum: D5-yeniden-hesap/alan-tamlığı/KNOWN_FOREIGN_TAGS-paritesi)
- **Batch-leaf-izdüşümü-(kompozisyon)**: AT-022-(kontrol-46;-2026-09-12):-Tamga-zincirbaşı
  (D5-sha256,-tam-64-hex)-Vauban-yaprak-şemasıyla-(k256(k256(bytes32)))-kodlanıp-epoch-10
  batch'inin-fact-pozisyonuna-izdüşürüldü;-tüm-batch-(57-yaprak)-tamga_keccak'le-bağımsız
  katlandı-ve-manifest-köküne-BAYT-birebir-eşti. Ders-kayıtlı:-felt252-gösterimi-(baştaki-
  sıfır-yazılmaz)-çapraz-teyit-tuzaklarından-biridir. Vektör:
  `tests/vectors/anchor-v0-design/composition-fixture.json`

## 6. Riskler (dürüst)

- Şema-pilot-verisi-görmeden-kilitlenirse-dönüş-maliyeti → bu-yüzden-YALNIZ-matematik-
  donduruldu; op-const'a-pilot-SONRASI-girer
- Dış-fact-yayıncısı-durursa-anchor-bayatlaşır → iki-alanlı-iddia-(R9-4)-tam-bu-yüzden:
  bayat-≠-yanlış
- Anchor'lu-zincirlerin-görünür-doğrulaması-registry-bağımlı-görünebilir → §3-sözleşmesi-
  'presentation-only'-ile-bunu-açıkça-sınırlar; green-giydirme-YOK

## 7. GERİBİLDİRİM-YÜZEYİ

- Kamu-tartışma-x402-foundation/x402#3447-(RFC-008-E1-tasıyla-aynı-kanal; DRAFT-öneri-
  issue-non-binding)
- Bu-taslağın-kaderi-orada-masaya-yatar; PR-yalnız-P8-1..3-ve-etiket-uyumu-kapandıktan-sonra
