"""tamga_bootstrap.py — PyPI-giriş-noktası + lazy-wasmtime-yükleyici (RFC-002 E-5 disiplini).

Konsol-betiği `tamga` buradan-başlar. runner-mantığı-DOKUNULMAZ (tamga_runner.main);
bootstrap-yalnız-İKİ-iş-yapar:
  1. wasmtime-motoru-yoksa-indirir (İLK-'run'-da; digest-pinned, sessiz-fallback-YOK)
  2. tamga_runner.main'i-same-argv-ile-çağırır

Doğrulama-yolçapı (keygen/ledger-verify/export/import)-wasmtime-İSTEMEZ — saf-stdlib+nacl.
Motor-yolu-sırası: (1) repo-tools/bin (geliştirici-klonu); (2) ~/.cache/tamga/bin (pip-kurulumu);
(3) pinned-release-indirimi (SHA256-kapısı). Her-başarısızlık-açık-hata + elle-kurulum-yolu.
"""
import hashlib
import os
import pathlib
import stat
import sys
import tarfile
import urllib.request
import tempfile

WASMTIME_VERSION = "v48.0.1"
_CACHE_DIR = pathlib.Path.home() / ".cache" / "tamga" / "bin"
# tests/setup.sh ile AYNI çapa (E-5): sürüm-bump'ta-ikisi-BİRLİKTE-güncellenir.
SHA256 = {
    "wasmtime-v48.0.1-x86_64-linux.tar.xz": "4c2e31b68ad99e0a519f225a261fda099eb15f056d4a24fdb3c2a46517bde1df",
    "wasmtime-v48.0.1-aarch64-linux.tar.xz": None,   # gerektiğinde-setup.sh'ten-çapa-kopyalanır
    "wasmtime-v48.0.1-aarch64-macos.tar.xz": None,
    "wasmtime-v48.0.1-x86_64-macos.tar.xz": None,
}


def _artifact_name() -> str:
    s, m = sys.platform, os.uname().machine  # type: ignore[attr-defined]
    if s.startswith("linux") and m == "x86_64":
        return f"wasmtime-{WASMTIME_VERSION}-x86_64-linux.tar.xz"
    if s.startswith("linux") and m == "aarch64":
        return f"wasmtime-{WASMTIME_VERSION}-aarch64-linux.tar.xz"
    if s == "darwin" and m == "arm64":
        return f"wasmtime-{WASMTIME_VERSION}-aarch64-macos.tar.xz"
    if s == "darwin" and m == "x86_64":
        return f"wasmtime-{WASMTIME_VERSION}-x86_64-macos.tar.xz"
    return ""


def _fail(msg_tr: str, msg_en: str) -> "SystemExit":
    print(f"[TAMGA-HATA] {msg_tr}\n[TAMGA-ERROR] {msg_en}", file=sys.stderr)
    return SystemExit(1)


def ensure_wasmtime() -> str:
    """wasmtime-yolunu-döndürür; gerekirse-pinned-indirir. Sessiz-fallback-YOK."""
    # (1) repo-klonu (geliştirici): repo-kökü-tools/bin
    repo_bin = pathlib.Path(__file__).resolve().parent / "tools" / "bin" / "wasmtime"
    if repo_bin.exists():
        return str(repo_bin)
    # (2) pip-kurulumu-cache
    cache_bin = _CACHE_DIR / "wasmtime"
    if cache_bin.exists():
        return str(cache_bin)
    # (3) pinned-indirimi
    art = _artifact_name()
    if not art:
        raise _fail(
            f"bu-platform-desteklenmiyor; wasmtime-{WASMTIME_VERSION}'i-elle-kurun",
            f"unsupported platform; install wasmtime {WASMTIME_VERSION} manually",
        )
    digest = SHA256.get(art)
    if not digest:
        raise _fail(
            f"{art}-için-SHA256-çapası-yok — tests/setup.sh'ten-kopyalayın",
            f"no pinned SHA256 for {art} — copy it from tests/setup.sh",
        )
    url = f"https://github.com/bytecodealliance/wasmtime/releases/download/{WASMTIME_VERSION}/{art}"
    print(f"[TAMGA] wasmtime-{WASMTIME_VERSION} ilk-kullanım-için-indiriliyor… / downloading engine (one-time)…")
    try:
        with tempfile.TemporaryDirectory() as td:
            tgz = pathlib.Path(td) / art
            urllib.request.urlretrieve(url, tgz)  # noqa: S310 — sabit-https-domain
            h = hashlib.sha256(tgz.read_bytes()).hexdigest()
            if h != digest:
                raise _fail(
                    f"indirilen-motor-SHA256-eşleşmedi ({h[:12]}…) — kurulum-DURDURULDU",
                    f"engine sha256 mismatch ({h[:12]}…) — install ABORTED",
                )
            with tarfile.open(tgz) as tf:
                member = next(n for n in tf.getnames() if n.endswith("/wasmtime"))
                tf.extract(member, td)
            _CACHE_DIR.mkdir(parents=True, exist_ok=True)
            src = pathlib.Path(td) / member
            data = src.read_bytes()
            cache_bin.write_bytes(data)
            cache_bin.chmod(cache_bin.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 — ağ/disk-her-ne-olursa-açık-hata
        raise _fail(
            f"wasmtime-indirilemedi ({e.__class__.__name__}: {e}); "
            f"elle-kur: tests/setup.sh-veya-releases-sayfası",
            f"engine download failed ({e.__class__.__name__}: {e}); "
            f"manual path: tests/setup.sh or the releases page",
        )
    return str(cache_bin)


def main(argv=None) -> int:
    """Console-script `tamga` girişi: motoru-gerekirse-çöz, sonra-runner'a-devret."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] in ("-h", "--help", "help"):
        # motor-İSTEMEYEN-komutlar-için-runner.usage-direkt
        import tamga_runner as r
        print(r.USAGE)
        return 0 if argv else 1
    if argv[0] == "run":  # motor-gereken-tek-yolçap
        import tamga_runner as r
        if not pathlib.Path(r.WASMTIME).exists():
            r.WASMTIME = ensure_wasmtime()
    import tamga_runner as r
    if argv[0] == "verify-mini":            # B2: bağımsız-mini-doğrulayıcı (engine-süz)
        import tamga_verify_mini as mv
        return int(mv.main(argv[1:]) or 0)
    cmds = {"keygen": r.cmd_keygen, "run": r.cmd_run, "export": r.cmd_export,
            "import": r.cmd_import, "ledger": r.cmd_ledger, "memory": r.cmd_memory,
            "grant": r.cmd_grant, "ledger-verify": r.cmd_ledger_verify,
            "keygen-node": r.cmd_keygen_node, "migrate-net": r.cmd_migrate_net}
    if argv[0] not in cmds:
        print(f"unknown command: {argv[0]}\n\n{r.USAGE}")
        return 1
    return int(cmds[argv[0]](argv[1:]) or 0)


if __name__ == "__main__":
    sys.exit(main())
