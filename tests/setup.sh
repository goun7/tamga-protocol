#!/usr/bin/env bash
# setup.sh — one-time fresh-clone bootstrap for the Tamga Protocol suite.
# Installs the RFC-002 digest-pinned wasmtime release into tools/bin/wasmtime.
# Everything else the suite needs (PyNaCl, jsonschema) comes from requirements.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

WASMTIME_VERSION="v48.0.1"
# sha256 of the release tarball, pinned like the RFC-002 engine digest (E-5);
# update together with the RFC when bumping. Cross-arch digests: add per-ART keys.
declare -A SHA256=(
  ["wasmtime-v48.0.1-x86_64-linux.tar.xz"]="4c2e31b68ad99e0a519f225a261fda099eb15f056d4a24fdb3c2a46517bde1df"
)

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
if [[ -n "${SHA256[$ART]:-}" ]]; then
  echo "${SHA256[$ART]}  /tmp/wt.tar.xz" | sha256sum -c - || { echo "digest mismatch: refusing to install" >&2; exit 1; }
else
  echo "WARNING: no pinned digest for ${ART} on this platform — skipping verification" >&2
fi
tar -xJf /tmp/wt.tar.xz -C /tmp
cp "/tmp/wasmtime-${WASMTIME_VERSION}-$(echo "$ART" | sed -E 's/.*-(x86_64|aarch64)-(linux|macos).*/\1-\2/')/wasmtime" tools/bin/wasmtime
chmod +x tools/bin/wasmtime
rm -f /tmp/wt.tar.xz
echo "installed: $(tools/bin/wasmtime --version)"
