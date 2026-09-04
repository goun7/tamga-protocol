# Tamga Protocol — Genişleme Haritası

> v2 pitch'in ötesine ne kadar ve nasıl genişleriz? Bu belge, "agentic ekonominin Bitcoin'i" hedefini ölçülebilir hale getirir ve kağıt genişlemesinin sınırlarını dürüstçe çizer.

## 0. "Bitcoin Testi": Hedefi ölçülebilir yapalım

"Agentic ekonominin Bitcoin'i" bir metafor değil, ölçülebilir dört özelliktir. Bitcoin'i Bitcoin yapan:

| # | Özellik | Bitcoin'de karşılığı | Tamga bugün | Tamga'da nasıl kazanılır |
|---|---|---|---|---|
| 1 | TEK kırılamayan primitif | Değiştirilemez, sansüre dirençli değer transferi | Yok (çok özellikli paket) | "Kendine-Sahip Ajan" primitifi (§1) |
| 2 | İnançlı tarafsızlık | Kural hiçbir tarafa avantaj vermez | Kurucu kapıları var | Tarafsızlık tasarımı (§3) + yıllarca davranışla kanıt |
| 3 | Sahipsizlik | Şirket/CEO yok; durdurulamaz | Kurucu-merkezli | Aşamalı dağıtılmayla "exit to governance" (§5) |
| 4 | Yaratıcısından uzun yaşamak | Satoshi yok; ağ çalışıyor | — | Sonuç — kağıtla üretilemez |

**Dürüst teşhis:** v2 kağıdı bu dördün hiçbirini sağlamıyor ve **kağıt tek başına hiçbirini üretemez.** Kağıdın yapabileceği üç şey: (a) primitifi tanımlamak, (b) tarafsızlığı tasarımda garantiye almak, (c) sahipsizliğe giden yolu sözleşmeleştirmek. Gerisi, yıllar içinde kazanılan bir davranış sonucudur.

## 1. Primitif: Kendine-Sahip Ajan (Self-Owning Agent)

Bitcoin değere self-sovereignty verdi. Tamga'nın tek primitifi bu olmalı: **ajana self-sovereignty.**

> **Tanım:** Kimlik anahtarları, cüzdanı, hafıza şifresi ve çalıştırma kanıtı; içinde koştuğu makinede değil, kendi elinde olan ajandır.
>
> **Tek cümlelik test:** Ajanı çalıştıran makine değiştiğinde; kimliği, hafızası ve parası kayıpsız olarak onunla gider.

Bu primitif seçilirse v2 pitch'teki tüm alt sistemler (Tier-1/Tier-2, termodinamik yönlendirme, Tamganomy) çekirdek olmaktan çıkar ve primitifi gerçekleyen **değiştirilebilir altyapı seçeneklerine** dönüşür. Bitcoin'de madencilik on beş yılda baştan sona değişti ama transfer primitifi hiç değişmedi — Tamga'da de aynı ayrım hedeflenir.

Primitifin dört zorunlu bileşeni (spec'ler bunları gerçekleyecektir):

1. **Kimlik** — ajan kendi anahtar çiftini tutar; host göremez, kopyalayamaz.
2. **Hafıza** — bağlam grafiği ajan anahtarıyla şifreli; host-kör.
3. **Yürütüm** — koşum kanıtı (attestation → zkVM). v0'daki en zayıf halka; dürüstçe işaretlenecek.
4. **Cüzdan** — makine-native alım-satım; ödemeyi ajan kendi imzalar.

## 2. Belge ağacı: kağıt ne kadar genişleyebilir?

**Tier A — ŞİMDİ** (kod kapısının önünü açar, hiçbir şeyi tetiklemez):

| Belge | İçerik | Hedef uzunluk |
|---|---|---|
| WHITEPAPER.md | Primitif + tehdit modeli + tarafsızlık tasarımı | 9–15 sayfa (Bitcoin standardı: KISA) |
| CONSTITUTION.md | Değişmez kurallar, fork süreci, insan kapıları, exit-to-governance planı | 3–5 sayfa |
| SPECS/ (4 RFC) | manifest şeması · runner API · ledger kayıt şeması · attestation formatı | her biri 2–6 sayfa |
| THREAT-MODEL.md | Varlıklar, düşmanlar, kanıt zinciri | 2–3 sayfa |

**Tier B — v0 verisi geldikten sonra:**

- ECONOMICS.md — birim ekonomi simülasyonu; token yalnız tetikleyici şartıyla bölüm başlığı alır
- NETWORK.md — node keşfi, itibar, dispute (itiraz) süreci
- STANDARDS.md — dış standartlara katkı (x402, DID); "Tamga Ajan Kimliği" teklifi
- GOVERNANCE.md — RFC süreci, yükseltme takvimi

**Tier C — ARAŞTIRMA MEMOLARI** (asla vaat cümlesi olarak yazılmaz):

canlı göç · zk yürütüm kanıtı · termodinamik yönlendirme · ZK uyumluluk predicate'leri ("ajan hukuku") · µs fast-path

Toplam adreslenebilir kağıt: ciddi içerikle **150–300 sayfa**. Ama bkz. §4: genişliğin kendisi bir metrik değil, bir borçtur.

## 3. Tarafsızlık tasarımı (kağıtta yapılabilecek kısım)

1. **Kural nötrlüğü:** primitif kuralları hiçbir node/ajan/kurucuya ayrıcalık tanımaz; ödüller yalnız ölçülmüş performansa bağlıdır.
2. **Veri nötrlüğü:** bağlam grafiği formatı açıktır; ajan verisini başka formatla da dışa aktarabilmelidir. Lock-in = tarafsızlık ihlali.
3. **Prosedür nötrlüğü:** kabul kuralları (test, kanıt) önceden yazılıdır; istisna yetkisi yoktur.
4. **Zaman nötrlüğü:** erken katılanlara kalıcı ayrıcalık yoktur. (Not: v1 pitch'teki Node Lisansı erken-avantajı bu ilkeyle çelişir; token aşamasında yeniden tasarlanacaktır.)

## 4. Genişleme borcu (expansion debt)

Erken yazılan her sayfa, sonra düzeltilmesi gereken sayfadır. Bitcoin 9 sayfaydı; gücü genişlikten değil üç şeyden geldi: **kısa primitif, 3 ayda yazılmış genesis bloğu, 15 yıllık kesintisiz çalışma.**

**Oran kuralı:** primitif dokümanlarının %70'i, vizyon dokümanlarının %30'u. Primitif spec'leri derinleşmeden yeni vizyon belgesi yazılmaz.

## 5. Sahipsizliğe giden sözleşmeli yol (exit to governance)

"Bitcoin gibi" iddiası, kurucu-merkezli başlangıçla açık çelişir. Çözüm: çelişkiyi saklamak değil, takvimlemek.

- **v0–v1:** kurucu kapıları açıkça ilan edilir (dürüstlük, gizlilik değil).
- **v1→v2:** node yazılımı çoklu-bağımsız dağıtıma açılır; kabul kuralları RFC'ye bağlanır.
- **v2:** kurucu anahtar yetkileri zaman kilitli sözleşmelere devredilir; "kurucu kapalı gün bile ağ çalışır" hedefi bir kilometre taşı olarak ölçülür.

## 6. Kağıdın gücünün sınırı (dürüstlük bölümü)

- Tarafsızlık ve sahipsizlik kağıtta **iddia** edilir; yıllarca davranışla **kanıtlanır.**
- Bitcoin'i Bitcoin yapan 9 sayfalık makale değil, ağın on beş yıldır durmamış olmasıydı. Tamga'nın eşdeğeri: v0'dan itibaren kesintisiz çalışan, dış node'ların koşabildiği, kurucunun kapattığı gün bile yaşayan bir ağ.
- Bu yüzden hedef en geniş kağıt değil; **en kısa primitif + en uzun kesintisiz çalışma** olmalıdır.

## 7. Sıradaki üç belge (sırayla)

1. **WHITEPAPER.md taslağı** — primitif tanımı + tarafsızlık tasarımı (bir sonraki oturum)
2. **CONSTITUTION.md** — değişmez kurallar + exit-to-governance planı
3. **RFC-001: Ajan Paket Manifest Şeması** — ilk kod kapısı (T+90'ın ilk günü)
