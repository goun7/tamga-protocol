#!/usr/bin/env python3
"""explain — bir receipt/charge kaydını insan dilline çevir (RFC-003 D5).

Bilgi-ekleme YOK: yalnız kayıttaki alanları etiketli-paragrafa döker. Türetilebilir
ilişkiler (input-bağı, delivery-bağı) yeniden HESAPLANIR — assumed-equality yok.

Usage:
  python3 tools/explain.py <receipt.json>            # dx402-receipt veya charge-kaydı (TR)
  python3 tools/explain.py --en <receipt.json>       # English rendering
  python3 tools/explain.py --charge <ledger.jsonl> 2  # zincir-N-kayıt (TR)
"""
import json, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from keccak256 import keccak256
import hashlib

def human_bytes(n):
    for u in ("B", "KiB", "MiB", "GiB"):
        if n < 1024:
            return f"{n:.1f} {u}" if u != "B" else f"{n} B"
        n /= 1024
    return f"{n:.1f} TiB"

LABELS_TR = {
    "header": "== {label} kaydı (seq {seq}) ==",
    "pkg": "  İş-sahibi       : {pkg} (oturum {session})",
    "fee": "  Ücret (sim)     : {fee} birim — simnet; gerçek-değer hareketi Faz-4'e kadar yok",
    "wall": "  Duvar-süresi    : {w} ms",
    "chain": "  Zincir-dürüstlüğü: h {v} (sha256(prev ‖ jcs(kayıt-minus-h,node_sig)) yeniden hesaplandı)",
    "ok": "DOĞRULANDI", "bad": "EŞLEŞMİYOR",
}
LABELS_EN = {
    "header": "== {label} record (seq {seq}) ==",
    "pkg": "  Owner           : {pkg} (session {session})",
    "fee": "  Fee (sim)       : {fee} units — simnet; real-value movement stays Phase-4 gated",
    "wall": "  Wall clock      : {w} ms",
    "chain": "  Chain integrity : h {v} (sha256(prev ‖ jcs(record-minus-h,node_sig)) recomputed)",
    "ok": "VERIFIED", "bad": "MISMATCH",
}

def explain_charge(rec, label="charge", L=None):
    L = L or LABELS_TR
    lines = [L["header"].format(label=label, seq=rec.get("seq", "?"))]
    lines.append(L["pkg"].format(pkg=rec.get("pkg", "?"), session=rec.get("session", "?")))
    fee = rec.get("fee_sim")
    if fee is not None:
        lines.append(L["fee"].format(fee=fee))
    w = rec.get("wall_ms")
    if w is not None:
        lines.append(L["wall"].format(w=w))
    en = L is LABELS_EN
    for k, u in (("cpu_saat", "cpu-hours" if en else "cpu-saat"),
                 ("ram_gb_sn", "GB-seconds RAM" if en else "GB-saniye RAM"),
                 ("io_mb", "MiB I/O")):
        if k in rec:
            lines.append(f"  {u:<19} : {rec[k]}")
    if "stdout_sha256" in rec:
        head = "Output fingerprint" if en else "Çıktı-parmak-izi"
        lines.append(f"  {head:<19} : sha256(stdout) = {rec['stdout_sha256'][:24]}…")
    dh = rec.get("delivery_hash")
    if isinstance(dh, dict):
        head = "Delivery binding" if en else "Teslim-bağı"
        note = ("(labeled - alg+hex pair, no assumed-equality)" if en
                else "(etiketli — alg+hex çifti, assumed-equality yok)")
        lines.append(f"  {head:<19} : {dh.get('alg', '?')} = {dh.get('hex', '')[:24]}… {note}")
    if "input_sha256" in rec:
        head = "Input binding (D11)" if en else "Girdi-bağı (D11)"
        lines.append(f"  {head:<19} : sha256(input) = {rec['input_sha256'][:24]}…")
    if "net_decl_sha256" in rec:
        head = "Net declaration" if en else "Ağ-beyanı (D12)"
        lines.append(f"  {head:<19} : net_decl_sha256 = {rec['net_decl_sha256'][:24]}…")
    if "net_mb" in rec:
        head = "Network traffic" if en else "Ağ-trafiği"
        note = "MiB (proxy counter)" if en else "MiB (proxy-sayaç)"
        lines.append(f"  {head:<19} : {rec['net_mb']} {note}")
    head = "Chain position" if en else "Zincir-yeri"
    lines.append(f"  {head:<19} : prev={rec.get('prev', '')[:16]}… → h={rec.get('h', '')[:16]}…")
    # türetilebilir-bağ-yeniden-hesabı:
    if rec.get("h"):
        no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
        exp = hashlib.sha256((rec.get("prev", "").encode() + jcs_bytes(no_h))).hexdigest()
        verdict = (L["ok"] if exp == rec["h"] else L["bad"])
        formula = ("sha256(prev ‖ jcs(record-minus-h,node_sig)) recomputed"
                   if en else "sha256(prev ‖ jcs(kayıt-minus-h,node_sig)) yeniden hesaplandı")
        head = "Chain integrity" if en else "Zincir-dürüstlüğü"
        lines.append(f"  {head}: h {verdict} ({formula})")
    return "\n".join(lines)

def jcs_bytes(obj):
    import io
    from tamga_validator import jcs
    return jcs(obj)

def explain_receipt(rec, L=None):
    en = L is LABELS_EN
    lines = ["== dx402 receipt (counterparty claim — only derivable relations are proven) =="] if en \
        else ["== dx402-receipt (karşı-taraf beyanı — yalnız türetilebilir-ilişkiler kanıtlanır) =="]
    pid = rec.get("paymentId", "")
    canon = ("(canonical 0x+64-lower OK)" if en else "(kanonik 0x+64-lower ✓)") if __import__("re").fullmatch(r"0x[0-9a-f]{64}", pid) else ("(NON-CANONICAL)" if en else "(KANONİK-DEĞİL)")
    lines.append(f"  {'Payment id' if en else 'Ödeme-kimliği':<16}: {pid[:26]}… {canon}")
    ch = rec.get("contentHash", "")
    if en:
        lines.append(f"  Content seal    : keccak(PLAINTEXT) = {ch[:26]}… — NEVER assume equality with served bytes (different populations; #3377-48c01ee)")
        ptr = rec.get("pointer", "")
        if ptr:
            lines.append(f"  Blob pointer    : {str(ptr)[:40]}… (CID = served-bytes seal — separate population)")
        lines.append(f"  Network         : {rec.get('network', '?')} · tx {rec.get('txHash', '')[:18]}…")
        lines.append(f"  Retention       : until={rec.get('retentionUntil', '?')} (epoch seconds)")
    else:
        lines.append(f"  İçerik-mührü    : keccak(PLAINTEXT) = {ch[:26]}… — served-baytlarla-eşitliği-VARSAYMA (farklı-popülasyonlar; #3377-48c01ee)")
        ptr = rec.get("pointer", "")
        if ptr:
            lines.append(f"  Blob-gösterici  : {str(ptr)[:40]}… (CID=served-bayt-mührü — ayrı-popülasyon)")
        lines.append(f"  Ağ              : {rec.get('network', '?')} · tx {rec.get('txHash', '')[:18]}…")
        lines.append(f"  Bekleme         : retentionUntil={rec.get('retentionUntil', '?')} (epoch-saniye)")
    return "\n".join(lines)

def main(argv):
    if not argv:
        print(__doc__)
        return 2
    L = LABELS_EN if "--en" in argv else None
    argv = [a for a in argv if a != "--en"]
    if argv[0] == "--charge":
        lines = (pathlib.Path(argv[1]).read_text(encoding="utf-8")).splitlines()
        rec = json.loads(lines[int(argv[2]) - 1])
        print(explain_charge(rec, L=L))
        return 0
    raw = json.loads(pathlib.Path(argv[0]).read_text(encoding="utf-8"))
    rec = raw.get("receipt", raw)
    if "paymentId" in rec or "contentHash" in rec:
        print(explain_receipt(rec, L=L))
    elif "op" in rec:
        print(explain_charge(rec, L=L))
    else:
        print("bilinmeyen-kayıt-şekli:", sorted(rec.keys())[:10])
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
