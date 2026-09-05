#!/usr/bin/env python3
"""Audit-7 — gömülü-zincir (Dilim-8/F24) saldırı simülasyonu (simnet, wasmtime'sız).

Kapsam: snapshot gövdesindeki `ledger_records` + `ledger_tip` yüzeyine üç saldırı:
  A1 record-splice : charge ücreti düşürülüp yeniden şifrelenir → import + ledger-verify
  A2 tip-swap      : ledger_tip uydurulur → hedefi zincirli node'a ve taze node'a import
  A3 merkle-fold   : hafıza kurcalanır ama graph_merkle tutarlı yeniden hesaplanır

NOT (dürüst sınır): saldırılar simnet parolası + seed ile yapılır; bu, "seed'i
bilmesine rağmen zinciri kurcalayan" güçlü düşmandır. Gerçek tehdit modelindeki
düşman (seed'siz host) daha zayıftır — burada mekanizmanın üst sınırı ölçülür.
Kanıt: kanit/GUVENLIK/<tarih>/audit-7.log
"""
import json, os, pathlib, subprocess, sys, hashlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.chdir(ROOT)
os.environ.setdefault("TAMGA_KS_PASSPHRASE", "simnet-2026")

import tamga_runner as tr  # runner'ın kendi kripto primitifleri

SB = ROOT / "tests/simnet/.audit7"
OUT = []


def sh(*args):
    r = subprocess.run([sys.executable, "tamga_runner.py", *args],
                       capture_output=True, text=True)
    return r.stdout.strip()


def log(s):
    OUT.append(s)
    print(s)


def parse_snap(p):
    data = pathlib.Path(p).read_bytes()
    hlen = int.from_bytes(data[4:8], "big")
    header = json.loads(data[8:8 + hlen].decode())
    return data, hlen, header


def craft(src, mutate):
    """snapshot gövdesini çöz → mutate(header, state) → yeniden şifrele."""
    data, hlen, header = parse_snap(src)
    # keystore'dan seed'i çöz (simnet parolasıyla) — hem gövde anahtarı hem kimlik
    seed = tr.xdec(bytes.fromhex(header["keystore_blob"]["ct"]), b"",
                   bytes.fromhex(header["keystore_blob"]["nonce"]),
                   tr.kdf(tr.passphrase(), bytes.fromhex(header["keystore_blob"]["salt"])))
    state = json.loads(tr.xdec(data[8 + hlen:], json.dumps(header, ensure_ascii=False, sort_keys=True).encode(),
                               bytes.fromhex(header["body_nonce"]), tr.body_key(seed)).decode())
    header, state = mutate(header, state)
    body_nonce = os.urandom(24)
    header["body_nonce"] = body_nonce.hex()
    hb = json.dumps(header, ensure_ascii=False, sort_keys=True).encode()
    ct = tr.xenc(json.dumps(state, ensure_ascii=False).encode(), hb, body_nonce, tr.body_key(seed))
    forged = tr.MAGIC + len(hb).to_bytes(4, "big") + hb + ct
    return forged


def fresh(name):
    p = SB / name
    p.mkdir(parents=True, exist_ok=True)
    for f in ("tamga.json", "agent.wasm"):
        (p / f).write_bytes((ROOT / "tests/vectors/tc-a1" / f).read_bytes())
    return p


def main():
    import shutil
    shutil.rmtree(SB, ignore_errors=True)
    (SB / "pkgA").mkdir(parents=True)
    for f in ("tamga.json", "agent.wasm"):
        (SB / "pkgA" / f).write_bytes((ROOT / "tests/vectors/tc-a1" / f).read_bytes())
    seed = json.loads(sh("keygen"))["seed_hex"]
    sh("grant", str(SB / "pkgA"), "0.01", "audit7-hibe")
    # memory'yi wasmtime'sız kur (MERGEN ders köprüsü — Dilim-4 mekanizması)
    mi = sh("memory", str(SB / "pkgA"), "--import-json", "tests/simnet/mergen-dersler.json")
    base = SB / "base.tsg"
    sh("export", str(SB / "pkgA"), "-o", str(base), "--seed", seed)
    log(f"# önkoşul: memory-import ok={json.loads(mi).get('ok') if mi.startswith('{') else mi[:80]}")

    # ---------- A1a: record-splice, ZAYIF düşman (hash yeniden hesaplamaz) ----------
    def a1a(header, state):
        for rec in state.get("ledger_records", []):
            if rec.get("op") == "grant":
                rec["amount"] = 100.0            # hibe şişirilir, h eski kalır
                break
        return header, state
    (SB / "a1a.tsg").write_bytes(craft(base, a1a))
    r1a = sh("import", str(SB / "a1a.tsg"), str(fresh("pkgB")))
    j1a_import = json.loads(r1a)
    ok1a = j1a_import.get("ok")
    v1a = sh("ledger-verify", str(SB / "pkgB"))
    j1a = json.loads(v1a)
    log(f"A1a splice (hash eski): import ok={ok1a} reason={j1a_import.get('reason_code')} {j1a_import.get('reason','')} "
        f"· hedef ledger-verify ok={j1a.get('ok')} broken_at={j1a.get('broken_at')}")
    if not ok1a and j1a_import.get("reason_code") == 14:
        log("A1a SONUÇ: import kuruluş-öncesinde RED (beklendi — Audit-7 D4 takviyesi sonrası)")
    elif ok1a and j1a.get("ok") is False:
        log("A1a SONUÇ: zincir-hash zayıf kurcalamayı sonradan yakaladı (düzeltme ÖNCESİ davranış)")
    else:
        log("A1a SONUÇ: BEKLENMEDİK")

    # ---------- A1b: record-splice, GÜÇLÜ düşman (tüm zinciri yeniden hesaplar) ----------
    def a1b(header, state):
        prev = "0" * 64
        for i, rec in enumerate(state.get("ledger_records", []), start=1):
            if rec.get("op") == "grant":
                rec["amount"] = 100.0
            rec["seq"] = i; rec["prev"] = prev
            no_h = {k: v for k, v in rec.items() if k != "h"}
            rec["h"] = hashlib.sha256((rec["prev"] + tr.jcs(no_h)).encode()).hexdigest()
            prev = rec["h"]
        return header, state
    (SB / "a1b.tsg").write_bytes(craft(base, a1b))
    r1b = sh("import", str(SB / "a1b.tsg"), str(fresh("pkgB2")))
    ok1b = json.loads(r1b).get("ok")
    v1b = json.loads(sh("ledger-verify", str(SB / "pkgB2")))
    log(f"A1b splice (zincir yeniden hesaplı): import ok={ok1b} · hedef ledger-verify ok={v1b.get('ok')} bakiye={v1b.get('balance_sim')}")
    if ok1b and v1b.get("ok"):
        log("A1b SONUÇ: AÇIK BULGU F25 — seed-sahibi taze node'a kendi-tutarlı sahte tarih kurabiliyor; "
            "mevcut panzehir: D4 append-only (zincirli hedef ezilmez) + provenance notu; "
            "kalıcı çözüm RFC-003 kapsamında node-cosign (kaydın hash'ine node anahtarı girer)")
    else:
        log("A1b SONUÇ: güçlü düşman da yakalandı (F25 yok — beklenmedik derecede iyi)")

    # ---------- A2: tip-swap ----------
    fake_tip = hashlib.sha256(b"uydurulmus-tip").hexdigest()
    def a2(header, state):
        state["ledger_tip"] = fake_tip
        return header, state
    (SB / "a2.tsg").write_bytes(craft(base, a2))
    r2_fresh = sh("import", str(SB / "a2.tsg"), str(fresh("pkgC")))          # taze node
    r2_chain = sh("import", str(SB / "a2.tsg"), str(SB / "pkgA"))            # zincirli node
    ok2f = json.loads(r2_fresh).get("ok")
    ok2c = json.loads(r2_chain).get("ok")
    rc2c = json.loads(r2_chain).get("reason_code")
    log(f"A2 tip-swap: taze node ok={ok2f} (erteleme notu beklenir) · zincirli node ok={ok2c} reason={rc2c}")
    if ok2f and not ok2c and rc2c == 14:
        log("A2 SONUÇ: tip-bağlama zincirli node üzerinde RED (beklendi); taze node erteliyor (bilinen, aşağıda)")
    else:
        log("A2 SONUÇ: BEKLENMEDİK")

    # ---------- A3: merkle-fold (tutarlı kurcalama) ----------
    def a3(header, state):
        n0 = state["memory"]["nodes"][0]
        n0["text"] = "SALDIRI-DEGISTI"
        state["graph_merkle"] = tr._graph_merkle(state["memory"])
        return header, state
    (SB / "a3.tsg").write_bytes(craft(base, a3))
    r3 = sh("import", str(SB / "a3.tsg"), str(fresh("pkgD")))
    ok3 = json.loads(r3).get("ok")
    log(f"A3 merkle-fold (tutarlı kurcalama): import ok={ok3}")
    if ok3:
        log("A3 SONUÇ: KABUL — belgeli sınır: seed sahibi tutarlı state üretebilir (düşman üst sınırı); merkle seed'siz host'a karşıdır")
    else:
        log("A3 SONUÇ: İDDİA — yakalandı")

    shutil.rmtree(SB, ignore_errors=True)
    log("")
    log("# Audit-7 betik sonu — değerlendirme SECURITY-AUDIT.md'de")


if __name__ == "__main__":
    logf = ROOT / "kanit/GUVENLIK" / __import__("time").strftime("%F") / "audit-7.log"
    logf.parent.mkdir(parents=True, exist_ok=True)
    import io
    buf = io.StringIO()
    _old = sys.stdout
    sys.stdout = buf
    try:
        main()
    finally:
        sys.stdout = _old
    text = buf.getvalue()
    print(text)
    with open(logf, "a", encoding="utf-8") as f:
        f.write(f"# audit-7 — {__import__('time').strftime('%FT%T%z')}\n" + text)
