use std::time::{Duration, Instant};
fn main() {
    let start = Instant::now();
    let mut spins: u64 = 0;
    while start.elapsed() < Duration::from_secs(31) { spins = spins.wrapping_add(1); }
    println!("c30: {} sn kosum tamam (spins={})", start.elapsed().as_secs(), spins);
}
