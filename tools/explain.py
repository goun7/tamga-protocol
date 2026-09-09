#!/usr/bin/env python3
"""explain — bir receipt/charge kaydını insan dilline çevir (RFC-003 D5).

Bilgi-ekleme YOK: yalnız kayıttaki alanları etiketli-paragrafa döker. Türetilebilir
ilişkiler (input-bağı, delivery-bağı) yeniden HESAPLANIR — assumed-equality yok.

Usage:
  python3 tools/explain.py <receipt.json>            # dx402-receipt veya charge-kaydı
  python3 tools/explain.py --charge <ledger.jsonl> 2  # zincir-N-kayıt
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

def explain_charge(rec, label="charge"):
    lines = [f"== {label} kaydı (seq {rec.get('seq', '?')}) =="]
    lines.append(f"  İş-sahibi       : {rec.get('pkg', '?')} (oturum {rec.get('session', '?')})")
    fee = rec.get("fee_sim")
    if fee is not None:
        lines.append(f"  Ücret (sim)     : {fee} birim — simnet; gerçek-değer hareketi Faz-4'e kadar yok")
    w = rec.get("wall_ms")
    if w is not None:
        lines.append(f"  Duvar-süresi    : {w} ms")
    for k, u in (("cpu_saat", "cpu-saat"), ("ram_gb_sn", "GB-saniye RAM"), ("io_mb", "MiB I/O")):
        if k in rec:
            lines.append(f"  {u:<15} : {rec[k]}")
    if "stdout_sha256" in rec:
        lines.append(f"  Çıktı-parmak-izi: sha256(stdout) = {rec['stdout_sha256'][:24]}…")
    dh = rec.get("delivery_hash")
    if isinstance(dh, dict):
        lines.append(f"  Teslim-bağı     : {dh.get('alg', '?')} = {dh.get('hex', '')[:24]}… "
                     f"(etiketli — alg+hex çifti, assumed-equality yok)")
    if "input_sha256" in rec:
        lines.append(f"  Girdi-bağı (D11): sha256(input) = {rec['input_sha256'][:24]}…")
    if "net_decl_sha256" in rec:
        lines.append(f"  Ağ-beyanı (D12) : net_decl_sha256 = {rec['net_decl_sha256'][:24]}…")
    if "net_mb" in rec:
        lines.append(f"  Ağ-trafiği      : {rec['net_mb']} MiB (proxy-sayaç)")
    lines.append(f"  Zincir-yeri     : prev={rec.get('prev', '')[:16]}… → h={rec.get('h', '')[:16]}…")
    # türetilebilir-bağ-yeniden-hesabı:
    if rec.get("h"):
        no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
        exp = hashlib.sha256((rec.get("prev", "").encode() + jcs_bytes(no_h))).hexdigest()
        lines.append(f"  Zincir-dürüstlüğü: h {'DOĞRULANDI' if exp == rec['h'] else 'EŞLEŞMİYOR'} "
                     f"(sha256(prev ‖ jcs(kayıt-minus-h,node_sig)) yeniden hesaplandı)")
    return "\n".join(lines)

def jcs_bytes(obj):
    import io
    from tamga_validator import jcs
    return jcs(obj)

def explain_receipt(rec):
    lines = ["== dx402-receipt (karşı-taraf beyanı — yalnız türetilebilir-ilişkiler kanıtlanır) =="]
    pid = rec.get("paymentId", "")
    lines.append(f"  Ödeme-kimliği   : {pid[:26]}… {'(kanonik 0x+64-lower ✓)' if __import__('re').fullmatch(r'0x[0-9a-f]{64}', pid) else '(KANONİK-DEĞİL)'}")
    ch = rec.get("contentHash", "")
    lines.append(f"  İçerik-mührü    : keccak(PLAINTEXT) = {ch[:26]}… — served-baytlarla-eşitliği-VARSAYMA "
                 "(farklı-popülasyonlar; #3377-48c01ee)")
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
    if argv[0] == "--charge":
        lines = (pathlib.Path(argv[1]).read_text(encoding="utf-8")).splitlines()
        rec = json.loads(lines[int(argv[2]) - 1])
        print(explain_charge(rec))
        return 0
    raw = json.loads(pathlib.Path(argv[0]).read_text(encoding="utf-8"))
    rec = raw.get("receipt", raw)
    if "paymentId" in rec or "contentHash" in rec:
        print(explain_receipt(rec))
    elif "op" in rec:
        print(explain_charge(rec))
    else:
        print("bilinmeyen-kayıt-şekli:", sorted(rec.keys())[:10])
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
