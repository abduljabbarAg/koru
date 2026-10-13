//! The transformer primitives, one at a time, each checkable on its own.
//!
//! The previous files decided what to run and computed one dot product. This
//! file assembles the pieces of an actual forward pass. Nothing here is fast;
//! all of it is meant to be obviously correct, because the failure mode of a
//! transformer implemented from scratch is not a crash. It is a model that
//! generates fluent, confident, wrong text, which is indistinguishable from a
//! working one until you compare it against something that works.
//!
//! So every function here is tested against a value computed by hand, and the
//! whole stack is tested against glen's `--dump1`, which prints the same
//! intermediates for a fixed prompt. That reference is the only thing standing
//! between "compiles" and "correct".

/// RMSNorm: `x / sqrt(mean(x^2) + eps)`, scaled by a learned weight.
///
/// Note it is RMS, not Layer: no mean subtraction and no bias. Every modern
/// decoder-only model uses this, and the difference matters — subtracting a
/// mean that is already been normalised out is a real numerical difference,
/// not a stylistic one.
pub fn rms_norm(x: &[f32], weight: &[f32], eps: f32, out: &mut [f32]) {
    assert_eq!(x.len(), out.len());
    assert_eq!(x.len(), weight.len(), "norm weight must match the hidden size");

    let n = x.len() as f32;
    let ss: f32 = x.iter().map(|v| v * v).sum();
    let scale = 1.0 / (ss / n + eps).sqrt();

    for i in 0..x.len() {
        out[i] = x[i] * scale * weight[i];
    }
}

/// Rotary position embedding, applied in place to the first `rot_dim` values
/// of each head.
///
/// Two conventions exist and mixing them up produces a model that generates
/// text with the token positions scrambled: "rotate half" (interleaved pairs)
/// versus "rotate half" on split halves. GGUF stores which one in
/// `rope.dimension_count` alongside the architecture, and the model here
/// (qwen2) uses the interleaved form, which is what this implements.
///
/// Position 0 must be the identity rotation. If it is not, every position is
/// wrong, and the cheapest possible test catches that.
pub fn rope(x: &mut [f32], head_dim: usize, pos: usize, n_heads: usize, theta: f32, neox: bool) {
    let half = head_dim / 2;
    for h in 0..n_heads {
        let base = h * head_dim;
        for i in 0..half {
            let freq = theta.powf(-((2 * i) as f32) / head_dim as f32);
            let angle = pos as f32 * freq;
            let (s, c) = angle.sin_cos();
            let (a, b) = if neox {
                // Adjacent pairs: [x0,x1], [x2,x3], ...
                (x[base + 2 * i], x[base + 2 * i + 1])
            } else {
                // Split halves: [x0..x(n/2)] paired with [x(n/2)..x(n)].
                // This is the GPT-J "normal" convention and what Qwen2 uses;
                // the adjacent-pair form is GPT-NeoX. Mixing them rotates the
                // wrong components and produces a model with scrambled
                // positions that still generates fluent text.
                (x[base + i], x[base + i + half])
            };
            if neox {
                x[base + 2 * i] = a * c - b * s;
                x[base + 2 * i + 1] = a * s + b * c;
            } else {
                x[base + i] = a * c - b * s;
                x[base + i + half] = a * s + b * c;
            }
        }
    }
}

/// Softmax over a whole slice, subtracting the max first.
///
/// The subtraction is not an optimisation detail, it is what makes the function
/// not overflow. Without it, a logit above about 88 in f32 gives exp() = inf
/// and the whole row becomes NaN. Real models do produce logits of that size.
pub fn softmax(x: &mut [f32]) {
    let max = x.iter().copied().fold(f32::NEG_INFINITY, f32::max);
    if !max.is_finite() {
        return;
    }
    let mut sum = 0f32;
    for v in x.iter_mut() {
        *v = (*v - max).exp();
        sum += *v;
    }
    if sum > 0.0 {
        for v in x.iter_mut() {
            *v /= sum;
        }
    }
}

/// SiLU, the activation half of SwiGLU: `x * sigmoid(x)`.
///
/// Computed as `x / (1 + e^-x)` rather than `x * sigmoid(x)` so the negative
/// branch does not compute an exp of a large positive number.
#[inline]
pub fn silu(x: f32) -> f32 {
    x / (1.0 + (-x).exp())
}

/// SwiGLU: `silu(gate) * up`, elementwise over two equal-length vectors.
///
/// This is the whole MLP. There is no bias and no activation after the
/// multiply: `down(silu(gate) * up)`. Getting that order wrong is the single
/// most common way a from-scratch implementation diverges, because it still
/// produces plausible numbers.
pub fn swiglu(gate: &[f32], up: &[f32], out: &mut [f32]) {
    assert_eq!(gate.len(), up.len());
    assert_eq!(gate.len(), out.len());
    for i in 0..gate.len() {
        out[i] = silu(gate[i]) * up[i];
    }
}

/// Grouped-query attention over one query position.
///
/// `q` is `n_head * head_dim`. `k` and `v` are `n_kv * head_dim`, holding the
/// *keys and values already concatenated over all past positions*, so
/// `n_past` positions each contribute `head_dim` floats.
///
/// GQA is the part worth reading twice. When `n_kv < n_head`, several query
/// heads share one key/value head: query head `h` uses KV head
/// `h / (n_head / n_kv)`. Getting that grouping wrong does not crash, it
/// produces a model that is subtly worse at long context, which is precisely
/// the thing GQA exists to be good at.
pub fn attention(
    q: &[f32],
    k: &[f32],
    v: &[f32],
    out: &mut [f32],
    n_head: usize,
    n_kv: usize,
    head_dim: usize,
    n_past: usize,
) {
    assert_eq!(q.len(), n_head * head_dim);
    assert_eq!(out.len(), n_head * head_dim);
    assert!(n_head % n_kv == 0, "n_head must divide by n_kv");
    let group = n_head / n_kv;

    assert_eq!(k.len(), n_kv * n_past * head_dim, "key cache size");
    assert_eq!(v.len(), k.len(), "value cache size");

    let scale = 1.0 / (head_dim as f32).sqrt();
    let mut scores = vec![0f32; n_past];

    for h in 0..n_head {
        let kvh = h / group;
        let qb = h * head_dim;

        for t in 0..n_past {
            let kb = (kvh * n_past + t) * head_dim;
            let mut s = 0f32;
            for d in 0..head_dim {
                s += q[qb + d] * k[kb + d];
            }
            scores[t] = s * scale;
        }

        softmax(&mut scores[..n_past]);

        for d in 0..head_dim {
            let mut acc = 0f32;
            for t in 0..n_past {
                acc += scores[t] * v[(kvh * n_past + t) * head_dim + d];
            }
            out[qb + d] = acc;
        }
    }
}

/// Argmax and its value. The tie-break is the lowest index, which makes
/// generation deterministic and testable.
pub fn argmax(x: &[f32]) -> (usize, f32) {
    let mut best = 0usize;
    let mut bv = f32::NEG_INFINITY;
    for (i, v) in x.iter().enumerate() {
        if *v > bv {
            bv = *v;
            best = i;
        }
    }
    (best, bv)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rms_norm_matches_a_hand_computed_vector() {
        // x = [3, 4], w = [1, 1]. mean(x^2) = (9+16)/2 = 12.5. eps = 0.
        // scale = 1/sqrt(12.5) = 0.28284271...
        // out = [3*scale, 4*scale] = [0.84852814, 1.13137085]
        let x = [3.0f32, 4.0];
        let w = [1.0f32, 1.0];
        let mut o = [0f32; 2];
        rms_norm(&x, &w, 0.0, &mut o);
        let s = 1.0 / 12.5f32.sqrt();
        assert!((o[0] - 3.0 * s).abs() < 1e-6, "got {}", o[0]);
        assert!((o[1] - 4.0 * s).abs() < 1e-6, "got {}", o[1]);
    }

    #[test]
    fn rms_norm_applies_the_learned_weight_after_normalising() {
        // The order matters: normalise, then scale. Doing it the other way
        // round is a different function and a different model.
        let x = [1.0f32, 2.0, 3.0, 4.0];
        let w = [2.0f32, 0.5, 1.0, 1.0];
        let mut o = [0f32; 4];
        rms_norm(&x, &w, 0.0, &mut o);

        let n = 4.0f32;
        let ss: f32 = x.iter().map(|v| v * v).sum();
        let s = 1.0 / (ss / n).sqrt();
        for i in 0..4 {
            assert!((o[i] - x[i] * s * w[i]).abs() < 1e-6, "index {i}");
        }
    }

    #[test]
    fn rms_norm_output_has_unit_rms_before_the_weight() {
        // The defining property. With an all-ones weight the result has
        // RMS 1, which is what makes the norm a norm.
        let x = [3.0f32, -1.0, 4.0, 1.0, 5.0, 9.0];
        let w = [1.0f32; 6];
        let mut o = [0f32; 6];
        rms_norm(&x, &w, 1e-6, &mut o);
        let ss: f32 = o.iter().map(|v| v * v).sum();
        let rms = (ss / 6.0).sqrt();
        assert!((rms - 1.0).abs() < 1e-4, "rms was {rms}");
    }

    #[test]
    fn rms_norm_epsilon_keeps_a_zero_vector_from_dividing_by_zero() {
        let x = [0.0f32; 4];
        let w = [1.0f32; 4];
        let mut o = [0f32; 4];
        rms_norm(&x, &w, 1e-5, &mut o);
        assert!(o.iter().all(|v| v.is_finite()), "produced {:?}", o);
    }

    #[test]
    fn rope_at_position_zero_is_the_identity() {
        // The cheapest possible test and it catches the most common RoPE bug.
        let original: Vec<f32> = (0..8).map(|i| (i as f32) * 0.25 - 1.0).collect();
        let mut x = original.clone();
        rope(&mut x, 8, 0, 1, 10000.0, false);
        for i in 0..8 {
            assert!((x[i] - original[i]).abs() < 1e-5, "index {i}: {} vs {}", x[i], original[i]);
        }
    }

    #[test]
    fn rope_rotates_by_the_expected_angle_split_halves() {
        // Split halves (Qwen2, GPT-J): x[0] pairs with x[half]. With
        // head_dim 4, half is 2, so x[0] rotates against x[2].
        // Pair 0 has frequency 1, so at position 1 the angle is 1 radian.
        let mut x = vec![1.0f32, 0.0, 0.0, 0.0];
        rope(&mut x, 4, 1, 1, 10000.0, false);
        let (s, c) = 1.0f32.sin_cos();
        assert!((x[0] - c).abs() < 1e-5, "x0 {}", x[0]);
        assert!((x[2] - s).abs() < 1e-5, "x2 {}", x[2]);
    }

    #[test]
    fn rope_rotates_by_the_expected_angle_adjacent_pairs() {
        // Adjacent pairs (GPT-NeoX): x[0] pairs with x[1]. Both conventions
        // are real and they are not interchangeable, so both are pinned.
        let mut x = vec![1.0f32, 0.0, 0.0, 0.0];
        rope(&mut x, 4, 1, 1, 10000.0, true);
        let (s, c) = 1.0f32.sin_cos();
        assert!((x[0] - c).abs() < 1e-5, "x0 {}", x[0]);
        assert!((x[1] - s).abs() < 1e-5, "x1 {}", x[1]);
    }

    #[test]
    fn rope_preserves_the_norm_of_each_pair() {
        // A rotation cannot change a length. If it does, the implementation
        // is scaling as well as rotating.
        // Split halves pairs index i with i + head_dim/2, not adjacent
        // indices, so the pairs to check are strided by the half-width.
        let mut x: Vec<f32> = (0..16).map(|i| (i as f32) * 0.7 - 3.0).collect();
        let before: Vec<f32> = x.clone();
        rope(&mut x, 8, 7, 2, 10000.0, false);
        for h in 0..2 {
            let base = h * 8;
            for i in 0..4 {
                let p = base + i;
                let nb = (before[p] * before[p] + before[p + 4] * before[p + 4]).sqrt();
                let na = (x[p] * x[p] + x[p + 4] * x[p + 4]).sqrt();
                assert!((nb - na).abs() < 1e-4, "pair {p}: {nb} vs {na}");
            }
        }
    }

    #[test]
    fn softmax_sums_to_one_and_is_monotone() {
        let mut x = vec![1.0f32, 2.0, 3.0, 4.0];
        softmax(&mut x);
        let s: f32 = x.iter().sum();
        assert!((s - 1.0).abs() < 1e-6, "sum {s}");
        assert!(x[3] > x[2] && x[2] > x[1] && x[1] > x[0]);
    }

    #[test]
    fn softmax_survives_logits_that_would_overflow() {
        // Without the max subtraction these become exp(100) = inf.
        let mut x = vec![100.0f32, 101.0, 102.0];
        softmax(&mut x);
        assert!(x.iter().all(|v| v.is_finite()), "got {:?}", x);
        let s: f32 = x.iter().sum();
        assert!((s - 1.0).abs() < 1e-5, "sum {s}");
    }

    #[test]
    fn silu_matches_known_values() {
        assert!((silu(0.0) - 0.0).abs() < 1e-6);
        // silu(1) = 1 * sigmoid(1) = 0.7310586
        assert!((silu(1.0) - 0.73105858).abs() < 1e-6, "got {}", silu(1.0));
        // silu(-1) = -1 * sigmoid(-1) = -0.2689414
        assert!((silu(-1.0) + 0.26894142).abs() < 1e-6, "got {}", silu(-1.0));
    }

    #[test]
    fn silu_is_finite_for_extreme_inputs() {
        for v in [-100.0f32, -50.0, 50.0, 100.0] {
            assert!(silu(v).is_finite(), "silu({v}) overflowed");
        }
    }

    #[test]
    fn swiglu_is_silu_of_gate_times_up() {
        let gate = [0.0f32, 1.0, -1.0];
        let up = [2.0f32, 1.0, 3.0];
        let mut o = [0f32; 3];
        swiglu(&gate, &up, &mut o);
        for i in 0..3 {
            assert!((o[i] - silu(gate[i]) * up[i]).abs() < 1e-6, "index {i}");
        }
    }

    #[test]
    fn attention_with_one_key_is_just_the_value() {
        // One past position means one key and one value, so the output is
        // that value regardless of the query. A softmax over a single element
        // is 1.0, which makes this the cleanest possible attention test.
        let q = [1.0f32, 2.0, 3.0, 4.0];
        let k = [9.0f32, 9.0, 9.0, 9.0];
        let v = [0.25f32, 0.5, 0.75, 1.0];
        let mut o = [0f32; 4];
        attention(&q, &k, &v, &mut o, 1, 1, 4, 1);
        for i in 0..4 {
            assert!((o[i] - v[i]).abs() < 1e-5, "index {i}: {} vs {}", o[i], v[i]);
        }
    }

    #[test]
    fn attention_matches_an_explicitly_computed_two_key_case() {
        // 1 head, head_dim 2, two positions.
        //   q  = [1, 0]
        //   k0 = [1, 0],  v0 = [10, 20]
        //   k1 = [0, 1],  v1 = [30, 40]
        // scale = 1/sqrt(2).
        // scores = [1/sqrt2, 0] -> softmax -> [0.6698, 0.3302]
        // out = 0.6698*[10,20] + 0.3302*[30,40] = [16.604, 26.604]
        let q = [1.0f32, 0.0];
        let k = [1.0f32, 0.0, 0.0, 1.0]; // k0 then k1, each head_dim wide
        let v = [10.0f32, 20.0, 30.0, 40.0];
        let mut o = [0f32; 2];
        attention(&q, &k, &v, &mut o, 1, 1, 2, 2);

        let s = (1.0f32 / 2.0f32.sqrt()).exp();
        let p0 = s / (1.0 + s);
        let p1 = 1.0 / (1.0 + s);
        let e0 = p0 * 10.0 + p1 * 30.0;
        let e1 = p0 * 20.0 + p1 * 40.0;
        assert!((o[0] - e0).abs() < 1e-4, "got {} want {e0}", o[0]);
        assert!((o[1] - e1).abs() < 1e-4, "got {} want {e1}", o[1]);
    }

    #[test]
    fn gqa_shares_one_kv_head_across_several_query_heads() {
        // 4 query heads, 2 KV heads: heads 0,1 use KV 0; heads 2,3 use KV 1.
        // Constructed so a wrong grouping changes the answer.
        let hd = 2;
        let q = vec![1.0f32; 8]; // 4 heads x 2
        // KV head 0 holds position 0; KV head 1 holds position 1.
        let k = vec![1.0f32, 0.0, 1.0, 0.0];
        let v = vec![1.0f32, 1.0, 9.0, 9.0];
        let mut o = vec![0f32; 8];
        attention(&q, &k, &v, &mut o, 4, 2, hd, 1);

        // Heads 0 and 1 read KV head 0, so they get 1.
        assert!((o[0] - 1.0).abs() < 1e-5, "head 0 got {}", o[0]);
        assert!((o[2] - 1.0).abs() < 1e-5, "head 1 got {}", o[2]);
        // Heads 2 and 3 read KV head 1, so they get 9.
        assert!((o[4] - 9.0).abs() < 1e-5, "head 2 got {}", o[4]);
        assert!((o[6] - 9.0).abs() < 1e-5, "head 3 got {}", o[6]);
    }

    #[test]
    fn argmax_breaks_ties_toward_the_lowest_index() {
        assert_eq!(argmax(&[1.0, 5.0, 3.0]), (1, 5.0));
        assert_eq!(argmax(&[5.0, 5.0, 1.0]), (0, 5.0));
        assert_eq!(argmax(&[-1.0, -2.0]), (0, -1.0));
    }
}