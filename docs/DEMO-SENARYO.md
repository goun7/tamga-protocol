# 30-Saniyelik Demo — Beklenen Akış

> Betik: `tools/demo.sh` · Kayıt: `asciinema rec -c "bash tools/demo.sh" demo.cast`
> Kısa-GIF seçeneği: kaydı Terminalizer/svg-term ile çevir veya "script" ile screenshot serisi.
> (Kayıt beklenen-akışın çıktısını birebir gösterir; her koşumda hash/ID'ler değişir — bu normaldir.)

## Beklenen akış (2026-09-05 canlı-doğrulandı)

| Adım | Komut-özü | Beklenen |
|---|---|---|
| 1 | keygen | ajan kimliği üretilir; seed diske YAZILMAZ |
| 2 | run --input girdi.json --require-proof | `koşum ok: True \| ücret: ~1e-4..1e-3` |
| 3 | export | `snapshot: ~2.2KB \| gövde-düz-metin taraması: 0` |
| 4 | import (farklı dizin/node) | `import ok: True \| ajan: <id16>… \| restore-düğüm: 4 \| devam-oturumu: 1` |
| 5 | ledger-verify + memory --search "node1" | `ledger-verify ok: True` · `hafıza-hatırlama: node1-de doğdu` |

## Anlatım-çerçevesi (konuşurken)

1. "Ajan doğdu ve **girdili iş** yaptı — girdi hash'i makbuza bağlandı." (Dilim-11)
2. "Makine öldü; ajan **şifreli** pakette taşındı — host içeriği okuyamaz."
3. "Yeni host'ta **kaldığı yerden** devam etti — kimlik+hafıza onunla geldi."
4. "Makbuz zinciri hedefte doğrulandı — **bu iş yapıldı** iddiası artık doğrulanabilir."
