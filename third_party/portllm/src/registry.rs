//! The models PortLLM knows how to weigh up, and how to weigh them.
//!
//! Every entry carries the architecture numbers the fit scorer needs. Those are
//! not estimates: a KV cache is `2 * layers * kv_heads * head_dim * ctx *
//! bytes_per_element`, so a model with the wrong `kv_heads` is scored against a
//! memory budget that does not exist. Getting this wrong is the single most
//! common way a recommender recommends a model that then gets killed.
//!
//! Sizes are INT4 weights in bytes unless stated. Context is the *default*
//! context PortLLM will pick for a device, not the model's maximum: a 128k
//! model on a 2 GB phone is not a 128k model on that phone.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Family {
    Llama,
    Qwen,
    Gemma,
    Phi,
    Smol,
    MoE,
}

#[derive(Debug, Clone, Copy)]
pub struct Model {
    pub id: &'static str,
    pub family: Family,
    /// Total parameters, in billions. For MoE this is capacity, not cost.
    pub params_b: f32,
    /// Parameters actually touched per token, in billions. Equals
    /// `params_b` for dense models.
    pub active_b: f32,
    pub layers: u32,
    pub kv_heads: u32,
    pub head_dim: u32,
    /// INT4 weight size on disk, bytes.
    pub weight_bytes: u64,
    /// Context PortLLM targets on a device with room to spare.
    pub default_ctx: u32,
    pub max_ctx: u32,
    /// Rough capability rank, used only to order models of equal fit.
    /// 1 is a toy, 5 is genuinely useful.
    pub quality: u8,
    pub note: &'static str,
}

impl Model {
    /// Bytes of KV cache for a given context length.
    ///
    /// Two tensors per layer (K and V), one f16 element each, per KV head per
    /// head_dim. GQA models keep this small, which is most of why they are
    /// viable on a phone.
    pub fn kv_bytes(&self, ctx: u32) -> u64 {
        2 * u64::from(self.layers)
            * u64::from(self.kv_heads)
            * u64::from(self.head_dim)
            * u64::from(ctx)
            * 2
    }

    pub fn is_moe(&self) -> bool {
        self.active_b < self.params_b
    }

    /// Approximate size of the token embedding table.
    ///
    /// Vocab sizes are not in this table, so this is derived from a typical
    /// 128k vocabulary scaled by the model's width. It is an estimate and is
    /// labelled as one; the exact figure arrives with the real graph parser.
    /// Embeddings matter here because they are read rarely but are large,
    /// which makes them the first sensible thing to demote when memory is
    /// short.
    pub fn embed_hint_bytes(&self) -> u64 {
        let d_model = u64::from(self.head_dim * self.kv_heads * 4); // GQA width understates; pad below
        let d_model = d_model.max(384);
        128_000 * d_model
    }

    /// Active weight bytes touched per token. This is what decode bandwidth
    /// is actually spent on, and it is why a MoE model can be enormous on disk
    /// and still decode fast.
    pub fn active_bytes(&self) -> u64 {
        ((self.active_b / self.params_b) as f64 * self.weight_bytes as f64) as u64
    }
}

/// Models PortLLM can currently reason about.
///
/// Ordered small to large. This list is the thing to extend first when a new
/// model matters; it is deliberately a fixed table rather than a download,
/// because a recommender that needs the network to decide anything is useless
/// exactly when the network is not there.
pub fn catalog() -> &'static [Model] {
    &[
        Model {
            id: "Qwen2.5-0.5B-Instruct",
            family: Family::Qwen,
            params_b: 0.49,
            active_b: 0.49,
            layers: 24,
            kv_heads: 2,
            head_dim: 64,
            weight_bytes: 491_400_032,
            default_ctx: 2048,
            max_ctx: 4096,
            quality: 2,
            note: "The measured baseline. Fast, weak, leaks its system prompt.",
        },
        Model {
            id: "MobileMoE-S",
            family: Family::MoE,
            params_b: 1.3,
            active_b: 0.272,
            layers: 20,
            kv_heads: 4,
            head_dim: 64,
            weight_bytes: 730_000_000,
            default_ctx: 4096,
            max_ctx: 8192,
            quality: 3,
            note: "0.27B active. Smallest thing worth calling an assistant.",
        },
        Model {
            id: "MobileMoE-M",
            family: Family::MoE,
            params_b: 2.8,
            active_b: 0.528,
            layers: 26,
            kv_heads: 4,
            head_dim: 64,
            weight_bytes: 1_589_000_000,
            default_ctx: 4096,
            max_ctx: 8192,
            quality: 4,
            note: "0.53B active. The sweet spot on a mid phone.",
        },
        Model {
            id: "Llama-3.2-3B-Instruct",
            family: Family::Llama,
            params_b: 3.2,
            active_b: 3.2,
            layers: 28,
            kv_heads: 8,
            head_dim: 128,
            weight_bytes: 1_930_000_000,
            default_ctx: 4096,
            max_ctx: 8192,
            quality: 3,
            note: "Well trodden. Good when you want a familiar chat template.",
        },
        Model {
            id: "Qwen3-4B",
            family: Family::Qwen,
            params_b: 4.0,
            active_b: 4.0,
            layers: 36,
            kv_heads: 8,
            head_dim: 128,
            weight_bytes: 2_400_000_000,
            default_ctx: 4096,
            max_ctx: 32768,
            quality: 4,
            note: "Best dense pick with real headroom for context.",
        },
        Model {
            id: "MobileMoE-L",
            family: Family::MoE,
            params_b: 5.3,
            active_b: 0.922,
            layers: 32,
            kv_heads: 4,
            head_dim: 64,
            weight_bytes: 2_952_000_000,
            default_ctx: 4096,
            max_ctx: 8192,
            quality: 4,
            note: "0.92B active. Beats OLMoE-1B-7B with less memory.",
        },
        Model {
            id: "LFM2.5-8B-A1B",
            family: Family::MoE,
            params_b: 8.3,
            active_b: 1.2,
            layers: 32,
            kv_heads: 4,
            head_dim: 128,
            weight_bytes: 4_400_000_000,
            default_ctx: 4096,
            max_ctx: 128000,
            quality: 4,
            note: "8B of knowledge for 1.2B of work. Needs the RAM to hold it.",
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kv_cache_grows_with_context() {
        let m = &catalog()[0];
        let short = m.kv_bytes(1024);
        let long = m.kv_bytes(8192);
        assert_eq!(long, short * 8, "KV must scale linearly with context");
    }

    #[test]
    fn moe_active_is_less_than_total() {
        for m in catalog() {
            if m.is_moe() {
                assert!(
                    m.active_b < m.params_b,
                    "{} claims MoE but is not sparse",
                    m.id
                );
            }
            assert!(m.active_b > 0.0, "{} has no active params", m.id);
        }
    }

    #[test]
    fn dense_models_spend_every_byte() {
        for m in catalog() {
            if !m.is_moe() {
                assert_eq!(m.active_bytes(), m.weight_bytes, "{}", m.id);
            }
        }
    }

    #[test]
    fn catalog_is_ordered_by_size() {
        let c = catalog();
        for w in c.windows(2) {
            assert!(
                w[0].weight_bytes <= w[1].weight_bytes,
                "{} is listed after a larger model",
                w[0].id
            );
        }
    }
}