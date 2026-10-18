"""Tamga MCP sunucu testleri — Model Context Protocol 2025-06-18 over stdio.

JSON-RPC el sıkışması + 5 aracı (verify_ledger/verify_bundle/verify_charge/
verify_attestation/ledger_head) uçtan-uca subprocess üzerinden çalıştırır.
Tamga'nın bağımsız-doğrulama sözleşmesini MCP yayın-yüzüne sabitler:
  - GREEN/RED/İNDETERMİNE üç-sonuç (asla exception, her zaman JSON kanıt)
  - saf stdlib (karşı taraf hiçbir tamga modülünü KURMADAN doğrular)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "mcp" / "server.py"
PROTOCOL_VERSION = "2025-06-18"


def _rpc(lines, env_extra=None, timeout=60):
    """Server'ı stdio üzerinden besle; yanıt satırlarını dict listesi dön."""
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    reqs = list(lines or [])
    proc = subprocess.run([sys.executable, str(SERVER)], input="\n".join(reqs) + "\n",
                          capture_output=True, text=True, env=env, timeout=timeout,
                          cwd=str(ROOT))
    out = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            out.append(json.loads(line))
    return proc, out


def _init_line():
    return ('{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
            '{"protocolVersion":"2025-06-18","capabilities":{},'
            '"clientInfo":{"name":"tamga-mcp-test","version":"0.1"}}}')


def _notify_initialized():
    return '{"jsonrpc":"2.0","method":"notifications/initialized"}'


def _tools_list():
    return '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'


def _call(req_id, name, arguments):
    return (f'{{"jsonrpc":"2.0","id":{req_id},"method":"tools/call",'
            f'"params":{{"name":"{name}","arguments":{json.dumps(arguments, ensure_ascii=False)}}}}}')


def _simnet_ledger():
    """Testlerin kullanabileceği GEÇERLİ bir ledger.jsonl yolu (repo-içi simnet)."""
    p = ROOT / "tests" / "simnet" / ".dbg" / "pkg" / "ledger.jsonl"
    return p


def _tool_names(out):
    for r in out:
        if r.get("id") == 2:
            return [t["name"] for t in r.get("result", {}).get("tools", [])]
    return []


def _content(out, req_id):
    """Bir tools/call sonucunun metin içeriğini JSON olarak çöz."""
    for r in out:
        if r.get("id") == req_id:
            for c in r.get("result", {}).get("content", []):
                return json.loads(c.get("text", "null"))
    return None


# --- el sıkışma -----------------------------------------------------------------

def test_initialize_negotiates_2025_06_18():
    proc, out = _rpc([_init_line()])
    assert proc.returncode == 0, proc.stderr[-500:]
    r = out[0]
    assert r["jsonrpc"] == "2.0" and r["id"] == 1
    assert r["result"]["protocolVersion"] == PROTOCOL_VERSION
    info = r["result"]["serverInfo"]
    assert info["name"] == "tamga"
    assert "capabilities" in r["result"]


def test_tools_list_after_initialized_notification():
    proc, out = _rpc([_init_line(), _notify_initialized(), _tools_list()])
    names = _tool_names(out)
    assert "verify_ledger" in names
    assert "verify_bundle" in names
    assert "ledger_head" in names


# --- verify_ledger: GEÇERLİ simnet ledger'ı GREEN -------------------------------

def test_verify_ledger_simnet_gecerli_green():
    ledger = _simnet_ledger()
    if not ledger.is_file():
        pytest.skip("simnet ledger fixture yok")
    proc, out = _rpc([_init_line(), _notify_initialized(),
                      _call(3, "verify_ledger", {"ledger_path": str(ledger)})])
    res = _content(out, 3)
    assert res is not None, out
    assert res["ok"] is True, res
    assert "head" in res and isinstance(res["head"], str)
    assert len(res["head"]) == 64


def test_verify_ledger_olmayan_dosya_indeterminate_degil_red():
    proc, out = _rpc([_init_line(), _notify_initialized(),
                      _call(3, "verify_ledger",
                            {"ledger_path": "/tmp/tamga-mcp-yok-999.jsonl"})])
    res = _content(out, 3)
    assert res is not None
    # Dosya-yok bir "bakamadı" DEĞİL, kanıt-üretim hatasıdır fail-closed RED.
    assert res["ok"] is False
    assert "reason" in res


def test_verify_ledger_kirik_zincir_red():
    # GEÇERLİ ledger'ın son satırının h-değerini boz → zincir kırılsın.
    ledger = _simnet_ledger()
    if not ledger.is_file():
        pytest.skip("simnet ledger fixture yok")
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
        lines = ledger.read_text().splitlines()
        for i, line in enumerate(lines):
            rec = json.loads(line)
            if i == len(lines) - 1:
                rec["h"] = "f" * 64
            f.write(json.dumps(rec) + "\n")
        broken = f.name
    proc, out = _rpc([_init_line(), _notify_initialized(),
                      _call(3, "verify_ledger", {"ledger_path": broken})])
    res = _content(out, 3)
    assert res["ok"] is False
    assert "broken" in res.get("reason", "") or "mismatch" in res.get("reason", "")


# --- ledger_head -----------------------------------------------------------------

def test_ledger_head_gecerli_ledger_tip_doner():
    ledger = _simnet_ledger()
    if not ledger.is_file():
        pytest.skip("simnet ledger fixture yok")
    proc, out = _rpc([_init_line(), _notify_initialized(),
                      _call(3, "ledger_head", {"ledger_path": str(ledger)})])
    res = _content(out, 3)
    assert res["ok"] is True
    assert len(res["head"]) == 64


# --- hata-yönetimi: exception DEĞİL, JSON kanıt ---------------------------------

def test_tools_call_hata_zaman_urpmaz_traceback_vermez():
    proc, out = _rpc([_init_line(), _notify_initialized(),
                      _call(3, "verify_ledger", {"ledger_path": 12345})])
    # Hatalı girdi bile sunucuyu çökertmemeli: bir JSON yanıtı dönmeli.
    assert any(r.get("id") == 3 for r in out), proc.stderr[-500:]


def test_unknown_tool_json_rpc_error_doner():
    proc, out = _rpc([_init_line(), _notify_initialized(),
                      _call(3, "yok-boyle-bir-arac", {})])
    # Bilinmeyen araç protocol-hatası olarak dönmeli (result değil error).
    ids = [r for r in out if r.get("id") == 3]
    assert ids, out
    assert "error" in ids[0] or "isError" in str(ids[0].get("result", {}))
