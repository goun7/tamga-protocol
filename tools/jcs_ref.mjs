// Reference RFC 8785 (JCS) canonicalizer — Node.js.
// ECMAScript number-to-string and UTF-16 code-unit ordering are NATIVE here, so this is the
// cross-language oracle for tamga_canon.py (Python). Parity harness: tools/jcs_parity.sh
export function canon(v) {
  if (v === null) return "null";
  const t = typeof v;
  if (t === "boolean") return v ? "true" : "false";
  if (t === "number") return JSON.stringify(v);   // ECMAScript number-to-string: 1.0→"1"
  if (t === "string") return JSON.stringify(v);   // escapes only " \ and <0x20 — matches RFC 8785
  if (Array.isArray(v)) return "[" + v.map(canon).join(",") + "]";
  if (t === "object") {
    const keys = Object.keys(v).sort();           // JS sort is by UTF-16 code units (RFC 8785 §3.2.3)
    return "{" + keys.map((k) => JSON.stringify(k) + ":" + canon(v[k])).join(",") + "}";
  }
  throw new TypeError("unsupported canonical value: " + t);
}

