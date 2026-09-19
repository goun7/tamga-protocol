#!/usr/bin/env python3
"""
AT-040: spec'ten-tek-başına-yazılmış bağımsız verifier (parite-testi-için).

KAYNAK: docs/ARCHITECTURE.md:42 (normatif):
    Ledger | tamga-sim/1 JSONL | each record: seq (1-based) + prev + h = sha256(prev ‖ jcs(record))

BU DOSYA üretim kodundan TAMAMEN BAĞIMSIZDIR. Hiçbir tamga_* modülü, hiçbir
tools/ modülü içe aktarılmaz. RFC 8785 (JCS) canonicalization burada ikinci
kez sıfırdan uygulanır — amacımız, üretim verifier'ının (tamga_verify_mini.py)
spec'in KENDİSİNE sadık olduğunu kanıtlamaktır, kodumuza değil.

Parite-testi (tests/at040_spec_parity.sh) bunu kullanır:
  - temiz fixture'larda: bağımsız == üretim (ikisi GREEN)
  - 6 kurcalama mutasyonunda: bağımsız == üretim (ikisi RED, aynı-kırık-satır)

Veridict'in tests/test_spec_verifier_parity.py örneğinin Tamga karşılığı.

Kullanım:
    python3 tools/spec_verifier_independent.py <ledger.jsonl>
"""
import hashlib
import json
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# RFC 8785 JCS — bağımsız ikinci uygulama (üretimdeki tamga_canon.jcs'ten
# bağımsız olarak bu dosyada sıfırdan yazılmıştır).
# ---------------------------------------------------------------------------

_INF_POS = b"\xc0\x00\x00\x00\x00\x00\x00\x00"      # +Inf little-endian
_INF_NEG = b"\xff\xff\xff\xff\xff\xff\xff\xff"      # -Inf


def _es_number(x: float) -> str:
    """RFC 8785 §6.1: en-kısa-benzersiz ondalık gösterim (üretim-tamga_canon
    ile parite: Python repr'inin bilimsel-gösterimini RFC biçimine getir)."""
    if x != x:                      # NaN
        raise ValueError("NaN JCS'de temsil edilemez")
    if x == float("inf"):
        return "1e+999"
    if x == float("-inf"):
        return "-1e+999"
    # tamsayı-değerler: ondalıksız (3.0 → "3", 0.0 → "0")
    if x == int(x) and abs(x) < 1e21:
        return str(int(x))
    s = repr(x)
    if "e" in s or "E" in s:
        mant, _, exp = s.partition("e")
        # mantistondan-tesessüf-eden-sıfırları-ve-noktayı-temizle
        if "." in mant:
            mant = mant.rstrip("0").rstrip(".")
        e = int(exp)
        # RFC 8785 §6.1: üs-pozitifse "e+" biçimi (üretim-ile-parite: 1e+21)
        es = f"e{e}" if e < 0 else f"e+{e}"
        return f"{mant}{es}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s


def _enc_string(s: str) -> str:
    """RFC 8785 §2.7: kaçış-sıraları küçük-tamsayılar-önce."""
    out = ['"']
    for ch in s:
        cp = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\b":
            out.append("\\b")
        elif ch == "\f":
            out.append("\\f")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif cp < 0x20:
            out.append("\\u%04x" % cp)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def _encode(o, out: list) -> None:
    """RFC 8785 §3: tip-önceliği — false/null/true → sayı → dize → dizi → nesne."""
    if o is False:
        out.append("false")
    elif o is None:
        out.append("null")
    elif o is True:
        out.append("true")
    elif isinstance(o, bool):
        out.append("true" if o else "false")
    elif isinstance(o, int):
        # RFC 7493 (I-JSON) §2: tamsayılar [−2^53, 2^53] içinde olmalı —
        # üretim tamga_canon.py ile parite: aralık-dışı RED (sayı→dize-istiyor)
        if not (-(2**53) <= o <= 2**53):
            raise ValueError(
                "ijson_number_out_of_range: int outside [−2^53, 2^53] "
                "is not in the I-JSON subset (RFC 7493); serialize as a "
                "string or scale the unit instead")
        out.append(str(o))
    elif isinstance(o, float):
        out.append(_es_number(o))
    elif isinstance(o, str):
        out.append(_enc_string(o))
    elif isinstance(o, (list, tuple)):
        out.append("[")
        first = True
        for item in o:
            if not first:
                out.append(",")
            first = False
            _encode(item, out)
        out.append("]")
    elif isinstance(o, dict):
        # §2.2: üye-adları UTF-16-kod-birim-dizisi olarak artan-sıralanır
        out.append("{")
        items = sorted(o.items(), key=lambda kv: kv[0].encode("utf-16-le"))
        first = True
        for k, v in items:
            if not isinstance(k, str):
                raise TypeError("nesne anahtarı dize olmalı")
            if not first:
                out.append(",")
            first = False
            out.append(_enc_string(k))
            out.append(":")
            _encode(v, out)
        out.append("}")
    else:
        raise TypeError(f"JCS-desteklenmeyen-tip: {type(o).__name__}")


def jcs(obj) -> bytes:
    out: list = []
    _encode(obj, out)
    return "".join(out).encode("utf-8")


# ---------------------------------------------------------------------------
# Bağımsız ledger doğrulaması — ARCHITECTURE.md:42'den
# ---------------------------------------------------------------------------

def verify_ledger(ledger_path: str) -> tuple[int, str]:
    """(0, reason) GREEN — (kırık-satır-no, reason) RED.

    Normatif-kural (spec'ten, koddan-değil):
      seq 1-based-artan; prev zincirin-önceki-h'si (ilk-kayıt: 64 sıfır);
      h == sha256(prev ‖ jcs(kayıt-h-ve-imza-harici)).
    """
    try:
        raw = Path(ledger_path).read_text(encoding="utf-8")
    except OSError as e:
        return 0, f"io_error: {e}"
    prev = "0" * 64
    n = 0
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        n += 1
        try:
            rec = json.loads(line)
        except ValueError:
            return n, "unparseable line"
        if not isinstance(rec, dict):
            return n, "record is not a JSON object"
        # kurcalama-koruması: devasa-satır (bomba)
        if len(line.encode("utf-8")) > 1 << 20:
            return n, "line > 1 MiB — bomba-satırı"
        if rec.get("seq") != n:
            return n, f"seq beklenen {n} ama {rec.get('seq')}"
        if rec.get("prev") != prev:
            return n, f"prev zincirle uyumsuz (beklenen {prev[:10]}…)"
        no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
        expected = hashlib.sha256(
            (rec.get("prev", "") + jcs(no_h).decode("utf-8")).encode("utf-8")
        ).hexdigest()
        if rec.get("h") != expected:
            return n, f"h uyuşmaz (bağımsız {expected[:10]}…)"
        prev = rec["h"]
    if n == 0:
        return 0, "empty chain"
    return 0, "ok"


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("kullanim: spec_verifier_independent.py <ledger.jsonl>", file=sys.stderr)
        return 2
    line_no, reason = verify_ledger(argv[1])
    result = {
        "verifier": "spec-independent (AT-040)",
        "ok": line_no == 0 and reason == "ok",
        "broken_line": line_no or None,
        "reason": reason,
    }
    print(json.dumps(result, ensure_ascii=False, indent=1))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
