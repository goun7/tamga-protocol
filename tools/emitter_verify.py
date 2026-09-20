#!/usr/bin/env python3
"""
AT-049: emitter-doğrulama — 'listeli-ama-yanlış-emitter' sınıfının kilidi.

DERS (Sester-2026-09-20): ölü-girdi-taraması 'listeli-ama-yayılmayan'ı-yakalar,
ama **'listeli-ama-yanlış-emitter'ı-yakamaz.** Sester-örneği: settlement-için-
el-girilen-yol-facilitator_svc-gösteriyordu, gerçek-emitter-middleware.py-idi;
makine-RED-verdi, düzeltti.

Bu-aracın-üç-yükümlülüğü:
  (a) EMITTER-TABLOSU: her-op-değeri-için-GÜVENİLİR-BİR-üretim-kaynağı-tara
      (kod-içi-ledger-append-çağrıları + gerçek-jsonl-kanıt)
  (b) TUTARLILIK: tablodaki-her-op-ya-gerçek-emitter'a-sahip-olmalı-ya-RESERVE
  (c) TERS-YÖN: gerçek-ledger'da-görünen-her-op-ya-tabloda-olmalı-ya-RESERVE

İKİ-YÖN-DE-MAKİNE. Gözle-değil — bu-turun-bizdeki-kanıtı: ben-ilk-bakışta
charge/grant/fee-sandım, replace-canlı-ledger'da-gizliydi; migrate-net-ise
kodda-var-ama-gözlem-kümemde-yoktu.
"""
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO))

# Üretim-modülleri — burada-elle-listelenir-AMA-koddan-doğrulanır (aşağıda)
EMITTER_MODULES = ("tamga_runner.py", "tamga_bundle.py", "tamga.py")

# Kasıtlı-reserve (yayılmaz, ölü-girdi-taraması-yeşil)
RESERVED = {"fee"}


def _code_emitters() -> dict:
    """(a) Kod-içi-ledger-append-çağrılarından-op→kaynak-çıkart.

    **ÇAĞRI-İÇİ-İĞNE (Sester-2026-09-20-dersi):** iğne dosyada-var-mı-değil,
    bir `_ledger_append(...)`-çağrı-aralığın-İÇİNDE-olmalı (parantez-eşlemeli,
    çok-satırlı-append'leri-de-tanıyan).

    Dosyada-var-yöntemi-yetmezdi (Sester'ın-ilk-test_209'u-gibi): bir-yorumda,
    parametrede-veya-payload'da-da-geçebilir. Sester'ın-ördüğü-negatif-kontrol:
      # "x"           → RED (yorum, çağrı-aralığında-değil)
      def f(op="x")   → RED (parametre, çağrı-değil)
      _ledger_append(lp, {"op": "x"}) → GREEN (gerçek-çağrı-içi)
    """
    out = {}
    for mod in EMITTER_MODULES:
        p = REPO / mod
        if not p.exists():
            continue
        lines = p.read_text(encoding="utf-8",
                           errors="replace").splitlines()
        for i, line in enumerate(lines, 1):
            if not re.search(r'_append\s*\(', line):
                continue
            # çok-satırlı-çağrı-aralığı: kapanış-parantezi-dengeyi-bulana-kadar
            blob, depth = "", 0
            for j in range(i - 1, min(i + 12, len(lines))):
                blob += " " + lines[j]
                depth += lines[j].count("(") - lines[j].count(")")
                if depth <= 0 and j > i - 1:
                    break
            # çağrı-aralığı-içinde-{"op": "deger"}-dict-literal-ara
            for m in re.finditer(r'\{\s*"op":\s*"([a-zçğıöşü][a-zçğıöşü0-9-]*)"',
                                 blob):
                op = m.group(1)
                out.setdefault(op, []).append(f"{mod}:{i}")
    return out


def _test_callin_needle() -> list:
    """Negatif-kontrol: üç-vasıtayı-da-doğru-sınıflandırıyor-mu (Sester'ın-ördüğü)."""
    import tempfile, pathlib
    cases = [
        ("yorum", '# "op": "x-yorum"\\n', []),
        ("parametre", 'def f(op="x-param"): pass\\n', []),
        ("gercek-append", '_ledger_append(lp, {"op": "x-gercek"})\\n',
         ["x-gercek"]),
        ("cok-satirli-append",
         '_ledger_append(lp,\\n    {"op": "x-cok"},\\n    "diger")\\n',
         ["x-cok"]),
    ]
    fails = []
    orig = REPO
    for name, src, expect in cases:
        d = tempfile.mkdtemp()
        (pathlib.Path(d) / "tamga_runner.py").write_text(src, encoding="utf-8")
        globals()["REPO"] = pathlib.Path(d)
        got = sorted(_code_emitters())
        globals()["REPO"] = orig
        if got != sorted(expect):
            fails.append(f"{name}: got={got} expected={sorted(expect)}")
    return fails


def _ledger_evidence() -> dict:
    """Gerçek-kanıt: op→görüldüğü-Tamga-ledger-dosya-sayısı.

    DİKKAT (false-positive-tuzağı, Sester-service.py:104-aynısı): repo-dışı-
    DSH-oturum-günlükleri-de-'op'-benzeri-anahtarlar-taşır. __pycache__/
    session.v3.jsonl-bir-Tamga-ledger'ı-DEĞILDIR ('type':'session'-kayıtları).
    İlk-taramam-'replace'-değerini-orada-yanlışlıkla-buldu. Çözüm: yalnızca
    'seq'+'prev'+'h'-üçlüsünü-taşıyan-satırları-ledger-kabul-et.

    DİKKAT-2 (Veridict-canary-2026-09-20-aynası): seq+prev+h-üçlüsü-test-
    fixture'leri-de-üretir! tests/,-altındaki-ledger'lar-gerçek-üretim-kanıtı
    DEĞİLDİR — onları-üretim-kanıtı-saymak-Veridict'in-canary-sayım-hatasının
    bire-bizdeki-aynası (sayım-kanıtın-girmediği-yerden-geliyordu). Artık
    fixture-ve-üretim-ayrı-tutarlı.
    """
    out = {}
    for p in REPO.rglob("*.jsonl"):
        if ".venv" in p.parts:
            continue
        sp = str(p)
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in txt.splitlines():
            # GERÇEK-Tamga-ledger-satırı: seq+prev+h-üçlüsü-olmalı
            if not ("\"seq\"" in line and "\"prev\"" in line and "\"h\"" in line):
                continue
            m = re.search(r'"op":\s*"([a-zçğıöşü][a-zçğıöşü0-9-]*)"', line)
            if m:
                out.setdefault(m.group(1), set()).add(sp)
    return {k: len(v) for k, v in out.items()}


def corpus_ops(production_only: bool = False) -> set:
    """Katman-3: corpus'ta-görünen-op'ler. production_only=True-ise-yalnızca
    üretim-ledger'ları (test-fixture'leri-hariç).

    Veridict-canary-2026-09-20-aynası: seq+prev+h-üçlüsü-FIXTURE'ler-de-üretir;
    fixture-kanıtı-üretim-erişilebilirliğini-KANITLAMAZ."""
    out = set()
    for p in REPO.rglob("*.jsonl"):
        if ".venv" in p.parts:
            continue
        sp = str(p)
        if production_only and any(t in sp for t in
                                   ("tests/", "test-", "fixture", ".dbg")):
            continue
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in txt.splitlines():
            if not ("\"seq\"" in line and "\"prev\"" in line and "\"h\""):
                continue
            m = re.search(r'"op":\s*"([a-zçğıöşü][a-zçğıöşü0-9-]*)"', line)
            if m:
                out.add(m.group(1))
    return out


def scan() -> dict:
    code = _code_emitters()
    seen = _ledger_evidence()
    spec = _read_spec()
    problems = []
    # (b) tablodaki-her-op-emitter'a-sahip-olmalı-veya-reserve
    all_ops = set(code) | set(seen) | RESERVED
    for op in sorted(all_ops):
        if op in RESERVED:
            continue
        if op not in code and op not in seen:
            problems.append(f"[{op}] ne-kodda-ne-ledgerda — hayalet-girdi")
        elif op not in code:
            # ledgerda-var-ama-kod-emitter'ı-yok → dış-kaynak-gürültüsü
            problems.append(
                f"[{op}] ledger-kanıtı-var-ama-ÜRETİM-KODUNDA-emitter-yok "
                f"({seen[op]}-dosya) — yanlış-emitter-veya-tarihçe")
        elif op not in spec:
            # CODE-ONLY (E1(c)-sınıfı): emitter-var-ama-spec'te-yazılı-değil
            problems.append(
                f"[{op}] ÜRETİM-KODUNDA-emitter-var-({code[op][0]})-ama-SPEC'TE-"
                f"yazılı-değil — gerçek-E1(c)-sınıfı-kod-only")
    return {"emitters": {k: v for k, v in code.items()},
            "ledger_evidence": seen,
            "reserved": sorted(RESERVED),
            "problems": problems,
            "ops_total": len(all_ops)}


def _read_spec() -> str:
    p = REPO / "tests" / "conformance" / "spec" / "LEDGER-SPEC.md"
    return p.read_text(encoding="utf-8") if p.exists() else ""


def main(argv: list[str]) -> int:
    d = scan()
    if d["problems"]:
        print("EMITTER-DOĞRULAMA-BAŞARISIZ:")
        for p in d["problems"]:
            print(f"  ✗ {p}")
        return 1
    print(f"  {d['ops_total']}-op: hepsinin-üretim-emitter'ı-kanıtlandı")
    for op, srcs in sorted(d["emitters"].items()):
        print(f"    {op:14s} ← {srcs[0]}" + (" (+)" if len(srcs) > 1 else ""))
    if d["reserved"]:
        print(f"  reserved: {d['reserved']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
