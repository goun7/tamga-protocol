// Tamga net-demo agent (RFC-006 D13, slice-4): speaks the framed stdin contract when
// the runner announces `TAMGA-STDIN-1 <len>`, otherwise falls back to legacy stdin.
// If the input contains the "net_demo" directive, emits ONE TAMGA-NET-1 request line,
// FLUSHES stdout (mandatory: the runner serves responses over stdin), reads the
// response line, and reports status. std-only: tiny b64 encoder, naive JSON field
// extraction — this is a fixture, not a general-purpose HTTP client.
use std::io::{self, BufRead, Read, Write};

fn fnv1a64(data: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for &b in data {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
fn b64(data: &[u8]) -> String {
    let mut out = String::new();
    for ch in data.chunks(3) {
        let b = [ch[0], *ch.get(1).unwrap_or(&0), *ch.get(2).unwrap_or(&0)];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(B64[(n >> 18) as usize & 63] as char);
        out.push(B64[(n >> 12) as usize & 63] as char);
        out.push(if ch.len() > 1 { B64[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if ch.len() > 2 { B64[n as usize & 63] as char } else { '=' });
    }
    out
}

fn field(s: &str, key: &str) -> Option<String> {
    // whitespace-tolerant string OR numeric value after "key":
    for pat in [format!("\"{}\":\"", key), format!("\"{}\": \"", key),
                format!("\"{}\":", key), format!("\"{}\": ", key)] {
        if let Some(i) = s.find(&pat) {
            let rest = &s[i + pat.len()..];
            let end = rest.find(|c| c == '"' || c == ',' || c == '}').unwrap_or(rest.len());
            if end == 0 { continue; }
            let v = rest[..end].trim_matches('"');
            if !v.is_empty() {
                return Some(v.to_string());
            }
        }
    }
    None
}

fn read_line(r: &mut impl BufRead) -> String {
    let mut s = String::new();
    let _ = r.read_line(&mut s);
    s
}

fn main() {
    let stdin = io::stdin();
    let mut r = stdin.lock();
    let first = read_line(&mut r);
    let input: Vec<u8> = if let Some(rest) = first.strip_prefix("TAMGA-STDIN-1 ") {
        let len: usize = rest.trim().parse().unwrap_or(0);
        let mut buf = vec![0u8; len];
        let _ = r.read_exact(&mut buf);
        buf
    } else {
        // legacy path: the first line belongs to the input; consume the rest to EOF
        let mut v = first.clone().into_bytes();
        let _ = r.read_to_end(&mut v);
        v
    };
    let input_str = String::from_utf8_lossy(&input).to_string();

    let mut status_report = String::from("no_request");
    // proof covers EVERY byte this agent emits (request line included)
    let mut emitted: Vec<u8> = Vec::new();
    if input_str.contains("net_demo") {
        let url = field(&input_str, "url").unwrap_or_default();
        let payload = field(&input_str, "payload").unwrap_or_default();
        let req = format!(
            "TAMGA-NET-1 {{\"id\":1,\"method\":\"POST\",\"url\":\"{}\",\"headers\":{{\"Content-Type\":\"application/json\"}},\"body_b64\":\"{}\"}}\n",
            url,
            b64(payload.as_bytes())
        );
        let _ = io::stdout().write_all(req.as_bytes());
        let _ = io::stdout().flush();   // MANDATORY before waiting on stdin (RFC-006 §2)
        emitted.extend_from_slice(req.as_bytes());
        let resp = read_line(&mut r);
        if let Some(rest) = resp.strip_prefix("TAMGA-NET-RESP-1 ") {
            let status = field(rest, "status").unwrap_or_else(|| "?".into());
            let ok = rest.contains("\"ok\":true");
            let body_b64 = field(rest, "body_b64").unwrap_or_default();
            let blen = body_b64.len() * 3 / 4 - body_b64.matches('=').count();
            status_report = format!("status={} ok={} body_len={}", status, ok, blen);
        } else {
            status_report = String::from("no_response");
        }
    }

    let output = format!(
        "NET-DEMO:{}\nTAMGA:v2 girdi-parmakizi fnv1a64={:016x} uzunluk={}\n",
        status_report,
        fnv1a64(&input),
        input.len()
    );
    let _ = io::stdout().write_all(output.as_bytes());
    emitted.extend_from_slice(output.as_bytes());
    // kanıt-satırı: bastığı TÜM baytların (istek-satırı dahil) parmakizi
    let out_fp = fnv1a64(&emitted);
    println!("TAMGA:{:016x}", out_fp);
}
