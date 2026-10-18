#!/usr/bin/env python3
"""tamga MCP sunucusu — Model Context Protocol 2025-06-18 over stdio.

Tamga'nın BAĞIMSIZ-DOĞRULAMA çekirdeğini AI ajanlarına MCP araçları olarak sunar.

Tasarım-ilkesi (tamga_verifier/tamga_verify_mini ile aynı sözleşme):
  • SAF STDLIB — hiçbir pip bağımliliği; karşı taraf tamga'yı KURMADAN
    doğrulayabildiği gibi, bu sunucu da tamga modüllerini SUBPROCESS-LEVEL'da
    çağırır, import etmez — sürüm-çakışması/kırılganlık yok.
  • ÜÇ-SONUÇ — her araç GREEN/RED/İNDETERMİNE JSON kanıtı döndürür;
    ASLA exception fırlatmaz (AT-192 message-RED disiplini).
  • Subprocess-tabanlı çağrı — her doğrulama, tamga'nın KENDİ CLI'ında
    çalışır; bu sunucu yalnızca bir RPC-cephesi değildir, bir DAĞITIM
    kanalıdır: ajanlar `pip install tamga` yapmadan doğrulayabilir.

Araçlar:
  verify_ledger    ledger.jsonl zincirini baştan-sona doğrula (tamga_verify_mini)
  ledger_head      zincirin geçerli head'ini döndür (verify_ledger'ın özeti)
  verify_attestation dış delivery-attestation doğrula (tamga_attest_verify)
  verify_charge    tek charge kaydının zincir-üyeliğini doğrula (IVerifier)
  verify_bundle    relayer fulfill-paketinin tüm mühürlerini doğrula

Çalıştırma:
  python3 mcp/server.py                    # stdio JSON-RPC
  (istemci tarafı: "command": "python", "args": ["<repo>/mcp/server.py"])
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

PROTOCOL_VERSION = "2025-06-18"
SERVER_NAME = "tamga"
SERVER_VERSION = "0.1.0"
ROOT = Path(__file__).resolve().parents[1]
MAX_TIMEOUT = 120  # saniye — doğrulama ödeme-yükü altında bile sınırlı


def _e(msg: str) -> dict:
    return {"jsonrpc": "2.0", "error": {"code": -32602, "message": msg}}


def _result(req_id, result: dict) -> dict:
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def _text(payload: dict) -> dict:
    return {"content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False)}]}


def _run_cli(script: str, args: list, stdin_data: str | None = None) -> dict:
    """Tamga'nın kendi CLI'ını SUBPROCESS olarak çağır, çıkışını JSON kanıta çevir.

    Fail-closed: her hata (zaman-aşımı, exception, bozuk-çıkış) bir RED
    kanıtıdır — traceback DEĞİL, JSON döner (AT-192).
    """
    script_path = ROOT / script
    if not script_path.is_file():
        return {"ok": False, "reason": f"script-bulunamadi: {script}"}
    try:
        proc = subprocess.run(
            [sys.executable, str(script_path), *args],
            capture_output=True, text=True, timeout=MAX_TIMEOUT, cwd=str(ROOT))
    except subprocess.TimeoutExpired:
        return {"ok": False, "reason": f"zaman-asimi: {MAX_TIMEOUT}s"}
    except Exception as e:  # noqa: BLE001 — cephedeki her hata JSON kanıtı olmalı
        return {"ok": False, "reason": f"calistirma-hatasi: {e}"}
    out = (proc.stdout or "").strip()
    # tamga CLI'ları tek-satır JSON basar (stderr insan-satırı).
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            rec = json.loads(line)
            if isinstance(rec, dict):
                rec.setdefault("ok", proc.returncode == 0)
                rec.setdefault("rc", proc.returncode)
                return rec
        except json.JSONDecodeError:
            continue
    # JSON-satırı yok: RED (fail-closed — "bakamadı" değil, kanıt üretilemedi).
    return {
        "ok": False,
        "rc": proc.returncode,
        "reason": "cekis-json-uretmedi" + (f": {out[:120]}" if out else ""),
        "stderr": (proc.stderr or "").strip()[:300],
    }


# --- araç implementasyonları ----------------------------------------------------

def _tool_verify_ledger(args: dict) -> dict:
    p = args.get("ledger_path")
    if not isinstance(p, str) or not p:
        return {"ok": False, "reason": "ledger_path-zorunlu (string)"}
    return _run_cli("tamga_verify_mini.py", [p])


def _tool_ledger_head(args: dict) -> dict:
    r = _tool_verify_ledger(args)
    if r.get("ok"):
        head = r.get("head") or r.get("tip") or ""
        return {"ok": True, "head": head, "lines": r.get("lines")}
    return r


def _tool_verify_attestation(args: dict) -> dict:
    claim = args.get("claim")
    if isinstance(claim, dict):
        # claim nesnesi olarak gelmişse geçici dosyaya yaz (CLI dosya-bekler).
        import tempfile
        try:
            with tempfile.NamedTemporaryFile("w", suffix=".json",
                                             delete=False, dir="/tmp") as f:
                json.dump(claim, f, ensure_ascii=False)
                path = f.name
        except Exception as e:  # noqa: BLE001
            return {"ok": False, "reason": f"claim-yazilamadi: {e}"}
        extra = ["--registry", args["registry"]] if isinstance(
            args.get("registry"), str) else []
        return _run_cli("tamga_attest_verify.py", [path, *extra])
    if isinstance(claim, str):
        extra = ["--registry", args["registry"]] if isinstance(
            args.get("registry"), str) else []
        return _run_cli("tamga_attest_verify.py", [claim, *extra])
    return {"ok": False, "reason": "claim-zorunlu (JSON-nesne veya dosya-yolu)"}


def _tool_verify_charge(args: dict) -> dict:
    rec = args.get("record")
    prev = args.get("prev_hex")
    h = args.get("expected_hex")
    if not isinstance(rec, dict):
        return {"ok": False, "reason": "record-zorunlu (JSON-nesne)"}
    if not isinstance(prev, str) or not isinstance(h, str):
        return {"ok": False, "reason": "prev_hex-ve-expected_hex-zorunlu (64-hex)"}
    # IVerifier.verify_charge ile aynı formül (bağımsız kopya — MCP cephesi
    # tamga_canon'u import etmeden parite ile doğrular).
    # MCP cepheleri tek-gerçek yerine PARİTE ile doğrular).
    import hashlib
    try:
        no_h = {k: v for k, v in rec.items() if k != "h"}
        got = hashlib.sha256(
            (rec.get("prev", "") + _jcs(no_h)).encode("utf-8")).hexdigest()
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "reason": f"hash-hatasi: {e}"}
    if rec.get("prev") != prev:
        return {"ok": False, "reason": "charge-prev-uyumsuz"}
    if got != h:
        return {"ok": False, "reason": f"charge-uyelik-mismatch: {got[:12]}… != {h[:12]}…"}
    return {"ok": True, "h": got}


def _jcs(d) -> str:
    """RFC 8785 canonical-JSON (tamga_canon ile bayt-paritesi — kasıtlı kopya).

    MCP cephesi bağımsızdır: tamga_canon'u import ETMEZ, kendi kopyasını
    taşır — böylece sunucu sürüm-kayması charge doğrulamasını sessizce
    değiştiremez.
    """
    if isinstance(d, dict):
        return "{" + ",".join(
            json.dumps(k, ensure_ascii=False) + ":" + _jcs(d[k])
            for k in sorted(d)) + "}"
    if isinstance(d, list):
        return "[" + ",".join(_jcs(x) for x in d) + "]"
    if isinstance(d, bool):
        return "true" if d else "false"
    if d is None:
        return "null"
    if isinstance(d, (int, float)):
        return json.dumps(d)
    return json.dumps(d, ensure_ascii=False)


def _tool_verify_bundle(args: dict) -> dict:
    p = args.get("bundle_path")
    if not isinstance(p, str) or not p:
        return {"ok": False, "reason": "bundle_path-zorunlu (string)"}
    return _run_cli("tamga_verifier.py", ["verify-bundle", p])


TOOLS = {
    "verify_ledger": {
        "handler": _tool_verify_ledger,
        "description": (
            "Bir tamga ledger.jsonl dosyasının kanıt-zincirini baştan-sona "
            "bağımsız doğrular (prev-link + JCS canonical-hash + seq). "
            "Karşı taraf tamga'yı kurmamış olsa bile doğrular. "
            "Dönüş: {ok, head, lines, reason?} —ok=true GREEN, ok=false RED."),
        "schema": {
            "type": "object",
            "properties": {
                "ledger_path": {
                    "type": "string",
                    "description": "ledger.jsonl dosya-yolu (mutlak önerilir)",
                }},
            "required": ["ledger_path"],
        }},
    "ledger_head": {
        "handler": _tool_ledger_head,
        "description": (
            "Geçerli bir ledger'ın zincir-head'ini (son h, 64-hex) döndürür. "
            "Sadece tamga'da kullanım —başka-istemin-çapası olarak. "
            "Dönüş: {ok, head, lines?}"),
        "schema": {
            "type": "object",
            "properties": {
                "ledger_path": {"type": "string"},
            },
            "required": ["ledger_path"],
        }},
    "verify_attestation": {
        "handler": _tool_verify_attestation,
        "description": (
            "DIŞ delivery-attestation (CAPACITY_ATTEST_V1) doğrular — "
            "üç-sonuç: 0 GREEN, 1 RED, 2 İNDETERMİNE (bilinmeyen-registry, "
            "sonuç-esirgenir). EIP-191 personal_sign + sha256(canonical-JSON). "
            "Dönüş: {verdict: 'green'|'red'|'indeterminate', reason, ...}"),
        "schema": {
            "type": "object",
            "properties": {
                "claim": {
                    "type": ["object", "string"],
                    "description": "Claim JSON-nesnesi veya dosya-yolu",
                },
                "registry": {
                    "type": "string",
                    "description": "Köken-etiket registry'si (opsiyonel)",
                }},
            "required": ["claim"],
        }},
    "verify_charge": {
        "handler": _tool_verify_charge,
        "description": (
            "Tek charge kaydının zincir-üyeliğini doğrular: "
            "h == sha256(prev + jcs(record-h-siz)). MCP cephesi "
            "tamga_canon'u import ETMEDEN bağımsız-kopya JCS ile doğrular "
            "(bayt-paritesi tools/vauban_conformance ile makine-denetlenir). "
            "Dönüş: {ok, h?, reason?}"),
        "schema": {
            "type": "object",
            "properties": {
                "record": {"type": "object", "description": "charge JSON-kaydı"},
                "prev_hex": {"type": "string", "description": "önceki-blok hash'i (64-hex)"},
                "expected_hex": {"type": "string", "description": "beklenen h (64-hex)"},
            },
            "required": ["record", "prev_hex", "expected_hex"],
        }},
    "verify_bundle": {
        "handler": _tool_verify_bundle,
        "description": (
            "Relayer fulfill-paketinin TÜM mühürlerini tek-seferde doğrular "
            "(stamp fnv1a64 + snapshot TSG1 + payload JCS + charge zincir + "
            "delivery keccak-256). Dönüş: {ok, checks, verified, reason?}"),
        "schema": {
            "type": "object",
            "properties": {
                "bundle_path": {"type": "string", "description": "bundle.json yolu"},
            },
            "required": ["bundle_path"],
        }},
}


def _tools_list_result() -> dict:
    return {"tools": [
        {"name": name,
         "description": spec["description"],
         "inputSchema": spec["schema"]}
        for name, spec in TOOLS.items()]}


def _handle_call(req_id: int | str | None, params: dict) -> dict | None:
    name = params.get("name")
    args = params.get("arguments") or {}
    spec = TOOLS.get(name)
    if spec is None:
        return {"jsonrpc": "2.0", "id": req_id,
                "error": {"code": -32601,
                          "message": f"bilinmeyen-arac: {name}"}}
    try:
        payload = spec["handler"](args)
    except Exception as e:  # noqa: BLE001 — AT-192: hiçbir yol exception'a düşmez
        payload = {"ok": False, "reason": f"arac-ic-hata: {type(e).__name__}: {e}"}
    return _result(req_id, _text(payload))


def main() -> int:
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            req = json.loads(raw)
        except json.JSONDecodeError:
            sys.stdout.write(json.dumps(_e("gecersiz-json")) + "\n")
            sys.stdout.flush()
            continue
        if not isinstance(req, dict):
            sys.stdout.write(json.dumps(_e("istek-bir-nesne-degil")) + "\n")
            sys.stdout.flush()
            continue
        method = req.get("method")
        req_id = req.get("id")
        if method == "initialize":
            sys.stdout.write(json.dumps(_result(req_id, {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {
                    "name": SERVER_NAME,
                    "version": SERVER_VERSION,
                    "instructions": (
                        "Tamga bağımsız-doğrulama sunucusu. "
                        "verify_ledger → kanıt-zinciri; ledger_head → zincir-ucu; "
                        "verify_attestation → dış-attest üç-sonuç; "
                        "verify_charge → tek-üye; verify_bundle → tüm-mühürler. "
                        "Her araç JSON kanıtı döner, asla exception fırlatmaz."),
                }})) + "\n")
        elif method == "notifications/initialized":
            continue  # bildirim — yanıt yok
        elif method == "tools/list":
            sys.stdout.write(json.dumps(_result(req_id, _tools_list_result())) + "\n")
        elif method == "tools/call":
            resp = _handle_call(req_id, req.get("params") or {})
            if resp is not None:
                sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
        elif method == "ping":
            sys.stdout.write(json.dumps(_result(req_id, {})) + "\n")
        elif req_id is not None:
            sys.stdout.write(json.dumps({
                "jsonrpc": "2.0", "id": req_id,
                "error": {"code": -32601, "message": f"bilinmeyen-method: {method}"}
            }) + "\n")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
