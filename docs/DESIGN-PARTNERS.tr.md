> Çeviri notu: İngilizce-orijinali (docs/DESIGN-PARTNERS.md) ile ikizdir; normatif-metin İngilizce'dir — çelişki-olursa ORİJİNAL-BAĞLAYICIDIR.

# Tasarım-ortağı programı (v0.1.0-alpha)

Tamga Protocol, yapay-zekâ ajanlarına taşınabilir, şifreli, kurcalamaya-kanıtlı
bir bellek + iş-makbuzu paketi verir: makine ölür, ajan başka bir node'da
devam eder ve defteri işin gerçekten yapıldığını kanıtlar.

v0.1 → v0.2 çevrimi için **2–3 tasarım ortağı** arıyoruz.

## Bir ortak ne kazanır (ücretsiz, ilk üç kişi)

- **Tamga'ya geçiş, bizim tarafımızdan yapılır** — mevcut ajan-belleği
  kaynağınızı (PostgreSQL/SQLite dökümü, Mem0 / Letta / Zep export-JSON ya da
  düz JSON-lines) analiz eder, şema eşlemesini kurar ve şifreli bir Tamga
  anlık-görüntüsünü geri-yükleme-doğrulama raporuyla (node/edge sayıları, hash
  kontrolü, anlık-görüntü gövdesinde 0 düz-metin sızıntı) teslim ederiz.
  Hedef: kick-off'tan itibaren 10 iş günü.
- **Dondurma-çevresinde bir koltuk** — dört hafta boyunca haftada 30 dakika;
  geri-bildiriminiz, RFC v0.2 kararlarını (node-birlikte-imzalama politikası,
  beyan-edilen çıkış (egress), faturalama alanları) bunlar donmadan *önce* besler.
- **"İlk üretim kullanıcısı" statüsü** — üstelik gelecekteki destek/yönetilen-node
  hizmetlerinde ömür-boyu %20 indirim.

## Bizim istediğimiz

- Dört hafta boyunca haftada bir geri-bildirim görüşmesi.
- İşbirliğini bir vaka-çalışması olarak anlatmamıza izin — **veriniz size
  aittir**: yalnızca sayılar ve mimari anlatılır, içerik asla.
- Alfa-kalitedeki kenarlara tahammül: bu, simnet-derecesinde bir
  yazılımdır ve dürüstçe böyle etiketlenmiştir.

## Dürüst sınırlar (başvurmadan önce okuyun)

- Ajan seed'i asla diske değmez; **passphrase'iniz sizindir** — onu
  saklayamayız ve kaybolan bir passphrase, geri-yüklene-meyen bir anlık-görüntü
  demektir (başta söylenir, yazılı olarak kabul edilir).
- v0.1'de gerçek ödeme yok ve sandbox içinde ağ-çıkışı yok; bellek içe/dışa
  aktarımı, hash-zincirli defter ve geçiş (migration) yolu üretim-yüzeyidir.
- Node-tarafındaki `state.json`, bellek metnini düz-metin tutar (bu bir
  çalışma-kopyasıdır); depoda-gizliliğin (confidentiality at rest) işi
  anlık-görüntünümdür. Tam tehdit-modeli için SECURITY.md'ye bakın.

## Nasıl başvurulur

Başlığı `[pilot] <projeniz>` olan bir GitHub issue açın ve şunları anlatın:
ajanınız ne yapıyor, bugün hangi bellek-deposunu kullanıyor ve kabaca kaç
kayıt. Size geçiş-kapsamı anketiyle yanıt veririz. (Güvenlik sorunları BU
kanal DEĞİL — SECURITY.md'ye bakın.)

## Neden Tamga (tek-satırlık konumlandırma)

Mem0/Letta/Zep belleği tutar ama onu taşınabilir kılmaz — anahtarı satıcı
tutar ve denetim-izi (audit trail) yoktur. ERC-8004 güveni sabitler ama
durumu (state) taşımaz — ajan ölünce bellek buharlaşır. x402 ödemeyi taşır ama
işin yapıldığını kanıtlamaz. Tamga eksik parçadır: kimlik + bellek +
makbuzlar; mühürlü, sahibi kullanıcı olan, taşınabilir.
