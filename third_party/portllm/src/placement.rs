//! One pool, many engines.
//!
//! The idea here is that RAM, GPU and storage are not three separate problems
//! to solve. On Android they are already one physical pool: Qualcomm's own
//! documentation says CPU and GPU allocations coexist in the same memory
//! space, and that a GPU allocation can starve the CPU. So there is nothing to
//! virtualise. What is missing is a policy for deciding what stays resident.
//!
//! The correction that shaped this file: low memory does not mean "use more
//! engines". GPU memory is the same DRAM, so on a starved device the GPU is
//! starved too, and adding parallelism makes it slower. Low memory means
//! keeping a smaller hot set and streaming the rest. glen has the receipts:
//! dropping the unpack cache took decode from 4.03 to 3.07 to 1.33 tok/s.
//!
//! What this models is therefore placement, not copying. A tier says where a
//! region lives. The engine asks for a region and gets a handle regardless of
//! which tier served it.

use crate::device::{Accel, Device};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tier {
    /// Resident in DRAM. Fastest, and the only tier that competes for RAM.
    Ram,
    /// Resident in accelerator-accessible DRAM. Same bytes, different engine.
    Gpu,
    /// Paged in on demand from flash.
    Storage,
}

impl Tier {
    pub fn label(self) -> &'static str {
        match self {
            Tier::Ram => "ram",
            Tier::Gpu => "gpu",
            Tier::Storage => "storage",
        }
    }
}

/// A block of model bytes, and where it currently lives.
#[derive(Debug, Clone)]
pub struct Region {
    pub name: String,
    pub bytes: u64,
    pub tier: Tier,
    /// How many times per generated token this region is read. The single
    /// most important number for placement: a region read every token belongs
    /// in RAM, and one read once per prompt can be streamed.
    pub reads_per_token: f32,
}

impl Region {
    pub fn new(name: &str, bytes: u64, reads_per_token: f32) -> Self {
        Region {
            name: name.to_string(),
            bytes,
            tier: Tier::Ram,
            reads_per_token,
        }
    }

    /// Time to serve one token, in seconds, given the device's tier bandwidths.
    ///
    /// Deliberately simple: bytes over bandwidth, scaled by read frequency.
    /// It is wrong in the details and right in the ordering, which is all a
    /// placement policy needs to be useful.
    pub fn cost_per_token(&self, tiers: &TierSpeeds) -> f64 {
        let gbs = tiers.of(self.tier);
        if gbs <= 0.0 {
            return f64::INFINITY;
        }
        (self.bytes as f64 * self.reads_per_token as f64) / (gbs * 1e9)
    }
}

/// Per-tier bandwidth in GB/s.
#[derive(Debug, Clone, Copy)]
pub struct TierSpeeds {
    pub ram: f64,
    pub gpu: f64,
    pub storage: f64,
}

impl TierSpeeds {
    pub fn of(&self, t: Tier) -> f64 {
        match t {
            Tier::Ram => self.ram,
            // An unreachable GPU is exactly as fast as nothing at all. This is
            // the whole point of probing reachability rather than assuming.
            Tier::Gpu => self.gpu,
            Tier::Storage => self.storage,
        }
    }

    /// Derive tier speeds from a measured device.
    ///
    /// GPU bandwidth is only real if the GPU is reachable, and on Android it
    /// often is not from inside the app sandbox. A GPU number derived from a
    /// device that cannot dispatch to it would send every region to a tier
    /// that does not exist.
    pub fn from_device(d: &Device) -> Self {
        let ram = 3.2; // calibrated to glen on this phone
        let gpu = match d.accel {
            Accel::ReachableGpu => 6.0, // TODO: measure on real hardware
            Accel::Npu => 8.0,          // TODO: measure
            // Present but unreachable, or absent: there is no GPU tier. Zero is
            // the honest value, because any positive number here gets used.
            Accel::UnreachableGpu | Accel::None | Accel::Cpu => 0.0,
        };
        let storage = d.storage_read_mb_s as f64 / 1024.0;
        TierSpeeds {
            ram,
            gpu,
            storage,
        }
    }
}

/// Where a region *should* live, given what the device can afford.
///
/// This is the policy the whole project is built around, and it is deliberately
/// conservative. The tempting optimisation is to move hot regions to the GPU
/// because it is nominally faster. The measured result on real hardware is
/// that naive offloading loses: GPU and NPU synchronisation costs around 400
/// microseconds, which is comparable to a whole kernel, so a region moved to
/// save bandwidth can arrive slower than it left.
pub struct Placement {
    pub regions: Vec<Region>,
    pub resident_bytes: u64,
    pub budget_bytes: u64,
    pub streamed_bytes: u64,
}

impl Placement {
    /// Decide residency for a set of regions.
    ///
    /// The rule is not "put the fastest tier everywhere". It is: keep what is
    /// read often, stream what is not, and never promise a GPU this device
    /// cannot reach.
    pub fn plan(d: &Device, mut regions: Vec<Region>) -> Self {
        let speeds = TierSpeeds::from_device(d);
        let budget = (d.ram_available_mb.saturating_sub(320)) * 1024 * 1024;

        // Hotter regions first, so when the budget runs out it runs out on the
        // coldest things. This single ordering decision is the policy.
        regions.sort_by(|a, b| {
            b.reads_per_token
                .partial_cmp(&a.reads_per_token)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then(b.bytes.cmp(&a.bytes))
        });

        let mut used = 0u64;
        let mut streamed = 0u64;

        for r in regions.iter_mut() {
            // Never place on a GPU tier the probe says we cannot dispatch to.
            // Without this the planner will happily build a beautiful schedule
            // for hardware that does not exist.
            if speeds.gpu <= 0.0 {
                r.tier = Tier::Ram;
            }

            if used.saturating_add(r.bytes) <= budget {
                used += r.bytes;
            } else {
                // Does not fit. Stream it, but only if streaming is genuinely
                // viable; otherwise leave it in RAM and let the caller know the
                // plan does not work rather than silently promising a crawl.
                if speeds.storage > 0.0 {
                    r.tier = Tier::Storage;
                    streamed += r.bytes;
                } else {
                    r.tier = Tier::Ram;
                    used += r.bytes;
                }
            }
        }

        Placement {
            regions,
            resident_bytes: used,
            budget_bytes: budget,
            streamed_bytes: streamed,
        }
    }

    /// Projected milliseconds per token across every region.
    pub fn est_ms_per_token(&self, d: &Device) -> f64 {
        let speeds = TierSpeeds::from_device(d);
        self.regions
            .iter()
            .map(|r| r.cost_per_token(&speeds))
            .sum::<f64>()
            * 1000.0
    }

    /// The obvious next question, and the one the engine will actually ask:
    /// which regions are on the critical path, and which were demoted.
    pub fn streamed(&self) -> Vec<&Region> {
        self.regions
            .iter()
            .filter(|r| r.tier == Tier::Storage)
            .collect()
    }
}

/// Split a model into the regions a forward pass actually touches.
///
/// The split matters because the regions do not have equal access patterns.
/// Attention weights are read once per token, the KV cache grows with context,
/// and the embedding table is read once at the start. Placing them identically
/// wastes the one lever we have.
pub fn regions_for(model: &crate::registry::Model, ctx: u32) -> Vec<Region> {
    let w = model.weight_bytes;
    let kv = model.kv_bytes(ctx);

    // A rough and explicitly labelled split of the weight bytes. The exact
    // proportions come with the real graph parser; what matters now is that
    // the planner sees regions with genuinely different read frequencies.
    let attention = w / 5;
    let mlp = w - attention - model.embed_hint_bytes();
    let embed = model.embed_hint_bytes();

    vec![
        Region::new("attention", attention, 1.0),
        Region::new("mlp", mlp, 1.0),
        Region::new("embed", embed, 0.05),
        Region::new("kv_cache", kv, 1.0),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::device::Device;

    fn dev(ram_mb: u64, accel: Accel, storage_mb_s: u64) -> Device {
        Device {
            cores: 8,
            big_cores: 2,
            ram_total_mb: ram_mb,
            ram_available_mb: ram_mb,
            storage_read_mb_s: storage_mb_s,
            storage_write_mb_s: storage_mb_s / 2,
            accel,
            accel_detail: "test".into(),
            core_max_mhz: vec![2000; 8],
        }
    }

    #[test]
    fn unreachable_gpu_never_becomes_a_tier() {
        let d = dev(6144, Accel::UnreachableGpu, 800);
        let speeds = TierSpeeds::from_device(&d);
        assert_eq!(speeds.gpu, 0.0, "unreachable GPU must have zero speed");
    }

    #[test]
    fn planner_never_places_on_an_unreachable_gpu() {
        let d = dev(6144, Accel::UnreachableGpu, 800);
        let p = Placement::plan(&d, vec![Region::new("w", 1 << 20, 1.0)]);
        assert!(p.regions.iter().all(|r| r.tier != Tier::Gpu));
    }

    #[test]
    fn plentiful_ram_streams_nothing() {
        let d = dev(16384, Accel::Cpu, 800);
        let p = Placement::plan(
            &d,
            vec![Region::new("w", 500 << 20, 1.0), Region::new("e", 10 << 20, 0.05)],
        );
        assert!(p.streamed().is_empty(), "should have fit everything");
        assert_eq!(p.resident_bytes, 510 << 20);
    }

    #[test]
    fn scarce_ram_streams_the_coldest_region_first() {
        let d = dev(1024, Accel::Cpu, 800);
        let hot = Region::new("hot", 600 << 20, 1.0);
        let cold = Region::new("cold", 600 << 20, 0.01);
        let p = Placement::plan(&d, vec![hot, cold]);

        assert!(p.streamed().len() >= 1, "something must be streamed");
        let streamed = p.streamed()[0];
        assert_eq!(
            streamed.name, "cold",
            "the least-read region must be the one demoted"
        );
    }

    #[test]
    fn resident_total_never_exceeds_budget() {
        for ram in [512u64, 1024, 2048, 4096, 8192] {
            let d = dev(ram, Accel::Cpu, 800);
            let p = Placement::plan(
                &d,
                vec![
                    Region::new("a", 300 << 20, 1.0),
                    Region::new("b", 300 << 20, 1.0),
                    Region::new("c", 300 << 20, 0.5),
                ],
            );
            assert!(
                p.resident_bytes <= p.budget_bytes,
                "ram {ram}: resident {} exceeded budget {}",
                p.resident_bytes,
                p.budget_bytes
            );
        }
    }

    #[test]
    fn streaming_costs_more_per_token_than_ram() {
        let d = dev(6144, Accel::Cpu, 800);
        let speeds = TierSpeeds::from_device(&d);
        let mut r = Region::new("w", 100 << 20, 1.0);

        r.tier = Tier::Ram;
        let fast = r.cost_per_token(&speeds);
        r.tier = Tier::Storage;
        let slow = r.cost_per_token(&speeds);

        assert!(slow > fast, "streaming must be slower: {slow} vs {fast}");
    }

    #[test]
    fn a_region_on_a_dead_tier_costs_infinity() {
        let d = dev(6144, Accel::UnreachableGpu, 800);
        let speeds = TierSpeeds::from_device(&d);
        let mut r = Region::new("w", 1 << 20, 1.0);
        r.tier = Tier::Gpu;
        assert!(r.cost_per_token(&speeds).is_infinite());
    }

    #[test]
    fn regions_cover_the_whole_model() {
        let m = &crate::registry::catalog()[1];
        let ctx = m.default_ctx;
        let rs = regions_for(m, ctx);
        let total: u64 = rs.iter().map(|r| r.bytes).sum();
        assert_eq!(
            total,
            m.weight_bytes + m.kv_bytes(ctx),
            "regions must account for every byte"
        );
    }

    /// The low-memory path, end to end, on a real model's region set.
    ///
    /// This is the case the project exists for. On a device with enough room
    /// the plan keeps everything in RAM and streaming never appears; squeeze
    /// the budget until it cannot, and the coldest region must demote rather
    /// than the plan simply failing or overcommitting.
    #[test]
    fn a_squeezed_device_streams_instead_of_overcommitting() {
        let m = &crate::registry::catalog()[0]; // Qwen2.5-0.5B, the measured one
        let regions = regions_for(m, m.default_ctx);

        // Roomy: everything resident.
        let roomy = Placement::plan(&dev(6144, Accel::Cpu, 800), regions.clone());
        assert!(roomy.streamed().is_empty(), "roomy device should not stream");

        // Squeezed to just under the model's own footprint.
        let squeezed = Placement::plan(&dev(700, Accel::Cpu, 800), regions);
        assert!(
            squeezed.resident_bytes <= squeezed.budget_bytes,
            "must not overcommit: {} > {}",
            squeezed.resident_bytes,
            squeezed.budget_bytes
        );
        assert!(
            !squeezed.streamed().is_empty(),
            "a squeezed device must demote something"
        );
        // The embedding table is read rarely, so it is the first thing to go.
        assert!(
            squeezed.streamed().iter().any(|r| r.name == "embed"),
            "expected the cold embedding table to be demoted first"
        );
    }

    /// Streaming has to actually be viable on the device, or the planner is
    /// making a promise storage cannot keep.
    #[test]
    fn streaming_requires_measurable_storage() {
        let m = &crate::registry::catalog()[0];
        let regions = regions_for(m, m.default_ctx);

        // No writable scratch, so storage bandwidth reads as zero.
        let blind = Placement::plan(&dev(700, Accel::Cpu, 0), regions.clone());
        assert!(
            blind.streamed().is_empty(),
            "with no storage to stream from, nothing may be demoted"
        );

        // Real storage, and the demotion happens.
        let sighted = Placement::plan(&dev(700, Accel::Cpu, 800), regions);
        assert!(!sighted.streamed().is_empty());
    }
}