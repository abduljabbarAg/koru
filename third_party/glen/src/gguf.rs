// gguf.rs - loader: header, KV, tensor table. data_start AFTER tensor table.
use memmap2::Mmap;
use std::collections::HashMap;
use std::fs::File;

#[derive(Debug, Clone)]
pub enum Kv {
    U32(u32),
    F32(f32),
    Bool(bool),
    Str(String),
    ArrStr(Vec<String>),
    U64(u64),
}

#[derive(Debug, Clone)]
pub struct Tensor {
    pub dims: Vec<u64>,
    pub dtype: u32,
    pub offset: u64,
    pub ne: u64,
}

pub struct Gguf {
    pub mm: Mmap,
    pub kv: HashMap<String, Kv>,
    pub tensors: HashMap<String, Tensor>,
    pub data_start: usize,
    pub arch: String,
}

fn r32(b: &[u8], o: &mut usize) -> u32 {
    let v = u32::from_le_bytes([b[*o], b[*o + 1], b[*o + 2], b[*o + 3]]);
    *o += 4;
    v
}
fn r64(b: &[u8], o: &mut usize) -> u64 {
    let v = u64::from_le_bytes(b[*o..*o + 8].try_into().unwrap());
    *o += 8;
    v
}
fn rstr(b: &[u8], o: &mut usize) -> String {
    let n = r64(b, o) as usize;
    let s = String::from_utf8_lossy(&b[*o..*o + n]).to_string();
    *o += n;
    s
}
fn skip_val(b: &[u8], o: &mut usize, t: u32) {
    match t {
        0 | 1 | 7 => *o += 1,
        2 | 3 => *o += 2,
        4 | 5 | 6 => *o += 4,
        8 => {
            let _ = rstr(b, o);
        }
        9 => {
            let et = r32(b, o);
            let n = r64(b, o) as usize;
            for _ in 0..n {
                skip_val(b, o, et);
            }
        }
        10 | 11 | 12 => *o += 8,
        _ => panic!("kv type {}", t),
    }
}
fn get_val(b: &[u8], o: &mut usize, t: u32) -> Kv {
    match t {
        4 => Kv::U32(r32(b, o)),
        6 => {
            let v = f32::from_le_bytes([b[*o], b[*o + 1], b[*o + 2], b[*o + 3]]);
            *o += 4;
            Kv::F32(v)
        }
        7 => {
            let v = b[*o] != 0;
            *o += 1;
            Kv::Bool(v)
        }
        8 => Kv::Str(rstr(b, o)),
        9 => {
            let et = r32(b, o);
            let n = r64(b, o) as usize;
            if et == 8 {
                let mut v = Vec::with_capacity(n.min(200000));
                for _ in 0..n {
                    v.push(rstr(b, o));
                }
                Kv::ArrStr(v)
            } else {
                for _ in 0..n {
                    skip_val(b, o, et);
                }
                Kv::U64(n as u64)
            }
        }
        10 => Kv::U64(r64(b, o)),
        _ => {
            skip_val(b, o, t);
            Kv::U64(0)
        }
    }
}

pub fn block_bytes(dtype: u32) -> (u64, u64) {
    match dtype {
        0 => (4, 1),
        1 => (2, 1),
        2 => (18, 32),
        6 => (22, 32),
        8 => (34, 32),
        12 => (144, 256),
        14 => (210, 256),
        24 => (1, 1),
        42 => (34, 128),
        142 => (34, 128),
        _ => (0, 1),
    }
}

pub fn open(path: &str) -> Gguf {
    let f = File::open(path).expect("open model");
    let mm = unsafe { Mmap::map(&f).expect("mmap") };
    let b: &[u8] = &mm;
    assert_eq!(&b[0..4], b"GGUF", "bad magic");
    let mut o = 4usize;
    let _ver = r32(b, &mut o);
    let nt = r64(b, &mut o);
    let nkv = r64(b, &mut o);
    let mut kv = HashMap::new();
    let mut align = 32u64;
    let mut arch = String::new();
    for _ in 0..nkv {
        let k = rstr(b, &mut o);
        let t = r32(b, &mut o);
        if k == "general.alignment" && (t == 4 || t == 10) {
            align = if t == 4 { r32(b, &mut o) as u64 } else { r64(b, &mut o) };
        } else if k == "general.architecture" {
            if let Kv::Str(s) = get_val(b, &mut o, t) {
                arch = s;
            }
        } else {
            let v = get_val(b, &mut o, t);
            // keep only what the runner needs (skip giant arrays except tokens/merges)
            let keep = k.ends_with("block_count")
                || k.ends_with("context_length")
                || k.ends_with("embedding_length")
                || k.ends_with("feed_forward_length")
                || k.ends_with("head_count")
                || k.ends_with("head_count_kv")
                || k.ends_with("key_length")
                || k.ends_with("value_length")
                || k.ends_with("freq_base")
                || k.ends_with("rope.scaling.type")
                || k.ends_with("rope.scaling.factor")
                || k.ends_with("rope.scaling.original_context_length")
                || k.ends_with("rope.scaling.mscale_all_dim")
                || k.ends_with("rms_epsilon")
                || k.ends_with("rms_norm_eps")
                || k.contains("tokenizer.ggml")
                || k == "tokenizer.chat_template"
                || k == "general.name";
            if keep {
                kv.insert(k, v);
            }
        }
    }
    let mut tensors = HashMap::new();
    for _ in 0..nt {
        let name = rstr(b, &mut o);
        let nd = r32(b, &mut o);
        let mut dims = vec![];
        let mut ne = 1u64;
        for _ in 0..nd {
            let d = r64(b, &mut o);
            dims.push(d);
            ne *= d;
        }
        let dt = r32(b, &mut o);
        let off = r64(b, &mut o);
        tensors.insert(name, Tensor { dims, dtype: dt, offset: off, ne });
    }
    let data_start = (o as u64 + align - 1) / align * align;
    Gguf { mm, kv, tensors, data_start: data_start as usize, arch }
}

impl Gguf {
    pub fn raw(&self, t: &Tensor) -> &[u8] {
        let (sz, blk) = block_bytes(t.dtype);
        assert!(sz > 0, "unknown dtype {}", t.dtype);
        let n = (t.ne / blk * sz) as usize;
        let s = self.data_start + t.offset as usize;
        &self.mm[s..s + n]
    }
    pub fn u32(&self, key: &str, dflt: u32) -> u32 {
        match self.kv.get(key) {
            Some(Kv::U32(v)) => *v,
            Some(Kv::U64(v)) => *v as u32,
            _ => dflt,
        }
    }
    pub fn f32(&self, key: &str, dflt: f32) -> f32 {
        match self.kv.get(key) {
            Some(Kv::F32(v)) => *v,
            _ => dflt,
        }
    }
}
