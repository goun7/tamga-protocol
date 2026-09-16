# MIGRATION-DEMO — yabancı kaynak-kodun zarfa göçürülmesi (2026-09-15 gece)

**Konu:** `b3sum` v1.8.7 — BLAKE3 ekibinin **yayınlanmış, bizim-olmayan, gerçek** CLI'ı
(MIT OR Apache-2.0, github.com/BLAKE3-team/BLAKE3). Amaç RFC-008'in "göç kalptir" iddiasını
kendi-şablonumuz **dışında** kanıtlamak: 2026-09-15'e kadar bu cümle yalnız kendi
`templates/agent.wasm`'ımızla kuruluydu.

## Üç-dürüst-adım (senaryonun kendisi = `scripts/migrate_ext_b3sum.sh`)

1. **Derleme-gerçeği.** `cargo build --release --target wasm32-wasip2` **doğrudan component**
   üretir (header `0d 00 01 00`) — `wasm-tools component new`/adapter bile gerekmez. Yorum:
   runner'ın component-sniff'i (`tamga run`, rc13 kapısı) yabancı derleyici-çıktısını olduğu
   gibi kabul eder; şablon-bağımlılığı YOK.
2. **Sandbox-gerçeği (en-öğretici-kısım).** Stock b3sum **çalışmaz**: thread-pool kurmaya
   çalıştığı anda wasmtime `ENOTSUP (os error 58)` verir ve süreç **fail-loud** düşer.
   Bu bir eksik değil, bir **sözleşmedir**: yarım-sessiz-degradasyon yerine hiç-çalışmama.
   Yama envanteri 3 noktaya düşer ve üçü de kaynakta `[tamga-migration-patch]` etiketiyle
   durur: (a) `mmap+rayon` feature-bağı çözülür, (b) thread-pool kurulumu kalkar (aynı gövde
   inline çalışır), (c) hızlı-yol düz reader'a iner. **Hash-mantığına tek-satır-dokunulmadı.**
3. **Zarf-gerçeği.** Manifest (pinned `wasm_sha256`) → `keygen` → `sign` → `validate` →
   `run --input` → `ledger-verify` → `export`. Üç-yollu parite: bare-wasm stdout == envelope
   stdout == referans-değer. Cümle: **zarf, motorun sonucunu değiştirmez — yalnız kanıt ekler.**

## Ölçümler (1 MB girdi, medyan-15, bu-makine; ham: `.evidence/MIGRATION-DEMO/2026-09-15/METS.txt`)

| katman | süre | ne-ölçüyor |
|---|---|---|
| native x86 `b3sum` | 9.7 ms (min 3.0) | taban |
| bare wasmtime v48.0.1 | 26.0 ms (min 20.8) | wasm-tax ≈ 2.7× native |
| tamga envelope-net | 37.6 ms | +11.6 ms **protokol-vergisi** = manifest-validate + ledger-append + receipt-seal + stdout-disk + state-IO (Python-startup 108.5 ms çıkarılmıştır) |

`fee_sim` = `cpu_saat×0.002 + ram_gb_sn×0.0005 + io_mb×0.001` (simnet-sabiti, RFC-003 §7-pinli; gerçek-fiyat Phase-2-pilot-kapısı) — 2026-09-16 reprodüksiyon koşumu: **1.5552e-05** (wall_ms 428; baskın-bileşen ram_gb_sn, zaman-kaynağına-bağlı-her-koşumda-kıpırdar). Bayat-not: belgenin-önceki-sayısı (2.39e-07) silinmiş-orijinal-koşumdan-tekl-snapshot-transkripsiyonuydu ve yeniden-türetilamadı — tek-değer-yazarı-yerine-formül+taze-değer yazıldı.

## Ne-Kanıtlar / Ne-Kanıtlamaz

**Kanıtlar:** (i) göç-hattı üçüncü-şahıs kodunda uçtan-uca çalışır; (ii) sandbox'ın
kısıtları işitilebilir-hata olarak görünür (E-14 ilkesinin motor-tarafı hali); (iii) sonuç
paritesi — zarf-dokunmazlığı bayt düzeyinde.
**Kanıtlayamaz:** pilot. Yabancı-kod-üstünde-göç, yabancı-**kullanıcı**-nın-bizi-seçmesi
değildir; 10-puanlık pilot-eksiği bu belgeyle erimez — erimiş gibi yazılmayacak.
Ayrıca derleme-yeniden-üretimi toolchain-pin'e bağlıdır (AT-032'nin rustc-patch-drift sınıfı
yabancı-kod için-de geçerlidir; bu yüzden PARİTE iddiası bare/envelope stdout arasındadır,
"her-makinede-bayt-bayt-aynı-wasm" değildir).

## Kendin-yap (iki-komut)

```bash
bash scripts/migrate_ext_b3sum.sh          # klon→yama→build→zarf→parite (cargo şart, bağıra-bağıra çıkar)
# ya da sadece doğrula:
sha256sum <(echo -n abc) ; # b3sum("abc") = 6437b3ac38465133ffb63b75273a8db5... (wasm==native teyitli)
```
