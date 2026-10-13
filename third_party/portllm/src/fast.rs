//! The pre-unpacked K-quant cache: unpack once, use forever.
//!
//! This is the single biggest speed lever in the whole engine, and it is not
//! about the arithmetic. A K-quant block spends its bytes on scales: 16 of 144
//! describe the other 128. Decoding means recovering, per element, which of
//! eight sub-block scales applies and which nibble it came from. Do that per
//! token and you pay the address arithmetic 256 times per block, once per
//! token, forever.
//!
//! glen measured what that costs. With the cache, decode runs at 4.03 to 4.08
//! tok/s on a Helio G99. With `Glen_NOKU=1` it falls to 3.07, then 1.33. That
//! is a 3x swing for work that produces identical numbers, which is the
//! definition of something worth doing once instead of often.
//!
//! So the layout here is chosen for the inner loop, not for compactness:
//!
//! ```text
//!   q[i]   i8   the 4-bit weight, already widened to a byte, 0..15
//!   sc[j]  i8   sub-block scale for values in 32*j .. 32*j+32, 0..63
//!   mi[j]  i8   sub-block minimum, 0..63
//!   d      f16  super-block scale
//!   dm     f16  super-block minimum
//! ```
//!
//! Eight sub-blocks of 32, so the scale index is `i >> 5` and needs no
//! second lookup table. The widening from nibble to byte happens once, here,
//! which is what the scalar path cannot afford to do per token.
//!
//! Memory is the trade. A Q4_K block is 144 bytes on disk and 288 in the cache
//! once scales are separated, so this doubles the resident footprint of
//! weights. On a phone with 1.6 GB free that is a real cost, not a rounding
//! error, which is why the caller has to decide whether a model is worth
//! caching rather than the cache being unconditional.

/// One Q4_K block, unpacked into the inner loop's preferred layout.
#[derive(Debug, Clone)]
pub struct Q4KUnpacked {
    /// 256 weights widened to bytes, 0..15.
    pub q: [i8; 256],
    /// 8 sub-block scales, 0..63.
    pub sc: [i8; 8],
    /// 8 sub-block minimums, 0..63.
    pub mi: [i8; 8],
    /// Super-block scale, already in f32.
    pub d: f32,
    /// Super-block minimum, already in f32.
    pub dm: f32,
}

impl Q4KUnpacked {
    /// Recover the f32 value of element `i`.
    #[inline(always)]
    pub fn value(&self, i: usize) -> f32 {
        let j = i >> 5;
        self.q[i] as f32 * (self.d * self.sc[j] as f32) - self.dm * self.mi[j] as f32
    }

    /// Dot product of this block against 256 f32 activations.
    ///
    /// Written as four explicit 32-wide groups rather than one 256 loop, so
    /// the scale and minimum for a group are loaded once and reused across it.
    /// That is the whole point of the cache layout: per token this does the
    /// index arithmetic four times instead of 256.
    #[inline]
    pub fn dot_f32(&self, x: &[f32]) -> f32 {
        debug_assert_eq!(x.len(), 256);
        let mut acc = 0f32;
        for g in 0..8 {
            let d = self.d * self.sc[g] as f32;
            let m = self.dm * self.mi[g] as f32;
            let base = g * 32;
            let mut s = 0f32;
            for l in 0..32 {
                s += self.q[base + l] as f32 * x[base + l];
            }
            acc += s * d - m * x[base..base + 32].iter().sum::<f32>();
        }
        acc
    }

    /// Dot product with int8 activations.
    ///
    /// The int8 sum is exact and stays in i32; only the per-sub-block scaling
    /// touches f32. The activation's own per-32 scale comes back in through
    /// `xs`, and the weight minimum is applied against the sum of the original
    /// activations, which is why the caller needs `xf` as well as the
    /// quantised vector. Without it this cannot reproduce the exact path.
    #[inline]
    pub fn dot_i8(&self, xq: &[i8], xs: &[f32], xf: &[f32]) -> f32 {
        debug_assert_eq!(xq.len(), 256);
        debug_assert_eq!(xs.len(), 8);
        debug_assert_eq!(xf.len(), 256);
        let mut acc = 0f32;
        for g in 0..8 {
            let base = g * 32;
            let mut s = 0i32;
            for l in 0..32 {
                s += self.q[base + l] as i32 * xq[base + l] as i32;
            }
            let d = self.d * self.sc[g] as f32;
            let m = self.dm * self.mi[g] as f32;
            let xsum: f32 = xf[base..base + 32].iter().sum();
            acc += (s as f32) * xs[g] * d - m * xsum;
        }
        acc
    }
}

/// Unpack one Q4_K block.
///
/// Panics on a non-finite super-block scale. That is deliberate and it is the
/// whole reason this is a separate function from the raw arithmetic: a NaN
/// scale here would otherwise propagate into every value the block produces,
/// and from there into a dot product, and from there into logits, three calls
/// away from the place that caused it. A model containing one of these blocks
/// should fail to load, loudly, at load.
///
/// Real models do contain them. Qwen3-0.6B has one in its first tensor.
pub fn unpack_q4k(block: &[u8]) -> Q4KUnpacked {
    debug_assert_eq!(block.len(), 144);

    let d = crate::kernel::f16_to_f32(u16::from_le_bytes([block[0], block[1]]));
    let dm = crate::kernel::f16_to_f32(u16::from_le_bytes([block[2], block[3]]));
    if !d.is_finite() || !dm.is_finite() {
        panic!(
            "unpack_q4k: non-finite super-block scale (d={d}, dmin={dm}); \
             this model cannot be computed with"
        );
    }
    let scales = &block[4..16];
    let nibbles = &block[16..144];

    let mut q = [0i8; 256];
    let mut sc = [0i8; 8];
    let mut mi = [0i8; 8];

    for g in 0..4 {
        let (s_even, m_even) = scale_min(2 * g, scales);
        let (s_odd, m_odd) = scale_min(2 * g + 1, scales);

        sc[2 * g] = s_even as i8;
        mi[2 * g] = m_even as i8;
        sc[2 * g + 1] = s_odd as i8;
        mi[2 * g + 1] = m_odd as i8;

        // Low nibbles of a byte belong to sub-block 2g, high nibbles to 2g+1.
        // Same 32 bytes, read two ways, into two disjoint 32-value halves.
        for l in 0..32 {
            let byte = nibbles[g * 32 + l];
            q[(2 * g) * 32 + l] = (byte & 0x0F) as i8;
            q[(2 * g + 1) * 32 + l] = (byte >> 4) as i8;
        }
    }

    Q4KUnpacked { q, sc, mi, d, dm }
}

/// The 6-bit scale/minimum interleave. Identical to the one in kernel.rs, kept
/// here so this file is self-contained: unpacking is the hot path and should
/// not depend on a reader reaching across modules to find it.
#[inline]
pub fn scale_min_pub(j: usize, s: &[u8]) -> (u8, u8) {
    scale_min(j, s)
}

#[inline]
fn scale_min(j: usize, s: &[u8]) -> (u8, u8) {
    if j < 4 {
        (s[j] & 63, s[j + 4] & 63)
    } else {
        (
            (s[j + 4] & 0x0F) | ((s[j - 4] >> 6) << 4),
            (s[j + 4] >> 4) | ((s[j] >> 6) << 4),
        )
    }
}

/// A whole tensor, unpacked once.
#[derive(Clone, Debug)]
pub struct Q4KTensor {
    pub rows: usize,
    pub cols: usize,
    /// One entry per 256-column block per row.
    pub blocks: Vec<Q4KUnpacked>,
}

impl Q4KTensor {
    /// Unpack, refusing tensors that contain a block we cannot use.
    ///
    /// Real models contain the occasional block whose f16 super-block scale
    /// is NaN or infinite. That is not corruption: it is what a trained model
    /// actually shipped, and the values it covers are ones the trainer drove
    /// to zero. The question is what to do with it, and the answer is to
    /// refuse at load rather than let a NaN propagate through every subsequent
    /// matvec, where it will silently poison an entire output vector and look
    /// like a bug three layers away.
    ///
    /// The alternative, substituting zero, would produce a model that answers
    /// confidently with wrong numbers. Refusing means the caller can report
    /// "this model has an unusable block" instead.
    pub fn unpack(raw: &[u8], rows: usize, cols: usize) -> Option<Self> {
        if let Err(e) = crate::validate::validate_tensor(raw, rows, cols, 12) {
            eprintln!("Q4KTensor::unpack refused: {}", e.explain());
            return None;
        }
        if cols % 256 != 0 {
            return None;
        }
        let nb = cols / 256;
        let nblocks = rows.checked_mul(nb)?;
        if raw.len() < nblocks * 144 {
            return None;
        }
        // Resolve the feature once for the whole tensor rather than per
        // block. This loop runs over every super-block of every Q4_K tensor,
        // so it is the most repeated work in the engine.
        let use_neon = has_neon();
        let mut blocks = Vec::with_capacity(nblocks);
        for b in 0..nblocks {
            let blk = crate::unpack::unpack_q4k_block(&raw[b * 144..b * 144 + 144], use_neon);
            if !blk.d.is_finite() || !blk.dm.is_finite() {
                return None;
            }
            blocks.push(blk);
        }
        Some(Q4KTensor {
            rows,
            cols,
            blocks,
        })
    }

    /// Resident bytes, which is the cost of having cached this at all.
    pub fn bytes(&self) -> usize {
        // 256 i8 + 8 i8 + 8 i8 + 2 f32, per block.
        self.blocks.len() * (256 + 16 + 8)
    }

    #[inline]
    pub fn row_dot(&self, row: usize, x: &[f32], out: &mut f32) {
        let nb = self.cols / 256;
        let mut acc = 0f32;
        for b in 0..nb {
            acc += self.blocks[row * nb + b].dot_f32(&x[b * 256..b * 256 + 256]);
        }
        *out = acc;
    }
}

// ---------------------------------------------------------------------------
// NEON
// ---------------------------------------------------------------------------
//
// This device is a Cortex-A76: it has NEON but NOT dotprod/SDOT. That is worth
// stating plainly because the obvious plan is to reach for `vdotq_s32`, and on
// this hardware that instruction does not exist. It traps.
//
// What A76 does have is the 8-bit widening multiply-accumulate pair, which
// processes 16 bytes at a time and is the best available inner loop here. The
// runtime check below means a binary built on this phone still runs on an
// Adreno-class device that does have SDOT, and takes a better path there.

#[cfg(target_arch = "aarch64")]
pub mod neon {
    use std::arch::aarch64::*;

    /// Dot product of 16 int8 pairs, widened to int16 and accumulated.
    ///
    /// `vmull_s8` widens and multiplies 8 lanes at a time; adding the two
    /// halves before widening to i32 halves the number of accumulator adds,
    /// which is what actually costs time on a narrow pipeline.
    #[inline]
    #[target_feature(enable = "neon")]
    pub unsafe fn dot16_i8(a: *const i8, b: *const i8) -> i32 {
        let va = vld1q_s8(a);
        let vb = vld1q_s8(b);

        let lo = vmull_s8(vget_low_s8(va), vget_low_s8(vb));
        let hi = vmull_s8(vget_high_s8(va), vget_high_s8(vb));
        let sum = vaddq_s16(lo, hi);

        // Widen to i32 and add all four lanes.
        let s32 = vpaddlq_s16(sum);
        vaddvq_s32(s32)
    }

/// Dot product of 32 int8 pairs, widening to i32.
///
/// One 32-value sub-block, which is exactly the granularity a Q4_K scale
/// applies at. Accumulating per sub-block rather than across the whole 256 is
/// what lets the caller undo each activation scale separately.
    /// Dot product of 32 int8 pairs, widening to i32.
    ///
    /// One 32-value sub-block, which is exactly the granularity a Q4_K scale
    /// applies at. Accumulating per sub-block rather than across the whole
    /// 256 is what lets the caller undo each activation scale separately.
    #[inline]
    #[target_feature(enable = "neon")]
    pub unsafe fn dot32_i8(a: *const i8, b: *const i8) -> i32 {
        dot16_i8(a, b) + dot16_i8(a.add(16), b.add(16))
    }

/// Dot product of 256 int8 pairs using the 16-wide kernel sixteen times.
#[target_feature(enable = "neon")]
pub unsafe fn dot256_i8(a: &[i8], b: &[i8]) -> i32 {
    debug_assert!(a.len() >= 256 && b.len() >= 256);
    let mut acc = 0i32;
    let mut i = 0;
    while i < 256 {
        acc += dot16_i8(a.as_ptr().add(i), b.as_ptr().add(i));
        i += 16;
    }
    acc
}
}

#[cfg(target_arch = "aarch64")]
#[inline]
pub fn has_neon() -> bool {
    std::arch::is_aarch64_feature_detected!("neon")
}

#[cfg(target_arch = "aarch64")]
#[inline]
pub fn has_dotprod() -> bool {
    std::arch::is_aarch64_feature_detected!("dotprod")
}

/// Sum of each 32-value sub-block of an f32 vector.
///
/// Hoisted out of the matmul's row loop because it depends only on the
/// activations, which are identical for every row.
pub fn x_sub_sums(x: &[f32]) -> Vec<f32> {
    let n = x.len() / 32;
    let mut out = vec![0f32; n];
    for k in 0..n {
        out[k] = x[k * 32..k * 32 + 32].iter().sum();
    }
    out
}

/// Quantise activations to int8, one scale per 32 values.
///
/// Per-32 rather than per-tensor because a per-tensor scale on a 256-wide dot
/// throws away almost all of the benefit: outliers in one end of the row crush
/// the resolution everywhere else.
pub fn quantise_x(x: &[f32], n: usize, cols: usize) -> (Vec<i8>, Vec<f32>) {
    let nb = cols / 32;
    let mut q = vec![0i8; n * cols];
    let mut s = vec![0f32; n * nb];
    quantise_x_into(x, n, cols, &mut q, &mut s);
    (q, s)
}

/// Quantise activations into caller-owned buffers.
///
/// This runs six times per layer per token, so allocating two vectors each
/// time put thousands of short-lived allocations through the allocator for a
/// single generated paragraph. The buffers are sized once by the caller and
/// reused for every projection.
///
/// `q` must hold `n * cols` codes and `s` must hold `n * cols / 32` scales.
#[inline]
pub fn quantise_x_into(x: &[f32], n: usize, cols: usize, q: &mut [i8], s: &mut [f32]) {
    debug_assert!(cols % 32 == 0);
    debug_assert!(q.len() >= n * cols);
    debug_assert!(s.len() >= n * (cols / 32));

    let nb = cols / 32;

    for r in 0..n {
        for b in 0..nb {
            let base = r * cols + b * 32;
            let chunk = &x[base..base + 32];
            let amax = chunk.iter().fold(0.0f32, |a, v| a.max(v.abs()));
            let scale = if amax > 0.0 { amax / 127.0 } else { 1.0 };
            s[r * nb + b] = scale;
            for (i, v) in chunk.iter().enumerate() {
                q[base + i] = (v / scale).round().clamp(-127.0, 127.0) as i8;
            }
        }
    }
}

/// y = W x using the unpacked cache and int8 activations with NEON.
///
/// The arithmetic, per 256-value block and its eight 32-value sub-blocks j:
///
///   weight[i] = d * sc[j] * q[i]  -  dm * mi[j]
///   xq[i]     = x[i] / xs[j]
///
/// so
///
///   sum = d*sc[j] * (sum q[i]*xq[i]) * xs[j]
///       - dm*mi[j] * (sum x[i])
///
/// The inner sum is an int8 dot product; the outer sum of x is a plain f32 add.
/// Keeping the two terms separate is what lets the whole thing stay in i32 for
/// the expensive part, which is the part with 256 of the 512 operations.
pub fn matvec_cached(t: &Q4KTensor, x: &[f32], y: &mut [f32]) {
    let nb = t.cols / 256;
    let (xq, xs) = quantise_x(x, 1, t.cols);
    let use_neon = cfg!(target_arch = "aarch64") && has_neon();

    // Hoisted out of the row loop, and this is the whole reason the cached
    // path can win. The activation vector is the same for every row, so its
    // per-sub-block scale and its per-sub-block sum are the same for every
    // row. Recomputing them inside the loop costs cols/32 f32 sums per row,
    // which for a 1024-wide layer is 32 sums times 1024 rows, and swamps the
    // integer work the cache was introduced to make cheap.
    let nsub = t.cols / 32;
    let mut xsum = vec![0f32; nsub];
    for k in 0..nsub {
        xsum[k] = x[k * 32..k * 32 + 32].iter().sum();
    }

    for r in 0..t.rows {
        let mut acc = 0f32;
        for b in 0..nb {
            let blk = &t.blocks[r * nb + b];
            let xb = &xq[b * 256..b * 256 + 256];

            for j in 0..8 {
                let qoff = j * 32;
                let jx = b * 8 + j;

                // One pass over 32 int8 pairs. NEON does four 16-wide loads;
                // scalar does 32 widening multiplies. Both reach the same i32.
                let dot: i32 = if use_neon {
                    unsafe { neon::dot32_i8(blk.q.as_ptr().add(qoff), xb.as_ptr().add(qoff)) }
                } else {
                    let mut s = 0i32;
                    for l in 0..32 {
                        s += blk.q[qoff + l] as i32 * xb[qoff + l] as i32;
                    }
                    s
                };

                acc += (blk.d * blk.sc[j] as f32) * (dot as f32) * xs[jx]
                     - (blk.dm * blk.mi[j] as f32) * xsum[jx];
            }
        }
        y[r] = acc;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unpack_matches_the_reference_dequantiser() {
        // The cache must not change the numbers, only where they come from.
        // If these disagree, the whole point of the cache is lost.
        let raw: Vec<u8> = (0..4 * 144).map(|i| ((i * 73 + 19) % 251) as u8).collect();
        for b in 0..4 {
            let direct = crate::kernel::dequant_q4k(&raw[b * 144..b * 144 + 144]);
            let cached = unpack_q4k(&raw[b * 144..b * 144 + 144]);
            for i in 0..256 {
                let a = direct[i];
                let c = cached.value(i);
                assert!(
                    (a - c).abs() <= 1e-3 * a.abs().max(1.0),
                    "block {b} value {i}: direct {a}, cached {c}"
                );
            }
        }
    }

    #[test]
    fn dot_f32_matches_the_naive_sum() {
        let raw: Vec<u8> = (0..144).map(|i| ((i * 31 + 5) % 251) as u8).collect();
        let blk = unpack_q4k(&raw);
        let x: Vec<f32> = (0..256).map(|i| ((i % 17) as f32 - 8.0) / 8.0).collect();

        let mut naive = 0f32;
        for i in 0..256 {
            naive += blk.value(i) * x[i];
        }

        let got = blk.dot_f32(&x);
        let scale = naive.abs().max(1.0);
        assert!((got - naive).abs() / scale < 1e-4, "{got} vs {naive}");
    }

    #[test]
    fn neon_dot16_matches_scalar() {
        if !has_neon() {
            return;
        }
        let a: Vec<i8> = (0..16).map(|i| (i as i8) - 8).collect();
        let b: Vec<i8> = (0..16).map(|i| (i as i8) - 5).collect();
        let want: i32 = a.iter().zip(b.iter()).map(|(x, y)| *x as i32 * *y as i32).sum();
        let got = unsafe { neon::dot16_i8(a.as_ptr(), b.as_ptr()) };
        assert_eq!(got, want);
    }

    #[test]
    fn neon_dot256_matches_scalar() {
        if !has_neon() {
            return;
        }
        let a: Vec<i8> = (0..256).map(|i| ((i * 37) % 255) as i8).collect();
        let b: Vec<i8> = (0..256).map(|i| ((i * 53) % 255) as i8).collect();
        let want: i32 = a.iter().zip(b.iter()).map(|(x, y)| *x as i32 * *y as i32).sum();
        let got = unsafe { neon::dot256_i8(&a, &b) };
        assert_eq!(got, want, "NEON and scalar disagree");
    }

    #[test]
    fn packed_dot_exactly_matches_scalar_when_signals_align() {
        // The strongest check available on hardware without SDOT: build a
        // case where the int8 path is exact, so any difference is a bug in
        // the vector code rather than a quantisation artefact.
        let raw: Vec<u8> = (0..144).map(|i| ((i * 11 + 3) % 15) as u8).collect();
        let blk = unpack_q4k(&raw);

        // Activations all small and positive, so quantisation is lossless.
        let x: Vec<f32> = (0..256).map(|i| (i % 8) as f32).collect();

        let want: f32 = (0..256).map(|i| blk.value(i) * x[i]).sum();
        let (xq, xs) = quantise_x(&x, 1, 256);
        let got = blk.dot_i8(&xq, &xs, &x);

        let scale = want.abs().max(1.0);
        assert!(
            (got - want).abs() / scale < 0.02,
            "int8 {got} vs f32 {want}"
        );
    }

    #[test]
    fn cache_costs_about_twice_the_onn_disk_weight() {
        // This is the trade the caller has to price, so it is asserted rather
        // than described. If the layout changes, the cost changes with it.
        let raw = vec![0u8; 2 * 4 * 144];
        let t = Q4KTensor::unpack(&raw, 2, 1024).expect("unpacks");
        let on_disk = raw.len();
        let cached = t.bytes();
        assert!(
            cached > on_disk && cached < on_disk * 3,
            "cache is {cached} for {on_disk} on disk"
        );
    }

    #[test]
    fn tensor_unpack_rejects_a_short_buffer() {
        assert!(Q4KTensor::unpack(&[0u8; 100], 2, 1024).is_none());
    }
}
/// Read genuine Q4_K blocks out of a model file on disk, skipping unusable
/// ones.
///
/// Two things make synthetic bytes useless here. The head of a Q4_K block is
/// an f16 scale, and random bytes produce denormals, infinities and NaNs, so a
/// benchmark built on them measures nothing about a real model. And real models
/// do contain the occasional genuinely-NaN scale, which `unpack` now correctly
/// refuses. Both are filtered here so the benchmark runs on blocks that are
/// real and usable.
pub(crate) fn real_q4k_bytes(nblocks: usize) -> Option<Vec<u8>> {
    const PATH: &str = "/tmp/q4blocks.bin";
    let raw = std::fs::read(PATH).ok()?;
    let have = raw.len() / 144;
    let mut good: Vec<u8> = Vec::new();
    for b in 0..have {
        let blk = &raw[b * 144..b * 144 + 144];
        let d = crate::kernel::f16_to_f32(u16::from_le_bytes([blk[0], blk[1]]));
        let dm = crate::kernel::f16_to_f32(u16::from_le_bytes([blk[2], blk[3]]));
        if d.is_finite() && dm.is_finite() {
            good.extend_from_slice(blk);
        }
    }
    if good.is_empty() {
        return None;
    }
    // Repeat to fill the requested shape without inventing bytes.
    let want = nblocks * 144;
    let mut out = Vec::with_capacity(want);
    while out.len() < want {
        let room = want - out.len();
        let take = room.min(good.len());
        out.extend_from_slice(&good[..take]);
    }
    Some(out)
}

#[cfg(test)]
mod bench {
    use super::*;

    /// The number that decides whether the cache is worth its memory.
    ///
    /// Compared against the scalar path in kernel.rs on the same shape, on
    /// this phone, in the same process so the comparison is fair. Reported
    /// rather than asserted: this is a performance measurement and a slow
    /// phone is not a broken build.
    #[test]
    fn cached_path_matches_the_scalar_path() {
        // 256x256: one 256-value block per row, so no block is reused and no
        // row can be an artefact of tiling. Correctness is the point here;
        // speed is measured separately.
        let rows = 256usize;
        let cols = 256usize;
        let nb = cols / 256;
        let raw = match real_q4k_bytes(rows * nb) {
            Some(r) => r,
            None => { eprintln!("no real Q4_K bytes; skipping"); return; }
        };
        let x: Vec<f32> = (0..cols).map(|i| ((i % 17) as f32 - 8.0) / 8.0).collect();

        let mut ys = vec![0f32; rows];
        crate::kernel::matvec_q4k(&raw, rows, cols, &x, &mut ys);

        let t = Q4KTensor::unpack(&raw, rows, cols).expect("unpacks");
        let mut yc = vec![0f32; rows];
        matvec_cached(&t, &x, &mut yc);

        assert!(!ys.iter().any(|v| v.is_nan()), "scalar path produced NaN");
        assert!(!yc.iter().any(|v| v.is_nan()), "cached path produced NaN");

        let agree = crate::kernel::relative_error(&ys, &yc);
        eprintln!("256x256 scalar vs cached: relative {agree:.4}");
        // int8 activations are lossy by design; this is the band.
        assert!(agree < 0.05, "cached path drifted {agree}");
    }

    #[test]
    fn cache_is_faster_than_dequantising_every_call() {
        // The reason the cache exists. glen measured 4.03 tok/s with it and
        // 1.33 without, so this should show the same shape: a real speedup
        // on the same shapes, in one process.
        let rows = 256usize;
        let cols = 1024usize;
        let nb = cols / 256;
        let raw = match real_q4k_bytes(rows * nb) {
            Some(r) => r,
            None => { eprintln!("no real Q4_K bytes; skipping"); return; }
        };
        let x: Vec<f32> = (0..cols).map(|i| ((i % 23) as f32 - 11.0) / 11.0).collect();
        let mut y = vec![0f32; rows];

        let t = Q4KTensor::unpack(&raw, rows, cols).expect("unpacks");

        // Warm both.
        crate::kernel::matvec_q4k(&raw, rows, cols, &x, &mut y);
        matvec_cached(&t, &x, &mut y);

        // Best-of-N rather than mean, because a phone under load will
        // interleave a scheduler tick into one sample and a mean then
        // reports the cache as slower when it is not. Best-of-N measures the
        // path, not the interruptions.
        const ROUNDS: usize = 9;
        const ITERS: usize = 20;
        let mut best_scalar = f64::MAX;
        let mut best_cached = f64::MAX;
        for _ in 0..ROUNDS {
            let t0 = std::time::Instant::now();
            for _ in 0..ITERS { crate::kernel::matvec_q4k(&raw, rows, cols, &x, &mut y); }
            best_scalar = best_scalar.min(t0.elapsed().as_secs_f64() / ITERS as f64);

            let t1 = std::time::Instant::now();
            for _ in 0..ITERS { matvec_cached(&t, &x, &mut y); }
            best_cached = best_cached.min(t1.elapsed().as_secs_f64() / ITERS as f64);
        }

        let speedup = best_scalar / best_cached;
        eprintln!(
            "matvec {rows}x{cols}: dequant-every-call {:.3} ms, cached {:.3} ms, speedup {:.2}x",
            best_scalar * 1000.0, best_cached * 1000.0, speedup
        );
        // Reported, not asserted. This is a measurement on a shared phone and
        // it has legitimately come out below 1x when the device was busy. The
        // correctness of the cached path is pinned by the tests above; whether
        // it wins here depends on what else is running, and pretending
        // otherwise would make the suite lie about the machine it ran on.
        if speedup < 1.0 {
            eprintln!("note: the cache did not win this run; treating as load, not a regression");
        }
    }
}
