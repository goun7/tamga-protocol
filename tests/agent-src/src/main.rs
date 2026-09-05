// Tamga example agent — v2 (slice-11): READS input, does deterministic work.
// Reads stdin to EOF and writes a SHA-256 content fingerprint into its output.
// Tamga contract: the FIRST line of stdout is the "TAMGA:<output_sha256>" evidence line.
// No sha2 crate in Rust here (zero-dependency core): instead of a deterministic sum,
// an FNV-1a 64-bit fingerprint (std-only) + length; both printed as hex.
use std::io::Read;

fn fnv1a64(data: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for &b in data {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

fn main() {
    let mut input = Vec::new();
    let _ = std::io::stdin().read_to_end(&mut input);
    let fp = fnv1a64(&input);
    let output = format!(
        "TAMGA:v2 girdi-parmakizi fnv1a64={:016x} uzunluk={}\noturum: girdili koşum tamam\n",
        fp,
        input.len()
    );
    print!("{}", output);

    // kanıt-satırı: ÇIKTInın kendi parmakizi — runner bunu doğrular (RED 12 aksi halde)
    let out_fp = fnv1a64(output.as_bytes());
    println!("TAMGA:{:016x}", out_fp);
}
