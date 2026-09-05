# Otonom Çalışma Denetim Kapısı (2026-09-05'ten itibaren her dilim için ZORUNLU)

Kurucu talimatı: otonom adımlarda "hatasız, eksiksiz, güvenlik-açığı-olmayan" güvence.
Her commit ÖNCE bu kapıdan geçer; kırmızıysa commit YOK, düzelt-koşu tekrarı:

1. `python3 -m py_compile` (dokunulan her .py)
2. `bash tests/run_all.sh` → 16/16
3. Negatif vektörler: AT-001f (4/4) + AT-003 (6/6)
4. Şema çapraz-doğrulaması: 34/34
5. YENİ kod → en az bir negatif vektör (beklenmedik-KABUL testi)
6. Kanıt logu: kanit/<KONU>/<tarih>/ — sayı+hash, gereksiz içerik yok
7. Güvenlik-özdenetim satırları: SECURITY-AUDIT.md'ye ek (injection, salt-okunur,
   gizlilik-taraması, geriye-uyum)
8. Gizlilik: kişiye-özel veri repo'ya GİRMEZ (gitignore + düz-metin taraması)
