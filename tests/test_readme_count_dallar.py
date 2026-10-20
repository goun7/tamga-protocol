"""G42 README-pin: README'deki regression-oyuncagi ( run_all.sh) sonucu stale degil.

Tamga README'sindeki yetkili sayi `tests/run_all.sh` ciktisidir ( 242 PASS,
1 SKIP, 0 FAIL), pytest `tests/`-collect-only degil. Pin run_all.sh'i calistirip
RESULT satirindan PASS/SKIP/FAIL sayilarini cikarir ve README badge + son-suit
satiri ile karsilastirir.
"""
import io
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README = os.path.join(ROOT, "README.md")
RUN_ALL = os.path.join(ROOT, "tests", "run_all.sh")


def test_readme_runall_result_is_not_stale():
    readme = io.open(README, encoding="utf-8").read()
    res = subprocess.run(
        ["bash", RUN_ALL], cwd=ROOT, capture_output=True, text=True, timeout=1800,
    )
    out = res.stdout + res.stderr
    m = re.search(r"RESULT:\s*(\d+)\s*PASS,\s*(\d+)\s*SKIP,\s*(\d+)\s*FAIL", out)
    assert m, "run_all.sh RESULT-satiri-bulunamadi: %s" % out[-500:]
    p, s, f = int(m.group(1)), int(m.group(2)), int(m.group(3))
    stale = []
    for mm in re.finditer(r"(\d+)\s*PASS/(\d+)\s*SKIP/(\d+)\s*FAIL", readme):
        if (int(mm.group(1)), int(mm.group(2)), int(mm.group(3))) != (p, s, f):
            stale.append(mm.group(0))
    for mm in re.finditer(r"tests-(\d+)%2F(\d+)%20PASS", readme):
        if (int(mm.group(1)), int(mm.group(2))) != (p, p + s):
            stale.append(mm.group(0))
    assert not stale, (
        "README run_all-sonuclari stale: %s (taze run_all=%d PASS/%d SKIP/%d FAIL)"
        % (stale, p, s, f)
    )
