#!/usr/bin/env python3
"""tamga_bundle.py — B4: tek-komut-doğrulama-bundle-çıkarıcı (teknik-olmayan-karşı-tarafa).

Amaç: bir-işin-TÜM-kanıtını-tekbir-konumda-topla: zincir-段-parçası-(doğrulanabilir)+
manifest-imza-özeti + delivery-hash + mini-verifier-kararı + (varsa) node-cosign.
Çıktı: <pkg>-bundle.json-(machine)-+ opsiyonel-<pkg>-bundle.md-(insan-okur özet).

Tasarım-kuralı: bundle-YENİ-iddia-ÜRETMEZ — yalnız-varolan-zincir kayıtlarını-KOPYALAR
ve-her-alan-kaynağıyla-etiketlenir (OBSERVED/DERIVED). Üçüncü-taraf-bundle'ı
tamga_verify_mini.py-ile-tek-komutla-çoğaltır (reproducibility-bağımlılığı-bilinçli).

Kullanım:
  python3 tamga_bundle.py <pkg> [-o out-dir] [--md]
Çıkış-rc: 0-ok · 1-doğrulama-RED-(bundle-yine-de-üretir: kırık-zincir-de-kanıttır) · 2-kullanım
"""
import hashlib
import json
import pathlib
import sys

MAX_LINE_BYTES = 1 * 1024 * 1024  # Audit-11 paritesi

def jcs(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

def _chain_head(lp: pathlib.Path):
    prev_h, n = "0" * 64, 0
    if not lp.exists():
        return "", 0, "no-ledger"
    try:
        with open(lp, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                n += 1
                if len(line.encode("utf-8")) > MAX_LINE_BYTES:
                    return "", n, f"broken@{n}(line>1MiB)"
                try:
                    rec = json.loads(line)
                except Exception:
                    return "", n, f"broken@{n}(unparseable)"
                no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
                exp = hashlib.sha256((rec.get("prev", "") + jcs(no_h).decode("utf-8")).encode("utf-8")).hexdigest()
                if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
                    return "", n, f"broken@{n}"
                prev_h = rec["h"]
    except OSError as e:
        return "", n, f"io_error:{e}"
    return prev_h, n, ("ok" if n else "empty-chain")

def build(pkg: pathlib.Path, out_dir: pathlib.Path):
    mf = pkg / "tamga.json"
    lp = pkg / "ledger.jsonl"
    m = json.loads(mf.read_text(encoding="utf-8")) if mf.exists() else {}
    tip, lines, verdict = _chain_head(lp)
    records = []
    if lp.exists():
        with open(lp, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip() and len(line.encode("utf-8")) <= MAX_LINE_BYTES:
                    try:
                        records.append(json.loads(line))
                    except Exception:
                        pass
    # RFC-003 D5: iş-kayıtı TEK-ŞEKLİ op="charge" — çalışmanın-TÜM-evidence'ı (engine,
    # wall_ms, stdout_sha256, delivery_hash, fee) aynı-kayıtta; ayrı-'run'-kaydı-YOK.
    jobs = [r for r in records if r.get("op") == "charge"]
    bundle = {
        "bundle_format": "tamga-evidence-bundle/1",
        "generated_note": "Kopya-kanıt — yeni-iddia-üretmez; her-alan-kaynak-etiketli. / Copy-evidence — asserts nothing new; every field source-labeled.",
        "package": {
            "name": m.get("package", {}).get("name"),
            "manifest_sha256": hashlib.sha256(mf.read_bytes()).hexdigest() if mf.exists() else None,
            "agent_pubkey": (m.get("signature", {}) or {}).get("key"),
            "_label": "OBSERVED (manifest bytes re-hashed at bundle time)",
        },
        "chain": {
            "head": tip,
            "lines": lines,
            "verdict": verdict,
            "_label": "DERIVED (mini-verifier kuralıyla yeniden-hesaplandı: sha256(prev + jcs(rec\\{h,node_sig})))".replace("\\{", "-minus-"),
            "records": records,
        },
        "jobs": [{
            "seq": r.get("seq"), "h": r.get("h"),
            "session": r.get("session"), "engine": r.get("engine"),
            "stdout_sha256": r.get("stdout_sha256"),
            "wall_ms": r.get("wall_ms"),
            "fee_sim": r.get("fee_sim"), "fee_birebir": r.get("fee_birebir"),
            "delivery_hash": r.get("delivery_hash"),
            "net_decl_sha256": r.get("net_decl_sha256"),
            "_label": "OBSERVED (chain record copy; RFC-003 D5: iş=charge kaydı) — "
                      "delivery_hash alg+hex-etiketli (RFC-007 R2)",
        } for r in jobs],
        "how_to_verify": [
            "python3 tamga_verify_mini.py <(jq -c '.chain.records[]' bundle.json)",
            "veya / or: pip install tamga-protocol && tamga ledger-verify <pkg>",
        ],
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{pkg.name}-bundle.json"
    out.write_text(json.dumps(bundle, indent=2, ensure_ascii=False), encoding="utf-8")
    md = out_dir / f"{pkg.name}-bundle.md"
    md.write_text(_md(bundle), encoding="utf-8")
    return out, md, bundle

def _md(b: dict) -> str:
    c, p = b["chain"], b["package"]
    lines = [
        f"# Evidence Bundle — {p['name']}",
        "",
        f"- **Zincir kararı / chain verdict:** `{c['verdict']}`",
        f"- **Head:** `{c['head']}` ({c['lines']} kayıt / records)",
        f"- **Manifest sha256:** `{p['manifest_sha256']}`",
        f"- **Agent pubkey:** `{p['agent_pubkey']}`",
        "",
        "## İşler / Jobs (RFC-003 D5: iş=charge kaydı)",
    ]
    for r in b["jobs"]:
        lines.append(f"- seq {r['seq']} (session {r.get('session')}, {r.get('engine')}): "
                     f"stdout_sha256 `{str(r.get('stdout_sha256'))[:16]}…` · wall_ms {r.get('wall_ms')} · fee {r.get('fee_sim')}/{r.get('fee_birebir')}")
        if r.get("delivery_hash"):
            dh = r["delivery_hash"]
            lines.append(f"    delivery: {dh.get('alg')} `{str(dh.get('hex'))[:16]}…`")
    lines += ["", "## Nasıl doğrulanır / How to verify", ""]
    for h in b["how_to_verify"]:
        lines.append(f"    {h}")
    return "\n".join(lines) + "\n"

def main(argv):
    if not argv:
        print(__doc__)
        return 2
    pkg = pathlib.Path(argv[0])
    if not pkg.exists():
        print(json.dumps({"ok": False, "reason": f"pkg not found: {pkg}"}))
        return 2
    out_dir = pathlib.Path(".")
    if "-o" in argv:
        out_dir = pathlib.Path(argv[argv.index("-o") + 1])
    out, md, b = build(pkg, out_dir)
    print(json.dumps({"ok": True, "bundle": str(out), "markdown": str(md),
                      "chain_verdict": b["chain"]["verdict"], "head": b["chain"]["head"],
                      "lines": b["chain"]["lines"]}))
    return 0 if b["chain"]["verdict"] in ("ok",) else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
