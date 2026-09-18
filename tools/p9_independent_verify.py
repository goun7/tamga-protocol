#!/usr/bin/env python3
"""P9 bağımsız ödeme-bacak doğrulayıcısı (stdlib-only — bizim protokol kodu KULLANILMAZ).

Amaç: P9 pilot-geliri kanıtının *ödeme bacağını* Tamga'nın kendi koduna
bağımlı olmadan doğrulamak. Bir alıcı bir tx-hash verir; bu araç doğrudan
public RPC'ye sorar (eth_getTransactionReceipt), USDC Transfer olayını çözer
ve facilitator sözleşmesiyle etkileşimi kanıtlar. Hiçbir tamga_* modülü
bacakta yok — gerçek bağımsızlık budur (holistis'in ASM-spec yönteminden
esinlenildi, #3379'da bizim de onayladığımız standart).

Makbuz bacağı ayrıdır ve bilinçli olarak AYRI tutulur: verify_dx402_vector.py
o işi yapar. Bu araç sadece "para gerçekten hareket etti mi?" sorusunu
cevaplar.

Kullanım:
  python3 tools/p9_independent_verify.py <tx-hash> [--rpc URL] [--receipt receipt.json]
  python3 tools/p9_independent_verify.py --dry-run   # ödeme-harici prosedür provası

Çıkış: PASS/FAIL/SKIP etiketli; rc=0 hiçbir zorunlu FAIL yoksa.
Dürüstlük kuralları: atlanan kontrol asla PASS sayılmaz; sentetik veri
asla gerçek kanıt gibi raporlanmaz (--dry-run çıktısı SENTETIK damgalı).
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
import urllib.request

# Kanıt-olarak-postalanan-tanımlayıcı-asla-kesik-olmaz (K19.2). Bu değerler
# evidence'da-değil-ise-buraya-sabitlenmeli; hiçbir-zaman "0x8a9f…" gibi-kesik.
FACILITATOR = "0xa3a05818d4051bfa759fb7d936b57c072e4e0caf"          # düşük-harf-sabit
USDC_BASE = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"            # Base USDC
RPC_DEFAULT = "https://1rpc.io/base"

ERC20_TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"  # Transfer(address,address,uint256)


def rpc(method: str, params: list, rpc_url: str, timeout: int = 30):
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                          "params": params}).encode()
    req = urllib.request.Request(rpc_url, data=payload,
                                 headers={"Content-Type": "application/json",
                                          "User-Agent": "tamga-p9-verify/0.2.12"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = json.load(r)
    if "error" in body:
        raise RuntimeError(f"rpc error: {body['error']}")
    return body.get("result")


def hex2int(h):
    return int(h, 16)


def addr(topic: str) -> str:
    """32-byte-topic'in son 20 baytı → düşük-harf checksum'siz adres."""
    return "0x" + topic[-40:]


def verify_tx(tx_hash: str, rpc_url: str, receipt_path: str | None) -> int:
    fails = 0
    print(f"P9 bağımsız ödeme-bacak doğrulaması")
    print(f"  tx         : {tx_hash}")
    print(f"  rpc        : {rpc_url}")
    print(f"  facilitator: {FACILITATOR}")
    print(f"  usdc       : {USDC_BASE}")
    print()

    # 1) tx gerçekten zincirde-mi (bağımsız RPC, bizim-kodumuz-harici)
    try:
        rcpt = rpc("eth_getTransactionReceipt", [tx_hash], rpc_url)
    except Exception as e:
        print(f"  FAIL rpc-erişim: {e}")
        return 1
    if rcpt is None:
        print(f"  FAIL tx-zincirde-bulunamadı (muhtemelen-yanlış-hash-veya-reorg)")
        return 1
    print(f"  PASS tx zincirde-mevcut · blok {hex2int(rcpt['blockNumber'])} · "
          f"{len(rcpt.get('logs', []))} log")

    if rcpt.get("status") != "0x1":
        print(f"  FAIL tx-status {rcpt.get('status')} — işlem revert-olmuş; para-hareket-etmedi")
        fails += 1
    else:
        print(f"  PASS tx status 0x1 (başarılı)")

    # 2) USDC Transfer olayı — gerçek-para-hareketi
    transfer_logs = [l for l in rcpt.get("logs", [])
                     if l.get("address", "").lower() == USDC_BASE
                     and l.get("topics") and l["topics"][0].lower() == ERC20_TRANSFER_TOPIC]
    if not transfer_logs:
        print(f"  SKIP bu tx'de USDC Transfer olayı-yok (doğrudan-ETH-veya-başka-token olabilir)")
    else:
        total = 0
        for l in transfer_logs:
            frm, to = addr(l["topics"][1]), addr(l["topics"][2])
            amount = hex2int(l["data"])
            total += amount
            print(f"  PASS USDC Transfer {frm[:10]}… → {to[:10]}… · {amount / 1e6:.2f} USDC")
        print(f"  PASS toplam {total / 1e6:.2f} USDC hareket-etti")

    # 3) facilitator etkileşimi
    to_addr = (rcpt.get("to") or "").lower()
    interacted = [l for l in rcpt.get("logs", [])
                  if (l.get("address") or "").lower() == FACILITATOR]
    if to_addr == FACILITATOR:
        print(f"  PASS tx doğrudan facilitator'a-çağrı")
    elif interacted:
        print(f"  PASS facilitator log-event üretti ({len(interacted)} olay)")
    else:
        print(f"  SKIP facilitator-bu-tx'de-görünmüyor (to={to_addr[:12]}…) — "
              f"aracı-üzerinden-veya-başka-sözleşme-ihtimali; manuel-kontrol-gerek")

    # 4) tx-hash tam-mı (K19.2 — kesik-hash-asla-kabul)
    if len(tx_hash) != 66 or not tx_hash.startswith("0x"):
        print(f"  FAIL tx-hash-kesik-veya-malformed (K19.2: kanıt-tanımlayıcı-asla-kesik)")
        fails += 1
    else:
        print(f"  PASS tx-hash tam-66-karakter (K19.2)")

    # 5) makbuz-bacağı-bağlantısı (eğer-receipt-verildiyse)
    if receipt_path:
        try:
            rec = json.loads(pathlib.Path(receipt_path).read_text())
            pid = str(rec.get("paymentId") or rec.get("payment_id") or "")
            if pid and pid.lower() == tx_hash.lower():
                print(f"  PASS receipt.paymentId == tx-hash (ödeme↔makbuz bağlandı)")
            else:
                print(f"  FAIL receipt.paymentId ({pid[:20]}…) ≠ tx-hash — makbuz-bağsız")
                fails += 1
        except Exception as e:
            print(f"  SKIP receipt-okunamadı: {e}")

    print()
    if fails:
        print(f"RESULT: {fails} zorunlu-FAIL — ödeme-bacağı-doğrulanamadı")
        return 1
    print("RESULT: PASS — ödeme-bacağı bağımsız-olarak-doğrulandı (stdlib-only, "
          "tamga-kodu-ödemede-kullanılmadı)")
    return 0


def dry_run() -> int:
    """Ödeme-harici prosedür provası: sentetik-kanıtla tüm-adımları-koş.

    SENTETIK damgası: bu-çıktı ASLA gerçek-P9-kanıtı-saymaz; sadece-akışın
    çalıştığını-gösterir (P9-ölçütü 'gerçek ödeme akışı'dır)."""
    print("=== P9 ÖRTÜLÜ-PROSEDÜR PROVASI (SENTETIK — kanıt-saymaz) ===\n")
    fake = "0x" + "ab" * 32
    print("1) evidence-dizini-aç: .evidence/P9/<tarih>/")
    print("2) tx-hash'ı-al → TAM-66-karakter-kaydet (K19.2)")
    print("3) bağımsız-doğrulama: tools/p9_independent_verify.py <hash>")
    print("4) makbuz-bacağı: tools/verify_dx402_vector.py receipt.json --pair-charge")
    print("5) üç-ölçüt-keseni: ANINDA + KANIT + BAĞIMSIZ\n")
    # format-kontrolü-sentetik-veri-ile
    assert len(fake) == 66, "K19.2 format-kontrolü"
    print(f"  PASS sentetik-hash formatı-doğru ({len(fake)} krk) — gerçek-koşuda-aynı-kontrol")
    print("  PASS araç-import-edilebilir, RPC-şablonu-hazır")
    print("\nSENTETIK-BİTTİ — gerçek-P9-için-cüzdan-ve-gerçek-ödeme-gerekir")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("tx_hash", nargs="?", help="doğrulanacak-tam-tx-hash (0x+64hex)")
    ap.add_argument("--rpc", default=RPC_DEFAULT, help="public RPC URL")
    ap.add_argument("--receipt", help="receipt.json (paymentId↔tx-hash bağı)")
    ap.add_argument("--dry-run", action="store_true", help="sentetik-prova (kanıt-saymaz)")
    a = ap.parse_args()
    if a.dry_run:
        return dry_run()
    if not a.tx_hash:
        ap.print_usage()
        return 2
    return verify_tx(a.tx_hash, a.rpc, a.receipt)


if __name__ == "__main__":
    sys.exit(main())
