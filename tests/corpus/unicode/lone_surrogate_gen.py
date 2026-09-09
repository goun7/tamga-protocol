# lone-surrogate JCS-ekstremi — UTF-8 dosyada TAŞINAMAZ (surrogates-not-allowed);
# bu-dosya test-içinde-bellek-içi-üretir: jcs({"a": "\ud800"}) → Python-json-ünlü-
# kaçış-yazarsa-aynı-hash-çapraz-uygulamada-ayrışabilir — Audit-18-ailesinin-sentetik-üreticisi.
S = "\ud800"  # noqa: silently-invalid-in-file — bu-dosya-src-olarak-import-edilir
