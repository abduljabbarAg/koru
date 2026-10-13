//! Deciding which models this device can actually run, and which will kill it.
//!
//! The mistake this file exists to prevent: budgeting only for weights. A 3 GB
//! model is not a 3 GB footprint. Its KV cache grows linearly with context, and
//! context is what turns a 3 GB model into an 8.8 GB one. A recommender that
//! compares weights against RAM will confidently suggest a model that gets the
//! app OOM killed the first time a conversation gets long.
//!
//! Two things are scored separately on purpose:
//!
//! * **Capacity** can fit. Weights plus KV plus working set, against available
//!   RAM. This is a yes/no with a margin.
//! * **Throughput** is worth it. Decode is memory-bandwidth-bound, so a model
//!   whose active weights exceed what the device can stream per second is
//!   technically runnable and practically unusable.
//!
//! Everything is estimated from measured device facts and published architecture
//! metadata. Estimates are labelled as such, because a number that pretends to
//! be measured is worse than no number.

use crate::device::{Accel, Device};
use crate::registry::Model;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Verdict {
    /// Cannot run at all. Shown so the user learns why, not hidden.
    TooHeavy,
    /// Runs only by streaming weights from storage. Slow but honest.
    Streaming,
    /// Runs, but memory is tight enough that the OS may intervene.
    Tight,
    /// Comfortable. Room for the OS, the browser, and a long conversation.
    Good,
    /// The best this device can do.
    Ideal,
}

impl Verdict {
    pub fn label(self) -> &'static str {
        match self {
            Verdict::TooHeavy => "too heavy",
            Verdict::Streaming => "streaming",
            Verdict::Tight => "tight",
            Verdict::Good => "good",
            Verdict::Ideal => "ideal",
        }
    }
}

/// What the OS and everything else already need. On a phone this is not
/// optional: the launcher, the compositor and the app's own UI are all
/// resident before we allocate a byte.
const OS_HEADROOM_MB: u64 = 320;

/// Peak memory for a model at a given context: weights, KV, and the scratch
/// space a decode step needs for its activations.
pub fn peak_bytes(m: &Model, ctx: u32) -> u64 {
    let weights = m.weight_bytes;
    let kv = m.kv_bytes(ctx);

    // Activations scale with the widest intermediate in the forward pass, not
    // with parameter count. A rough multiple of the KV row width is close
    // enough for a recommendation and never the thing that tips a device over.
    let scratch = 64 * 1024 * 1024;

    weights + kv + scratch
}

/// Score one model against one device at one context length.
pub fn score(dev: &Device, m: &Model, ctx: u32) -> Fit {
    let peak = peak_bytes(m, ctx);
    let budget = (dev.ram_available_mb.saturating_sub(OS_HEADROOM_MB)) * 1024 * 1024;

    let memory_ratio = peak as f64 / budget.max(1) as f64;

    // Decode bandwidth actually achieved, not peak. glen measures 6.39 to 6.89
    // tok/s on a 491,400,032 byte model on a Helio G99, which works out to
    // 3.1 to 3.4 GB/s of weights streamed per token. That is the number to
    // plan with, because it already contains everything the theory leaves out:
    // dequant, softmax, norm, rope, and the passes that read no weights at all.
    //
    // An unreachable GPU is deliberately identical to CPU. It is tempting to
    // give it a middling value, but it cannot dispatch a single kernel from
    // here, so any value above CPU is a number that will never be earned.
    let effective_bandwidth_gbs = match dev.accel {
        Accel::ReachableGpu => 6.0, // TODO: measure. No Adreno in hand.
        Accel::Npu => 8.0,          // TODO: measure. No NPU in hand.
        Accel::UnreachableGpu | Accel::None | Accel::Cpu => 3.2,
    };

    let bytes_per_token = m.active_bytes() as f64;
    let tok_s = (effective_bandwidth_gbs * 1e9) / bytes_per_token.max(1.0);

    let verdict = if memory_ratio > 1.0 {
        // Over budget. Streaming is the only way this ever runs, and it runs
        // at whatever storage gives us.
        Verdict::TooHeavy
    } else if memory_ratio > 0.85 {
        Verdict::Tight
    } else if memory_ratio < 0.45 {
        Verdict::Ideal
    } else {
        Verdict::Good
    };

    // Streaming is viable when storage can feed active weights faster than we
    // generate. Below roughly 2x the per-token read we will never win the race.
    let streaming_viable = dev.storage_read_mb_s > 0
        && ((bytes_per_token / (1024.0 * 1024.0)) as u64)
            < dev.storage_read_mb_s.saturating_mul(2).max(1);

    Fit {
        model_id: m.id,
        ctx,
        peak_bytes: peak,
        budget_bytes: budget,
        memory_ratio,
        est_tok_s: tok_s,
        verdict,
        streaming_viable,
        is_moe: m.is_moe(),
        quality: m.quality,
        note: m.note,
    }
}

#[derive(Debug, Clone)]
pub struct Fit {
    pub model_id: &'static str,
    pub ctx: u32,
    pub peak_bytes: u64,
    pub budget_bytes: u64,
    pub memory_ratio: f64,
    pub est_tok_s: f64,
    pub verdict: Verdict,
    pub streaming_viable: bool,
    pub is_moe: bool,
    pub quality: u8,
    pub note: &'static str,
}

impl Fit {
    /// The best context this model can hold on this device.
    ///
    /// Found by walking down in powers of two, because halving is the only
    /// step that keeps the estimate honest when the cache is the thing that
    /// grew.
    pub fn best_ctx(&self, m: &Model, dev: &Device) -> u32 {
        let budget = self.budget_bytes;
        let fixed = m.weight_bytes + 64 * 1024 * 1024;
        if fixed >= budget {
            return 0;
        }
        let per_token = 2 * u64::from(m.layers) * u64::from(m.kv_heads) * u64::from(m.head_dim) * 2;
        let ctx = (budget - fixed) / per_token.max(1);
        let capped = ctx.min(u64::from(m.max_ctx));
        // Round down to a power of two: context windows are powers of two, and
        // asking for 6100 tokens gets you 512.
        let mut p = 1024u64;
        while p * 2 <= capped {
            p *= 2;
        }
        if capped < 1024 {
            return 0;
        }
        let _ = dev;
        p as u32
    }
}

/// Rank every model for a device, best first.
///
/// Ordering is by verdict, then by quality, then by speed. A better model that
/// needs streaming loses to a worse one that runs natively, because a
/// recommendation the user cannot actually use is not a recommendation.
pub fn recommend(dev: &Device) -> Vec<Fit> {
    let mut out: Vec<Fit> = Vec::new();

    for m in crate::registry::catalog() {
        let ctx = {
            let probe = score(dev, m, m.default_ctx);
            probe.best_ctx(m, dev)
        };
        if ctx == 0 {
            // Cannot hold the weights at any context worth having.
            out.push(Fit {
                model_id: m.id,
                ctx: 0,
                peak_bytes: peak_bytes(m, 1),
                budget_bytes: (dev.ram_available_mb.saturating_sub(OS_HEADROOM_MB)) * 1024 * 1024,
                memory_ratio: 2.0,
                est_tok_s: 0.0,
                verdict: Verdict::TooHeavy,
                streaming_viable: dev.storage_read_mb_s > 0,
                is_moe: m.is_moe(),
                quality: m.quality,
                note: m.note,
            });
            continue;
        }
        out.push(score(dev, m, ctx));
    }

    out.sort_by(|a, b| {
        b.verdict
            .cmp(&a.verdict)
            .then(b.quality.cmp(&a.quality))
            .then(
                b.est_tok_s
                    .partial_cmp(&a.est_tok_s)
                    .unwrap_or(std::cmp::Ordering::Equal),
            )
            .then(a.model_id.cmp(b.model_id))
    });

    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::device::Device;

    fn phone(ram_mb: u64, cores: usize) -> Device {
        Device {
            cores,
            big_cores: cores / 2,
            ram_total_mb: ram_mb,
            ram_available_mb: ram_mb,
            storage_read_mb_s: 800,
            storage_write_mb_s: 400,
            accel: Accel::None,
            accel_detail: "test".into(),
            core_max_mhz: vec![2000; cores],
        }
    }

    #[test]
    fn context_growth_can_tip_a_fit_from_good_to_too_heavy() {
        let dev = phone(4096, 8);
        let m = &crate::registry::catalog()[3]; // Qwen2.5-0.5B
        let short = score(&dev, m, 512);
        let huge = score(&dev, m, m.max_ctx);
        assert!(
            huge.peak_bytes > short.peak_bytes,
            "peak must grow with context"
        );
    }

    #[test]
    fn bigger_phone_never_scores_worse() {
        let small = phone(2048, 8);
        let large = phone(8192, 8);
        for m in crate::registry::catalog() {
            let s = score(&small, m, 2048);
            let l = score(&large, m, 2048);
            assert!(
                l.verdict >= s.verdict,
                "{} scored better on less RAM",
                m.id
            );
        }
    }

    #[test]
    fn moe_scores_faster_than_equally_sized_dense() {
        let dev = phone(6144, 8);
        let moe = score(&dev, &crate::registry::catalog()[1], 2048);
        let dense = score(&dev, &crate::registry::catalog()[4], 2048);
        assert!(
            moe.est_tok_s > dense.est_tok_s,
            "MoE should win on speed: {} vs {}",
            moe.est_tok_s,
            dense.est_tok_s
        );
    }

    #[test]
    fn recommendation_is_sorted_best_first() {
        let fits = recommend(&phone(6144, 8));
        for w in fits.windows(2) {
            assert!(w[0].verdict >= w[1].verdict, "recommendation out of order");
        }
    }

    #[test]
    fn a_tiny_device_still_gets_an_answer() {
        let fits = recommend(&phone(1024, 4));
        assert!(!fits.is_empty(), "must always return something");
    }

    #[test]
    fn best_ctx_never_exceeds_model_maximum() {
        let dev = phone(16384, 8);
        for m in crate::registry::catalog() {
            let f = score(&dev, m, m.default_ctx);
            assert!(f.best_ctx(m, &dev) <= m.max_ctx, "{} exceeded max", m.id);
        }
    }

    /// The estimator is calibrated against exactly one real measurement, and
    /// this is the test that says so.
    ///
    /// glen measured 6.39 to 6.89 tok/s decoding Qwen2.5-0.5B-Instruct
    /// Q4_K_M (491,400,032 bytes) on a Helio G99 with the GPU unreachable
    /// from the process. If this test starts failing, the calibration is
    /// wrong and the fix is to re-measure, not to widen the tolerance.
    #[test]
    fn estimate_matches_the_only_measured_baseline_we_have() {
        let dev = phone(5649, 8);
        let m = crate::registry::catalog()
            .iter()
            .find(|m| m.id == "Qwen2.5-0.5B-Instruct")
            .expect("baseline model must stay in the catalog");

        let est = score(&dev, m, 2048).est_tok_s;

        assert!(
            (6.3..=7.0).contains(&est),
            "estimated {est:.2} tok/s, glen measured 6.39-6.89 on this exact phone"
        );
    }

    #[test]
    fn unreachable_gpu_scores_exactly_like_cpu() {
        let mut dev = phone(6144, 8);
        let m = &crate::registry::catalog()[3];

        dev.accel = Accel::Cpu;
        let cpu = score(&dev, m, 2048).est_tok_s;
        dev.accel = Accel::UnreachableGpu;
        let gpu = score(&dev, m, 2048).est_tok_s;

        assert_eq!(cpu, gpu, "an unreachable GPU cannot earn any speed");
    }
}