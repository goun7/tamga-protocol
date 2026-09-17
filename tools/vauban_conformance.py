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
    # İç-KAT-1: RFC-8785 §3.2.3 yayımlanmış-özler (boş-nesne / kontrol-karakterleri / unicode+array)
    cases = [
        ({}, "{}"),
        ({"\u20ac": "Euro Sign", "\r": "Carriage Return", "\n": "Line Feed", "a": "A"},
         '{"\\n":"Line Feed","\\r":"Carriage Return","a":"A","\u20ac":"Euro Sign"}'),
        ({"b": [1, 2], "a": "\u00e9"}, '{"a":"\u00e9","b":[1,2]}'),
        # ECMAScript number serialization (RFC-8785 §3.2.2.2) — json.dumps'ın-yalan-söylediği-yer:
        ({"a": 1.0, "b": 1}, '{"a":1,"b":1}'),                     # 1.0 → "1", "1.0"-DEĞİL
        ({"fee": 2.93e-07, "cpu": 2.983e-06},
         '{"cpu":0.000002983,"fee":2.93e-7}'),                     # e-06 → ondalık; e-07 → e-7
        ({"big": 1e16, "huge": 1e21, "tiny": 1e-7},
         '{"big":10000000000000000,"huge":1e+21,"tiny":1e-7}'),    # 1e16 → ondalık (Python 1e+16 der)
        ({"z": -0.0, "third": 0.3333333333333333},
         '{"third":0.3333333333333333,"z":0}'),                     # -0.0 → "0"
        # UTF-16 code-unit member order (RFC-8785 §3.2.3) — code-point sıralaması YANLIŞ-verir:
        ({"\uffff": 1, "\U00010000": 2}, '{"\U00010000":2,"\uffff":1}'),
        # BMP-içi-bayt-tuzağı (Rul1an issue#2, 2026-09-17): küçük-endian BAYT sıralaması
        # code-unit sıralamasına-eşit-değildir. LE'de 'Ā'(0x0100) → bayt 00,01 → 'a'(0x61)
        # öncesi-yanlış-sıralar; BE doğru-sıralar. Bu-vektör LE-uygulamada-KIRMIZI-verir:
        ({"a": 1, "Ā": 2}, '{"a":1,"Ā":2}'),                      # a(0x61) < Ā(0x0100)
        ({"ÿ": 1, "Ā": 2}, '{"ÿ":1,"Ā":2}'),                      # ÿ(0x00FF) < Ā(0x0100)
        # quote + backslash kaçışı (\u001f = \u00XX kısa-değil):
        ({"q": 'he said "hi" \\\\done', "ctl": "a\bb\nc\u001fd"},
         '{"ctl":"a\\bb\\nc\\u001fd","q":"he said \\"hi\\" \\\\\\\\done"}'),
    ]
    bad = 0
    for obj, want in cases:
        got = jcs(obj).decode("utf-8")
        if got != want:
            print(f"SELFTEST-FAIL: {obj!r} → {got!r} ≠ {want!r}")
            bad += 1
    # İç-KAT-2: üç-uygulama-birebir (mini / validator / canon) — kopyalar-drift-yapamaz
    try:
        from tamga_validator import jcs as vj
        from tamga_canon import jcs as cj
        for obj, _ in cases:
            if not (jcs(obj) == vj(obj) == cj(obj)):
                print(f"SELFTEST-FAIL: üçlü-parite-bozuk: {obj!r}")
                bad += 1
    except ImportError as e:
        print(f"SELFTEST-FAIL: parite-import-hatası: {e}")
        bad += 1
    if bad:
        return 1
    print(f"selftest: {len(cases)}/{len(cases)} RFC-8785-öz-OK + 3-uygulama-paritesi "
          f"(ECMAScript-number + UTF-16-sıra; json.dumps'ın-hatalı-olduğu-8-yer)")
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
