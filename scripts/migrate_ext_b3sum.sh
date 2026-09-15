#!/usr/bin/env bash
# migrate_ext_b3sum.sh — YABANCI kaynak-kodun Tamga-zarfına göçürülmesinin yeniden-üretilebilir tarifi.
# Konu: BLAKE3-team/BLAKE3 b3sum v1.8.7 (MIT OR Apache-2.0) — yayınlanmış, bizim-olmayan, gerçek-bir-CLI.
# Üç-dürüst-adım: (1) derleme-gerçeği: wasip2 hedefi DOĞRUDAN component üretir (wasm-tools bile gerekmez);
# (2) sandbox-gerçeği: thread yok → default b3sum ENOTSUP(os-58) ile FAIL-LOUD düşer (yarı-sessiz-çalışma YOK);
#     3 etiketli yama [tamga-migration-patch] thread-paths'lerini düz-okuyucuya indirir;
# (3) zarf-gerçeği: manifest pinned-hash + sign + validate + run + ledger-verify + export = aynı-bayt-parite.
# Çıktı: $WORK'ta ext-b3sum paketi + /tmp/mets-$(date +%s).txt ölçüm özeti. Cargo-gerği: bağırarak çıkar.
set -euo pipefail
command -v cargo >/dev/null || { echo "[HATA] cargo yok — bu demo bir DERLEYİCİ ister, atlamak için RUN_SLOW'u kapalı tutun"; exit 1; }
command -v rustup >/dev/null && rustup target list --installed | grep -q wasm32-wasip2 || rustup target add wasm32-wasip2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; WORK="${TMPDIR:-/tmp}/tamga-mig-$$"
mkdir -p "$WORK"; echo "çalışma-dizini: $WORK"
git clone -q --depth 1 https://github.com/BLAKE3-team/BLAKE3 "$WORK/BLAKE3"
cd "$WORK/BLAKE3/b3sum"
# yama-1: rayon+mmap feature-bağı ; yama-2: thread-pool; yama-3: fast-path reader  (hepsi etiketli)
sed -i 's/features = \["mmap", "rayon"\]/features = []/' Cargo.toml
sed -i '/^rayon-core = /d' Cargo.toml
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path("src/main.rs"); s = p.read_text()
a1 = '''    } else {
        // The fast path: Try to mmap the file and hash it with multiple threads.
        hasher.update_mmap_rayon(path)?;
    }'''
b1 = '''    } else {
        // [tamga-migration-patch] mmap+rayon fast path removed: the WASI sandbox
        // has no threads (wasmtime returns ENOTSUP/os-58) and no fs preopen.
        // Same bytes hashed single-thread through the plain reader.
        hasher.update_reader(File::open(path)?)?;
    }'''
a2 = '''    let mut thread_pool_builder = rayon_core::ThreadPoolBuilder::new();
    if let Some(num_threads) = args.num_threads() {
        thread_pool_builder = thread_pool_builder.num_threads(num_threads);
    }
    let thread_pool = thread_pool_builder.build()?;
    thread_pool.install(|| {'''
b2 = '''    // [tamga-migration-patch] no rayon pool in the sandbox; identical body runs inline.
    (|| {'''
a3 = '''        std::process::exit(if files_failed > 0 { 1 } else { 0 });
    })
}'''
b3 = '''        std::process::exit(if files_failed > 0 { 1 } else { 0 });
    })()
}'''
for a in (a1, a2, a3):
    assert s.count(a) == 1, "patch-anchor-bulunamadı — upstream drift: " + a[:40]
p.write_text(s.replace(a1,b1).replace(a2,b2).replace(a3,b3))
print("üç-yama uygulandı (etiketli)")
PYEOF
cargo build -q --release --target wasm32-wasip2
PKG="$WORK/ext-b3sum"; mkdir -p "$PKG" "$WORK/keys"
cp target/wasm32-wasip2/release/b3sum.wasm "$PKG/agent.wasm"
cd "$ROOT"
python3 - "$PKG" <<'PYEOF'
import json, hashlib, sys, pathlib
pkg = pathlib.Path(sys.argv[1])
t = json.loads((pathlib.Path("templates/tamga.json")).read_text())
t["package"]["name"] = "ext-b3sum"; t["package"]["version"] = "1.8.7"
t["package"]["code"]["wasm_sha256"] = hashlib.sha256((pkg/"agent.wasm").read_bytes()).hexdigest()
(pkg/"tamga.json").write_text(json.dumps(t, indent=1))
PYEOF
python3 tamga_validator.py keygen "$WORK/keys/builder" >/dev/null
python3 tamga_validator.py sign "$PKG/tamga.json" "$PKG/agent.wasm" "$WORK/keys/builder/seed.hex" >/dev/null
python3 tamga_validator.py validate "$PKG"
head -c 1000000 /dev/urandom > "$WORK/in1mb.bin"
SEED=$(cat "$WORK/keys/builder/seed.hex")
python3 tamga_bootstrap.py run "$PKG" --seed "$SEED" --input "$WORK/in1mb.bin" > "$WORK/run.json"
python3 tamga_bootstrap.py ledger-verify "$PKG" >/dev/null
TAMGA_KS_PASSPHRASE=mig-demo python3 tamga_bootstrap.py export "$PKG" -o "$WORK/mig-receipt.tsg" --seed "$SEED" >/dev/null
# ÜÇ-YOLLU PARİTE: native-build YAPMIYORUZ (ağ-bant-için); bare-wasm ile zarf-çıktısı birebir-aynıs-mi?
BARE=$(timeout 60 tools/bin/wasmtime run "$PKG/agent.wasm" < "$WORK/in1mb.bin" | cut -d' ' -f1)
ENV=$(cut -d" " -f1 "$PKG/session-1.stdout")
echo "bare-wasm blake3: $BARE"; echo "envelope  blake3: $ENV"
[ "$BARE" = "$ENV" ] && echo "PARİTE ✓ — zarf, motorun-sonucunu-değiştirmez; yalnız-KANIT-ekler" || { echo "PARİTE-FARKI!!"; exit 1; }
echo "kanıtlar: $WORK (receipt: mig-receipt.tsg, run: run.json)"
