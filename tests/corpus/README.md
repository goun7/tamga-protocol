# corpus — kirli-girdi-arşivi (mükemmelliyet-yolu Boyut-2)

Her-audit-family'sinin-RED-üreten-girdileri-buraya-örnek-olarak-eklenir: birikmiş-corpus,
yeni-kodun-regresyon-taramasında-hızlı-fuzz-besleyicidir (hafızada-ki-bulgu-geri-gelmez).

| Alt-dizin | Kaynak-aile | İçerik | Binder-durumu |
|---|---|---|---|
| snapshot/ | Audit-17 | `tamper_gen.py` — 6-kurcalama-sınıfı-üretici (truncate/body-flip/header-flip/tail-flip/swap/magic-swap); observed-RED-nedenleri manifest'e-işliyor | kontrol-38-4 ✓ |
| unicode/ | Audit-18 | NFC/NFD-homoglif-null-dizeleri + `lone_surrogate_gen.py` | kontrol-38-1/3 ✓ |
| schema/ | Audit-15/16 | `state_tamper_gen.py` — 5-state-tamper-deseni-üretici (truncated/invalid-json/tip-swap/sessions-inflate/nested-deep) | kontrol-38-5 ✓ |

Binder: `tests/run_corpus_fuzz.sh` (kontrol-38; suite'in-hızlı-yolçapında-koşar) —
unicode-hash-ayrışma + audit-17-determinizm + surrogate + iki-yeni-üreticinin
determinizm/manifest-tamlık koşumları.

Eklenme-kuralı: sadece-ÜRETİCİ-ve-deterministik-(küçük-script veya-düz-dize-listesi);
binary-artifact-KOYMA — corpus-üretilebilir-olmalı. Her-üreticinin-manifest'inde
`expected`-alanı CANLI-GÖZLEMLENEN davranışı-yazar (olması-istenen-değil).
