#!/usr/bin/env python3
"""tamga_verifier.py — IVerifier arayüzü: relayer kanıtlarını BAĞIMSIZ doğrular.

Amaç: KARŞI-TARAF (x402 node, Solidity/JS implementörü, denetçi)
tamga_oracle_relayer.py'yi KURMADAN bir fulfill kanıtını baştan sona doğrulasın.

Bağımsızlık ilkesi (AT-075 / tamga_verify_mini ile aynı disiplin):
  • SAF STDLIB — hashlib + json + base64 + struct. PyNaCl DAHİL hiçbir
    pip bağımlılığı yoktur; tamga_oracle_relayer import EDİLMEZ.
  • JCS (RFC 8785) burada KASITLI olarak kopyalanır — tek-gerçek yerine
    bağımsız-implementasyon paritesi (vauban_conformance machine-check eder).
  • Her hata bir result-dict'tir (message-RED, AT-192): {"ok": False, "reason": …}.
    ASLA exception fırlatmaz — denetçiye traceback DEĞİL, JSON kanıtı döner.

Doğruladığı kanıt ailesi (relayer'ın TAMGA_FULFILL/1 çıktısı):
  mühür-2  fnv1a64 stamp        — agent stdout'unun son satırı "TAMGA:<hex16>"
  mühür-1  SHA-256(ct)          — tamga-snapshot/1 şifreli GÖVDE digest'i
  payload  JCS byte-paritesi    — yeniden serileştir == orijinal baytlar
  charge   zincir-üyeliği       — h == sha256(prev + jcs(charge, h-siz))
  delivery keccak-256 legacy    — outputData'nın durable-evidence digest'i
  input    SHA-256              — request girdisinin bağımsız parmakizi

Kullanım:
  python3 tamga_verifier.py verify-bundle <bundle.json>
  python3 tamga_verifier.py verify-tx <tx-hash> <rpc-url>   # canlı-zincir (okuma-yalnız)
  python3 tamga_verifier.py stamp <stdout-file> <hex16>
  python3 tamga_verifier.py snapshot <snap.tsg> <digest-hex>
  python3 tamga_verifier.py payload <payload.json>
  python3 tamga_verifier.py charge <charge.jsonl-line> <prev-hex> <h-hex>
  python3 tamga_verifier.py delivery <payload-file> <keccak-hex>
  python3 tamga_verifier.py input <input-file> <sha256-hex>

Çıkış (her zaman): tek JSON satırı
  {"ok": true,  "checks": n, "verified": [...]}
  {"ok": false, "checks": n, "reason": "...", "verified": [...]}
rc: 0-doğrulandı · 1-kırık-kanıt · 2-kullanım
"""
import base64
import hashlib
import json
import sys

# --- sabitler (relayer ile AYNI değerler; bağımsız-kopya kasıtlı) --------------
SNAPSHOT_MAGIC = b"TSG1"
SAFE_SNAP_MAX = 64 * (1 << 20)          # 64 MiB — kaynak-tüketimi-RED (trivial bomb)
FNV_OFFSET = 0xcbf29ce484222325
FNV_PRIME = 0x100000001b3
GENESIS = "0" * 64

# --- RFC 8785 canonical serialization (standalone copy; tamga_verify_mini ile ---
# --- bayt-bayt aynı; vauban_conformance --selftest machine-check eder) ---------
_ESCAPE = {'"': '\\"', "\\": "\\\\", "\b": "\\b", "\f": "\\f",
           "\n": "\\n", "\r": "\\r", "\t": "\\t"}


def _es_number(x):
    if x != x or x in (float("inf"), float("-inf")):
        raise ValueError("ijson_number_not_finite")
    if x == 0:
        return "0"
    neg = x < 0
    digits, exp = __import__("decimal").Decimal(repr(abs(x))).as_tuple()[-2:]
    while len(digits) > 1 and digits[-1] == 0:
        digits, exp = digits[:-1], exp + 1
    k = len(digits); n = exp + k
    s = "".join(map(str, digits))
    if k <= n <= 21:
        body = s + "0" * (n - k)
    elif 0 < n <= 21:
        body = s[:n] + "." + s[n:]
    elif -6 < n <= 0:
        body = "0." + "0" * (-n) + s
    else:
        e = n - 1
        mant = s if k == 1 else s[0] + "." + s[1:]
        body = mant + "e" + ("+" if e >= 0 else "-") + str(abs(e))
    return ("-" if neg else "") + body


def _enc_string(s_):
    out = ['"']
    for ch in s_:
        if ch in _ESCAPE:
            out.append(_ESCAPE[ch])
        elif ord(ch) < 0x20:
            out.append(f"\\u{ord(ch):04x}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def _encode(o, out):
    if o is None: out.append("null")
    elif isinstance(o, bool): out.append("true" if o else "false")
    elif isinstance(o, int):
        if not (-(2 ** 53) <= o <= 2 ** 53):
            raise ValueError("ijson_number_out_of_range")
        out.append(str(o))
    elif isinstance(o, float): out.append(_es_number(o))
    elif isinstance(o, str): out.append(_enc_string(o))
    elif isinstance(o, dict):
        out.append("{"); first = True
        for key in sorted(o, key=lambda k: k.encode("utf-16-be")):   # §3.2.3
            if not first: out.append(",")
            first = False
            out.append(_enc_string(str(key))); out.append(":"); _encode(o[key], out)
        out.append("}")
    elif isinstance(o, (list, tuple)):
        out.append("["); first = True
        for item in o:
            if not first: out.append(",")
            first = False
            _encode(item, out)
        out.append("]")
    else:
        raise TypeError(f"unsupported canonical value: {type(o).__name__}")


def jcs(obj) -> bytes:
    out = []; _encode(obj, out)
    return "".join(out).encode("utf-8")


def _keccak256(b: bytes) -> bytes:
    """Legacy-padding keccak-256 (Ethereum/x402 digest). hashlib.sha3_256 UYUŞMAZ
    (FIPS 0x06 vs legacy 0x01). tamga_keccak saf-Python (zero-dep) — relayer ve
    wheel ile birlikte gider; yokluğunda çağıran message-RED döner (dürüst-düşüş)."""
    from tamga_keccak import keccak256
    return keccak256(b)


# === IVerifier =================================================================

class IVerifier:
    """Bağımsız kanıt-doğrulayıcı (saf-stdlib; relayer kurulumu GEREKMEZ).

    Arayüz kontratı — başka bir dilde (Solidity/JS/Go) yeniden uygularken aynı
    kararlar zorunludur:
      verify_stamp(raw, hex16)       fnv1a64(raw[:stamp-satırı-öncesi]) == int(hex16,16)
      verify_snapshot(bytes, digest) TSG1 parse → SHA-256(ct) == digest
      verify_payload(bytes)          jcs(json.loads(bytes)) == bytes (byte-parite)
      verify_charge(rec, prev, h)    sha256(prev + jcs(rec-siz-h)) == h
      verify_delivery(bytes, hex)    keccak256(bytes, legacy-pad) == hex
      verify_input(data, hex)        sha256(data) == hex
    """

    # --- mühür-2: fnv1a64 stamp -------------------------------------------------
    @staticmethod
    def verify_stamp(raw: bytes, expected_hex16: str) -> dict:
        parts = raw.rsplit(b"TAMGA:", 1)
        if len(parts) != 2:
            return {"ok": False, "reason": "stamp-yok: 'TAMGA:<hex16>' satırı bulunamadı"}
        head, tag = parts
        tag = tag.rstrip(b"\n")
        if len(tag) != 16 or any(c not in b"0123456789abcdef" for c in tag):
            return {"ok": False, "reason": "stamp-format: 16 küçük-hex değil"}
        got = fnv1a64(head)
        if got != int(tag, 16):
            return {"ok": False,
                    "reason": f"stamp-mismatch: fnv1a64(head)={got:016x} != stamp"}
        if expected_hex16 is not None and tag.decode("ascii") != expected_hex16:
            return {"ok": False, "reason": "stamp-expected-mismatch"}
        return {"ok": True, "stamp": tag.decode("ascii")}

    # --- mühür-1: tamga-snapshot/1 → SHA-256(ct) --------------------------------
    @staticmethod
    def verify_snapshot(data: bytes, expected_digest_hex: str) -> dict:
        if len(data) < 8 or data[:4] != SNAPSHOT_MAGIC:
            return {"ok": False, "reason": "snapshot-magic: b'TSG1' yok"}
        if len(data) > SAFE_SNAP_MAX:
            return {"ok": False, "reason": f"snapshot-too-large: {len(data)} > {SAFE_SNAP_MAX}"}
        hlen = int.from_bytes(data[4:8], "big")
        if hlen < 0 or 8 + hlen > len(data):
            return {"ok": False, "reason": "snapshot-header-uzunluğu geçersiz"}
        try:
            json.loads(data[8:8 + hlen])                 # header JCS doğrula
        except Exception as e:
            return {"ok": False, "reason": f"snapshot-header-JSON-değil: {e}"}
        ct = data[8 + hlen:]
        got = hashlib.sha256(ct).hexdigest()
        if got != expected_digest_hex:
            return {"ok": False, "reason": f"digest-mismatch: {got[:12]}… != {expected_digest_hex[:12]}…"}
        return {"ok": True, "digest": got, "ct_len": len(ct)}

    # --- payload: JCS byte-paritesi + zorunlu-alanlar ---------------------------
    PAYLOAD_REQUIRED = ("kind", "request_id", "wasi_module_hash",
                        "encrypted_snapshot_digest", "stdout_sha256", "ledger_tip")

    @staticmethod
    def verify_payload(payload_bytes: bytes) -> dict:
        try:
            obj = json.loads(payload_bytes)
        except Exception as e:
            return {"ok": False, "reason": f"payload-JSON-değil: {e}"}
        if obj.get("kind") != "TAMGA_FULFILL/1":
            return {"ok": False, "reason": f"payload-kind: {obj.get('kind')!r} != 'TAMGA_FULFILL/1'"}
        missing = [k for k in IVerifier.PAYLOAD_REQUIRED if obj.get(k) is None]
        if missing:
            return {"ok": False, "reason": f"payload-eksik-alan: {missing}"}
        try:
            reencoded = jcs(obj)
        except (ValueError, TypeError) as e:
            # AT-192 sözleşmesi: hata message-RED'dir, ASLA exception değil.
            # I-JSON dışı tam sayı (|n| > 2^53, RFC 7493) dahil — jcs reddeder,
            # biz bunu zarif bir red-dict'ine çeviririz (denetçi traceback görmez).
            return {"ok": False, "reason":
                    f"payload-jcs-geçersiz-değer: {e}"}
        if reencoded != payload_bytes:
            return {"ok": False, "reason":
                    "payload-jcs-parite: yeniden-serileştir orijinalden-farklı "
                    f"(bağımsız-JCS bayt-uyuşmazlığı — {len(reencoded)} vs {len(payload_bytes)})"}
        return {"ok": True, "payload": obj}

    # --- charge: zincir-üyeliği (receiptHash; verify_pairing_fixture #2 ile aynı)
    @staticmethod
    def verify_charge(rec: dict, prev_h: str, expected_h: str) -> dict:
        if rec.get("prev") != prev_h:
            return {"ok": False, "reason": "charge-prev-uyumsuz"}
        no_h = {k: v for k, v in rec.items() if k != "h"}
        got = hashlib.sha256((rec.get("prev", "") + jcs(no_h).decode("utf-8")
                              ).encode("utf-8")).hexdigest()
        if got != expected_h:
            return {"ok": False, "reason": f"charge-üyelik-mismatch: {got[:12]}… != {expected_h[:12]}…"}
        return {"ok": True, "h": got}

    # --- delivery: keccak-256 legacy over outputData ----------------------------
    @staticmethod
    def verify_delivery(payload_bytes: bytes, expected_hex: str) -> dict:
        try:
            got = _keccak256(payload_bytes).hex()
        except Exception as e:
            return {"ok": False, "reason": f"keccak-hesaplanamadı: {e}"}
        if got != expected_hex:
            return {"ok": False, "reason": f"delivery-mismatch: {got[:12]}… != {expected_hex[:12]}…"}
        return {"ok": True, "digest": got}

    # --- input: bağımsız parmakiz ----------------------------------------------
    @staticmethod
    def verify_input(data: bytes, expected_hex: str) -> dict:
        got = hashlib.sha256(data).hexdigest()
        if got != expected_hex:
            return {"ok": False, "reason": f"input-mismatch: {got[:12]}… != {expected_hex[:12]}…"}
        return {"ok": True, "sha256": got}

    # --- üst-seviye: relayer'ın tam kanıt-paketini tek-seferde doğrula ----------
    # fulfillExecution(uint256,bytes32,bytes,bytes) — keccak-256 legacy-padding
    # (tamga_keccak ile-hesaplandı; sha3_256 DEĞİL — AT-201 3-kaynak-paritesi)
    FULFILL_SELECTOR = bytes.fromhex("e266d3c7")

    @staticmethod
    def verify_tx(tx_hash: str, rpc_url: str) -> dict:
        """Zincirdeki bir fulfillExecution tx'inin olgularını doğrular (OKUMA-YALNIZ).

        Gas-harcamaz: tx'i RPC'den-çeker, calldata'yı ABI-decode-eder ve tx-in-
        olgularının-BİRBİRİYLE-TUTARLI olduğunu-kanıtlar:
          selector    fulfillExecution(uint256,bytes32,bytes,bytes) == 0xe266d3c7
          request_id  pozitif-tamsayı
          payload     jcs(json.loads(payload)) == payload-baytları (byte-parite)
          digest      tx-argümanı == payload-içindeki-snapshot-digest (uyum)

        Off-chain mühürler (stdout/snapshot/charge/delivery/input) tx-inde-YOK —
        onlar için verify-bundle; bu-yol ZİNCİR-FACT-tutarlılığını-doğrular
        (tx'i-imzalayan-kişi-digest'i-payload-ile-tutarlı-göndermiş-olmalıdır).
        web3/eth-abi zorunlu (KATMAN-2); IVerifier'ın-stdlib-çekirdeği
        verify-bundle-yoluyla-korunur — bu-metot web3-yoksa message-RED-döner.
        """
        verified: list = []
        try:
            from web3 import Web3
            from eth_abi import decode as abi_decode
        except ImportError:
            return {"ok": False, "checks": 0, "reason":
                    "web3-yok: KATMAN-2-bağımlılık (pip install .[relayer])"}
        try:
            w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={"timeout": 30}))
            if not w3.is_connected():
                return {"ok": False, "checks": 0, "reason": f"rpc-unreachable: {rpc_url}"}
            raw = w3.eth.get_transaction(tx_hash)["input"]
            raw = bytes(raw) if isinstance(raw, (bytes, bytearray)) else bytes.fromhex(
                raw[2:] if raw.startswith("0x") else raw)
            if raw[:4] != IVerifier.FULFILL_SELECTOR:
                return {"ok": False, "checks": 0, "reason":
                        f"selector-değil: {raw[:4].hex()} (fulfillExecution-beklenir)"}
            verified.append("selector")
            rid, digest, output_data, _proof = abi_decode(
                ["uint256", "bytes32", "bytes", "bytes"], raw[4:])
            rid = int(rid) if not isinstance(rid, (bytes, bytearray)) else int.from_bytes(rid, "big")
            if rid <= 0:
                return {"ok": False, "checks": 1, "verified": verified,
                        "reason": f"request_id-geçersiz: {rid}"}
            verified.append("request_id")
            payload = bytes(output_data)
            pr = IVerifier.verify_payload(payload)
            if not pr["ok"]:
                return {"ok": False, "checks": 2, "verified": verified,
                        "reason": "payload: " + pr["reason"]}
            verified.append("payload")
            want = (digest.hex() if isinstance(digest, (bytes, bytearray)) else str(digest)).lower()
            got = str(json.loads(payload.decode()).get("encrypted_snapshot_digest") or "").lower()
            if not got or got != want:
                return {"ok": False, "checks": 3, "verified": verified,
                        "reason": f"digest-uyumsuz: tx={want[:16]}… payload={got[:16]}…"}
            verified.append("digest-uyumu")
        except Exception as e:
            return {"ok": False, "checks": len(verified), "verified": verified,
                    "reason": f"tx-okuma-hatası: {type(e).__name__}: {str(e)[:120]}"}
        return {"ok": True, "checks": 4, "verified": verified,
                "note": "zincir-fact-tutarlılığı; off-chain mühürler için verify-bundle"}

    @staticmethod
    def verify_bundle(bundle: dict) -> dict:
        """bundle: {stdout_b64, snapshot_b64, payload (JCS text), charge, prev_h,
        delivery_hash, input_b64?} — relayer run-request çıktısından üretilir."""
        verified = []
        # payload EN ÖNCE: parite + parse — diğer check'ler onun alanlarını kullanır
        pv = IVerifier.verify_payload(bundle["payload"].encode("utf-8"))
        verified.append("payload")
        if not pv["ok"]:
            return {"ok": False, "checks": 1, "verified": verified,
                    "reason": f"payload: {pv['reason']}"}
        po = pv["payload"]

        checks = [("stamp", lambda: IVerifier.verify_stamp(
                       base64.b64decode(bundle["stdout_b64"]), None)),
                  ("snapshot", lambda: IVerifier.verify_snapshot(
                       base64.b64decode(bundle["snapshot_b64"]),
                       po["encrypted_snapshot_digest"])),
                  ("charge", lambda: IVerifier.verify_charge(
                       bundle["charge"], bundle.get("prev_h", GENESIS),
                       bundle["charge"]["h"])),
                  ("delivery", lambda: IVerifier.verify_delivery(
                       bundle["payload"].encode("utf-8"), bundle["delivery_hash"]))]
        if bundle.get("input_b64"):      # opsiyonel: run-request bazen input'suz
            checks.append(("input", lambda: IVerifier.verify_input(
                base64.b64decode(bundle["input_b64"]), po["input_sha256"])))
        for name, fn in checks:
            r = fn()
            verified.append(name)
            if not r["ok"]:
                return {"ok": False, "checks": len(verified), "verified": verified,
                        "reason": f"{name}: {r['reason']}"}
        return {"ok": True, "checks": len(verified), "verified": verified}


def fnv1a64(b: bytes) -> int:
    """FNV-1a 64-bit — relayer:122, tamga_runner.py:30, agent Rust ile BİREBİR."""
    h = FNV_OFFSET
    for x in b:
        h ^= x
        h = (h * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return h


# --- CLI -----------------------------------------------------------------------
USAGE = {"verify-bundle": "verify-bundle <bundle.json>",
         "stamp": "stamp <stdout-file> <hex16>",
         "snapshot": "snapshot <snap.tsg> <digest-hex>",
         "payload": "payload <payload.json>",
         "charge": "charge <charge.jsonl-line> <prev-hex> <h-hex>",
         "delivery": "delivery <payload-file> <keccak-hex>",
         "input": "input <input-file> <sha256-hex>"}


def _ok(d):
    print(json.dumps(d, ensure_ascii=False))
    return 0 if d.get("ok") else 1


def main(argv):
    if len(argv) < 2:
        print(__doc__); return 2
    cmd, a = argv[0], argv[1:]
    try:
        if cmd == "verify-bundle":
            b = json.loads(open(a[0], encoding="utf-8").read())
            return _ok(IVerifier.verify_bundle(b))
        if cmd == "stamp":
            raw = open(a[0], "rb").read()
            return _ok(IVerifier.verify_stamp(raw, a[1] if len(a) > 1 else None))
        if cmd == "snapshot":
            return _ok(IVerifier.verify_snapshot(open(a[0], "rb").read(), a[1]))
        if cmd == "payload":
            return _ok(IVerifier.verify_payload(open(a[0], "rb").read()))
        if cmd == "verify-tx":
            return _ok(IVerifier.verify_tx(a[0], a[1]))
        if cmd == "charge":
            rec = json.loads(a[0])
            return _ok(IVerifier.verify_charge(rec, a[1], a[2]))
        if cmd == "delivery":
            return _ok(IVerifier.verify_delivery(open(a[0], "rb").read(), a[1]))
        if cmd == "input":
            return _ok(IVerifier.verify_input(open(a[0], "rb").read(), a[1]))
    except FileNotFoundError as e:
        print(json.dumps({"ok": False, "reason": f"dosya-yok: {e.filename}"}))
        return 1
    except (KeyError, IndexError, ValueError) as e:
        print(json.dumps({"ok": False, "reason": f"kullanim: {USAGE.get(cmd, cmd)} ({e})"}))
        return 2
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
