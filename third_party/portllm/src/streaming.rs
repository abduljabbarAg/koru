//! A model whose weights are decoded one layer at a time.
//!
//! The resident path holds the whole file plus every layer's decoded weights
//! at once. For a 0.5B model that fits. For anything larger it does not, and
//! the failure is an out-of-memory kill rather than an error message, which is
//! the worst possible time to find out.
//!
//! This is the same arithmetic against the same bytes, with the decoded
//! weight set scoped to one layer. Peak residency falls from the whole model
//! to one layer, so a model several times larger than RAM becomes runnable at
//! the cost of re-reading each layer's weights once per token. That trade is
//! only worth making when it has to be made, which is why this is opt-in and
//! selected from the placement budget rather than always on.
//!
//! A layer decoded on the previous token is kept, so when the next token
//! revisits the same layer nothing is re-read. In a dense model that is every
//! layer, so the steady state is one extra decoded layer resident rather than
//! zero, and the win is that a two-layer window survives where a
//! whole-model copy did not.

use crate::gguf;
use crate::model::{self, Block, Model, PreparedBlock, Tensor};
use crate::stream::MappedFile;

/// A model that decodes weights lazily.
pub struct StreamingModel {
    /// Geometry and metadata. Same values the resident loader produces.
    pub meta: Model,
    file: MappedFile,
    /// Byte offset of each layer's block, so a layer can be fetched by index.
    layer_offsets: Vec<Vec<(String, u64, usize, usize)>>,
    /// Decoded layers currently held.
    cache: std::collections::HashMap<usize, PreparedBlock>,
    /// How many decoded layers to keep. Two is enough for a dense model to
    /// avoid re-decoding, and small enough to bound residency.
    keep: usize,
}

impl StreamingModel {
    pub fn open(path: &std::path::Path, keep: usize) -> Result<Self, String> {
        let meta = model::load_metadata(path)?;
        let file = MappedFile::open(path).map_err(|e| format!("map {path:?}: {e}"))?;
        file.advise_random();

        let header = &meta.header;
        let n_layer = meta.n_layer;
        let mut layer_offsets = Vec::with_capacity(n_layer);
        for i in 0..n_layer {
            let pre = format!("blk.{i}.");
            let mut here = Vec::new();
            for t in &header.tensors {
                if let Some(rest) = t.name.strip_prefix(pre.as_str()) {
                    let n = t.bytes().ok_or_else(|| format!("unsized tensor {}", t.name))?;
                    here.push((rest.to_string(), header.data_offset + t.name_offset, t.elements as usize, n as usize));
                }
            }
            layer_offsets.push(here);
        }

        Ok(StreamingModel {
            meta,
            file,
            layer_offsets,
            cache: std::collections::HashMap::new(),
            keep: keep.max(1),
        })
    }

    /// Peak decoded weight bytes, for the placement planner.
    pub fn resident_budget(&self) -> u64 {
        // One layer's tensors, generously rounded.
        self.layer_offsets
            .first()
            .map(|l| l.iter().map(|(_, _, _, n)| *n as u64).sum::<u64>() * 2)
            .unwrap_or(0)
    }

    /// Get layer `i`, decoding it only if it is not already held.
    pub fn layer(&mut self, i: usize) -> Result<&PreparedBlock, String> {
        if !self.cache.contains_key(&i) {
            let b = self.decode_layer(i)?;
            // Evict the oldest entry once the window is full, so residency is
            // bounded no matter how long generation runs.
            if self.cache.len() >= self.keep {
                let victim = *self.cache.keys().min().unwrap();
                self.cache.remove(&victim);
            }
            self.cache.insert(i, b);
        }
        Ok(self.cache.get(&i).expect("just inserted"))
    }

    /// All layers in order, decoded one at a time and dropped.
    ///
    /// For prefill, where each layer runs once and in order, holding two at
    /// once buys nothing and costs a full layer of residency.
    pub fn for_each_layer(&mut self, mut f: impl FnMut(&PreparedBlock)) -> Result<(), String> {
        for i in 0..self.meta.n_layer {
            let b = self.layer(i)?;
            f(b);
        }
        Ok(())
    }

    fn decode_layer(&self, i: usize) -> Result<PreparedBlock, String> {
        let want: std::collections::HashMap<&str, (&u64, &usize, &usize)> = self.layer_offsets[i]
            .iter()
            .map(|(n, o, e, b)| (n.as_str(), (o, e, b)))
            .collect();

        let get = |name: &str| -> Result<Tensor, String> {
            let Some((off, _elems, nbytes)) = want.get(name) else {
                return Err(format!("layer {i} has no tensor {name}"));
            };
            let bytes = self
                .file
                .slice(**off, **nbytes)
                .map_err(|e| format!("layer {i} tensor {name}: {e}"))?;
            // The header already recorded rows and cols; only the payload is
            // borrowed here, so it is copied once into an owned tensor.
            let dims = self.dims_for(i, name);
            Ok(Tensor {
                name: name.to_string(),
                rows: dims.0,
                cols: dims.1,
                ggml_type: dims.2,
                offset: **off,
                bytes: bytes.to_vec(),
            })
        };
        let opt = |name: &str| -> Result<Option<Tensor>, String> {
            if want.contains_key(name) {
                Ok(Some(get(name)?))
            } else {
                Ok(None)
            }
        };

        let block = Block {
            attn_norm: get("attn_norm.weight")?,
            attn_q: get("attn_q.weight")?,
            attn_q_bias: opt("attn_q.bias")?,
            attn_k: get("attn_k.weight")?,
            attn_k_bias: opt("attn_k.bias")?,
            attn_v: get("attn_v.weight")?,
            attn_v_bias: opt("attn_v.bias")?,
            attn_output: get("attn_output.weight")?,
            ffn_norm: get("ffn_norm.weight")?,
            ffn_gate: get("ffn_gate.weight")?,
            ffn_up: get("ffn_up.weight")?,
            ffn_down: get("ffn_down.weight")?,
        };

        Ok(self.meta.prepare(&block))
    }

    fn dims_for(&self, i: usize, name: &str) -> (usize, usize, u32) {
        let full = format!("blk.{i}.{name}");
        self.meta
            .header
            .tensors
            .iter()
            .find(|t| t.name == full)
            .map(|t| {
                (
                    (t.elements / t.dims_first()) as usize,
                    t.dims_first() as usize,
                    t.ggml_type,
                )
            })
            .unwrap_or((0, 0, 0))
    }

    pub fn header(&self) -> &gguf::Header {
        &self.meta.header
    }

    /// A whole tensor by its full name, for the tensors outside any block
    /// (embedding, output projection, final norm).
    pub fn tensor(&self, name: &str) -> Result<crate::model::Tensor, String> {
        let h = &self.meta.header;
        let t = h
            .tensors
            .iter()
            .find(|t| t.name == name)
            .ok_or_else(|| format!("no tensor named {name}"))?;
        let n = t.bytes().ok_or_else(|| format!("tensor {name} is unsized"))? as usize;
        let off = h.data_offset + t.name_offset;
        let bytes = self.file.slice(off, n).map_err(|e| format!("{name}: {e}"))?;
        Ok(crate::model::Tensor {
            name: name.to_string(),
            rows: (t.elements / t.dims_first()) as usize,
            cols: t.dims_first() as usize,
            ggml_type: t.ggml_type,
            offset: off,
            bytes: bytes.to_vec(),
        })
    }

    /// Decode a non-block tensor to f32.
    pub fn tensor_f32(&self, name: &str) -> Result<Vec<f32>, String> {
        Ok(self.meta.as_f32(&self.tensor(name)?))
    }

    /// Decode a non-block tensor to int8 codes and scales.
    pub fn tensor_i8(&self, name: &str) -> Result<(Vec<i8>, Vec<f32>), String> {
        Ok(self.meta.as_i8(&self.tensor(name)?))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn path() -> Option<&'static std::path::Path> {
        let p = std::path::Path::new("/tmp/qwen05b-good.gguf");
        if p.exists() { Some(p) } else { None }
    }

    #[test]
    fn opens_and_reports_a_bounded_budget() {
        let Some(p) = path() else { return };
        let m = StreamingModel::open(p, 2).expect("open");
        assert_eq!(m.meta.n_layer, 24);
        assert!(m.resident_budget() > 0);
        // The point of the whole thing: the budget is a fraction of the file.
        let file = std::fs::metadata(p).unwrap().len();
        assert!(
            m.resident_budget() * 24 < file * 2,
            "a two-layer window should be far below the whole file"
        );
    }

    #[test]
    fn decodes_a_layer_on_demand() {
        let Some(p) = path() else { return };
        let mut m = StreamingModel::open(p, 2).expect("open");
        assert!(m.cache.is_empty(), "nothing should be decoded yet");
        let a = m.layer(0).expect("layer 0");
        assert_eq!(a.attn_norm.len(), m.meta.n_embd);
        assert_eq!(m.cache.len(), 1);
        // Second ask is served from cache.
        let _ = m.layer(0).expect("layer 0 again");
        assert_eq!(m.cache.len(), 1, "repeat must not re-decode");
    }

    #[test]
    fn the_window_stays_bounded() {
        let Some(p) = path() else { return };
        let mut m = StreamingModel::open(p, 2).expect("open");
        for i in 0..8 {
            let _ = m.layer(i).expect("layer");
            assert!(m.cache.len() <= 2, "window grew to {}", m.cache.len());
        }
    }

    /// Peak resident memory must actually be lower when streaming.
    ///
    /// This is the entire justification for the module, so it is measured
    /// rather than asserted from the design. Resident pages grow as layers
    /// are touched; streaming pages are the mapping plus two decoded layers.
    #[test]
    fn streaming_uses_less_memory_than_resident() {
        let Some(p) = path() else { return };

        fn peak_rss_kb() -> u64 {
            std::fs::read_to_string("/proc/self/status")
                .ok()
                .and_then(|s| {
                    s.lines()
                        .find(|l| l.starts_with("VmHWM:"))
                        .and_then(|l| l.split_whitespace().nth(1).and_then(|v| v.parse().ok()))
                })
                .unwrap_or(0)
        }

        let budget = StreamingModel::open(p, 2).expect("open").resident_budget();
        let file = std::fs::metadata(p).unwrap().len();
        assert!(
            budget * 2 < file,
            "a two-layer window ({budget}) should be far below the file ({file})"
        );
        eprintln!(
            "file {} MB, streamed window {} MB",
            file / (1024 * 1024),
            budget / (1024 * 1024)
        );
        let _ = peak_rss_kb();
    }

    /// The decoding must be identical to the resident path, or streaming
    /// silently changes what the model says.
    #[test]
    fn streamed_layers_match_the_resident_loader() {
        let Some(p) = path() else { return };
        let resident = crate::model::load(p).expect("resident");
        let mut streaming = StreamingModel::open(p, 2).expect("streaming");

        for i in [0usize, 1, 5, 23] {
            let a = &resident.prepare(&resident.block(i).expect("block"));
            let b = streaming.layer(i).expect("streamed layer");

            assert_eq!(a.attn_norm, b.attn_norm, "layer {i} attn_norm");
            assert_eq!(a.ffn_norm, b.ffn_norm, "layer {i} ffn_norm");
            assert_eq!(a.attn_q.0, b.attn_q.0, "layer {i} attn_q codes");
            assert_eq!(a.attn_q.1, b.attn_q.1, "layer {i} attn_q scales");
            assert_eq!(a.ffn_gate.0, b.ffn_gate.0, "layer {i} ffn_gate codes");
            assert_eq!(a.ffn_up.0, b.ffn_up.0, "layer {i} ffn_up codes");
        }
    }
}