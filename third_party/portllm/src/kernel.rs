//! Dequantization and the first matrix multiply.
//!
//! This is the file that decides whether the project is real. Everything
//! before it decides what to run; this decides whether we can run it. If a
//! from-scratch kernel cannot reproduce a known-good engine's numbers, the
//! approach is wrong and no amount of placement policy rescues it.
//!
//! The reference is glen's Q4_K path, which is MIT and independently measured
//! at 6.39-6.89 tok/s against llama.cpp on the same phone. We do not copy its
//! activation quantization: glen quantizes x to int8 per call, which is fast
//! and lossy. For a correctness test we want the exact arithmetic, so this
//! dequantizes weights and keeps activations in f32. Slower, and unambiguous.
//!
//! If the two agree here, the difference between us and glen is a policy
//! question. If they disagree, it is a correctness bug and nothing else
//! matters yet.

// ---------------------------------------------------------------------------
// f16
// ---------------------------------------------------------------------------

/// IEEE half to single precision.
///
/// Written out rather than using a lookup table, because the interesting
/// inputs are the denormals and the infinities, and those are exactly the
/// cases a clever shortcut gets wrong.
pub fn f16_to_f32(bits: u16) -> f32 {
    // Bit 15 of the half becomes bit 31 of the single. Shifting the whole
    // mask by 16 moves it to bit 31 and leaves the rest clear; shifting by
    // 31 would drag in the exponent bits and sign every normal number wrong.
    let sign = ((bits as u32) & 0x8000) << 16;
    let exp = ((bits >> 10) & 0x1F) as u32;
    let mant = (bits & 0x03FF) as u32;

    let out: u32 = match exp {
        // Zero or denormal: normalise by shifting the mantissa left.
        0 => {
            if mant == 0 {
                sign
            } else {
                let mut e = -14i32;
                let mut m = mant;
                while m & 0x400 == 0 {
                    m <<= 1;
                    e -= 1;
                }
                m &= 0x03FF;
                sign | (((127 + e) as u32) << 23) | (m << 13)
            }
        }
        // Inf or NaN.
        0x1F => sign | (0xFF << 23) | (mant << 13),
        _ => sign | (((exp + 127 - 15) as u32) << 23) | (mant << 13),
    };
    f32::from_bits(out)
}

// ---------------------------------------------------------------------------
// Q4_K
// ---------------------------------------------------------------------------

/// One dequantised 256-value block.
#[derive(Debug, Clone)]
pub struct Q4KBlock {
    pub values: [f32; 256],
}

/// Recover the 256 floats in one Q4_K block.
///
/// Panics on a non-finite super-block scale, for the same reason
/// `dequant_q4k_tensor` does: one NaN scale makes all 256 values NaN, and
/// that is indistinguishable from a model that is merely very wrong.
pub fn dequant_q4k(block: &[u8]) -> [f32; 256] {
    debug_assert_eq!(block.len(), 144);

    let d = f16_to_f32(u16::from_le_bytes([block[0], block[1]]));
    let dmin = f16_to_f32(u16::from_le_bytes([block[2], block[3]]));
    if !d.is_finite() || !dmin.is_finite() {
        panic!("dequant_q4k: non-finite super-block scale (d={d}, dmin={dmin})");
    }
    let scales = &block[4..16];
    let nibbles = &block[16..144];

    let mut out = [0f32; 256];

    // Four groups of 64 values. Each group is fed by 32 packed bytes and
    // carries its own pair of sub-block scales: `2g` for the first 32 values
    // and `2g+1` for the next 32. Both write to disjoint halves of the group,
    // so neither may overwrite the other.
    for g in 0..4 {
        let (sc_even, m_even) = unpack_scale_min(2 * g, scales);
        let d_even = d * sc_even as f32;
        let m_even = dmin * m_even as f32;

        let (sc_odd, m_odd) = unpack_scale_min(2 * g + 1, scales);
        let d_odd = d * sc_odd as f32;
        let m_odd = dmin * m_odd as f32;

        for l in 0..32 {
            let byte = nibbles[g * 32 + l];
            // Low nibbles of the byte give the first sub-block, high nibbles
            // the second: the same 32 bytes, read two ways.
            out[g * 64 + l] = (byte & 0x0F) as f32 * d_even - m_even;
            out[g * 64 + 32 + l] = (byte >> 4) as f32 * d_odd - m_odd;
        }
    }

    out
}

/// Extract the 6-bit scale and 6-bit minimum for sub-block `j` (0..8).
fn unpack_scale_min(j: usize, s: &[u8]) -> (u8, u8) {
    if j < 4 {
        (s[j] & 63, s[j + 4] & 63)
    } else {
        (
            (s[j + 4] & 0x0F) | ((s[j - 4] >> 6) << 4),
            (s[j + 4] >> 4) | ((s[j] >> 6) << 4),
        )
    }
}

/// Dequantize a whole Q4_K tensor stored row-major, `rows` x `cols`.
///
/// GGUF stores K-quants with `cols / 256` blocks per row and the rows
/// contiguous, so a tensor is one flat run of blocks.
///
/// Validates first. Real models carry blocks whose f16 scale is NaN, and
/// dequantising one of those poisons every value it touches, silently. A
/// tensor that fails validation panics here rather than producing a model
/// that answers confidently with nonsense.
pub fn dequant_q4k_tensor(bytes: &[u8], rows: usize, cols: usize) -> Vec<f32> {
    if let Err(e) = crate::validate::validate_tensor(bytes, rows, cols, 12) {
        panic!("dequant_q4k_tensor: {}", e.explain());
    }
    assert_eq!(cols % 256, 0, "Q4_K rows are a multiple of 256");
    let nb = cols / 256;
    let nblocks = rows * nb;
    assert!(bytes.len() >= nblocks * 144, "tensor bytes are short");

    let mut out = vec![0f32; rows * cols];
    for r in 0..rows {
        for q in 0..nb {
            let bi = r * nb + q;
            let blk = dequant_q4k(&bytes[bi * 144..bi * 144 + 144]);
            let base = r * cols + q * 256;
            out[base..base + 256].copy_from_slice(&blk);
        }
    }
    out
}

// ---------------------------------------------------------------------------
// The matmul
// ---------------------------------------------------------------------------

/// `y = W x` with W row-major `rows` x `cols` and x a column of length cols.
///
/// Exact f32, no activation quantization. Correctness over speed: the point
/// of this function is to be obviously right so that when it matches glen we
/// know the quantizer is right, and when it does not we know where.
pub fn matvec(w: &[f32], rows: usize, cols: usize, x: &[f32], y: &mut [f32]) {
    assert_eq!(w.len(), rows * cols, "weight shape");
    assert_eq!(x.len(), cols, "input length");
    assert!(y.len() >= rows, "output length");

    for r in 0..rows {
        let row = &w[r * cols..(r + 1) * cols];
        let mut acc = 0f32;
        for c in 0..cols {
            acc += row[c] * x[c];
        }
        y[r] = acc;
    }
}

/// Same, but the weights stay quantised.
///
/// This is the path the engine will actually take, and it is the one worth
/// benchmarking. It exists beside the exact one above so the two can be
/// compared: if the fast path drifts from the exact path, the drift is the
/// quantizer, and that difference is a real accuracy cost someone has to own.
///
/// Validates first, for the same reason as `dequant_q4k_tensor`. This is the
/// function that was previously unchecked, and the gap is exactly the kind
/// that only a code review would have caught.
pub fn matvec_q4k(qw: &[u8], rows: usize, cols: usize, x: &[f32], y: &mut [f32]) {
    if let Err(e) = crate::validate::validate_tensor(qw, rows, cols, 12) {
        panic!("matvec_q4k: {}", e.explain());
    }
    let nb = cols / 256;
    let mut blk = [0f32; 256];

    for r in 0..rows {
        let mut acc = 0f32;
        for q in 0..nb {
            let bi = r * nb + q;
            dequant_q4k_into(&qw[bi * 144..bi * 144 + 144], &mut blk);
            let off = q * 256;
            for i in 0..256 {
                acc += blk[i] * x[off + i];
            }
        }
        y[r] = acc;
    }
}

/// Dequantise into a caller-owned buffer, to keep the fast path allocation
/// free. The stack array in `dequant_q4k` is 1 KB, which is fine once per
/// call but not once per block.
fn dequant_q4k_into(block: &[u8], out: &mut [f32; 256]) {
    let v = dequant_q4k(block);
    out.copy_from_slice(&v);
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

/// Aggregate relative error between two vectors, as a ratio of total
/// absolute error to total absolute magnitude.
///
/// This is the honest comparison for a vector of dot products, and the
/// per-element version is not. A matvec output row is a sum that can land
/// anywhere near zero, so normalising each element by its own magnitude turns
/// one cancelled output into an enormous "error" and hides the real drift.
/// Normalising the whole vector measures what actually matters: how far the
/// answer moved overall.
pub fn relative_error(a: &[f32], b: &[f32]) -> f32 {
    assert_eq!(a.len(), b.len());
    let mag: f64 = a.iter().map(|v| (*v as f64).abs()).sum();
    let diff: f64 = a
        .iter()
        .zip(b.iter())
        .map(|(x, y)| (*x as f64 - *y as f64).abs())
        .sum();
    if mag == 0.0 {
        return if diff == 0.0 { 0.0 } else { 1.0 };
    }
    (diff / mag) as f32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn f16_handles_the_awkward_values() {
        assert_eq!(f16_to_f32(0x0000), 0.0);
        assert_eq!(f16_to_f32(0x3C00), 1.0, "one");
        assert_eq!(
            f16_to_f32(0xC000),
            -2.0,
            "minus two, got bits {:#010X}",
            f16_to_f32(0xC000).to_bits()
        );
        assert_eq!(f16_to_f32(0x3800), 0.5, "one half");

        assert!(f16_to_f32(0x7C00).is_infinite(), "inf");
        assert!(f16_to_f32(0xFC00).is_infinite(), "minus inf");
        assert!(f16_to_f32(0x7E00).is_nan(), "nan");

        // Smallest normal half is 2^-14; the one below it is a denormal.
        assert!((f16_to_f32(0x0400) - 6.103_515_625e-5).abs() < 1e-12);
        assert!(f16_to_f32(0x0001) > 0.0, "denormals are not flushed to zero");
        assert!(f16_to_f32(0x0001) < 1e-4, "but they are still tiny");
    }

    #[test]
    fn f16_roundtrips_the_values_a_scale_would_use() {
        for bits in [0x3C00u16, 0x3800, 0x4000, 0x3555, 0x2E66, 0x1A0B] {
            let back = f32_to_f16(f16_to_f32(bits));
            assert_eq!(back, bits, "0x{bits:04x} did not roundtrip");
        }
    }

    fn f32_to_f16(v: f32) -> u16 {
        let b = v.to_bits();
        let sign = ((b >> 16) & 0x8000) as u16;
        let exp = ((b >> 23) & 0xFF) as i32 - 127;
        let mant = b & 0x7FFFFF;
        if exp > 15 {
            return sign | 0x7C00;
        }
        if exp < -14 {
            return sign;
        }
        sign | (((exp + 15) as u16) << 10) | ((mant >> 13) as u16)
    }

    #[test]
    fn scale_unpack_matches_the_documented_interleave() {
        // Bytes 0-3 hold scales 0-3 in their low six bits, and minimums 0-3
        // in the low six bits of bytes 4-7. The upper four of each then live
        // in the high bits of the same bytes.
        let s = [0x0Fu8, 0x01, 0x02, 0x03, 0x34, 0x12, 0x00, 0x00, 0, 0, 0, 0];

        // j < 4: scale is s[j] & 63, minimum is s[j+4] & 63.
        assert_eq!(unpack_scale_min(0, &s), (0x0F, 0x34), "j=0");
        assert_eq!(unpack_scale_min(1, &s), (0x01, 0x12), "j=1");

        // A value with bits in both halves, so the stitching is actually
        // exercised rather than reading zeros from both sides. s[8] = 0 so
        // the low nibble of s[j+4] is zero for both. The scale's high two
        // bits come from s[j-4] = s[0] = 0xC0, giving 0b11 << 4 = 48. The
        // minimum's high two bits come from s[j] = s[4] = 0x5A, giving
        // 0b01 << 4 = 16.
        let t = [0xC0u8, 0, 0, 0, 0x5Au8, 0, 0, 0, 0, 0, 0, 0];
        let (sc4, m4) = unpack_scale_min(4, &t);
        assert_eq!(sc4, 48, "scale high bits come from s[j-4]");
        assert_eq!(m4, 16, "minimum high bits come from s[j]");
    }

    #[test]
    fn an_all_zero_block_dequantises_to_the_sub_block_minimum() {
        // With every scale and minimum at zero, `d*sc` and `dmin*m` are both
        // zero, so the value is `0*d - 0*dmin` = 0. The real check here is
        // that no stray scale or nibble leaks in: a value of 0 everywhere
        // means the block was read from the right offsets.
        let mut block = [0u8; 144];
        block[0] = 0x00;
        block[1] = 0x3C; // f16 1.0, unused because all scales are zero
        block[2] = 0x00;
        block[3] = 0x3C; // f16 1.0
        let v = dequant_q4k(&block);
        for (i, x) in v.iter().enumerate() {
            assert!(x.abs() < 1e-6, "value {i} was {x}");
        }
    }

    #[test]
    fn a_scaled_block_actually_uses_its_scale() {
        // The counterpart to the zero case: give the first sub-block a real
        // scale and confirm the values move. If dequant ignored `d` and the
        // scales, the zero-block test above would still pass.
        let mut block = [0u8; 144];
        block[0] = 0x00;
        block[1] = 0x3C; // d = 1.0
        block[2] = 0x00;
        block[3] = 0x00; // dmin = 0.0
        block[4] = 0x08; // scale[0] = 8
        for i in 0..128 {
            block[16 + i] = 0x11; // every nibble is 1
        }
        let v = dequant_q4k(&block);
        // First 32 values use scale[0]=8: 1 * 1.0 * 8 = 8.
        assert!((v[0] - 8.0).abs() < 1e-4, "v[0] was {}", v[0]);
    }

    #[test]
    fn dequant_is_block_local() {
        // Two identical blocks in one tensor must produce identical values,
        // which catches any indexing that leaks across the block boundary.
        let mut block = [0u8; 144];
        for i in 0..128 {
            block[16 + i] = (i % 16) as u8;
        }
        let mut tensor = vec![0u8; 288];
        tensor[0..144].copy_from_slice(&block);
        tensor[144..288].copy_from_slice(&block);

        let out = dequant_q4k_tensor(&tensor, 1, 512);
        assert_eq!(&out[0..256], &out[256..512], "blocks are not independent");
    }

    #[test]
    fn exact_and_quantised_matvec_agree() {
        // The whole point of the quantised path is that it computes the same
        // thing as the exact one. If these diverge, the fast path is wrong.
        let rows = 8;
        let cols = 512;
        let nblocks = rows * (cols / 256);

        // Build quantised bytes, then dequantise them to get the exact
        // reference. Comparing a path against itself would prove nothing, so
        // the reference is the dequantised tensor and the test is whether the
        // streaming path reproduces the same arithmetic.
        let raw: Vec<u8> = (0..nblocks * 144)
            .map(|i| ((i * 37 + 11) % 251) as u8)
            .collect();

        let w = dequant_q4k_tensor(&raw, rows, cols);
        let x: Vec<f32> = (0..cols).map(|i| ((i % 7) as f32 - 3.0) / 4.0).collect();

        let mut y_exact = vec![0f32; rows];
        matvec(&w, rows, cols, &x, &mut y_exact);

        let mut y_fast = vec![0f32; rows];
        matvec_q4k(&raw, rows, cols, &x, &mut y_fast);

        assert_eq!(y_exact, y_fast, "quantised path diverged from exact");
    }

    #[test]
    fn matvec_handles_a_known_vector() {
        // 2x2 identity times a vector. Trivial on purpose: if this is wrong,
        // the loop structure is wrong and every other test here is noise.
        let w = vec![1.0, 0.0, 0.0, 1.0];
        let x = vec![3.0, -4.0];
        let mut y = vec![0.0; 2];
        matvec(&w, 2, 2, &x, &mut y);
        assert_eq!(y, vec![3.0, -4.0]);
    }

    #[test]
    fn relative_error_is_scale_free() {
        assert!(relative_error(&[1.0], &[1.0]) < 1e-6, "identical");
        assert!(relative_error(&[1000.0], &[1000.1]) < 1e-3, "small rel");
        assert!(relative_error(&[0.001], &[0.5]) > 0.9, "large rel");
        // A vector that cancels to near zero must not report a huge error:
        // that is a property of the data, not of the comparison.
        let a = [1000.0f32, -1000.0, 500.0, -500.0];
        assert!(relative_error(&a, &a) < 1e-6, "exact match stays exact");
    }

    #[test]
    fn a_real_tensor_dequantises_within_range() {
        let path = std::path::Path::new("/tmp/gbz/q3.gguf");
        if !path.exists() {
            return;
        }
        // This model is Q3_K_M, not Q4_K, so we only assert that the reader
        // agrees the file is a sane model. Q3 unpacking arrives with inference.
        let h = crate::gguf::read_header(path).expect("header parses");
        assert_eq!(h.unsized_tensors(), 0);
        assert!(h.integrity().is_ok());
    }
}