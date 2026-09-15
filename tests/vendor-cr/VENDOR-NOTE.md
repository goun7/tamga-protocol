# VENDOR-NOTE — tests/vendor-cr/ (Tamga tarafı kayıt; upstream DEĞİŞTİRİLMEDİ)

Kaynak: https://github.com/anomly-labs/computation-receipts @ commit 9450cfda82b6
(main, 2026-08-26T19:23:53Z — gh api ile doğrulandı). Lisans: Apache-2.0 (LICENSE aynı-dizin).

| Dosya | sha256 | Durum |
|---|---|---|
| spec/CR-v0.1-conformance-vectors.json | 2e940bf3006d95481690c9f264b9f1a4d23b076db4793a046c8abf940eb13e02 | byte-identical |
| python/conformance_runner.py | 4e9216e85ba1bd727c595cf7246eb9730654ed4bf6a508ed5336e1e8b97b2e2f | byte-identical |
| LICENSE | (upstream Apache-2.0 tam-metin) | byte-identical |

Neden-vendored: AT-029 cross-proof kontrolü ağa-bağlı-olamaz (CI determinizm-kuralı: suite
tek-hariç-with offline-koşar — vektör-verisi kabul-kanıtıdır, taze-indirme ile değişebilir-
girdi OLAMAZ). Drift-koruma: tests/at029_cr_crossproof.sh bu-iki-hash'i kendisi-doğrulur;
upstream-güncellenirse kontrol KIRMALI (sessiz-kayma yok) — taze-vektör-bilinçli-kopyalanır.

Tarafsızlık notu (cross-proof'un anlamı): runner upstream'in kendisinden-alıntı, TAMGA
DEĞİŞTİRMEDİ — aday-çıktıyı üreten kod tools/cr_crossproof.py'dır ve SADECE Tamga'nın kendi
jcs yolu (tamga_verify_mini.jcs — epoch-anchor digest'lerinin koştuğu AYNI fonksiyon) +
stdlib (hashlib, struct) kullanır. Yani: Anomly'nin hakemi, Anomly-kodundan-bağımsız bizim
muskülümüzü notluyor. Kapsam-dürüstlüğü: yalnız canonicalisation-katmanı (8 vektör) iddia
edilir; receipt/chain/refuse katmanı CR-aritmetik-semantiğidir — Tamga CR-certifier DEĞİLDİR.

Bağlam: in-toto/attestation PR #592 yorumunda karşılıklı-teklif edildi (2026-09-15,
goun7 5679421331 — "someone other than the author running it", aynı-saygı karşılığı).
