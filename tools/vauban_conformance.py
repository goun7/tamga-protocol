#!/usr/bin/env python3
"""tools/vauban_conformance.py — RFC-8785 JCS çapraz-kanıt koşucusu (Vauban süiti).

Vauban Research'ın x402-stark-receipts-conformance vektör-seti, RFC-8785'in 8-dilde
doğrulanmış-referans-matrisine-sahip. Bu-koşucu-Tamga'nın-tam-stdlib-JCS'ini
(tamga_validator.jcs) o-vektörlere-karşı-bayt-birebir-sınar:

  Aile-1 (stark):      receipt_core → JCS-baytları → sha256-özü (ikisi-de-sabitlenmiş)
  Aile-2 (delegation): delegation_grant → JCS-baytları (bayt-esas)

Kullanım:
  python3 tools/vauban_conformance.py <süit-dizini>   # klonsuz-çalışmaz; vectors/ aranır
  python3 tools/vauban_conformance.py --selftest      # iç-KAT: bilinen-3-vektör-özü

Kanıt-kültürü-notu: bu-koşucu-Vauban-kanıtını-Tamga-iddia-doğrulaması-için-KULLANIR;
ters-yönü-(onların-süiti-bizim-araçları-dogruylamaz)-ayrı-taraftır. Süit-DIŞARIDAN
klonlanır;-repo-içine-kopyalanmaz-(provenans-disiplini:-donmuş-kanıt-.evidence altında).
"""
import base64
import hashlib
import json
import pathlib
import sys

_ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT))
from tamga_validator import jcs  # noqa: E402


def run_suite(suite_dir: pathlib.Path) -> int:
    vectors = suite_dir / "vectors"
    if not vectors.is_dir():
        print(f"ERR: {vectors} bulunamadı — süiti-klonlayın:", file=sys.stderr)
        print("  git clone --depth 1 https://github.com/vauban-org/x402-stark-receipts-conformance", file=sys.stderr)
        return 2
    total = passed = red_ok = skipped = 0
    for fam in sorted(vectors.iterdir()):
        if not fam.is_dir():
            continue
        for f in sorted(fam.glob("*.json")):
            total += 1
            v = json.loads(f.read_text())
            core = v.get("receipt_core") or v.get("delegation_grant")
            jkey = ("expected_jcs_bytes_b64" if "receipt_core" in v
                    else "expected_delegation_grant_jcs_bytes_b64")
            dkey = "expected_core_digest" if "receipt_core" in v else None
            if not core or jkey not in v:
                # RED-vektörleri: kurcalama/digest-sapması-sabitlenmiş-FAIL-durumları —
                # baytları-YENİDEN-ÜRETEMEYIZ-(kurcalama-yasak);-sabitlenmiş-divergent-digest'in
                # VARLIĞINI-doğrularız (iddia-doğrulama-değil,-şekil-teyidi)
                if v.get("expected_result") in ("FAIL", "FAIL_AT_VERIFIER") and "expected_divergent_digest" in v:
                    red_ok += 1
                    print(f"  RED-vec kabul: {f.name} — divergent-digest-sabitlenmiş")
                else:
                    skipped += 1
                    print(f"  SKIP: {f.name} (core/jcs-bytes-yok)")
                continue
            ours = jcs(core)
            ours = ours if isinstance(ours, bytes) else ours.encode()
            exp = base64.b64decode(v[jkey])
            j_ok = ours == exp
            d_ok = True
            if dkey and v.get(dkey):
                d_ok = ("sha256:" + hashlib.sha256(ours).hexdigest()) == v[dkey]
            status = "PASS" if (j_ok and d_ok) else "FAIL"
            if status == "PASS":
                passed += 1
            print(f"  {status}: {fam.name}/{f.name} jcs-bytes={j_ok} digest={d_ok}")
    print(f"RESULT: {passed} PASS-byte-exact, {red_ok} RED-vec-accepted, {skipped} SKIP, {total} total")
    return 0 if (passed + red_ok + skipped) == total and passed >= 5 else 1


def selftest() -> int:
    # İç-KAT: RFC-8785 §3.2.3 yayımlanmış-özler (boş-nesne / kontrol-karakterleri / unicode+array)
    cases = [
        ({}, "{}"),
        ({"\u20ac": "Euro Sign", "\r": "Carriage Return", "\n": "Line Feed", "a": "A"},
         '{"\\n":"Line Feed","\\r":"Carriage Return","a":"A","\u20ac":"Euro Sign"}'),
        ({"b": [1, 2], "a": "\u00e9"}, '{"a":"\u00e9","b":[1,2]}'),
    ]
    bad = 0
    for obj, want in cases:
        got = jcs(obj).decode("utf-8")
        if got != want:
            print(f"SELFTEST-FAIL: {obj!r} → {got!r} ≠ {want!r}")
            bad += 1
    if bad:
        return 1
    print(f"selftest: {len(cases)}/{len(cases)} RFC-8785-öz-OK")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    if len(argv) != 2:
        print(__doc__)
        return 2
    return run_suite(pathlib.Path(argv[1]))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
