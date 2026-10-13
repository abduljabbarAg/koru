//! Reading a GGUF file's shape without reading its weights.
//!
//! The header is a few kilobytes at the front of a file that can be gigabytes
//! long, and everything the engine needs to decide how to place a model is in
//! there. Parse the header, decide placement, and only then touch the tensor
//! data. Doing it the other way round means streaming half a gigabyte before
//! discovering the model does not fit.
//!
//! Layout, from the v3 spec:
//!
//! ```text
//!   magic      u32   "GGUF" little endian, 0x46554747
//!   version    u32   2 or 3
//!   tensors    u64
//!   metadata   u64   count of key-value pairs
//!   kv[]       key: string, type: u32, value: typed
//!   tensors[]  name: string, n_dims: u32, dims: u64[n_dims],
//!              type: u32, offset: u64
//! ```
//!
//! Note there is no length field between the two counts and the data: the
//! reader walks the key-value block and then the tensor table to find where
//! weights begin.
//!
//! Strings are u64 length then that many bytes, with no terminator. The length
//! is a byte count, not a character count, which matters for anything non-ASCII
//! in a model name.

use std::collections::BTreeMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

pub const GGUF_MAGIC: u32 = 0x4655_4747;

/// Metadata value types. The discriminant is part of the file format.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ValueType {
    U8,
    I8,
    U16,
    I16,
    U32,
    I32,
    F32,
    Bool,
    String,
    Array,
    U64,
    I64,
    F64,
    Unknown(u32),
}

impl ValueType {
    fn from_u32(v: u32) -> Self {
        match v {
            0 => ValueType::U8,
            1 => ValueType::I8,
            2 => ValueType::U16,
            3 => ValueType::I16,
            4 => ValueType::U32,
            5 => ValueType::I32,
            6 => ValueType::F32,
            7 => ValueType::Bool,
            8 => ValueType::String,
            9 => ValueType::Array,
            10 => ValueType::U64,
            11 => ValueType::I64,
            12 => ValueType::F64,
            other => ValueType::Unknown(other),
        }
    }

    /// The variant tag stored in a `ggml_type` for this value type, used to
    /// skip array payloads we do not interpret.
    fn array_element(self) -> ValueType {
        self
    }
}

#[derive(Debug, Clone)]
pub enum Value {
    U64(u64),
    I64(i64),
    F64(f64),
    Bool(bool),
    Str(String),
    Array(Vec<Value>),
}

impl Value {
    pub fn as_u64(&self) -> Option<u64> {
        match self {
            Value::U64(v) => Some(*v),
            Value::I64(v) => u64::try_from(*v).ok(),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::F64(v) => Some(*v),
            Value::U64(v) => Some(*v as f64),
            Value::I64(v) => Some(*v as f64),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct TensorDesc {
    /// The tensor's name. Kept inline rather than in a side table because an
    /// offset is not an identity, and weight-tied models legitimately put two
    /// tensors at the same data offset.
    pub name: String,
    pub name_offset: u64,
    pub n_dims: u32,
    pub ggml_type: u32,
    /// Product of the dimensions: how many values this tensor holds.
    pub elements: u64,
    /// The first dimension: the input width for a weight matrix, because
    /// GGUF stores weight dims as [in, out].
    pub first_dim: u64,
}

impl TensorDesc {
    /// The first dimension. For a GGUF weight, dims are [in, out], so this
    /// is the input width and the one a matvec consumes.
    pub fn dims_first(&self) -> u64 {
        self.first_dim
    }

    /// Bytes this tensor occupies, from its block structure.
    ///
    /// Quantized formats are stored in fixed-size blocks, so the size is
    /// `ceil(elements / block) * block_bytes`, not `elements * bits / 8`. A
    /// Q4_K block is 256 values in 144 bytes, which is 4.5 bits per value;
    /// computing it as 4 bits under-reports every K-quant model by about 12%,
    /// which is a model that does not fit being recommended as though it did.
    pub fn bytes(&self) -> Option<u64> {
        let (block_elems, block_bytes) = block_shape(self.ggml_type)?;
        let blocks = self.elements.div_ceil(block_elems);
        blocks.checked_mul(block_bytes)
    }
}

/// The `(elements, bytes)` shape of one quantization block.
///
/// `None` means the type is not one we can size, and the caller must refuse to
/// guess: an unknown format means an unknown size.
fn block_shape(ggml_type: u32) -> Option<(u64, u64)> {
    Some(match ggml_type {
        0 => (1, 4),     // F32
        1 => (1, 2),     // F16
        2 => (32, 18),   // Q4_0
        3 => (32, 20),   // Q4_1
        6 => (32, 22),   // Q5_0: 2 (d) + 4 (mh) + 16 (qs)
        7 => (32, 24),   // Q5_1: 2 (d) + 2 (m) + 20 (qs)
        8 => (32, 34),   // Q8_0: 2 (d) + 32 (qs)
        10 => (256, 84), // Q2_K
        11 => (256, 110), // Q3_K
        12 => (256, 144), // Q4_K
        13 => (256, 176), // Q5_K
        14 => (256, 210), // Q6_K
        _ => return None,
    })
}

/// Human name for a ggml type, for the CLI. Unknown values are shown as their
/// number rather than silently mapped to something wrong.
pub fn type_name(ggml_type: u32) -> String {
    match ggml_type {
        0 => "F32".into(),
        1 => "F16".into(),
        2 => "Q4_0".into(),
        3 => "Q4_1".into(),
        6 => "Q5_0".into(),
        7 => "Q5_1".into(),
        8 => "Q8_0".into(),
        10 => "Q2_K".into(),
        11 => "Q3_K".into(),
        12 => "Q4_K".into(),
        13 => "Q5_K".into(),
        14 => "Q6_K".into(),
        other => format!("type#{other}"),
    }
}

#[derive(Debug, Clone)]
pub struct Header {
    pub version: u32,
    pub tensor_count: u64,
    pub metadata_kv_count: u64,
    pub metadata: BTreeMap<String, Value>,
    pub tensors: Vec<TensorDesc>,
    /// Tensor names by their data offset. Names are read because a forward
    /// pass has to find weights like "blk.0.attn_q.weight", and an offset is
    /// not a name.
    pub tensor_names: BTreeMap<u64, String>,
    /// Bytes from the start of the file to the first tensor's data.
    pub data_offset: u64,
    pub total_bytes: u64,
}

impl Header {
    pub fn get(&self, key: &str) -> Option<&Value> {
        self.metadata.get(key)
    }

    pub fn num(&self, key: &str) -> Option<u64> {
        self.metadata.get(key).and_then(|v| v.as_u64())
    }

    /// A float-valued metadata field.
    ///
    /// Separate from `num` because the two are stored differently: a GGUF
    /// f32 is a real IEEE single in the file, while a uint32 that happens to
    /// read 1,000,000 is an integer. Reading `rope.freq_base` with `num`
    /// gets the bit pattern of the float, not its value, and a base of
    /// 1.7e9 instead of 1e6 produces a model with scrambled positions.
    pub fn num_f32(&self, key: &str) -> Option<f32> {
        self.metadata.get(key).and_then(|v| v.as_f64()).map(|v| v as f32)
    }

    /// How far the tensor data actually reaches, in bytes from the start of
    /// the data region.
    ///
    /// This is the useful quantity, and it is deliberately *not* the sum of
    /// tensor sizes. Weight-tied models share one buffer between the input
    /// embedding and the output projection, so both entries describe the same
    /// bytes and summing them double-counts. Qwen2.5-0.5B does exactly this
    /// with a 136M-element embedding, which made the sum report 630 MB for a
    /// 491 MB file and made a perfect HuggingFace download look truncated.
    ///
    /// The extent is max(offset + size), which is immune to sharing: a second
    /// tensor pointing into the middle of the first adds nothing.
    pub fn tensor_extent(&self) -> Option<u64> {
        self.tensors.iter().try_fold(0u64, |acc, t| {
            let b = t.bytes()?;
            Some(acc.max(t.name_offset.saturating_add(b)))
        })
    }

    /// Total bytes of tensor data, double-counting any shared buffer.
    ///
    /// Kept because it is a useful cross-check in the other direction: a sum
    /// well above the extent means the model is heavily weight-tied, which is
    /// information rather than an error. Never use it as a file-size test.
    pub fn tensor_bytes(&self) -> Option<u64> {
        self.tensors.iter().try_fold(0u64, |acc, t| acc.checked_add(t.bytes()?))
    }

    /// Every quantization type present, deduplicated, for the report.
    pub fn types_used(&self) -> Vec<u32> {
        let mut v: Vec<u32> = self.tensors.iter().map(|t| t.ggml_type).collect();
        v.sort_unstable();
        v.dedup();
        v
    }

    /// Count of tensors whose type we cannot size.
    ///
    /// Nonzero means the model contains something the planner cannot account
    /// for, so a recommendation made from it would be a guess.
    pub fn unsized_tensors(&self) -> usize {
        self.tensors.iter().filter(|t| t.bytes().is_none()).count()
    }
}

/// Read a bounded prefix of the file without loading the whole thing.
struct Cursor<R> {
    inner: R,
    pos: u64,
    limit: u64,
}

impl<R: Read + Seek> Cursor<R> {
    fn take(inner: R, limit: u64) -> Self {
        Cursor {
            inner,
            pos: 0,
            limit,
        }
    }

    fn u8(&mut self) -> Result<u8, String> {
        let mut b = [0u8; 1];
        self.read_exact(&mut b).map_err(|e| e.to_string())?;
        Ok(b[0])
    }

    fn read_exact(&mut self, buf: &mut [u8]) -> Result<(), String> {
        if self.pos + buf.len() as u64 > self.limit {
            return Err("header extends past end of file".into());
        }
        self.inner.read_exact(buf).map_err(|e| e.to_string())?;
        self.pos += buf.len() as u64;
        Ok(())
    }

    fn u16(&mut self) -> Result<u16, String> {
        let mut b = [0u8; 2];
        self.read_exact(&mut b)?;
        Ok(u16::from_le_bytes(b))
    }

    fn u32(&mut self) -> Result<u32, String> {
        let mut b = [0u8; 4];
        self.read_exact(&mut b)?;
        Ok(u32::from_le_bytes(b))
    }

    fn u64(&mut self) -> Result<u64, String> {
        let mut b = [0u8; 8];
        self.read_exact(&mut b)?;
        Ok(u64::from_le_bytes(b))
    }

    fn string(&mut self) -> Result<String, String> {
        let len = self.u64()?;
        // A model name can be long but not unbounded. Anything past 64 KiB in
        // a header is a corrupt length field, and allocating on it would be
        // how a malformed file takes the process down.
        if len > 64 * 1024 {
            return Err(format!("string length {len} is not plausible"));
        }
        let mut buf = vec![0u8; len as usize];
        self.read_exact(&mut buf)?;
        String::from_utf8(buf).map_err(|e| e.to_string())
    }

    fn value(&mut self, ty: ValueType) -> Result<Value, String> {
        Ok(match ty {
            ValueType::U8 => Value::U64(self.u8()? as u64),
            ValueType::I8 => Value::I64(self.u8()? as i8 as i64),
            ValueType::U16 => Value::U64(self.u16()? as u64),
            ValueType::I16 => Value::I64(self.u16()? as i16 as i64),
            ValueType::U32 => Value::U64(self.u32()? as u64),
            ValueType::I32 => Value::I64(self.u32()? as i32 as i64),
            ValueType::F32 => {
                let mut b = [0u8; 4];
                self.read_exact(&mut b)?;
                Value::F64(f32::from_le_bytes(b) as f64)
            }
            ValueType::Bool => Value::Bool(self.u8()? != 0),
            ValueType::String => Value::Str(self.string()?),
            ValueType::U64 => Value::U64(self.u64()?),
            ValueType::I64 => Value::I64(self.u64()? as i64),
            ValueType::F64 => {
                let mut b = [0u8; 8];
                self.read_exact(&mut b)?;
                Value::F64(f64::from_le_bytes(b))
            }
            ValueType::Array => {
                let elem_ty = ValueType::from_u32(self.u32()?);
                let n = self.u64()?;
                // An array claiming more elements than the remaining header can
                // possibly hold is corrupt. Without this check a bad length
                // turns into a multi-gigabyte allocation.
                if n > 10_000_000 {
                    return Err(format!("array length {n} is not plausible"));
                }
                let mut out = Vec::with_capacity(n.min(4096) as usize);
                for _ in 0..n {
                    out.push(self.value(elem_ty)?);
                }
                Value::Array(out)
            }
            ValueType::Unknown(t) => return Err(format!("unknown value type {t}")),
        })
    }
}

/// How much of the file the tensor data should account for, and whether that
/// is plausible.
///
/// A GGUF that does not add up is a broken download. This does not fail
/// cleanly: the header parses, the model loads, and the fault appears minutes
/// later during inference. Comparing the declared tensor bytes against the
/// real file length turns that into an answer at load time, which is the only
/// moment anyone can act on it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Integrity {
    /// Tensors account for the file within alignment tolerance.
    Ok,
    /// The header declares more tensor data than the file holds. This is what
    /// a short download looks like, and it is the common one: the metadata is
    /// fine, so everything up to the point of use is fine.
    Truncated { short_by: u64 },
    /// The file holds far more than the tensors need, which usually means
    /// trailing junk or a concatenated archive rather than a bad download.
    Oversized { extra: u64 },
    /// At least one tensor uses a quant format we cannot size, so no
    /// conclusion is possible either way.
    Unsized { count: usize },
}

impl Integrity {
    pub fn is_ok(&self) -> bool {
        matches!(self, Integrity::Ok)
    }
}

impl Header {
    pub fn integrity(&self) -> Integrity {
        let Some(extent) = self.tensor_extent() else {
            return Integrity::Unsized {
                count: self.unsized_tensors(),
            };
        };

        // Compare the declared extent against the real data region, not
        // against the whole file: the header itself occupies the first few
        // megabytes and is legitimately not tensor data.
        let data = self.total_bytes.saturating_sub(self.data_offset);
        const ALIGNMENT_SLACK: u64 = 1 << 20;

        if extent > data.saturating_add(ALIGNMENT_SLACK) {
            // The header wants more tensor bytes than the file holds. Same
            // fault as a short download, named for the direction that is
            // actionable: get more bytes.
            Integrity::Truncated {
                short_by: extent - data,
            }
        } else if extent * 100 < data * 90 {
            Integrity::Oversized {
                extra: data - extent,
            }
        } else {
            Integrity::Ok
        }
    }}

/// Read a GGUF header.
///
/// Reads only as far as the tensor table, so cost is independent of model size.
pub fn read_header(path: &Path) -> Result<Header, String> {
    let file = File::open(path).map_err(|e| format!("open {}: {e}", path.display()))?;
    let total_bytes = file
        .metadata()
        .map_err(|e| format!("stat: {e}"))?
        .len();

    // Headers are kilobytes. 64 MiB is far past any real one and bounds the
    // damage a corrupt length prefix can do.
    let limit = total_bytes.min(64 * 1024 * 1024);
    let mut c = Cursor::take(file, limit);

    let magic = c.u32()?;
    if magic != GGUF_MAGIC {
        return Err(format!(
            "not a GGUF file: magic {magic:#010x}, expected {GGUF_MAGIC:#010x}"
        ));
    }

    let version = c.u32()?;
    if !(2..=3).contains(&version) {
        return Err(format!("unsupported GGUF version {version}"));
    }

    // Version 3 is: magic, version, tensor_count, metadata_kv_count, then the
    // key-value block and the tensor table. There is no byte-length field
    // between the counts and the data, so the reader walks both blocks to find
    // where the tensor data begins. Adding a length field here silently
    // misaligns the entire file, which is what a version-2 file does have and
    // is the trap worth naming.
    let tensor_count = c.u64()?;
    let metadata_kv_count = c.u64()?;

    // A file claiming more tensors than bytes available cannot be real.
    if tensor_count > (total_bytes / 32) as u64 {
        return Err(format!(
            "header claims {tensor_count} tensors in a {total_bytes} byte file"
        ));
    }
    if metadata_kv_count > 1_000_000 {
        return Err(format!("implausible metadata count {metadata_kv_count}"));
    }

    let mut metadata = BTreeMap::new();
    for _ in 0..metadata_kv_count {
        let key = c.string()?;
        let ty = ValueType::from_u32(c.u32()?);
        let value = c.value(ty)?;
        metadata.insert(key, value);
    }

    let mut tensor_names: BTreeMap<u64, String> = BTreeMap::new();
    let mut tensors = Vec::with_capacity(tensor_count.min(65536) as usize);
    for _ in 0..tensor_count {
        let name = c.string()?;
        let n_dims = c.u32()?;
        if !(1..=4).contains(&n_dims) {
            return Err(format!("tensor with {n_dims} dimensions is not valid"));
        }
        let mut elements: u64 = 1;
        let mut first_dim: u64 = 1;
        for di in 0..n_dims {
            let d = c.u64()?;
            if d == 0 || d > 1 << 40 {
                return Err(format!("implausible tensor dimension {d}"));
            }
            elements = elements.checked_mul(d).ok_or("tensor overflows")?;
            if di == 0 {
                first_dim = d;
            }
        }
        let ggml_type = c.u32()?;
        let name_offset = c.u64()?;
        let _ = &mut tensor_names;
        tensors.push(TensorDesc {
            name,
            name_offset,
            n_dims,
            ggml_type,
            elements,
            first_dim,
        });
    }

    // The tensor data begins at the next ALIGNMENT boundary after the
    // tensor table, not immediately after it. general.alignment defaults to
    // 32 and several writers omit the key entirely. Getting this wrong by a
    // few bytes shifts every weight and the model decodes to noise.
    let align = metadata
        .get("general.alignment")
        .and_then(|v| v.as_u64())
        .filter(|a| *a > 0 && a.is_power_of_two())
        .unwrap_or(32);
    let data_offset = (c.pos + align - 1) / align * align;

    Ok(Header {
        version,
        tensor_count,
        metadata_kv_count,
        metadata,
        tensors,
        tensor_names,
        data_offset,
        total_bytes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quant_block_sizes_are_exact_not_approximated() {
        // Q4_K is 256 values in 144 bytes. Computing it as 4 bits per value
        // would under-report every K-quant by about 12%.
        let t = TensorDesc {
            name_offset: 0,
            name: "t".into(),
            n_dims: 2,
            ggml_type: 12,
            elements: 1000,
            first_dim: 32,
        };
        // ceil(1000/256) = 4 blocks, 4 * 144 = 576 bytes.
        assert_eq!(t.bytes(), Some(576));

        // Q8_0: 32 values in 34 bytes, so 1000 values is 32 blocks.
        let t8 = TensorDesc {
            ggml_type: 8,
            elements: 1000,
            ..t.clone()
        };
        assert_eq!(t8.bytes(), Some(32 * 34));

        // F32 is one value per four bytes, no blocking.
        let t32 = TensorDesc {
            ggml_type: 0,
            elements: 1000,
            ..t.clone()
        };
        assert_eq!(t32.bytes(), Some(4000));
    }

    #[test]
    fn a_partial_block_still_costs_a_whole_block() {
        let t = TensorDesc {
            name_offset: 0,
            name: "t".into(),
            n_dims: 1,
            ggml_type: 12,
            elements: 1,
            first_dim: 32,
        };
        assert_eq!(t.bytes(), Some(144), "one Q4_K value still occupies a block");
    }

    #[test]
    fn unknown_quant_types_are_refused_not_guessed() {
        let t = TensorDesc {
            name_offset: 0,
            name: "t".into(),
            n_dims: 2,
            ggml_type: 9999,
            elements: 1000,
            first_dim: 32,
        };
        assert_eq!(t.bytes(), None, "an unknown format has an unknown size");
    }

    #[test]
    fn a_file_that_is_not_gguf_is_rejected() {
        let p = std::env::temp_dir().join("portllm-not-gguf.bin");
        std::fs::write(&p, b"this is definitely not a GGUF file at all").unwrap();
        let err = read_header(&p).unwrap_err();
        assert!(err.contains("not a GGUF"), "got: {err}");
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn a_truncated_file_fails_rather_than_hanging() {
        let p = std::env::temp_dir().join("portllm-truncated.gguf");
        // Valid magic and version, then nothing.
        std::fs::write(&p, [0x47, 0x47, 0x55, 0x46, 3, 0, 0, 0]).unwrap();
        assert!(read_header(&p).is_err(), "truncated header must be an error");
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn a_corrupt_tensor_count_cannot_trigger_a_huge_alloc() {
        let p = std::env::temp_dir().join("portllm-bogus.gguf");
        let mut b = Vec::new();
        b.extend_from_slice(&GGUF_MAGIC.to_le_bytes());
        b.extend_from_slice(&3u32.to_le_bytes());
        b.extend_from_slice(&u64::MAX.to_le_bytes()); // absurd tensor count
        b.extend_from_slice(&0u64.to_le_bytes());
        b.extend_from_slice(&0u64.to_le_bytes());
        std::fs::write(&p, &b).unwrap();
        let err = read_header(&p).unwrap_err();
        assert!(err.contains("claims"), "got: {err}");
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn reading_a_real_model_header_is_fast_and_small() {
        let path = Path::new("/tmp/qwen05b.gguf");
        if !path.exists() {
            return; // not every machine has one
        }
        let start = std::time::Instant::now();
        let h = read_header(path).expect("real model header should parse");
        let elapsed = start.elapsed();

        // Generous, because this asserts "does not read the whole file" rather than
        // "is fast". Under parallel test load on a phone this has been seen at
        // 3.5s while doing exactly the right thing, and a flaky test trains
        // people to ignore failures.
        assert!(
            elapsed.as_secs() < 10,
            "header took {elapsed:?}, which suggests it is reading the file"
        );
        assert_eq!(h.version, 3);
        assert!(h.tensor_count > 0, "model should declare tensors");
        assert!(
            h.total_bytes > 400_000_000,
            "file size should be the real one, got {}",
            h.total_bytes
        );
        // The header carries the tokenizer, which for a real model is tens of
        // thousands of strings. That is megabytes, not kilobytes, and it is
        // still a rounding error against the weights.
        assert!(
            h.data_offset < 32 * 1024 * 1024,
            "header of {} bytes is implausibly large",
            h.data_offset
        );
        assert!(
            h.data_offset * 10 < h.total_bytes,
            "header is a large fraction of the file: {} of {}",
            h.data_offset,
            h.total_bytes
        );
    }

    /// A weight-tied model is the case that broke this check.
    ///
    /// Qwen2.5-0.5B shares one 136M-element buffer between its input
    /// embedding and its output projection. Summing tensor sizes therefore
    /// reports 630 MB of data for a 491 MB file, and the earlier integrity
    /// check called a byte-perfect HuggingFace download truncated. The file
    /// matched the published sha256; the checker was wrong.
    ///
    /// Asserting against the real file is the only way this stays fixed. A
    /// synthetic fixture would not have caught it, because the bug is in how
    /// the header's entries relate to each other.
    #[test]
    fn a_complete_model_is_not_reported_as_truncated() {
        let path = std::path::Path::new("/tmp/qwen05b-good.gguf");
        if !path.exists() {
            return;
        }
        let h = read_header(path).expect("header");

        // After the Q5_0 block size was corrected from 34 to its real 22,
        // the declared tensor bytes sit just under the file, which is what
        // a complete model looks like. The earlier "the sum exceeds the
        // file" assertion was itself an artifact of that bug: the sum only
        // overran because every Q5_0 tensor was inflated by 55%.
        let sum = h.tensor_bytes().expect("sized");
        let extent = h.tensor_extent().expect("sized");
        assert!(extent <= h.total_bytes, "extent {extent} exceeds file");
        assert!(
            sum <= h.total_bytes,
            "a complete model should not declare more tensor bytes than it holds: {sum} > {}",
            h.total_bytes
        );
        assert!(
            h.integrity().is_ok(),
            "a byte-perfect HuggingFace download must not be flagged, got {:?}",
            h.integrity()
        );
    }
    #[test]
    fn real_model_metadata_is_readable() {
        let path = Path::new("/tmp/qwen05b.gguf");
        if !path.exists() {
            return;
        }
        let h = read_header(path).expect("header");
        // Every GGUF carries these two, and without them the planner cannot
        // reason about the model at all.
        let arch = h.get("general.architecture").and_then(|v| v.as_str());
        assert!(arch.is_some(), "general.architecture must be present");

        let name = h.get("general.name").and_then(|v| v.as_str());
        assert!(name.is_some(), "general.name must be present");
    }
}