#!/usr/bin/env python3
"""readme_stats.py — README'e giren HER sayıyı test çıktısından üretir.

Portföyün tekrar-eden-zayıflığı: README'lerde elle-yazılmış test-sayıları
(233/233, 47/47, 227, 83-88) gerçek suite çıktısı ile uyumsuz. Bu script
sayıları **kaynaktan** çıkarır — elle bakımı yok.

Kullanım:
    python3 scripts/readme_stats.py                    # tüm istatistikler (JSON)
    python3 scripts/readme_stats.py --key suite_pass   # tek değer
    python3 scripts/readme_stats.py --badge            # README badge string'i

Kaynaklar (elle-yazım-YOK):
    1. tests/run_all.sh          — kontrol-çağrı-sayısı (PASS= PASS+1 her çağrıda)
    2. .evidence/REGRESYON/...    — en-son suite log'undan RESULT: satırı
    3. tests/at*.sh dosya sayısı  — test-kitaplığı büyüklüğü
"""
import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RUN_ALL = ROOT / "tests" / "run_all.sh"
EVIDENCE = ROOT / ".evidence" / "REGRESYON"


def count_suite_controls() -> int:
    """run_all.sh içindeki toplam kontrol() + bash-tests çağrısı = PASS-sayısının
    üst-sınırı. Gerçek değer log'dan gelir (SKIP'ler düşer)."""
    txt = RUN_ALL.read_text(encoding="utf-8")
    # her 'kontrol ...' satırı bir PASS-artışı; her 'bash tests/at...' bir test
    kontrol = len(re.findall(r"^  kontrol ", txt, re.M))
    return kontrol


def latest_suite_result():
    """En-son REGRESYON log'undan RESULT: satırını parse eder.
    Gerçek PASS/SKIP/FAIL — elle-yazım değil, koşum-çıktısı."""
    if not EVIDENCE.exists():
        return None
    logs = sorted(EVIDENCE.rglob("run_all-*.log"))
    for lg in reversed(logs):
        try:
            txt = lg.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        m = re.search(r"RESULT:\s*(\d+)\s*PASS,\s*(\d+)\s*SKIP,\s*(\d+)\s*FAIL", txt)
        if m:
            return {
                "log": str(lg.relative_to(ROOT)),
                "pass": int(m.group(1)),
                "skip": int(m.group(2)),
                "fail": int(m.group(3)),
            }
    return None


def count_test_files() -> int:
    """tests/at*.sh kitaplığı büyüklüğü."""
    return len(list((ROOT / "tests").glob("at[0-9]*.sh")))


def badge_string() -> str:
    """README badge'i için: tests-N/N PASS."""
    r = latest_suite_result()
    if not r:
        return "tests-? (suite-log-yok)"
    total = r["pass"] + r["skip"] + r["fail"]
    return f"tests-{r['pass']}%2F{total}%20PASS"


def all_stats() -> dict:
    r = latest_suite_result()
    return {
        "suite_result": r,
        "suite_controls_static": count_suite_controls(),
        "test_files": count_test_files(),
        "badge": badge_string(),
    }


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--key", help="tek değer: suite_result / test_files / badge")
    ap.add_argument("--badge", action="store_true", help="README badge string")
    ap.add_argument("--check", action="store_true",
                    help="README'lerdeki elle-yazılmış sayıları denetle (rc1 = uyumsuz)")
    ap.add_argument("--update", action="store_true",
                    help="README'lerdeki test-sayılarını suite-log'undan üretilen değerle değiştir")
    a = ap.parse_args(argv)

    if a.badge:
        print(badge_string())
        return 0

    st = all_stats()
    if a.key:
        print(json.dumps(st.get(a.key), ensure_ascii=False))
        return 0

    print(json.dumps(st, ensure_ascii=False, indent=2))

    if a.check:
        # README'lerde elle-yazılmış test-badge'lerini ara
        bad = []
        for rf in ("README.md", "README.tr.md"):
            p = ROOT / rf
            if not p.exists():
                continue
            txt = p.read_text(encoding="utf-8")
            for m in re.finditer(r"badge/tests-(\d+)%2F(\d+)%20PASS", txt):
                got_pass, got_total = int(m.group(1)), int(m.group(2))
                real = st["suite_result"]
                if real and (got_pass != real["pass"] or got_total != real["pass"] + real["skip"] + real["fail"]):
                    bad.append(f"{rf}: badge {got_pass}/{got_total} ≠ gerçek {real['pass']}/{real['pass']+real['skip']+real['fail']}")
        if bad:
            print("UYUMSUZ:", "; ".join(bad), file=sys.stderr)
            return 1
        print("README-badge'leri suite-çıktısı ile uyumlu")

    if a.update:
        # README'lerdeki elle-yazılmış test-sayılarını üretilen-değerle-değiştir
        real = st["suite_result"]
        if not real:
            print("HATA: suite-log yok — README güncellenemez", file=sys.stderr)
            return 2
        total = real["pass"] + real["skip"] + real["fail"]
        badge = f"tests-{real['pass']}%2F{total}%20PASS"
        controls = f"{real['pass']}/{total} controls — {real['skip']} SKIP, {real['fail']} FAIL"
        n = 0
        for rf in ("README.md", "README.tr.md"):
            p = ROOT / rf
            if not p.exists():
                continue
            t = p.read_text(encoding="utf-8")
            t2, c1 = re.subn(r"badge/tests-\d+%2F\d+%20PASS", f"badge/{badge}", t)
            # SADECE sayıları-değiştir, çevreleyen-metne-DOKUNMA:
            # "N/N controls" → sayılar (ardından gelen-metin-ne-ise-kalsın)
            t2, c2 = re.subn(r"(#\s*)\d+/\d+(?=\s+controls)", r"\g<1>" + f"{real['pass']}/{total}", t2)
            # "0 SKIP, 0 FAIL" / "0 SKIP / 0 FAIL" → gerçek-değerler
            t2, c3 = re.subn(r"\d+ SKIP, \d+ FAIL",
                             f"{real['skip']} SKIP, {real['fail']} FAIL", t2)
            t2, c4 = re.subn(r"\d+ SKIP / \d+ FAIL",
                             f"{real['skip']} SKIP / {real['fail']} FAIL", t2)
            # → N/N (TR-README biçimi)
            t2, c5 = re.subn(r"(→\s*)\d+/\d+(?=\s+controls)", r"\g<1>" + f"{real['pass']}/{total}", t2)
            # TR-biçimleri: "N/N kontrol" ve "→ N/N —" (TR-README)
            t2, c6 = re.subn(r"(#\s*)\d+/\d+(?=\s+kontrol)", r"\g<1>" + f"{real['pass']}/{total}", t2)
            t2, c7 = re.subn(r"(→\s*)\d+/\d+(?=\s+[—-])", r"\g<1>" + f"{real['pass']}/{total}", t2)
            if c1 or c2 or c3 or c4 or c5 or c6 or c7:
                p.write_text(t2, encoding="utf-8")
                n += c1 + c2 + c3 + c4 + c5 + c6 + c7
                print(f"{rf}: {c1} badge + {c2}/{c3}/{c4}/{c5}/{c6}/{c7} sayı-güncellendi")
        print(f"toplam {n} yer güncellendi → {controls}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
