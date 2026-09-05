# Pilot Müşteri Stratejisi — Müşterimiz "AI Ajanlar"sa Yol Haritası
(2026-09-05, kurucu sorusuna yanıt; Faz 2 çerçevesinde)

## 0. Kritik çerçeve: "ajan müşteri" aslında kim?

Ajanlar fatura ödeyemez — **ödeyen her zaman ajanın arkasındaki insan/kurum**.
Dolayısıyla "müşterimiz AI ajanlar olacak" cümlesinin operasyonel karşılığı üç
kişilikten biridir:

1. **Ajan-kütüphanesi/platform geliştiricileri** (Mem0/Letta/Zep tipi, ya da kendi
   ajanını yazan indie dev) — Tamga'yı ürünlerine gömmek isterler (B2D: business-to-developer)
2. **Ajan işleten kurumlar** (destek-botu, otomasyon kullanan şirketler) — ajanlarının
   hafızası/muhasebesi denetlenebilir olsun isterler (B2B)
3. **Ajan-pazarı yapanlar** (marketplace'ler, ERC-8004 tabanlı keşif katmanları) —
   satıcı ajanları doğrulamak isterler (B2B2B)

Pilot'ta hedef: **tip 1'den 2-3 tane design-partner.** En düşük sürtünme orada.

## 1. Ürünün tek cümlelik satış vaadi (her kişiliğe aynı)

> "Ajanın hafızası, kimliği ve iş-kayıtları şifreli ve kurcalamaya-kapalı bir pakette;
> makine ölür, ajan başka makinede kaldığı yerden devam eder — ve 'bu iş gerçekten
> yapıldı' diyebilen bir makbuz zinciri bırakır."

Demo şart. Söz değil, 30 saniyelik terminal kaydı: ajan çalışır → makine "öldürülür"
→ başka node'da ayağa kalkar → hafızayı hatırlar → makbuzu doğrulanır.

## 2. Huni (funnel) — aşama kapılı, takvim değil

| Aşama | Ne yapılır | Çıkış kriteri |
|---|---|---|
| A. Özel-demo (REV: K12 — repo en-sonda) | Kapalı-repo özel-demo turu: 30-sn demo kaydı + KURUM-PAKETI tek-sayfa ile doğrudan 5-10 hedef-ekibe ulaşım; equivalence-doc birebir paylaşım | ≥2 design-partner sohbeti |
| B. İlk temas | ERC-8004 tartışma-komüniteleri + ajan-framework Discord'ları; "adaptör yazdık, sizinkini de yazarız" teklifi | 5-10 gerçek sohbet |
| C. Design-partner | 2-3 seçilmiş ekibe **ücretsiz pilot**: MERGEN-aktarıcı tarzı göç yolunu BİZ yazıyoruz; karşılığında geri-bildirim + referans | pilot başlangıcı |
| D. Ücretliye geçiş | pilot dönüşü: self-host ücretsiz kalır; barındırma/destek/SLA ücretlenir | 1 ücretli dönüşüm |

Kill kriteri (ROADMAP ile hizalı): C aşamasında 90 günde tek design-partner çıkmıyorsa
"ağ hedefi" durur, tek-makine ürün sadeleşir — amaç cesaretle yazılıydı, ölçülü uygulanır.

## 3. Neden bizden alırlar (rekabet-cevabı, konuşmada hazır olsun)

- **Mem0/Letta/Zep hafızayı tutar ama taşımaz** — vendor'a kilitli, şifre-anahtarı
  onlarda, denetim-iz yok.
- **ERC-8004 güven çapası koyar ama durum taşımaz** — ajan öldüğünde hafıza buharlaşır.
- **x402 ödemeyi taşır ama işin yapıldığını ispatlamaz.**
- Tamga = bu üçünün arasındaki boşluk: *taşınabilir + şifreli + denetlenebilir durum.*
  Rakip değil, tamamlayıcıyız — ERC-8004 eşleme dokümanı bu tezin kanıtı.

## 4. "Ajan-müşteri" senaryosunun otomatikleşen kısmı (protokolün görevi)

Müşteri-kazanmanın ajanlara-devri — protokolün doğal işi:
- Ajan-servis kaydı (ERC-8004 registration) → keşif organik gelir
- charge-makbuz zinciri → SLA kanıtı → kurumsal satışta "kanıtla konuş"
- node-cosign L1 → "işte sertifika, denetçi gelsin" → güven tazeleme otomatik
- Deterministik yeniden-koşum → "işte aynı çıktı" demosu → stake'li doğrulama pazarı

Yani uzun-vadede GTM'nin kendisi protokolün bir özelliği olmalı: **ajanlar kendi
kanıtını pazarlar.** Faz 3'ün "itibar sorgusu" tam buna service eder.

## 5. İlk 30 gün listesi (söz değil, yapılacaklar)

1. Özel-demo paketi (KURUM-PAKETI + 30-sn demo kaydı) — repo-açılışı EN SONA (K12)
2. 30 sn demo kaydı (asciinema/GIF): öl→taşı→diril→makbuz-doğrula
3. ERC-8004 Ethereum-Magicians + x402 topluluğuna equivalence-doc paylaşımı
4. MERGEN-aktarıcı gibi **ikinci adaptör** (herhangi popüler hafıza-export JSON'u) —
   "adaptör kütüphanesi büyüyor" sinyali
5. 3 design-partner adayı listesi + birebir teklif (ücretsiz göç + kanıt paketi)
