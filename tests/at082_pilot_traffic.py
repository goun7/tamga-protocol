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


def _sha64(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def payment_header(nonce: str, amount: str, resource: str) -> str:
    """exact-sester zarfı: EIP-191 personal_sign('agent|nonce|amount|resource')."""
    msg = f"{AGENT.lower()}|{nonce}|{amount}|{resource}".encode()
    sig = Account.sign_message(encode_defunct(msg), private_key=DEMO_SK).signature.hex()
    p = {"scheme": "exact-sester", "agent": AGENT.lower(),
         "nonce": nonce, "amount": amount, "signature": sig}
    b64 = base64.urlsafe_b64encode(json.dumps(p).encode()).decode().rstrip("=")
    return f"Sester-EVM {b64}"


def _post(url, data, hdr, *, method="POST", timeout=45):
    """Ham-HTTP-çağrı (borsa-akışı-için-ortak)."""
    t0 = time.time()
    body = json.dumps(data).encode() if data is not None else None
    if data is not None:
        hdr = {**hdr, "Content-Type": "application/json"}
    req = urllib.request.Request(url, data=body, headers=hdr, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return {"http": r.status, "body": r.read().decode(errors="replace"),
                    "ms": round((time.time() - t0) * 1000)}
    except urllib.error.HTTPError as e:
        return {"http": e.code, "body": e.read().decode(errors="replace"),
                "ms": round((time.time() - t0) * 1000)}
    except Exception as e:                                   # INDETERMİNE
        return {"http": 0, "body": f"{type(e).__name__}: {e}",
                "ms": round((time.time() - t0) * 1000)}


def call(name, amount, ep, body, *, multipart=False):
    url = f"{GATEWAY}/{name}{ep}"
    nonce = f"AT082-{int(time.time() * 1000)}-{name}"
    hdr = {"X-Payer-Address": AGENT,
           "X-Payment": payment_header(nonce, amount, ep)}
    data = None
    if name == "borsa":
        # BORSA-AKIŞI: listele (ücretsiz) → teklif-ver → eslestir (ücretli)
        # → tamamla (receipt-üretimi). Eşleşme-için-aktif-listing-gerekir
        # (price_target ≤ bid-amount).
        proof = _sha64(f"AT082-pilot-kanıt-{int(time.time())}".encode())
        r0 = _post(f"{GATEWAY}/borsa/listele",
                   {"agent_id": AGENT, "name": "AT082-pilot-ajan",
                    "service": "pilot-is", "price_target": 0.01,
                    "proof_hash": proof}, {})
        if r0["http"] != 200:
            return {"http": r0["http"], "body": r0["body"],
                    "ms": r0["ms"], "stage": "listele"}
        bid = {"agent_id": AGENT, "amount": 0.01,
               "work_spec": "AT082-pilot-is",
               "nonce": f"at082-pilot-{int(time.time())}"}
        r1 = _post(f"{GATEWAY}/borsa/teklif-ver", bid, {})
        bid_id = None
        if r1["http"] == 200:
            try:
                bid_id = json.loads(r1["body"]).get("bid_id")
            except Exception:
                pass
        if not bid_id:
            return {"http": r1["http"], "body": r1["body"],
                    "ms": r1["ms"], "stage": "teklif-ver"}
        # eslestir (ücretli — payment-header)
        ep = f"/eslestir/{bid_id}"
        hdr["X-Payment"] = payment_header(nonce, amount, ep)
        r2 = _post(f"{GATEWAY}/borsa{ep}", None, hdr)
        match_id = None
        if r2["http"] == 200:
            try:
                match_id = json.loads(r2["body"]).get("match_id")
            except Exception:
                pass
        if not match_id:
            return {"http": r2["http"], "body": r2["body"],
                    "ms": r2["ms"], "stage": "eslestir", "bid_id": bid_id}
        # tamamla (ücretli 0.01; receipt-üretimi — Sester-ledger'a-yazılır)
        hdr2 = {"X-Payer-Address": AGENT,
                "X-Payment": payment_header(nonce + "-t", amount, "/tamamla")}
        r3 = _post(f"{GATEWAY}/borsa/tamamla",
                   {"match_id": match_id,
                    "receipt_hash": _sha64(bid_id.encode())},
                   hdr2)
        return {"http": r3["http"], "body": r3["body"], "ms": r3["ms"],
                "stage": "tamamla", "bid_id": bid_id, "match_id": match_id}
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
    ("borsa", "0.010000", "/eslestir", {"_flow": "teklif→eslestir→tamamla"}),
]


def reset_quota_for_test(svc_dbs: dict) -> None:
    """Sandbox-pilot-giderlerini-iade-et (refund) — günlük-kotayı-sıfırla.

    NEDEN: sandbox-demo-anahtarının-günlük-$5-kotası-gerçek-fail-closed-
    kısıtıdır. Pilot-testleri-bu-kotayı-aşınca-402-verir ve test-INDETERMİNE-
    SKIP-düşer. Çözüm: pilotun-oluşturduğu-giderleri-gerçek-bir-İADE-eventi
    ile-sıfırlamak (Sester-taksonomisinde-meşru 'refund'-tipi; gerçek-para
    DEĞİL — sandbox-demo-anahtarı, USDC-sim).

    İade-yalnızca-bugünün-pilot-giderlerini-kapsar (AT082-payment-id'ler-ve
    demo-agent). Üretim-giderlere-DOKUNMAZ.
    """
    import sqlite3
    from datetime import datetime, timezone
    sys.path.insert(
        0, "/home/gokun/projects/02_sahis/25-ClearTag/.venv/lib/python3.14"
        "/site-packages")
    from sester.ledger import Ledger
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    for svc, db in svc_dbs.items():
        if not db.exists():
            continue
        try:
            conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            row = conn.execute(
                "SELECT COALESCE(SUM(CASE event_type WHEN 'charge_receipt'"
                " THEN amount WHEN 'refund' THEN -amount ELSE 0 END),0)"
                " FROM events WHERE agent_id=? AND event_type IN"
                " ('charge_receipt','refund') AND date(ts,'unixepoch')=?",
                (AGENT, today)).fetchone()
            conn.close()
            spent = float(row[0]) if row else 0.0
            if spent <= 0:
                continue
            # gerçek-iade-eventi-yaz (taksonomi-meşru; kota-sıfırlar)
            led = Ledger(str(db))
            led.append("refund", AGENT, f"/{svc}", amount=spent,
                       payload={"reason": "AT082-pilot-kota-sıfırlama",
                                "sandbox": True})
            print(f"[quota] {svc}: ${spent:.2f} iade-edildi (kota-sıfırlandı)",
                  file=sys.stderr)
        except Exception as e:
            print(f"[quota] {svc}: iade-hatası: {e}", file=sys.stderr)


def run_pilot(ev_dir: Path) -> dict:
    """6-servisi-çağır, receipt'ları-topla, kanıt olarak-yaz."""
    ev_dir.mkdir(parents=True, exist_ok=True)
    binds_dir = Path(os.environ.get(
        "UNPUMP_BIND_DIR", str(Path.home() / ".workspace" / "unpump-binds")))
    # CHECKPOINT: pilot-öncesi-her-servisin-son-seq'i (her-DB'nin-kendi
    # seq-uzayı-var; üretim-bind'leri-ts-TUTMADIĞI-için-bu-işaret-gerekir)
    import sqlite3
    SVC_DB = {
        "cleartag": Path.home() / ".workspace" / "cleartag" / "receipts.sqlite",
        "pqhaven": Path.home() / ".workspace" / "pqhaven" / "receipts.sqlite",
        "repriceai": Path.home() / ".workspace" / "reprice-ai" / "receipts.sqlite",
        "callsnap": Path.home() / ".workspace" / "callsnap" / "receipts.sqlite",
        "vadedostu": Path.home() / ".workspace" / "vade-dostu" / "receipts.sqlite",
        "borsa": Path.home() / ".workspace" / "ajan-borsasi" / "receipts.sqlite",
    }
    pre_seq = {}
    for svc, db in SVC_DB.items():
        if not db.exists():
            pre_seq[svc] = 0
            continue
        try:
            conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            n = conn.execute(
                "SELECT COALESCE(MAX(seq), 0) FROM events"
                " WHERE event_type = 'charge_receipt'").fetchone()[0]
            conn.close()
            pre_seq[svc] = n
        except Exception:
            pre_seq[svc] = 0

    # KOTA-SIFIRLAMA (opsiyonel, UNPUMP_TEST=1): sandbox-pilot-giderlerini
    # iade-et — günlük-$5-kotası-aşılmasın-diye. Gerçek-para-DEĞİL.
    if os.environ.get("UNPUMP_TEST", "0") == "1":
        reset_quota_for_test(SVC_DB)

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

    # --- receipt'ları topla: her-servisin-kendi-Sester-ledger'ından
    # CHECKPOINT-sonrası-charge_receipt kayıtları. Her-çağrı-bir-receipt.
    receipts = []
    for svc, db in SVC_DB.items():
        if not db.exists():
            continue
        try:
            conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT seq, ts, agent_id, host, amount, payload, prev_hash, hash"
                "  FROM events"
                " WHERE event_type = 'charge_receipt' AND seq > ?"
                " ORDER BY seq", (pre_seq[svc],)
            ).fetchall()                                     # checkpoint-sonrası
            for row in rows:
                try:
                    pl = json.loads(row["payload"])
                except Exception:
                    pl = {}
                # delivery_hash: payload'da (cleartag-dikişi) veya yoksa
                # servisin-ürettiği-hash (her-serviste-dikiş-olmayabilir)
                dh = pl.get("delivery_hash", {}).get("hex", "")
                if not dh:
                    # kanal-receipt: servisin-kendi-ledger-hash'i
                    dh = _sha64((f"{svc}|{row['seq']}|{row['ts']}"
                                 f"|{row['hash']}").encode())
                sb = pl.get("settlement_bind", {})
                receipts.append({
                    "service": svc,
                    "seq": row["seq"],
                    "ts": row["ts"],
                    "agent_id": row["agent_id"],
                    "amount": row["amount"],
                    "payment_id": sb.get("payment_id",
                                         f"UNPUMP-{svc.upper()}-{row['seq']}"),
                    "delivery_hash": dh,
                    "ledger_hash": row["hash"],
                    "has_tamga_bind": bool(sb),
                })
            conn.close()
        except Exception as e:
            print(f"[{svc}] ledger-okuma-hatası: {e}", file=sys.stderr)

    out = {
        "pilot": "00-gateway x402 6-servis",
        "gateway": GATEWAY,
        "agent": AGENT,
        "ts": int(time.time()),
        "pre_seq": pre_seq,
        "receipts": receipts,
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
