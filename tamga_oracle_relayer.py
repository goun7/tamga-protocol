#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tamga_oracle_relayer.py — Tamga Protocol on-chain oracle relayer.

Mimari (3 katman; bu dosya KATMAN-0 + KATMAN-1 + KATMAN-2'yi barındırır,
ancak geliştirme adım-adımı yapılır — Orkestratör kararı 2026-09-24):

    KATMAN-0 — kanıt-üretim çekirdeği (saf Python, sıfır yeni PyPI bağımlılığı)
        • fnv1a64 stamp doğrulaması (tamga_runner.py:30 ile BYTE-IDENTICAL kopya;
          agent stdout'unun son satırı "TAMGA:<fnv1a64-hex16>" damgasını taşır)
        • tamga-snapshot/1 parse → şifreli gövde (ct) ayıkla
          → encryptedSnapshotDigest = SHA-256(ct)
          (mühür-1 standardı: şifreli GÖVDE'nin digest'i — tüm blob'un DEĞİL)
        • fulfill payload inşası (JCS canonical — RFC 8785; tamga_canon)
    KATMAN-1 — üretim-yolu sürücüsü (subprocess → tamga_runner.py; gerçek wasmtime)
        • run  --seed --input --require-proof   (gerçek sandbox, D4: fs/network yok)
        • export -o snap.tsg                     (gerçek XChaCha20-Poly1305)
        • Ledger secret ZORUNLU (AT-190: dev-secret kaldırıldı; üretim yolu)
        • registry: wasiModuleHash → pkg path; fail-closed + atomic-reload
    KATMAN-2 — EVM transport (opsiyonel extras: pip install tamga[relayer] → web3<7)
        • eth_getLogs poll → RequestExecution event decode
        • EIP-1559 tx imzala → fulfillExecution(requestId, digest, outputData, proof)

KATMAN-0 (bu dosyanın çekirdeği) tamga_runner'ın DEĞİL, onun ÜRETTİĞİ kanıtları
tüketir: çalıştırma → kanıt → fulfill. Bağımsız doğrulama doktrini (AT-075):
fnv1a64 stamp'ini relayer TEKRAR hesaplar (runner'ın --require-proof doğrulamasına
güvenmez — mühür-2 standardı); snapshot digest'ini bağımsız parse eder.

Mühürlü standartlar (Orkestratör onayı 2026-09-24, değişmez):
  1. fulfillExecution'in stateRoot parametresi = encryptedSnapshotDigest = SHA-256(ct)
     — export'un tüm-blob sha256'ı DEĞİL (D3 portabilite: header.created her
     export'ta değişir, tüm-blob digest kararsız olurdu).
  2. Relayer, çıktıyı on-chain göndermeden ÖNCE fnv1a64 stamp kontrolü YAPAR.
  3. Ledger(path, secret=...) üretimde ZORUNLU (AT-190; dev-secret YOK).

Bağımlılık ilkesi: core zero-dependency prensibi KORUNUR. web3 yalnızca
pyproject.toml [project.optional-dependencies] relayer = ["web3<7"] altında,
KATMAN-2'de opsiyonel import edilir; yokluğunda message-RED (usage_guard).
"""

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

__all__ = [
    # KATMAN-0
    "fnv1a64", "verify_output_stamp", "parse_snapshot", "snapshot_body_digest",
    "build_fulfill_payload", "out", "TamgaRelayerError",
    # KATMAN-1
    "load_registry", "resolve_module", "effective_cpu_ms", "run_module",
    "export_snapshot", "open_ledger", "execute_request",
    # KATMAN-2
    "OracleTransport", "daemon_loop",
    # reason-code sabitleri (tamga_runner ile paylaşılan doktrin)
    "RC_OK", "RC_OUTPUT_PROOF_MISMATCH", "RC_SNAPSHOT_BAD_MAGIC",
    "RC_SNAPSHOT_HEADER", "RC_SNAPSHOT_TOO_LARGE",
    "RC_MODULE_NOT_FOUND", "RC_CPU_MS_OUT_OF_RANGE", "RC_RUN_FAILED",
    "RC_REGISTRY_INVALID", "RC_LEDGER_SECRET_REQUIRED", "RC_INSECURE_SECRET",
    "RC_LEDGER_UNAVAILABLE",
]

# --- reason-code'ları (tamga_runner.py ile uyumlu, message-RED) -----------------
# 12 = agent_run_failed ailesi (stamp bozukluğu run çıktısının kanıtını bozar)
RC_OK = 0
RC_OUTPUT_PROOF_MISMATCH = 12      # TAMGA:<fnv1a64> stamp eşleşmedi
RC_SNAPSHOT_BAD_MAGIC = 1          # MAGIC b"TSG1" yok
RC_SNAPSHOT_HEADER = 2             # header JCS/şema çözülemedi
RC_SNAPSHOT_TOO_LARGE = 7          # SAFE_SNAP_MAX aşımı (trivyal-RED, kaynak-tüketimi)
# KATMAN-1 reason-code'ları (oracle-sözleşmesi semantiği)
RC_MODULE_NOT_FOUND = 20           # registry-dışı wasiModuleHash (fail-closed; RCE yok)
RC_CPU_MS_OUT_OF_RANGE = 21        # maxCpuMsAllowed [1,60000] dışında
RC_RUN_FAILED = 22                 # tamga_runner run/export başarısız (rc!=0)
RC_REGISTRY_INVALID = 23           # registry JSON/şema geçersiz
RC_LEDGER_SECRET_REQUIRED = 24     # ledger secret yok (AT-190/193: dev-secret YOK)
RC_INSECURE_SECRET = 25            # bilinen-secret ('dev-secret'/boş) reddedildi
RC_LEDGER_UNAVAILABLE = 26         # sester.ledger modülü bulunamadı (mesh-modülü)
RC_NETWORK = 27                  # RPC ağ-hatası (OSError) — daemon loop sağ-kalsın (AT-225-K2b)

# tamga_runner.py:20 — snapshot format sabitleri (yeniden icat etme: aynı değerler)
SNAPSHOT_MAGIC = b"TSG1"
SNAPSHOT_FORMAT = "tamga-snapshot/1"
SNAPSHOT_CIPHER = "XChaCha20-Poly1305"
# cmd_import'ın koyduğu üst sınırı burada da uyguluyoruz (boyut RED'i = kaynak
# tüketimi koruması; relayer asla sınırsız snapshot parse etmemeli)
SAFE_SNAP_MAX = 64 * (1 << 20)     # 64 MiB — tamga_runner ile aynı değer

# tamga_runner.py:579 cmd_run'un imza ürettiği alanlar (fulfill payload'a taşınır)
RUNNER_ENGINE = "wasmtime-v48.0.1"


class TamgaRelayerError(Exception):
    """Relayer message-RED doktrini: hata bir nedendir, traceback DEĞİL.

    out(ok=False, reason_code=..., reason=...) ile aynı bilgiyi taşır; KATMAN-1/2
    bu istisnayı yakalayıp out()'a çevirir (E-14 guard felsefesi).
    """

    def __init__(self, reason_code, reason):
        super().__init__(f"[{reason_code}] {reason}")
        self.reason_code = reason_code
        self.reason = reason


def out(ok, **kw):
    """Tek-merkez JSON çıkış (tamga_runner.out ile birebir doktrin; E-14 guard).

    Her kötü durum bir MESAJ'dır (ok:false + reason_code + reason), asla
    traceback değil. Sıfır-arg hataları, parse hataları, eksik bağımlılıklar
    hepsi bu noktadan geçer — dağınık hata yolu (AT-194 sınıf-4) YOK.
    """
    print(json.dumps({"ok": bool(ok), **kw}, ensure_ascii=False), flush=True)
    return 0 if ok else 1


# === KATMAN-0/1: fnv1a64 — BYTE-IDENTICAL kopya (tamga_runner.py:30) ===========
# Neden kopya, import değil: (a) relayer'ı tek dosya olarak dağıtmak mümkün olsun;
# (b) parite testleri (AT-195 N2) iki kopyanın da aynı sonucu verdiğini doğrular —
# sürüm kayması ANINDA yakalanır. Tamamen uyuşmazlık = regresyon.
def fnv1a64(b: bytes) -> int:
    """FNV-1a 64-bit — byte-identical to tests/agent-src/src/main.rs (slice-11)
    ve tamga_runner.py:_fnv1a64. Üretim yolu: agent bu değeri hesaplar, runner ve
    relayer BAĞIMSIZ olarak tekrar hesaplar (mühür-2 standardı)."""
    h = 0xcbf29ce484222325
    for x in b:
        h ^= x
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def verify_output_stamp(raw: bytes) -> str:
    """KATMAN-0: agent stdout'unun fnv1a64 stamp'ini BAĞIMSIZ olarak doğrular.

    Kontrat (tamga_runner.py:763-779, --require-proof):
        son satır   = "TAMGA:<fnv1a64-hex16>"   (16 hex karakter, küçük harf)
        doğrulama   = fnv1a64(bu-satırdan-önceki-tüm-baytlar) == int(stamp, 16)

    Başarı → stamp hex (16 karakter). Başarısız → TamgaRelayerError(reason_code=12)
    (runner'ın "output_proof_mismatch: TAMGA line does not match the preceding
    bytes" RED'i ile AYNI kod — kanıt-üretim-tutarlılığı, AT-191 doktrini).

    Runner --require-proof ile zaten doğrular; relayer BUNA GÜVENMEZ — mühür-2:
    on-chain'e göndermeden ÖNCE kendi hesabını yapar (bayt-bayt aynı algoritma).
    """
    try:
        parts = raw.rsplit(b"TAMGA:", 1)
        if len(parts) != 2:
            raise ValueError("stamp-yok: 'TAMGA:<hex16>' satırı bulunamadı")
        head, tag = parts
        tag = tag.rstrip(b"\n")
        if len(tag) != 16 or any(c not in b"0123456789abcdef" for c in tag):
            raise ValueError("stamp-format: 16 küçük-hex değil")
        if fnv1a64(head) != int(tag, 16):
            raise ValueError("stamp-mismatch: fnv1a64(head) != stamp")
    except ValueError as e:
        raise TamgaRelayerError(
            RC_OUTPUT_PROOF_MISMATCH,
            f"output_proof_mismatch: TAMGA line does not match the preceding bytes ({e})"
        ) from None
    return tag.decode("ascii")


# === KATMAN-0: tamga-snapshot/1 parse → encryptedSnapshotDigest ================

def snapshot_body_digest(path) -> dict:
    """KATMAN-0: snapshot dosyasını parse eder → encryptedSnapshotDigest = SHA-256(ct).

    Dilimleme tamga_runner.cmd_import (tamga_runner.py:1101-1142) ile AYNI:
        data[:4]          == MAGIC b"TSG1"
        data[4:8]          = header-uzunluğu (big-endian uint32)
        data[8:8+hlen]     = header JCS (JSON)
        data[8+hlen:]      = ct  ← şifreli gövde (XChaCha20-Poly1305)

    Karar (mühür-1, Orkestratör 2026-09-24): digest = SHA-256(ct) — şifreli
    GÖVDE'nin hash'idir, tüm blob'un DEĞİL. Gerekçe: header.created her export'ta
    değişir; tüm-blob digest aynı state'in iki export'unda farklı değer verir ve
    D3 portabilite invariant'ı çöker. ct kararlıdır.

    Dönüş: {header, ct, digest, blob_sha256, bytes}. header doğrulanır
    (format/cipher/alan-şeması); ct ASLA decrypt EDİLMEZ (relayer seed'i
    tutmaz — üretimde anahtar havuzda, gövde on-chain'e açılmadan gider).
    """
    p = pathlib.Path(path)
    try:
        if p.stat().st_size > SAFE_SNAP_MAX:
            raise TamgaRelayerError(RC_SNAPSHOT_TOO_LARGE, "snapshot_too_large")
        data = p.read_bytes()
    except OSError as e:
        raise TamgaRelayerError(RC_SNAPSHOT_BAD_MAGIC,
                                f"snapshot_bad_magic: {e}") from None
    if data[:4] != SNAPSHOT_MAGIC:
        raise TamgaRelayerError(RC_SNAPSHOT_BAD_MAGIC,
                                "snapshot_bad_magic: MAGIC b\"TSG1\" beklenmedi")
    hlen = int.from_bytes(data[4:8], "big")
    if hlen <= 0 or 8 + hlen > len(data):
        raise TamgaRelayerError(RC_SNAPSHOT_HEADER,
                                f"snapshot_header_invalid: hlen={hlen} aralık-dışı")
    try:
        header = json.loads(data[8:8 + hlen].decode("utf-8"))
    except Exception as e:
        raise TamgaRelayerError(RC_SNAPSHOT_HEADER,
                                f"snapshot_header_invalid: {e}") from None
    # cmd_import._check_header ile aynı şema (format/cipher/alan-adları)
    for k in ("format", "pkg_name", "pkg_wasm_sha256", "agent_id",
              "cipher", "body_nonce", "created"):
        if not isinstance(header, dict) or k not in header:
            raise TamgaRelayerError(RC_SNAPSHOT_HEADER,
                                    f"snapshot_header_invalid: alan-eksik: {k}")
    if header["format"] != SNAPSHOT_FORMAT:
        raise TamgaRelayerError(RC_SNAPSHOT_HEADER,
                                f"snapshot_header_invalid: format={header['format']}")
    if header["cipher"] != SNAPSHOT_CIPHER:
        raise TamgaRelayerError(RC_SNAPSHOT_HEADER,
                                f"snapshot_header_invalid: cipher={header['cipher']}")
    ct = data[8 + hlen:]
    if not ct:
        raise TamgaRelayerError(RC_SNAPSHOT_HEADER,
                                "snapshot_header_invalid: gövde boş (ct yok)")
    return {
        "header": header,
        "ct": ct,
        "digest": hashlib.sha256(ct).hexdigest(),       # ← mühür-1 standardı
        "blob_sha256": hashlib.sha256(data).hexdigest(),  # export'un out() alanı
        "bytes": len(data),
    }


# === KATMAN-0: fulfill payload (JCS canonical) =================================

def build_fulfill_payload(request_id: int, wasi_module_hash: str, run_receipt: dict,
                          snap: dict, ledger_tip=None) -> bytes:
    """KATMAN-0: on-chain gönderilecek fulfill kanıtını JCS canonical olarak kurar.

    outputData'nın içeriği (RFC-009/010 makbuz ailesi ile tutarlı): runner'ın
    ürettiği run-receipt (stdout_sha256, agent_id, session, fee_sim, wall_ms) +
    snapshot digest (mühür-1) + ledger tipi (mühür-3: hash-chain kayıt 'h').

    Neden JCS (RFC 8785) ve plain-JSON değil: bu payload'un digest'i bir YABANCI
    tarafından başka bir dilde (Solidity/JS) yeniden hesaplanabilmeli — plain
    json.dumps(sort_keys=True) Python'a özeldir (tamga_canon.py başlığındaki
    Dümen #4 vakası). Node/Solidity tarafı aynı baytları üretmeli.
    """
    from tamga_canon import jcs
    payload = {
        "kind": "TAMGA_FULFILL/1",
        "request_id": request_id,
        "wasi_module_hash": wasi_module_hash,
        "engine": RUNNER_ENGINE,
        "encrypted_snapshot_digest": snap["digest"],        # mühür-1
        "blob_sha256": snap["blob_sha256"],                 # export out() paritesi
        "pkg_name": snap["header"]["pkg_name"],
        "pkg_wasm_sha256": snap["header"]["pkg_wasm_sha256"],
        "agent_id": snap["header"]["agent_id"],
        "stdout_sha256": run_receipt.get("stdout_sha256"),
        "session": run_receipt.get("session"),
        "fee_sim": run_receipt.get("fee_sim"),
        "wall_ms": run_receipt.get("wall_ms"),
        "cpu_saat": run_receipt.get("cpu_saat"),
        "io_mb": run_receipt.get("io_mb"),
        "ram_gb_sn": run_receipt.get("ram_gb_sn"),
        "input_sha256": run_receipt.get("input_sha256"),
        "payment_scheme": run_receipt.get("payment_scheme"),
        "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    if ledger_tip is not None:
        # unpump-bridge JSONL paritesi: h/prev/seq üçlüsü (mühür-3). Sester'in
        # append() dönüş-değeri {seq, ts, hash, prev_hash} — burada {h, prev}
        # adlarıyla x402/pairing-fixture alan-yapısıyla hizalanır.
        payload["ledger_tip"] = ledger_tip                  # mühür-3
    return jcs(payload)


# === KATMAN-1: üretim-yolu sürücüsü (subprocess → tamga_runner) =================
#
# Karar dosyası §2 sert kısıtları (TAMGA_RELAYER_KARARLARI_2026-09-24):
#   1. fail-closed ZORUNLU — registry'de OLMAYAN wasiModuleHash → RED (skip+log),
#      ASLA keyfi modül çalıştırma. Relayer bir RCE vektörü DEĞİLDİR.
#   2. cpu_ms_per_run çift-kısıtlı: effective = min(request, manifest) + [1,60000]
#      aralık doğrulaması; dışarıda → RED.
#   3. Registry ATOMIC yeniden yükleme: sıcak-yeniden-yükleme YOK — değişim
#      restart gerektirir (TOCTOU: config'i değiştir → pending request'leri farklı
#      modülle çalıştır). load_registry() bir KEZ (daemon başında) çağrılır;
#      modül-düzey cache YOK — execute_request registry'yi argüman alır.

CPU_MS_MIN = 1
CPU_MS_MAX = 60000
RUNNER = "tamga_runner.py"
# registry entry'deki zorunlu alanlar (karar dosyası §2 örneği)
REGISTRY_ENTRY_FIELDS = ("pkg_path", "cpu_ms_per_run", "max_input_bytes")


def load_registry(path) -> dict:
    """KATMAN-1: wasiModuleHash → paket registry'sini BİR KEZ yükler (daemon başı).

    Atomic-reload kısıtı: bu fonksiyon çağrıldığında dosya TAM okunur ve doğrulanır;
    dönen dict dondurulmuş kabul edilir. Sıcak-yeniden-yükleme YAPILMAZ — config
    değişirse relayer RESTART edilir (TOCTOU açığı kapatılmıştır).

    Yapı (karar dosyası §2):
        {"<wasiModuleHash hex>": {"pkg_path": "unpump-bridge/agent",
                                  "cpu_ms_per_run": 5000,
                                  "max_input_bytes": 262144}, ...}
    """
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8")
        reg = json.loads(text)
    except OSError as e:
        raise TamgaRelayerError(RC_REGISTRY_INVALID,
                                f"registry_invalid: okunamadı: {e}") from None
    except json.JSONDecodeError as e:
        raise TamgaRelayerError(RC_REGISTRY_INVALID,
                                f"registry_invalid: JSON hatası: {e}") from None
    if not isinstance(reg, dict) or not reg:
        raise TamgaRelayerError(RC_REGISTRY_INVALID,
                                "registry_invalid: boş veya obje-değil")
    # _-önekli anahtarlar METADATA'dır (registry dokümantasyonu; örn _aciklama,
    # _atomic_reload). Entry sayılmaz — hex-olmadıkları için zaten entry olamazlar,
    # ama açık-atlama sözleşmesi bunu belirsiz bırakmaz (üretim-registry'leri
    # insan-açıklaması taşıyabilsin diye).
    entries = {k: v for k, v in reg.items() if not k.startswith("_")}
    if not entries:
        raise TamgaRelayerError(RC_REGISTRY_INVALID,
                                "registry_invalid: entry-yok (yalnızca _-metadata)")
    for hsh, entry in entries.items():
        if not isinstance(entry, dict):
            raise TamgaRelayerError(RC_REGISTRY_INVALID,
                                    f"registry_invalid: {hsh[:12]}… entry-obje-değil")
        for f in REGISTRY_ENTRY_FIELDS:
            if f not in entry:
                raise TamgaRelayerError(RC_REGISTRY_INVALID,
                                        f"registry_invalid: {hsh[:12]}… alan-eksik: {f}")
        cpu = entry["cpu_ms_per_run"]
        if not isinstance(cpu, int) or isinstance(cpu, bool) \
                or not (CPU_MS_MIN <= cpu <= CPU_MS_MAX):
            raise TamgaRelayerError(
                RC_REGISTRY_INVALID,
                f"registry_invalid: {hsh[:12]}… cpu_ms_per_run={cpu!r} [1,60000] dışı")
        if not isinstance(entry["max_input_bytes"], int) or entry["max_input_bytes"] <= 0:
            raise TamgaRelayerError(
                RC_REGISTRY_INVALID,
                f"registry_invalid: {hsh[:12]}… max_input_bytes geçersiz")
        if not pathlib.Path(entry["pkg_path"]).is_dir():
            raise TamgaRelayerError(
                RC_REGISTRY_INVALID,
                f"registry_invalid: {hsh[:12]}… pkg_path yok: {entry['pkg_path']}")
    return reg


def resolve_module(registry: dict, wasi_module_hash: str) -> dict:
    """KATMAN-1: wasiModuleHash → registry entry. FAIL-CLOSED.

    Registry'de OLMAYAN hash → RC_MODULE_NOT_FOUND RED'i. Relayer ASLA keyfi
    modül çalıştırmaz — bu, relayer'ın bir RCE vektörü OLMADIĞININ garantisi
    (Orkestratör AT-198 alt-vakası: kanıtlanması gereken budur).
    """
    if not isinstance(wasi_module_hash, str) or not wasi_module_hash:
        raise TamgaRelayerError(RC_MODULE_NOT_FOUND,
                                "module-not-registered: wasiModuleHash boş/değil")
    try:
        bytes.fromhex(wasi_module_hash)
    except ValueError:
        raise TamgaRelayerError(
            RC_MODULE_NOT_FOUND,
            f"module-not-registered: wasiModuleHash hex-değil: {wasi_module_hash[:16]}…"
        ) from None
    entry = registry.get(wasi_module_hash)
    if entry is None:
        raise TamgaRelayerError(
            RC_MODULE_NOT_FOUND,
            f"module-not-registered: {wasi_module_hash[:16]}… registry'de-YOK "
            f"(fail-closed: keyfi-modül-çalıştırma-YOK — RCE-vektörü-değil)"
        )
    return entry


def effective_cpu_ms(request_ms, manifest_cpu_ms) -> int:
    """KATMAN-1: çift-kısıtlı CPU bütçesi = min(request, manifest) + [1,60000].

    Oracle sözleşmesi maxCpuMsAllowed'ı [1,60000] aralığında göndermek zorundadır
    (EVM gas DEĞİL — wasmtime cpu_ms). Relayer bu sözleşmeyi doğrular:
      • aralık-dışı request → RC_CPU_MS_OUT_OF_RANGE RED (sözleşme-ihlali)
      • request > manifest → manifest kazanır (ASLA aşılmaz; runner manifest'i
        kaynaktan okur, relayer sadece ihlali raporlar)
    """
    bad = (not isinstance(request_ms, int) or isinstance(request_ms, bool)
           or not (CPU_MS_MIN <= request_ms <= CPU_MS_MAX))
    if bad:
        raise TamgaRelayerError(
            RC_CPU_MS_OUT_OF_RANGE,
            f"cpu_ms_out_of_range: maxCpuMsAllowed={request_ms!r} "
            f"[{CPU_MS_MIN},{CPU_MS_MAX}] dışında (sözleşme-ihlali)")
    eff = min(request_ms, manifest_cpu_ms)
    if eff < CPU_MS_MIN:
        raise TamgaRelayerError(
            RC_CPU_MS_OUT_OF_RANGE,
            f"cpu_ms_out_of_range: effective={eff} < {CPU_MS_MIN} "
            f"(manifest cpu_ms_per_run={manifest_cpu_ms})")
    return eff


def _runner(argv: list, cwd: str = None) -> dict:
    """tamga_runner.py subprocess'ini çalıştırır; JSON out()'u parse eder.

    Üretim yolu doktrini (AT-075): test-double YOK — gerçek wasmtime, gerçek
    sandbox (D4: fs preopen/network yok). argv her zaman LİSTE-form (shell=False)
    — AT-194 sınıf-1 injection taraması ile uyumlu.
    cwd varsayılanı: tamga_oracle_relayer.py'nin-dizini (runner orada; workdir
    yalnız geçici-dosyalar içindir — kirlilik-yok).
    """
    if cwd is None:
        cwd = str(pathlib.Path(__file__).resolve().parent)
    try:
        r = subprocess.run([sys.executable, RUNNER, *argv], capture_output=True,
                           text=True, cwd=cwd)
    except OSError as e:
        raise TamgaRelayerError(RC_RUN_FAILED,
                                f"runner_unavailable: {RUNNER} başlatılamadı: {e}") from None
    if r.returncode != 0:
        tail = (r.stdout + r.stderr).strip().replace("\n", " ")[-160:]
        raise TamgaRelayerError(
            RC_RUN_FAILED, f"runner rc={r.returncode}: {tail}")
    try:
        return json.loads(r.stdout.splitlines()[-1])
    except (json.JSONDecodeError, IndexError) as e:
        raise TamgaRelayerError(RC_RUN_FAILED,
                                f"runner çıktı JSON değil: {e}") from None


def run_module(pkg_path, seed_hex, input_path=None, cwd=".") -> dict:
    """KATMAN-1: gerçek wasmtime koşumu (tamga_runner run --require-proof).

    --require-proof: agent stdout'una TAMGA:<fnv1a64> damgasını basar; runner ve
    KATMAN-0 BAĞIMSIZ olarak doğrular (mühür-2). Dönüş: runner out() JSON'u
    (stdout_file, stdout_sha256, session, fee_sim, ...).
    """
    argv = ["run", str(pkg_path), "--seed", seed_hex, "--require-proof"]
    if input_path is not None:
        argv += ["--input", str(input_path)]
    res = _runner(argv, cwd)
    if res.get("ok") is not True:
        raise TamgaRelayerError(
            RC_RUN_FAILED,
            f"run ok=false: {res.get('reason_code')} {res.get('reason')}")
    return res


def export_snapshot(pkg_path, seed_hex, out_path, cwd=".") -> str:
    """KATMAN-1: gerçek XChaCha20-Poly1305 snapshot export'u (mühür-1 kaynağı).

    Dönüş: snapshot dosya yolu (caller snapshot_body_digest ile parse eder).
    """
    res = _runner(["export", str(pkg_path), "-o", str(out_path), "--seed", seed_hex], cwd)
    if res.get("ok") is not True:
        raise TamgaRelayerError(
            RC_RUN_FAILED,
            f"export ok=false: {res.get('reason_code')} {res.get('reason')}")
    return str(out_path)


def open_ledger(db_path, secret):
    """KATMAN-1: oracle-operatör maliyet-ledger'ı (sester Ledger; AT-190/193).

    Secret ZORUNLU — 'dev-secret' varsayılanı KALDIRILDI (AT-190), bilinen-değer
    reddedilir (AT-179/193). Doğrulama relayer'da ÖNCE yapılır (testlerin
    sester'e bağımlı olmadan RED yollarını doğrulayabilmesi için); sester.ledger
    aynı doğrulamayı tekrar yapar (çift-katman).
    """
    if secret is None:
        raise TamgaRelayerError(
            RC_LEDGER_SECRET_REQUIRED,
            "ledger-secret-required: Ledger-secret-ZORUNLU — 'dev-secret'-"
            "varsayılanı-YOK (AT-190/193); açık-secret-geçin")
    if secret in ("dev-secret", ""):
        raise TamgaRelayerError(
            RC_INSECURE_SECRET,
            "insecure-secret: 'dev-secret'/boş BİLİNEN-değer — sahte-HMAC-"
            "üretilebilir; üretimde-gerçek-secret-geçin — AT-179/AT-193")
    # mesh-modül yolu (üretimde PYTHONPATH'te; testler/dağıtım env ile bildirir)
    se = os.environ.get("TAMGA_SESTER_PATH")
    if se and se not in sys.path:
        sys.path.insert(0, se)
    try:
        from sester.ledger import Ledger          # mesh-modülü
    except ImportError as e:
        raise TamgaRelayerError(
            RC_LEDGER_UNAVAILABLE,
            f"ledger-unavailable: sester.ledger bulunamadı (mesh-modülü): {e}") from None
    return Ledger(db_path, secret=secret)


def execute_request(request: dict, registry: dict, seed_hex: str,
                    workdir: str = ".", ledger_secret=None) -> dict:
    """KATMAN-1: tam üretim-yolu — RequestExecution → fulfill kanıtına.

    Akış: resolve(fail-closed) → cpu-çift-kısıt → run(gerçek wasmtime) →
    stamp(mühür-2) → export(gerçek AEAD) → digest(mühür-1) → fulfill(JCS).

    request: {"wasi_module_hash", "input_payload" (bytes/dosya-yolu/None),
              "max_cpu_ms_allowed", "request_id"}
    Dönüş: {receipt, stamp, digest, payload, blob_sha256, effective_cpu_ms}
    """
    entry = resolve_module(registry, request["wasi_module_hash"])
    manifest = json.loads((pathlib.Path(entry["pkg_path"]) / "tamga.json")
                          .read_text(encoding="utf-8"))
    manifest_cpu = int(manifest["runtime"]["limits"]["cpu_ms_per_run"])
    if entry["cpu_ms_per_run"] != manifest_cpu:
        raise TamgaRelayerError(
            RC_REGISTRY_INVALID,
            f"registry_invalid: cpu-ms-uyumsuz registry={entry['cpu_ms_per_run']} "
            f"manifest={manifest_cpu} ({entry['pkg_path']})")
    eff = effective_cpu_ms(int(request["max_cpu_ms_allowed"]), manifest_cpu)

    inp = request.get("input_payload")
    inp_path = None
    input_sha256 = None
    if inp is not None and not isinstance(inp, (str, pathlib.PurePath)):
        data = bytes(inp)
        if len(data) > entry["max_input_bytes"]:
            raise TamgaRelayerError(
                RC_CPU_MS_OUT_OF_RANGE,
                f"input-too-large: {len(data)} > {entry['max_input_bytes']} "
                f"(registry max_input_bytes)")
        tf = pathlib.Path(workdir) / f".relayer-input-{os.getpid()}.bin"
        tf.write_bytes(data)
        inp_path = tf
        input_sha256 = hashlib.sha256(data).hexdigest()   # bağımsız (runner'a değil)
    elif isinstance(inp, (str, pathlib.PurePath)):
        inp_path = pathlib.Path(inp)
        input_sha256 = hashlib.sha256(
            inp_path.read_bytes()).hexdigest() if inp_path.is_file() else None

    receipt = run_module(entry["pkg_path"], seed_hex, inp_path)
    try:
        stdout = pathlib.Path(receipt["stdout_file"]).read_bytes()
        stamp = verify_output_stamp(stdout)          # mühür-2: bağımsız fnv1a64
    finally:
        if inp_path is not None and isinstance(inp, (bytes, bytearray)):
            pathlib.Path(inp_path).unlink(missing_ok=True)

    snap_path = export_snapshot(entry["pkg_path"], seed_hex,
                                str(pathlib.Path(workdir) / f".relayer-snap-{os.getpid()}.tsg"))
    snap = snapshot_body_digest(snap_path)           # mühür-1: SHA-256(ct)

    # unpump-bridge charge_record paritesi: runner-ölçümleri + bağımsız input
    # hash'i (hepsi özyinelemesiz — outputData'dan ÖNCE kararır).
    charge = {
        "op": "charge",
        "pkg": manifest["package"]["name"],
        "request_id": str(request.get("request_id")),
        "engine": RUNNER_ENGINE,
        "cpu_saat": receipt.get("cpu_saat"),
        "fee_sim": receipt.get("fee_sim"),
        "fee_birebir": receipt.get("fee_birebir"),
        "io_mb": receipt.get("io_mb"),
        "ram_gb_sn": receipt.get("ram_gb_sn"),
        "wall_ms": receipt.get("wall_ms"),
        "stdout_sha256": receipt.get("stdout_sha256"),
        "input_sha256": input_sha256,
    }

    ledger_tip = None
    if ledger_secret is not None:
        led = open_ledger(str(pathlib.Path(workdir) / "relayer-ledger.sqlite3"),
                          ledger_secret)
        # event-tipi sester taksonomisindedir (ERRATUM-K0.2; 'oracle_fulfill' yeni
        # tip ekler — mevcut 'charge_receipt' ailesi ile uyumlu, AT-193 yolu)
        led_rec = led.append("charge_receipt", str(request.get("request_id")),
                             entry["pkg_path"], float(receipt.get("fee_sim", 0)),
                             payload=charge)
        # mühür-3 canlı-yol: append() dönüşü {seq, ts, hash, prev_hash} —
        # getattr(led,'tip') YOK (önceden ölü-koddu; 2026-09-25 bulgusu).
        ledger_tip = {"seq": led_rec.get("seq"), "h": led_rec.get("hash"),
                      "prev": led_rec.get("prev_hash")}

    receipt["input_sha256"] = input_sha256
    receipt["payment_scheme"] = (manifest.get("payment", {}).get("schemes") or [None])[0]

    payload = build_fulfill_payload(
        int(request.get("request_id", 0)), request["wasi_module_hash"],
        receipt, snap, ledger_tip=ledger_tip)

    # delivery_hash: keccak256(outputData) — x402 durable-evidence bağlantısı
    # (pairing-fixture: keccak-legacy-padding; hashlib.sha3_256 UYUŞMAZ).
    # outputData'da DEĞİL — özyinelemesiz (keccak payload-baytları üzerinden).
    try:
        from tamga_keccak import keccak256
        delivery_hash = keccak256(payload).hex()
    except Exception:
        delivery_hash = None

    return {"receipt": receipt, "stamp": stamp, "digest": snap["digest"],
            "blob_sha256": snap["blob_sha256"], "payload": payload.decode("utf-8"),
            "effective_cpu_ms": eff, "delivery_hash": delivery_hash,
            "ledger_tip": ledger_tip}


# === KATMAN-2: EVM transport (opsiyonel extras: pip install tamga[relayer]) =====
#
# Karar dosyası §3 (onaylı): web3<7 yalnız [project.optional-dependencies]
# relayer altındadır; core zero-dependency prensibi KORUNUR. Import'ta web3 yoksa
# message-RED (usage_guard). KATMAN-2: eth_getLogs poll → RequestExecution decode
# + EIP-1559 imzalı fulfillExecution tx.
#
# Mühürlü arayüz (Orkestratör 2026-09-24):
#   event RequestExecution(uint256 indexed requestId, address indexed caller,
#       bytes32 wasiModuleHash, bytes inputPayload, uint32 maxCpuMsAllowed,
#       address indexed callbackContract, bytes4 callbackSelector);
#   function fulfillExecution(uint256 requestId, bytes32 encryptedSnapshotDigest,
#       bytes outputData, bytes nodeSignatureOrProof) external;

RC_WEB3_MISSING = 27             # web3 kurulu değil (pip install tamga[relayer])
RC_TX_FAILED = 28                # fulfill tx revert etti veya makbuz alınamadı

ORACLE_ABI = [
    {"anonymous": False, "inputs": [
        {"indexed": True, "internalType": "uint256", "name": "requestId", "type": "uint256"},
        {"indexed": True, "internalType": "address", "name": "caller", "type": "address"},
        {"indexed": False, "internalType": "bytes32", "name": "wasiModuleHash", "type": "bytes32"},
        {"indexed": False, "internalType": "bytes", "name": "inputPayload", "type": "bytes"},
        {"indexed": False, "internalType": "uint32", "name": "maxCpuMsAllowed", "type": "uint32"},
        {"indexed": True, "internalType": "address", "name": "callbackContract", "type": "address"},
        {"indexed": False, "internalType": "bytes4", "name": "callbackSelector", "type": "bytes4"},
     ], "name": "RequestExecution", "type": "event"},
    {"inputs": [
        {"internalType": "uint256", "name": "requestId", "type": "uint256"},
        {"internalType": "bytes32", "name": "encryptedSnapshotDigest", "type": "bytes32"},
        {"internalType": "bytes", "name": "outputData", "type": "bytes"},
        {"internalType": "bytes", "name": "nodeSignatureOrProof", "type": "bytes"},
     ], "name": "fulfillExecution", "outputs": [],
     "stateMutability": "nonpayable", "type": "function"},
]


class OracleTransport:
    """KATMAN-2: EVM iletişim katmanı (web3 opsiyonel; anvil/solc gerekmez).

    • fetch_requests(from_block): eth_getLogs → RequestExecution event'lerini
      decode eder → KATMAN-1'in işleyeceği request dict'leri.
    • submit_fulfillment(...): EIP-1559 tx imzalar + fulfillExecution'ı gönderir;
      gerçek makbuz (status + gasUsed) döner (AT-196 receipt-doğrulaması).
    """

    def __init__(self, rpc_url, oracle_address, account_private_key, chain_id=None):
        try:
            from web3 import Web3
        except ImportError as e:
            raise TamgaRelayerError(
                RC_WEB3_MISSING,
                f"web3-missing: EVM transport için 'pip install tamga[relayer]': {e}"
            ) from None
        self._w3 = Web3(Web3.HTTPProvider(rpc_url))
        if not self._w3.is_connected():
            raise TamgaRelayerError(RC_TX_FAILED,
                                    f"rpc-unreachable: {rpc_url}")
        self._acct = self._w3.eth.account.from_key(account_private_key)
        self._chain_id = chain_id or self._w3.eth.chain_id
        self._oracle = self._w3.eth.contract(
            address=self._w3.to_checksum_address(oracle_address), abi=ORACLE_ABI)

    # --- RequestExecution okuma (eth_getLogs poll) ---------------------------
    # Event'in imzalı-alan-yapısı (ABI'den sabit; indexed + data ayrımı):
    #   indexed topics[1..3]: requestId, caller, callbackContract
    #   data (ABI-encoded): (bytes32 wasiModuleHash, bytes inputPayload,
    #                        uint32 maxCpuMsAllowed, bytes4 callbackSelector)
    # Manuel decode: web3<7 process_log ABI-çözümünde HexBytes/bytes uyuşmazlığı
    # patlar (AT-196 keşfi); decode doğrudan eth_abi ile — test-double YOK,
    # log formatı ve ABI-encoding gerçektir.
    REQ_DECODER = ["bytes32", "bytes", "uint32", "bytes4"]

    def fetch_requests(self, from_block=0):
        # AT-225-K2b: ağ-kesintisi (OSError) burada-fırlar — daemon_loop'un
        # TamgaRelayerError-except'ine-düşmez → loop-ölür. Saralım: loop-sağ-
        # kalsın-ve-bir-sonraki-cycle'da-tekrar-deneyecek (fail-closed:
        # yanlış-tx-ASLA-gönderilmez).
        try:
            logs = self._w3.eth.get_logs({
                "fromBlock": from_block, "toBlock": "latest",
                "address": self._oracle.address,
                "topics": [self._request_topic()],
            })
        except OSError as e:
            raise TamgaRelayerError(
                RC_NETWORK, f"rpc-ağ-hatası (get_logs): {e}") from None
        reqs = []
        for lg in logs:
            tops = lg["topics"]
            raw = lg["data"]
            if isinstance(raw, (bytes, bytearray)):
                raw_hex = raw.hex() if not raw.hex().startswith("0x") else raw.hex()[2:]
            else:
                raw_hex = raw[2:] if raw.startswith("0x") else raw
            try:
                from eth_abi import decode as _abi_decode
                vals = _abi_decode(self.REQ_DECODER, bytes.fromhex(raw_hex))
            except Exception as e:
                raise TamgaRelayerError(
                    RC_SNAPSHOT_HEADER,
                    f"request-decode-hatası (log #{lg.get('logIndex')}): {e}") from None
            reqs.append({
                "request_id": int.from_bytes(tops[1], "big"),
                "caller": "0x" + bytes(tops[2][-20:]).hex(),
                "wasi_module_hash": vals[0].hex(),
                "input_payload": bytes(vals[1]),
                "max_cpu_ms_allowed": int(vals[2]),
                "callback_contract": "0x" + bytes(tops[3][-20:]).hex(),
                "callback_selector": bytes(vals[3]),
                "tx_hash": (bytes(lg["transactionHash"]).hex()
                            if isinstance(lg.get("transactionHash"), (bytes, bytearray))
                            else str(lg.get("transactionHash", ""))),
                "log_index": lg.get("logIndex"),
                "block_number": lg.get("blockNumber"),
            })
        return reqs

    def _request_topic(self):
        # keccak256("RequestExecution(uint256,address,bytes32,bytes,uint32,address,bytes4)")
        # — web3 event imza topic'i ile aynı. HexBytes GİBİSİ olmadan: eth-tester'ın
        # topic-filtre karşılaştırması HexBytes.hex()'in "0x"-önekini yanlış
        # eşler (AT-196 keşfi); saf-bytes gönderilir.
        return bytes(self._w3.keccak(text="RequestExecution(uint256,address,bytes32,"
                                        "bytes,uint32,address,bytes4)"))

    # --- fulfillExecution gönderme (EIP-1559 imzalı) -------------------------
    def submit_fulfillment(self, request_id, encrypted_snapshot_digest_hex,
                           output_data_bytes, proof_bytes, gas=500000):
        digest = bytes.fromhex(encrypted_snapshot_digest_hex)
        if len(digest) != 32:
            raise TamgaRelayerError(
                RC_SNAPSHOT_HEADER,
                f"digest-uzunluğu: {len(digest)} (bytes32 = 32 beklenir)")
        try:
            nonce = self._w3.eth.get_transaction_count(self._acct.address)
            # AT-211-bulgusu: sabit 2-gwei-maxFee Base-mainnet'te (baseFee
            # 0.005 gwei) 400×-aşırı-ücrettir → düşük-bakiyeli-hesapta
            # 'insufficient funds for gas * price' ile daemon-çöker. Dinamik:
            # zincir-baseFee'nin-2× + makul-priority (üretim + test-anvil uyumlu).
            try:
                base = int(self._w3.eth.get_block("latest")["baseFeePerGas"])
            except Exception:
                base = self._w3.to_wei(1, "gwei")
            prio = max(self._w3.to_wei(0.001, "gwei"), base // 2)
            tx = self._oracle.functions.fulfillExecution(
                request_id, digest, output_data_bytes, proof_bytes
            ).build_transaction({
                "from": self._acct.address,
                "nonce": nonce,
                "chainId": self._chain_id,
                "gas": gas,
                "maxFeePerGas": base * 2 + prio,
                "maxPriorityFeePerGas": prio,
            })
            signed = self._acct.sign_transaction(tx)
            # eth_account <0.13 → camelCase rawTransaction; ≥0.13 → snake_case
            # raw_transaction. İkisini de destekle ( pinned-venv ve yeni
            # user-site sürümleri arasında API-çakışmasını önle).
            _raw = getattr(signed, "raw_transaction", None)
            if _raw is None:
                _raw = signed.rawTransaction  # eski camelCase API
            h = self._w3.eth.send_raw_transaction(_raw)
            rcpt = self._w3.eth.wait_for_transaction_receipt(h)
        except TamgaRelayerError:
            raise
        except Exception as e:
            # web3/eth-tester hataları (gas-yetersiz, intrinsic-gas-too-low,
            # nonce/validasyon): daemon crash-ETMEMELİ — RC_TX_FAILED fail-closed.
            # EIP-1559 yolundaki tüm istisnalar message-RED'e döner (AT-203).
            raise TamgaRelayerError(
                RC_TX_FAILED,
                f"fulfill-tx-hata: {type(e).__name__}: {str(e)[:160]}")
        if rcpt["status"] != 1:
            raise TamgaRelayerError(
                RC_TX_FAILED,
                f"fulfill-tx-revert: status={rcpt['status']} tx={h.hex()[:18]}…")
        return {"tx_hash": h.hex(), "status": rcpt["status"],
                "gas_used": int(rcpt["gasUsed"]), "block": int(rcpt["blockNumber"])}


def _load_replay_cache(path) -> dict:
    """Disk replay-önbelleği: request_id→tx_hash (daemon-restart-koruma, AT-207).

    Bozuk/okunamaz-dosya → taze-başla (fail-open-DEĞİL: bu katman ek-savunma;
    asıl koruma zincir-üyeliğindedir). int-key'ler JSON'da-string'e-döner —
    geri-çevir.
    """
    try:
        raw = json.loads(path.read_text())
        return {int(k): v for k, v in raw.items()}
    except FileNotFoundError:
        return {}
    except Exception:
        return {}


def _save_replay_cache(path, fulfilled: dict) -> None:
    """Atomik-yaz (tmp+os.replace) — çökme-anında-yarım-dosya-kalmaz.

    tx_hash HexBytes-gelebilir → hex-string'e-normalize (json.dumps-yok).
    """
    try:
        norm = {str(k): (v.hex() if hasattr(v, "hex") else str(v))
                for k, v in fulfilled.items()}
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(norm))
        os.replace(tmp, path)
    except Exception:
        pass   # disk-dolu/izin → zincir-guard'ı-destekler; daemon-durmaz


def daemon_loop(transport: "OracleTransport", registry: dict, seed_hex: str,
                ledger_secret=None, workdir: str = ".", interval_s: int = 15,
                once: bool = False, max_cycles: int | None = None,
                gas: int = 500000, from_block: int | None = None,
                backfill: int = 100, log=print):
    """KATMAN-2 daemon döngüsü: poll → execute → fulfill (sistemd daemon modu).

    Replay koruması: request_id → tx_hash kümesi — ARTIK DISKE-DAYALI
    (workdir/.tamga-fulfilled.json; AT-207 canlı-bulgusu-sonrası). Aynı request
    ikinci poll'de fulfilled'de-zaten-var → TEKRAR fulfill EDİLMEZ (AT-202),
    ve daemon RESTART'ından-sonra-da EDİLMEZ: önbellek atomik-yazılır ve
    açılışta-yeniden-yüklenir. AT-207 canlıda-kanıtladı: process-ömrü-ince
    koruma yetersizdi (restart → set-sıfırlanır → çift-fulfill; oracle
    kontratında replay-guard olmayınca zincir bunu durdurmuyordu).
    Hatalar message-RED olarak log'lanır, döngü DURMAZ (systemd Restart=always
    ile çift-katman; watchdog'a gerek bırakmaz).
    max_cycles: None=sonsuz (üretim); sayı=kaç-poll-cycle-sonra-dön (test).
    Canlı-zincir-uyumu: from_block=0 tüm-zinciri-tarar (public-RPC limitlerini
    aşar — Base mainnet 51M block). daemon cursor-takibi-yapar: başlangıçta
    latest-backfill, her-cycle'da block-number'a-güncellenir (AT-205 bulgusu).
    """
    replay_path = pathlib.Path(workdir) / ".tamga-fulfilled.json"
    fulfilled = _load_replay_cache(replay_path)
    cycle = 0
    cursor = from_block
    if cursor is None:
        try:
            cursor = max(0, int(transport._w3.eth.block_number) - backfill)
        except Exception:
            cursor = 0
    while True:
        cycle += 1
        try:
            for req in transport.fetch_requests(cursor):
                rid = req["request_id"]
                if rid in fulfilled:
                    continue
                exec_req = {
                    "wasi_module_hash": req["wasi_module_hash"],
                    "max_cpu_ms_allowed": req["max_cpu_ms_allowed"],
                    "request_id": rid,
                    "input_payload": (bytes(req["input_payload"])
                                      if req["input_payload"] else None),
                }
                try:
                    res = execute_request(exec_req, registry, seed_hex,
                                          workdir=workdir,
                                          ledger_secret=ledger_secret)
                    out = transport.submit_fulfillment(
                        rid, res["digest"], res["payload"].encode(),
                        res["receipt"]["stdout_sha256"].encode(), gas=gas)
                except TamgaRelayerError as e:
                    log(f"[relayer] request {rid} RED: {e.reason_code} {e.reason}")
                    continue
                fulfilled[rid] = out["tx_hash"]
                _save_replay_cache(replay_path, fulfilled)
                log(f"[relayer] request {rid} fulfilled: tx={out['tx_hash'][:18]}… "
                    f"status={out['status']} gasUsed={out['gas_used']} "
                    f"digest={res['digest'][:12]}… "
                    f"delivery={res.get('delivery_hash') or '-'}")
        except TamgaRelayerError as e:
            log(f"[relayer] poll-hatası (devam): {e.reason_code} {e.reason}")
        # sonraki-cycle: cursor'u-güncelle (stale-yok; public-RPC için-ardışık-tarama)
        try:
            cursor = int(transport._w3.eth.block_number)
        except OSError as e:
            log(f"[relayer] ağ-hatası (devam): {e}")
        except Exception:
            pass
        if once or (max_cycles is not None and cycle >= max_cycles):
            return fulfilled
        time.sleep(interval_s)


# === CLI (KATMAN-0 yüzü: üretilen kanıtları bağımsız denetle) ===================

USAGE = {
    "verify-stamp": "verify-stamp <stdout-file>",
    "snapshot-digest": "snapshot-digest <snap.tsg>",
    "registry-check": "registry-check <registry.json>",
    "run-request": "run-request --registry <json> --seed <hex> --module-hash <hex> "
                   "[--cpu-ms N] [--input <file>] [--ledger-secret S]",
    "daemon": "daemon --registry <json> --seed <hex> --rpc-url <url> --oracle <hex> "
              "--key <hex> [--ledger-secret S] [--interval N] [--once] [--workdir D] "
              "[--from-block N] [--backfill N]",
}


def cmd_verify_stamp(a):
    if len(a) < 1:
        return out(False, op="verify-stamp", reason_code=2,
                   reason=f"kullanim: {USAGE['verify-stamp']} (en-az 1 argman)")
    try:
        raw = pathlib.Path(a[0]).read_bytes()
    except OSError as e:
        return out(False, op="verify-stamp", reason_code=1, reason=f"dosya-yok: {e}")
    try:
        stamp = verify_output_stamp(raw)
        return out(True, op="verify-stamp", file=a[0], stamp=stamp,
                   fnv1a64_ok=True, stdout_sha256=hashlib.sha256(raw).hexdigest())
    except TamgaRelayerError as e:
        return out(False, op="verify-stamp", reason_code=e.reason_code, reason=e.reason)


def cmd_snapshot_digest(a):
    if len(a) < 1:
        return out(False, op="snapshot-digest", reason_code=2,
                   reason=f"kullanim: {USAGE['snapshot-digest']} (en-az 1 argman)")
    try:
        s = snapshot_body_digest(a[0])
    except TamgaRelayerError as e:
        return out(False, op="snapshot-digest", reason_code=e.reason_code, reason=e.reason)
    return out(True, op="snapshot-digest", file=a[0],
               encrypted_snapshot_digest=s["digest"],
               blob_sha256=s["blob_sha256"], bytes=s["bytes"],
               pkg_name=s["header"]["pkg_name"],
               agent_id=s["header"]["agent_id"])


def _opt(a, flag, default=None):
    """--flag value argüman çıkarıcı (LİSTE-form; shell-injection yüzü YOK)."""
    if flag in a:
        i = a.index(flag)
        if i + 1 < len(a):
            return a[i + 1]
    return default


def cmd_registry_check(a):
    if len(a) < 1:
        return out(False, op="registry-check", reason_code=2,
                   reason=f"kullanim: {USAGE['registry-check']} (en-az 1 argman)")
    try:
        reg = load_registry(a[0])
    except TamgaRelayerError as e:
        return out(False, op="registry-check", reason_code=e.reason_code, reason=e.reason)
    mods = [k for k in reg if not k.startswith("_")]
    return out(True, op="registry-check", file=a[0],
               modules=len(mods), hashes=[h[:16] for h in mods])


def cmd_daemon(a):
    if len(a) < 1:
        return out(False, op="daemon", reason_code=2,
                   reason=f"kullanim: {USAGE['daemon']}")
    reg_path = _opt(a, "--registry")
    seed = _opt(a, "--seed")
    rpc = _opt(a, "--rpc-url") or os.environ.get("TAMGA_RELAYER_RPC_URL")
    oracle = _opt(a, "--oracle") or os.environ.get("TAMGA_RELAYER_ORACLE")
    key = _opt(a, "--key") or os.environ.get("TAMGA_RELAYER_KEY")
    sec = _opt(a, "--ledger-secret") or os.environ.get("TAMGA_RELAYER_LEDGER_SECRET")
    workdir = _opt(a, "--workdir", ".")
    interval = int(_opt(a, "--interval", "15"))
    once = "--once" in a
    from_block = _opt(a, "--from-block")
    from_block = int(from_block) if from_block else None
    backfill = int(_opt(a, "--backfill", "100"))
    if not (reg_path and seed and rpc and oracle and key):
        return out(False, op="daemon", reason_code=2,
                   reason=f"kullanim: {USAGE['daemon']} (registry/seed/rpc-url/"
                          "oracle/key zorunlu)")
    try:
        reg = load_registry(reg_path)
        t = OracleTransport(rpc, oracle, key)
    except TamgaRelayerError as e:
        return out(False, op="daemon", reason_code=e.reason_code, reason=e.reason)
    fulfilled = daemon_loop(t, reg, seed, ledger_secret=sec, workdir=workdir,
                            interval_s=interval, once=once,
                            from_block=from_block, backfill=backfill)
    return out(True, op="daemon", registry=reg_path, fulfilled=len(fulfilled),
               requests=fulfilled)


def cmd_run_request(a):
    if len(a) < 1:
        return out(False, op="run-request", reason_code=2,
                   reason=f"kullanim: {USAGE['run-request']}")
    reg_path = _opt(a, "--registry")
    seed = _opt(a, "--seed")
    mh = _opt(a, "--module-hash")
    cpu = _opt(a, "--cpu-ms")
    inp = _opt(a, "--input")
    sec = _opt(a, "--ledger-secret")
    workdir = _opt(a, "--workdir", ".")
    # argv öncelikli, env yalnızca fallback (cmd_daemon_fulfill:947 ile aynı desen).
    # Önceki 'env.get(ENV, sec) if sec' argv-VERİLDİĞİNDE-argv'i-ezdi: dev-secret
    # sessizce-yok-sayıldı → K5 GREEN (AT-197 bulgusu); ve argv-YOKKEN env'i
    # hiç-okumadan RC-24'e-düşürdü. Açık-talep kazanır — bilinen-değer-reddi
    # (AT-179/193) env-kirliliğinde-baypas-edilemez.
    sec = sec or os.environ.get("TAMGA_RELAYER_LEDGER_SECRET")
    if not (reg_path and seed and mh):
        return out(False, op="run-request", reason_code=2,
                   reason=f"kullanim: {USAGE['run-request']} (registry/seed/"
                          "module-hash zorunlu)")
    try:
        reg = load_registry(reg_path)
        request = {"wasi_module_hash": mh,
                   "max_cpu_ms_allowed": int(cpu) if cpu is not None else 5000,
                   "request_id": 1, "input_payload": inp}
        res = execute_request(request, reg, seed, workdir=workdir,
                              ledger_secret=sec)
    except TamgaRelayerError as e:
        return out(False, op="run-request", reason_code=e.reason_code, reason=e.reason)
    except (ValueError, KeyError, OSError) as e:
        return out(False, op="run-request", reason_code=2, reason=f"parse-hatası: {e}")
    return out(True, op="run-request", **{k: v for k, v in res.items()},
               module=mh[:16])


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        print("\nkullanım (KATMAN-0 yüzü):")
        for k, v in USAGE.items():
            print(f"  python3 tamga_oracle_relayer.py {v}")
        return 0
    cmd, a = sys.argv[1], sys.argv[2:]
    if cmd == "verify-stamp":
        return cmd_verify_stamp(a)
    if cmd == "snapshot-digest":
        return cmd_snapshot_digest(a)
    if cmd == "registry-check":
        return cmd_registry_check(a)
    if cmd == "run-request":
        return cmd_run_request(a)
    if cmd == "daemon":
        return cmd_daemon(a)
    return out(False, op=cmd, reason_code=2,
               reason=f"bilinmeyen-komut: {cmd} (kullanım: {', '.join(USAGE)})")


if __name__ == "__main__":
    sys.exit(main())
