# Kendiniz çoğaltın

Bu depodaki her iddia, çalıştırabileceğiniz bir komutla arkalanır. CI'mıza güvenmek
zorunda değilsiniz — klonlayın, çalıştırın, karşılaştırın.

## 0. Klonlamak yok mu? Wheel'i kurun, aynı kontrolleri koşun

```bash
pip install tamga-protocol        # yayında: pypi.org/project/tamga-protocol
tamga --version && tamga doctor   # motor-gerektirmeyen yolçaplar SAĞLIKLI raporlar
```

Doğrulama-komutları (`ledger-verify`, `verify-mini`, `bundle`, `explain`) 67 MB'lık
motor olmadan çalışır; motor ilk `tamga run`'da bir-kereliğine, SHA256-pinli iner.
Yayınlanan-wheel'den (**0.2.7**, canlı-PyPI) son-doğrulama: **2026-09-15** —
quickstart-U2E + `tamga explain --charge` + wheel-tarafı keccak-KAT + ledger-verify
+ verify-mini + bundle + `epoch-verify --selftest` + canlı epoch-15 iki-bacak doğrulaması
+ tüm-CLI boş-argman matrisi (8-komut: mesaj-RED, traceback-yok, vakum-yeşil-yok);
hepsi canlı-index'ten-sürüm-no-ile-kurulan temiz-venv'de yeşil.
(0.2.4→0.2.5 `epoch-verify`'yi wheel'e koydu; 0.2.5→0.2.6 `explain` kötü-girdiyi mesaj-RED'e
çevirdi; 0.2.6→0.2.7 bu-kuralı TÜM-CLI'a genişletti (E-14, reason_code 19) + CR-v0.1
cross-proof-kontrolünü taşıdı — üçü-de canlı-wheel-kurulup-yabancı-gözüyle-kullanılınca-bulundu.)

## 0b. Aylık-yabancı-ritüeli (2026-09-15+)

`bash tools/fresh_audit.sh` — CANLI PyPI tekerleğini uçucu-venv'e kurar ve yabancı gibi-kullanır
(doctor, boş-argman matrisi, öz-testler, E-15 yanlış-zincir sondası, engine-önbelleği-varsa E2E).
CI her-ayın-20'sinde koşar (kendi-rutubeli, İNDETERMİNE-duyarlı). İlk-geçiş: 0.2.8'de 9/9.

## 1. Tam kabul-süiti (49 kontrol, ~20 sn)

```bash
git clone https://github.com/goun7/tamga-protocol && cd tamga-protocol
bash tests/setup.sh && pip install -r requirements.txt   # bir-kerelik: pinned wasmtime + pynacl
bash tests/run_all.sh
```

Beklenen kuyruk: `RESULT: 49 PASS, 0 FAIL`. Son burada doğrulandı: **2026-09-15** — yayınlanan-tekerlekle, **0.2.8** canlı PyPI'den (yayında-48/48; AT-028 katıldı, 49/49: taze kontroller dahil — AT-029 CR cross-proof baseline'a katıldı; yavaş-tur aynı gün yeniden-pişirildi).
Kanıt günlüğü `.evidence/REGRESYON/<tarih>/run_all-*.log` altına düşer.

Yavaş ek kontroller (çapraz-host c30 + AT-019 wheel + AT-020 self-pilot — CI'da yok):

```bash
RUN_SLOW=1 bash tests/run_all.sh     # → 53 kontrol (bu makinede 53/53)
```

Yavaş-kontrollerin dürüst-önkoşulları (taze-klonda BUG değil — eksik-önkoşul; her biri söyler):
- c30 (31-sn çapraz-host duvar-kontrolü) gitignored yerel simnet-fixtürleri ister
  (`tests/simnet/node-C/` + `seedC.hex`) — yoksa `[SKIP]` basar ve koşum 49/49 okunur.
- AT-019 `dist/` wheel'ini (gitignored) kurar/kullanır — wheel yoksa ve `build` paketi
  importlanabiliyorsa anında üretir; ikisi de yoksa `[SKIP]` basar.
- AT-026 `python3 -m build` ister (`pip install build`); üretimi İZOLE geçici-dizine yapar
  (mevcut `dist/`'i asla silmez).

## 2. Hiçbir şey kurmadan zincir doğrulayın (yalnız-stdlib)

```bash
python3 tamga_verify_mini.py tests/vectors/tc-net-demo/ledger.jsonl
# → {"ok": true, ...}  — wasmtime yok, ağ yok, pynacl gerekmez
```

## 2b. stdlib-saf altküme, PyNaCl kasıtlı-engelli

```bash
python3 tools/verify_lite.py
```

Dört-sağlama-(mini-doğrulayıcı, pairing-hash, explain zincir-dürüstlüğü, nacl-blok-kanıtı) —
`import nacl`-aktif-yasakken-çalışır; karşı-taraf-yolçapı-gerçekten-stdlib-saf ve bu-komut-o-kanıttır.

## 3. Üçüncü-taraf kanıt paketi üretin

```bash
python3 tamga_bundle.py tests/vectors/tc-net-demo -o /tmp/kanit
# → /tmp/kanit/tc-net-demo-bundle.json + .md (kayıtlar bayt-eşit kopyalanır)
```

## 4. Şemayı çapraz-doğrulayın (60/60)

```bash
python3 -m venv .venv-jsonschema && . .venv-jsonschema/bin/activate
pip install jsonschema && bash tests/crossval.sh && deactivate
```

## 5. Kamu pairing-fixtürünü tek komutla doğrulayın

```bash
python3 tools/verify_pairing_bundle.py    # charge-hash yeniden-türetme + zincir-kesit-bilgisi
```

## 6. Düşman-aileleri

| Aile | Komut | Kanıtladığı |
|---|---|---|
| Audit-11 ledger-bomba | `bash tests/audit11_ledger_bomb.sh` | 50 MB-satır + grant-tavan RED, sınırlı RSS |
| Audit-15 state-sertleştirme | `bash tests/audit15_state_hardening.sh` | bozuk-state → fail-closed, state-kurcalamaya-kapalı-zincir |
| Audit-16 node-iptali | `bash tests/audit16_revocation_gap.sh` | iptalli-node import RED (key-theft kapanışı) |
| DX402 eşleştirme | `bash tests/at012_dx402_pairing.sh` | canlı vektör: paymentId/EIP-712/CID gidiş-dönüş |

Her betik başarida 0 çıkar ve `RESULT: N PASS, 0 FAIL` basar.

## 7. Elimizde olmayan (dürüst sınırlar)

- **Pilot kanıtı özeldir**: #3379 rızalı-teslimat artefaktları karşı-tarafın verisini içerir;
  *yöntem* kamudur, yük değildir.
- **CI bizim makinemizi kanıtlar**: asıl test sizin makineniz. Yukarıdaki komutlardan biri
  temiz klonlarda başarısız olursa bu bir hatadır — günlük kuyruğuyla issue açın.
