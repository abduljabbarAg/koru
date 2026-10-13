//! Turning logits into text.
//!
//! The forward pass produces a score per vocabulary entry. Sampling decides
//! which one to emit. Two choices matter and are easy to get wrong:
//!
//!  * Greedy takes the highest score every time. It is reproducible and it is
//!    what makes a correctness comparison possible, but it produces flat,
//!    looping text because the same token wins again and again.
//!  * Temperature reshapes the distribution before the draw. Below 1.0 it
//!    sharpens and repeats; above 1.0 it flattens and wanders into incoherence.
//!    Sampling must be driven by a seeded generator so a run can be repeated
//!    exactly, otherwise a bug and bad luck look identical.

/// A small, seeded xorshift generator.
///
/// Deliberately not from the system entropy pool: inference needs to be
/// reproducible from a seed so the same prompt and seed give the same text.
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        // Zero is a fixed point for xorshift, so it is replaced.
        Rng(if seed == 0 { 0x9E3779B97F4A7C15 } else { seed })
    }

    /// A splitmix64 finaliser.
    ///
    /// Plain xorshift alone leaves the high bits of nearby seeds correlated:
    /// seeds 1 and 2 produce visibly similar streams, which silently biases
    /// sampling for small seeds. Mixing every output costs three multiplies
    /// and makes adjacent seeds behave independently.
    fn mix(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E3779B97F4A7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
        z ^ (z >> 31)
    }

    pub fn next_u64(&mut self) -> u64 {
        self.mix()
    }

    /// Uniform in `[0, 1)`, using the high 24 bits so every representable
    /// f32 in that range is reachable with the intended resolution.
    pub fn next_f32(&mut self) -> f32 {
        (self.mix() >> 40) as f32 / (1u32 << 24) as f32
    }
}

/// Pick one token.
///
/// With `temperature` at or below zero this is greedy, which is what tests and
/// reproducible runs use. Above zero it samples from the softmax with an
/// exponent of `1/temperature`.
pub fn sample(logits: &[f32], temperature: f32, rng: &mut Rng) -> usize {
    if logits.is_empty() {
        return 0;
    }
    if temperature <= 0.0 {
        return argmax(logits);
    }

    let max = logits.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
    // exp of (logit - max) so nothing overflows, then scale by temperature.
    let inv_t = 1.0 / temperature;
    let mut probs: Vec<f32> = logits.iter().map(|l| ((l - max) * inv_t).exp()).collect();
    let sum: f32 = probs.iter().sum();
    if sum <= 0.0 || !sum.is_finite() {
        return argmax(logits);
    }

    let mut r = rng.next_f32() * sum;
    for (i, p) in probs.iter_mut().enumerate() {
        r -= *p;
        if r <= 0.0 {
            return i;
        }
    }
    probs.clear();
    logits.len() - 1
}

pub fn argmax(logits: &[f32]) -> usize {
    let mut best = 0;
    let mut bv = f32::NEG_INFINITY;
    for (i, l) in logits.iter().enumerate() {
        if *l > bv {
            bv = *l;
            best = i;
        }
    }
    best
}

/// Keep only the most likely `k` tokens, then renormalise.
///
/// This is nucleus sampling. Trimming the long tail before the draw is what
/// stops a flat distribution from occasionally emitting a near-zero-probability
/// token and derailing the sentence.
pub fn top_k_top_p(logits: &[f32], k: usize, p: f32) -> Vec<usize> {
    let mut idx: Vec<usize> = (0..logits.len()).collect();
    idx.sort_by(|a, b| logits[*b].partial_cmp(&logits[*a]).unwrap_or(std::cmp::Ordering::Equal));

    let mut keep = k.min(idx.len());
    let mut probs: Vec<f32> = idx.iter().take(keep).map(|i| logits[*i].exp()).collect();
    let sum: f32 = probs.iter().sum();
    if sum > 0.0 {
        for p in &mut probs {
            *p /= sum;
        }
    }

    // Cumulative cut.
    if p > 0.0 && p < 1.0 {
        let mut acc = 0f32;
        let mut cut = probs.len();
        for (i, pr) in probs.iter().enumerate() {
            acc += *pr;
            if acc >= p {
                cut = i + 1;
                break;
            }
        }
        keep = cut;
        probs.truncate(keep);
        let s: f32 = probs.iter().sum();
        if s > 0.0 {
            for pr in &mut probs {
                *pr /= s;
            }
        }
    }

    idx.truncate(keep);
    idx
}

/// Restrict `logits` in place to the given candidate indices.
pub fn restrict(logits: &mut Vec<f32>, keep: &[usize]) {
    let mut out = vec![f32::NEG_INFINITY; logits.len()];
    for (slot, src) in keep.iter().enumerate() {
        out[slot] = logits[*src];
    }
    *logits = out;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greedy_takes_the_largest() {
        let l = [1.0, 5.0, 2.0, 5.0];
        assert_eq!(sample(&l, 0.0, &mut Rng::new(1)), 1, "first max wins ties");
    }

    #[test]
    fn greedy_ignores_the_seed() {
        let l = [1.0, 9.0, 2.0];
        assert_eq!(sample(&l, 0.0, &mut Rng::new(1)), 1);
        assert_eq!(sample(&l, 0.0, &mut Rng::new(99)), 1);
    }

    #[test]
    fn same_seed_gives_the_same_text() {
        let l: Vec<f32> = (0..500).map(|i| (i as f32 * 0.01).sin()).collect();
        let a: Vec<usize> = (0..50).map(|_| sample(&l, 0.8, &mut Rng::new(7))).collect();
        let b: Vec<usize> = (0..50).map(|_| sample(&l, 0.8, &mut Rng::new(7))).collect();
        assert_eq!(a, b, "sampling must be reproducible from the seed");
    }

    #[test]
    fn different_seeds_diverge() {
        let l: Vec<f32> = (0..500).map(|i| (i as f32 * 0.01).sin()).collect();
        let a: Vec<usize> = (0..50).map(|_| sample(&l, 0.8, &mut Rng::new(1))).collect();
        let b: Vec<usize> = (0..50).map(|_| sample(&l, 0.8, &mut Rng::new(2))).collect();
        assert_ne!(a, b, "different seeds should not give identical output");
    }

    #[test]
    fn low_temperature_concentrates() {
        // With a peak much higher than the rest, cold sampling should almost
        // always pick the peak.
        let mut l = vec![0.0f32; 200];
        l[7] = 10.0;
        let mut hits = 0;
        for s in 0..200 {
            if sample(&l, 0.1, &mut Rng::new(s)) == 7 {
                hits += 1;
            }
        }
        assert!(hits > 180, "cold sampling only hit the peak {hits} times");
    }

    #[test]
    fn rng_produces_varied_values() {
        let mut r = Rng::new(1);
        let v: Vec<f32> = (0..8).map(|_| r.next_f32()).collect();
        assert!(v.iter().any(|x| *x > 0.0), "all zero: {v:?}");
        assert!(v.iter().any(|x| *x > 0.01), "degenerate: {v:?}");
    }

    #[test]
    fn rng_never_returns_one() {
        let mut r = Rng::new(3);
        for _ in 0..10_000 {
            let v = r.next_f32();
            assert!((0.0..1.0).contains(&v), "out of range: {v}");
        }
    }

    #[test]
    fn top_k_keeps_the_k_best_in_order() {
        let l = [0.1f32, 5.0, 0.2, 3.0, 0.05];
        let keep = top_k_top_p(&l, 2, 1.0);
        assert_eq!(keep, vec![1, 3]);
    }

    #[test]
    fn top_p_trims_the_tail() {
        // With one dominant peak, p=0.5 is reached at the first token and
        // everything else is legitimately cut.
        let peaked = [5.0f32, 4.0, 3.0, 0.0, 0.0];
        assert_eq!(top_k_top_p(&peaked, 5, 0.5), vec![0]);

        // With a flat spread, p=0.9 must keep several tokens, and the order
        // must stay sorted best first.
        let flat = [1.0f32, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
        let keep = top_k_top_p(&flat, 10, 0.9);
        assert!(keep.len() > 1, "a flat row must keep more than one, kept {keep:?}");
        assert!(keep.len() < 10, "the tail must still be cut, kept {keep:?}");
        assert!(keep.windows(2).all(|w| w[0] <= w[1]), "not sorted: {keep:?}");
    }

    #[test]
    fn top_p_of_one_keeps_only_the_peak() {
        let l = [0.0f32, 0.0, 0.0];
        assert_eq!(top_k_top_p(&l, 3, 1.0), vec![0, 1, 2]);
        assert_eq!(top_k_top_p(&l, 1, 1.0), vec![0]);
    }

    #[test]
    fn restrict_is_a_projection() {
        let mut l = vec![1.0f32, 2.0, 3.0];
        restrict(&mut l, &[2, 0]);
        assert_eq!(l[0], 3.0);
        assert_eq!(l[1], 1.0);
        assert!(l[2].is_infinite() && l[2] < 0.0, "dropped entries must not win");
    }

    #[test]
    fn empty_logits_do_not_panic() {
        assert_eq!(sample(&[], 0.0, &mut Rng::new(1)), 0);
        assert_eq!(argmax(&[]), 0);
    }
}
/// Discourage tokens that already appeared, by dividing their logit if it is
/// positive and multiplying it if it is negative.
///
/// Repetition is the failure mode that is most visible in generated text: a
/// greedy model falls into "the the the" and a sampled one builds the same
/// sentence twice. The penalty has to look at what was actually emitted, not
/// at what merely scored well, because penalising high-scoring tokens that
/// were never chosen changes the text for no reason.
///
/// The sign handling matters. Dividing a negative logit by a number greater
/// than one makes it *more* negative, which is the intent, but applying one
/// formula to both signs pushes the wrong way on negatives. Splitting them is
/// what makes this a penalty rather than a distortion.
pub fn apply_repeat_penalty(
    logits: &mut [f32],
    history: &[u32],
    penalty: f32,
) {
    if penalty <= 0.0 || history.is_empty() || penalty == 1.0 {
        return;
    }
    for id in history {
        let Some(l) = logits.get_mut(*id as usize) else {
            continue;
        };
        if *l > 0.0 {
            *l /= penalty;
        } else {
            *l *= penalty;
        }
    }
}

/// Stop the sequence when the emitted tokens end with one of these.
///
/// Stopping is decided on the token *ids*, not the decoded text, because a
/// string can straddle a token boundary. `" stop"` might arrive as one token
/// or as three, and only the id comparison catches both without having to
/// re-tokenise the whole output on every step.
///
/// A stop string of one token is matched as that token; longer strings are
/// matched as a suffix of the generated history.
pub struct Stopper {
    sequences: Vec<Vec<u32>>,
}

impl Stopper {
    /// Build from decoded stop strings, via the model's own tokenizer.
    pub fn from_texts(tok: &crate::tokenizer::Tokenizer, texts: &[String]) -> Self {
        let sequences = texts
            .iter()
            .map(|t| tok.encode(t))
            .filter(|ids| !ids.is_empty())
            .collect();
        Stopper { sequences }
    }

    pub fn is_empty(&self) -> bool {
        self.sequences.is_empty()
    }

    /// True when `history` now ends with a stop sequence.
    pub fn matches(&self, history: &[u32]) -> Option<usize> {
        for seq in &self.sequences {
            if seq.len() > history.len() {
                continue;
            }
            if history[history.len() - seq.len()..] == seq[..] {
                return Some(seq.len());
            }
        }
        None
    }
}

#[cfg(test)]
mod history_tests {
    use super::*;

    #[test]
    fn repeat_penalty_divides_positive_logits() {
        let mut l = vec![4.0f32, 1.0];
        apply_repeat_penalty(&mut l, &[0], 2.0);
        assert!((l[0] - 2.0).abs() < 1e-6, "positive logit should shrink: {}", l[0]);
        assert_eq!(l[1], 1.0, "untouched tokens must not move");
    }

    #[test]
    fn repeat_penalty_multiplies_negative_logits() {
        let mut l = vec![-4.0f32, 1.0];
        apply_repeat_penalty(&mut l, &[0], 2.0);
        assert!((l[0] + 8.0).abs() < 1e-6, "negative logit should get worse: {}", l[0]);
    }

    /// The sign split is the whole reason this is a penalty. Applying one
    /// formula to both signs would make a negative logit *less* likely to be
    /// sampled, which is backwards.
    #[test]
    fn repeat_penalty_pushes_repeats_down_in_rank() {
        let mut l = vec![10.0f32, 9.5];
        let before = argmax(&l);
        apply_repeat_penalty(&mut l, &[before as u32], 4.0);
        assert_ne!(argmax(&l), before, "the repeated token should lose the top spot");
    }

    #[test]
    fn a_penalty_of_one_changes_nothing() {
        let mut l = vec![3.0f32, -2.0, 7.0];
        let orig = l.clone();
        apply_repeat_penalty(&mut l, &[0, 1, 2], 1.0);
        assert_eq!(l, orig);
    }

    #[test]
    fn no_history_is_a_no_op() {
        let mut l = vec![3.0f32];
        apply_repeat_penalty(&mut l, &[], 2.0);
        assert_eq!(l[0], 3.0);
    }

    #[test]
    fn an_out_of_range_token_is_ignored() {
        let mut l = vec![1.0f32];
        apply_repeat_penalty(&mut l, &[999_999], 2.0);
        assert_eq!(l[0], 1.0, "must not panic on a bad id");
    }

    fn stopper(pairs: &[(&[u32], &[u32])]) -> Stopper {
        Stopper {
            sequences: pairs.iter().map(|(a, _)| a.to_vec()).collect(),
        }
    }

    #[test]
    fn a_stop_sequence_matches_a_suffix() {
        let s = stopper(&[(&[1, 2, 3], &[])]);
        assert_eq!(s.matches(&[9, 1, 2, 3]), Some(3));
    }

    #[test]
    fn a_stop_sequence_does_not_match_a_prefix() {
        let s = stopper(&[(&[1, 2, 3], &[])]);
        assert_eq!(s.matches(&[1, 2, 3, 9]), None, "a prefix is not a suffix");
    }

    #[test]
    fn a_short_history_cannot_match_a_long_sequence() {
        let s = stopper(&[(&[1, 2, 3], &[])]);
        assert_eq!(s.matches(&[1]), None);
    }

    #[test]
    fn several_stops_all_work() {
        let s = stopper(&[(&[1], &[]), (&[7, 8], &[])]);
        assert_eq!(s.matches(&[5, 1]), Some(1));
        assert_eq!(s.matches(&[5, 7, 8]), Some(2));
        assert_eq!(s.matches(&[5, 6]), None);
    }

    #[test]
    fn an_empty_stopper_never_matches() {
        let s = Stopper { sequences: Vec::new() };
        assert!(s.is_empty());
        assert_eq!(s.matches(&[1, 2, 3]), None);
    }
}

impl Stopper {
    /// A stopper that never fires, for callers with no stop sequences.
    pub fn default_empty() -> Self {
        Stopper { sequences: Vec::new() }
    }
}
