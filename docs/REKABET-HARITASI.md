# Rekabet/Bitişiklik Haritası — "Bu işi yapan protokol var mı?" (2026-09-05 canlı tarama)

> Soru: kurucu. Yanıt yöntemi: arXiv canlı API çekimi + daha önce kanıtlanan pazar
> taraması (findings.md, 2026-09-05: x402/ERC-8004/Mem0/Letta/Zep). Aşağıda her komşu
> için ne YAPTIĞI ve ne YAPMADIĞI dürüstçe ayrılmıştır — iddiasız harita.

## 1. En yakın akademik komşu: MutMem-V2 (arXiv:2609.01235, Eyl 2026)

**Yapıyor:** kalıcı ajan-hafızasında kriptografik-yetkili mutasyon; taşınabilir
doğrulama sözleşmesi (kanonik bayt, commitment, kanıt-membership, kimlik-epoch'ları,
İPTAL, makbuzlar); Node+Python bağımsız gerçekleme, conformance korpusu (72/72, 42/42).
**Yapmıyor:** ekonomi/ücret/makbuz-ücreti (yok), koşum/deterministik-replay (yok),
host-ötesi taşıma-snapshot'ı ile kimlik+ücret birlikteliği (yok), node-cosign ağ-güveni (yok).
**Hüküm: RAKİP DEĞİL, ÖNCÜL-KOMŞU.** İptal + makbuz + kimlik-epoch tasarımı bizim
node-revoke + charge + agent_id bağını akademik olarak teyit ediyor; kendi
supersedes-modelimiz için de okunacak kaynak. (Nezaket: Fork/olası iş-birliği notu Faz 2.)

## 2. Kavram-uzayı komşuları (gerçekleme yok)

- **Afterlife Delegation Protocol (arXiv:2608.15405, ERC-10001 TASLAK):** "fonu+hafızası
  olan, sahibinden sonra yaşayan blockchain-ajanı" — spekülatif-tasarım (sci-fi yöntemi);
  çalışma gerçeklemesi yok. **Ders:** "ajan=fon+hafıza taşıyan varlık" kavramı artık
  ERC-tasarımlarında — bizim tamga-snapshot tezimizin kavramsal önceli doğrulanıyor.
- **Self-Sovereign Agent (arXiv:2604.08551, Mar 2026 — Qu, Zhao, Zhang, Dawn Song):**
  alan-çalışması: ajanların kendi ekonomik-varlığını sürdürmesi teknik-engelleri ve
  güvenlik/yönetişim riskleri. **Ders:** alan meşru ve ciddi oyuncularca çalışılıyor;
  bize referans-çapa.

## 3. Endüstri parçaları (aynı işi BÜTÜN yapan yok)

| Oyuncu katmanı | Yapıyor | Yapmıyor |
|---|---|---|
| Hafıza (Mem0/Letta/Zep) | bellek yönetimi/arama | taşınabilirlik, uçtan-uca şifre, iş-kanıtı |
| Güven çapası (ERC-8004) | keşif+itibar/doğrulama kayıtları | durum taşıma; itibarı Sybil'e açık (bkz. docs/AJAN-EKONOMISI-ARASTIRMA-2026-09-05.md B2) |
| Ödeme (x402 + cüzdan-servisleri*) | per-request ödeme | iş-kanatı, durum, makbuz-zinciri |
| Koşum izolasyonu (WASM motorları) | sandbox | kimlik/ücret/taşıma üst-katmanı |

*cüzdan-servisleri ayrıntısı Faz 2 taramasında teyit edilecek (ad-koymadan önce kanıt).

## 4. Hüküm

**"Şifreli taşınabilir ajan-durumu + kanıtlanabilir-iş muhasebesi + ekonomi-kancaları"
bütününü yapan protokol: taramada BULUNAMADI.** En yakın komşu MutMem-V2 bütünlük
katmanında; ekonomi+bütünlük birlikteliği boşluk. Bu boşluk bizim pozisyonumuzdur —
ve MutMem-V2'nin varlığı bu boşluğun *gerçek bir araştırma-konusu* olduğunu kanıtlar
(boşlukta tek başına olmak = ya öncü olmak ya yanlış yerde olmak; MutMem + AgentLance +
TessIndex üçlüsü yanlış yerde olmadığımızı gösteriyor).
EOF
echo "REKABET-HARITASI yazıldı"; ls docs/
## 5. v2 Taraması — LangGraph-checkpointer ve "moat-cevabı" (2026-09-05, Tur-4 telafi-7)

Tur-4'ün itirazı: "LangGraph checkpointer + şifreli-DB + x402 inandırıcı DIY-stack;
bununla senin farkın ne?" Cevap önce dürüst kabul: **o stack birleşimde ÇALIŞIR** —
ve tek-framework içi süreklilik için en hızlı yoldur. Fark tablosu (LangGraph
persistence/checkpointer dokümantasyonu 2026-09-05 canlı-doğrulamalı):

| Boyut | LangGraph checkpointer (+şifreli-DB+x402) | Tamga |
|---|---|---|
| Kimlik sahipliği | thread_id / config — **altyapı-sahibinin** | ed25519 ajan-anahtar çifti — **ajanın**; seed diskte-düz-değil (şifreli keystore) |
| Durum-koruma | checkpointer'ın DB'si ne kadar güvenliyse o kadar; şifreleme DEPLOYMAN kararında | paketin İÇİNDE uçtan-uca (XChaCha20-Poly1305+scrypt); host-dışı aktarımda da şifreli |
| Kurcalama-direnci | DB-bağımlı; hash-zincir/kurcalama-RED dilinde değil | ledger hash-zinciri + graph_merkle + ledger_tip → truncate/splice RED (adversarial testli) |
| Taşınabilirlik | framework-şeması-bağlı (checkpoints tablosu, thread kavramı) | framework-bağımsız snapshot (tamga-snapshot/1); farklı host, farklı yığın |
| Ödeme | x402 ayrıca eklenir; ödeme↔iş bağlantısı uygulamacının işi | iş-makbuzu (charge) protokol-düzeyinde; ücret ölçüm+medyan-adaletle makbuzda |
| Kapsam | **graf-yürütümü çerçevesi** (LangGraph uygulamaları) | framework-agnostik durum+kanıt katmanı (graf-yürütümü DEĞİL — kasıtlı sınır) |

**Moat-cevabı (tek cümle):** LangGraph-stack *uygulamanın* sürekliliğini verir; Tamga
*ajanın* sahipliğini, kurcalama-direncini ve faturalanabilir-iş kanıtını verir — birincisi
uygulama-seçimi, ikincisi altyapı-sözleşmesi; çakışan yer hafıza-depolama satırıdır ve
orada Tamga'nın ayrışması şifreleme+kurcalama-RED'in **protokol-düzeyinde** olmasıdır.

**Dürüst sınırlar (v2 taraması):** (1) LangGraph için onlarca katkı-yıllık ekosistem var —
bizim "adaptör" tezimiz (Mem0-gibi hafıza-export → Tamga) onların kullanıcı-tabanına
köprü kurma stratejisidir, rakip-iddiası değil; (2) TEE-altyapıları (Phala vb.) bu taramada
derinlemesine incelenmedi — Faz 3 öncesi ayrı tarama kalemi; (3) skill/artifact bütünlüğü
(SkillShift tehdidi) endüstride henüz kimse protokol-düzeyinde çözmüş görünmüyor —
imzalı-manifest ilkesi bizim başlangıç-avantajı adayı (Faz 2+ yetenek-sisteminde kanıtlanacak).
