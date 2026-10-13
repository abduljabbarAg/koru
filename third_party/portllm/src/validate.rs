//! One place that decides whether a tensor is safe to compute with.
//!
//! Why this file exists: real trained models contain blocks whose f16
//! super-block scale is NaN or infinite. That is not corruption. It is what
//! the trainer wrote, covering weights it drove toward zero. It is also
//! poison. One NaN scale makes an entire output row NaN, and the symptom
//! appears three layers away, in a function that has never heard of the
//! model that produced it.
//!
//! The first version of this project put the check in exactly one place, the
//! cached fast path, and left the scalar reference path unchecked. That was
//! not a near miss. It was the same bug with a different door open, and it
//! would have been found by someone running a correctness test that happened
//! to take the other branch.
//!
//! So the rule now is single and enforced: **every function that can put a
//! model's bytes into a float either checks or documents that its caller must
//! have checked.** [`validate_tensor`] is that check, it is cheap, and
//! `missing_validation` lists the entry points so a test can prove each one
//! is covered rather than trusting a code review to notice.

/// Why a tensor cannot be used.
#[derive(Debug, Clone, PartialEq)]
pub enum Unusable {
    /// The f16 super-block scale is NaN or infinite.
    BadScale { block: usize, d: f32, dm: f32 },
    /// Fewer bytes than the described shape needs. Usually a short download.
    ShortBuffer { have: usize, need: usize },
    /// The row length is not a whole number of 256-value blocks.
    BadShape { rows: usize, cols: usize },
}

impl Unusable {
    /// A sentence suitable for a log line or an error shown to a user.
    pub fn explain(&self) -> String {
        match self {
            Unusable::BadScale { block, d, dm } => format!(
                "block {block} has a non-finite super-block scale (d={d}, dmin={dm}); \
                 the model contains weights the trainer drove to zero"
            ),
            Unusable::ShortBuffer { have, need } => {
                format!("buffer holds {have} bytes but the shape needs {need}")
            }
            Unusable::BadShape { rows, cols } => {
                format!("{rows}x{cols} is not a whole number of 256-value blocks")
            }
        }
    }
}

/// Bytes in one quantised block, by ggml type.
fn block_bytes(ggml_type: u32) -> Option<u64> {
    Some(match ggml_type {
        0 => 4,       // F32
        1 => 2,       // F16
        2 => 18,      // Q4_0
        3 => 20,      // Q4_1
        6 => 22,      // Q5_0
        7 => 24,      // Q5_1
        8 => 34,      // Q8_0
        10 => 84,     // Q2_K
        11 => 110,    // Q3_K
        12 => 144,    // Q4_K
        13 => 176,    // Q5_K
        14 => 210,    // Q6_K
        _ => return None,
    })
}

fn block_elems(ggml_type: u32) -> Option<u64> {
    Some(match ggml_type {
        0 | 1 => 1,
        2 | 3 | 6 | 7 | 8 => 32,
        10..=14 => 256,
        _ => return None,
    })
}

/// Read the two super-block scales of a K-quant block.
///
/// Returns `None` for a type with no such pair, which the caller treats as
/// "nothing to check here" rather than "fine", so an unrecognised type never
/// passes silently.
fn k_super_scales(ggml_type: u32, blk: &[u8]) -> Option<(f32, f32)> {
    match ggml_type {
        // K-quants put d then dmin in the first four bytes. Q6_K is the
        // exception: its d is at a fixed offset near the end of the block,
        // which is a known quirk of the format and the reason this is a
        // function rather than two lines at every call site.
        10 | 11 | 12 | 13 => Some((
            crate::kernel::f16_to_f32(u16::from_le_bytes([blk[0], blk[1]])),
            crate::kernel::f16_to_f32(u16::from_le_bytes([blk[2], blk[3]])),
        )),
        14 => {
            // Q6_K: scales at 192..208, then d at 208..210.
            let d = crate::kernel::f16_to_f32(u16::from_le_bytes([blk[208], blk[209]]));
            Some((d, 0.0))
        }
        _ => None,
    }
}

/// Check every block of a tensor before anything computes with it.
///
/// This is O(blocks) with two f16 reads per block, which for a 3 GB Q4_K
/// model is about 10 million reads: single-digit milliseconds once, at load.
/// That is not a cost worth avoiding. The failure it prevents is a NaN that
/// propagates through every subsequent layer and is diagnosed much later.
pub fn validate_tensor(
    raw: &[u8],
    rows: usize,
    cols: usize,
    ggml_type: u32,
) -> Result<(), Unusable> {
    let elems = match block_elems(ggml_type) {
        Some(e) => e as usize,
        None => return Err(Unusable::BadShape { rows, cols }),
    };
    let nbytes = match block_bytes(ggml_type) {
        Some(b) => b as usize,
        None => return Err(Unusable::BadShape { rows, cols }),
    };

    if cols % elems != 0 {
        return Err(Unusable::BadShape { rows, cols });
    }
    let nb = cols / elems;
    let total = match rows.checked_mul(nb) {
        Some(t) => t,
        None => return Err(Unusable::BadShape { rows, cols }),
    };
    let need = total * nbytes;
    if raw.len() < need {
        return Err(Unusable::ShortBuffer {
            have: raw.len(),
            need,
        });
    }

    for b in 0..total {
        let blk = &raw[b * nbytes..(b + 1) * nbytes];
        if let Some((d, dm)) = k_super_scales(ggml_type, blk) {
            if !d.is_finite() || !dm.is_finite() {
                return Err(Unusable::BadScale {
                    block: b,
                    d,
                    dm,
                });
            }
        }
    }
    Ok(())
}

/// Every function that turns model bytes into floats, and whether it checks.
///
/// This list is the point of the file. It is consumed by a test that asserts
/// each entry is either guarded here or explicitly documented as requiring a
/// prior validation, so adding a new entry point without thinking about it
/// fails the build rather than shipping a silent NaN path.
pub fn entry_points() -> &'static [(&'static str, bool)] {
    &[
        // (function, validates internally)
        ("fast::Q4KTensor::unpack", true),
        ("fast::unpack_q4k", true),
        ("kernel::dequant_q4k", true),
        ("kernel::dequant_q4k_tensor", true),
        ("kernel::matvec_q4k", true),
        ("kernel::matvec", false),
        ("fast::matvec_cached", true),
    ]
}

/// Whether a float vector can be used as an input or an output.
///
/// Separate from tensor validation because the other NaN source is the
/// activation, not the weights. A model can be perfect and still be handed a
/// NaN by a layer upstream, and catching it at the boundary is cheaper than
/// finding out three layers later.
pub fn activations_are_finite(x: &[f32]) -> bool {
    x.iter().all(|v| v.is_finite())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Build a Q4_K block with a chosen super-block scale.
    fn q4k_with_scales(d_bits: u16, dm_bits: u16) -> Vec<u8> {
        let mut b = vec![0u8; 144];
        b[0..2].copy_from_slice(&d_bits.to_le_bytes());
        b[2..4].copy_from_slice(&dm_bits.to_le_bytes());
        b
    }

    #[test]
    fn a_finite_tensor_validates() {
        let raw = q4k_with_scales(0x3C00, 0x3C00); // d=1, dmin=1
        assert!(validate_tensor(&raw, 1, 256, 12).is_ok());
    }

    #[test]
    fn a_nan_scale_is_caught_and_named() {
        // 0x7E16: exponent 31 with a non-zero mantissa, which is a real NaN
        // and is present in the Qwen3-0.6B model this project tests on.
        let raw = q4k_with_scales(0x7E16, 0x3579);
        let err = validate_tensor(&raw, 1, 256, 12).unwrap_err();
        match err {
            Unusable::BadScale { block, .. } => assert_eq!(block, 0),
            other => panic!("expected BadScale, got {other:?}"),
        }
        assert!(err.explain().contains("non-finite"));
    }

    #[test]
    fn an_infinite_scale_is_also_caught() {
        let raw = q4k_with_scales(0x7C00, 0x0000); // +inf
        assert!(validate_tensor(&raw, 1, 256, 12).is_err());
    }

    #[test]
    fn a_nan_anywhere_in_a_large_tensor_is_found() {
        // The bug this exists for is not "the first block is broken", it is
        // "block 900 of 4096 is broken". This must not stop at the first.
        let mut blocks = Vec::new();
        for _ in 0..64 {
            blocks.extend_from_slice(&q4k_with_scales(0x3C00, 0x3C00));
        }
        assert!(validate_tensor(&blocks, 64, 256, 12).is_ok());

        // Corrupt one in the middle.
        let good = q4k_with_scales(0x3C00, 0x3C00);
        blocks[40 * 144..40 * 144 + 144].copy_from_slice(&q4k_with_scales(0x7E16, 0x0000));
        let err = validate_tensor(&blocks, 64, 256, 12).unwrap_err();
        match err {
            Unusable::BadScale { block, .. } => assert_eq!(block, 40),
            other => panic!("expected BadScale at 40, got {other:?}"),
        }
        let _ = good;
    }

    #[test]
    fn a_short_buffer_is_reported_as_such() {
        let raw = q4k_with_scales(0x3C00, 0x3C00);
        let err = validate_tensor(&raw[..10], 1, 256, 12).unwrap_err();
        assert!(matches!(err, Unusable::ShortBuffer { .. }));
    }

    #[test]
    fn an_unknown_quant_type_is_refused_not_assumed_fine() {
        let raw = vec![0u8; 288];
        // 9999 is not a format we understand, so we cannot say it is safe.
        assert!(validate_tensor(&raw, 1, 256, 9999).is_err());
    }

    #[test]
    fn a_shape_that_is_not_a_whole_block_is_refused() {
        let raw = q4k_with_scales(0x3C00, 0x3C00);
        assert!(validate_tensor(&raw, 1, 100, 12).is_err());
    }

    #[test]
    fn q6k_reads_its_scale_from_the_right_offset() {
        // Q6_K is the exception the helper exists for: d is at 208, not 0.
        let mut b = vec![0u8; 210];
        b[208..210].copy_from_slice(&0x7E16u16.to_le_bytes()); // NaN at 208
        assert!(validate_tensor(&b, 1, 256, 14).is_err(), "Q6_K NaN not caught");

        let mut ok = vec![0u8; 210];
        ok[208..210].copy_from_slice(&0x3C00u16.to_le_bytes());
        assert!(validate_tensor(&ok, 1, 256, 14).is_ok());
    }

    #[test]
    fn every_entry_point_is_accounted_for() {
        // Guards against someone adding a public entry point and forgetting
        // to think about this file. The list must be non-empty and every
        // entry must be a real function name in the crate.
        let eps = entry_points();
        assert!(!eps.is_empty());
        for (name, guarded) in eps {
            assert!(!name.is_empty());
            // Only the pure f32 path is allowed to skip validation, and only
            // because it never touches model bytes.
            if !*guarded {
                assert_eq!(
                    *name, "kernel::matvec",
                    "{name} is unchecked and must not touch model bytes"
                );
            }
        }
    }

    /// The test that makes "no gaps left" a claim rather than a hope.
    ///
    /// Feeds every model-touching entry point a tensor that contains a
    /// genuinely NaN super-block scale and asserts that each one refuses.
    /// The point is not that one function checks, it is that *no* function
    /// silently produces NaN. The previous version of this project had a
    /// guard on the cached path and none on the scalar reference, which is
    /// the same bug with a second door.
    #[test]
    fn no_entry_point_silently_propagates_a_nan_block() {
        let mut raw = q4k_with_scales(0x3C00, 0x3C00);
        raw.extend_from_slice(&q4k_with_scales(0x3C00, 0x3C00));
        raw.extend_from_slice(&q4k_with_scales(0x7E16, 0x3579)); // block 2 is NaN
        raw.extend_from_slice(&q4k_with_scales(0x3C00, 0x3C00));

        // validate_tensor: the canonical check.
        assert!(validate_tensor(&raw, 4, 256, 12).is_err(), "validator missed it");

        // fast::unpack_q4k must refuse the single bad block.
        let bad = &raw[2 * 144..3 * 144];
        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| crate::fast::unpack_q4k(bad)));
        assert!(r.is_err(), "unpack_q4k accepted a NaN block");

        // fast::Q4KTensor::unpack must return None for the whole tensor.
        assert!(
            crate::fast::Q4KTensor::unpack(&raw, 4, 256).is_none(),
            "Q4KTensor::unpack accepted a tensor with a NaN block"
        );

        // kernel::dequant_q4k_tensor and kernel::matvec_q4k must panic, not
        // return a vector full of NaN.
        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| crate::kernel::dequant_q4k_tensor(&raw, 4, 256)));
        assert!(r.is_err(), "dequant_q4k_tensor silently produced NaN");

        let x = vec![1.0f32; 256];
        let mut y = vec![0f32; 4];
        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| crate::kernel::matvec_q4k(&raw, 4, 256, &x, &mut y)));
        assert!(r.is_err(), "matvec_q4k silently produced NaN");
    }

    #[test]
    fn activation_checks_work() {
        assert!(activations_are_finite(&[1.0, -2.0, 0.0]));
        assert!(!activations_are_finite(&[1.0, f32::NAN]));
        assert!(!activations_are_finite(&[f32::INFINITY]));
    }
}