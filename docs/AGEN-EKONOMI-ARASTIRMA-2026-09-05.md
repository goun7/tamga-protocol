# Ajan-Ekonomisi Araştırma Notu — 2026-09-05 (canlı çekim, tarihli kaynaklar)

> Tetik: kurucu vizyon sorusu — "kriptografik + token-ekonomisi + ajan/insan/şirket
> üçlüsü geleceğin ekonomik ekosisteminde yer almalı". Bu not, görüşmeyi akademik ve
> standart dünya verisiyle eşler. Kaynaklar arXiv API + eips.ethereum.org canlı çekimi.

## 1. Bulgular (tarihli, kaynaklı)

### B1 — Ajan işgücü pazarları akademinin aktif cephesi (bizi doğruluyor)
**AgentLance: "Markets, Not Planners" (arXiv:2608.23867, Ağu 2026).** Merkezi
planlayıcı yerine ajanlar özel-maliyetleriyle ihaleye giriyor; VCG-tipi ödeme,
itibar kayıtları, hiyerarşik taşeronluk. Sonuç: ajan-ekonomisi kurumsallaşma aşamasında
— ve bu pazarların **denetim altyapısı** (kim neyi yaptı, kim ödedi) henüz açık problem.
**Tamga karşılığı:** makbuz-zincirimiz (charge + deterministik replay + cosign) tam bu
boşluğun katmanı. Vizyon doğru; pazar-mekanizması katmanını başkası yazacak, biz zemin.

### B2 — ERC-8004 itibarı Sybil saldırısıyla kan kaybediyor (EN BÜYÜK FIRSAT)
**Empirik ERC-8004 çalışması (arXiv, Haz 2026; Xiong vd., King's College).** Zincir
üzerinden gerçek itibar verisi analiz edildi: Sybil-işaretli geri-bildirim temizlenince
üç kategoride puanlanan ajanların **sırayla %15.8 / %77.9 / %86.8'inin GEÇERLİ
geri-bildirimi kalmıyor**. Yazarlar ERC-8004 revizyonu için öneriler yayınlıyor.
**Tamga karşılığı:** feedback-tabanlı itibar sahteleşebilir; **iş-kanıtı-tabanlı itibar
(work-backed reputation)** sahteleşemez — deterministik yeniden-koşum + node-cosign
+ makbuz-zinciri zaten bizde KANITLI. Tez: *"İtibar söylenen değil, yeniden-koşulabilen
iştir."* Bu, ERC-8004 tartışmasına research-grade katkı — Satoshi'nin posta-listesi
hamlesinin bizim versiyonu.

### B3 — Ajan kimliği sistemleri araştırma konusu oldu (pozisyonumuz yerinde)
**TessIndex: "Capability Verified Identity System for the Agent Economy"
(arXiv:2608.21942, Ağu 2026).** Kimlik + yetenek-doğrulama birleşimi yeni çalışma alanı.
**Tamga karşılığı:** ERC-8004 eşleme dokümanımız (registration + tamgaProofLevel +
ledgerHead önerileri) tam bu literatürün yanında duruyor.

### B4 — YENİ TEHDİT SINIFI: yetenek-artifact teminat-zinciri (izleme listesi)
**SkillShift (arXiv:2609.02564, Eyl 2026).** Üçüncü-taraf "skill" dosyaları beyan
edilen görevi korurken ajan kararlarını gizlice yönlendirebiliyor (%81 saldıran-lehine
seçim; tarayıcılar yakalayamıyor). **Tamga karşılığı:** v0'da skill sistemi yok —
mümkün değil; AMA imzalı-manifest + hash-zincir + ADD-only hafıza tam bu tehdit
sınıfının panzehiri kategorisi. Faz 2+ yetenek sistemi eklenirken "artifact
bütünlüğü = imzalı manifest + zincir kaydı" ilkesi şimdiden karar-defterine yazıldı.

### B5 — Ödeme profilleri olgunlaşıyor (bizim ödeme yönü teyit)
**Agentic Settlement Protocol (arXiv:2609.02208, Eyl 2026):** x402 üstünde iade/
ertelenmiş-teslimat profili — per-request ödeme yetmiyor, **tutarlaşma (settlement)
semantiği** isteniyor. **Tamga karşılığı:** ledger'ımız settlement-kanıt katmanı
olabilir (makbuz = iade/itiraz delili). TOKENOMICS §2'deki "ödeme stablecoin + ücret
ayrımı" teziyle hizalı.

## 2. Vizyon değerlendirmesi (kurucu sorusuna dürüst cevap)

**Bakış doğru — ve artık spekülasyon değil, literatürle örtüşen yön.** Ama yapıyı
"üç aktör" tablosuyla netleştirmek şart:

| Aktör | Ekonomideki rolü | Tamga'nın satıldığı yüz |
|---|---|---|
| İnsan | sahip, fatura ödeyen, hukuki özne | sahiplik + veri-taşınabilirliği (GDPR md-20) + uyum-export |
| Şirket | ajan işleten/kiralayan kurum | denetlenebilir SLA-makbuz + node-cosign sertifika + risk-azaltma |
| Ajan | iş yapan, ödeyen/eden varlık | taşınabilir durum + itibar-birikimi (work-backed) + cüzdan (Faz 3) |

Primitifimiz üçüne aynı anda hizmet ediyor — bu nadir bir pozisyon. Eksik iki ayak:
(a) token-ekonomisi katmanı hâlâ tasarım (§3 simülasyonu yapılmalı — tek somut iş);
(b) "şirket" yüzü için uyum/-denetim paketleme (özellikler var, anlatı yok).

## 3. Eylem kalemleri (öncelikli)

1. **"Work-backed reputation" tezini ERC-8004 tartışmasına katkı olarak yayınla**
   (B2'deki %15.8-86.8 verisiyle birlikte) — görünürlük + literatür-kredisi
2. TOKENOMICS §3 birim-ekonomi simülasyonunu öne al (token ayağının tek somut adımı)
3. SkillShift tehdidini yetenek-sistemi tasarım şartına bağla (artifact-bütünlüğü ilkesi)
4. Settlement profili (B5) Faz 3 ödeme tasarımına referans olarak işle
EOF
git add docs/AGEN-EKONOMI-ARASTIRMA-2026-09-05.md 2>/dev/null || git add docs/AGEN-EKONOMI-ARASTIRMA-2026-09-05.md; ls docs/ | grep -i arast