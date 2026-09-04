use std::time::{Duration, Instant};
fn main() {
    let start = Instant::now();
    let mut spins: u64 = 0;
    while start.elapsed() < Duration::from_secs(3) { spins = spins.wrapping_add(1); }
    println!("c-smoke: {} sn tamam", start.elapsed().as_secs());
}
