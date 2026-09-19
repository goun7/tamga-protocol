#!/usr/bin/env python3
"""
AT-042: settlement-köprü — doğrulanmış Veridict-sertifikasını ödeme-katmanının
değerlendirebileceği bir release-claim'ine çevirir (Veridict'in-aynı-disiplini).

TASARIM (Veridict/settlement.py'nin-Tamga-tarafı-eşi, 2026-09-19):
  build_settlement_claim — sertifikanın-doğrulanmış-içeriğinden release-claim
                           üretir (sadece "iş-kanıtla-yapılmış-mı"; amount-HAYIR)
  verify_settlement_claim — claim'i sertifika üzerinden BAĞIMSIZ olarak
                            YENİDEN HESAPLAR (sadece-karşılaştırmaz)

İKİ-KATMANLI-DİSİPLİN (Veridict-dersi, AT-041-ile-aynı):
  katman-1: presented-tutarlılık — claim'in-own-digest'ı-kendi-alanlarından
  katman-2: bağımsız-yeniden-hesap — claim, sertifikadan-tekrar-üretilir

TEK-katman-saldırısı (Veridict-yakaladı): valid:true'ya-çevirilip-eski-digest
korunursa doğrulama geçiyordu — çünkü digest-bir-kez-hesaplanıp-karşılaştırılıyordu.
Çözüm: digest-presented-claim'in-KENDİ-alanlarından-yeniden-hesaplanır.

SINIRLAR (Veridict-ile-aynı, dürüst): ödeme-hareket-ettirmiyor, amount-
hesaplamıyor. Sadece "iş-kanıtla-yapıldı-mı" — fiyatı-ödeme-katmanı-belirler.

Kullanım:
    python3 tools/settlement_bridge.py build  <cert.json>  <ledger.jsonl> > claim.json
    python3 tools/settlement_bridge.py verify <claim.json>   <cert.json> <ledger.jsonl>
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(HERE))


def _canon(o) -> bytes:
    """Sıralı-JSON-kanonik-form (AT-040/041-ile-aynı-felsefe)."""
    return json.dumps(o, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode("utf-8")


def _verify_cert(cert_path: str, ledger_path: str) -> dict:
    """Veridict-sertifikasını-üretim-CLI-ile-doğrula (zero-import-yol)."""
    r = subprocess.run(
        [sys.executable, "-m", "veridict.cli", "verify",
         "--ledger", ledger_path, "--cert", cert_path],
        capture_output=True, text=True)
    if r.returncode != 0:
        return {"ok": False, "reason": f"veridict-verify-RED rc={r.returncode}"}
    try:
        d = json.loads(r.stdout)
    except ValueError:
        return {"ok": False, "reason": "veridict-çıktı-JSON-değil"}
    return {"ok": bool(d.get("valid", d.get("ok"))), "raw": d}


# Settlement-claim'in-KANONİK-alanları — bunlardan-digest-hesaplanır
CLAIM_FIELDS = ("cert_id", "task_id", "verdict", "risk_level", "issued_at_task")


def build_settlement_claim(cert_path: str, ledger_path: str) -> dict:
    """Sertifikadan-settlement-claim-üret (release-claim).

    Sadece-doğrulanmış-içeriği-alır; ham-sertifikayı-kopyalamaz.
    """
    chk = _verify_cert(cert_path, ledger_path)
    if not chk.get("ok"):
        return {"ok": False, "reason": f"sertifika-doğrulanmadı: {chk.get('reason')}"}
    try:
        cert = json.loads(Path(cert_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return {"ok": False, "reason": f"sertifika-okunamadı: {type(e).__name__}"}
    claim = {
        "type": "tamga-settlement-claim",
        "version": "0.1",
        "cert_id": cert.get("cert_id"),
        "task_id": cert.get("issued_at_task", {}).get("task_id")
                   if isinstance(cert.get("issued_at_task"), dict)
                   else cert.get("issued_at_task"),
        "verdict": cert.get("claims", {}).get("verdict")
                   if isinstance(cert.get("claims"), dict) else None,
        "risk_level": cert.get("risk_level"),
        "issued_at_task": cert.get("issued_at_task"),
    }
    # katman-1-digest: claim'in-KENDİ-alanlarından-hesaplanır
    core = {k: claim[k] for k in CLAIM_FIELDS}
    claim["digest"] = hashlib.sha256(_canon(core)).hexdigest()
    claim["limits"] = {"moves_payment": False, "computes_amount": False,
                       "answers": "is-work-proven"}
    return {"ok": True, "claim": claim}


def verify_settlement_claim(claim_path: str, cert_path: str,
                            ledger_path: str) -> dict:
    """Claim'i-sertifika-üzerinden-BAĞIMSIZ-yeniden-hesapla.

    İki-katman (Veridict-dersi):
      1. presented-claim'in-digest'ı-kendi-alanlarından-yeniden-hesaplanır
      2. claim-bütünüyle-sertifikadan-tekrar-üretilir-ve-karşılaştırılır
    """
    try:
        presented = json.loads(Path(claim_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return {"ok": False, "reason": f"claim-okunamadı: {type(e).__name__}"}
    if not isinstance(presented, dict) or \
       presented.get("type") != "tamga-settlement-claim":
        return {"ok": False, "reason": "type tamga-settlement-claim değil"}
    if presented.get("version") != "0.1":
        return {"ok": False, "reason": f"version 0.1 değil: {presented.get('version')}"}

    # --- katman-1: presented-digest'ı-kendi-alanlarından-yeniden-hesapla ---
    try:
        core = {k: presented[k] for k in CLAIM_FIELDS}
    except KeyError as k:
        return {"ok": False, "reason": f"gerekli-alan-yok: {k}"}
    recomputed = hashlib.sha256(_canon(core)).hexdigest()
    if presented.get("digest") != recomputed:
        return {"ok": False, "reason":
                "digest-uyuşmaz — presented-claim-kendi-içinde-tutarsız "
                "(Veridict-saldırı-sınıfı)",
                "expected": recomputed[:16],
                "actual": str(presented.get("digest"))[:16]}

    # --- katman-2: claim'i-sertifikadan-BAĞIMSIZ-yeniden-üret ---
    rebuilt = build_settlement_claim(cert_path, ledger_path)
    if not rebuilt.get("ok"):
        return {"ok": False, "reason":
                f"sertifikadan-yeniden-üretilemedi: {rebuilt.get('reason')}"}
    new_claim = rebuilt["claim"]
    # karşılaştırma: kanonik-alanlar-birebir-olmalı (digest-dahil)
    if new_claim.get("digest") != presented.get("digest"):
        return {"ok": False, "reason":
                "bağımsız-yeniden-hesap-uyuşmaz — sertifika-claim'i-"
                "desteklemiyor (sahte-claim)",
                "expected": new_claim.get("digest", "")[:16],
                "actual": str(presented.get("digest"))[:16]}

    # --- sınırlar-denetimi (dürüst) ---
    lim = presented.get("limits", {})
    if not isinstance(lim, dict):
        return {"ok": False, "reason": "limits bir nesne değil"}
    for k, v in (("moves_payment", False), ("computes_amount", False)):
        if lim.get(k) != v:
            return {"ok": False, "reason": f"limits.{k} {v!r} olmalı"}
    return {"ok": True, "verdict": "GREEN", "digest": recomputed,
            "cert_id": presented.get("cert_id")}


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__); return 2
    cmd = argv[0]
    if cmd == "build":
        if len(argv) < 3:
            print("kullanim: build <cert.json> <ledger.jsonl>", file=sys.stderr)
            return 2
        r = build_settlement_claim(argv[1], argv[2])
        if not r.get("ok"):
            print(json.dumps(r, ensure_ascii=False)); return 1
        print(json.dumps(r["claim"], ensure_ascii=False, indent=1))
        return 0
    if cmd == "verify":
        if len(argv) < 4:
            print("kullanim: verify <claim.json> <cert.json> <ledger.jsonl>",
                  file=sys.stderr)
            return 2
        r = verify_settlement_claim(argv[1], argv[2], argv[3])
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return 0 if r.get("ok") else 1
    print(f"bilinmeyen komut: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
