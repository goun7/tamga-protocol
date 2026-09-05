# Tamga Yol Haritası — Aşama Kapılı

> İlke: takvim değil kapı. Her fazın çıkış kriteri ölçülebilir; kriter dolmadan sonraki faz başlamaz. Her fazın kill kriteri vardır — küçük öl, büyük ölme.

## Faz 0 — Kağıt Donması (şimdi)
- **İş:** WHITEPAPER v0.1-final · RFC-001 manifest şeması **(DONDURULDU 2026-09-02 — v0.1-FINAL)** · RFC-002 runner API **(DONDURULDU 2026-09-02 — v0.1-FINAL)** · RFC-003 ledger kaydı · RFC-004 attestation formatı (taslak). Proje adı: **Tamga Protocol** (2026-09-02). AT-001a: **6/6 vektör kanıtlı** (kanit/AT-001/2026-09-02/AT-001a.log).
- **Çıkış kriteri:** primitif tanımı donduruldu; RFC'ler kurucu onaylı; AT-001 testleri yazılı ve kırmızı.
- **Kill kriteri:** yok (maliyet düşük).

## Faz 1 — v0 Genesis (hafta 1→12)
- **İş:** test-önce dikey dilimler: (1) manifest+runner koşum **✔ kanıtlı** (kanit/FAZ1/2026-09-02/dilim-1.log), (2) bağlam grafiği+şifreli snapshot **✔ kanıtlı** (dilim-2.log), (3) taşıma **✔ kanıtlı** (dilim-2/3.log), (4) muhasebe+simüle ödeme **✔ omurga kanıtlı** (RFC-003 bekliyor), (5) AT-001 tamamı — **✅ PASS 2026-09-02 (a 6/6 + b/c/d/e; kanit/AT-001/2026-09-02/)**, (6) katılım yüzeyi: halka açık repo + build-in-public simnet logları. **Dilim-3 ✔:** gerçek WASI 0.3 koşumu — wasmtime v48.0.1 (digest-doğrulamalı), süreç-izole, D4 default-deny; motor: `tools/bin/wasmtime`; ajan: `tests/agent-src/`. Güvenlik denetimi: SECURITY-AUDIT.md (Audit-1/2/3/4) — her dilim sonunda denetleme kuralı işliyor. **Dilim-5 ✔:** ledger hash-zinciri + `grant`/`ledger-verify` (RFC-003 D4/D7 taslak gerçeklemesi) — kanit/FAZ1/2026-09-02/dilim-5.log. **Dilim-6/7/8 ✔ (2026-09-03):** F21 truncate-panzehiri (`ledger_tip` state'e yazılıyor, reason 14) · çapraz-import RED kanıtı · **F24 kapanışı: ledger snapshot'la seyahat eder** (gömülü `ledger_records` + tip bağlama) · merkle kurcalama RED (reason 17) · tek-komut regresyon takımı `tests/run_all.sh` (15 kontrol: 14 + AT-001f negatif vektör bölümü, POSIX çıkış-semantiği, PIPESTATUS ile boru-koruma) — kanit/REGRESYON/2026-09-03/. **Dilim-9 (2026-09-05):** AT-001f negatif vektör fabrikası — reason 7 (SAFE_SNAP_MAX aşımı) / 9 (header agent_id taklidi) / 8 (replay rollback) beklenmedik-KABUL kapanışı; kanit/AT-001/2026-09-05/AT-001f-vektorler.log. RFC-002 E-9 errata'sı işlendi (2026-09-05). **RFC-003/004 TASLAK'ta — kurucu onayı bekliyor.**
- **Çıkış kriteri:** AT-001a-e yeşil + kanıt dosyaları mevcut **(✅ 2026-09-02: AT-001a 6/6 + b/c/d/e PASS — kanit/AT-001/2026-09-02/)**; T+90: 3+ kendi ajanı v0 üzerinde üretimde koşuyor.
- **Kill kriteri:** hafta 12'de AT-001b/d (taşıma + host-körlük) yeşile gelemiyorsa kapsamı sadeleştir — taşıma primitifidir, diğer her şey pazarlıktır.

## Faz 2 — v0 Sertleşmesi (ay 4→6)
- **İş:** 1 dış pilot müşteri; performans ölçümü (runner overhead ms cinsinden beyan); kanıt kültürünün dış node şahitliğinde testi; birim ekonomi simülasyonu (TOKENOMICS §3) çalıştırılır; hafıza içe-aktarma adaptörleri (**MERGEN** → Mem0 → Letta → Zep → Tamga snapshot) — mevcut ajanlara sıfır-sürtünmeli göç yolu = birincil katılım kaldıracı. MERGEN ilk sıra: sahibi biziz (kurucu projesi, /MERGEN), şeması dosyadan biliniyor, ilk adaptörün test maliyeti en düşük (bkz. MERGEN-ENTEGRASYON-NOTU.md). (2026-09 pazar notu: Mem0 51k+ ★ / $24M / 100k+ geliştirici — adaptör pazarı gerçek ve büyüyor; LoCoMo/LongMemEval/BEAM benchmark'ları ölçüt.)
- **Çıkış kriteri:** pilot aktif; ölçülmüş overhead beyanlı; break-even kullanım eşiği hesaplı.
- **Kill kriteri:** 6. ay sonunda dış talep sinyali yoksa "ağ" hedefi durdurulur; v0 tek-makine ürün olarak sadeleştirilir.

## Faz 3 — v1 Ağ (ay 6→18) — TETİKLEYİCİLİ
- **Tetik:** Faz 2 metrikleri (dış node sayısı, pilot geliri, simülasyon eşikleri).
- **İş:** node keşfi+itibar — **ERC-8004 kayıt sözleşmeleriyle (kimlik/itibar/doğrulama) uyumlu tasarlanır** (2026-09-05 teyidi: hâlâ Draft — Identity Registry ERC-721 tabanlı, Reputation/Validation kayıtları ayrı; ajan kayıt-dosyası `registration-v1` şeması `x402Support` + `supportedTrust` alanları taşıyor — Tamga manifest'i eşlenebilir tutulur); gerçek mikro-ödeme (x402 vs L1 channel — prototip ölçümüyle karar; x402: Nisan 2026'da 165M+ işlem / ~69k aktif ajan / ~$50M kümülatif — dürüst not: hacmin kabaca yarısı test trafiği olabilir, gerçek-ticaret payı ölçümü v1 öncesi şart; ağ: Base + Solana); TEE pilot (bulut enclave — Nitro/SEV-SNP; Intel TDX'i de izle); AT-002 test ailesi.
- **Kill kriteri:** ödeme entegrasyonu ücret geliri ≤ node işletme maliyeti ise ağ büyütme durdurulur.

## Faz 4 — v2 Protokol (ay 18+) — ÇİFT TETİKLEYİCİLİ
- **Tetik 1:** Faz 3 traction metrikleri. **Tetik 2:** yazılı hukuki görüş (menkul kıymet analizi).
- **İş:** state channel/kanıt katmanı, zkVM yürütüm kanıtı, yönetişim ağı, exit-to-governance başlangıcı; araştırma memoları (canlı göç, termodinamik yönlendirme) yalnız bu fazda gündeme alınır.

## Metrik Panosu (her faz sonunda güncellenir)

| Metrik | Faz 1 | Faz 2 | Faz 3 |
|---|---|---|---|
| AT-001 durumu | yeşil | yeşil (regresyon) | — |
| Kendi ajan sayısı | 3+ | 5+ | — |
| Dış node | — | 1 pilot | 5+ |
| Ölçülmüş overhead | beyanlı | beyanlı | iyileşme |
| Dış gelir | — | pilot | ücret > maliyet yüzdesi |
