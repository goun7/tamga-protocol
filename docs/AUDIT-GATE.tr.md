> Çeviri notu: İngilizce-orijinali (docs/AUDIT-GATE.md) ile ikizdir; normatif-metin İngilizce'dir — çelişki-olursa ORİJİNAL-BAĞLAYICIDIR.

# Denetim-Kapısı (Audit Gate) — her değişikliğin geçtiği 8 adım

Kapıyı geçmeden hiçbir commit girmez; kapı RED ise commit de yoktur —
düzelt, yeniden-koş, tekrarla:

1. `python3 -m py_compile` — değinilen her `.py`
2. `bash tests/run_all.sh` → hızlıda 52 PASS (RUN_SLOW=1 ile 57); yetkili alt-satır
   sayıyı taşır — asla ayrı bir iddia olarak koda-gömülmez (aşağıdaki sayaç kuralına bak)
3. Negatif vektörler: AT-001f (3 beklenen-RED + 1 önkoşul kontrolü) + AT-003 (6/6) — beklenen-RED
   fixture'lar RED kalır
4. Şema çapraz-doğrulama: 34/34
5. Yeni kod → en az bir negatif vektör (beklenmedik-ACCEPT testi)
6. Kanıt-günlüğü: yalnızca sayı içeren, hash'lenmiş koşu-günlükleri; gereksiz içerik yok
7. Güvenlik öz-gözden-geçirme satırları: enjeksiyon, salt-okunur kaynaklar, gizlilik taraması, geriye-uyum
8. Gizlilik: depoya hiçbir kişisel veri girmez (.gitignore + düz-metin taraması)

## Counter rule (sayaç kuralı — drift belgesidir)

Her sayaç-baytatı (kontrol-sayısı, vektör-sayısı, EN-payı, sürüm-dizgisi) YANINDA ya
`run_all` tail-line'ından-türer ya da son-doğrulama-TARİHİ-taşır. Salt-sayaç-yazan-bayt
(düz "N/M PASS") bayatlama-sayılır: süpürme-deseni bunları plain "N/M", markdown-link
metni VE shields.io %20-URL-kodlu haliyle-aramalıdır (47/47 rozeti böyle-kaçtı, f917f24).

## Neden bir kapı

Projenin kuralı şu: otonom bir adım, koşabilir kanıt olmadan *"doğru, eksiksiz,
zafiyetsiz"* iddiasında bulunamaz. Kapı, bu iddiayı çıktısı arşivlenen
komutlara dönüştürür.

## Açıklama (Disclosure)

Bir zafiyet mi buldunuz? Halka-açık issue **açmayın** — bkz. [SECURITY.md](../SECURITY.md).
