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
import pathlib
import sys
import time

__all__ = [
    # KATMAN-0
    "fnv1a64", "verify_output_stamp", "parse_snapshot", "snapshot_body_digest",
    "build_fulfill_payload", "out", "TamgaRelayerError",
    # reason-code sabitleri (tamga_runner ile paylaşılan doktrin)
    "RC_OK", "RC_OUTPUT_PROOF_MISMATCH", "RC_SNAPSHOT_BAD_MAGIC",
    "RC_SNAPSHOT_HEADER", "RC_SNAPSHOT_TOO_LARGE",
]

# --- reason-code'ları (tamga_runner.py ile uyumlu, message-RED) -----------------
# 12 = agent_run_failed ailesi (stamp bozukluğu run çıktısının kanıtını bozar)
RC_OK = 0
RC_OUTPUT_PROOF_MISMATCH = 12      # TAMGA:<fnv1a64> stamp eşleşmedi
RC_SNAPSHOT_BAD_MAGIC = 1          # MAGIC b"TSG1" yok
RC_SNAPSHOT_HEADER = 2             # header JCS/şema çözülemedi
RC_SNAPSHOT_TOO_LARGE = 7          # SAFE_SNAP_MAX aşımı (trivyal-RED, kaynak-tüketimi)

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
        "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    if ledger_tip is not None:
        payload["ledger_tip"] = ledger_tip                  # mühür-3
    return jcs(payload)


# === CLI (KATMAN-0 yüzü: üretilen kanıtları bağımsız denetle) ===================

USAGE = {
    "verify-stamp": "verify-stamp <stdout-file>",
    "snapshot-digest": "snapshot-digest <snap.tsg>",
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
    return out(False, op=cmd, reason_code=2,
               reason=f"bilinmeyen-komut: {cmd} (kullanım: {', '.join(USAGE)})")


if __name__ == "__main__":
    sys.exit(main())
