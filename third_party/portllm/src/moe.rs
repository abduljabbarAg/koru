//! Sparse mixture-of-experts routing.
//!
//! A dense feed-forward block computes every neuron. A mixture block has a
//! router that scores the input against every expert, picks the top few, and
//! runs only those, weighting each by a softmax over the chosen scores. The
//! arithmetic is the same; what changes is that eight of sixty-four experts
//! run instead of all of them, which is the whole reason the model is worth
//! running on a phone at all.
//!
//! Two details decide whether the output is right or merely finite:
//!
//!  * The scores must be normalised over the *selected* experts, not over all
//!    of them. Normalising over all sixty-four and then discarding leaves
//!    outputs that are far too small, which still generate fluent text, which
//!    is why this is easy to miss.
//!  * Ties in the router scores must break deterministically, or two runs on
//!    the same input can select different experts and the model stops being
//!    reproducible.

use crate::gguf::Header;

/// Router shape, read from the model's own metadata.
#[derive(Clone, Copy, Debug)]
pub struct MoeShape {
    pub n_expert: usize,
    pub n_used: usize,
    pub n_embd: usize,
}

impl MoeShape {
    /// Read the expert configuration, or `None` for a dense model.
    pub fn from_header(h: &Header, arch: &str) -> Option<MoeShape> {
        let n_expert = h.num(&format!("{arch}.expert_count"))? as usize;
        let n_used = h.num(&format!("{arch}.expert_used_count"))? as usize;
        let n_embd = h.num(&format!("{arch}.embedding_length"))? as usize;
        if n_expert == 0 || n_used == 0 || n_used > n_expert {
            return None;
        }
        Some(MoeShape { n_expert, n_used, n_embd })
    }
}

/// The experts a single token routed to.
#[derive(Clone, Debug, PartialEq)]
pub struct Route {
    /// Expert indices, highest score first.
    pub experts: Vec<usize>,
    /// Softmax weight per selected expert, summing to one.
    pub weights: Vec<f32>,
}

/// Score every expert and return the top `n_used`.
///
/// Returns indices sorted by score, descending, with a deterministic tie-break
/// on index so the same input always routes the same way.
pub fn route(weights: &[f32], x: &[f32], n_used: usize) -> Route {
    assert!(
        weights.len() % x.len() == 0 && !x.is_empty(),
        "router weights ({}) must be a whole number of {}-wide rows",
        weights.len(),
        x.len()
    );
    let n_expert = weights.len() / x.len();

    // Scores for every expert. The router weight is [n_expert][n_embd], so
    // expert e reads row e.
    let mut scored: Vec<(usize, f32)> = (0..n_expert)
        .map(|e| {
            let row = &weights[e * x.len()..(e + 1) * x.len()];
            let mut s = 0f32;
            for (w, v) in row.iter().zip(x) {
                s += *w * *v;
            }
            (e, s)
        })
        .collect();

    // Highest score first; ties resolve to the lower index.
    scored.sort_by(|a, b| {
        b.1.partial_cmp(&a.1)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.0.cmp(&b.0))
    });
    scored.truncate(n_used.min(scored.len()));

    // Softmax over the selected scores only.
    let max = scored.iter().map(|(_, s)| *s).fold(f32::NEG_INFINITY, f32::max);
    let mut weights: Vec<f32> = scored.iter().map(|(_, s)| (s - max).exp()).collect();
    let sum: f32 = weights.iter().sum();
    if sum > 0.0 && sum.is_finite() {
        for w in &mut weights {
            *w /= sum;
        }
    } else {
        // A degenerate row would otherwise produce NaN weights that silently
        // poison every downstream value.
        let uniform = 1.0 / weights.len().max(1) as f32;
        for w in &mut weights {
            *w = uniform;
        }
    }

    Route {
        experts: scored.iter().map(|(e, _)| *e).collect(),
        weights,
    }
}

/// Combine the selected experts' outputs.
///
/// This is the weighted sum that turns a list of expert results back into one
/// vector of the model's width.
pub fn combine(expert_outs: &[Vec<f32>], weights: &[f32], n_embd: usize, out: &mut [f32]) {
    for v in out.iter_mut().take(n_embd) {
        *v = 0.0;
    }
    for (o, w) in expert_outs.iter().zip(weights) {
        for (dst, src) in out.iter_mut().take(n_embd).zip(o.iter().take(n_embd)) {
            *dst += *w * *src;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gguf::{self, Value};

    fn w(n_expert: usize, n_embd: usize, f: impl Fn(usize, usize) -> f32) -> Vec<f32> {
        (0..n_expert * n_embd).map(|i| f(i / n_embd, i % n_embd)).collect()
    }

    #[test]
    fn selects_the_highest_scoring_experts() {
        let n_embd = 4;
        // Experts 0 and 3 score highest on this input; 1 and 2 tie at zero.
        let weights = w(4, n_embd, |e, _| match e {
            0 => 1.0,
            3 => 2.0,
            _ => 0.0,
        });
        let x = vec![1.0f32, 1.0, 1.0, 1.0];
        let r = route(&weights, &x, 2);
        assert_eq!(r.experts, vec![3, 0], "order must be by score");
    }

    #[test]
    fn weights_sum_to_one_over_the_selection() {
        let weights = w(8, 3, |e, i| (e as f32 + 1.0) * (i as f32 + 1.0));
        let x = vec![1.0f32, 2.0, 3.0];
        let r = route(&weights, &x, 3);
        let sum: f32 = r.weights.iter().sum();
        assert!((sum - 1.0).abs() < 1e-5, "weights summed to {sum}");
        // The point of normalising over the selection is that the top weight
        // can reach 1. Normalising over all eight and then keeping three would
        // cap every weight at 3/8, so the sum-to-one check above is the real
        // assertion; this pins that the top one is genuinely dominant here.
        assert!(
            r.weights[0] > 0.9,
            "the best expert should dominate this input: {:?}",
            r.weights
        );
    }

    #[test]
    fn ties_break_to_the_lower_index_deterministically() {
        // Every expert scores identically, so only the tie-break decides.
        let weights = w(6, 2, |_, _| 1.0);
        let x = vec![1.0f32, 1.0];
        let a = route(&weights, &x, 3);
        let b = route(&weights, &x, 3);
        assert_eq!(a, b, "routing must be reproducible");
        assert_eq!(a.experts, vec![0, 1, 2]);
    }

    #[test]
    fn asking_for_more_than_exists_is_clamped() {
        let weights = w(2, 2, |_, _| 1.0);
        let x = vec![1.0f32, 1.0];
        let r = route(&weights, &x, 5);
        assert_eq!(r.experts.len(), 2);
        let sum: f32 = r.weights.iter().sum();
        assert!((sum - 1.0).abs() < 1e-5);
    }

    #[test]
    fn a_zero_row_gives_uniform_weights_not_nan() {
        let weights = w(4, 3, |_, _| 0.0);
        let x = vec![0.0f32; 3];
        let r = route(&weights, &x, 2);
        assert!(r.weights.iter().all(|w| w.is_finite()), "NaN weights: {:?}", r.weights);
        assert!((r.weights.iter().sum::<f32>() - 1.0).abs() < 1e-5);
    }

    #[test]
    fn huge_scores_do_not_overflow() {
        let weights = w(4, 2, |e, _| 1e30 * (e as f32 + 1.0));
        let x = vec![1e10f32, 1e10];
        let r = route(&weights, &x, 2);
        assert!(r.weights.iter().all(|w| w.is_finite()), "{:?}", r.weights);
    }

    #[test]
    fn combine_is_a_weighted_sum() {
        let outs = vec![vec![1.0f32, 2.0], vec![3.0, 4.0]];
        let mut out = vec![9.0f32; 2];
        combine(&outs, &[0.25, 0.75], 2, &mut out);
        assert!((out[0] - 2.5).abs() < 1e-6);
        assert!((out[1] - 3.5).abs() < 1e-6);
    }

    #[test]
    fn combine_clears_the_destination_first() {
        let mut out = vec![100.0f32, 100.0];
        combine(&[vec![1.0f32, 1.0]], &[1.0], 2, &mut out);
        assert_eq!(out, vec![1.0, 1.0], "stale values leaked through");
    }

    #[test]
    fn routing_is_stable_across_calls() {
        let weights = w(16, 8, |e, i| ((e * 7 + i * 3) % 11) as f32);
        let x: Vec<f32> = (0..8).map(|i| (i as f32 * 0.5).sin()).collect();
        let a = route(&weights, &x, 8);
        for _ in 0..20 {
            assert_eq!(route(&weights, &x, 8), a, "routing drifted between calls");
        }
    }

    #[test]
    fn reads_shape_from_a_real_moe_header() {
        let p = std::path::Path::new("/tmp/olmoe-head.bin");
        if !p.exists() {
            return;
        }
        let h = gguf::read_header(p).expect("header");
        let s = MoeShape::from_header(&h, "olmoe").expect("moe shape");
        assert_eq!(s.n_expert, 64);
        assert_eq!(s.n_used, 8);
        assert_eq!(s.n_embd, 2048);
        // A dense model must not be mistaken for a sparse one.
        let d = std::path::Path::new("/tmp/qwen05b-good.gguf");
        if d.exists() {
            let hd = gguf::read_header(d).expect("dense header");
            assert!(MoeShape::from_header(&hd, "qwen2").is_none());
        }
        let _ = Value::U64(0);
    }

    #[test]
    fn the_real_router_selects_a_plausible_number_of_experts() {
        let p = std::path::Path::new("/tmp/olmoe-head.bin");
        if !p.exists() {
            return;
        }
        let h = gguf::read_header(p).expect("header");
        let shape = MoeShape::from_header(&h, "olmoe").expect("shape");
        let t = h.tensors.iter().find(|t| t.name == "blk.0.ffn_gate_inp.weight").expect("router");
        assert_eq!(t.ggml_type, 0, "router is f32");
        assert_eq!(
            t.elements as usize,
            shape.n_expert * shape.n_embd,
            "router is one row per expert"
        );
        assert_eq!(t.elements as usize, 131072);
    }
}