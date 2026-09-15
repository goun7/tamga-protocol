> Çeviri notu: İngilizce-orijinali (docs/WHY-HASHCHAIN.md) ile ikizdir; normatif-metin İngilizce'dir — çelişki-olursa ORİJİNAL-BAĞLAYICIDIR.

# Neden bir hash-zinciri, ve Merkle nereye oturuyor

> Tasarım-notu — spesifikasyon değişikliği yok. En sık aldığımız teknik soruyu yanıtlar:
> "defter için Merkle ağacı yerine neden doğrusal bir zincir?" ve ikiz sorusu:
> "peki Merkle'yi NEREDE kullanıyorsunuz?" Her iki yanıt da yük-taşıyıcıdır; ikisi de kaza-eseri değildir.

## 1. Defter bir zincirdir (RFC-003 D5)

`h = sha256(prev ‖ jcs(record − {h, node_sig}))` — her kayıt, kendinden öncekine
bağlanır (commit). Buradan üç özellik doğar; bir ağacın vermediği bu özellikler,
hızlı üyelik-kanıtlarından çok bir iş-makbuzu defteri için önemlidir:

**Eklenme-sırası anlam taşır.** Bir makbuz zinciri bir *anlatı*dır: grant →
charge → charge → … Her kaydın anlamı öncesine bağlıdır (oturumlar, ücret
birikimi, EN SON charge'a karşı D12 net-bağlama). Bir Merkle ağacı bir *küme*ye
bağlanır; kümelerde "önce ne geldi" diye bir şey yoktur. Sırayı geri
getirmek için diziyi nasılsa serileştirmeniz gerekir — o noktada zincir, daha
ucuz serileştirmedir.

**Kırpma, güvenilir bir çapa olmadan saptanabilir.** Zincirde, n kayıtlık bir
defterin 1..k kaydını birine vermek kesimi ele verir: alıcı `ledger_tip`
ister (F21, reason 14) ve erken duran her zincir uç çapraz-bağlantısını
geçemez. Yalnızca kökü görünen bir Merkle ağacı, "3. eleman çıkarıldı" ile
"defter zaten 3 elemanlıydı"nı, ağacın kaçınmak için tasarlandığı sıralamayı
geri getiren bir şahit-yapısı olmadan birbirinden ayırt edemez.

**Kısmi doğrulama yapıdadır, sonradan eklenmez.** Mini-doğrulayıcı
(`tamga_verify_mini.py`, stdlib-only) zinciri herhangi bir önekten yeniden
oynatır ve her başı yeniden hesaplar. Tek bir doğrulama algoritması vardır ve
90 satırdır. Bir Merkle kanıt-sistemi ise yaprak başına şahitler artı
"defterin geri kalanı"nı tutmanın kanonik bir yolunu ister — daha çok
artefakt, anlatması daha çok, yanlışlaması daha çok şey.

Dürüstçe kabul ettiğimiz maliyetler:
- **O(n) doğrulama.** Ölçeğimizde sorun değil (bellek-ölçeği sıhhat testi: tam
  paket ~20 s'de koşar; işlembaşı medyanları load~7'de 60–130 ms). Makbuz
  hacmi günün birinde O(n)'i gerçekten dert yaparsa, çözüm checkpoint'lemedir
  (çapalanmış bir ara-baş), tarihi yeniden-köklemek değil.
- **Tek uç.** Seed'i kim tutuyorsa kendine ait bir kuyruğu yeniden
  yazabilir (A3 — belgelenmiş üst sınır, gizlenmemiş boşluk değil). Bu
  rakibe verilecek cevap dış çapalamadır — ki tam da şu:

## 2. Merkle'nin yine de ortaya çıktığı yer

- **Anlık-görüntü bütünlüğü (D6):** `graph_merkle` = nodes+edges üzerinde
  sıralı hash — sırasız bir kümenin üstünde kurcalamaya-kanıtlı bir *mühür*
  (bellek). Küme için doğru araç budur. Reason 17, içe-aktarımda bir uyuşmayı
  RED yapar; belgelenmiş sınır (seed tutanın tutarlı bir mühür yeniden
  basabilmesi) aynı A3 sınırının kendisidir.
- **Dış çapalama profilleri (RFC-003 §8, v0.1 profil çalışması):** makbuz
  başlarının epoch-çapalamasıyla batch köklerinin içine yerleştirilmesi
  Merkle-yapılıdır — mühürlü bir epoch içinde bir başın bulunması bir üyelik
  iddiasıdır; üyelik iddiaları ağaçların varlık nedenidir. §4.4 kuralı
  (bilinmeyen etiket → indeterminate, asla absent) tam da bu arayüzden doğdu.
- **Bileşim, kanıtlanmış (AT-022 + Vauban PR #2, 2026-09-12):** artık bu düz
  nesir değil. Zincir-başını-batch-yaprağına çeviren izdüşüm kanıtta
  donduruldu: bir Tamga başı (D5 sha256, tam 64-hex) epoch-batch yaprak
  şemasıyla (`k256(k256(bytes32))`) kodlanır, gerçek bir epoch-10 olgu
  yaprağının (57 olgu, Sepolia-çapalı) yerini alır ve yeniden-kurulan kök
  sabitlenmiş bir fixture'a düşer — üstelik *tüm host batch'i* kontrol olarak
  bayt-birebir bağımsızca yeniden katlanır. Üçüncü eksen, sade haliyle:
  **zincir anlatıyı günlük taşır; batch ise üyeliği epoch başına tek bir
  köke sıkıştırır.** Defteri ağaca çevirmeyiz — mühürlü, taraflar-arası bir
  üyelik kontrol-noktası bir çapa değerli olduğunda *ucunu* bir başkasının
  ağacına izdüşürürüz. Yol boyunca bulunan felt-notasyonu tuzağı (baştaki
  sıfır düşmüş; integer-decode güvenli, raw-bytes çöker, right-pad sessiz
  üye-değillik) üst tarafa bir FAIL vektörü olarak sabitlendi — notasyon,
  digest'ler için bile yük-taşıyıcıdır.
- **Reddettiğimiz:** defteri "performans için" ağaçla değiştirmek.
  Performans bir Faz-2 ölçüm sorusudur (overhead taban-çizgileri mevcut), bir
  veri-yapısı sorunu değil.

## 3. Tek-cümle kural

Kümeler mühür alır (merkle); diziler zincir alır; mühürlü-batch-içine-üyelik
kanıt alır. Her yapı, maliyet modeli taşıdığı iddiayla eşleştiği yerde ortaya çıkar.
