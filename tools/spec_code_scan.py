#!/usr/bin/env python3
"""
AT-046: tri-product spec↔code-divergence tarayıcısı.

Sester'ın-önerisinin-Tamga-tarafı: "üç ürünü birden tarayan tek checklist."
Her-normatif-kural-için-iki-yönü-de-ÜRETİM-ÜZERİNDE-ölçer:

  YÖN-A "kodda-uygulanıyor, spec'te-yazıyor-mu?"  → spec-coverage
  YÖN-B "spec'te-yazıyor, kodda-uygulanıyor-mu?"  → code-coverage

Sadece-biri-yeterli-değil: Sester-K0.1/Veridict-D12/Tamga-E1+A1-hepsi-aynı
sınıftı — **bir-tarafın-bilip-diğerinin-bilmediği-kural-ayrışma-yaratır.**

Çıktı: JSON — her-kural-için {id, rule, spec_documented, code_enforced,
                              evidence, divergence}
divergence-türleri:
  spec-only  → spec'te-yazıyor-kodda-yok  (K0.2/D12-sınıfı)
  code-only  → kodda-var-spec'te-yok      (K0.1/E1-sınıfı)
  aligned    → her-iki-yön-de-kanıtlandı
  untested   → ölçülemedi (ürün-kurulu-değil-vb.)

Kullanım:
    python3 tools/spec_code_scan.py [--format json|table]
"""
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO))


def _chain(records):
    """Üretim-JCS-ile-geçerli-zincir-üret (son-h:'i-döndürür)."""
    from tamga_canon import jcs
    out, prev = [], "0" * 64
    for rec in records:
        rec = dict(rec)
        rec["prev"] = prev
        no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
        rec["h"] = hashlib.sha256((prev + jcs(no_h).decode()).encode()).hexdigest()
        out.append(rec)
        prev = rec["h"]
    d = tempfile.mkdtemp()
    p = f"{d}/l.jsonl"
    Path(p).write_text("\n".join(json.dumps(r) for r in out) + "\n",
                       encoding="utf-8")
    return p


def _vmin(path):
    """Üretim-mini-verifier-ile-sonuç."""
    r = subprocess.run([sys.executable, str(REPO / "tamga_verify_mini.py"),
                        path], capture_output=True, text=True)
    return r.returncode == 0


def _vind(path):
    """Bağımsız-paket-verifier-ile-sonuç (üretimden-tamamen-ayrı)."""
    sys.path.insert(0, str(REPO / "tests" / "conformance"))
    from verify import verify_ledger
    ln, _ = verify_ledger(path)
    return ln == 0


# ---- KURAL-TABLOSU: (id, kural-açıklaması, spec'te-yazan-metin,
#                      RED-beklenen-kurcalama | None, GREEN-beklenen-geçerli)
RULES = [
    # spec_ref: spec-dosyasında-gerçekten-geçen-bir-dize (needle)
    ("L-3.1", "seq 1-based-aritmetik-artan",
     "`seq`-1-based-aritmetik-artan", "seq0", None),
    ("L-3.2", "prev-önceki-h'ye-eşit",
     "`prev`-önceki-kaydın-`h`-değerine-eşit", "prev_bad", None),
    ("L-3.3", "h-yeniden-hesapla-birebir",
     "`h`-yukarıdaki-formüle-göre-yeniden-hesaplandığında-birebir-aynı",
     "h_bad", None),
    ("L-3.4", "kayıt-JSON-nesnesi-olmalı",
     "kayıt-bir-JSON-nesnesi-olmalı", "not_obj", None),
    ("L-3.5", "satır ≤ 1 MiB",
     "satır-1-MiB'-i-aşamaz", "big_line", None),
    ("L-IJSON", "tamsayılar [−2^53, 2^53]-içinde",
     "I-JSON sınırı (RFC 7493 §2)", "big_int", None),
    ("L-4", "boş-zincir-geçerli-başlangıç",
     "Boş-zincir", None, "empty"),
    ("E1(a)", "op-değerleri-kısıtlanmamış (kasıtlı)",
     "(a) `op`-değerleri-KISITLANMAMIŞTIR", None, "unknown_op"),
    ("E1(b)", "bilinmeyen-ekstra-alana-izin (kasıtlı)",
     "bilinmeyen-ekstra-alanlara-izin", None, "extra_field"),
]


def _make(case):
    """Kural-kırım-veya-geçerli-vektör-üret."""
    if case == "empty":
        d = tempfile.mkdtemp()
        p = f"{d}/l.jsonl"
        Path(p).write_text("\n\n", encoding="utf-8")
        return p
    if case == "unknown_op":
        return _chain([{"seq": 1, "op": "BILINMEYEN", "amount": 1}])
    if case == "extra_field":
        return _chain([{"seq": 1, "op": "charge", "amount": 1, "ekstra": 1}])
    # kırım-vektörleri
    recs = [{"seq": 1, "op": "charge", "amount": 10, "agent_id": "a"},
            {"seq": 2, "op": "charge", "amount": 20, "agent_id": "a"}]
    if case == "seq0":
        recs = [{"seq": 0, "op": "charge", "amount": 1}, {"seq": 1, "op": "charge", "amount": 1}]
    p = _chain(recs)
    if case == "prev_bad":
        t = Path(p).read_text(encoding="utf-8").splitlines()
        r = json.loads(t[1])
        r["prev"] = "f" * 64
        t[1] = json.dumps(r)
        Path(p).write_text("\n".join(t) + "\n", encoding="utf-8")
    if case == "h_bad":
        t = Path(p).read_text(encoding="utf-8").splitlines()
        r = json.loads(t[1])
        r["h"] = "0" * 64
        t[1] = json.dumps(r)
        Path(p).write_text("\n".join(t) + "\n", encoding="utf-8")
    if case == "not_obj":
        Path(p).write_text("[1, 2]\n", encoding="utf-8")
    if case == "big_line":
        Path(p).write_text('{"seq": 1, "x": "' + "A" * (2 * 1024 * 1024) + '"}\n',
                           encoding="utf-8")
    if case == "big_int":
        Path(p).write_text('{"seq": 1, "amount": 123456789012345678901}\n',
                           encoding="utf-8")
    return p




def _anchor(results, sources):
    """ERRATUM-A1-formülüyle-geçerli-anchor-üret."""
    import hashlib as _h
    from sovereign_anchor import _canon as _ac
    return {"type": "sovereign-anchor", "version": "0.1",
            "products_present": sorted(results),
            "products_proved": [p for p in ("tamga","sester","veridict")
                                if results.get(p, {}).get("ok")],
            "all_proved": bool(results) and all(v.get("ok") for v in results.values()),
            "results": results, "sources": sources,
            "anchor_root": _h.sha256(_ac({"results": results,
                                          "sources": sources})).hexdigest()}

def _avmin(path):
    """Bağımsız-anchor-verifier (paket) — üretimden-tamamen-ayrı."""
    sys.path.insert(0, str(REPO / "tests" / "conformance"))
    from verify_anchor import verify_anchor
    return verify_anchor(path).get("ok")

def _anchor_case(case):
    """Anchor-kural-kırım/veya-geçerli-vektör-üret → yol-döndür."""
    d = tempfile.mkdtemp()
    p = f"{d}/a.json"
    good = {"tamga": {"ok": True, "verdict": "GREEN"},
            "sester": {"ok": True, "verdict": "GREEN"},
            "veridict": {"ok": True, "verdict": "GREEN"}}
    src = {"tamga_claim": "a", "sester_db": "b", "veridict_cert": "c"}
    if case == "a-clean":
        json.dump(_anchor(good, src), open(p, "w"), indent=1)
    elif case == "a-bad-type":
        a = _anchor(good, src); a["type"] = "x"; json.dump(a, open(p,"w"), indent=1)
    elif case == "a-bad-ver":
        a = _anchor(good, src); a["version"] = "9"; json.dump(a, open(p,"w"), indent=1)
    elif case == "a-bad-result-obj":
        json.dump(_anchor({}, src), open(p, "w"), indent=1)
    elif case == "a-root-tamper":
        a = _anchor(good, src); a["anchor_root"] = "f"*64
        json.dump(a, open(p,"w"), indent=1)
    elif case == "a-proved-missing":
        a = _anchor(good, src); a["products_proved"] = ["tamga"]
        json.dump(a, open(p,"w"), indent=1)
    elif case == "a-allproved-lie":
        a = _anchor(good, src); a["all_proved"] = False
        json.dump(a, open(p,"w"), indent=1)
    elif case == "a-no-sources":
        json.dump(_anchor(good, {}), open(p, "w"), indent=1)
    elif case == "a-sources-tamper":
        a = _anchor(good, src); a["sources"]["sester_db"] = "/tmp/sahte.db"
        json.dump(a, open(p,"w"), indent=1)
    return p

# ANCHOR-kural-tablosu: (id, açıklama, spec-needle, kırım/yeşil-case,
#                       beklenen: red|green|unverified)
ANCHOR_RULES = [
    ("A-5.1t", "type sovereign-anchor", '`type == "sovereign-anchor"`',
     "a-bad-type", "red"),
    ("A-5.1v", "version 0.1", '`version == "0.1"`',
     "a-bad-ver", "red"),
    ("A-5.2", "results-nesne + {ok,verdict}", "`results`-bir-nesne-olmalı",
     "a-bad-result-obj", "red"),
    ("A-5.3", "anchor_root-yeniden-hesap (A1-dahil)",
     "anchor_root    = sha256",
     "a-root-tamper", "red"),
    ("A-5.4", "products_proved-tutarlı", "`products_proved ==",
     "a-proved-missing", "red"),
    ("A-5.5", "all_proved-tutarlı", "`all_proved ==",
     "a-allproved-lie", "red"),
    ("A-5.6", "kaynaksız → UNVERIFIED", "UNVERIFIED-INDEPENDENTLY",
     "a-no-sources", "unverified"),
    ("A-A1", "sources-köke-girer (ERRATUM-A1)", "Erratum A1",
     "a-sources-tamper", "red"),
    ("A-0", "temiz-anchor-geçerli", "Üye-sıralaması",
     "a-clean", "green"),
]

def scan() -> dict:
    spec_ledger = (REPO / "tests" / "conformance" / "spec" /
                   "LEDGER-SPEC.md").read_text(encoding="utf-8")
    rows = []
    for rid, desc, spec_ref, red_case, green_case in RULES:
        # spec-coverage: kural-spec'te-belgeli-mi
        documented = spec_ref in spec_ledger
        # code-coverage: üretim-gerçekten-uyguluyor-mu
        if red_case:
            p = _make(red_case)
            code_ok = not _vmin(p)          # kırım-RED-gelmeli → enforced
            evidence = f"kırım-{red_case}: üretim-RED-beklendi={'EVET' if code_ok else 'HAYIR'}"
        elif green_case:
            p = _make(green_case)
            code_ok = _vmin(p)              # geçerli-GREEN-gelmeli
            evidence = f"geçerli-{green_case}-üretimde-GREEN={'EVET' if code_ok else 'HAYIR'}"
        else:
            code_ok = None
            evidence = "ölçülemedi"
        # bağımsız-verifier-paritesi (ayrışma-yoksa)
        if p:
            ind = _vind(p) if green_case else (not _vind(p) if red_case else None)
        else:
            ind = None
        div = "aligned" if (documented and code_ok) else (
            "spec-only" if documented and not code_ok else (
                "code-only" if not documented and code_ok else "untested"))
        rows.append({"id": rid, "rule": desc, "spec_ref": spec_ref,
                     "spec_documented": documented, "code_enforced": code_ok,
                     "independent_parity": ind, "divergence": div,
                     "evidence": evidence})
    # ---- ANCHOR-tarafı (ANCHOR-SPEC.md §5 + ERRATUM-A1) ----
    spec_anchor = (REPO / "tests" / "conformance" / "spec" /
                   "ANCHOR-SPEC.md").read_text(encoding="utf-8")
    for rid, desc, needle, case, expect in ANCHOR_RULES:
        documented = needle in spec_anchor
        p = _anchor_case(case)
        got = _avmin(p)
        if expect == "red":
            code_ok = not got        # kırım-RED-gelmeli
        elif expect == "green":
            code_ok = got            # geçerli-GREEN-gelmeli
        else:                        # unverified
            code_ok = got            # UNVERIFIED-dönmeli (ok=True)
        div = "aligned" if (documented and code_ok) else (
            "spec-only" if documented and not code_ok else (
                "code-only" if not documented and code_ok else "untested"))
        rows.append({"id": rid, "rule": desc, "spec_ref": needle,
                     "spec_documented": documented, "code_enforced": code_ok,
                     "independent_parity": code_ok, "divergence": div,
                     "evidence": f"anchor-{case}: beklenen={expect}"})
    n = lambda k: sum(1 for r in rows if r["divergence"] == k)
    return {"scanner": "AT-046-tri-product", "product": "tamga",
            "rules": rows,
            "summary": {"aligned": n("aligned"), "spec_only": n("spec-only"),
                        "code_only": n("code-only"), "untested": n("untested")},
            "errata_applied": ["E1(a)", "E1(b)"]}


def _table(d):
    w = d["summary"]
    lines = [f"  Ürün: {d['product']}  |  aligned={w['aligned']} "
             f"spec-only={w['spec_only']} code-only={w['code_only']} "
             f"untested={w['untested']}", "  " + "-" * 78]
    for r in d["rules"]:
        mark = {"aligned": "✓", "spec-only": "S", "code-only": "C",
                "untested": "?"}[r["divergence"]]
        lines.append(f"  [{mark}] {r['id']:7s} {r['rule'][:40]:40s} "
                     f"spec={'E' if r['spec_documented'] else '-'} "
                     f"kod={'E' if r['code_enforced'] else '-'}")
    lines.append("")
    lines.append("  E=evet | ✓=uyumlu | S=sadece-spec'te | "
                 "C=sadece-kodda | ?=ölçülemedi")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    fmt = "table"
    if "--format" in argv:
        fmt = argv[argv.index("--format") + 1]
    d = scan()
    if fmt == "json":
        print(json.dumps(d, ensure_ascii=False, indent=1))
    else:
        print(_table(d))
    # kapı: ölçülemeyen-veya-çift-yönlü-kanıtsız-kural-varsa-RED
    bad = [r for r in d["rules"] if r["divergence"] == "untested"]
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
