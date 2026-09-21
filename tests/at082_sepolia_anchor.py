#!/usr/bin/env python3
"""
AT-082 Sepolia-anchor-üreticisi — toplanan 6 receipt'den R9-3-kanonik anchor.

RFC-009 (DRAFT) R9-1..R9-5:
  R9-1  anchor_version = TAMGA_EXTERNAL_ANCHOR_V1 (sabit)
  R9-2  foreign_registry = bilinen-registry (apodix/epoch)
  R9-3  foreign_fact / foreign_digest = kanonik 0x+64-lowercase-hex
  R9-4  verified_at = RFC3339-UTC-Z (iki-alanlı-iddia: claim,day)
  R9-5  presentation_only: dış-fact'in-geçerliliği-bizim-iddiamız-DEĞİL

Anchor-kökü: 6-receipt'ın-merkle-kökü (keccak256-veya-sha256-çiftli).
Sepolia-cite: ücretsiz-RPC'den-güncel-block-height (gerçek-zincir-okuması;
anchor-YAZMA-yok — ücretsiz, gas'sız).

Çıktı: .evidence/GATEWAY-PILOT/anchor-sepolia.json
"""
import hashlib
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SEPOLIA_RPC = os.environ.get(
    "SEPOLIA_RPC", "https://ethereum-sepolia-rpc.publicnode.com")

# R9-2: RFC-009'un-bilinen-registry'si (tamga_runner._KNOWN_FOREIGN_REGISTRIES)
FOREIGN_REGISTRY = "apodix/epoch"
ANCHOR_VERSION = "TAMGA_EXTERNAL_ANCHOR_V1"          # R9-1


def _canon_0x64(hexstr: str) -> str | None:
    """R9-3: kanonik 0x+64-lowercase (tamga_runner._is_canonical_0x64 ile-aynı)."""
    if not isinstance(hexstr, str):
        return None
    v = hexstr[2:] if hexstr.startswith(("0x", "0X")) else hexstr
    if len(v) != 64 or not all(c in "0123456789abcdef" for c in v.lower()):
        return None
    return "0x" + v.lower()


def _sha64(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def collect_receipts(pilot: dict, binds_dir: Path) -> list[dict]:
    """Pilot-üretimi-receipt'lar: pilot-trafiği-checkpoint'-sonrası-dikişler.

    Her-servis-2-kayıt-yazar (payment-event + charge_receipt) — anchor-
    üretimi-charge_receipt-kanalını-alır (her-çağrı-bir-receipt: 6-servis-6).
    """
    receipts = pilot.get("receipts", [])
    if receipts:
        # Her-servis-2-kayıt-yazar: (1) payment-event, (2) charge_receipt —
        # ikincisi-iş-kanıtıdır. Anchor-üretimi-her-servisin-SON-kaydını-alır
        # (her-çağrı-bir-receipt: 6-servis-6-yaprak).
        by_svc: dict[str, dict] = {}
        for r in receipts:
            svc = r.get("service")
            if svc is None:
                continue
            if svc not in by_svc or r.get("seq", 0) > by_svc[svc].get("seq", 0):
                by_svc[svc] = r
        return sorted(by_svc.values(), key=lambda r: r.get("service", ""))
    # yedek-yol (eski-kanıt-uyumu): tüm-dikişleri-topla
    out = []
    if not binds_dir.is_dir():
        return out
    for f in sorted(binds_dir.glob("seq*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        ch = d.get("charge", {})
        sb = ch.get("settlement_bind", {})
        out.append({
            "seq": ch.get("seq"),
            "payment_id": sb.get("payment_id") or "",
            "service": (ch.get("host") or "").lstrip("/"),
            "delivery_hash": ch.get("delivery_hash", {}).get("hex", ""),
            "payer": sb.get("payer", ""),
            "bind_file": str(f),
        })
    return out


def merkle_root_sha256(leaves: list[str]) -> str:
    """Basit-ikili-merkle (boşsa-genesis-sıfır; tek-yaprak-kendisi)."""
    if not leaves:
        return "0" * 64
    layer = [bytes.fromhex(l) for l in leaves]
    while len(layer) > 1:
        if len(layer) % 2:
            layer.append(layer[-1])                 # son-yaprak-çiftleştir
        nxt = []
        for i in range(0, len(layer), 2):
            nxt.append(hashlib.sha256(layer[i] + layer[i + 1]).digest())
        layer = nxt
    return layer[0].hex()


def sepolia_block_height() -> dict:
    """Ücretsiz-Sepolia-RPC: güncel-block-height (anchor-için-zaman-damgası)."""
    try:
        req = urllib.request.Request(
            SEPOLIA_RPC,
            data=json.dumps({"jsonrpc": "2.0", "method": "eth_blockNumber",
                             "params": [], "id": 1}).encode(),
            headers={"Content-Type": "application/json",
                     "User-Agent": "Tamga-AT082/1.0"})
        with urllib.request.urlopen(req, timeout=15) as r:
            d = json.load(r)
        if "result" not in d:
            return {"ok": False, "rpc": SEPOLIA_RPC, "error": str(d)[:120]}
        return {"ok": True, "rpc": SEPOLIA_RPC,
                "block_height": int(d["result"], 16),
                "block_height_hex": d["result"]}
    except Exception as e:
        return {"ok": False, "rpc": SEPOLIA_RPC,
                "error": f"{type(e).__name__}: {e}"}


def build_anchor(receipts: list[dict], ev_dir: Path) -> dict:
    """R9-3-kanonik-anchor-üret: merkle-kökü + Sepolia-block-cite."""
    leaves = []
    for r in receipts:
        c = _canon_0x64(r.get("delivery_hash", ""))
        if c:
            leaves.append(c[2:])
    root = merkle_root_sha256(leaves)
    foreign_fact = "0x" + root
    foreign_digest = "0x" + _sha64(
        (FOREIGN_REGISTRY + "|" + foreign_fact).encode())

    now = datetime.now(timezone.utc)
    verified_at = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    day = now.strftime("%Y-%m-%d")
    sep = sepolia_block_height()

    anchor = {
        # R9-1
        "anchor_version": ANCHOR_VERSION,
        # R9-2
        "foreign_registry": FOREIGN_REGISTRY,
        # R9-3 — kanonik 0x+64-lowercase
        "foreign_fact": foreign_fact,
        "foreign_digest": foreign_digest,
        # R9-4 — iki-alanlı-iddia (claim,day); süreklilik-DEĞİL
        "verified_at": verified_at,
        "claim_day": day,
        # R9-5 — biz-iddia-etmiyoruz, sunuyoruz
        "presentation_only": True,
        "tool": "AT-082 pilot-traffic + free Sepolia RPC (read-only)",
        # anchor-içeriği
        "source": "00-gateway 6 x402-servis-pilot-receipt'ları",
        "receipt_count": len(receipts),
        "leaves": [_canon_0x64("0x" + l) for l in leaves],
        "sepolia": sep,
        "merkle_alg": "sha256-ikili-son-yaprak-çiftleştir",
    }
    # R9-3 kendi-kendini-doğrula
    assert _canon_0x64(anchor["foreign_fact"]) == anchor["foreign_fact"]
    assert _canon_0x64(anchor["foreign_digest"]) == anchor["foreign_digest"]
    assert len(anchor["foreign_fact"]) == 66 and len(anchor["foreign_digest"]) == 66

    ev_dir.mkdir(parents=True, exist_ok=True)
    (ev_dir / "anchor-sepolia.json").write_text(
        json.dumps(anchor, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return anchor


if __name__ == "__main__":
    ev = Path(sys.argv[1] if len(sys.argv) > 1 else ".evidence/GATEWAY-PILOT")
    pilot = json.loads((ev / "pilot-traffic.json").read_text(encoding="utf-8"))
    binds_dir = Path(pilot.get("binds_dir",
                               str(Path.home() / ".workspace" / "unpump-binds")))
    receipts = collect_receipts(pilot, binds_dir)
    a = build_anchor(receipts, ev)
    print(f"receipt-toplandı : {a['receipt_count']}")
    print(f"foreign_fact     : {a['foreign_fact']}")
    print(f"foreign_digest   : {a['foreign_digest']}")
    print(f"R9-3-kanonik     : 0x+64-lowercase ✓")
    print(f"Sepolia-block    : {a['sepolia'].get('block_height', 'YOK')}"
          f"{' (RPC-okuma)' if a['sepolia'].get('ok') else ' — ' + str(a['sepolia'].get('error'))}")
    print(f"kanıt            : {ev}/anchor-sepolia.json")
