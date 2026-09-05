# Kurum Paketi — "Şirketim neden ajanına Tamga giydirmeli?" (tek sayfa)

> Hedef okur: ajan/otomasyon işleten şirketin teknoloji-lideri. Teknik-jargon minimum;
> her iddia ya kanıta ya "plan" etiketine bağlı (kanıt-kültürü: vaat ≠ demo).

## 1. Probleminiz (bugün yaşadığınız)

Şirketiniz bir AI ajanı işletiyorsa üç sessiz risk taşıyorsunuz:

1. **Kilitlenme:** Ajanın hafızası vendor'ın formatında ve sunucunda. Vendor değişmek =
   hafızayı kaybetmek. Ajan sizin değil, vendor'un.
2. **İspat edilemeyen iş:** "Ajan bu işi yaptı" diyorsunuz — kanıtınız sohbet-logu.
   Müşteri/küratör/denetçi sorduğunda *yeniden gösteremezsiniz*, yeniden *koşturamazsınız*.
3. **Denetlenebilirlik borcu:** Ajan hatası bir müşteriye zarar verdiğinde "ne oldu,
   kim ödedi, hangi veriyle" sorusunun zincirli cevabı yoksa, cezayı siz ödersiniz.

## 2. Tamga'nın cevabı (her iddiaya kanıt)

| İhtiyaç | Tamga mekanizması | Kanıt |
|---|---|---|
| Ajan sizin olsun (vendor-bağımsız) | Şifreli taşınabilir snapshot: kimlik+hafıza+muhasabe tek pakette, anahtar SİZDE | taşıma testleri; 900-ders gerçek göç (Eyl 2026) |
| "İş yapıldı" diyebilesiniz | Hash-zincirli iş-makbuzu; aynı girdi → birebir aynı çıktı (yeniden koşturulabilir) | determinizm kaydı; adversarial Audit-8 |
| Kurcalama anlaşılsın | Zincir bozulursa RED — sahte makbuz üretilemez | truncate/splice saldırı testleri (Audit-4/7) |
| Sunucunuz da yalan söylemesin | node-cosign: sunucu kendi sertifikasıyla makbuzu mühürler; iptal listesi devreden-çıkanı geçersiz kılar | Audit-8; iptal-RED 14 kanıtı |
| Veri tesisinizden çıkmasın | Varsayılan-yasak koşum: ağ yok, dosya yok, ortam-değişkeni yok | default-deny tasarımı, wasmtime sandbox |
| Uyum (GDPR md.20 veri-taşınabilirliği) | Ajan-hafızası **standart pakette** dışa aktarılabilir — "veriyi taşı" hakkına ajan-çeşidi | export/import sözleşmesi (RFC-002) |

## 3. Ne DEĞİL (dürüst sınırlar — satın-alma kararına girenler için)

- Üretim-ağı değil (Faz 2 pilot); gerçek-para akışı Faz 3 + hukuki görüşle
- Kullanım-anı gizlilik (TEE) Faz 3'te; bugün bekleyen-veri kanıtlı, çalışma-anı değil
- Tek-makine ölçeğinde olgun; çok-node ledger birleşimi yol-haritasında

## 4. Pilot teklifi (design-partner)

Ücretsiz: hafıza-göçünü BİZ yapıyoruz (MSSQL/Postgres/Mem0-export → şifreli snapshot),
tek koşul: 4 hafta geri-bildirim + referans hakkı. Pilot çıktısı size: denetlenebilir
ajan-muhasebesi raporu + vendor-bağımsız hafıza arşivi. (İletişim: repo Issues.)

## 5. "Bunu zaten LangGraph + şifreli-DB ile yaparız" diyenler için

Uygulamanızın sürekliliği için checkpointer en hızlı yoldur — doğru. Fark: **kimliğin
kimiolarını, kurcalama-direncinin kimde olduğunu ve iş-makbuzunun protokol-düzeyinde
olup olmadığını** sorar. Karşılaştırma tablosu: [REKABET-HARITASI.md §5](REKABET-HARITASI.md).

---
*Kanıt-kültürü: bu sayfadaki her "kanıt" hücresi, depodaki log'la eşleşir (kanit/).*
