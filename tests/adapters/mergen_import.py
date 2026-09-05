#!/usr/bin/env python3
"""MERGEN → Tamga hafıza aktarıcı (Faz 2, L2 — MERGEN-ENTEGRASYON-NOTU §L2).

AMAÇ: MERGEN SQLite'ındaki kayıtları Tamga bağlam-grafik JSON'una çevirir;
çıktı `memory --import-json` ile snapshot'a eklenir. Çalıştırma TAMAMEN LOKALDİR —
araç ağa bağlanmaz, veri yalnız makine içinde akar; repo'ya yalnız SENTETİK fixture girer.

Kullanım:
  python3 tests/adapters/mergen_import.py <mergen.db> --out cikti.json \
      [--table lessons] [--id-col id] [--text-col text] [--ts-col created_at]

Şema notu (dürüst): MERGEN v1.6.1 gerçek şemasının zengin alanları (bi-temporal
valid_from/valid_to, CRDT, FTS) Faz 2'nin sonraki adımlarında eşlenir; bu ilk sürüm
minimal çekirdeği taşır (id/text/ts → Tamga not-düğümü + ADD-only). Gerçek DB'de
kolon adları farklıysa --table/--*-col bayraklarıyla eşlenir (şema-tahmini YOK).

Güvenlik: kaynak DB okunur, ASLA silinmez/değiştirilmez; çıktı JSON kullanıcıya
aittir. Gerçek kişisel veriyle çalıştırmadan önce KOPYA üzerinde deneyin.
"""
import argparse, json, pathlib, sqlite3, sys

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("db", help="MERGEN SQLite dosyası (yalnız OKUNUR)")
    ap.add_argument("--out", required=True, help="çıktı JSON (Tamga memory biçimi)")
    ap.add_argument("--table", default="lessons")
    ap.add_argument("--id-col", default="id")
    ap.add_argument("--text-col", default="text")
    ap.add_argument("--ts-col", default="created_at")
    a = ap.parse_args()

    src = pathlib.Path(a.db)
    if not src.exists():
        print(json.dumps({"ok": False, "reason": "kaynak DB yok"})); return 1
    con = sqlite3.connect(f"file:{src}?mode=ro", uri=True)   # read-only: kaynağa yazım YOK
    con.row_factory = sqlite3.Row
    try:
        rows = con.execute(f"SELECT {a.id_col}, {a.text_col}, {a.ts_col} FROM {a.table}").fetchall()
    except sqlite3.OperationalError as e:
        print(json.dumps({"ok": False, "reason": f"tablo/kolon eşleşmedi: {e}",
                          "ipucu": "--table/--id-col/--text-col/--ts-col bayraklarını kullanın"}))
        return 1
    nodes = []
    for r in rows:
        text = str(r[a.text_col] or "").strip()
        if not text:
            continue
        nodes.append({"kind": "note", "text": text,
                      "ts": str(r[a.ts_col] or "") or None,
                      "src": f"mergen:{a.table}:{r[a.id_col]}"})   # izlenebilirlik: kaynak kayıt
    # Tamga memory biçimi: nodes + edges (ADD-only import birleştirir; F22 parmakizi-dedup)
    out = {"format": "tamga-memory-import/1",
           "nodes": [{"kind": n["kind"], "text": n["text"], "ts": n["ts"]} for n in nodes],
           "edges": []}
    pathlib.Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({"ok": True, "kaynak_satir": len(rows), "aktarılan_düğüm": len(nodes),
                      "çıktı": a.out, "not": "import: python3 tamga_runner.py memory <pkg> --import-json " + a.out}))
    return 0

if __name__ == "__main__":
    sys.exit(main())
