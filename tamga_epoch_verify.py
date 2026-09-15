#!/usr/bin/env python3
"""tamga_epoch_verify.py — dış epoch-mührünü kendin doğrula (verify-it-yourself; AT-027).

RFC-009 alıcı-çiftinin genel-uzantısı: PUGIO köprüsünün İKİ özel-çıpa biçimini doğrulayan
tamga_pugio_receiver/tamga_pugio_ingest'in yanı sıra, bu modül KAMU epoch-mühür-kanıtı
payload'unu (örnek: Apodix/Vauban explorer `GET /v1/anchors/proof/<fact>`) doğrular.

İKİ BACAK:
  1. dahil-etme — yaprak = keccak256(keccak256(bytes32(fact))); sorted-pairs yürüyüşü
     (OpenZeppelin merkle-tree tarifi) → hesaplanan kök payload'ın `root`'una eşit mi
  2. çapa (isteğe bağlı, --rpc) — `epoch(uint64)` eth_call'u; on-chain factsRoot/factsCount
     payload köküyle/yaprak-sayısıyla eşleşiyor mu. --rpc verilmezse yalnız 1. bacak koşar.

EXIT: 0 = GREEN (istenen bacaklar eşleşti) · 1 = RED (uymazlık) · 2 = İNDETERMİNE (RPC yanıt
vermedi — "bakamadım" ile "yeşil" karıştırılmaz; VERIFY-EPOCH-ANCHOR.md §yeşil-demek-için).

DÜRÜSTLÜK-SINIRI: bu doğrulama, fact'ın mühürlü bir epoch-ağacına DAHİL EDİLDİĞİNİ ve mührün
zincirde DURDUĞUNU kanıtlar; fact'ın kendi içeriğinin (örn. bir STARK kabulünün) doğruluğunu
kanıtlamaz. İki soru karıştırılmaz.

Bağımlılık: YOK — tamga_keccak (saf-Python keccak; 3 bilinen-yanıt vektörüyle öz-doğrular).
Kaynak-olay: 2026-09-13 epoch-13 seal-flip replay (kanıt: .evidence/APODIX-EPOCH-13/2026-09-13/;
kamu raporu: x402 #3389 issuecomment-5653083752). El-rehberi: docs/VERIFY-EPOCH-ANCHOR.md.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request

import tamga_keccak

DEFAULT_RPC = "https://ethereum-sepolia-rpc.publicnode.com"
DEFAULT_CONTRACT = "0x48421a2e448cb2E3fA66af2E047F86ee755cFB14"
DEFAULT_CHAIN_ID = 11155111  # sepolia — DEFAULT_CONTRACT orada; eşleme-varsayılana bağlanır

EXIT_OK, EXIT_RED, EXIT_INDETERMINATE = 0, 1, 2


def _leaf(fact_hash: str) -> bytes:
    raw = bytes.fromhex(fact_hash[2:] if fact_hash.startswith("0x") else fact_hash)
    if len(raw) != 32:
        raise ValueError(f"fact_hash 32-bayt olmalı (64 hex); {len(raw)} bayt geldi")
    return tamga_keccak.keccak256(tamga_keccak.keccak256(raw))


def verify_inclusion(fact_hash: str, proof: list[str], expected_root: str) -> tuple[bool, str]:
    """Dahil-etme bacağı: sorted-pairs keccak yürüyüşü (fail-loud hex hataları)."""
    node = _leaf(fact_hash)
    for i, p in enumerate(proof):
        try:
            sib = bytes.fromhex(p[2:] if p.startswith("0x") else p)
        except ValueError as exc:
            return False, f"proof[{i}] hex-bozuk: {exc}"
        if len(sib) != 32:
            return False, f"proof[{i}] 32-bayt olmalı; {len(sib)} bayt"
        lo, hi = sorted([node, sib])
        node = tamga_keccak.keccak256(lo + hi)
    computed = "0x" + node.hex()
    return computed == expected_root, computed


def _selector(signature: str) -> str:
    return "0x" + tamga_keccak.keccak256(signature.encode()).hex()[:8]


def _rpc_result(rpc: str, method: str, params: list):
    """Tek-atımlık JSON-RPC: result-yoksa raise (İNDETERMİNE sözleşmesi)."""
    corps = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    req = urllib.request.Request(
        rpc, data=json.dumps(corps).encode(),
        headers={"content-type": "application/json", "user-agent": "tamga-epoch-verify/1"})
    rep = json.load(urllib.request.urlopen(req, timeout=60))
    if "result" not in rep or not rep["result"]:
        raise RuntimeError(f"RPC beklenmedik yanıt ({method}): {str(rep.get('error', rep))[:160]}")
    return rep["result"]


def read_onchain_epoch(rpc: str, contract: str, epoch_id: int,
                       expect_chainid: int | None = None) -> tuple[str, int]:
    """Çapa bacağı: epoch(uint64) → (factsRoot, factsCount). RPC hatası → raise (INDETERMINATE).

    #2887 (2026-09-15) testable-binding dersi: çağıranın-verdiği-RPC'ye-güven,
    "hash-eşleşmesi-kimlik-eşleşmesi-değildir" ailesinin bizdeki-hali — eth_chainId ön-sorgusu
    politikadır, şans-değil: beklenti-dışı-zincirde sözleşme-olsa-bile BAŞKA-veri okumuş oluruz.
    """
    if expect_chainid is not None:
        got = int(_rpc_result(rpc, "eth_chainId", []), 16)
        if got != expect_chainid:
            raise RuntimeError(f"yanlış-zincir: RPC chainId={got}, beklenen={expect_chainid}")
    data = _selector("epoch(uint64)") + f"{epoch_id:064x}"
    corps = {"jsonrpc": "2.0", "id": 1, "method": "eth_call",
             "params": [{"to": contract, "data": data}, "latest"]}
    req = urllib.request.Request(
        rpc, data=json.dumps(corps).encode(),
        headers={"content-type": "application/json", "user-agent": "tamga-epoch-verify/1"})
    rep = json.load(urllib.request.urlopen(req, timeout=60))
    if "result" not in rep or not rep["result"] or len(rep["result"]) < 130:
        raise RuntimeError(f"RPC beklenmedik yanıt: {str(rep.get('error', rep))[:200]}")
    brut = rep["result"][2:]
    return "0x" + brut[0:64], int(brut[64:128], 16)


def _selftest() -> int:
    """AT-027 iç-özünü-kanıtı: yaprak/kök/yürüyüş üçlüsünü bilinen vektörle doğrular."""
    ok = True
    # yaprak-şekli: double-keccak32 — boş-değerde deterministik
    leaf = tamga_keccak.keccak256(tamga_keccak.keccak256(bytes(32)))
    ok &= leaf == tamga_keccak.keccak256(tamga_keccak.keccak256(bytes(32)))
    # tek-öğe kanıt: proof boş → kök = yaprak
    good, comp = verify_inclusion("0x" + bytes(32).hex(), [], "0x" + leaf.hex())
    ok &= good and comp == "0x" + leaf.hex()
    # kardeş-sıralaması: sorted-pairs — (node,sib) ile (sib,node) aynı kökü verir
    n1 = tamga_keccak.keccak256(b"n")
    s1 = tamga_keccak.keccak256(b"s")
    k1 = tamga_keccak.keccak256(min(n1, s1) + max(n1, s1))
    ok &= k1 == tamga_keccak.keccak256(sorted([n1, s1])[0] + sorted([n1, s1])[1])
    print("[selftest] yaprak-şekli + boş-kanıt + sorted-pairs:", "OK" if ok else "FAIL")
    return 0 if ok else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="tamga epoch-verify",
        description="Dış epoch-mühür-kanıtını doğrula (dahil-etme + isteğe-bağlı zincir-kökü).")
    ap.add_argument("proof", nargs="?", help="epoch-mühür kanıt-payload'ı (explorer /v1/anchors/proof JSON'u)")
    ap.add_argument("--rpc", help=f"zincir-bacağını da koş (default: {DEFAULT_RPC})",
                    nargs="?", const=DEFAULT_RPC)
    ap.add_argument("--contract", default=DEFAULT_CONTRACT, help="epoch sözleşmesi (default: %(default)s)")
    ap.add_argument("--expect-chainid", type=int, default=DEFAULT_CHAIN_ID,
                    help="zincir-bağı ön-sorgusu (eth_chainId); 0 = atla (dürüst-not basılır) "
                         f"(default: {DEFAULT_CHAIN_ID} = sepolia)")
    ap.add_argument("--selftest", action="store_true", help="iç-özünü-kanıtı (ağ YOK)")
    a = ap.parse_args(argv)

    if a.selftest:
        return _selftest()
    if not a.proof:
        ap.error("kanıt-dosyası gerekli (veya --selftest)")

    try:
        d = json.load(open(a.proof, encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"[RED] kanıt-dosyası okunamadı: {exc}")
        return EXIT_RED
    for alan in ("fact_hash", "proof", "root", "epoch_id"):
        if alan not in d:
            print(f"[RED] zarf-eksik: '{alan}' alanı yok (explorer proof-payload'ı bekleniyor)")
            return EXIT_RED

    # bacak-1: dahil-etme
    good, comp = verify_inclusion(d["fact_hash"], d["proof"], d["root"])
    print(f"dahil-etme : hesaplanan-kök {comp}")
    print(f"            payload-kök     {d['root']}  → {'EŞİT' if good else 'FARKLI'}")
    if not good:
        print("[RED] dahil-etme bacağı uymadı — fact bu epoch-ağacının yaprağı DEĞİL")
        return EXIT_RED

    # bacak-2 (yalnız --rpc ile): zincir-üstü kök
    if a.rpc:
        expect = a.expect_chainid if a.expect_chainid else None
        if expect is None:
            print("[not] zincir-bağı (eth_chainId) ATLANDI — 'hangi zincir' sorusu yanıtsız "
                  "(#2887 dersi: bu-kaydı bilinçli-atlama, unutma değil)")
        try:
            root, count = read_onchain_epoch(a.rpc, a.contract, int(d["epoch_id"]), expect)
        except Exception as exc:  # noqa: BLE001 — INDETERMINATE sözleşmesi geniş
            print(f"[İNDETERMİNE] RPC yanıt vermedi ({exc}) — bakamadım ile yeşil karıştırılmaz")
            return EXIT_INDETERMINATE
        leaf_count = int(d.get("leaf_count", 0))
        root_ok = root.lower() == str(d["root"]).lower()
        count_ok = count == leaf_count if leaf_count else True
        print(f"zincir     : epoch({d['epoch_id']}).factsRoot {root}")
        print(f"            factsCount {count}" + (f" / leaf_count {leaf_count}" if leaf_count else ""))
        if not (root_ok and count_ok):
            print("[RED] zincir-kökü veya sayısı uymadı — mühür bu kökü taşımıyor")
            return EXIT_RED
        print("[GREEN] dahil-etme + zincir-çapası iki bacak da eşleşti")
        return EXIT_OK

    print("[GREEN] dahil-etme bacağı eşleşti (zincir bacağı için --rpc verin)")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
