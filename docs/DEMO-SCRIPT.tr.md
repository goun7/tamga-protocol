> Çeviri notu: İngilizce-orijinali (docs/DEMO-SCRIPT.md) ile ikizdir; normatif-metin İngilizce'dir — çelişki-olursa ORİJİNAL-BAĞLAYICIDIR.

# 30-Saniyelik Demo — Beklenen Akış

> Betik: `tools/demo.sh` · Kayıt: `asciinema rec -c "bash tools/demo.sh" demo.cast`
> (Kaydedilmiş bir oturum [docs/assets/demo.cast](assets/demo.cast) olarak gelir.)
> Hash'ler/ID'ler her koşuda değişir — aşağıdaki *şekil* değişmeyendir.

## Beklenen akış (2026-09-13'te doğrulandı; 9 adım — köprü artık iki-taraflı)

| Step | What happens | Expected output |
|---|---|---|
| 1 | `keygen` | ajan kimliği basıldı; koşu-tohumu (run-seed) yalnızca kabukta kalır (demonun tek-kullanımlık imza-anahtarı kendi sandbox dizinine yazılır) |
| 2 | `run --input job.json --require-proof` | `run ok: True \| fee: ~1e-4..1e-3` |
| 3 | `export` | `snapshot: ~2.2KB \| plaintext body scan: 0` |
| 4 | başka bir node dizininde `import` | `import ok: True \| agent: <id16>… \| memory nodes: 4 \| resumed session: 1` |
| 5 | `ledger-verify` + `memory --search "node1"` | `ledger-verify ok: True` · `memory recall: born on node1` |
| 6 | `python3 tamga_verify_mini.py <pkg>/ledger.jsonl` | `{"ok": true, ...}` — yalnızca-stdlib, kurulum yok (B2) |
| 7 | `python3 tamga_bundle.py <pkg> -o /tmp/ev` | `/tmp/ev/<pkg>-bundle.json + .md` — karşı-tarafa elden verilir (B4) |
| 8 | `python3 tamga_bootstrap.py project-head <pkg>` | zincir-başı basıldı (D5) → bir batch-yaprağı olarak kodlandı (`TAMGA_PROJECT_HEAD_V1`); bileşim kökü yazdırıldı (AT-022/023) |
| 9 | `python3 tamga_pugio_receiver.py foreign_anchor.jsonl` | sentetik bir dış anchor satırı BİZİM tarafta doğrulanır — `SONUÇ: SAĞLAM` (AT-024, RFC-009'un alıcı yarısı; demonun köprü-hikâyesi iki-taraflı hale gelir) |

## Anlatım çerçevesi (sunum yapıyorsanız)

1. "Ajan doğar ve **girdiye-bağlı iş** yapar — girdinin hash'i makbuza bağlanır."
2. "Makine ölür; ajan **şifreli** bir pakette yolculuk eder — ev sahibi (host) gövdeyi okuyamaz."
3. "Yeni bir ev-sahibinde **kaldığı yerden devam eder** — kimlik ve bellek onunla gelir."
4. "Makbuz-zinciri varış noktasında doğrulanır — 'bu iş yapıldı' iddiası artık denetlenebilir."
5. "Üstelik karşı tarafın bizim kodumuza ihtiyacı bile yok — 200 satırlık bir stdlib betiği ya da tek-komutluk kanıt-demeti."
6. "Adım 8 dışa açılan köprü: `verify-mini`'nin denetlediği aynı zincir-başı,
   **başkasının batch'inin bir yaprağı** oluyor — Starknet-çapalı bir Merkle kökü.
   *Şeklin* bileştiğini kanıtlıyoruz; dış kayıt-defterinin (registry) kendi hakkında
   söyledikleri ise kendi beyanı olarak kalır — yalnızca sunum, asla ödünç-güven. Ve
   oraya giden yoldaki tuzak — baştaki sıfırı düşüren felt-notasyonu — herkes için
   bir FAIL vektörü olarak sabitlendi (yukarı-akış uygunluk PR #2)."
