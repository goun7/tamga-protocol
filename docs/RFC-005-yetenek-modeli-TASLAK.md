# RFC-005 (TASLAK) — Yetenek-Modeli v1: Beyanlı-Ağ Egress ve Gerçek-Ajan Uydurmazlığı

> Durum: TASLAK — uygulanmadan önce kurucu onayı + RFC-001 şema-değişikliği gerekir.
> Tetik: Tur-4 dış-gerçeklik eleştirisi (telafi-4): "default-deny vs gerçek-ajan çelişkisi —
> ürün-uydurmazlığı yazılı ve çözülmemiş". Bu belge çelişkiyi tasarım-düzeyinde açar; kod yok.

## 1. Problem — çelişkinin dürüst beyanı

v0 koşum-kutusu **ağ-yok**tur (D4: fs-preopen yok, ağ yok, env sıfır). Bu, koruma
isteyen işler için doğru; ama gerçek ajanların işi büyük oranda **LLM-çağrısı**dır ve
LLM-çağrısı ağ ister. Yani bugünkü kutuya gerçek-ajan işi koyarsak ajan açlıktan ölür.
İki kötü çözümü baştan reddediyoruz:

- "Ağ olsun, güvenelim" — default-deny değişmezi kırılır (satılamaz).
- "LLM-işleri kutu-dışı koşsun" — kanıt/makbuz zinciri asıl-işin dışına düşer; tez boşa döner.

## 2. Tasarım — beyanlı-egress (capability = beyan, kısıt = koşucu)

**Prensip:** ağ bir *varsayılan* değil, bir *yetenektir* — tıpkı bugünkü `clock`/`random`
gibi manifest'te beyan edilir; koşucu beyanı kısıt olarak uygular.

```
tamga.json (v0.2-öneri):
"runtime": {
  "limits":   { ... mevcut, donmuş ... },
  "net": {                                  // YENİ — yalnız beyan edilmişse ağ şansı var
    "egress": [ "api.openai.com:443", "api.anthropic.com:443" ],   // beyanlı uçlar
    "max_bytes_per_run": 8388608,           // ağ-IO tavanı (koşum-faturasına girer)
    "timeout_s": 30
  }
}
```

**Uygulama (koşucu-yana, şema-donukluğunu kırmadan):** kutu içinden doğrudan soket
açılmaz (component-model'de de izin yok). Ajan `wasi:http` istemini kutu-içi yerel-
vekil'e (127.0.0.1) yollar; runner vekili **beyanlı-egress listesiyle** karşılaştırır:
uyan uç → proxy-ler; uymayan → kutuya AIYA döner (kayıt: `net_denied`). Böylece:

- default-deny *içinde* kalır: ajanın soket-gücü yoktur, yalnız beyanlı-vekil kapısı vardır;
- her ağ-eylemi koşum-log'una düşer → **ağ-IO faturalanabilir** (charge'a `net_mb` alanı
  adayı — TOKENOMICS ile hizalı);
- kurumsal anlatıya uyum: "ajan hangi uçlara gidebilir" sorusu manifest'te okunur —
  satın-alan firma için denetlenebilir beyan.

## 3. Determinizm-etkisi (RFC-003 §9 sınıf-tanımlı kontratla hizalı)

`net` beyanlı işler **Sınıf-B'dir**: replay vaadi YOK; kanıt = girdi-bağlama (input_sha256)
+ koşum-log + node-cosign mührü. Sınıf-A işler net-beyansız kalır — tablo bozulmaz.

## 4. Güvenlik-önlemleri (tasarım-şartları; uygulanmadan Audit'e girmez)

1. Egress-beyanı manifest imzası İÇİNDEDİR → koşum-sonrası değiştirilemez.
2. Proxy, host-header/DNS-pinning ile beyan-dışı yönlendirmeyi reddeder (SSRF panzehiri).
3. Yanıt-boyutu + süre tavanları RLIMIT ailesine eklenir (F15 disiplini).
4. LLM-işleri için prompt-gizliliği: vekil kutu-içi olduğundan gizli-anahtar ajanın
   keystore'unda kalabilir (host'a sızmaz) — bu, "host'a güvenme" tezini ağ-işlerine
   taşır; TEE-eşleştirmesi (RFC-004 attestation) ile Faz-3'te mühürlenir.

## 5. Açık-kararlar (kurucuya)

1. Beyan-kişiliği: alan-adı-sayısı sınırsız mı, yoksa bantlı mı (ör. ≤8 uç)?
2. net-IO faturalaması: cpu/ram/io satırlarına ek `net_mb` — TOKENOMICS'e işlenir mi?
3. Zamanlama: bu tasarım Faz-2 dilimi mi (pilot öncesi), Faz-3'e mi kalır?
   Öneri: **Faz-2 ortası** — design-partner'a "gerçek-LLM ajanı kutuda" demosu gerekecek.
