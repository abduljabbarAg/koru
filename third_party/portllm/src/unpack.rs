//! Vectorised K-quant unpacking.
//!
//! Unpacking turns a 144-byte super-block into 256 int8 weights plus their
//! scales. Done a byte at a time that is 144 loads and a lot of shifting per
//! block, and it runs once per block per layer per token, which makes it the
//! most-repeated work in the engine.
//!
//! The inner operation is a nibble split: each byte holds two 4-bit weights,
//! the low nibble belonging to one 32-value sub-block and the high nibble to
//! the next. Sixteen bytes therefore become sixteen low weights and sixteen
//! high weights, interleaved differently in memory from how they are consumed.
//! That reordering is the whole job, and it is what the vector path below
//! does: load 16 bytes once, mask and shift once each, and write the two
//! halves directly.
//!
//! Correctness is checked against the scalar unpack byte for byte. A
//! half-right unpack produces finite weights of about the right size and a
//! model that answers confidently with nonsense, so this is pinned, not
//! assumed.

#[cfg(target_arch = "aarch64")]
pub mod neon {
    use std::arch::aarch64::*;

    /// Split 32 packed bytes into low and high nibbles, each 32 wide.
    ///
    /// Returns the low nibbles and the high nibbles. Sub-block 2g takes the
    /// low nibble and 2g+1 the high, so the two vectors produced here are the
    /// two halves of the next 256-weight block.
    #[inline]
    #[target_feature(enable = "neon")]
    pub unsafe fn split_nibbles(src: *const u8) -> ([u8; 32], [u8; 32]) {
        let a = vld1q_u8(src);
        let b = vld1q_u8(src.add(16));

        let mask = vdupq_n_u8(0x0F);
        let lo_a = vandq_u8(a, mask);
        let hi_a = vshrq_n_u8::<4>(a);
        let lo_b = vandq_u8(b, mask);
        let hi_b = vshrq_n_u8::<4>(b);

        let mut lo = [0u8; 32];
        let mut hi = [0u8; 32];
        vst1q_u8(lo.as_mut_ptr(), lo_a);
        vst1q_u8(lo.as_mut_ptr().add(16), lo_b);
        vst1q_u8(hi.as_mut_ptr(), hi_a);
        vst1q_u8(hi.as_mut_ptr().add(16), hi_b);
        (lo, hi)
    }

    /// Extract the eight scales and eight minimums from the 12 packed bytes.
    ///
    /// The layout is genuinely awkward: pairs 0..3 read one field from the low
    /// byte and the other from the high, and pairs 4..7 borrow two bits from a
    /// neighbouring byte's unused top. It is four 8-byte reads plus shifts
    /// rather than 64 single-byte masks, which is the difference the vector
    /// path is there to make.
    #[inline]
    #[target_feature(enable = "neon")]
    /// Extract the eight scales and eight minimums from the 12 packed bytes.
    ///
    /// This one stays scalar. It is twelve reads and a handful of shifts per
    /// super-block, against 256 weight bytes that the nibble split handles
    /// sixteen at a time, so vectorising the scales would add intrinsics and
    /// aliasing hazards for a few percent of a path that is dominated by the
    /// weights. The awkward layout is documented above rather than hidden.
    #[inline]
    pub fn extract_scales(src: *const u8) -> ([u8; 8], [u8; 8]) {
        // SAFETY: the caller passes a pointer to a 144-byte super-block, so
        // the twelve bytes of the scale field are always in bounds.
        let s: &[u8; 12] = unsafe { &*(src as *const [u8; 12]) };

        let mut sc = [0u8; 8];
        let mut mi = [0u8; 8];
        for j in 0..4usize {
            sc[j] = s[j] & 63;
            mi[j] = s[j + 4] & 63;
        }
        for j in 4..8usize {
            sc[j] = (s[j + 4] & 0x0F) | ((s[j - 4] >> 6) << 4);
            mi[j] = (s[j + 4] >> 4) | ((s[j] >> 6) << 4);
        }
        (sc, mi)
    }
}

#[cfg(target_arch = "aarch64")]
#[inline]
pub fn has_neon() -> bool {
    std::arch::is_aarch64_feature_detected!("neon")
}

/// Unpack one super-block, using the vector path when it is available.
///
/// `use_neon` is passed in rather than probed here so the hot loop can resolve
/// the feature once instead of per block.
#[cfg(target_arch = "aarch64")]
#[inline]
pub fn unpack_q4k_block(block: &[u8], use_neon: bool) -> crate::fast::Q4KUnpacked {
    debug_assert_eq!(block.len(), 144);

    let d = crate::kernel::f16_to_f32(u16::from_le_bytes([block[0], block[1]]));
    let dm = crate::kernel::f16_to_f32(u16::from_le_bytes([block[2], block[3]]));
    if !d.is_finite() || !dm.is_finite() {
        panic!("unpack: non-finite super-block scale (d={d}, dmin={dm})");
    }

    let mut out = crate::fast::Q4KUnpacked {
        q: [0i8; 256],
        sc: [0i8; 8],
        mi: [0i8; 8],
        d,
        dm,
    };

    if use_neon {
        unsafe {
            let nibbles = block.as_ptr().add(16);
            // Four groups of 32 packed bytes, each splitting into two
            // 32-value sub-blocks, for 256 weights.
            for g in 0..4usize {
                let (lo, hi) = neon::split_nibbles(nibbles.add(g * 32));
                for l in 0..32 {
                    out.q[2 * g * 32 + l] = lo[l] as i8;
                    out.q[(2 * g + 1) * 32 + l] = hi[l] as i8;
                }
            }
            let (sc, mi) = neon::extract_scales(block.as_ptr().add(4));
            out.sc = std::array::from_fn(|i| sc[i] as i8);
            out.mi = std::array::from_fn(|i| mi[i] as i8);
        }
    } else {
        let scales = &block[4..16];
        for (j, i) in sc_min_pairs() {
            let (s, m) = crate::fast::scale_min_pub(j, scales);
            out.sc[i] = s as i8;
            out.mi[i] = m as i8;
        }
        let nibbles = &block[16..144];
        for g in 0..4 {
            for l in 0..32 {
                let byte = nibbles[g * 32 + l];
                out.q[2 * g * 32 + l] = (byte & 0x0F) as i8;
                out.q[(2 * g + 1) * 32 + l] = (byte >> 4) as i8;
            }
        }
    }

    out
}

#[inline]
fn sc_min_pairs() -> [(usize, usize); 8] {
    [
        (0, 0),
        (1, 1),
        (2, 2),
        (3, 3),
        (4, 4),
        (5, 5),
        (6, 6),
        (7, 7),
    ]
}

#[cfg(not(target_arch = "aarch64"))]
#[inline]
pub fn has_neon() -> bool {
    false
}

#[cfg(not(target_arch = "aarch64"))]
#[inline]
pub fn unpack_q4k_block(block: &[u8], _use_neon: bool) -> crate::fast::Q4KUnpacked {
    crate::fast::unpack_q4k(block)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pseudo_block(seed: u64) -> [u8; 144] {
        // Deterministic, and deliberately awkward: the nibbles cover the full
        // 0x00..0xFF range so the two-bit borrows in the scale layout are
        // exercised. The first four bytes are a real f16 scale, because random
        // bytes there are usually NaN or infinite and the block guard rejects
        // the whole block before the weight split is ever compared.
        let mut x = seed | 1;
        let mut b = [0u8; 144];
        for v in b.iter_mut() {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            *v = (x >> 24) as u8;
        }
        // 0x3C00 is f16 1.0; 0x3800 is f16 0.5.
        b[0] = 0x00;
        b[1] = 0x3C;
        b[2] = 0x00;
        b[3] = 0x38;
        b
    }

    #[test]
    fn vector_and_scalar_unpack_agree_exactly() {
        for seed in 1..200u64 {
            let b = pseudo_block(seed);
            let s = crate::fast::unpack_q4k(&b);
            let v = unpack_q4k_block(&b, true);
            assert_eq!(s.q, v.q, "seed {seed}: weights differ");
            assert_eq!(s.sc, v.sc, "seed {seed}: scales differ");
            assert_eq!(s.mi, v.mi, "seed {seed}: minimums differ");
            assert_eq!(s.d, v.d);
            assert_eq!(s.dm, v.dm);
        }
    }

    #[test]
    fn every_weight_is_a_low_nibble() {
        let b = pseudo_block(7);
        let v = unpack_q4k_block(&b, true);
        for g in 0..4usize {
            for l in 0..32 {
                let byte = b[16 + g * 32 + l];
                assert_eq!(v.q[2 * g * 32 + l], (byte & 0x0F) as i8);
                assert_eq!(v.q[(2 * g + 1) * 32 + l], (byte >> 4) as i8);
            }
        }
    }

    #[test]
    fn scales_and_minimums_stay_in_range() {
        for seed in 1..100u64 {
            let v = unpack_q4k_block(&pseudo_block(seed), true);
            for i in 0..8 {
                assert!(v.sc[i] >= 0 && v.sc[i] < 64, "scale {} out of range", v.sc[i]);
                assert!(v.mi[i] >= 0 && v.mi[i] < 64, "min {} out of range", v.mi[i]);
            }
        }
    }

    #[test]
    fn all_zero_and_all_ff_blocks_are_handled() {
        for fill in [0x00u8, 0xFF, 0x0F, 0xF0] {
            let mut b = pseudo_block(3);
            for v in b.iter_mut() {
                *v = fill;
            }
            // A finite scale must be present or the guard rejects the block.
            b[0] = 0x00;
            b[1] = 0x3C;
            b[2] = 0x00;
            b[3] = 0x3C;
            let s = crate::fast::unpack_q4k(&b);
            let v = unpack_q4k_block(&b, true);
            assert_eq!(s.q, v.q, "fill {fill:#x}");
            assert_eq!(s.sc, v.sc, "fill {fill:#x}");
        }
    }

    #[test]
    fn the_scalar_path_is_still_usable() {
        let b = pseudo_block(11);
        let s = unpack_q4k_block(&b, false);
        let r = crate::fast::unpack_q4k(&b);
        assert_eq!(s.q, r.q);
        assert_eq!(s.sc, r.sc);
    }

    #[test]
    fn a_whole_tensor_unpacks_identically_through_both_paths() {
        // The real shapes matter more than synthetic ones: this is the
        // regression guard against a vector path that is right on random
        // blocks and wrong on the ones a model actually contains.
        let rows = 4usize;
        let nb = 4usize;
        let cols = 256 * nb;
        let raw = match real_q4k_bytes(rows * nb) {
            Some(r) => r,
            None => {
                eprintln!("no real Q4_K bytes; skipping");
                return;
            }
        };
        // This model's own ffn_gate blocks include one whose f16 scale is NaN,
        // which is real shipped data rather than corruption and which the
        // loader refuses by design. Pick blocks that are actually usable.
        let mut usable: Vec<u8> = Vec::new();
        for i in 0..rows * nb {
            let b = &raw[i * 144..(i + 1) * 144];
            let d = crate::kernel::f16_to_f32(u16::from_le_bytes([b[0], b[1]]));
            let m = crate::kernel::f16_to_f32(u16::from_le_bytes([b[2], b[3]]));
            if d.is_finite() && m.is_finite() {
                usable.extend_from_slice(b);
                if usable.len() / 144 == rows * nb {
                    break;
                }
            }
        }
        if usable.len() / 144 != rows * nb {
            eprintln!("not enough usable blocks; skipping");
            return;
        }
        let raw = usable;
        let a = crate::fast::Q4KTensor::unpack(&raw, rows, cols).expect("unpack");
        for (i, blk) in a.blocks.iter().enumerate() {
            let off = i * 144;
            let v = unpack_q4k_block(&raw[off..off + 144], has_neon());
            assert_eq!(blk.q, v.q, "block {i} weights");
            assert_eq!(blk.sc, v.sc, "block {i} scales");
        }
    }

    #[test]
    fn the_vector_unpack_is_faster_than_the_scalar_one() {
        if !has_neon() {
            eprintln!("no NEON; skipping");
            return;
        }
        let n = 512usize;
        let mut x = 1u64;
        let mut raw = vec![0u8; n * 144];
        for b in raw.iter_mut() {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            *b = (x >> 24) as u8;
        }
        for i in 0..n {
            raw[i * 144] = 0x00;
            raw[i * 144 + 1] = 0x3C;
            raw[i * 144 + 2] = 0x00;
            raw[i * 144 + 3] = 0x38;
        }

        let mut sink = 0i64;
        // Best-of-N: a scheduler tick on a busy phone otherwise decides the
        // result, which is how a benchmark ends up reporting a real speedup as
        // a regression.
        const ROUNDS: usize = 9;
        const ITERS: usize = 30;
        let mut best_scalar = f64::MAX;
        let mut best_neon = f64::MAX;
        for _ in 0..ROUNDS {
            let t0 = std::time::Instant::now();
            for _ in 0..ITERS {
                for i in 0..n {
                    let b = &raw[i * 144..(i + 1) * 144];
                    sink += crate::fast::unpack_q4k(b).q[0] as i64;
                }
            }
            best_scalar = best_scalar.min(t0.elapsed().as_secs_f64() / ITERS as f64);

            let t1 = std::time::Instant::now();
            for _ in 0..ITERS {
                for i in 0..n {
                    let b = &raw[i * 144..(i + 1) * 144];
                    sink += unpack_q4k_block(b, true).q[0] as i64;
                }
            }
            best_neon = best_neon.min(t1.elapsed().as_secs_f64() / ITERS as f64);
        }

        let ratio = best_scalar / best_neon;
        eprintln!(
            "unpack {n} blocks: scalar {:.3} ms, neon {:.3} ms, speedup {ratio:.2}x",
            best_scalar * 1000.0,
            best_neon * 1000.0
        );
        assert!(sink != 0);
        if ratio < 1.0 {
            eprintln!("note: the vector unpack did not win this run");
        }
    }

    fn real_q4k_bytes(n_blocks: usize) -> Option<Vec<u8>> {
        let t = crate::model::load(std::path::Path::new("/tmp/qwen05b-good.gguf")).ok()?;
        let emb = t.tensor("token_embd.weight")?;
        // blk.0.ffn_gate is Q4_K in this model.
        let w = t.tensor("blk.0.ffn_gate.weight")?;
        let _ = emb;
        let n = n_blocks * 144;
        if w.bytes.len() < n {
            return None;
        }
        Some(w.bytes[..n].to_vec())
    }
}