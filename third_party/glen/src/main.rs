// main.rs - spike 007: Qwen2.5-0.5B text runner (greedy decode, single thread).
mod gguf;
mod guard;
mod json;
mod quant;
mod serve;
mod tok;
mod tools;

use gguf::Gguf;
use std::collections::HashMap;
use std::time::Instant;

/// Precomputed tensor names for one layer: built once at load, borrowed in the hot loop.
struct LNames {
    q: String,
    k: String,
    v: String,
    qb: String,
    kb: String,
    vb: String,
    o: String,
    gate: String,
    up: String,
    down: String,
    an: String,
    ff: String,
    qn: String,
    kn: String,
}
struct Model {
    g: Gguf,
    n_layer: usize,
    hidden: usize,
    n_head: usize,
    n_kv: usize,
    ff: usize,
    head_dim: usize,
    eps: f32,
    theta: f32,
    neox: bool,
    eos: u32,
    fb: HashMap<String, Vec<f32>>, // cached F32 1-D tensors (norms, biases)
    ku: HashMap<String, quant::KU>, // cached unpacked Q4_K/Q6_K weights
    ln: Vec<LNames>, // precomputed per-layer tensor names: zero format! in hot loop
    has_bias: bool,  // any .bias tensors present (skip bias-name formatting if none)
    exact: bool,     // Glen_EXACT single-thread path (env read once at load)
    use_ku: bool,    // cached K-quant path (off with Glen_NOKU)
    qk_norm: bool,   // qwen3 per-head q/k RMS norm before rope
    yarn: bool,      // rope scaling type yarn (qwen3 long context)
    freq_scale: f32,
    ext_factor: f32,
    mscale: f32,
    corr_lo: f32,
    corr_hi: f32,
    pool: quant::Pool,
}

impl Model {
    fn mat(&self, name: &str, x: &[f32], y: &mut [f32]) {
        let t = self.g.tensors.get(name).unwrap_or_else(|| panic!("missing tensor {}", name));
        assert!(t.dims.len() == 2, "{} not 2d", name);
        let cols = t.dims[0] as usize;
        let rows = t.dims[1] as usize;
        assert_eq!(x.len(), cols, "{} xlen", name);
        assert!(y.len() >= rows);
        if self.exact {
            quant::gemv(self.g.raw(t), t.dtype, rows, cols, x, &mut y[..rows]);
            return;
        }
        if self.use_ku {
            if let Some(ku) = self.ku.get(name) {
                quant::gemv_ku_mt(ku, rows, cols, x, &mut y[..rows], &self.pool);
                return;
            }
        }
        quant::gemv_mt(self.g.raw(t), t.dtype, rows, cols, x, &mut y[..rows], &self.pool);
    }
    fn mat_batch(&self, name: &str, xb: &[f32], n: usize, yb: &mut [f32]) {
        let t = self.g.tensors.get(name).unwrap_or_else(|| panic!("missing tensor {}", name));
        assert!(t.dims.len() == 2, "{} not 2d", name);
        let cols = t.dims[0] as usize;
        let rows = t.dims[1] as usize;
        if self.exact {
            for bi in 0..n {
                quant::gemv(self.g.raw(t), t.dtype, rows, cols, &xb[bi * cols..(bi + 1) * cols], &mut yb[bi * rows..(bi + 1) * rows]);
            }
            return;
        }
        if self.use_ku {
            if let Some(ku) = self.ku.get(name) {
                quant::gemm_ku_batch_mt(ku, rows, cols, xb, n, yb, &self.pool);
                return;
            }
        }
        quant::gemm_batch_mt(self.g.raw(t), t.dtype, rows, cols, xb, n, yb, &self.pool);
    }
    fn dims2(&self, name: &str) -> (u32, usize, usize) {
        let t = self.g.tensors.get(name).unwrap_or_else(|| panic!("missing tensor {}", name));
        assert!(t.dims.len() == 2, "{} not 2d", name);
        (t.dtype, t.dims[0] as usize, t.dims[1] as usize)
    }
    /// Bias add by full tensor name: no formatting (names prebuilt in LNames).
    fn add_bias_full(&self, bn: &str, y: &mut [f32]) {
        if let Some(b) = self.fb.get(bn) {
            for i in 0..y.len().min(b.len()) {
                y[i] += b[i];
            }
            return;
        }
        if let Some(bt) = self.g.tensors.get(bn) {
            let b = quant::dequant_all(self.g.raw(bt), bt.dtype, bt.ne as usize);
            for i in 0..y.len().min(b.len()) {
                y[i] += b[i];
            }
        }
    }
    fn add_bias1(&self, base: &str, y: &mut [f32]) {
        if !self.has_bias {
            return;
        }
        let bn = base.strip_suffix(".weight").map(|s| format!("{}.bias", s)).unwrap_or_else(|| format!("{}.bias", base));
        if let Some(b) = self.fb.get(&bn) {
            for i in 0..y.len().min(b.len()) {
                y[i] += b[i];
            }
            return;
        }
        if let Some(bt) = self.g.tensors.get(&bn) {
            let b = quant::dequant_all(self.g.raw(bt), bt.dtype, bt.ne as usize);
            for i in 0..y.len().min(b.len()) {
                y[i] += b[i];
            }
        }
    }
    fn add_bias_n(&self, base: &str, yb: &mut [f32], n: usize) {
        if !self.has_bias {
            return;
        }
        let bn = base.strip_suffix(".weight").map(|s| format!("{}.bias", s)).unwrap_or_else(|| format!("{}.bias", base));
        if let Some(b) = self.fb.get(&bn) {
            let rows = yb.len() / n;
            for bi in 0..n {
                for i in 0..rows.min(b.len()) {
                    yb[bi * rows + i] += b[i];
                }
            }
        }
    }
    /// Fused single-token pair (decode), no bias. y1.len/y2.len must equal rows.
    fn mat2(&self, n1: &str, n2: &str, x: &[f32], y1: &mut [f32], y2: &mut [f32]) {
        let (d1, c1, r1) = self.dims2(n1);
        let (d2, c2, r2) = self.dims2(n2);
        assert_eq!(c1, c2);
        assert_eq!(x.len(), c1);
        if self.exact {
            let t1 = self.g.tensors.get(n1).unwrap();
            let t2 = self.g.tensors.get(n2).unwrap();
            quant::gemv(self.g.raw(t1), d1, r1, c1, x, &mut y1[..r1]);
            quant::gemv(self.g.raw(t2), d2, r2, c2, x, &mut y2[..r2]);
            return;
        }
        let t1 = self.g.tensors.get(n1).unwrap();
        let t2 = self.g.tensors.get(n2).unwrap();
        quant::gemv2_mt(self.g.raw(t1), d1, r1, self.g.raw(t2), d2, r2, c1, x, &mut y1[..r1], &mut y2[..r2], &self.pool);
    }
    /// Fused single-token triple (decode) with bias. Takes prebuilt layer names: zero alloc.
    fn mat3_opt_bias(&self, L: &LNames, x: &[f32], y1: &mut [f32], y2: &mut [f32], y3: &mut [f32]) {
        let (d1, c1, r1) = self.dims2(&L.q);
        let (d2, c2, r2) = self.dims2(&L.k);
        let (d3, c3, r3) = self.dims2(&L.v);
        assert_eq!(c1, c2);
        assert_eq!(c1, c3);
        assert_eq!(x.len(), c1);
        if self.exact {
            let t1 = self.g.tensors.get(&L.q).unwrap();
            let t2 = self.g.tensors.get(&L.k).unwrap();
            let t3 = self.g.tensors.get(&L.v).unwrap();
            quant::gemv(self.g.raw(t1), d1, r1, c1, x, &mut y1[..r1]);
            quant::gemv(self.g.raw(t2), d2, r2, c2, x, &mut y2[..r2]);
            quant::gemv(self.g.raw(t3), d3, r3, c3, x, &mut y3[..r3]);
        } else {
            let t1 = self.g.tensors.get(&L.q).unwrap();
            let t2 = self.g.tensors.get(&L.k).unwrap();
            let t3 = self.g.tensors.get(&L.v).unwrap();
            quant::gemv3_mt(self.g.raw(t1), d1, r1, self.g.raw(t2), d2, r2, self.g.raw(t3), d3, r3, c1, x, &mut y1[..r1], &mut y2[..r2], &mut y3[..r3], &self.pool);
        }
        self.add_bias_full(&L.qb, &mut y1[..r1]);
        self.add_bias_full(&L.kb, &mut y2[..r2]);
        self.add_bias_full(&L.vb, &mut y3[..r3]);
    }
    /// Fused batched pair (prefill), no bias.
    fn mat2_batch(&self, n1: &str, n2: &str, xb: &[f32], n: usize, y1: &mut [f32], y2: &mut [f32]) {
        let (d1, c1, r1) = self.dims2(n1);
        let (d2, c2, r2) = self.dims2(n2);
        assert_eq!(c1, c2);
        if self.exact {
            for bi in 0..n {
                let t1 = self.g.tensors.get(n1).unwrap();
                let t2 = self.g.tensors.get(n2).unwrap();
                quant::gemv(self.g.raw(t1), d1, r1, c1, &xb[bi * c1..(bi + 1) * c1], &mut y1[bi * r1..(bi + 1) * r1]);
                quant::gemv(self.g.raw(t2), d2, r2, c2, &xb[bi * c2..(bi + 1) * c2], &mut y2[bi * r2..(bi + 1) * r2]);
            }
            return;
        }
        let t1 = self.g.tensors.get(n1).unwrap();
        let t2 = self.g.tensors.get(n2).unwrap();
        quant::gemm2_batch_mt(self.g.raw(t1), d1, r1, self.g.raw(t2), d2, r2, c1, xb, n, y1, y2, &self.pool);
    }
    /// Fused batched triple (prefill) with bias.
    fn mat3_opt_bias_batch(&self, n1: &str, n2: &str, n3: &str, xb: &[f32], n: usize, y1: &mut [f32], y2: &mut [f32], y3: &mut [f32]) {
        let (d1, c1, _) = self.dims2(n1);
        let (d2, c2, _) = self.dims2(n2);
        let (d3, c3, _) = self.dims2(n3);
        assert_eq!(c1, c2);
        assert_eq!(c1, c3);
        if self.exact {
            self.mat_opt_bias_batch(n1, xb, n, y1);
            self.mat_opt_bias_batch(n2, xb, n, y2);
            self.mat_opt_bias_batch(n3, xb, n, y3);
            return;
        }
        let (d1b, _, r1) = self.dims2(n1);
        let (d2b, _, r2) = self.dims2(n2);
        let (d3b, _, r3) = self.dims2(n3);
        let t1 = self.g.tensors.get(n1).unwrap();
        let t2 = self.g.tensors.get(n2).unwrap();
        let t3 = self.g.tensors.get(n3).unwrap();
        quant::gemm3_batch_mt(self.g.raw(t1), d1b, r1, self.g.raw(t2), d2b, r2, self.g.raw(t3), d3b, r3, c1, xb, n, y1, y2, y3, &self.pool);
        self.add_bias_n(n1, y1, n);
        self.add_bias_n(n2, y2, n);
        self.add_bias_n(n3, y3, n);
        let _ = (d1, d2, d3);
    }
    fn mat_opt_bias(&self, base: &str, x: &[f32], y: &mut [f32]) {
        self.mat(base, x, y);
        let bn = base.strip_suffix(".weight").map(|s| format!("{}.bias", s)).unwrap_or_else(|| format!("{}.bias", base));
        if let Some(b) = self.fb.get(&bn) {
            for i in 0..y.len().min(b.len()) {
                y[i] += b[i];
            }
            return;
        }
        if let Some(bt) = self.g.tensors.get(&bn) {
            let b = quant::dequant_all(self.g.raw(bt), bt.dtype, bt.ne as usize);
            for i in 0..y.len().min(b.len()) {
                y[i] += b[i];
            }
        }
    }
    fn mat_opt_bias_batch(&self, base: &str, xb: &[f32], n: usize, yb: &mut [f32]) {
        self.mat_batch(base, xb, n, yb);
        let bn = base.strip_suffix(".weight").map(|s| format!("{}.bias", s)).unwrap_or_else(|| format!("{}.bias", base));
        if let Some(b) = self.fb.get(&bn) {
            let rows = yb.len() / n;
            for bi in 0..n {
                for i in 0..rows.min(b.len()) {
                    yb[bi * rows + i] += b[i];
                }
            }
        }
    }
    fn norm_w(&self, name: &str) -> &[f32] {
        // fb holds every 1-D tensor from load: borrow, never clone.
        self.fb.get(name).map(|w| w.as_slice()).unwrap_or_else(|| panic!("missing norm {}", name))
    }
}

fn rmsnorm(x: &[f32], w: &[f32], eps: f32, o: &mut [f32]) {
    let mut s = 0.0f32;
    for &v in x {
        s += v * v;
    }
    let inv = 1.0 / ((s / x.len() as f32 + eps).sqrt());
    for i in 0..x.len() {
        o[i] = x[i] * inv * w[i];
    }
}
fn silu(v: &mut [f32]) {
    for x in v.iter_mut() {
        *x *= 1.0 / (1.0 + (-*x).exp());
    }
}
fn softmax(v: &mut [f32]) {
    let mx = v.iter().fold(f32::NEG_INFINITY, |a, &b| a.max(b));
    let mut s = 0.0f32;
    for x in v.iter_mut() {
        *x = (*x - mx).exp();
        s += *x;
    }
    for x in v.iter_mut() {
        *x /= s;
    }
}

/// Yarn aware rope for the batched path: cos/sin computed per position.
fn rope_yarn_apply(x: &mut [f32], pos: usize, head_dim: usize, n_head: usize, m: &Model) {
    let d = head_dim;
    let hd2 = d / 2;
    let theta_scale = m.theta.powf(-2.0 / d as f32);
    let span = (m.corr_hi - m.corr_lo).max(0.001);
    for hh in 0..n_head {
        let mut theta_extrap = pos as f32;
        for i in 0..hd2 {
            let (c, s) = if m.yarn {
                let ramp = (1.0 - ((i as f32 - m.corr_lo) / span).clamp(0.0, 1.0)) * m.ext_factor;
                let theta = m.freq_scale * theta_extrap * (1.0 - ramp) + theta_extrap * ramp;
                (theta.cos() * m.mscale, theta.sin() * m.mscale)
            } else {
                (theta_extrap.cos(), theta_extrap.sin())
            };
            let base = hh * d;
            if m.neox {
                let a = x[base + 2 * i];
                let b = x[base + 2 * i + 1];
                x[base + 2 * i] = a * c - b * s;
                x[base + 2 * i + 1] = a * s + b * c;
            } else {
                let a = x[base + i];
                let b = x[base + i + hd2];
                x[base + i] = a * c - b * s;
                x[base + i + hd2] = a * s + b * c;
            }
            theta_extrap *= theta_scale;
        }
    }
}

struct Cache {
    q8: bool,
    kv_dim: usize,
    nblk: usize, // kv_dim / 32
    k: Vec<f32>,
    v: Vec<f32>,
    kq: Vec<i8>,
    kd: Vec<f32>,
    vq: Vec<i8>,
    vd: Vec<f32>,
}

fn cache_new(max_pos: usize, kv_dim: usize, q8: bool) -> Cache {
    let nblk = kv_dim / 32;
    if q8 {
        Cache {
            q8,
            kv_dim,
            nblk,
            k: Vec::new(),
            v: Vec::new(),
            kq: vec![0i8; max_pos * kv_dim],
            kd: vec![0f32; max_pos * nblk],
            vq: vec![0i8; max_pos * kv_dim],
            vd: vec![0f32; max_pos * nblk],
        }
    } else {
        Cache {
            q8,
            kv_dim,
            nblk,
            k: vec![0f32; max_pos * kv_dim],
            v: vec![0f32; max_pos * kv_dim],
            kq: Vec::new(),
            kd: Vec::new(),
            vq: Vec::new(),
            vd: Vec::new(),
        }
    }
}

/// Append one position, quantized to int8 in 32-blocks when q8 is on.
fn cache_put(c: &mut Cache, pos: usize, k: &[f32], v: &[f32]) {
    let kd = c.kv_dim;
    if c.q8 {
        let (kq, ks) = (&mut c.kq[pos * kd..(pos + 1) * kd], &mut c.kd[pos * c.nblk..(pos + 1) * c.nblk]);
        let (vq, vs) = (&mut c.vq[pos * kd..(pos + 1) * kd], &mut c.vd[pos * c.nblk..(pos + 1) * c.nblk]);
        for b in 0..c.nblk {
            let mut amax = 0f32;
            for i in 0..32 {
                let a = k[b * 32 + i].abs();
                if a > amax {
                    amax = a;
                }
            }
            let dk = if amax == 0.0 { 1.0 } else { amax / 127.0 };
            ks[b] = dk;
            for i in 0..32 {
                kq[b * 32 + i] = (k[b * 32 + i] / dk).round().clamp(-127.0, 127.0) as i8;
            }
            let mut vmax = 0f32;
            for i in 0..32 {
                let a = v[b * 32 + i].abs();
                if a > vmax {
                    vmax = a;
                }
            }
            let dv = if vmax == 0.0 { 1.0 } else { vmax / 127.0 };
            vs[b] = dv;
            for i in 0..32 {
                vq[b * 32 + i] = (v[b * 32 + i] / dv).round().clamp(-127.0, 127.0) as i8;
            }
        }
    } else {
        c.k[pos * kd..(pos + 1) * kd].copy_from_slice(k);
        c.v[pos * kd..(pos + 1) * kd].copy_from_slice(v);
    }
}

#[inline]
fn kget(c: &Cache, j: usize, i: usize) -> f32 {
    if c.q8 {
        c.kq[j * c.kv_dim + i] as f32 * c.kd[j * c.nblk + i / 32]
    } else {
        c.k[j * c.kv_dim + i]
    }
}

#[inline]
fn vget(c: &Cache, j: usize, i: usize) -> f32 {
    if c.q8 {
        c.vq[j * c.kv_dim + i] as f32 * c.vd[j * c.nblk + i / 32]
    } else {
        c.v[j * c.kv_dim + i]
    }
}

fn rope(x: &mut [f32], pos: usize, head_dim: usize, n_head: usize, theta: f32, neox: bool) {
    // neox=true: adjacent pairs (GPT-NeoX). false: split halves (GPT-J / NORMAL).
    for h in 0..n_head {
        if neox {
            for i in 0..head_dim / 2 {
                let f = theta.powf(-2.0 * i as f32 / head_dim as f32) * pos as f32;
                let (c, s) = (f.cos(), f.sin());
                let a = x[h * head_dim + 2 * i];
                let b = x[h * head_dim + 2 * i + 1];
                x[h * head_dim + 2 * i] = a * c - b * s;
                x[h * head_dim + 2 * i + 1] = a * s + b * c;
            }
        } else {
            for i in 0..head_dim / 2 {
                let f = theta.powf(-2.0 * i as f32 / head_dim as f32) * pos as f32;
                let (c, s) = (f.cos(), f.sin());
                let a = x[h * head_dim + i];
                let b = x[h * head_dim + i + head_dim / 2];
                x[h * head_dim + i] = a * c - b * s;
                x[h * head_dim + i + head_dim / 2] = a * s + b * c;
            }
        }
    }
}

/// RoPE with a precomputed (cos,sin) table for this position: same math as rope(), no trig.
fn rope_t(x: &mut [f32], rc: &[(f32, f32)], n_head: usize, neox: bool) {
    let hd2 = rc.len();
    let hd = hd2 * 2;
    for h in 0..n_head {
        if neox {
            for i in 0..hd2 {
                let (c, s) = rc[i];
                let a = x[h * hd + 2 * i];
                let b = x[h * hd + 2 * i + 1];
                x[h * hd + 2 * i] = a * c - b * s;
                x[h * hd + 2 * i + 1] = a * s + b * c;
            }
        } else {
            for i in 0..hd2 {
                let (c, s) = rc[i];
                let a = x[h * hd + i];
                let b = x[h * hd + i + hd2];
                x[h * hd + i] = a * c - b * s;
                x[h * hd + i + hd2] = a * s + b * c;
            }
        }
    }
}

fn rms(v: &[f32]) -> f32 {
    let mut s = 0.0f64;
    for &x in v {
        s += x as f64 * x as f64;
    }
    ((s / v.len() as f64).sqrt()) as f32
}

fn forward<'a>(m: &Model, tok_id: u32, pos: usize, caches: &mut [Cache], tmp: &'a mut Tmp, max_layer: usize, trace: bool) -> &'a [f32] {
    let h = m.hidden;
    let d = m.head_dim;
    // embed
    let emb = m.g.tensors.get("token_embd.weight").expect("no emb");
    let eb = m.g.raw(emb);
    let x = &mut tmp.x[..h];
    deq_emb_row(emb.dtype, eb, tok_id, h, x);
    // rope (cos,sin) table for this position: trig once per token, shared by q/k and all layers
    let hd2 = d / 2;
    tmp.rc.resize(hd2, (0.0, 0.0));
    if m.yarn {
        let theta_scale = m.theta.powf(-2.0 / d as f32);
        let mut theta_extrap = pos as f32;
        let span = (m.corr_hi - m.corr_lo).max(0.001);
        for i in 0..hd2 {
            let ramp = (1.0 - ((i as f32 - m.corr_lo) / span).clamp(0.0, 1.0)) * m.ext_factor;
            let theta = m.freq_scale * theta_extrap * (1.0 - ramp) + theta_extrap * ramp;
            tmp.rc[i] = (theta.cos() * m.mscale, theta.sin() * m.mscale);
            theta_extrap *= theta_scale;
        }
    } else {
        for i in 0..hd2 {
            let f = m.theta.powf(-2.0 * i as f32 / d as f32) * pos as f32;
            tmp.rc[i] = (f.cos(), f.sin());
        }
    }
    let prof = std::env::var("Glen_PROFILE").is_ok();
    let mut pa = [0f64; 9];
    let mut ck = |i: usize, t: &mut std::time::Instant, a: &mut [f64; 9]| {
        a[i] += t.elapsed().as_secs_f64() * 1e3;
        *t = std::time::Instant::now();
    };
    for l in 0..max_layer.min(m.n_layer) {
        let L = &m.ln[l];
        let mut _t = std::time::Instant::now();
        rmsnorm(&x, &m.norm_w(&L.an), m.eps, &mut tmp.h1);
        if prof { ck(0, &mut _t, &mut pa); }
        m.mat3_opt_bias(L, &tmp.h1, &mut tmp.q, &mut tmp.k, &mut tmp.v);
        if prof { ck(1, &mut _t, &mut pa); }
        if m.qk_norm {
            let qn = m.norm_w(&L.qn);
            let kn = m.norm_w(&L.kn);
            for hh in 0..m.n_head {
                let off = hh * d;
                let mut s = 0.0f32;
                for i in 0..d { s += tmp.q[off + i] * tmp.q[off + i]; }
                let inv = 1.0 / ((s / d as f32 + m.eps).sqrt());
                for i in 0..d { tmp.q[off + i] *= inv * qn[i]; }
            }
            for hh in 0..m.n_kv {
                let off = hh * d;
                let mut s = 0.0f32;
                for i in 0..d { s += tmp.k[off + i] * tmp.k[off + i]; }
                let inv = 1.0 / ((s / d as f32 + m.eps).sqrt());
                for i in 0..d { tmp.k[off + i] *= inv * kn[i]; }
            }
        }
        rope_t(&mut tmp.q, &tmp.rc, m.n_head, m.neox);
        rope_t(&mut tmp.k, &tmp.rc, m.n_kv, m.neox);
        // append kv
        let c = &mut caches[l];
        cache_put(c, pos, &tmp.k, &tmp.v);
        if prof { ck(2, &mut _t, &mut pa); }
        // attention
        let scale = 1.0 / (d as f32).sqrt();
        let rep = m.n_head / m.n_kv;
        for hh in 0..m.n_head {
            let kh = hh / rep;
            for j in 0..=pos {
                let mut s = 0.0f32;
                for i in 0..d {
                    s += tmp.q[hh * d + i] * kget(c, j, kh * d + i);
                }
                tmp.sc[j] = s * scale;
            }
            softmax(&mut tmp.sc[..pos + 1]);
            for i in 0..d {
                let mut s = 0.0f32;
                for j in 0..=pos {
                    s += tmp.sc[j] * vget(c, j, kh * d + i);
                }
                tmp.o[hh * d + i] = s;
            }
        }
        if prof { ck(3, &mut _t, &mut pa); }
        m.mat(&L.o, &tmp.o, &mut tmp.h2);
        for i in 0..h {
            x[i] += tmp.h2[i];
        }
        if prof { ck(4, &mut _t, &mut pa); }
        if trace {
            println!("L{} post-attn rms(x)={:.4} rms(q)={:.4} rms(o)={:.4}", l, rms(&x), rms(&tmp.q), rms(&tmp.o));
        }
        // mlp
        rmsnorm(&x, &m.norm_w(&L.ff), m.eps, &mut tmp.h1);
        if prof { ck(5, &mut _t, &mut pa); }
        m.mat2(&L.gate, &L.up, &tmp.h1, &mut tmp.g, &mut tmp.u);
        if prof { ck(6, &mut _t, &mut pa); }
        silu(&mut tmp.g);
        for i in 0..m.ff {
            tmp.g[i] *= tmp.u[i];
        }
        if prof { ck(7, &mut _t, &mut pa); }
        m.mat(&L.down, &tmp.g, &mut tmp.h2);
        for i in 0..h {
            x[i] += tmp.h2[i];
        }
        if prof { ck(8, &mut _t, &mut pa); }
        if trace {
            println!("L{} post-mlp  rms(x)={:.4} rms(g)={:.4}", l, rms(&x), rms(&tmp.g));
        }
    }
    if prof {
        println!("PROF norm1={:.1} qkv={:.1} ropekv={:.1} attn={:.1} o={:.1} norm2={:.1} gateup={:.1} act={:.1} down={:.1} sum={:.1}ms", pa[0], pa[1], pa[2], pa[3], pa[4], pa[5], pa[6], pa[7], pa[8], pa.iter().sum::<f64>());
    }
    // output norm + logits via tied embeddings (scratch reused: zero per-token alloc)
    rmsnorm(x, m.norm_w("output_norm.weight"), m.eps, &mut tmp.h1);
    let rows = emb.dims[1] as usize; // vocab? for tied, dims [hidden, vocab]
    let cols = emb.dims[0] as usize;
    assert_eq!(cols, h);
    if tmp.log.len() < rows {
        tmp.log.resize(rows, 0.0);
    }
    quant::gemv_mt(eb, emb.dtype, rows, cols, &tmp.h1, &mut tmp.log[..rows], &m.pool);
    &tmp.log[..rows]
}

struct TmpB {
    ncap: usize,
    x: Vec<f32>,
    h1: Vec<f32>,
    h2: Vec<f32>,
    q: Vec<f32>,
    k: Vec<f32>,
    v: Vec<f32>,
    o: Vec<f32>,
    g: Vec<f32>,
    u: Vec<f32>,
    sc: Vec<f32>,
}

impl TmpB {
    fn new(ncap: usize, h: usize, qd: usize, kvd: usize, ff: usize, max_pos: usize) -> Self {
        TmpB {
            ncap,
            x: vec![0.0; ncap * h],
            h1: vec![0.0; ncap * h],
            h2: vec![0.0; ncap * h],
            q: vec![0.0; ncap * qd],
            k: vec![0.0; ncap * kvd],
            v: vec![0.0; ncap * kvd],
            o: vec![0.0; ncap * qd],
            g: vec![0.0; ncap * ff],
            u: vec![0.0; ncap * ff],
            sc: vec![0.0; max_pos],
        }
    }
}

/// Batched forward over ids[0..n] at positions pos0.., returns logits of the LAST token.
fn forward_batch(m: &Model, ids: &[u32], pos0: usize, caches: &mut [Cache], tb: &mut TmpB, max_layer: usize) -> Vec<f32> {
    let n = ids.len();
    assert!(n > 0 && n <= tb.ncap);
    let h = m.hidden;
    let d = m.head_dim;
    let qd = m.n_head * d;
    let kvd = m.n_kv * d;
    let emb = m.g.tensors.get("token_embd.weight").expect("no emb");
    let eb = m.g.raw(emb);
    for (i, &tok) in ids.iter().enumerate() {
        deq_emb_row(emb.dtype, eb, tok, h, &mut tb.x[i * h..(i + 1) * h]);
    }
    for l in 0..max_layer.min(m.n_layer) {
        let L = &m.ln[l];
        let nw = m.norm_w(&L.an);
        for i in 0..n {
            rmsnorm(&tb.x[i * h..(i + 1) * h], &nw, m.eps, &mut tb.h1[i * h..(i + 1) * h]);
        }
        m.mat3_opt_bias_batch(&L.q, &L.k, &L.v, &tb.h1[..n * h], n, &mut tb.q[..n * qd], &mut tb.k[..n * kvd], &mut tb.v[..n * kvd]);
        if m.qk_norm {
            let qn = m.norm_w(&L.qn);
            let kn = m.norm_w(&L.kn);
            for i in 0..n {
                for hh in 0..m.n_head {
                    let off = i * qd + hh * d;
                    let mut s = 0.0f32;
                    for k in 0..d {
                        s += tb.q[off + k] * tb.q[off + k];
                    }
                    let inv = 1.0 / ((s / d as f32 + m.eps).sqrt());
                    for k in 0..d {
                        tb.q[off + k] *= inv * qn[k];
                    }
                }
                for hh in 0..m.n_kv {
                    let off = i * kvd + hh * d;
                    let mut s = 0.0f32;
                    for k in 0..d {
                        s += tb.k[off + k] * tb.k[off + k];
                    }
                    let inv = 1.0 / ((s / d as f32 + m.eps).sqrt());
                    for k in 0..d {
                        tb.k[off + k] *= inv * kn[k];
                    }
                }
            }
        }
        let scale = 1.0 / (d as f32).sqrt();
        let rep = m.n_head / m.n_kv;
        let c = &mut caches[l];
        for i in 0..n {
            let pos = pos0 + i;
            rope_yarn_apply(&mut tb.q[i * qd..(i + 1) * qd], pos, d, m.n_head, m);
            rope_yarn_apply(&mut tb.k[i * kvd..(i + 1) * kvd], pos, d, m.n_kv, m);
            cache_put(c, pos, &tb.k[i * kvd..(i + 1) * kvd], &tb.v[i * kvd..(i + 1) * kvd]);
            for hh in 0..m.n_head {
                let kh = hh / rep;
                let mut mx = f32::NEG_INFINITY;
                for j in 0..=pos {
                    let mut s = 0.0f32;
                    for k in 0..d {
                        s += tb.q[i * qd + hh * d + k] * kget(c, j, kh * d + k);
                    }
                    s *= scale;
                    tb.sc[j] = s;
                    if s > mx {
                        mx = s;
                    }
                }
                let mut psum = 0.0f32;
                for j in 0..=pos {
                    let e = (tb.sc[j] - mx).exp();
                    tb.sc[j] = e;
                    psum += e;
                }
                for k in 0..d {
                    let mut s = 0.0f32;
                    for j in 0..=pos {
                        s += tb.sc[j] * vget(c, j, kh * d + k);
                    }
                    tb.o[i * qd + hh * d + k] = s / psum;
                }
            }
        }
        m.mat_batch(&L.o, &tb.o[..n * qd], n, &mut tb.h2[..n * h]);
        for i in 0..n * h {
            tb.x[i] += tb.h2[i];
        }
        let nw2 = m.norm_w(&L.ff);
        for i in 0..n {
            rmsnorm(&tb.x[i * h..(i + 1) * h], &nw2, m.eps, &mut tb.h1[i * h..(i + 1) * h]);
        }
        m.mat2_batch(&L.gate, &L.up, &tb.h1[..n * h], n, &mut tb.g[..n * m.ff], &mut tb.u[..n * m.ff]);
        for i in 0..n {
            let base = i * m.ff;
            silu(&mut tb.g[base..base + m.ff]);
            for k in 0..m.ff {
                tb.g[base + k] *= tb.u[base + k];
            }
        }
        m.mat_batch(&L.down, &tb.g[..n * m.ff], n, &mut tb.h2[..n * h]);
        for i in 0..n * h {
            tb.x[i] += tb.h2[i];
        }
    }
    let nw3 = m.norm_w("output_norm.weight");
    let mut h1 = vec![0f32; h];
    rmsnorm(&tb.x[(n - 1) * h..n * h], &nw3, m.eps, &mut h1);
    let rows = emb.dims[1] as usize;
    let cols = emb.dims[0] as usize;
    let mut logits = vec![0f32; rows];
    quant::gemv_mt(eb, emb.dtype, rows, cols, &h1, &mut logits, &m.pool);
    logits
}

struct Tmp {
    x: Vec<f32>,   // residual stream scratch (was per-token alloc)
    log: Vec<f32>, // logits scratch (was 152k alloc per token)
    rc: Vec<(f32, f32)>, // rope (cos,sin) table for current pos (was 24x trig/layer)
    h1: Vec<f32>,
    h2: Vec<f32>,
    q: Vec<f32>,
    k: Vec<f32>,
    v: Vec<f32>,
    o: Vec<f32>,
    g: Vec<f32>,
    u: Vec<f32>,
    sc: Vec<f32>,
}

fn argmax(v: &[f32]) -> u32 {
    let mut bi = 0;
    for i in 1..v.len() {
        if v[i] > v[bi] {
            bi = i;
        }
    }
    bi as u32
}

fn dumprms(tag: &str, v: &[f32]) {
    let mut s = 0.0f64;
    let mut mx = 0.0f32;
    let mut mi = 0usize;
    for (i, &x) in v.iter().enumerate() {
        s += x as f64 * x as f64;
        if x.abs() > mx {
            mx = x.abs();
            mi = i;
        }
    }
    let r = ((s / v.len() as f64).sqrt()) as f32;
    println!("{} rms={:.6} max={:.3}@{} f4=[{:.6} {:.6} {:.6} {:.6}]", tag, r, v[mi], mi, v[0], v[1], v[2], v[3]);
}

/// Dequant one embedding row of any supported quant dtype into x.
fn deq_emb_row(dtype: u32, eb: &[u8], tok: u32, h: usize, x: &mut [f32]) {
    let (sz, blk) = gguf::block_bytes(dtype);
    let (sz, blk) = (sz as usize, blk as usize);
    let base = tok as usize * (h / blk * sz);
    for q in 0..h / blk {
        quant::deq_row_into(dtype, &eb[base + q * sz..base + (q + 1) * sz], &mut x[q * blk..(q + 1) * blk]);
    }
}

/// Exact-production-path stage dump for toks[0..n] at pos 0.. (layer by layer, per-token).
fn dump_toks(m: &Model, toks: &[u32], caches: &mut [Cache], tb: &mut TmpB) -> Vec<f32> {
    let n = toks.len();
    assert!(n > 0 && n <= tb.ncap);
    let h = m.hidden;
    let d = m.head_dim;
    let qd = m.n_head * d;
    let kvd = m.n_kv * d;
    let emb = m.g.tensors.get("token_embd.weight").expect("no emb");
    let eb = m.g.raw(emb);
    for (i, &tok) in toks.iter().enumerate() {
        deq_emb_row(emb.dtype, eb, tok, h, &mut tb.x[i * h..(i + 1) * h]);
        dumprms(&format!("T{} emb", i), &tb.x[i * h..(i + 1) * h]);
    }
    for l in 0..m.n_layer {
        let L = &m.ln[l];
        let nw = m.norm_w(&L.an);
        for i in 0..n {
            rmsnorm(&tb.x[i * h..(i + 1) * h], &nw, m.eps, &mut tb.h1[i * h..(i + 1) * h]);
        }
        m.mat3_opt_bias_batch(&L.q, &L.k, &L.v, &tb.h1[..n * h], n, &mut tb.q[..n * qd], &mut tb.k[..n * kvd], &mut tb.v[..n * kvd]);
        if m.qk_norm {
            let qn = m.norm_w(&L.qn);
            let kn = m.norm_w(&L.kn);
            for i in 0..n {
                for hh in 0..m.n_head {
                    let off = i * qd + hh * d;
                    let mut s = 0.0f32;
                    for k in 0..d {
                        s += tb.q[off + k] * tb.q[off + k];
                    }
                    let inv = 1.0 / ((s / d as f32 + m.eps).sqrt());
                    for k in 0..d {
                        tb.q[off + k] *= inv * qn[k];
                    }
                }
                for hh in 0..m.n_kv {
                    let off = i * kvd + hh * d;
                    let mut s = 0.0f32;
                    for k in 0..d {
                        s += tb.k[off + k] * tb.k[off + k];
                    }
                    let inv = 1.0 / ((s / d as f32 + m.eps).sqrt());
                    for k in 0..d {
                        tb.k[off + k] *= inv * kn[k];
                    }
                }
            }
        }
        let scale = 1.0 / (d as f32).sqrt();
        let rep = m.n_head / m.n_kv;
        let c = &mut caches[l];
        for i in 0..n {
            rope_yarn_apply(&mut tb.q[i * qd..(i + 1) * qd], i, d, m.n_head, m);
            rope_yarn_apply(&mut tb.k[i * kvd..(i + 1) * kvd], i, d, m.n_kv, m);
            cache_put(c, i, &tb.k[i * kvd..(i + 1) * kvd], &tb.v[i * kvd..(i + 1) * kvd]);
            for hh in 0..m.n_head {
                let kh = hh / rep;
                let mut mx = f32::NEG_INFINITY;
                for j in 0..=i {
                    let mut s = 0.0f32;
                    for k in 0..d {
                        s += tb.q[i * qd + hh * d + k] * kget(c, j, kh * d + k);
                    }
                    s *= scale;
                    tb.sc[j] = s;
                    if s > mx {
                        mx = s;
                    }
                }
                let mut psum = 0.0f32;
                for j in 0..=i {
                    let e = (tb.sc[j] - mx).exp();
                    tb.sc[j] = e;
                    psum += e;
                }
                for k in 0..d {
                    let mut s = 0.0f32;
                    for j in 0..=i {
                        s += tb.sc[j] * vget(c, j, kh * d + k);
                    }
                    tb.o[i * qd + hh * d + k] = s / psum;
                }
            }
            dumprms(&format!("T{} L{} q", i, l), &tb.q[i * qd..(i + 1) * qd]);
            dumprms(&format!("T{} L{} o", i, l), &tb.o[i * qd..(i + 1) * qd]);
        }
        m.mat_batch(&L.o, &tb.o[..n * qd], n, &mut tb.h2[..n * h]);
        for i in 0..n * h {
            tb.x[i] += tb.h2[i];
        }
        for i in 0..n {
            dumprms(&format!("T{} L{} xa", i, l), &tb.x[i * h..(i + 1) * h]);
        }
        let nw2 = m.norm_w(&L.ff);
        for i in 0..n {
            rmsnorm(&tb.x[i * h..(i + 1) * h], &nw2, m.eps, &mut tb.h1[i * h..(i + 1) * h]);
        }
        m.mat2_batch(&L.gate, &L.up, &tb.h1[..n * h], n, &mut tb.g[..n * m.ff], &mut tb.u[..n * m.ff]);
        for i in 0..n {
            let base = i * m.ff;
            dumprms(&format!("T{} L{} h1", i, l), &tb.h1[i * h..(i + 1) * h]);
            dumprms(&format!("T{} L{} gate", i, l), &tb.g[base..base + m.ff]);
            dumprms(&format!("T{} L{} up", i, l), &tb.u[base..base + m.ff]);
            silu(&mut tb.g[base..base + m.ff]);
            for k in 0..m.ff {
                tb.g[base + k] *= tb.u[base + k];
            }
            dumprms(&format!("T{} L{} g", i, l), &tb.g[base..base + m.ff]);
        }
        m.mat_batch(&L.down, &tb.g[..n * m.ff], n, &mut tb.h2[..n * h]);
        for i in 0..n * h {
            tb.x[i] += tb.h2[i];
        }
        for i in 0..n {
            dumprms(&format!("T{} L{} xm", i, l), &tb.x[i * h..(i + 1) * h]);
        }
    }
    let nw3 = m.norm_w("output_norm.weight");
    let mut h1 = vec![0f32; h];
    rmsnorm(&tb.x[(n - 1) * h..n * h], &nw3, m.eps, &mut h1);
    let rows = emb.dims[1] as usize;
    let cols = emb.dims[0] as usize;
    let mut logits = vec![0f32; rows];
    quant::gemv_mt(eb, emb.dtype, rows, cols, &h1, &mut logits, &m.pool);
    logits
}

fn repl(m: &Model, bpe: &tok::Bpe, caches: &mut [Cache], tmp: &mut Tmp, max_pos: usize) {
    use std::io::{BufRead, Write};
    const CYA: &str = "\x1b[36m";
    const GRN: &str = "\x1b[32m";
    const DIM: &str = "\x1b[2m";
    const BLD: &str = "\x1b[1m";
    const OFF: &str = "\x1b[0m";
    const RULE: &str = "----------------------------------------";
    let mut samp = tools::Samp::from_env();
    let mut rng = tools::Rng::new();
    let mut tools_on = std::env::var("Glen_TOOLS").map(|v| v != "0").unwrap_or(true);
    println!("{DIM}::::::::::::::::::::::::::::::::::::::::{OFF}");
    println!("{BLD}{CYA}  ____ _            {OFF}{BLD}///{OFF}");
    println!("{BLD}{CYA} / ___| | ___ _ __  {OFF}{BLD}//{OFF}");
    println!("{BLD}{CYA}| |  _| |/ _ \\ '_ \\ {OFF}{BLD}//{OFF}");
    println!("{BLD}{CYA}| |_| | |  __/ | | |{OFF}{BLD}//{OFF}");
    println!("{BLD}{CYA} \\____|_|\\___|_| |_|{OFF}{BLD}//{OFF}");
    println!("{DIM}local AI engine for low end devices{OFF}");
    println!("{DIM}::::::::::::::::::::::::::::::::::::::::{OFF}");
    println!("{DIM}type /help for commands, /quit to exit{OFF}");
    let llama = m.g.arch == "llama";
    let base = "You are Glen, a local AI engine on the user's phone. Answer directly and briefly.";
    let inner = if tools_on { format!("{}\n{}", base, tools::TOOLS_HINT) } else { base.to_string() };
    let sys_txt = if llama {
        format!("<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{}<|eot_id|>", inner)
    } else if tools_on {
        format!("<|im_start|>system\n{}\n{}<|im_end|>\n", base, tools::TOOLS_HINT)
    } else {
        format!("<|im_start|>system\n{}<|im_end|>\n", base)
    };
    let mut sys_ids = tok::encode(bpe, &sys_txt);
    if llama {
        sys_ids.insert(0, bpe.bos);
    }
    let end_txt = if llama { "<|eot_id|>".to_string() } else { "<|im_end|>\n".to_string() };
    let end_ids = tok::encode(bpe, &end_txt);
    let mut max_new = 512usize;
    let mut pos = 0usize;
    let mut tpb = TmpB::new(512, m.hidden, m.n_head * m.head_dim, m.n_kv * m.head_dim, m.ff, max_pos);
fn feed(m: &Model, ids: &[u32], pos: &mut usize, caches: &mut [Cache], tpb: &mut TmpB) -> Vec<f32> {
    let mut lg = vec![];
    let mut done = 0;
    while done < ids.len() {
        let end = (done + tpb.ncap).min(ids.len());
        lg = forward_batch(m, &ids[done..end], *pos + done, caches, tpb, m.n_layer);
        done = end;
    }
    *pos += ids.len();
    lg
}
    let t0 = Instant::now();
    feed(m, &sys_ids, &mut pos, caches, &mut tpb);
    let mname: String = match m.g.kv.get("general.name") {
        Some(gguf::Kv::Str(n)) => n.clone(),
        _ => m.g.arch.clone(),
    };
    let l1 = format!("Glen | {} | ctx {} | ready {:.1}s", mname, max_pos, t0.elapsed().as_secs_f64());
    println!("+{:-<48}+", "");
    println!("| {:46} |", &l1[..l1.len().min(46)]);
    println!("| {:46} |", samp.desc());
    println!("+{:-<48}+", "");
    println!("{DIM}First chat? Try: \"What is 2+2? Answer in one sentence.\"{OFF}");
    println!("{DIM}/new fresh chat   /len N reply length   /tools on/off   /quit exit{OFF}");
    // Full transcript of fed token ids: enables context compaction (drop oldest turns,
    // wipe KV, re-prefill) so long back-to-back chats survive a full window.
    let mut history: Vec<u32> = sys_ids.clone();
    let stdin = std::io::stdin();
    print!("{GRN}you>{OFF} ");
    std::io::stdout().flush().unwrap();
    for l in stdin.lock().lines() {
        let msg = l.unwrap_or_default();
        let msg = msg.trim().to_string();
        if msg == "/quit" || msg == "/q" || msg == "/exit" {
            println!("bye.");
            break;
        }
        if msg == "/new" || msg == "/reset" {
            for c in caches.iter_mut() {
                c.k.fill(0.0);
                c.v.fill(0.0);
                c.kq.fill(0);
                c.kd.fill(0.0);
                c.vq.fill(0);
                c.vd.fill(0.0);
            }
            pos = 0;
            feed(m, &sys_ids, &mut pos, caches, &mut tpb);
            history = sys_ids.clone();
            println!("(fresh chat)");
            print!("{GRN}you>{OFF} ");
            std::io::stdout().flush().unwrap();
            continue;
        }
        if msg.starts_with('/') {
            let mut it = msg[1..].splitn(2, ' ');
            let cmd = it.next().unwrap_or("");
            let arg = it.next().unwrap_or("").trim();
            match cmd {
                "temp" => {
                    if let Ok(t) = arg.parse::<f32>() {
                        samp.temp = t;
                    }
                    println!("temp={}", samp.temp);
                }
                "topk" => {
                    if let Ok(k) = arg.parse::<usize>() {
                        samp.top_k = k;
                    }
                    println!("top_k={}", samp.top_k);
                }
                "topp" => {
                    if let Ok(p) = arg.parse::<f32>() {
                        samp.top_p = p;
                    }
                    println!("top_p={}", samp.top_p);
                }
                "rep" => {
                    if let Ok(r) = arg.parse::<f32>() {
                        samp.repeat = r;
                    }
                    println!("repeat={}", samp.repeat);
                }
                "len" => {
                    if let Ok(n) = arg.parse::<usize>() {
                        max_new = n.clamp(16, 1024);
                    }
                    println!("max_new={}", max_new);
                }
                "tools" => {
                    if arg == "on" {
                        tools_on = true;
                    } else if arg == "off" {
                        tools_on = false;
                    }
                    println!("tools {}", if tools_on { "on" } else { "off" });
                }
                "samp" => {
                    println!("{} | tools {}", samp.desc(), if tools_on { "on" } else { "off" });
                }
                "help" | "h" | "?" => {
                    println!("commands: /new reset | /quit exit | /temp X | /topk N | /topp X | /rep X | /len N | /tools on|off | /samp show");
                    println!("tools: <call>calc EXPR</call> or <call>date</call>");
                }
                _ => {
                    println!("unknown command. /help lists commands.");
                }
            }
            print!("{GRN}you>{OFF} ");
            std::io::stdout().flush().unwrap();
            continue;
        }
        if msg.is_empty() {
            print!("{GRN}you>{OFF} ");
            std::io::stdout().flush().unwrap();
            continue;
        }
        let chunk = if llama {
            format!("<|start_header_id|>user<|end_header_id|>\n\n{}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n", msg)
        } else {
            format!("<|im_start|>user\n{}<|im_end|>\n<|im_start|>assistant\n", msg)
        };
        let mut ids = tok::encode(bpe, &chunk);
        // Long-chat survival: if this turn would overflow the window, compact:
        // keep sys + the most recent tail that fits, wipe KV, re-prefill. Oldest
        // turns are forgotten, the chat continues instead of refusing.
        if pos + ids.len() + max_new + 8 > max_pos {
            let room = max_pos.saturating_sub(max_new + 8 + sys_ids.len() + ids.len());
            let keep = room.min(history.len().saturating_sub(sys_ids.len()));
            let tail: Vec<u32> = history[history.len() - keep..].to_vec();
            let dropped = history.len().saturating_sub(sys_ids.len() + keep);
            for c in caches.iter_mut() {
                c.k.fill(0.0);
                c.v.fill(0.0);
                c.kq.fill(0);
                c.kd.fill(0.0);
                c.vq.fill(0);
                c.vd.fill(0.0);
            }
            pos = 0;
            history.clear();
            feed(m, &sys_ids, &mut pos, caches, &mut tpb);
            history.extend_from_slice(&sys_ids);
            feed(m, &tail, &mut pos, caches, &mut tpb);
            history.extend_from_slice(&tail);
            println!("(context compacted: kept last {} tokens, forgot {})", keep, dropped);
        }
        // Pathological single message bigger than the whole window: keep its tail.
        if ids.len() + max_new + 8 > max_pos {
            let fit = max_pos - max_new - 8;
            ids = ids[ids.len() - fit..].to_vec();
        }
        let mut logits = feed(m, &ids, &mut pos, caches, &mut tpb);
        history.extend_from_slice(&ids);
        let t_turn = Instant::now();
        let mut cur: &[f32] = &logits;
        println!("{DIM}{RULE}{OFF}");
        print!("{BLD}{CYA}Glen>{OFF} ");
        std::io::stdout().flush().unwrap();
        let mut gen = 0usize;
        let mut hist: Vec<u32> = vec![];
        let mut resp = String::new();
        let mut calls = 0usize;
        let mut stop = false;
        while !stop && gen < max_new + 64 && pos < max_pos - 4 {
            let nx = tools::sample(&mut rng, cur, &hist, &samp);
            if nx == bpe.eos {
                break;
            }
            let piece = tok::decode(bpe, &[nx]);
            print!("{}", piece);
            std::io::stdout().flush().unwrap();
            resp.push_str(&piece);
            hist.push(nx);
            history.push(nx);
            cur = forward(m, nx, pos, caches, tmp, m.n_layer, false);
            pos += 1;
            gen += 1;
            if gen >= max_new {
                stop = true;
            }
            if tools_on {
                if let Some((name, args)) = tools::extract_call(&resp) {
                    if calls >= 2 {
                        stop = true;
                        continue;
                    }
                    let out = tools::builtin(&name, &args);
                    println!("\n[tool {} → {}]", name, out);
                    if let Some(a) = resp.find("<call>") {
                        if let Some(b) = resp[a..].find("</call>") {
                            let end = a + b + 7;
                            resp.replace_range(a..end, "[tool used]");
                        }
                    }
                    let tool_chunk = if llama {
                        format!("<|start_header_id|>user<|end_header_id|>\n\nTool {} returned: {}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n", name, out)
                    } else {
                        format!("<|im_start|>user\nTool {} returned: {}\n<|im_end|>\n<|im_start|>assistant\n", name, out)
                    };
                    let tids = tok::encode(bpe, &tool_chunk);
                    if pos + tids.len() + 8 > max_pos {
                        stop = true;
                    } else {
                        logits = feed(m, &tids, &mut pos, caches, &mut tpb);
                        history.extend_from_slice(&tids);
                        cur = &logits;
                        calls += 1;
                    }
                }
            }
        }
        println!();
        let dt = t_turn.elapsed().as_secs_f64();
        println!("{DIM}[{} tokens in {:.1}s, {:.1} tok/s, ctx {}/{}]{OFF}", gen, dt, gen as f64 / dt.max(1e-9), pos, max_pos);
        feed(m, &end_ids, &mut pos, caches, &mut tpb);
        history.extend_from_slice(&end_ids);
        print!("{GRN}you>{OFF} ");
        std::io::stdout().flush().unwrap();
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(|s| s.as_str()) == Some("--version") {
        println!("Glen 0.1.0");
        return;
    }
    if args.get(1).map(|s| s.as_str()) == Some("--help") {
        println!("Glen 0.1.0, local AI engine for low end devices");
        println!("usage:");
        println!("  Glen                 persistent chat, /quit exits");
        println!("  Glen --chat          same thing, explicit");
        println!("  Glen \"PROMPT\"        one shot answer and exit");
        println!("  Glen --serve [PORT]  OpenAI compatible local server (default 8080)");
        println!("  Glen --dump1 TOK     debug: top 5 logits after one token");
        println!("  Glen --bench         debug: matmul microbench");
        println!("  Glen --ppl FILE      debug: perplexity over a text file");
        println!("env: Glen_MODEL path override, Glen_THREADS 1..16, Glen_VERBOSE=1, Glen_TOOLS=0,");
        println!("     Glen_CTX tokens (default 2048), Glen_KVF32=1 for f32 KV cache");
        return;
    }
    let user = args.get(1).map(|s| s.as_str()).unwrap_or("What is 2+2?");
    let n_new: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(12);
    let max_layer_arg: usize = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(0);
    let trace = args.get(4).map(|s| s == "trace").unwrap_or(false);
    let verbose = std::env::var("Glen_VERBOSE").is_ok();
    macro_rules! vprintln { ($($t:tt)*) => { if verbose { println!($($t)*) } } }
    // A nervous system that can say no.
    //
    // Loading a model is the most expensive thing this program does: hundreds of
    // megabytes of weights into RAM, sustained CPU for seconds, and on a phone
    // that is the moment the device is most likely to be hot or near flat. So
    // the check goes here, before any of it, where refusing costs nothing.
    //
    // The contract with axonspark is its exit code and nothing else: 0 allows,
    // 2 refuses. A subprocess and a status code, deliberately, because a
    // nervous system that had to be linked in to be consulted would be a second
    // thing to keep in step.
    //
    // Two ways it can fail to answer, handled differently on purpose. A real
    // refusal is fatal. An unreachable guard is loud but not fatal: a missing
    // install is a packaging problem, not a reason to refuse every run, and a
    // guard that could brick the engine when it breaks would be worse than no
    // guard.
    //
    // GLEN_GUARD=0 opts out entirely, for benchmarking where a refusal would
    // corrupt the measurement.
    if std::env::var("GLEN_GUARD").as_deref() != Ok("0") {
        if let Some(r) = guard::check() {
            if r.unreachable {
                eprintln!("Glen: guard unavailable, continuing. {}", r.reason);
            } else {
                eprintln!("Glen: not starting. {}", r.reason);
                eprintln!(
                    "Glen: wait for the device to cool, or GLEN_GUARD=0 to start anyway."
                );
                std::process::exit(3);
            }
        }
    }

    println!("Loading model...");
    vprintln!("max_layer={} trace={}", max_layer_arg, trace);
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let def = format!("{}/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf", home);
    let path = std::env::var("Glen_MODEL").unwrap_or(def);
    let t0 = Instant::now();
    let g = gguf::open(&path);
    vprintln!("load+parse {:.1}ms arch={} data_start={}", t0.elapsed().as_secs_f64() * 1e3, g.arch, g.data_start);
    let a = &g.arch;
    let llama = a.as_str() == "llama";
    let p = |k: &str| format!("{}.{}", a, k);
    let neox = args.get(5).map(|s| s.as_str()) == Some("neox") || llama;
    vprintln!("rope mode: {}", if neox { "neox" } else { "normal" });
    let qk_norm = g.tensors.contains_key("blk.0.attn_q_norm.weight") && std::env::var("Glen_NOQKNORM").is_err();
    let scale_type = match g.kv.get(&p("rope.scaling.type")) {
        Some(gguf::Kv::Str(s)) => s.clone(),
        _ => String::new(),
    };
    let yarn = scale_type == "yarn" && std::env::var("Glen_NOYARN").is_err();
    let rope_factor = g.f32(&p("rope.scaling.factor"), 1.0);
    let n_ctx_orig = g.u32(&p("rope.scaling.original_context_length"), 0) as f32;
    let n_dims = {
        let kl = g.u32(&p("attention.key_length"), 0) as f32;
        if kl > 0.0 {
            kl
        } else {
            (g.u32(&p("embedding_length"), 896) / g.u32(&p("attention.head_count"), 14).max(1)) as f32
        }
    };
    let freq_scale = if yarn && rope_factor > 1.0 { 1.0 / rope_factor } else { 1.0 };
    let ext_factor = if yarn { 1.0 } else { 0.0 };
    let mscale = if yarn { 1.0 + 0.1 * rope_factor.ln() } else { 1.0 };
    let (corr_lo, corr_hi) = if yarn && n_ctx_orig > 0.0 {
        let base_ln = g.f32(&p("rope.freq_base"), 1000000.0).ln();
        let corr = |beta: f32| n_dims * (n_ctx_orig / (beta * 2.0 * std::f32::consts::PI)).ln() / (2.0 * base_ln);
        (corr(32.0).floor().max(0.0), corr(1.0).ceil().min(n_dims - 1.0))
    } else {
        (0.0, 0.0)
    };
    vprintln!("qk_norm={} yarn={} factor={} mscale={:.4} corr=[{},{}]", qk_norm, yarn, rope_factor, mscale, corr_lo, corr_hi);
    let hd = {
        let kl = g.u32(&p("attention.key_length"), 0) as usize;
        if kl > 0 {
            kl
        } else {
            (g.u32(&p("embedding_length"), 896) / g.u32(&p("attention.head_count"), 14).max(1)) as usize
        }
    };
    let m = Model {
        n_layer: g.u32(&p("block_count"), 24) as usize,
        hidden: g.u32(&p("embedding_length"), 896) as usize,
        n_head: g.u32(&p("attention.head_count"), 14) as usize,
        n_kv: g.u32(&p("attention.head_count_kv"), 2) as usize,
        ff: g.u32(&p("feed_forward_length"), 4864) as usize,
        head_dim: 0,
        eps: g.f32(&p("attention.layer_norm_rms_epsilon"), 1e-6),
        theta: g.f32(&p("rope.freq_base"), 1000000.0),
        neox,
        eos: 151645,
        fb: HashMap::new(),
        ku: HashMap::new(),
        ln: vec![],
        has_bias: false,
        exact: std::env::var("Glen_EXACT").is_ok(),
        use_ku: std::env::var("Glen_NOKU").is_err(),
        qk_norm,
        yarn,
        freq_scale,
        ext_factor,
        mscale,
        corr_lo,
        corr_hi,
        pool: quant::Pool::new(),
        g,
    };
    let mut fb: HashMap<String, Vec<f32>> = HashMap::new();
    for (name, t) in m.g.tensors.iter() {
        if t.dtype == 0 && t.dims.len() == 1 {
            fb.insert(name.clone(), quant::dequant_all(m.g.raw(t), 0, t.ne as usize));
        }
    }
    vprintln!("cached {} F32 1-D tensors (norms+biases)", fb.len());
    let tku = std::time::Instant::now();
    let mut ku: HashMap<String, quant::KU> = HashMap::new();
    let mut ku_bytes = 0usize;
    let mut ku_skip = 0usize;
    let ku_budget: usize = std::env::var("Glen_KU_MB").ok().and_then(|v| v.parse().ok()).unwrap_or(192) * 1_000_000;
    for (name, t) in m.g.tensors.iter() {
        if (t.dtype == 12 || t.dtype == 14) && t.dims.len() == 2 {
            let rows = t.dims[1] as usize;
            let cols = t.dims[0] as usize;
            if ku_bytes + rows * cols * 4 > ku_budget {
                ku_skip += 1;
                continue;
            }
            let u = quant::unpack_ku(t.dtype, m.g.raw(t), rows, cols);
            ku_bytes += u.bytes();
            ku.insert(name.clone(), u);
        }
    }
    vprintln!("unpacked {} K-quant tensors ({:.1}MB, skipped {}) in {:.2}s", ku.len(), ku_bytes as f64 / 1e6, ku_skip, tku.elapsed().as_secs_f64());
    let mut ln: Vec<LNames> = Vec::with_capacity(m.n_layer);
    for l in 0..m.n_layer {
        let pre = format!("blk.{}.", l);
        ln.push(LNames {
            q: pre.clone() + "attn_q.weight",
            k: pre.clone() + "attn_k.weight",
            v: pre.clone() + "attn_v.weight",
            qb: pre.clone() + "attn_q.bias",
            kb: pre.clone() + "attn_k.bias",
            vb: pre.clone() + "attn_v.bias",
            o: pre.clone() + "attn_output.weight",
            gate: pre.clone() + "ffn_gate.weight",
            up: pre.clone() + "ffn_up.weight",
            down: pre.clone() + "ffn_down.weight",
            an: pre.clone() + "attn_norm.weight",
            ff: pre.clone() + "ffn_norm.weight",
            qn: pre.clone() + "attn_q_norm.weight",
            kn: pre + "attn_k_norm.weight",
        });
    }
    let has_bias = m.g.tensors.keys().any(|k| k.ends_with(".bias"));
    vprintln!("layer names prebuilt ({}), has_bias={}", ln.len(), has_bias);
    let m = Model { head_dim: hd, fb, ku, ln, has_bias, ..m };
    let max_layer = if max_layer_arg == 0 { m.n_layer } else { max_layer_arg };
    vprintln!("cfg L={} H={} heads={} kv={} ff={} eps={} theta={} max_layer={}", m.n_layer, m.hidden, m.n_head, m.n_kv, m.ff, m.eps, m.theta, max_layer);
    let bpe = tok::build(&m.g);
    vprintln!("tokenizer ready, eos={} bos={}", bpe.eos, bpe.bos);
    // round-trip check
    let rt = tok::encode(&bpe, "Hello, world!");
    let back = tok::decode(&bpe, &rt);
    vprintln!("tok round-trip: {:?} -> {}", rt, back);
    assert_eq!(back, "Hello, world!", "tokenizer mismatch");

    let prompt = if llama {
        format!("<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\nYou are Glen, a local AI engine on the user's phone. Answer directly and briefly.<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n", user)
    } else {
        format!("<|im_start|>system\nYou are Glen, a local AI engine on the user's phone. Answer directly and briefly.<|im_end|>\n<|im_start|>user\n{}<|im_end|>\n<|im_start|>assistant\n", user)
    };
    let mut ids = tok::encode(&bpe, &prompt);
    if llama {
        ids.insert(0, bpe.bos);
    }
    vprintln!("prompt {} chars -> {} tokens", prompt.len(), ids.len());
    vprintln!("prompt ids: {:?}", ids);
    vprintln!("prompt decode-back: {}", tok::decode(&bpe, &ids));

    let max_pos: usize = std::env::var("Glen_CTX").ok().and_then(|v| v.parse().ok()).unwrap_or(2048).clamp(256, 32768);
    let kvq8 = std::env::var("Glen_KVF32").is_err();
    vprintln!("ctx={} kv_q8={}", max_pos, kvq8);
    let kv_dim = m.n_kv * hd;
    let mut caches: Vec<Cache> = (0..m.n_layer).map(|_| cache_new(max_pos, kv_dim, kvq8)).collect();
    let mut tmp = Tmp {
        x: vec![0.0; m.hidden],
        log: vec![0.0; m.g.tensors.get("token_embd.weight").map(|t| t.dims[1] as usize).unwrap_or(151936)],
        rc: vec![(0.0, 0.0); hd / 2],
        h1: vec![0.0; m.hidden],
        h2: vec![0.0; m.hidden.max(m.ff)],
        q: vec![0.0; m.n_head * hd],
        k: vec![0.0; m.n_kv * hd],
        v: vec![0.0; m.n_kv * hd],
        o: vec![0.0; m.n_head * hd],
        g: vec![0.0; m.ff],
        u: vec![0.0; m.ff],
        sc: vec![0.0; max_pos],
    };
    // h2 reused for attn_out (hidden) and ffn_down (hidden): size max(hidden, ff)? ffn_down out is hidden. ok hidden suffice; allocate hidden
    tmp.h2 = vec![0.0; m.hidden];

    if user == "--serve" {
        let port: u16 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(8080);
        serve::run(&m, &bpe, &mut caches, &mut tmp, max_pos, port);
        return;
    }

    if user == "--ppl" {
        let fpath = args.get(2).map(|s| s.as_str()).unwrap_or("");
        let txt = std::fs::read_to_string(fpath).expect("read ppl file");
        let pids = tok::encode(&bpe, &txt);
        let n = pids.len().min(max_pos - 1);
        println!("ppl tokens: {} (capped {})", pids.len(), n);
        let mut sum = 0f64;
        let mut cnt = 0usize;
        let t0p = Instant::now();
        for i in 0..n {
            let lg = forward(&m, pids[i], i, &mut caches, &mut tmp, max_layer, false);
            if i + 1 < n {
                let nx = pids[i + 1] as usize;
                let mx = lg.iter().fold(f32::NEG_INFINITY, |a, &b| a.max(b));
                let mut s = 0f32;
                for &v in lg {
                    s += (v - mx).exp();
                }
                sum += ((lg[nx] - mx) - s.ln()) as f64;
                cnt += 1;
            }
            if (i + 1) % 64 == 0 {
                println!("  ppl {}/{} ({:.1}s)", i + 1, n, t0p.elapsed().as_secs_f64());
            }
        }
        println!("PPL over {} tokens: {:.4}", cnt, (-sum / cnt as f64).exp());
        return;
    }
    if user == "--dump1" {
        let t0: u32 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(9707);
        let mut toks = vec![t0];
        if let Some(s) = args.get(3) {
            if let Ok(t) = s.parse::<u32>() {
                toks.push(t);
            }
        }
        let n = toks.len();
        let mut dcaches: Vec<Cache> = (0..m.n_layer).map(|_| cache_new(n, kv_dim, false)).collect();
        let mut dtb = TmpB::new(n, m.hidden, m.n_head * hd, kv_dim, m.ff, n);
        let lg = dump_toks(&m, &toks, &mut dcaches, &mut dtb);
        let mut top: Vec<(usize, f32)> = lg.iter().enumerate().map(|(i, &v)| (i, v)).collect();
        top.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        println!("dump1 top5: {:?}", top[..5].iter().map(|(i, v)| (*i, *v)).collect::<Vec<_>>());
        return;
    }
    if user == "--bench" {
        let cols = 896usize;
        let x: Vec<f32> = (0..cols).map(|i| i as f32 * 0.001 - 0.45).collect();
        let mut y = vec![0f32; 4864];
        for _ in 0..3 {
            m.mat("blk.0.ffn_gate.weight", &x, &mut y);
        }
        let t0 = Instant::now();
        let it = 20;
        for _ in 0..it {
            m.mat("blk.0.ffn_gate.weight", &x, &mut y);
        }
        println!("bench gate4864x896 Q5_0: {:.2}ms/call over {} iters", t0.elapsed().as_secs_f64() * 1e3 / it as f64, it);
        let kvd1 = m.n_kv * m.head_dim;
        let mut bcaches: Vec<Cache> = (0..m.n_layer).map(|_| cache_new(8, kvd1, false)).collect();
        let mut btmp = Tmp { x: vec![0.0; m.hidden], log: vec![0.0; m.g.tensors.get("token_embd.weight").map(|t| t.dims[1] as usize).unwrap_or(151936)], rc: vec![(0.0, 0.0); m.head_dim / 2], h1: vec![0.0; m.hidden], h2: vec![0.0; m.hidden.max(m.ff)], q: vec![0.0; m.n_head * m.head_dim], k: vec![0.0; kvd1], v: vec![0.0; kvd1], o: vec![0.0; m.n_head * m.head_dim], g: vec![0.0; m.ff], u: vec![0.0; m.ff], sc: vec![0.0; 8] };
        let t1 = Instant::now();
        let lg = forward(&m, 9707, 0, &mut bcaches, &mut btmp, m.n_layer, false);
        println!("bench 1 decode token (24L): {:.0}ms top={}", t1.elapsed().as_secs_f64() * 1e3, argmax(&lg));
        return;
    }
    if user == "--matmul" {
        let tname = args.get(2).cloned().unwrap_or_default();
        let t = m.g.tensors.get(&tname).expect("no tensor");
        if t.dims.len() == 1 {
            let v = quant::dequant_all(m.g.raw(t), t.dtype, t.ne as usize);
            let mut s = 0.0f64;
            for &x in &v {
                s += x as f64 * x as f64;
            }
            println!("VEC {} dtype={} len={} rms={:.6} f8={:?}", tname, t.dtype, v.len(), ((s / v.len() as f64).sqrt()) as f32, &v[..8.min(v.len())]);
            return;
        }
        let cols = t.dims[0] as usize;
        let rows = t.dims[1] as usize;
        let x: Vec<f32> = (0..cols).map(|i| i as f32 * 0.001 - 0.45).collect();
        let mut y = vec![0f32; rows];
        m.mat(&tname, &x, &mut y);
        println!("MATMUL {} dtype={} rows={} cols={} ysum={:.6}", tname, t.dtype, rows, cols, y.iter().sum::<f32>());
        for i in 0..rows.min(8) {
            println!("y[{}]={:.6}", i, y[i]);
        }
        return;
    }
    if user == "--chat" || args.len() < 2 {
        repl(&m, &bpe, &mut caches, &mut tmp, max_pos);
        return;
    }
    let t1 = Instant::now();
    let mut logits = vec![];
    let mut tpb = TmpB::new(256, m.hidden, m.n_head * hd, kv_dim, m.ff, max_pos);
    let mut done = 0usize;
    while done < ids.len() {
        let end = (done + 256).min(ids.len());
        logits = forward_batch(&m, &ids[done..end], done, &mut caches, &mut tpb, max_layer);
        done = end;
        println!("  prefill {}/{}", done, ids.len());
    }
    println!("prefill {} tokens {:.2}s", ids.len(), t1.elapsed().as_secs_f64());
    // sanity: top-5 of prompt-final logits
    let mut top: Vec<(usize, f32)> = logits.iter().enumerate().map(|(i, &v)| (i, v)).collect();
    top.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
    println!("top5 after prompt: {:?}", top[..5].iter().map(|(i, v)| (tok::decode(&bpe, &[*i as u32]), *v)).collect::<Vec<_>>());

    let t2 = Instant::now();
    let samp1 = tools::Samp::from_env();
    let mut rng1 = tools::Rng::new();
    let mut gen: Vec<u32> = vec![];
    let mut cur: &[f32] = &logits;
    for n in 0..n_new {
        let nx = tools::sample(&mut rng1, cur, &gen, &samp1);
        if nx == bpe.eos {
            break;
        }
        gen.push(nx);
        print!("{}", tok::decode(&bpe, &[nx]));
        use std::io::Write;
        std::io::stdout().flush().unwrap();
        let pos = ids.len() + n;
        cur = forward(&m, nx, pos, &mut caches, &mut tmp, max_layer, false);
    }
    if trace {
        println!("--- trace re-run of last prompt token ---");
        let last = *ids.last().unwrap();
        let _ = forward(&m, last, ids.len() - 1, &mut caches, &mut tmp, max_layer, true);
    }
    println!();
    let dt = t2.elapsed().as_secs_f64();
    println!("generated {} tokens in {:.2}s = {:.2} tok/s", gen.len(), dt, gen.len() as f64 / dt.max(1e-9));
    println!("full text: {}", tok::decode(&bpe, &gen));
}
