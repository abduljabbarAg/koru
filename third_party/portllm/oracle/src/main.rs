// Dump glen's dequantised output for a block, for cross-checking.
include!("/root/koru/third_party/glen/src/quant.rs");
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let data = std::fs::read(&args[1]).expect("read");
    let dtype: u32 = args[2].parse().expect("dtype");
    let nb: usize = args[3].parse().expect("nblocks");
    let n = if dtype == 6 { 22 } else { 34 };
    for b in 0..nb {
        let blk = &data[b * n..(b + 1) * n];
        let v: Vec<f32> = if dtype == 6 { deq_q50(blk).to_vec() } else { deq_q80(blk).to_vec() };
        for x in v { print!("{:.6e} ", x); }
        println!();
    }
}
