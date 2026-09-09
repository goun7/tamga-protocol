# Tamga Protokolü — sade anlatım (kod okumadan anlaşılır)

## Bir cümleyle

Yapay zekâ ajanları (sizin adınıza internette iş yapan programlar) için **fiş defteri tutan bir sistem**: ajan ne yaparsa yapsın mühürlü bir makbuz düşer, makbuzlar sonradan değiştirilemez ve merkezi bir kuruma güvenmeden herkes tarafından kontrol edilebilir. İsim de eski Türk damgasından: **Tamga**.

## Sorun nedir

Bugün bir yapay zekâ ajanı sizin adınıza bir şey yaptığında (satın alma, rezervasyon, araştırma, ödeme) ortada tarafsız kanıt yok. Ajanın sahibi "yaptı" der, karşı taraf "gelmedi" der; para gerçekse bu kavgayı çözecek fiş bulunmaz. İkinci sorun: ajana "şu sitelere bağlanabilirsin" izni verirsiniz ama gerçekten sadece oraya bağlandığını kimin doğrulayacağı belirsizdir.

## Çözüm — üç basit fikir

1. **Her iş bir makbuz.** Ajan iş yaptığında makbuz oluşur: hangi program, hangi girdiyle, ne üretti, kaç paraya, hangi izinlerle. Makbuzlar kuyruk numaralı bir defter gibi birbirine bağlı: bir sayfayı yırtarsanız numaralar bozulur ve herkes görür. (Kasiyer fişleri gibi — ama dijital ve kendini denetleyen.)

2. **Ajan defterini yanında taşır.** Ajan bir bilgisayardan diğerine taşındığında (firma değişimi, bulut değişimi) defteri şifreli olarak yanına gider; kayıt eklemek, atlamak veya kurcalamak tek komutla anlaşılır.

3. **Kontrol tamamen bağımsız.** Alıcı veya hakem, kendi bilgisayarında, tek komutla, ajanın sahibinin yazılımına güvenmeden doğrular. Makbuzda "hangi kapılara girebilirdi" (ağ izinleri) listesi de imzalıdır; ajan izinsiz bir kapıyı açarsa makbuz kırmızı verir. Teslim edilen dosyanın parmak izi de makbuzdadır — "paket elimde bozuldu" tartışması kapanır.

## Bugün neredeyiz

- **Çalışan bir prototip var** — açık kaynak, herkes bakabilir (GitHub). Henüz **simülasyon** aşamasında; gerçek para dönmüyor.
- **Kalite iddiası boş değil:** her değişiklikte otomatik koşan **34 kontrol testi** var (yavaş modda 35); ikinci bağımsız doğrulama yöntemiyle **55/55 aynı karar** veriyor. Her iddianın altında koşulmuş test kanıtı var.
- **Bu hafta önemli bir eşik geçti:** ajanın ağ izinleri artık imzalı belgeye gömülüyor (v0.2.0 sürüm adayı). Kapsamlı hata araması yapıldı: iki turda **4 gerçek hata bulundu ve düzeltildi**, başka açık çıkmadı.
- **Ekosistemde dikkat çekiyor:** x402 topluluğundaki açık tartışmada dört farklı ekip bizimle müzakere ediyor; biri bizim test paketimizi bağımsız doğruladı, diğeri bizim çalışmamızı kendi ticari teklifinde kamu kanıtı olarak referans gösteriyor. Biz de onların kanıt araçlarını çevrimdışı doğruladık (sahtecilik girişinde kırmızı verdiğini bizzat test ettik).
- **Şimdi beklenen:** bir tarafın "onaylı test teslimatı" demesi. Gerçekleşirse prototip "gerçek dünyada uçtan uca doğrulandı" statüsüne geçecek — bunun tek komutluk hazırlığı tamam.

## Dürüst sınırlar

- Gerçek para henüz akmıyor; prototip simülasyonda.
- Şifreyi bilen bir saldırgan içeriden tutarlı sahte defter üretebilir — bunu belgeledik; çözümü bir sonraki aşama (ağ düğümü şahitliği) için planlı.
- Aynı soruna kollarını sıvamış başka projeler de var; bizim farkımız kapsam: girdi bağlama + hafıza + taşıma + ağ izinleri + ücret hepsi aynı defterde.

## İngilizce özet (PLAIN-SUMMARY)

**Tamga Protocol** gives autonomous AI agents a tamper-evident receipt ledger. Every job a
run — inputs, outputs, fees, and the network permissions it acted under — lands as a
hash-chained record that any third party can verify offline with a single command, without
trusting the agent's owner. The agent carries its encrypted ledger between hosts as one
snapshot. Status: working prototype, simulation only (no real money), 26-control acceptance
suite, schema cross-validation 55/55, two external-verification tracks live on the x402
standard discussion. The core discipline: **every claim ships with the evidence that produced
it.**
