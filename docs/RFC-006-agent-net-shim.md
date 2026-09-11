# RFC-006 — Agent-Side Network Request Shim (D13: stdin/stdout tek-kenar)

> **Durum: IMPLEMENTED (2026-09-06, d59c1b4; AT-008 6/6, kontrol-21; suite-21/21;
> CI-yeşil).** Kurucu-onayı: 2026-09-06-(şim-dilimi-şimdi; demo-hedefi-mock-HTTPS).
> Öncül: RFC-005-§2-dürüst-bulgu-(wasmtime-v48-CLI'da-ilkeli-outbound-YOK). Bu-doküman
> kamu-kayıdıdır; test-tarafı-kusur-dersleri-dahil-dürüst-notlarla.

## 1. Tez

Ajan-soket-AÇMAZ-(D4-kalıcı). Ajan-stdout'una-bir-**istek-satırı**-yazar; koşumcu-istek'i
**TamgaProxy-CONNECT-tünelinden**-geçirir-ve-yanıtı-ajanın-stdin'ine-**yanıt-satırı**
olarak-yazar. Ağ-çıkışının-TEK-yolu-vekil-kalır; politika-kaynağı-(net.json+proxy)
hiç-değişmez; koşucu-kendisi-asla-doğrudan-host'a-bağlanmaz.

## 2. Protokol (TAMGA-NET-1 / TAMGA-NET-RESP-1)

**İstek-(ajan→stdout,-tek-satır,-≤64-KiB):**
`TAMGA-NET-1 {"id":1,"method":"GET","url":"https://host:443/path","headers":{...},"body_b64":null}`
method-∈-{GET,POST,PUT,DELETE,HEAD,PATCH}; url-http/https-yalnız; body_b64-opsiyonel.

**Yanıt-(koşumcu→ajan-stdin,-tek-satır):**
`TAMGA-NET-RESP-1 {"id":1,"ok":true,"status":200,"headers_b64":"...","body_b64":"..."}`
hata: `{"id":1,"ok":false,"error":"net_denied:not_listed"}`-(red-nedenleri-proxy-ile-aynı-aile).

**stdin-disiplin-(yetenek-sınaması;-iki-mod):** koşumcu-ajan-wasm'ını-`TAMGA-NET-1 `-bayt-
dizisi-için-tarar:
- **net-bilinçli-ajan**-(işaret-var): stdin-=-`TAMGA-STDIN-1 <len>\n`+girdi-baytları;
  stdin-**açık-tutulur**-(yanıt-kanalı); ajan-stdout'a-yazınca-`flush`-ZORUNLU.
- **eski-ajan**-(işaret-yok): stdin-=-girdi-baytları-+**derhal-EOF**-(D4-ile-bayt-özdeş;
  `read_to_end`-ajanlar-bloklamaz). Eski-ajan-istek-satırı-basarsa-sessiz-ret
  (`net_shim_ignored`).
- Dürüst-sınır-notu: yanıt-kanalı-stdin'i-açık-tuttuğu-için-eski-semantik+yanıt-tek-stdin'de
  birleştirilemez; yetenek-sınaması-bu-ikiliğin-mekanik-sınırıdır.

**Kilit-adım:** tek-uçuşta-tek-istek; yanıt-yazılmadan-yeni-istek-işlenmez.

## 3. Güvenlik-modeli (değişmeyenler)

- **Politika:** allow-list-dışı-uç → vekil-403 → ajan'a-hata-yanıtı-(soft-path;-koşum-sürer)
- **Kanıt-bütünlüğü:** stdout-kanıt-dosyası-bayt-bayt-çocuk-çıktısıdır — **istek-satırları
  DAHİL**-yazılır-(çıkarım/düzenleme-=-kurcalama,-YASAK). Ağ-kanıtı-=-events-log-(0600)+
  D12-alanları; iki-kanıt-ayrı-bacak.
- **TLS:** CONNECT-üstüne-`wrap_socket(server_hostname=<beyan-host>)`-TCP-hedefi-pinli-IP;
  sertifika-doğrulaması-beyan-adıyla; test-CA-yalnız-`TAMGA_NET_CA_BUNDLE`-env'iyle
  (prod: unset; dokümante).
- **Şim-hatası-koşumu-düşürmez**-(soft); YALNIZ-byte-cap-orta-akım-kesme-sert-yolu-tetikler
  (RED-11,-charge-yok).

## 4. Kabul-kanıtları (AT-008; kontrol-21)

| | senaryo | kanıt |
|---|---|---|
| a | net.json'lu-paket+net-demo-ajan→mock-echo | koşum-OK; stdout'ta-istek-satırı+status; charge-net_mb>0; events'te-net_connect |
| b | egress-dışı-host'a-istek | hata-yanıtı-not_listed; koşum-sürer; events'te-net_denied |
| c | mock-HTTPS-(yerel-CA) | 200+gövde-echo; sertifika-beyan-adıyla-doğrulanır |
| d | net.json'suz-pakette-istek | sessiz-ret; `net_shim_ignored:1`; makbuzda-net-yok-(D4) |
| e | cap-1KiB+8KiB-yanıt | orta-akım-capped → RED-11,-charge-yok |
| f | kanıt-bütünlüğü | stdout-dosyasında-istek-satırı-bayt-bayt; stdout_sha256-eş |

Gerçekleşme-dersleri-(dürüst): AT-008c-IP-SAN-sertifikası-ister-(D12-dns-fail-closed-
çözülemez-adı-RED'lediği-için-test-127.0.0.1+IP:127.0.0.1-SAN-kullanır); mock-sunucu
Content-Length'ı-okumadan-kapanırsa-RST-yalar-(mock'larda-gövde-dreni-zorunlu);
net_mb-kesinliği-round(bytes/2^20,-6-hane)-(D12c). Kanıt: `.evidence/AT-008/2026-09-06/`.

## 5. Bilinçli-olmayanlar (dürüst; v1-sınırları)

- Akış/WebSocket/çoklu-eşzamanlı-istek: YOK-(kilit-adım-yeter)
- HTTP-ayrıştırıcı-minimal-(Content-Length+chunked) — genel-amaçlı-istemci-DEĞİL;
  zengin-istemci-ajan-kontratı-ileride-ayrı-RFC
- **auth-başlık-gizliliği:** istek-satırı-stdout-kanıtına-YAZILIR — gizli-anahtar-içeren
  başlıklar-kanıta-bulaşır; gizli-taşıma-ajanın-KENDİ-sorumluluğu-(header-karartma
  v0.2-adayı-D14 — taslak-YOK)
