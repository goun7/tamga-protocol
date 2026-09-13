#!/usr/bin/env python3
"""tamga_verify_mini.py — standalone Tamga chain verifier (B2, Cosmos-modeli).

Amaç: KARŞI-TARAF bizim runner'ımızı KURMADAN ledger.jsonl doğrulasın.
Girdi: tek dosya (ledger.jsonl) — THIRDPARTY-minimal yüzey.
Bağımlılık: YOK (saf stdlib; PyNaCl dahi gerekmez — node-cosign doğrulaması
ed25519-imza-şeması doctest-dışı ihtiyaç olursa opsiyoneldir; bu mini araç
yalnız zincir matematiğini kontrol eder: prev-link + JCS-canonical-hash + seq).

Doğrulama kuralı — tamga_runner._verify_chain ile BİREBİR (tek-gerçek):
  h = sha256( rec.prev + jcs(rec-minus-h-and-node_sig) )   seq 1'den başlar, prev-zinciri
MAX_LINE_BYTES = 1 MiB (Audit-11 panzehiri — burada da geçerli).

Kullanım:
  python3 tamga_verify_mini.py <ledger.jsonl> [--expect-tip=<hex>]

Çıkış: JSON-satır {"ok": bool, "lines": n, "head": hex|"", "reason": str}
rc: 0-doğrulandı · 1-kırık · 2-kullanım-hatası
"""
import hashlib
import json
import sys

MAX_LINE_BYTES = 1 * 1024 * 1024  # Audit-11 D1 paritesi

def jcs(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

def verify(ledger_path: str):
    prev_h, n = "0" * 64, 0
    try:
        with open(ledger_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                n += 1
                if len(line.encode("utf-8")) > MAX_LINE_BYTES:
                    return "", f"broken@{n} (line > {MAX_LINE_BYTES}B — bomba-satırı-yutulmaz)"
                try:
                    rec = json.loads(line)
                except Exception:
                    return "", f"broken@{n} (unparseable line)"
                if not isinstance(rec, dict):
                    # parite: tamga_runner._verify_chain aynı-girdiyi broken-RED'ye çevirir —
                    # mini de öyle davranır (2026-09-13 taze-göz-paritesi-bulgusu)
                    return "", f"broken@{n} (record is not a JSON object)"
                no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
                exp = hashlib.sha256((rec.get("prev", "") + jcs(no_h).decode("utf-8")).encode("utf-8")).hexdigest()
                if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
                    return "", f"broken@{n}"
                prev_h = rec["h"]
    except OSError as e:
        return "", f"io_error: {e}"
    return prev_h, "ok" if n else "empty chain: no records yet (genesis tip is valid)"

def main(argv):
    args = [a for a in argv if not a.startswith("--expect-tip")]
    expect = None
    for a in argv:
        if a.startswith("--expect-tip="):
            expect = a.split("=", 1)[1].lower()
    if len(args) != 1:
        print(__doc__)
        return 2
    tip, reason = verify(args[0])
    ok = tip != ""
    res = {"ok": ok, "lines": None, "head": tip, "reason": reason}
    # satır-sayısı-ok-ken-yeniden-say (küçük-dosyalar-için-netlik):
    if ok:
        with open(args[0], "r", encoding="utf-8") as f:
            res["lines"] = sum(1 for l in f if l.strip())
    if expect is not None and ok:
        ok = (tip == expect)
        res["reason"] = "ok" if ok else f"tip-mismatch: expected {expect[:12]}…, got {tip[:12]}…"
    print(json.dumps(res))
    return 0 if ok else 1

# --- Vauban stark-receipt-profile v0.1 §4.4 uyumu (2026-09-09) ---
# 'a verifier that does not know the label concludes nothing (indeterminate), never absent'
KNOWN_FOREIGN_TAGS = {"TAMGA_CHAIN_HEAD_V1", "APODIX_EPOCH_ROOT_V1"}

def foreign_leaf_verdict(tag, digest_lo, digest_hi):
    """v3-yabancı-leaf üçlüsü-için-üç-verdict-döndürür: established|refuted|indeterminate.
    Kurallar (§4.3-F1/F2 + §4.4): tag=0→indeterminate-(etiket-bilinmiyor); digest=0→refuted
    -(boş-söz); tag-bilinmiyor→indeterminate; biliniyor→indeterminate-(kök-recompute-bizde-değil
    — origin-registry-validity-ASLA-iddia-edilmez)."""
    if not tag:
        return "indeterminate", "empty origin tag (§4.3 F1) — a digest without a label is a number"
    if digest_lo == 0 and digest_hi == 0:
        return "refuted", "zero digest (§4.3 F2) — an unfilled field, never a real hash"
    if tag not in KNOWN_FOREIGN_TAGS:
        return "indeterminate", f"unknown origin tag {tag!r} — conclusion withheld, not absence"
    return "indeterminate", (f"tag {tag!r} known but root recompute belongs to the origin "
                             "registry; this verifier claims presentation only (§4.4)")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
