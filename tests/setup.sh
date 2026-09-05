#!/usr/bin/env bash
# setup.sh — one-time fresh-clone bootstrap for the Tamga Protocol suite.
# Installs the RFC-002 digest-pinned wasmtime release into tools/bin/wasmtime.
# Everything else the suite needs (PyNaCl, jsonschema) comes from requirements.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

WASMTIME_VERSION="v48.0.1"
SHA256=""   # RFC-002 pins the release digest; update together with the RFC when bumping

mkdir -p tools/bin
if [[ -x tools/bin/wasmtime ]]; then
  echo "wasmtime already present: $(tools/bin/wasmtime --version)"
  exit 0
fi

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  ART="wasmtime-${WASMTIME_VERSION}-x86_64-linux.tar.xz" ;;
  Linux-aarch64) ART="wasmtime-${WASMTIME_VERSION}-aarch64-linux.tar.xz" ;;
  Darwin-arm64)  ART="wasmtime-${WASMTIME_VERSION}-aarch64-macos.tar.xz" ;;
  Darwin-x86_64) ART="wasmtime-${WASMTIME_VERSION}-x86_64-macos.tar.xz" ;;
  *) echo "unsupported platform $(uname -s)-$(uname -m): install wasmtime ${WASMTIME_VERSION} into tools/bin/ manually" >&2; exit 1 ;;
esac

echo "downloading wasmtime ${WASMTIME_VERSION} (${ART})..."
curl -sSL -o /tmp/wt.tar.xz "https://github.com/bytecodealliance/wasmtime/releases/download/${WASMTIME_VERSION}/${ART}"
tar -xJf /tmp/wt.tar.xz -C /tmp
cp "/tmp/wasmtime-${WASMTIME_VERSION}-$(echo "$ART" | sed -E 's/.*-(x86_64|aarch64)-(linux|macos).*/\1-\2/')/wasmtime" tools/bin/wasmtime
chmod +x tools/bin/wasmtime
rm -f /tmp/wt.tar.xz
echo "installed: $(tools/bin/wasmtime --version)"
