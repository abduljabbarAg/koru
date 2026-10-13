//! PortLLM: a portable LLM engine that sizes itself to the device.
//!
//! The crate is split in two halves that can be used independently.
//!
//! **Decide** — [`device`], [`registry`], [`fit`] and [`placement`] answer
//! "what can this machine run, and how?". They are cheap, allocation-light and
//! have no model-format knowledge, so an application can call them at startup
//! before committing to a download.
//!
//! **Compute** — [`gguf`], [`model`], [`tokenizer`], [`sampling`] and
//! [`streaming`] read a model and produce text.
//!
//! The reason they are separable is that the two halves fail differently. A
//! recommendation that does not fit is a bad recommendation; an engine that
//! cannot fit in memory is a crash. Keeping the fit calculation separate from
//! the loader means an application can refuse a model *before* mapping it.
//!
//! ```no_run
//! use portllm::{device, fit, registry};
//!
//! let d = device::probe();
//! for m in registry::catalog() {
//!     let f = fit::score(&d, m, 2048);
//!     println!("{:<28} {} ({:.0} MB peak)", m.id, f.verdict.label(), f.peak_bytes as f64 / 1e6);
//! }
//! ```

pub mod capi;
pub mod device;
pub mod fast;
pub mod fit;
pub mod gguf;
pub mod json;
pub mod kernel;
pub mod model;
pub mod moe;
pub mod ops;
pub mod placement;
pub mod registry;
pub mod sampling;
pub mod serve;
pub mod stream;
pub mod streaming;
pub mod tokenizer;
pub mod unpack;
pub mod validate;
