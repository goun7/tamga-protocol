# #3396 Index-Hazırlık — AT-0NN ↔ corpus-family eşleme (sabit-karşılık tablosu)

> Amaç: smartflowproai birleşik-vektör-indeksi-taslağı-ındiğinde(gönderdikleri-sözün
> karşılığı) satır-satır **hızlı ve hatasız** karşılaşmak. Bu-dosya-bizim-tarafın
> KAMU-karşılıklarını-önceden-sabitler: hangi-corpus-ailesi-hangi-herkesin-koşabileceği
> AT-0NN ailesine denk, hangi-etikette-hangi-sabit-tag.
> Karşılıklar-#3396-yanıtımızda-gönderilen-tabloyla-BİREBİR (issuecomment-5636756335).

## Durum-damgası

- Sabitlenmiş: 2026-09-12 · Tag-bağlamı: `v0.2.2` (wheel-canlı;-PyPI) — regenerasyon-komutları
  DAİMA-tam-etikete-sabitlenir, asla-dalların-kafasına-değil.
- Bu-dosya-SÜREÇ-dosyası-değil, KAMU-taahhüdü-tablosu: index-taslağı-gelince-her-satırı
  bu-tabloyla-çapraz-doğrulayıp-uyuşmayanları-RED-listesine-alacağız.

## Corpus-family ↔ AT-0NN karşılıkları

| index family (onların-adı) | bizim kamu test ailesi | kanıt-bağı | sabit-tdi |
|---|---|---|---|
| chain-forgery | AT-003 (+ Audit-7 gömülü-zincir: splice/tip-swap/merkle-fold) | reason-14-zincir-kırma; gömülü-zincir-kurcalamaları-ithalatta-RED | `tests/at003_*.sh` |
| state-tamper | Audit-15 | kırık-state.json-RED-5;-zincir-tamper-inert | `.evidence/AUDIT-15/` |
| revocation | Audit-16 | iptal-listedeki-node-imzası-ithalatta-RED-(L1-politika) | `.evidence/AUDIT-16/` |
| snapshot-byte-fuzz | Audit-17 (+ AT-001f) | truncate/flip/swap/magic → fail-closed; metin-gizliliği | `tests/corpus/snapshot/` |
| unicode-hash-separation | Audit-18 (+ corpus fuzz binder) | NFC/NFD/homoglyph/null-kimlikleri-ayırır; JCS-sapma-sınıfı-notları | `tests/audit18_unicode_fuzz.sh` |
| timing | Audit-19 | timing-yan-kanal-matrisi; unlock-RED≈success-band | `.evidence/AUDIT-19/` |
| version-drift pins | AT-015 (mem0 2.0.20 / letta 0.16.8 / zep 3.28.0) | ihracat-şekli-değişiklikleri-YENİ-pinli-dosyalar-ekler | `tests/at015_*.sh` |
| input-binding / ledger-bomb | AT-004 + Audit-11 | input_sha256-makbuzda; 50MB-ledger-bomb-RSS-sınırlı-fail-closed | `tests/at004_*.sh` |

## Bizim-katkı-vektörlerimiz (index'e-girecekler)

- **Kompozisyon-vektörü** (AT-022; bugün-yeni): epoch-10-batch'i-tamga_keccak-ile-bağımsız-
  yeniden-katlandı-kök-birebir-eşti + Tamga-zincirbaşı-D5-izdüşümü-batch-yaprağı-(felt252-notasyonu
  dersi-kayıtlı). 46-kontrol-yavaş-süit üyesi.
- **Pairing-fixture** (AT-007/AT-012): etiket-disiplinli-alanlar-(simulated|observed|derived);
  `receiptHash → makbuz → delivery_hash → contentHash` üçüncü-taraf-kenetleme.

## Söz-disiplini (RED-sözlüğü)

- **RED**-bizde: çalışma-zamanı-red-taksonomisi-(reason-kodları). Test-aileleri-`AT-0NN`/`Audit-NN`.
- **Corpus-family**: #3396-öneri-dili; bu-tablo-ikisini-haritalar,-eşitlediği-yerde-KİLİTLİ.
- Yeni-aileye-girersek: additive-satır-(tablo-donmez,-genişler) — aynı-disiplin.

## Bekleyen-taraf

- smartflowproai: index-taslağı-(~1-hafta-içinde-söz-verildi) → bizim-tur: satır-satır-kesim.
- Vaat-edilen-şekil: `captured_at`+`last_verified_at` tazelik-çifti;-`disclosure: host withheld`;
- `simulated`-canlı-karşıtı-notu;-lisans-Apache-2.0-ayrı-korpus-repo-(onlar-ev-sahibi).
