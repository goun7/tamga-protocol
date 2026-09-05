# Tamga Protocol

**Kendi kendine sahip ajanlar için taşınabilir kimlik + hafıza + muhasebe protokolü.**

Bir ajanın kimliği (ed25519), hafızası (şifreli snapshot) ve muhasebesi (hash-zincirli ledger)
host'tan bağımsız taşınır: ajan bir makineden diğerine göç eder, kimliği ve geçmişi onunla gelir.

> Durum: **Faz 1 — simnet (tek makine simülasyon ağı), kanıt-kültürlü geliştirme.**
> Bu depo üretim ağı değildir; token/coin değildir; tüm tutarlar `*_sim`.

## Hızlı Başlangıç

```bash
python3 tamga_validator.py keygen tests/keys/alici          # anahtar çifti (0600)
python3 tamga_validator.py sign  <pkg>/tamga.json <pkg>/agent.wasm tests/keys/alici/seed.hex
python3 tamga_validator.py validate <pkg>                   # ACCEPT / RED + neden

python3 tamga_runner.py keygen                              # ajan kimliği (yalnız stdout)
export TAMGA_KS_PASSPHRASE="..."
python3 tamga_runner.py run    <pkg> --seed <hex> --note "not"
python3 tamga_runner.py export <pkg> -o snapshot.tsg --seed <hex>
python3 tamga_runner.py import snapshot.tsg <yeni-pkg>      # kimlik + hafıza + ledger göçü
python3 tamga_runner.py ledger <pkg>                        # bakiye özeti
python3 tamga_runner.py ledger-verify <pkg>                 # hash-zinciri doğrulaması
python3 tamga_runner.py grant  <pkg> 0.01 "hibe"            # simnet hibe kaydı
python3 tamga_runner.py memory <pkg> --search <q>           # hafıza arama
python3 tamga_runner.py memory <pkg> --import-json d.json   # MERGEN → Tamga ders köprüsü
```

## Belgeler

| Belge | İçerik | Durum |
|---|---|---|
| [RFC-001](specs/RFC-001-paket-bicimi.md) | Paket biçimi (`tamga.json`, manifest şeması) | v0.1-FINAL (donmuş) |
| [RFC-002](RFC-002-runner.md) | Runner sözleşmesi (koşum, ölçüm, snapshot) | v0.1-FINAL (donmuş, erratalı) |
| [RFC-003](RFC-003-ledger.md) | Ledger kaydı ve ölçüm sözleşmesi (`tamga-sim/1`) | TASLAK — kurucu onayı bekliyor |
| [RFC-004](RFC-004-context-graph.md) | Bağlam grafiği ve snapshot sözleşmesi | TASLAK — kurucu onayı bekliyor |
| [SECURITY-AUDIT.md](SECURITY-AUDIT.md) | Audit-1…6 — 24 bulgu, kapanış kanıtlarıyla | Yaşayan belge |
| [ROADMAP.md](ROADMAP.md) | Dikey dilim planı + çıkış ölçütleri | Yaşayan belge |
| [TOKENOMICS.md](TOKENOMICS.md) | Birim ekonomi (yalnız sim) | Faz 4 kapısı kilitli |
| [kanit/](kanit/) | Tüm koşu kanıtları (log'lar) | Eklenir, silinmez |

## Güvenlik Duruşu (dürüst çerçeve)

- **Bekleyen (at-rest) gizlilik kanıtlı:** seed asla diskte düz metin değil (XChaCha20-Poly1305,
  scrypt KDF); hafıza gövdesi şifreli; disk taraması 0 düz-metin sızıntı (kanıt: AT-001d).
- **Kullanım-anı (in-use) gizlilik KANITLANMAMIŞTIR:** koşum sırasında seed host belleğinde yaşar.
  TEE/niyet-kanatı (RFC-004 attestation) v1 planıdır — v0 bunu iddia etmez.
- **Bütünlük:** ledger hash-zinciri (kurcalama → `broken_at` RED), hafıza `graph_merkle`,
  snapshot ↔ ledger bağlaması (`ledger_tip` — truncate saldırısı RED).
- **Bağlantısız çalışma:** motor (wasmtime v48.0.1, digest-pinli — **ratifiye WASI 0.3.0 üstünde**,
  Wasmtime 46+ default) default-deny: dosya yok, ağ yok, host env sıfır. Yetenekler
  manifest'te beyan edilir (şu an: clock, random).
- Açık bulgular her zaman [SECURITY-AUDIT.md](SECURITY-AUDIT.md)'de yaşar; kapatma kanıtsız yapılmaz.

## Tek-Komut Regresyon

```bash
bash tests/run_all.sh              # hızlı takım (~sn)
RUN_SLOW=1 bash tests/run_all.sh   # + 31s wall-ölçüm kanıtı (AT-001c özü)
```

## Tasarım İlkeleri

1. **Kanıt kültürü:** hiçbir "çalışıyor" iddiası log'suz kabul edilmez (kanit/).
2. **Taşınabilirlik değişmezi:** kimlik + hafıza + muhasebe snapshot'la birlikte göç eder.
3. **ADD-only hafıza:** düğüm silinmez; düzeltme `supersedes` ile yeni düğüm ekler.
4. **Sıfır-bağımlılık çekirdek:** Python stdlib + PyNaCl. Ek bağımlılık = RFC + gerekçe.
5. **Kurucu kapıları:** RFC donması, lisans, gerçek-değer taşıma, genel repo — insan kararı.

## Lisans

Kurucu kararı bekliyor (bkz. ROADMAP Dilim-5: katılım yüzeyi).
