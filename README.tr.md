<div align="center">

<img src="docs/assets/banner.svg" width="660" alt="Tamga Protocol — taşınabilir kimlik, şifreli hafıza, doğrulanabilir iş-makbuzu"/>

[![CI](https://github.com/goun7/tamga-protocol/actions/workflows/ci.yml/badge.svg)](https://github.com/goun7/tamga-protocol/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/tests-17%2F17%20PASS-brightgreen)](README.md#one-command-regression)

</div>

---

# Tamga Protocol — Türkçe (yerelleştirilmiş README)

> Bu dosya, İngilizce [README.md](README.md)'nin Türkçe özetidir. Ayrıntılı teknik
> dokümanlar `docs/` altında İngilizce'dir; derin tasarım-belgeleri (RFC'ler, denetim
> raporu) Türkçe özgünlerinden çevrilmektedir.

## Neden var?

Ajan-ekosisteminin üç katmanı var ve hiçbiri aradaki boşluğu doldurmuyor:
**Hafıza** (Mem0/Letta/Zep — taşınabilirlik yok) · **Güven** (ERC-8004 — durum yok)
· **Ödeme** (x402 — kanıt yok). Tamga bu boşluktadır: **şifreli, taşınabilir,
kurcalamaya-dirençli ajan-durumu.** Rakip değil, tamamlayıcı.

## 30 saniyelik özet

```bash
python3 tamga_runner.py run pkg/ --seed $SEED --input job.json --require-proof  # girdili iş
python3 tamga_runner.py export pkg/ -o snapshot.tsg --seed $SEED                # makine öldü
python3 tamga_runner.py import snapshot.tsg new-pkg/                            # yeni host'ta dirildi
python3 tamga_runner.py ledger-verify new-pkg/                                  # ok: true
```

## Temel güvenceler

- 🔐 Diskte-düz-metin yok (XChaCha20-Poly1305 + scrypt; tarama 0 sızıntı)
- ⛓️ Hash-zincirli defter; truncate/splice sahteciliği → RED
- 🪪 node-cosign: node sertifikasıyla mühürlü iş-makbuzu + iptal-listesi
- ⌨️ `input_sha256` makbuza bağlı; `--require-proof` çıktı-kanıt-satırı koşucu-taraflı doğrulanır
- 🔁 Aynı wasm+girdi → aynı çıktı-parmakizi (stake'li yeniden-koşum ön-koşulu)
- 🚫 Ağ-yok, fs-yok, env-yok — default-deny; wasmtime v48 + WASI 0.3 component

Ayrıntı: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · Rehber: [docs/AGENT-GUIDE.md](docs/AGENT-GUIDE.md)

## Dürüst sınırlar (v0 iddia ETMEZ)

- Koşum-anı gizlilik kanıtsız (seed RAM'de) — TEE Faz 3
- Simnet — gerçek-değer yok; bu bir token/coin DEĞİLDİR
- Snapshot ≤ 64 MiB; çok-node defter-birleşmesi açık soru
- Determinizm sınıf-tanımlı: deterministik wasm işleri replay-kanıtlı; LLM-sınıfı işlerde
  farklı kanıt-kontratı

## Hızlı başlangıç

```bash
git clone https://github.com/goun7/tamga-protocol && cd tamga-protocol
pip install -r requirements.txt
bash tests/run_all.sh    # 17/17 kontrol — ~6 sn
```
Komut-seti ve ilk-ajan akışı: [README.md#quick-start](README.md#quick-start) ve
[docs/AGENT-GUIDE.md](docs/AGENT-GUIDE.md).

## Yol haritası

✅ Faz 1 simnet-jenerasyonu · 🔄 Faz 2 sertleştirme (adaptörler, tasarım-partner pilotu)
· 🔒 Faz 3 ağ (ERC-8004, gerçek mikro-ödeme, TEE) · 🔒 Faz 4 protokol v2 (zkVM) — kapılı.

## Lisans

[Apache-2.0](LICENSE)
