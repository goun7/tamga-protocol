# Hizmet-Paketi Şablonu — Tamga Göç-Paketi (design-partner teklif-iskeleti)

> Tur-4 telafi-5 (madde-1): hizmet-geliri merdiveninin ilk basamağı. Bu şablon bir
> SÖZLEŞME değil; pazarlık-açılan teklif-iskeletidir. Fiyatlar banttır — müşteri
> kapsamına göre netleşir. Hukuki metin imza-öncesi müşteri-taraflı revizyona açıktır.

## 1. Paket-özet (teklif-sayfasına giren kısım)

**Tamga Göç-Paketi — "Ajan hafızası vendor-kilidinden çıkarsın"**

- **Kapsam:** mevcut ajan-hafızası kaynağınızı (PostgreSQL/SQLite dump, Mem0/ Letta/
  Zep export-JSON'u veya düz JSON-lines) Tarayıcı-sınıfı bir gün içinde analiz eder,
  şema-eşlemesini kurar, **şifreli Tamga snapshot'ına** taşır; bir "boş-node restore"
  doğrulamasıyla teslim eder.
- **Teslimatlar:**
  1. Şema-eşleme haritası (kaynak-alan → Tamga-düğüm; eklenen/bırakılan alan gerekçeleri)
  2. `tools/mergen_batch.py` sınıfı tek-komut göç betiği (sizin kaynağınıza özgü)
  3. Şifreli snapshot + restore-doğrulama raporu (node/edge sayıları, hash uyumu)
  4. "Nasıl kullanılır" 1-sayfa: export / import / ledger-verify komut seti
- **Süre:** ilk görüşmeden **10 iş-günü** içinde teslim (veri ≤ 1M kayıt bandı)
- **Sınırlar (dürüst):** hafıza-formatı-dışı iş-mantığı-göçü kapsam-dışı; gerçek-ödeme
  entegrasyonu kapsam-dışı (Faz 3); şifreleme parolası müşteri elinde kalır — biz
  saklamayız, KAYBEDERSEK RESTORE YAPILAMAZ (beyanla onaylanır).
- **Fiyat-bantı:** $2.000–5.000 + gerektiğinde yol-gideri; kayıt sayısı ve kaynak-format
  sayısına göre netleşir.
- **Kabul-kriteri:** restore-doğrulama raporunda (a) node/edge sayıları kaynak-sayımıyla
  ±0, (b) ledger-verify ok:true, (c) snapshot gövdesinde düz-metin taraması 0 sızıntı.

## 2. Design-partner karşılığı (ücretsiz-göç bandı)

İlk 3 partner için göç-paketi **ücretsiz**; karşılığında:
- 4 hafta boyunca haftalık 30 dk geri-bildirim görüşmesi (RFC dondurma sürecini besler;
  bkz. KURUCU-KARARLARI geri-bildirim planı)
- Çıktılarımızı vaka-çalışması olarak anma izni (müşteri-materyali gizli kalır —
  yalnız işlem-oranları ve mimari anlatılır)
- Bahis: "ilk üretim-kullanıcısı" statüsü + ömür-boyu %20 destek-indirimi

## 3. Sözleşme-iskeleti (imza-öncesi müşteri-revizyonuna açık)

1. **Taraflar:** sağlayıcı [X]; müşteri [Y].
2. **Konu:** Ek-A'daki kapsam; kapsam-dışı işler ayrıca fiyatlanır (saat-bazı $90-140/saat bandı).
3. **Veri-gizliliği:** müşteri-verisi yalnız müşteri-taraflı ortamda işlenir; ara-dosyalar
   RAM-diskte tutulur, teslim-sonrası yok edilir; raporlarda yalnız sayı+hash bulunur.
4. **Parola-egemenliği:** şifreleme parolası müşteriye aittir; sağlayıcı saklamaz;
   kayıp-parola kurtarma hizmeti TEKNİK OLARAK MÜMKÜN DEĞİLDİR (önceden beyan).
5. **Kabul:** Ek-A kabul-kriterleri; 10 iş-günü içinde onarım turu dahil.
6. **Gizlilik:** karşılıklı NDA; vaka-çalışması izni yalnız madde-2 sınırlarıyla.
7. **Sorumluluk-sınırı:** ücret-tavanıyla sınırlı; dolandırıcılık/kaba-kusur hariç.
8. **Uygulanacak hukuk:** [müşteriyle netleşecek — Türk hukuku öntasarım].

## 4. Operasyon-notu (bize)

- Göç-betiği `tools/mergen_batch.py` genellemesidir: `--source-format {mergen,pg_dump,
  mem0_export,letta_export,zep_export,jsonl}` — her partner ek bir format-çekirdeği
  demektir; eklenen her format sonraki partnerin maliyetini düşürür (öğrenme-eğrisi
  kasıtlı tasarım).
- Her partner teslimi kanit/GOC/ altına sayı+hash-log bırakır (gizlilik-genişletmesi:
  müşteri-adı YOK).
