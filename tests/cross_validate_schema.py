#!/usr/bin/env python3
"""RFC-001 schema cross-validation (closes the validator TODO — Audit-1 note).

Method: decision-level equivalence. For each sample (6 real vectors + 36 mutations):
  A) jsonschema (draft 2020-12, specs/manifest-0.1.0.schema.json) — is it valid?
  B) tamga_validator.py (stdlib schema block) — is it a schema-family RED (otherwise ACCEPT /
     hash/imza ailesi RED mi)?
Claim: A-invalid ⇔ B-schema-RED. A divergence = drift: one of the two implementations deviates from RFC-001.
Faz-B (RFC-007): 9 draft-phase probes — specs/manifest-0.2.0-draft.schema.json additive
contract (0.1.0 manifests stay valid; runtime.net validates under draft only; tc-a6's
spec_version flip is the documented v0.2 gate, not drift).

Run: .venv-jsonschema/bin/python tests/cross_validate_schema.py
Evidence: .evidence/VALIDASYON/<date>/schema-crossvalidation.log
"""
import copy, hashlib, json, pathlib, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
try:
    import jsonschema
    from jsonschema import Draft202012Validator
except ImportError:
    print("ERROR: jsonschema missing — run with .venv-jsonschema/bin/python")
    sys.exit(2)

SCHEMA = json.loads((ROOT / "specs/manifest-0.1.0.schema.json").read_text(encoding="utf-8"))
VEC = ROOT / "tests/vectors"
SB = ROOT / "tests/simnet/.schemacheck"
OUT = []


def log(s):
    OUT.append(s)
    print(s)


def manual_verdict(pkg: pathlib.Path):
    r = subprocess.run([sys.executable, str(ROOT / "tamga_validator.py"), "validate", str(pkg)],
                       capture_output=True, text=True, cwd=str(ROOT))  # Audit-9 B20: cwd-independent
    msg = r.stdout.strip()
    schema_family = ("schema_violation" in msg or "unknown_field" in msg or
                     "unknown_capability" in msg or "unsupported_spec_version" in msg)
    return r.returncode == 0, msg, schema_family


def check(name, manifest: dict):
    pkg = SB / name
    pkg.mkdir(parents=True, exist_ok=True)
    (pkg / "tamga.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    (pkg / "agent.wasm").write_bytes((VEC / "tc-a1/agent.wasm").read_bytes())
    try:
        jsonschema.validate(manifest, SCHEMA)
        js_valid = True
        js_err = ""
    except jsonschema.ValidationError as ex:
        js_valid = False
        js_err = f"{list(ex.absolute_path)}: {ex.message[:70]}"
    accept, msg, sch_red = manual_verdict(pkg)
    agree = (not js_valid) == sch_red
    tag = "AGREE" if agree else "!!DRIFT!!"
    log(f"[{tag}] {name:24s} js={'valid' if js_valid else 'INVALID':8s} "
        f"validator={'ACCEPT' if accept else msg[:58]}")
    if not js_valid:
        log(f"{'':26s} js-hata: {js_err}")
    return agree


def mutants(base: dict):
    out = []

    def add(name, fn):
        m = copy.deepcopy(base)
        fn(m)
        out.append((name, m))

    add("m01-spec-yok", lambda m: m.pop("spec_version"))
    add("m02-spec-0.2.0", lambda m: m.update(spec_version="0.2.0"))
    add("m03-bilinmeyen-kok", lambda m: m.update(hack=1))
    add("m04-package-yok", lambda m: m.pop("package"))
    add("m05-ad-buyuk", lambda m: m["package"].update(name="BadName"))
    add("m06-ad-kisa", lambda m: m["package"].update(name="ab"))
    add("m07-semver-kotu", lambda m: m["package"].update(version="1.0"))
    add("m08-code-yok", lambda m: m["package"].pop("code"))
    add("m09-hash-hex-degil", lambda m: m["package"]["code"].update(wasm_sha256="zz" * 32))
    add("m10-hash-algo", lambda m: m["package"]["code"].update(hash_algo="sha512"))
    add("m11-target-0.2", lambda m: m["package"]["code"].update(target="wasi-0.2/component"))
    add("m12-proof-P9", lambda m: m["runtime"].update(min_proof_level="P9"))
    add("m13-limit-buyuk", lambda m: m["runtime"]["limits"].update(memory_mb=8192))
    add("m14-limit-bool", lambda m: m["runtime"]["limits"].update(cpu_ms_per_run=True))
    add("m15-limit-str", lambda m: m["runtime"]["limits"].update(io_mb_per_run="5"))
    add("m16-limit-eksik", lambda m: m["runtime"]["limits"].pop("io_mb_per_run"))
    add("m17-limit-bilinmeyen", lambda m: m["runtime"]["limits"].update(gpu=1))
    add("m18-snap-2", lambda m: m["memory"].update(snapshot_format="tamga-snapshot/2"))
    add("m19-crypto-aes", lambda m: m["memory"].update(crypto_suite="AES-GCM"))
    add("m20-cap-dup", lambda m: m.update(capabilities=["clock", "clock"]))
    add("m21-cap-cok", lambda m: m.update(capabilities=["fs", "net", "clock", "env", "random", "teleport"]))
    add("m22-cap-dizi-degil", lambda m: m.update(capabilities="clock"))
    add("m23-scheme-bos", lambda m: m["payment"]["schemes"].clear() if "payment" in m
        else m.update(payment={"schemes": []}))
    add("m24-scheme-yabanci", lambda m: m["payment"]["schemes"].__setitem__(0, "tamga-real/1")
        if "payment" in m and m["payment"].get("schemes")
        else m.update(payment={"schemes": ["tamga-real/1"]}))
    # --- RFC-007 R1/R3: runtime.net shape family (schema <-> validator drift net) ---
    add("m29-net-tam", lambda m: m["runtime"].update(net={
        "egress": ["api.ornek.com:443"], "max_bytes_per_run": 1048576, "timeout_s": 30}))
    add("m30-net-9-uç", lambda m: m["runtime"].update(net={
        "egress": [f"h{i}:443" for i in range(9)], "max_bytes_per_run": 1048576, "timeout_s": 30}))
    add("m31-net-0-uç", lambda m: m["runtime"].update(net={
        "egress": [], "max_bytes_per_run": 1048576, "timeout_s": 30}))
    add("m32-net-port-0", lambda m: m["runtime"].update(net={
        "egress": ["api.ornek.com:0"], "max_bytes_per_run": 1048576, "timeout_s": 30}))
    add("m33-net-port-65536", lambda m: m["runtime"].update(net={
        "egress": ["api.ornek.com:65536"], "max_bytes_per_run": 1048576, "timeout_s": 30}))
    add("m34-net-bytes-küçük", lambda m: m["runtime"].update(net={
        "egress": ["api.ornek.com:443"], "max_bytes_per_run": 512, "timeout_s": 30}))
    add("m35-net-timeout-121", lambda m: m["runtime"].update(net={
        "egress": ["api.ornek.com:443"], "max_bytes_per_run": 1048576, "timeout_s": 121}))
    add("m36-net-bilinmeyen-anahtar", lambda m: m["runtime"].update(net={
        "egress": ["api.ornek.com:443"], "max_bytes_per_run": 1048576, "timeout_s": 30,
        "proto": "https"}))
    add("m25-sig-algo", lambda m: m["signature"].update(algo="rsa"))
    add("m26-sig-key-hex", lambda m: m["signature"].update(key="zz" * 32))
    add("m27-sig-sig-hex", lambda m: m["signature"].update(sig="zz" * 64))
    add("m28-sig-yok", lambda m: m.pop("signature"))
    return out


def main():
    import shutil
    shutil.rmtree(SB, ignore_errors=True)
    SB.mkdir(parents=True)
    base = json.loads((VEC / "tc-a1/tamga.json").read_text(encoding="utf-8"))
    if "payment" not in base:
        base["payment"] = {"schemes": ["tamga-sim/1"]}

    log(f"# RFC-001 schema cross-validation — {time.strftime('%FT%T%z')}")
    log(f"# jsonschema {jsonschema.__version__ if hasattr(jsonschema,'__version__') else '4.x'} · "
        f"schema: specs/manifest-0.1.0.schema.json (draft 2020-12) · validator: tamga_validator.py")
    log("")

    ok = 0; total = 0
    log("## Real vectors")
    for tc in ["tc-a1", "tc-a2", "tc-a3", "tc-a4", "tc-a5", "tc-a6"]:
        total += 1
        m = json.loads((VEC / tc / "tamga.json").read_text(encoding="utf-8"))
        if "payment" not in m:
            m["payment"] = {"schemes": ["tamga-sim/1"]}
        ok += check(tc, m)
    log("")

    log("## Mutation matrix (tc-a1 base)")
    for name, m in mutants(base):
        total += 1
        ok += check(name, m)
    log("")

    # ---- Faz-B: v0.2 DRAFT additive contract (RFC-007) --------------------
    # Dondur-ikili (0.1.0 schema + validator) yukarıdaki her vektöre aynı kararı
    # vermeye devam eder; 0.2.0 DRAFT şema EKLEYİCİDİR: her 0.1.0 manifest'i
    # onun altında da geçerli kalır, runtime.net'li manifest YALNIZ draft'ta
    # geçerlidir (üst-sınır sapması belgelenmiş v0.2 kapısı — validator const'ı
    # kurucu sürüm-flip'ine kadar 0.1.0 kalır; bu drift değil tasarımdır).
    log("## v0.2 draft additive contract (RFC-007)")
    draft = json.loads((ROOT / "specs/manifest-0.2.0-draft.schema.json").read_text(encoding="utf-8"))
    draft_state = {"ok": 0, "total": 0}

    def draft_check(name, manifest, expect_draft_valid):
        errs = list(Draft202012Validator(draft).iter_errors(manifest))
        valid = not errs
        agree = valid == expect_draft_valid
        draft_state["total"] += 1
        draft_state["ok"] += 1 if agree else 0
        log(f"[{'AGREE' if agree else '!!DRIFT!!'}] {name:24s} draft={'valid' if valid else 'INVALID':8s} "
            f"(beklenen={'valid' if expect_draft_valid else 'INVALID'})")

    for tc in ["tc-a1", "tc-a2", "tc-a3", "tc-a4", "tc-a5", "tc-a6"]:
        m = json.loads((VEC / tc / "tamga.json").read_text(encoding="utf-8"))
        if "payment" not in m:
            m["payment"] = {"schemes": ["tamga-sim/1"]}
        # beklenti = donuk-şema-kararı: draft EKLEYİCİ → hiçbir donmuş-vektör
        # karar-sınıfı değiştiremez. TEK-istisna tc-a6: o vektör spec_version
        # "0.2.0" taşır — donuk-çift onu RED'ler (üst-sınır), draft KABUL eder;
        # bu-flip belgelenen v0.2 kapısının kendisidir, drift-değil.
        frozen_valid = not list(Draft202012Validator(SCHEMA).iter_errors(m))
        expect = frozen_valid
        if tc == "tc-a6":
            expect = m.get("spec_version") in draft["properties"]["spec_version"]["enum"]
        draft_check(f"{tc}/under-draft", m, expect)
    v2 = json.loads(json.dumps(base))
    v2["spec_version"] = "0.2.0"
    v2["runtime"]["net"] = {"egress": ["127.0.0.1:1"], "max_bytes_per_run": 1048576, "timeout_s": 10}
    draft_check("v0.2-runtime.net", v2, True)
    v2_bad = json.loads(json.dumps(v2))
    v2_bad["runtime"]["net"]["egress"] = ["127.0.0.1:0"]
    draft_check("v0.2-port-0", v2_bad, False)
    v2_big = json.loads(json.dumps(v2))
    v2_big["runtime"]["net"]["max_bytes_per_run"] = 8388609
    draft_check("v0.2-cap-overflow", v2_big, False)

    # --- geçiş-matrisi (P2, 2026-09-09): yükseltme-DOWNgrade-yönleri ---
    log("## spec_version geçiş matrisi (yükseltme + downgrade)")
    a1 = json.loads((VEC / "tc-a1" / "tamga.json").read_text(encoding="utf-8"))
    a1_v2 = json.loads(json.dumps(a1))
    a1_v2["spec_version"] = "0.2.0"
    a1_v2["runtime"]["net"] = {"egress": ["127.0.0.1:1"], "max_bytes_per_run": 1048576, "timeout_s": 10}
    matrix = [
        ("down:0.2.0→frozen-schema", a1_v2, SCHEMA, False),
        ("up:0.1.0→draft-schema", a1, draft, True),
        ("down:0.2.0→draft-schema", a1_v2, draft, True),
    ]
    for name, m, schema, expect in matrix:
        valid = not list(Draft202012Validator(schema).iter_errors(m))
        agree = valid == expect
        total += 1
        ok += 1 if agree else 0
        log(f"[{'AGREE' if agree else '!!DRIFT!!'}] {name:28s} {'valid' if valid else 'RED':8s} "
            f"(beklenen={'valid' if expect else 'RED'})")
    v2_big = json.loads(json.dumps(v2))
    v2_big["runtime"]["net"]["max_bytes_per_run"] = 8388609
    draft_check("v0.2-cap-overflow", v2_big, False)
    total += draft_state["total"]; ok += draft_state["ok"]

    # --- v0.3.0-draft satiri (M6, 2026-09-10): RFC-008 external_receipt dilimi ---
    draft3 = json.loads((ROOT / "specs/manifest-0.3.0-draft.schema.json").read_text(encoding="utf-8"))
    a1_v3 = json.loads(json.dumps(a1))
    a1_v3["spec_version"] = "0.3.0"
    matrix3 = [
        ("up:0.1.0→v0.3.0-draft", a1, draft3, True),
        ("down:0.2.0→v0.3.0-draft", a1_v2, draft3, True),
        ("ext-receipt:0.3.0→v0.3.0-draft", json.loads((VEC / "m6-external-receipt" / "ok-external-receipt.json").read_text(encoding="utf-8")), draft3, True),
        ("down:0.3.0→v0.2.0-draft", json.loads((VEC / "m6-external-receipt" / "ok-external-receipt.json").read_text(encoding="utf-8")), draft, False),
    ]
    log("## v0.3.0-draft gecis-satiri (M6 additive-contract)")
    for name, m, schema, expect in matrix3:
        valid = not list(Draft202012Validator(schema).iter_errors(m))
        agree = valid == expect
        total += 1
        ok += 1 if agree else 0
        log(f"[{'AGREE' if agree else '!!DRIFT!!'}] {name:28s} {'valid' if valid else 'RED':8s} "
            f"(beklenen={'valid' if expect else 'RED'})")
    log("")
    log(f"RESULT: {ok}/{total} AGREE — {'cross-validation CLEAN' if ok == total else 'DRIFT → RFC-001 fidelity must be fixed'}")
    shutil.rmtree(SB, ignore_errors=True)


if __name__ == "__main__":
    logf = ROOT / "kanit/VALIDASYON" / time.strftime("%F") / "schema-crossvalidation.log"
    logf.parent.mkdir(parents=True, exist_ok=True)
    import io
    buf = io.StringIO(); _old = sys.stdout; sys.stdout = buf
    try:
        main()
    finally:
        sys.stdout = _old
    text = buf.getvalue()
    print(text)
    with open(logf, "a", encoding="utf-8") as f:
        f.write(text)
    sys.exit(0 if "CLEAN" in text.splitlines()[-1] else 1)  # English since i18n: match the printed verdict
