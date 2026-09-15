#!/usr/bin/env bash
# AT-032 — builder-determinism kontrolü (AynıAraç-dizi-aynı-bayt).
# Sınıf-bildirimi (2026-09-15 soruşturması): templates/agent.wasm 11-Eyl'de bir 1.98-x rustc ile
# derlendi; bugünün toolchain'i code-section'ı +2 bayt farklı üretiyor — kaynak-KAYMASI DEĞİL
# (main.rs aynı), intra-toolchain NON-determinizm DEĞİL (build1==build2 bayt-bayt). Kök: rustc
# patch-sürümü codegen drift'i. Dürüst-sınır: "source→binary byte-identity, builder'ın-PINLENMİŞ-
# toolchain'ine-garelidir; protokol-doğrulaması-buna-bağımlı-DEĞİLDİR (manifest pinned-hash ↔
# shipped-binary öz-tutarlılığı asıl-değişmezdir). Bu-kontrol PINLENMİŞ-araçla çift-derlemenin
# bayt-bayt-aynı-çıktığını-garanti-eder (rust-toolchain.toml ile-birlikte-sınıf).
# cargo yoksa BAĞIRARAK SKIP (c30-deseni): rc=0 + [SKIP] satırı-log'a.
set -u
cd "$(dirname "$0")/.."
D=".evidence/AT-032/$(date +%F)"; mkdir -p "$D"; LOG="$D/at032.log"
if ! command -v cargo >/dev/null; then
  echo "[SKIP] cargo yok — builder-determinism-kontrolü bu-makinede-koşulamaz (sessiz-geçilmez)" | tee "$ROOT/$LOG"
  exit 0
fi
ROOT="$(pwd)"
A="$ROOT/$D/b1.wasm"; B="$ROOT/$D/b2.wasm"
cd tests/agent-src
cargo build --release --target wasm32-wasip2 >/dev/null 2>&1 || { echo "BUILD-Fail" | tee "$ROOT/$LOG"; exit 1; }
cp target/wasm32-wasip2/release/agent.wasm "$A"
touch src/main.rs
cargo build --release --target wasm32-wasip2 >/dev/null 2>&1
cp target/wasm32-wasip2/release/agent.wasm "$B"
if cmp -s "$A" "$B"; then
  echo "PASS: çift-derleme bayt-bayt AYNI (pinlenmiş-toolchain: $(rustc --version | cut -d' ' -f2))" | tee "$ROOT/$LOG"; RC=0
else
  echo "FAIL: aynı-kaynak+aynı-toolchain FARKLI bayt — intra-toolchain non-determinizm!" | tee "$ROOT/$LOG"; RC=1
fi
# sınıf-sınırı-kanıtı: pinned-şablonla-karşılaştırma BİLGİ-satırıdır (fail-yapılmaz; beklenen-drift)
if cmp -s "$A" ../../templates/agent.wasm; then
  echo "INFO: pinli-şablonla-da-bayt-bayt-aynı (toolchain-tam-oturdu)" | tee -a "$ROOT/$LOG"
else
  echo "INFO: pinli-şablonla içerik-farkı VAR = bilinen rustc-patch-drift sınıfı (dokümante; determinizm-ihlali-DEĞİL)" | tee -a "$ROOT/$LOG"
fi
exit $RC
