#!/usr/bin/env python3
"""liveness_probe.py — tek-komut canlılık-sondası (üç-sonuç sözleşmesi; founder-onaylı 2026-09-15).

NE ÖLÇER: seçilen RPC'de en-güncel bloğun TAZELİĞİ — block-number-farkı = saat.
Sunucu-duvar-saati-güvenilmez (yanlış-saat-gerçeği budur; x402 #3389'daki 41-dk-STALE
hata-sınıfi başkasının defterinde kaldı): `latest` ve `latest-K` blok NO'larını istekte
kendimiz veriyoruz, yanıtın İÇİNDEKİ timestamp'i hiç okumuyoruz. Fark-K-öncesi-blok
bulunamıyorsa (yanıt-kısa/boş) → İNDETERMİNE, GUESS yok.

NE İDDİA ETMEZ (dürüstlük-satırı, çıktıdan-düşer): konsensüs-kanaati, zincirin-doğruluğu,
receipt-kabulü — sadece "bu-RPC bu-eşiklerde taze-görünüyor mu". §4.x metri geldiğinde
gidon-adları-buraya-bağlanır (G6-RUNBOOK §2.A); bugünkü haliyle metinden-BAĞIMSIZdır.

ÇIKIŞ SÖZLEŞMESİ (tamga üçlüsü): 0 GREEN · 1 RED (bloklar-var-ama-çatlak: head!=parent
kardeş yaşı; ya da eşik-aşımı RED-isterken) · 2 İNDETERMİNE (RPC-bakamadım — yeşil-değil,
kırmızı-da-değil). JSON tek-satır stdout; insan-satırı stderr.
"""
import argparse
import json
import sys
import urllib.request

EXIT_GREEN, EXIT_RED, EXIT_IND = 0, 1, 2


def _rpc(rpc: str, method: str, params: list) -> dict:
    corps = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    req = urllib.request.Request(
        rpc, data=json.dumps(corps).encode(),
        headers={"content-type": "application/json", "user-agent": "tamga-liveness-probe/1"})
    rep = json.load(urllib.request.urlopen(req, timeout=30))
    if "error" in rep:
        raise RuntimeError(f"RPC error yanıtı: {str(rep['error'])[:160]}")
    if "result" not in rep or rep["result"] in (None, "0x", ""):
        raise RuntimeError(f"RPC beklenmedik boş yanıt: {str(rep)[:160]}")
    return rep["result"]


def probe(rpc: str, max_age_blocks: int) -> tuple[int, dict]:
    out = {"probe": "liveness", "rpc_kind": "public" if "localhost" not in rpc and "127.0.0.1" not in rpc else "local",
           "max_age_blocks": max_age_blocks,
           "claim": "RPC tazelik-sondası — konsensüs/receipt-kanaati DEĞİLDİR"}
    try:
        head_hex = _rpc(rpc, "eth_getBlockByNumber", ["latest", False])
    except Exception as e:  # bakamadım — yeşil de kırmızı da değil
        out.update(verdict="İNDETERMİNE", reason=f"latest-okunamadı: {e}")
        return EXIT_IND, out
    head = int(head_hex["number"], 16)
    out["head"] = head
    if head == 0:  # jenezis: ilerleme KAVRAMSAL olarak kanıtlanamaz — sessizlik değil, RED.
        out.update(verdict="RED", reason="head=0: zincir-henüz-blok-üretmedi")
        return EXIT_RED, out
    if max_age_blocks == 0:  # salt-okuma modu: eşik-yok, tazelik-raporu RED/GREEN üretmez
        out.update(verdict="İNDETERMİNE", reason="max_age_blocks=0: eşik-tanım-sız ölçüm kaydı")
        return EXIT_IND, out
    # eşik-öncesi-blok: yanıt-timestamp'i GÜVENİLMEZ — K-blok-önceki-bloğun var-olduğunu
    # kendimiz-sorgulayarak kanıtlıyoruz (number-farkı = saat).
    try:
        past_hex = _rpc(rpc, "eth_getBlockByNumber", [hex(max(head - max_age_blocks, 0)), False])
    except Exception as e:
        out.update(verdict="İNDETERMİNE", reason=f"eşik-öncesi-blok okunamadı: {e}")
        return EXIT_IND, out
    span = head - int(past_hex["number"], 16)
    out["blocks_since_threshold"] = span
    if span < max_age_blocks:
        # yerel-test-ve-sessiz-ağ-dürüstlüğü: K-block FARK EDİLEMİYORSA tazelik iddia edilemez.
        out.update(verdict="İNDETERMİNE",
                   reason=f"fark-yetersiz ({span}<{max_age_blocks}): K-blok-ilerleme kanıtlanamadı")
        return EXIT_IND, out
    out.update(verdict="GREEN",
               reason=f"head {head}; en-az {max_age_blocks} blok-ilerleme RPC-varlık-karıtıyla ölçüldü")
    return EXIT_GREEN, out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="tamga-liveness-probe", description=__doc__.split("\n\n")[0])
    ap.add_argument("--rpc", default="https://ethereum-sepolia-rpc.publicnode.com",
                    help="eth_getBlockByNumber konuşan herhangibir HTTP RPC (default: %(default)s)")
    ap.add_argument("--max-age-blocks", type=int, default=10,
                    help="tazelik eşiği: bu-kadar-blok-ilerleme kanıtlanamazsa GREEN denmez (default: %(default)s)")
    a = ap.parse_args(argv)
    rc, out = probe(a.rpc, a.max_age_blocks)
    print(json.dumps(out, ensure_ascii=False))
    print(f"[{out['verdict']}] {out['reason']}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main())
