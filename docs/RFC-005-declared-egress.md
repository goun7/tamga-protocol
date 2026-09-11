# RFC-005 — Declared Egress (vekil-proxy modeli: beyanlı-ağ-çıkışı)

> **Durum: IMPLEMENTED (Dilim-1/2, 2026-09-06; AT-006 20-kontrol, kontrol-19; M6-göçü
> RFC-007-R1'de-tamamlandı).** Tasarım-kaynağı: K15-kurucu-kararı-(2026-09-05)+
> private/RFC-005-yetenek-modeli-TASLAK.md + RFC-005A-uygulama-şeması. Bu-doküman
> kamu-kaydıdır: NE-yapıldı, NEDEN-böyle, HANGİ-KANITLA — dürüst-bulgular-dahil.
> Kapılı-kalanlar-açıkça-etiketli-(§6).

## 0. Çözülen-çelişki (özet)

v0-koşum-kutusu **ağ-yok**tur-(D4: fs-preopen-yok, ağ-yok, env-sıfır) — koruma-isteyen
işler-için-doğru; ama gerçek-ajanların-işi-büyük-oranda-LLM-çağrısıdır-ve-LLM-ağ-ister.
İki-kötü-çözüm-REDDEDİLDİ: "ağ-olsun-güvenelim"-(default-deny-değişmezi-kırılır;
satılamaz) ve "LLM-işleri-kutu-dışı-koşsun"-(kanıt-zinciri-asıl-işin-dışına-düşer).
Çözüm: **ağ-bir-varsayılan-değil-YETENEKTİR** — manifest'te/beyanda-ilan-edilir,
koşucu-kısıt-olarak-uygular; kutu-içi-soket-ASLA-açılmaz.

## 1. Mimari (M1-M6; hepsi-uygulandı)

```
kutu-içi-ajan → [tek-kenar: stdin/stdout] → runner → 127.0.0.1-vekil (ephemeral)
                                          vekil: beyan-listesiyle-eşleşme
   ├─ uç-listede → CONNECT-tüneli; bayt-sayacı-RW-akar; timeout-başlar
   ├─ uç-LİSTEDE-DEĞİL → kutuya-AIYA; koşum-log'a net_denied (koşum-sürer — op-bazlı)
   ├─ DNS-cevabı-liste-dışı-IP'ye-pinhole → red + net_denied (SSRF-panzehiri)
   ├─ byte-tavanı-aşımı → aktif-bağlantı-kesilir + koşum-RED 11 (session-capped, charge-YOK)
   └─ timeout-aşımı → bağlantı-kesilir + net_denied (koşum-RED-değil — tek-uç-ölür)
```

- **M1** net.json-okuyucu-(katı: format/egress-≤8/timeout-1-120s/bayt-tavan-1KiB-8MiB/
  bilinmeyen-anahtar-RED) → **M2** loopback-HTTP-CONNECT-vekili-(her-koşumda-yeniden-port)
  → **M3** politika-motoru-(net_denied: not_listed|dns_fail|upstream_fail|bad_request|
  byte_cap) → **M4** RW-bayt-sayacı-(net_mb-özet) → **M5** events-log-0600+-hash'li →
  **M6** manifest-göçü-(RFC-007-R1: `runtime.net`; migrate-net-tek-yön).

## 2. wasmtime-outbound-socket — DÜRÜST-BULGU (Dilim-2)

`/tmp/netprobe`-(Rust,-wasm32-wasip2)-ile-bayrak-matrisi-koşuldu:
- `-S tcp` DAHİL tüm-ilkeli-bayraklarda-outbound-connect → `Permission denied (os error 2)`
- `-S inherit-network` tekeli-sistem-çağrısını-açıyor-AMA-konuk-sürece-TÜM-ana-makine-
  ağını-verir → allow-list'i-tamamen-atlar → **reddedildi**-(tek-kenar-kuralı-bozulur)
- **Sonuç:** wasmtime-v48.0.1-CLI'da-ilkeli-outbound-YOK; Box-soketsiz-kalır-(D4-korunur).
  Ajan-tarafı-çıkış-D13-şimiyle-(RFC-006)-çözüldü; koşum-düzeyi-dayatma + makbuz-bağlama
  gerçek-koşumla-kanıtlı.

## 3. D12 — beyan-bağlama (üç-alan, koşullu-birlik)

Charge-kaydına-(net-beyanlı-paketlerde): `net_decl_sha256`-(beyan-hash'i:-net.json-dosya-
baytları / runtime.net-jcs-alt-ağacı — RFC-007-R3-formalizasyonu) + `net_events_sha256`
(events-log-0600-hash'i) + `net_mb`-(MiB-6-hane). **Üçlü-BİRLİKTE**-(AT-011:
`net_trio_incomplete`-RED); beyansız-paketlerde-üçü-de-YASAK-(D4-sessizlik-"harcadı"-
gösteremez). Post-run-beyan-değişimi → `net_binding_mismatch`; silme → `net_binding_missing`.

## 4. Güvenlik-önlemleri (hepsi-kanıtlı)

1. Beyan-imza-içinde-(v0.2: manifest-imzası; v0.1-köprüsü: koşum-öncesi-hash-makbuza)
2. **DNS-rebinding-panzehiri:** her-FQDN-yükleme-anında-çözülüp-IP-pinlenir-(CONNECT-anında
   DNS-yolu-yok); çözülemez-uç → yüklemede-RED-(fail-closed); SNI/Host-korunur — istemci
   konuştuğu-isimle-konuşmaya-devam-eder
3. Yanıt-boyutu + süre-tavanları-RLIMIT-ailesine-(F15-disiplini); byte-cap-aşımı = koşum-
   RED-11 + capped-işareti-(kısmi-log-0600-hash'li-kalır)
4. TLS-inspeksiyonu-YOK-(vekil-blind-tünel: uç+bayt-görür-içerik-görmez) — içerik-düzeyi-
   politika-Faz-3'te-TEE-ile-(bilinçli-erteleme,-§6)
5. net.json'suz-paketler: bayt-bayt-eski-yol-(D4-hermeneutik-değişmez,-AT-006a)

## 5. Kabul-kanıtları

AT-006-(kontrol-19;-20-koşum): 8-uç-aşımı-RED; liste-dışı-uç-soft-denial; byte-tavanı-
GERÇEK-koşumda-(tc-net-slow-3s-uyur,-8KiB-akış-kesilir,-charge-yok); sahte-DNS'ten-listeli-
uç-gerçek-sunucuya-ulaşır-(rebinding-modeli:-yalnız-isim-aramaları-zehirli); post-run-
tamper-doğrulama-RED; D12-alanları-charge'ta. TDD-dersleri-açık-ayrı-tutuldu-(test-client
çıplak-port-CONNECT'i-net_mb-yuvarlama-kabulü-eksik-fixture — hepsi-gerçek-bulgu).
AT-009-(migrate-net)/AT-011-(üçlü-birlik)-RFC-007-kayıdında.

## 6. Kapılı-kalanlar (bilinçli; kapı-etiketiyle)

- **TLS-içerik-politikası** → Faz-3-TEE-(OQ-4)
- **Çok-protokol-beyanı**-(bazı-uçlar-HTTP/bazıları-gRPC) → v0.2+'ya-ertelendi-(tek-liste
  FQDN:port-yeterli)
- **R4-imzalı-DENY-artifact'ı** → pilot-kapılı-aday-not-(RFC-007-§5b)
