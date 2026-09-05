# Kurucu Karar Defteri — 2026-09-05

> Bu dosya, kurucu görüşmelerinde alınan kararların sade kaydıdır. Teknik gerekçeler
> RFC'lerde, kanıtlar kanit/ dizinindedir. Add-only: karar değişirse üstüne yeni satır
> yazılır, eskisi silinmez.

| # | Konu | Karar | Ne anlama geliyor | Kanıt/durum |
|---|---|---|---|---|
| OQ-1 | İş kayıtlarına sunucu imzası pilot'ta | **Opt-in** (açık ama zorunlu değil) | Müşteri isterse açar; kurulumda zorunlu "güvenilir liste" yükü yok | L1 pilot zaten bu şekilde çalışıyor |
| OQ-2 | Güvenilir sunucu listesinin yeri | **Basit dosya** | ERC-8004 Final olana kadar elle güncellenen liste; sonrası zincir kaydına geçiş | `--node-trust` mevcut |
| OQ-3 | Devreden çıkan sunucunun eski imzaları | **İptal kuralı ŞİMDİ kodlandı** (kurucu talebi) | `--node-revoked` listesindeki sunucunun İMZALARI da geçersiz; yalnız listeden düşmek yetmez | a083eee — iptalli import RED 14 `node_id_iptal_edildi@1` |
| OQ-4 | Güvenli donanım (TEE) imzası | **Ayrı alan** (Faz 3) | Bugünkü imza alanı karıştırılmaz; TEE pilotunda kendi alanı eklenir | Tasarım notunda |
| OQ-8 | Faturalama adaleti | **Son 5 işin ortancası** (pilot) | Sunucu yoğunluğu müşteri faturasına yansımaz; ham ölçüm `fee_birebir` alanında şeffaf durur | a083eee — gürültü oranı 172× → 1.11× |
| Zamanlama | RFC dondurma | **Pilot geri-bildiriminden sonra** (Faz 2 ortası) | Dış göz görmeden kilitlenme yok | — |
| Zamanlama | Depo açma | **Pilot başlarken** | Önce "gerçekten çalışıyor" kanıtı, sonra sahne | — |
| Lisans | Lisans seçimi | **Apache-2.0** (kurucu onayı; gerekçe görüşmede anlatıldı) | Aşağıda uzun açıklama | — |
| Ödeme | Gerçek para | **Simülasyon kalır** (Faz 3 + yazılı hukuki görüş) | Vergi/KVKK/menkul kıymet soruları o kapıda açılır | — |

## Geri-bildirim planı (RFC dondurma şartı)

Dondurma ancak "verimli geri-bildirim alınabiliyor" kanıtlanınca yapılacak. Kanal planı:
1. Pilot müşteriyle haftalık 30 dk görüşme notu (yapı: ne işe yaradı / nerede tıkandı / ne istedi).
2. Repoda sorun-şablonu (açılış sonrası): hata-mesajı + komut + beklenen/gerçek.
3. Her turdan çıkan istekler ROADMAP'e "talep sinyali" satırı olarak işlenir; Faz 3
   tetikleyicisi bu satırların sayısı ve ağırlığıyla beslenir.

## Lisans gerekçesi (görüşmede sözlü anlatılanın özeti)

Apache-2.0 ile başkaları kodu alıp değiştirebilir — bu doğrudur ve bilinçli tercihtir:
- **Fork tehdidi gerçek mi?** Ajan-protokolü pazarında rakip çıkaran şey kod değil,
  dağıtımdır. Bir fork'un bizi yenmesi için aynı müşteri tabanını, güven birikimini ve
  kanıt zincirini inşa etmesi gerekir. Kodun kendisi en küçük avantaj.
- **Kurumsal alım kuralı:** Şirketler "patent riski olmayan" lisanslı kodu alır.
  Apache-2.0'da bize özgü patent-koruma maddesi var: katkıda bulunanların patentleri
  kullanıcılara otomatik açılır ama kimse bize patent davası açarsa lisansı kaybeder.
- **Ekosistem çekimi:** ERC-8004 ekosistemiyle entegrasyon yazmak isteyenler lisans
  derdi yaşamaz → daha çok entegrasyon = ağın değeri büyür = bizim payımız büyür.
- **Geri-katkı pratikte üstün gelir:** İnsanlar fork açmaktansa yukarı akışa katkı
  verirse bakım yükümüz düşer (Observability/infra dünyasında bu kalıp defalarca işledi).
- Alternatif karşılaştırması: kapalı kod → benimseme ölür; AGPL → kurumsal hukuk
  departmanları kaçar; MIT → patent maddesi yok. Apache-2.0 dengeli nokta.
