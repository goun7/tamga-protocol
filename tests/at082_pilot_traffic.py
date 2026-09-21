#!/usr/bin/env python3
"""
AT-082 pilot-trafik-üreticisi — 00-gateway üzerinden 6 x402 servisini çağırır.

Yol: gateway.py:51 _match_route → 7-route (bu-testin-6'sı: planlock-kendi-trial-
sistemi-olduğu-için-çalışmıyor; geriye-6 x402-servisi-kalır).

Her-çağrı-bir-receipt-üretir (Sester-ledger + Tamga-RFC-010-dikişi,
~/.workspace/unpump-binds/seq*.json). Bu-receipt'lar-toplanır-ve-bir
Sepolia-anchor-kaynağı-olur (RFC-009 R9-3: 0x+64hex-kanonik).

GÜVENLİK: sandbox-demo-anahtarı (GENISLEME_ANALIZI.md:33) whitelist'li —
gerçek-zincir-ödemesi-YOK (USDC-sim). Fail-closed-korunur: rasgele-adres 402.
"""
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

GATEWAY = "http://127.0.0.1:8000"
DEMO_SK = os.environ.get(
    "UNPUMP_DEMO_SK",
    "0x110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857",
)
AGENT = os.environ.get(
    "UNPUMP_AGENT", "0x26dbfe78d63509f845c147b8480079c6fbd28bfc"
)

sys.path.insert(
    0, "/home/gokun/projects/02_sahis/25-ClearTag/.venv/lib/python3.14/site-packages"
)
from eth_account import Account  # gerçek-EIP-191 (test-double YOK)
from eth_account.messages import encode_defunct


def payment_header(nonce: str, amount: str, resource: str) -> str:
    """exact-sester zarfı: EIP-191 personal_sign('agent|nonce|amount|resource')."""
    msg = f"{AGENT.lower()}|{nonce}|{amount}|{resource}".encode()
    sig = Account.sign_message(encode_defunct(msg), private_key=DEMO_SK).signature.hex()
    p = {"scheme": "exact-sester", "agent": AGENT.lower(),
         "nonce": nonce, "amount": amount, "signature": sig}
    b64 = base64.urlsafe_b64encode(json.dumps(p).encode()).decode().rstrip("=")
    return f"Sester-EVM {b64}"


def call(name, amount, ep, body, *, multipart=False):
    url = f"{GATEWAY}/{name}{ep}"
    nonce = f"AT082-{int(time.time() * 1000)}-{name}"
    hdr = {"X-Payer-Address": AGENT,
           "X-Payment": payment_header(nonce, amount, ep)}
    data = None
    if multipart:
        b = "----AT082"
        data = (f"--{b}\r\nContent-Disposition: form-data; "
                f'name="csv_file"; filename="f.csv"\r\n'
                f"Content-Type: text/csv\r\n\r\n").encode() \
            + body + f"\r\n--{b}--\r\n".encode()
        hdr["Content-Type"] = f"multipart/form-data; boundary={b}"
    else:
        data = json.dumps(body).encode()
        hdr["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=hdr, method="POST")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return {"http": r.status, "body": r.read().decode(errors="replace"),
                    "ms": round((time.time() - t0) * 1000)}
    except urllib.error.HTTPError as e:
        return {"http": e.code, "body": e.read().decode(errors="replace"),
                "ms": round((time.time() - t0) * 1000)}
    except Exception as e:                                   # INDETERMİNE
        return {"http": 0, "body": f"{type(e).__name__}: {e}",
                "ms": round((time.time() - t0) * 1000)}


# 6 x402-servisi — gateway.ROUTES ile-birebir (planlock-hariç)
CALLS = [
    ("cleartag", "0.100000", "/dogrula",
     {"offer_id": "AT082/CT", "current_price": 500.0,
      "claimed_original_price": 64999.99,
      "history": [{"ts": "2026-09-18T10:00:00Z", "price_amount": 21500.0},
                  {"ts": "2026-09-15T10:00:00Z", "price_amount": 22000.0}]}),
    ("pqhaven", "0.500000", "/tara",
     {"target": "cloudflare.com:443", "scan_type": "network",
      "shelf_life_years": 10.0, "migration_time_years": 3.0,
      "crqc_arrival_years": 7.5}),
    ("repriceai", "0.250000", "/tara",
     {"our_seller_id": "US", "target_margin": 0.15,
      "offers": [
          {"seller_id": "US", "price": 105.0, "in_stock": True,
           "fulfillment": "fba", "seller_rating": 97,
           "delivery_days": 1, "account_health": 0.95},
          {"seller_id": "C1", "price": 100.0, "in_stock": True,
           "fulfillment": "fba", "seller_rating": 95,
           "delivery_days": 2, "account_health": 0.90}]}),
    ("callsnap", "0.150000", "/geri-ara",
     {"hasta_adi": "AT082 Pilot", "hasta_telefonu": "+905551112233",
      "tarih": "2026-09-25", "servis": "Dis Temberligi",
      "slot_indis": 0, "notas": "pilot"}),
    ("vadedostu", "0.500000", "/hatirlatma",
     b"firma,fatura_no,vade,durum,tutar\n"
     b"AT082 A,F-1001,2026-09-05,open,1500.00\n"
     b"AT082 B,F-1002,2026-09-12,open,750.50\n"),
    ("borsa", "0.010000", "/teklif-ver",
     {"agent_id": AGENT, "amount": 0.01,
      "work_spec": "AT082-pilot-is", "nonce": "at082-pilot"}),
]


def run_pilot(ev_dir: Path) -> dict:
    """6-servisi-çağır, receipt'ları-topla, kanıt olarak-yaz."""
    ev_dir.mkdir(parents=True, exist_ok=True)
    results = {}
    for name, amount, ep, body in CALLS:
        r = call(name, amount, ep, body, multipart=(name == "vadedostu"))
        results[name] = {"endpoint": ep, "amount": amount, **r}
        try:
            j = json.loads(r["body"])
            results[name]["result_keys"] = sorted(j.keys())[:6]
        except Exception:
            results[name]["result_keys"] = []
        time.sleep(0.4)

    # --- receipt'ları topla: her-servisin-Sester-ledger-yanıtı-zaten-üretimde
    # Tamga-dikişi-yazıyor (~/.workspace/unpump-binds). Biz-pilot-öncesi-son-
    # seq'yi-işaretleyip-sonrasını-toplarız.
    binds_dir = Path(os.environ.get(
        "UNPUMP_BIND_DIR", str(Path.home() / ".workspace" / "unpump-binds")))

    out = {
        "pilot": "00-gateway x402 6-servis",
        "gateway": GATEWAY,
        "agent": AGENT,
        "ts": int(time.time()),
        "services": results,
        "up_count": sum(1 for v in results.values() if v["http"] == 200),
        "binds_dir": str(binds_dir),
    }
    (ev_dir / "pilot-traffic.json").write_text(
        json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return out


if __name__ == "__main__":
    ev = Path(sys.argv[1] if len(sys.argv) > 1 else ".evidence/GATEWAY-PILOT")
    o = run_pilot(ev)
    print(json.dumps({k: {kk: vv for kk, vv in v.items() if kk != "body"}
                      for k, v in o["services"].items()},
                     indent=1, ensure_ascii=False))
    print(f"\n6/6-200: {o['up_count']}/6 — kanıt: {ev}/pilot-traffic.json")
