# Güvenlik Politikası

## Desteklenen sürümler

| Sürüm | Destek |
|---|---|
| `main` | ✅ aktif geliştirme hattı |

Bu proje **Faz 2 (pilot)** aşamasındadır: simnet ortamı, gerçek-değer taşıma yok
(`TOKENOMICS`/`ROADMAP` kapsamı). Üretim-kullanımı için tasarlanmamıştır.

## Zafiyet bildirimi

1. **Tercih edilen yol:** GitHub [Security Advisories → Report a vulnerability]
   (özel iletişim; kamuya açık issue AÇMAYIN).
2. **Alternatif:** depo sahibiyle doğrudan iletişim (profildeki e-posta).

## Bildirimde beklenenler

- Etkilenen bileşen (runner / validator / şema / aktarıcı) + sürüm/commit
- Yeniden-üretim adımları (komut + beklenen vs gerçek)
- Varsa: `reason_code` akışı ve kanıt-log çıktısı

## Bildirimin akışı

1. 72 saat içinde ilk dönüş
2. Doğrulama → `SECURITY-AUDIT.md`'ye F-numarası ile kayıt (eklenir, silinmez)
3. Düzeltme → kanıtlı kapanış (negatif-vektör testi zorunlu) → sürüm-notu

## Kanıt-kültürü

Her düzeltme bir negatif-vektörle kilitlenir; "çalışıyor" iddiası log'suz kabul
edilmez — bkz. [SECURITY-AUDIT.md](SECURITY-AUDIT.md) (10 denetim turu, F-bulgu tablosu).
