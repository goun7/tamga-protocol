#!/usr/bin/env python3
"""Multi-format memory importer → Tamga memory JSON (tamga-memory/1).

Purpose: a zero-friction on-ramp for existing agent memories (Phase-2 roadmap item).
Reads an export file, converts every record into Tamga ADD-only memory nodes, and
prints a JSON document consumable by:

    python3 tamga_runner.py memory <pkg> --import-json converted.json

Design rules:
- The source file is opened READ-ONLY. No writes to the source.
- Deterministic node ids (h<sha256-12>) → re-importing the same source is idempotent
  (Tamga's ADD-only merge skips existing nodes).
- Tolerant field mapping: any record that carries a text-like field
  ("memory", "text", "content", "fact", "value", "summary") becomes a node.
  Extra fields are preserved under "meta" (bounded: 8 keys, 256 chars per value).

Formats:
  auto     sniff: JSON list → mem0/letta/zep/generic by field shape; JSONL → jsonl
  jsonl    one JSON object per line (or bare strings)
  mem0     Mem0 export: list of {"memory": str, "user_id": str, ...}
  letta    Letta export: {"archival_memory": [...]} or list of {"text": str, ...}
  zep      Zep export: {"facts": [...]} / {"memories": [...]} or list of {"fact": str, ...}
  generic  list of objects with any text-like field (fallback)

Usage:
  python3 tools/memory_import.py --from export.json --format auto -o out.json
  python3 tools/memory_import.py --from export.jsonl --format jsonl | \
      python3 tamga_runner.py memory pkg --import-json /dev/stdin
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

MAX_BYTES = 64 << 20          # same safe envelope as snapshots
MAX_RECORDS = 200_000
TEXT_FIELDS = ("memory", "text", "content", "fact", "value", "summary")
MAX_META_KEYS = 8
MAX_META_VALUE = 256
NODE_ID_PREFIX = "x"          # importer id-space; never collides with m1.. probe ids


def _node_id(text: str, user: str) -> str:
    h = hashlib.sha256(f"{user}\x00{text}".encode()).hexdigest()[:12]
    return f"{NODE_ID_PREFIX}{h}"


def _meta(rec: dict) -> dict:
    out = {}
    for k, v in sorted(rec.items()):
        if k in TEXT_FIELDS or k in ("id",):
            continue
        if isinstance(v, (str, int, float, bool)) and len(str(v)) <= MAX_META_VALUE:
            if len(out) < MAX_META_KEYS:
                out[k] = v
    return out


def _records_from_list(items: list) -> list[dict]:
    recs = []
    for it in items:
        if isinstance(it, str):
            recs.append({"text": it})
        elif isinstance(it, dict):
            recs.append(it)
    return recs


def load_records(data, fmt: str) -> list[dict]:
    """Extract text records from any supported shape."""
    if fmt == "jsonl":
        recs = []
        for line in data.splitlines():
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if isinstance(obj, str):
                obj = {"text": obj}
            recs.append(obj)
        return recs

    # container unwrapping
    if isinstance(data, dict):
        for key in ("archival_memory", "facts", "memories", "memories_v2", "results", "items", "data"):
            if key in data and isinstance(data[key], list):
                data = data[key]
                break
    if isinstance(data, dict):   # still a dict → maybe single record
        data = [data]
    if not isinstance(data, list):
        raise ValueError("unsupported root shape: expected list or known container")

    recs = _records_from_list(data)
    # mem0/letta/zep nested shapes: {"memory": {...}} / {"memory": "text"} etc.
    out = []
    for r in recs:
        if isinstance(r.get("memory"), dict) and any(f in r["memory"] for f in TEXT_FIELDS):
            m = dict(r["memory"]); m.setdefault("user_id", r.get("user_id"))
            out.append(m)
        else:
            out.append(r)
    return out


def to_memory(recs: list[dict]) -> dict:
    nodes, seen = [], set()
    for r in recs:
        text = next((str(r[f]).strip() for f in TEXT_FIELDS if r.get(f)), None)
        if not text:
            continue
        user = str(r.get("user_id") or r.get("user") or r.get("agent_id") or "")
        nid = _node_id(text, user)
        if nid in seen:
            continue
        seen.add(nid)
        node = {"id": nid, "kind": "fact", "text": text}
        meta = _meta(r)
        if meta:
            node["meta"] = meta
        nodes.append(node)
    return {"format": "tamga-memory/1", "nodes": nodes, "edges": []}


def sniff(path: Path, data) -> str:
    if path.suffix == ".jsonl":
        return "jsonl"
    if isinstance(data, list):
        if data and all(isinstance(x, dict) and "memory" in x for x in data[:20]):
            return "mem0"
        return "generic"
    if isinstance(data, dict):
        if "archival_memory" in data:
            return "letta"
        if "facts" in data or "memories" in data:
            return "zep"
    return "generic"


def main() -> int:
    ap = argparse.ArgumentParser(description="Export → Tamga memory JSON (ADD-only import ready)")
    ap.add_argument("--from", dest="src", required=True, help="export file (read-only)")
    ap.add_argument("--format", default="auto",
                    choices=["auto", "jsonl", "mem0", "letta", "zep", "generic"])
    ap.add_argument("-o", "--out", default="-", help="output file ('-' = stdout)")
    a = ap.parse_args()

    src = Path(a.src)
    raw = src.read_bytes()
    if len(raw) > MAX_BYTES:
        print(f"source too large: {len(raw)} > {MAX_BYTES} bytes", file=sys.stderr)
        return 2
    src_len = len(raw)

    if a.format == "jsonl" or (a.format == "auto" and src.suffix == ".jsonl"):
        recs = load_records(raw.decode("utf-8", "replace"), "jsonl")
    else:
        try:
            data = json.loads(raw.decode("utf-8", "replace"))
        except json.JSONDecodeError as e:
            print(f"invalid JSON: {e}", file=sys.stderr)
            return 2
        fmt = sniff(src, data) if a.format == "auto" else a.format
        recs = load_records(data, fmt)

    if len(recs) > MAX_RECORDS:
        print(f"too many records: {len(recs)} > {MAX_RECORDS}", file=sys.stderr)
        return 2

    memory = to_memory(recs)
    memory["nodes"].sort(key=lambda n: n["id"])           # deterministic output
    payload = json.dumps(memory, ensure_ascii=False, indent=1)
    print(f"ok: {len(memory['nodes'])} nodes from {len(recs)} records ({a.format})", file=sys.stderr)

    if a.out == "-":
        print(payload)
    else:
        Path(a.out).write_text(payload + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
