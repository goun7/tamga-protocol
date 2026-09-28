# fnv1a64 Tekrarı — Değerlendirme (değişiklik YAPILMADI)

**Soru:** `fnv1a64` beş yerde byte-identical kopya. Ortak bir modüle taşımak değerli mi, yoksa bilinçli mi?

**Kısa yanıt:** **Karışık.** Rust tarafında **gerçek, giderilebilir bir tekrar** (aynı crate). Python tarafında **bilinçli bir mimari kararın sonucu** (bağımsız modüller). Aşağıda kanıtlarıyla.

---

## 1. Beş kopyanın tam durumu

| # | Dosya | Konum | Dil | Bağlam |
|---|---|---|---|---|
| 1 | `tests/agent-src/src/main.rs` | `fn fnv1a64` (satır 8) | Rust | crate-root binary; stdin okur, parmakizi yazar |
| 2 | `tests/agent-src/src/bin/netdemo.rs` | `fn fnv1a64` (satır 9) | Rust | **aynı crate'in** `bin/` hedefi (RFC-006 D13 net-demo) |
| 3 | `tamga_runner.py` | `def _fnv1a64` (satır 30) | Python | agent stdout mührünü doğrular |
| 4 | `tamga_verifier.py` | `def fnv1a64` (satır 339), `FNV_OFFSET`/`FNV_PRIME` (satır 46-47) | Python | stdalone zincir doğrulayıcı |
| 5 | `tamga_oracle_relayer.py` | `_fnv1a64` | Python | relayer, mührü yeniden hesaplar |

Beşi de **aynı algoritma**: offset `0xcbf29ce484222325`, prime `0x100000001b3`, FNV-1a. Rust'ta `wrapping_mul`, Python'da `& 0xFFFFFFFFFFFFFFFF` — dilin doğal taşma karşılığı.

## 2. Rust tarafı: GERÇEK tekrar, giderilebilir

**Kritik bulgu:** `tests/agent-src/` **tek bir crate** (bir `Cargo.toml`, bulunur: `tests/agent-src/Cargo.toml`). `netdemo.rs` `src/bin/` altında bir **binary hedefi**, `main.rs` crate-root.

Yani **"her crate bağımsız derleniyor" savunması geçersiz**: `netdemo.rs`, `main.rs`'in `fnv1a64`'sini `crate::fnv1a64` veya bir `mod` ile kullanabilirdi. Bu, aynı compilation-unit içinde elle kopyalanmış bir fonksiyondur.

**Değerlendirme:** Rust tarafındaki tekrar **gerçek kod-tekrarıdır** ve ortak bir `mod fingerprint { pub fn fnv1a64(...) }` veya doğrudan `crate::fnv1a64` ile giderilebilir. Maliyet: küçük (tek crate, derleme-yolunu değiştirmez).

**Ama bu bir öncelik DEĞİLDİR ve bu değerlendirme değişiklik yapmaz**, çünkü: (a) fonksiyon 6 satır, düz bir standart algoritma — yanlış olma ihtimali yok; (b) her iki kopya da kanıtlanmış şekilde aynı baytları üretir (test'lerle); (c) taşımak `netdemo.rs`'nin derleme-yoluna dokunur, ki o RFC-006 D13 net-demo fixture'ının sabit-bayt çıktısına bağlıdır.

## 3. Python tarafı: BİLİNÇLİ mimari karar

**Kanıt:** `tamga_oracle_relayer.py` `import hashlib, json, os, pathlib, subprocess, sys, time` — **tamamı stdlib**. `tamga_runner`'ı **import etmiyor**.

Bu bir kaza değil: relayer, runner'a **runtime-bağımlılığı olmayan bağımsız bir süreç** olarak tasarlanmış. Relayer'ın kendi yorumu bunu söyler (satır 9): *"fnv1a64 stamp doğrulaması (tamga_runner.py:30 ile BYTE-IDENTICAL kopya)"* — tekrar **belgelenmiş ve bilinçlidir**.

`tamga_verifier.py` de aynı şekilde stdlib-only bağımsız doğrulayıcıdır: `verify_stamp` mührünü kendi `fnv1a64`'sü ile yeniden hesaplar, runner'ı çağırmaz.

**Değerlendirme:** Python tekrarı **bağımsız-dağıtılabilir-modüller** disiplininin sonucudur (RFC-002 D1: "every operation is a single command" — her bileşen ayrı çalışır). Ortak bir `tamga_fnv.py`'ye taşımak **bağımlılık yaratır**: verifier ve relayer artık o modülü bulmalıdır. Bu, stdlib-only dağıtım felsefesini **zayıflatabilir**.

**Karşı-görüş (dürüst):** 6 satırlık bir algoritma için bağımlılık yaratmak ağır değildir; `tamga_canon` zaten `jcs` için ortak modüldür. Yani Python tarafı da taşınabilir — ama **bu bir hata değil, bir takas (tradeoff)**: tekrar vs. bağımsızlık. Mevcut seçim belgeli ve tutarlıdır.

## 4. Özet-tablosu

| Taraf | Tekrar-gerçek-mi? | Giderilebilir-mi? | Değerlendirme |
|---|---|---|---|
| **Rust** (main.rs + netdemo.rs) | **EVET** — aynı crate içinde | **EVET** — `crate::fnv1a64` | **Kod-tekrarı**; ama 6-satır-algoritma, öncelik-düşük |
| **Python** (runner + verifier + relayer) | **EVET** — 3 kopya | **Evet-ama** — bağımsız-modül-felsefesini zayıflatır | **Bilinçli-tasarım** (stdlib-only, belgelenmiş) |

## 5. Değişiklik YAPILMADI — neden

Bu görev **değerlendirme** istedi, değişiklik değil. Ve:

1. **Rust tarafı:** tek-crate içinde `crate::` kullanımı `netdemo.rs`'nin derleme-yolunu değiştirir; RFC-006 D13 fixture'ı sabit-bayt çıktısına bağlı — kanıtlanmış-parite test'lerini yeniden koşmak gerekir.
2. **Python tarafı:** mevcut tasarım **belgeli ve bilinçlidir** (relayer yorumu "BYTE-IDENTICAL kopya" der). Bunu değiştirmek mimari-kararı-değiştirmektir, refactor-değil; founder/lead kararı gerektirir.
3. **Öncelik:** 6-satır, hiçbir bağımlılığı olmayan, kanıtlanmış-doğru bir algoritmanın tekrarı — teknik-borç olarak **düşük-öncelikli**dir. README test-sayısı gibi **kullanıcıya görünen** yanlış-lar daha yüksek önceliklidir.

**Bu belge bir öneri DEĞİL** — sadece durumun değerlendirmesidir. Değişiklik kararı lead'indir.

## 6. Kanıt-çıkarımı (değişiklik-yapılmadan-önce-koşul)

Eğer Rust tekrarı giderilirse, şu test'ler **yeniden-koşulmalı** (parite-kanıtları):
- `tests/at090` (agent stdout mührü), `tests/at007` (pairing fixture agent-yolu)
- net-demo RFC-006 D13 fixture'ı (sabit-bayt çıktı)
- `tamga_runner.py` ile byte-identical-parite test'i (AT-002d gibi)

---

## 7. BOŞLUQ-3: "daemon modu tek canlı tx ile kanıtlanmış" — doğrulama sonucu

**Araştırma sonucu:** README'lerde **"daemon kanıtlanmış" veya "tek canlı tx" ifadesi YOKTUR** (grep ile tarandı). Lead'in raporundaki bu iddia README'de bulunamadı.

**Ama ilgili GERÇEK bir hata bulundu:** `README.md:175` (eski) şunu gösteriyordu:

```
# 4. Daemon başlat
tamga daemon
```

**Bu komut YOK** — `python3 tamga_runner.py daemon` → `unknown command: daemon` (kanıtlandı). Daemon modu **`tamga_oracle_relayer.py`'dedir** (cmd_daemon, satır 938), `tamga` CLI'sında değil. RFC-002 D1 bunu söyler: *"API surface: CLI + JSON stdio (no daemon, no HTTP in v0). Daemon/HTTP is the subject of v1."*

**Düzeltme (yapıldı):** README.md 4. adım artık `python3 tamga_oracle_relayer.py daemon --registry ...` komutunu gösteriyor ve neden (RFC-002 D1) notunu taşıyor.

**Daemon'un gerçek kanıt durumu (TESTS.md kayıtlarından):**
- **AT-199:** daemon-loop'un paritesi — fulfill tx receipt **status=1, gasUsed 45379** (lokal py-evm/anvil; canlı zincir DEĞİL)
- **AT-207:** **CANLI Base mainnet'te daemon-restart çift-fulfill güvenlik açığı BULUNDU** — iki tx, ikisi de status=1, **gerçek gaz yandı**. Bu bir "kanıtlanmış başarı" değil, **kanıtlanmış bir açıktı**; iki katmanlı düzeltme (daemon-disk-cache + contract replay-guard AT-210) ile kapatıldı.
- **AT-210:** replay-guard bytecode (24-byte), lokal anvil — **canlı-oracle'da HENÜZ DEPLOY DEĞİL** ("layer 1 daemon cache canlıyı korur, layer 2 hazır-bekler").

**Dürüst özet:** daemon modu **lokalde kanıtlanmış, canlı zincirde bir güvenlik açığı ortaya koymuş ve kapatılmıştır**. "Tek canlı tx ile kanıtlanmış" ifadesi README'de olmasa da, canlı-daemon yolunun tek-koşum-kanıtı **AT-207'nin çift-fulfill bulgusudur** — bu, README'de "daemon production-ready" imajı verilmesinden daha dürüst bir anlatımdır. Değişiklik-yapılmadı; bu durum sadece belgelendi.
