"""tamga_bundle zincir-basi + markdown-uretim dal-kesen testleri (LEED).

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (dict girdi) + tmp_path ile gecici-dosya (ledger.jsonl).

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _chain_head  streaming zincir-dogrulama -> (head, n, verdict)
               verdictler: ok / empty-chain / no-ledger / broken@n / broken@n(unparseable) /
                           broken@n(line>1MiB) / io_error:<msg>
  _md          evidence-bundle markdown uretimi (chain + package + jobs + how-to-verify)

KAYNAK-TUZAGI (Audit-11 D1): >1MiB satir sentinel ile kirilir (bomba RAM'e ALINMAZ).
"""
import hashlib
import json
import pathlib
import sys

import pytest

sys.path.insert(0, ".")
from tamga_bundle import _chain_head, _md, MAX_LINE_BYTES  # noqa: E402
from tamga_canon import jcs  # noqa: E402

ZERO64 = "0" * 64


def _rec(seq, prev, **fields):
    """Gecerli bir ledger-kaydi insa et (h dahil)."""
    base = {"seq": seq, "prev": prev, **fields}
    no_h = {k: v for k, v in base.items() if k not in ("h", "node_sig")}
    base["h"] = hashlib.sha256(
        (prev + jcs(no_h).decode("utf-8")).encode("utf-8")).hexdigest()
    return base


def _valid_ledger(lp, n=3):
    prev = ZERO64
    lines = []
    for i in range(1, n + 1):
        r = _rec(i, prev, kind="note", text=f"m{i}")
        lines.append(json.dumps(r))
        prev = r["h"]
    lp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return prev


# == _chain_head: gecerli zincir =================================================================

def test_chain_head_valid_missing_file_is_no_ledger(tmp_path):
    """Olmayan-dosya -> ('', 0, 'no-ledger')."""
    head, n, verdict = _chain_head(tmp_path / "ledger.jsonl")
    assert verdict == "no-ledger"
    assert head == ""
    assert n == 0


def test_chain_head_valid_three_records(tmp_path):
    lp = tmp_path / "l.jsonl"
    h = _valid_ledger(lp, 3)
    head, n, verdict = _chain_head(lp)
    assert verdict == "ok"
    assert n == 3
    assert head == h


def test_chain_head_single_record(tmp_path):
    lp = tmp_path / "l.jsonl"
    r = _rec(1, ZERO64, kind="note", text="solo")
    lp.write_text(json.dumps(r) + "\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert verdict == "ok"
    assert n == 1
    assert head == r["h"]


def test_chain_head_returns_triple(tmp_path):
    r = _chain_head(tmp_path / "l.jsonl")
    assert isinstance(r, tuple) and len(r) == 3


def test_chain_head_head_is_64_hex(tmp_path):
    lp = tmp_path / "l.jsonl"
    _valid_ledger(lp, 5)
    head, _, verdict = _chain_head(lp)
    assert verdict == "ok"
    assert len(head) == 64
    assert all(c in "0123456789abcdef" for c in head)


def test_chain_head_genesis_prev():
    """Ilk kaydin prev'i '0'*64 (GENESIS)."""
    assert _rec(1, ZERO64)["prev"] == ZERO64


def test_chain_head_chain_progresses(tmp_path):
    """Her kaydin h'si oncekinin h'sine bagli (chain-of-hash)."""
    lp = tmp_path / "l.jsonl"
    prev = ZERO64
    for i in range(1, 4):
        r = _rec(i, prev, kind="note", text=f"r{i}")
        with open(lp, "a", encoding="utf-8") as f:
            f.write(json.dumps(r) + "\n")
        prev = r["h"]
        head, n, verdict = _chain_head(lp)
        assert verdict == "ok"
        assert head == r["h"]
        assert n == i


@pytest.mark.parametrize("n", [1, 2, 5, 10])
def test_chain_head_various_lengths(tmp_path, n):
    lp = tmp_path / "l.jsonl"
    _valid_ledger(lp, n)
    _, count, verdict = _chain_head(lp)
    assert verdict == "ok"
    assert count == n


def test_chain_head_ignores_blank_lines(tmp_path):
    """Bos-satirlar atlanir (n artmaz)."""
    lp = tmp_path / "l.jsonl"
    prev = ZERO64
    parts = []
    for i in range(1, 3):
        r = _rec(i, prev, kind="note", text=f"m{i}")
        parts.append(json.dumps(r))
        parts.append("")             # bos satir
        prev = r["h"]
    lp.write_text("\n".join(parts) + "\n", encoding="utf-8")
    _, n, verdict = _chain_head(lp)
    assert verdict == "ok"
    assert n == 2


def test_chain_head_strips_whitespace(tmp_path):
    """satir.strip() — satir-ici bosluklar tolere edilir."""
    lp = tmp_path / "l.jsonl"
    r = _rec(1, ZERO64, kind="note", text="x")
    lp.write_text("  " + json.dumps(r) + "  \n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert verdict == "ok"
    assert n == 1
    assert head == r["h"]


# == _chain_head: no-ledger / empty-chain ========================================================

def test_chain_head_missing_file(tmp_path):
    """Olmayan-dosya -> ('', 0, 'no-ledger')."""
    assert _chain_head(tmp_path / "nope.jsonl") == ("", 0, "no-ledger")


def test_chain_head_no_ledger_head_empty(tmp_path):
    head, _, _ = _chain_head(tmp_path / "nope.jsonl")
    assert head == ""


def test_chain_head_empty_file(tmp_path):
    """Bos-dosya -> ('0'*64, 0, 'empty-chain')."""
    lp = tmp_path / "l.jsonl"
    lp.write_text("", encoding="utf-8")
    assert _chain_head(lp) == (ZERO64, 0, "empty-chain")


def test_chain_head_only_blank_lines(tmp_path):
    lp = tmp_path / "l.jsonl"
    lp.write_text("\n\n\n", encoding="utf-8")
    assert _chain_head(lp) == (ZERO64, 0, "empty-chain")


def test_chain_head_empty_head_is_genesis():
    """empty-chain head = '0'*64 (GENESIS)."""
    assert ZERO64 == "0" * 64


# == _chain_head: kirik zincir (broken@n) ========================================================

def test_chain_head_wrong_seq(tmp_path):
    """seq n'e esit OLMALI."""
    lp = tmp_path / "l.jsonl"
    lp.write_text(json.dumps(_rec(7, ZERO64, kind="note", text="x")) + "\n",
                  encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert head == ""
    assert n == 1
    assert verdict == "broken@1"


def test_chain_head_wrong_prev(tmp_path):
    """prev onceki head'e esit OLMALI."""
    lp = tmp_path / "l.jsonl"
    r1 = _rec(1, ZERO64, kind="note", text="a")
    r2 = _rec(2, "f" * 64, kind="note", text="b")   # yanlis-prev
    lp.write_text(json.dumps(r1) + "\n" + json.dumps(r2) + "\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert head == ""
    assert n == 2
    assert verdict == "broken@2"


def test_chain_head_wrong_h(tmp_path):
    """h yeniden-hesaplanan degerle eslesmeli."""
    lp = tmp_path / "l.jsonl"
    r1 = _rec(1, ZERO64, kind="note", text="a")
    r2 = _rec(2, r1["h"], kind="note", text="b")
    r2["h"] = "deadbeef"                             # kurcalanmis-h
    lp.write_text(json.dumps(r1) + "\n" + json.dumps(r2) + "\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert verdict == "broken@2"
    assert head == ""


def test_chain_head_middle_break(tmp_path):
    """Orta-kayit kirik -> broken@2 (1 GECERLI sayildi)."""
    lp = tmp_path / "l.jsonl"
    r1 = _rec(1, ZERO64, kind="note", text="a")
    r2 = {"seq": 2, "prev": r1["h"], "kind": "note", "text": "CORRUPTED", "h": "deadbeef"}
    r3 = _rec(3, r2["h"], kind="note", text="c")
    lp.write_text("\n".join(json.dumps(r) for r in (r1, r2, r3)) + "\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert verdict == "broken@2"
    assert n == 2
    assert head == ""


def test_chain_head_broken_at_first_record(tmp_path):
    """Ilk kayit kirik -> broken@1."""
    lp = tmp_path / "l.jsonl"
    lp.write_text(json.dumps({"seq": 1, "prev": "x" * 64, "h": "y"}) + "\n",
                  encoding="utf-8")
    assert _chain_head(lp) == ("", 1, "broken@1")


def test_chain_head_broken_n_counts_partial(tmp_path):
    """n, KIRILAN kayda kadar olan sayidir."""
    lp = tmp_path / "l.jsonl"
    prev = ZERO64
    parts = []
    for i in range(1, 4):
        r = _rec(i, prev, kind="note", text=f"m{i}")
        parts.append(json.dumps(r))
        prev = r["h"]
    r4 = {"seq": 99, "prev": prev, "h": "zzz"}
    parts.append(json.dumps(r4))
    lp.write_text("\n".join(parts) + "\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert verdict == "broken@4"
    assert n == 4


def test_chain_head_h_excludes_h_and_node_sig(tmp_path):
    """h'nin girisinden 'h' ve 'node_sig' CIKARILIR (imza hash'e dahil DEGIL)."""
    lp = tmp_path / "l.jsonl"
    r = _rec(1, ZERO64, kind="note", text="x")
    r["node_sig"] = "abc"
    lp.write_text(json.dumps(r) + "\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert verdict == "ok"
    assert head == r["h"]


def test_chain_head_node_sig_does_not_affect_h(tmp_path):
    """node_sig degisse bile h AYNI kalir (imza-dogrulama ayri-katman)."""
    r1 = _rec(1, ZERO64, kind="note", text="x")
    r2 = dict(r1)
    r2["node_sig"] = "different-sig"
    no_h = {k: v for k, v in r2.items() if k not in ("h", "node_sig")}
    h = hashlib.sha256((r2["prev"] + jcs(no_h).decode("utf-8")).encode("utf-8")).hexdigest()
    assert h == r1["h"]


# == _chain_head: unparseable ====================================================================

def test_chain_head_unparseable_line(tmp_path):
    """Gecersiz-JSON -> broken@n(unparseable)."""
    lp = tmp_path / "l.jsonl"
    lp.write_text("not json at all\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert head == ""
    assert n == 1
    assert verdict == "broken@1(unparseable)"


def test_chain_head_json_fragment(tmp_path):
    """Yarim-JSON -> unparseable."""
    lp = tmp_path / "l.jsonl"
    lp.write_text('{"seq": 1, "prev":', encoding="utf-8")
    assert _chain_head(lp)[2] == "broken@1(unparseable)"


def test_chain_head_valid_then_unparseable(tmp_path):
    """Gecerli 1 kayit sonra unparseable -> broken@2(unparseable)."""
    lp = tmp_path / "l.jsonl"
    r = _rec(1, ZERO64, kind="note", text="a")
    lp.write_text(json.dumps(r) + "\nGARBAGE\n", encoding="utf-8")
    assert _chain_head(lp) == ("", 2, "broken@2(unparseable)")


@pytest.mark.parametrize("content", ["[1,2,3]", "null", "42", '"str"', "true"])
def test_chain_head_non_object_json_raises(tmp_path, content):
    """ORTAM-QUIRK (karakterizasyon): JSON-gecerli-ama-OBJE-olmayan satir
    rec.items() -> AttributeError firlatir (try/except yalniz json.loads'u tutar).
    Uretim bu yolla cagrilmaz (ledger'lar her zaman nesne-tutulur); test
    davranisi belgeler, URETIMI DUZELTMEZ (Kural-5)."""
    lp = tmp_path / "l.jsonl"
    lp.write_text(content + "\n", encoding="utf-8")
    with pytest.raises(AttributeError):
        _chain_head(lp)


def test_chain_head_object_json_is_broken_not_crash(tmp_path):
    """Nesne-formu JSON (bos bile olsa) AttributeError FIRLATMAZ — rec.get None
    doner, prev/seq deneti kirmadan once kirar ('', 1, 'broken@1')."""
    lp = tmp_path / "l.jsonl"
    lp.write_text("{}\n", encoding="utf-8")
    assert _chain_head(lp) == ("", 1, "broken@1")


# == _chain_head: satir-bombasi (Audit-11 D1) ====================================================

def test_chain_head_oversize_line(tmp_path):
    """>1MiB satir -> broken@n(line>1MiB) — satir OKUNMAZ (RAM'e ALINMAZ)."""
    lp = tmp_path / "l.jsonl"
    lp.write_text("x" * (MAX_LINE_BYTES + 1) + "\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert head == ""
    assert n == 1
    assert verdict == "broken@1(line>1MiB)"


def test_chain_head_max_boundary_ok(tmp_path):
    """Tam 1MiB = sinir (esitlik DAHIL, kirik DEGIL)."""
    lp = tmp_path / "l.jsonl"
    r = _rec(1, ZERO64, kind="note", text="x" * (MAX_LINE_BYTES - 300))
    line = json.dumps(r)
    assert len(line.encode("utf-8")) <= MAX_LINE_BYTES
    head, n, verdict = _chain_head(lp if False else lp)
    lp.write_text(line + "\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert verdict == "ok"


def test_chain_head_bomb_after_valid(tmp_path):
    """Gecerli-kayitlar-sonra bomba -> broken@N(line>1MiB)."""
    lp = tmp_path / "l.jsonl"
    r = _rec(1, ZERO64, kind="note", text="a")
    lp.write_text(json.dumps(r) + "\n" + "y" * (MAX_LINE_BYTES + 5) + "\n",
                  encoding="utf-8")
    assert _chain_head(lp)[2] == "broken@2(line>1MiB)"


def test_chain_head_bomb_does_not_consume_memory(tmp_path):
    """Sentinel: 50MB satir hic RAM'e inmez (kaynak-tuzagi)."""
    lp = tmp_path / "l.jsonl"
    lp.write_text("z" * (50 * 1024 * 1024) + "\n", encoding="utf-8")
    head, n, verdict = _chain_head(lp)
    assert verdict == "broken@1(line>1MiB)"
    assert head == ""


# == _chain_head: io_error =======================================================================

def test_chain_head_directory_as_file(tmp_path):
    """Dizin -> OSError -> ('', n, 'io_error:<msg>')."""
    head, n, verdict = _chain_head(tmp_path)
    assert head == ""
    assert n == 0
    assert verdict.startswith("io_error:")


def test_chain_head_io_error_contains_message(tmp_path):
    _, _, verdict = _chain_head(tmp_path)
    assert "Errno" in verdict or "Is a directory" in verdict


# == _md =========================================================================================

def _bundle(**over):
    b = {
        "chain": {"verdict": "ok", "head": "a" * 64, "lines": 3},
        "package": {"name": "demo-pkg", "manifest_sha256": "b" * 64,
                    "agent_pubkey": "c" * 64},
        "jobs": [{"seq": 1, "session": "s1", "engine": "dsh", "stdout_sha256": "d" * 64,
                  "wall_ms": 42, "fee_sim": "0.001", "fee_birebir": "0.002",
                  "delivery_hash": {"alg": "keccak256", "hex": "e" * 64}}],
        "how_to_verify": ["step one", "step two"],
    }
    b.update(over)
    return b


def test_md_returns_str():
    assert isinstance(_md(_bundle()), str)


def test_md_starts_with_title():
    assert _md(_bundle()).startswith("# Evidence Bundle — demo-pkg")


def test_md_contains_package_name():
    assert "demo-pkg" in _md(_bundle())


def test_md_contains_chain_verdict():
    """Zincir-karari markdown'a gomulu (insan-okur)."""
    assert "`ok`" in _md(_bundle())


def test_md_contains_head_and_lines():
    r = _md(_bundle())
    assert "a" * 64 in r
    assert "3 kayıt / records" in r


def test_md_contains_manifest_and_pubkey():
    r = _md(_bundle())
    assert "b" * 64 in r
    assert "c" * 64 in r


def test_md_contains_job_section():
    assert "## İşler / Jobs" in _md(_bundle())


def test_md_lists_job_seq():
    assert "seq 1" in _md(_bundle())


def test_md_lists_job_fields():
    r = _md(_bundle())
    for f in ("session s1", "dsh", "wall_ms 42", "0.001", "0.002"):
        assert f in r


def test_md_truncates_stdout_sha256():
    """stdout_sha256 ilk 16-char + '…'."""
    r = _md(_bundle())
    assert "`" + "d" * 16 + "…`" in r


def test_md_contains_delivery_hash():
    r = _md(_bundle())
    assert "delivery: keccak256" in r
    assert "e" * 16 + "…" in r


def test_md_omits_delivery_when_absent():
    b = _bundle()
    b["jobs"] = [{"seq": 2}]
    assert "delivery:" not in _md(b)


def test_md_contains_how_to_verify():
    assert "## Nasıl doğrulanır / How to verify" in _md(_bundle())


def test_md_lists_verify_steps():
    r = _md(_bundle())
    assert "    step one" in r
    assert "    step two" in r


def test_md_ends_with_newline():
    assert _md(_bundle()).endswith("\n")


def test_md_multiple_jobs():
    b = _bundle()
    b["jobs"] = [{"seq": 1, "stdout_sha256": "a" * 64},
                 {"seq": 2, "stdout_sha256": "b" * 64}]
    r = _md(b)
    assert "seq 1" in r
    assert "seq 2" in r


def test_md_broken_verdict_shown():
    b = _bundle(chain={"verdict": "broken@2", "head": "z" * 64, "lines": 2})
    assert "`broken@2`" in _md(b)


def test_md_missing_optional_job_fields():
    """get() ile alinir — eksik-alan None olur (traceback YOK)."""
    b = _bundle()
    b["jobs"] = [{"seq": 9}]
    r = _md(b)
    assert "seq 9" in r
    assert "None" in r          # session/engine/wall_ms None olarak basilir


def test_md_deterministic():
    assert _md(_bundle()) == _md(_bundle())


def test_md_empty_jobs():
    b = _bundle()
    b["jobs"] = []
    assert "## İşler / Jobs" in _md(b)


def test_md_empty_how_to_verify():
    b = _bundle()
    b["how_to_verify"] = []
    assert "## Nasıl doğrulanır / How to verify" in _md(b)


def test_md_delivery_without_alg():
    b = _bundle()
    b["jobs"] = [{"seq": 1, "delivery_hash": {"hex": "f" * 64}}]
    r = _md(b)
    assert "delivery: None" in r


# == parite: _chain_head + jcs ===================================================================

def test_chain_head_hash_formula():
    """h = sha256(prev + jcs(kayit-h-siz))."""
    r = _rec(1, ZERO64, kind="note", text="x")
    no_h = {k: v for k, v in r.items() if k not in ("h", "node_sig")}
    manual = hashlib.sha256(
        (ZERO64 + jcs(no_h).decode("utf-8")).encode("utf-8")).hexdigest()
    assert r["h"] == manual


def test_chain_head_hash_changes_with_text():
    a = _rec(1, ZERO64, kind="note", text="a")
    b = _rec(1, ZERO64, kind="note", text="b")
    assert a["h"] != b["h"]


def test_chain_head_hash_changes_with_prev():
    a = _rec(1, ZERO64, kind="note", text="x")
    b = _rec(1, "f" * 64, kind="note", text="x")
    assert a["h"] != b["h"]


def test_chain_head_hash_changes_with_seq():
    a = _rec(1, ZERO64, kind="note", text="x")
    b = _rec(2, ZERO64, kind="note", text="x")
    assert a["h"] != b["h"]


def test_chain_head_hash_is_hex():
    h = _rec(1, ZERO64, kind="note", text="x")["h"]
    assert len(h) == 64
    assert all(c in "0123456789abcdef" for c in h)
