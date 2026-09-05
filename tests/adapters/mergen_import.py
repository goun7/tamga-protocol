#!/usr/bin/env python3
"""MERGEN → Tamga hafıza aktarıcı (Faz 2, L2 — MERGEN-ENTEGRASYON-NOTU §L2) v2.

AMAÇ: MERGEN SQLite'ındaki kayıtları Tamga bağlam-grafik JSON'una çevirir;
çıktı `memory --import-json` ile snapshot'a eklenir. Çalıştırma TAMAMEN LOKALDİR —
araç ağa bağlanmaz, veri yalnız makine içinde akar; repo'ya yalnız SENTETİK fixture girer.

Kullanım:
  python3 tests/adapters/mergen_import.py <mergen.db> --out cikti.json [--mode generic]
  python3 tests/adapters/mergen_import.py <mergen.db> --out cikti.json [--mode mergen]

--mode mergen (v2, 2026-09-05): MERGEN v1.6.1 GERÇEK şeması (canlı okumayla doğrulandı:
/mnt/hdd/projects/MERGEN/mergen_tools/mergen_memory/projects/*.db):
    memories(id, timestamp, problem, solution, tier, is_deprecated, superseded_by_id...)
    relations(source_id, target_id, relation_type)
Eşleme: ders = problem+solution → kind:fact (superseded olanlar kind:archived);
ID UZAYI: m{900000+mergen_id} — Tamga probe-id'leriyle (m1..m5) ÇAKIŞMAZ; runner
"m+digit korunur" kuralı bu ad-uzayını mekanik olarak destekler.
metadata alıkonulur (tier, kaynak id "mergen:M<id>"); relations → Tamga edges
(m_ids Tamga node-id'siyle eşlenir; m-kuralı: id'siz düğümün id'si "m"+satır-no
kuralına göre import'ta korunur — runner: raw[1:].isdigit → nid=raw).
--mode generic: v1 davranışı (--table/--id-col/--text-col/--ts-col).

Güvenlik: kaynak DB okunur, ASLA silinmez/değiştirilmez; çıktı JSON kullanıcıya
aittir. Gerçek kişisel veriyle çalıştırmadan önce KOPYA üzerinde deneyin.
"""
import argparse, json, pathlib, re, sqlite3, sys

M_ID_OFFSET = 900000   # MERGEN id → çakışmasız Tamga m-uzayı (docstring: ID UZAYI)


def mode_mergen(db_path):
    """MERGEN v1.6.1 gerçek şeması → Tamga nodes+edges."""
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    try:
        mem_rows = con.execute(
            "SELECT id, timestamp, problem, solution, tier, is_deprecated, "
            "superseded_by_id FROM memories ORDER BY id").fetchall()
        rel_rows = con.execute(
            "SELECT source_id, target_id, relation_type FROM relations").fetchall()
    finally:
        con.close()
    nodes, edges, idmap = [], [], {}
    for r in mem_rows:
        tid = r["id"]
        problem = (r["problem"] or "").strip()
        solution = (r["solution"] or "").strip()
        text = (problem + (" → " + solution if solution else "")).strip()
        if not text:
            continue
        deprecated = bool(r["is_deprecated"])
        node = {"id": f"m{M_ID_OFFSET + tid}",                       # import kuralı korunur (m+digit)
                "kind": "archived" if deprecated else "fact",
                "text": text[:60000],                   # MAX_NOTE_BYTES 64KB marjı
                "ts": str(r["timestamp"] or "") or None,
                "src": f"mergen:memories:{tid}"}
        if r["tier"]:
            node["meta"] = {"tier": str(r["tier"])}
        if deprecated and r["superseded_by_id"]:
            node["supersedes"] = f"m{M_ID_OFFSET + r['superseded_by_id']}"
        nodes.append(node)
        idmap[tid] = node
    for r in rel_rows:
        s, t2 = idmap.get(r["source_id"]), idmap.get(r["target_id"])
        if s and t2:
            edges.append([s["id"], t2["id"], str(r["relation_type"] or "ref")])
    return {"format": "tamga-memory-import/1", "nodes": nodes, "edges": edges,
            "istatistik": {"memories": len(mem_rows), "aktarilan": len(nodes),
                           "relations": len(rel_rows), "edges": len(edges)}}


def mode_generic(a):
    """v1: genel SQLite şeması (bayraklarla eşleme)."""
    ident = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")   # Audit-10: SQL identifier enjeksiyonu kapalı
    for name in (a.table, a.id_col, a.text_col, a.ts_col):
        if not ident.match(name):
            return {"ok": False, "reason": f"geçersiz identifier: {name!r}"}
    con = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA query_only=ON")               # ikinci katman: motor-düzeyi salt-okunur
    try:
        rows = con.execute(f"SELECT {a.id_col}, {a.text_col}, {a.ts_col} FROM {a.table}").fetchall()
    except sqlite3.OperationalError as e:
        return {"ok": False, "reason": f"tablo/kolon eşleşmedi: {e}",
                "ipucu": "--table/--id-col/--text-col/--ts-col bayraklarını kullanın"}
    finally:
        con.close()
    nodes = []
    for r in rows:
        text = str(r[a.text_col] or "").strip()
        if not text:
            continue
        nodes.append({"kind": "note", "text": text,
                      "ts": str(r[a.ts_col] or "") or None})
    return {"format": "tamga-memory-import/1", "nodes": nodes, "edges": [],
            "istatistik": {"kaynak_satir": len(rows), "aktarilan": len(nodes)}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("db", help="MERGEN SQLite dosyası (yalnız OKUNUR)")
    ap.add_argument("--out", required=True, help="çıktı JSON (Tamga memory biçimi)")
    ap.add_argument("--mode", default="mergen", choices=["mergen", "generic"])
    ap.add_argument("--table", default="lessons")
    ap.add_argument("--id-col", default="id")
    ap.add_argument("--text-col", default="text")
    ap.add_argument("--ts-col", default="created_at")
    a = ap.parse_args()

    src = pathlib.Path(a.db)
    if not src.exists():
        print(json.dumps({"ok": False, "reason": "kaynak DB yok"})); return 1
    # read-only URI: kaynağa yazım YOK (denetim garantisi)
    out = mode_mergen(src) if a.mode == "mergen" else mode_generic(a)
    if out.get("ok") is False:
        print(json.dumps(out, ensure_ascii=False)); return 1
    pathlib.Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    st = out.get("istatistik", {})
    print(json.dumps({"ok": True, "çıktı": a.out, "istatistik": st,
                      "not": "import: python3 tamga_runner.py memory <pkg> --import-json " + a.out}))
    return 0

if __name__ == "__main__":
    sys.exit(main())
