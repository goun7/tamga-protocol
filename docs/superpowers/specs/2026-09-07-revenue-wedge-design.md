# Tasarım — Gelir-Kolu 1+2: Doğrulama-Servisi-Teklifi + pip-Paketi

**Tarih:** 2026-09-07 · **Durum:** onay-bekliyor · **Kaynak:** private/STRATEJI-2026-09-07.md
**Karar-girdileri (kurucu):** pip-scope = tam-runner + lazy-wasmtime · servis-fiyatı = 3-kademe-bant ·
onboarding = QUICKSTART.md + README-bağlantı

---

## 1. Kol-1: Tamga-Evidence-Audit — hizmet-teklif-paketi (private/)

**Amaç:** "ilk-gerçek-$1"i-gelmesi-icine-en-kisa-yol — satışa-hazır-teklif-matrisi.
**Hedef-alıcı:** ajan-hafızası/iş-kanıtı-üreten-ekipler (x402-ekosistemi-ilk-sıra).
**Kanıt-temeli:** AT-012 + 26/27-kontrol + crossval-51/51 + 2-dış-referans (safal207, wildcherrycasa)
— teklifte-SADECE-linklenebilir-kanıtlar, iddia-yok.

### 1.1 Fiyat-modeli (3-kademe, sabit-bant)

| Kademe | Fiyat | Kapsam-çapası | Süre |
|---|---|---|---|
| Basic | **$750** | ≤3-artefakt (ledger + 1-receipt + 1-delivery) — tek-komut-tur + yazılı-özet | 2-iş-günü |
| Standart | **$1.500** | ≤5-artefakt + çapraz-köprü (--pair-charge) + açık-bulgu-matrisi | 3-iş-günü |
| Derin | **$2.500** | tam-26/27-koşum-tekrarı + manifest-imza + migrate-net-zincir-kanıtı + yazılı-rapor | 5-iş-günü |

**Çapa-mantığı:** safal207-kendi-lab'ını-$1.000-sabit-alıyor → bant-onun-altında-açılıp-$2.500-
tavana-yürüyor. **Ödeme:** 50% avans / 50% teslimat; sözleşme-şablonu-göç-paketiyle-aynı-iskelet.

### 1.2 Teslimatlar (private/HIZMET-PAKETI-DOGRULAMA.md)

1. **Teklif-matrisi** — 3-kademe×(kapsam/süre/teslimat/ödeme); NDA-öncesi-paylaşılabilir-dil
2. **Kapsam-dışı-listesi** — kod-fix'i-DEĞİL (kanıt-doğrulama); hukuki-denetim-değil; kötü-niyetli-tarafta-kanıt-üretme-DEĞİL
3. **E-posta-şablonu** — TR+EN-tek-mesajlik-teklif (link: AT-012-tests + #3379-kanıt-mesajı)
4. **Kanıt-ekleri-haritası** — hangi-artefakt-nerede-linklenir (hazır-arsiv-dizinleriyle-birebir)

### 1.3 Bilinçli-olmayanlar (scope-yok)

- Sözleşme-hukuki-metni (göç-paketi-şablonundan-devam)
- Ödeme-altyapısı (ilk-müşteri-ile: havale-veya-x402)
- Toplu-işletme/MRR-modeli (Kol-3-tetikli)

---

## 2. Kol-2: pip-paketi — `tamga-protocol` (tam-runner + lazy-wasmtime)

### 2.1 Paket-yapısı

- **PyPI-adı:** `tamga-protocol` · **versiyon:** repo-tag-paraleli (ilk: 0.2.0rc1)
- **Giriş-noktası:** console-script `tamga` → `tamga_runner.main()` — mevcut-cmds-tablosu-dokunulmaz
- **Bağımlılık:** `pynacl>=1.5` (tek-sert); **wasmtime-binary-PyPI-ARTİFACT-DEĞİL:**
  ilk-`run`-çağrısında-~67MB-indirilir → `~/.cache/tamga/bin/wasmtime`; SHA-digest-şart
  (tools/install.sh'teki-kapı-taşınır); başarısız-indirme → açık-hata (sessiz-fallback-YOK)
- validator/netproxy/net_shim-aynı-pakette-import-uyumlu

### 2.2 Kurulum-yüzeyi

- `pip install tamga-protocol` → `tamga keygen`-5-saniye (wasmtime-gerekmez)
- ilk-`tamga run`-wasmtime-lazy-indirir (tek-seferlik; digest-bağlantısı-README'de-yazılı)
- `tamga ledger-verify`-wasmtime'sız-çalışır — **doğrulama-yolçapı-saf-stdlib+nacl**

### 2.3 QUICKSTART.md (yeni, 5-dakika-yolu)

1. `pip install tamga-protocol` → 2. `tamga keygen` (seed-bir-kez-yazar) →
3. demo-pkg-kopyala + `tamga run pkg --seed …` → 4. `tamga ledger-verify pkg` (PASS-okunur) →
5. `tamga export/import`-tek-satırlık-göç. Sonda: ARCHITECTURE.md-tehdit-modeli-bağlantısı.

### 2.4 CI/ölçüm (test-katı)

- **Yeni-test:** `tests/at013_pip_sanity.sh` (kontrol-27) — izole-venv'de-`pip install .` +
  `tamga keygen` + `tamga ledger-verify` (wasmtime-YOK-çalışmalı) + import-temizliği
- pyproject-build-backend: setuptools (minimum-surpriz) · Python-3.10+
- CI: mevcut-bench-adımına-`pip install .` + `tamga --help`-smoke (ayrı-job-DEĞİL)

---

## 3. Veri-akışı / risk-taşıyıcılar

- **wasmtime-lazy-download:** MITM→digest-kapısı (tools/install.sh'ten-taşınır);
  başarısız-indirme→açık-TÜRK/İNGİLİZCE-hata + elle-yerleştirme-yolu-dökümante
- **pip-vs-repo-farkı:** repo-tools/bin-MANIFEST-exclude; pip-kurulumunda-tools/bin-yoksa-lazy-yol
- **Gizlilik:** HIZMET-PAKETI-DOGRULAMA.md-private/-(gitignored)-kalır; QUICKSTART+pyproject-public

## 4. Test-stratejisi

at013_pip_sanity (kontrol-27) — venv-izole-kurulum + wasmtime'sız-doğrulama-yolçapı;
suite-27/27-(+28-slow); badge/doküman-senkronu-A2-A4-modeli.

## 5. Başarı-ölçütü

- Kol-1: teklif-matrisi-kurucunun-ilk-e-postasına-girebilir-durumda
- Kol-2: temiz-venv'de-`pip install . && tamga keygen`-çalışır + at013-PASS + CI-yeşil
