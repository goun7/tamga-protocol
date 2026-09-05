// Tamga örnek ajanı — v2 (Dilim-11): girdi OKUR, deterministik iş yapar.
// stdin'i bitişine kadar okur, SHA-256 içerik-parmakizini çıktıya yazar.
// Tamga-sözleşmesi: stdout'un İLK satırı "TAMGA:<cikti_sha256>" kanıt-satırıdır.
// Rust'ta sha2 yok (sıfır-bağımlılık çekirdeği): deterministik toplama yerine
// FNV-1a 64-bit parmakizi (std-only) + uzunluk; her ikisi de hex olarak basılır.
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
