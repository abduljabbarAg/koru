// quant.rs - dequant + fused GEMV. Scalar correct everywhere; NEON for Q8_0/Q5_0 (proven in 005).
pub fn f16_to_f32(bits: u16) -> f32 {
    let s = ((bits >> 15) & 1) as u32;
    let e = ((bits >> 10) & 0x1F) as u32;
    let m = (bits & 0x3FF) as u32;
    let f: u32 = if e == 0 {
        if m == 0 {
            s << 31
        } else {
            let mut e2 = 127u32.wrapping_sub(14);
            let mut mm = m;
            while mm & 0x400 == 0 {
                mm <<= 1;
                e2 -= 1;
            }
            mm &= 0x3FF;
            (s << 31) | (e2 << 23) | (mm << 13)
        }
    } else if e == 31 {
        (s << 31) | (0xFF << 23) | (m << 13)
    } else {
        (s << 31) | ((e + 112) << 23) | (m << 13)
    };
    f32::from_bits(f)
}

fn deq_q80(b: &[u8]) -> [f32; 32] {
    let d = f16_to_f32(u16::from_le_bytes([b[0], b[1]]));
    let mut o = [0f32; 32];
    for i in 0..32 {
        o[i] = (b[2 + i] as i8 as f32) * d;
    }
    o
}
fn deq_q50(b: &[u8]) -> [f32; 32] {
    let d = f16_to_f32(u16::from_le_bytes([b[0], b[1]]));
    let qh = u32::from_le_bytes([b[2], b[3], b[4], b[5]]);
    // ggml split-half: qs[j] low nibble = element j, high nibble = element j+16.
    let mut o = [0f32; 32];
    for i in 0..16 {
        let l0 = (b[6 + i] & 0xF) | (((qh >> i) & 1) as u8) << 4;
        let l1 = (b[6 + i] >> 4) | (((qh >> (i + 16)) & 1) as u8) << 4;
        o[i] = (l0 as i32 - 16) as f32 * d;
        o[i + 16] = (l1 as i32 - 16) as f32 * d;
    }
    o
}
#[inline(always)]
/// Q2_0 g128 (Prism Bonsai): block of 128 weights, fp16 scale then 32 bytes of
/// 2-bit codes. code 0,1,2,3 maps to (-1, 0, +1, +2) * d. 34 bytes per block.
/// Note: this file uses type id 42 with the group-128 layout. Prism's fork later
/// moved group-128 to id 142, so both ids are accepted here.
fn deq_q20(b: &[u8]) -> [f32; 128] {
    let d = f16_to_f32(u16::from_le_bytes([b[0], b[1]]));
    let mut o = [0.0f32; 128];
    for j in 0..128 {
        let q = (b[2 + j / 4] >> ((j % 4) * 2)) & 3;
        o[j] = (q as f32 - 1.0) * d;
    }
    o
}

fn k4_sc_min(j: usize, s: &[u8]) -> (u8, u8) {
    if j < 4 {
        (s[j] & 63, s[j + 4] & 63)
    } else {
        (s[j + 4] & 0xF | ((s[j - 4] >> 6) << 4), s[j + 4] >> 4 | ((s[j] >> 6) << 4))
    }
}
fn deq_q4k(b: &[u8]) -> [f32; 256] {
    let d = f16_to_f32(u16::from_le_bytes([b[0], b[1]]));
    let dm = f16_to_f32(u16::from_le_bytes([b[2], b[3]]));
    let sc = &b[4..16];
    let qs = &b[16..144];
    // ggml groups 64 values per 32 bytes: low nibbles, then high nibbles of SAME bytes.
    let mut o = [0f32; 256];
    for g in 0..4 {
        let (s0, m0) = k4_sc_min(2 * g, sc);
        let (s1, m1) = k4_sc_min(2 * g + 1, sc);
        let (dl0, ml0) = (d * s0 as f32, dm * m0 as f32);
        let (dl1, ml1) = (d * s1 as f32, dm * m1 as f32);
        for l in 0..32 {
            o[g * 64 + l] = dl0 * (qs[g * 32 + l] & 0xF) as f32 - ml0;
            o[g * 64 + 32 + l] = dl1 * (qs[g * 32 + l] >> 4) as f32 - ml1;
        }
    }
    o
}
fn deq_q6k(b: &[u8]) -> [f32; 256] {
    let ql = &b[0..128];
    let qh = &b[128..192];
    let scales = &b[192..208];
    let d = f16_to_f32(u16::from_le_bytes([b[208], b[209]]));
    let mut o = [0f32; 256];
    // ggml: 128-value chunks; 4 subgroups of 32 sharing qh bytes at 2-bit lanes.
    for n in 0..256 {
        let chunk = n / 128;
        let m = n % 128;
        let t = m % 32;
        let sub = m / 32;
        let qb = chunk * 64 + t + if sub == 1 || sub == 3 { 32 } else { 0 };
        let low = (ql[qb] >> if sub >= 2 { 4 } else { 0 }) & 0xF;
        let high = (qh[chunk * 32 + t] >> (sub * 2)) & 3;
        let q = (low | (high << 4)) as i32 - 32;
        o[n] = d * (b[192 + n / 16] as i8 as f32) * q as f32;
    }
    o
}

fn gemv_scalar(w: &[u8], dtype: u32, cols: usize, x: &[f32], y: &mut [f32], r0: usize, r1: usize) {
    match dtype {
        0 => {
            let f: &[f32] = unsafe { std::slice::from_raw_parts(w.as_ptr() as *const f32, w.len() / 4) };
            for r in r0..r1 {
                        let mut s = 0.0f32;
                for c in 0..cols {
                    s += f[r * cols + c] * x[c];
                }
                y[r - r0] = s;
            }
        }
        1 => {
            for r in r0..r1 {
                        let mut s = 0.0f32;
                for c in 0..cols {
                    let v = f16_to_f32(u16::from_le_bytes([w[(r * cols + c) * 2], w[(r * cols + c) * 2 + 1]]));
                    s += v * x[c];
                }
                y[r - r0] = s;
            }
        }
        8 => {
            let nb = cols / 32;
            for r in r0..r1 {
                        let mut s = 0.0f32;
                for q in 0..nb {
                    let v = deq_q80(&w[(r * nb + q) * 34..(r * nb + q + 1) * 34]);
                    for i in 0..32 {
                        s += v[i] * x[q * 32 + i];
                    }
                }
                y[r - r0] = s;
            }
        }
        6 => {
            let nb = cols / 32;
            for r in r0..r1 {
                        let mut s = 0.0f32;
                for q in 0..nb {
                    let v = deq_q50(&w[(r * nb + q) * 22..(r * nb + q + 1) * 22]);
                    for i in 0..32 {
                        s += v[i] * x[q * 32 + i];
                    }
                }
                y[r - r0] = s;
            }
        }
        12 => {
            let nb = cols / 256;
            for r in r0..r1 {
                        let mut s = 0.0f32;
                for q in 0..nb {
                    let v = deq_q4k(&w[(r * nb + q) * 144..(r * nb + q + 1) * 144]);
                    for i in 0..256 {
                        s += v[i] * x[q * 256 + i];
                    }
                }
                y[r - r0] = s;
            }
        }
        14 => {
            let nb = cols / 256;
            for r in r0..r1 {
                        let mut s = 0.0f32;
                for q in 0..nb {
                    let v = deq_q6k(&w[(r * nb + q) * 210..(r * nb + q + 1) * 210]);
                    for i in 0..256 {
                        s += v[i] * x[q * 256 + i];
                    }
                }
                y[r - r0] = s;
            }
        }
        42 | 142 => {
            let nb = cols / 128;
            for r in r0..r1 {
                let mut s = 0.0f32;
                for q in 0..nb {
                    let v = deq_q20(&w[(r * nb + q) * 34..(r * nb + q + 1) * 34]);
                    for i in 0..128 {
                        s += v[i] * x[q * 128 + i];
                    }
                }
                y[r - r0] = s;
            }
        }
        _ => panic!("gemv dtype {}", dtype),
    }
}

#[cfg(target_arch = "aarch64")]
unsafe fn gemv_q80_neon(w: &[u8], cols: usize, x: &[f32], y: &mut [f32], r0: usize, r1: usize) {
    use std::arch::aarch64::*;
    let nb = cols / 32;
    for r in r0..r1 {
        let mut acc = vdupq_n_f32(0.0);
        for q in 0..nb {
            let base = (r * nb + q) * 34;
            let vd = vdupq_n_f32(f16_to_f32(u16::from_le_bytes([w[base], w[base + 1]])));
            for k in 0..8 {
                let mut vw = vdupq_n_f32(0.0);
                vw = vsetq_lane_f32(w[base + 2 + k * 4] as i8 as f32, vw, 0);
                vw = vsetq_lane_f32(w[base + 2 + k * 4 + 1] as i8 as f32, vw, 1);
                vw = vsetq_lane_f32(w[base + 2 + k * 4 + 2] as i8 as f32, vw, 2);
                vw = vsetq_lane_f32(w[base + 2 + k * 4 + 3] as i8 as f32, vw, 3);
                vw = vmulq_f32(vw, vd);
                acc = vfmaq_f32(acc, vw, vld1q_f32(x.as_ptr().add(q * 32 + k * 4)));
            }
        }
        *y.get_unchecked_mut(r - r0) = vaddvq_f32(acc);
    }
}

#[cfg(target_arch = "aarch64")]
unsafe fn gemv_q50_neon(w: &[u8], cols: usize, x: &[f32], y: &mut [f32], r0: usize, r1: usize) {
    use std::arch::aarch64::*;
    let nb = cols / 32;
    for r in r0..r1 {
        let mut acc = vdupq_n_f32(0.0);
        for q in 0..nb {
            let base = (r * nb + q) * 22;
            let d = f16_to_f32(u16::from_le_bytes([w[base], w[base + 1]]));
            let qh = u32::from_le_bytes([w[base + 2], w[base + 3], w[base + 4], w[base + 5]]);
            // split-half dequant to stack temp, then vector FMA (bit ops aren't SIMD-friendly here)
            let mut t = [0f32; 32];
            for i in 0..16 {
                let l0 = (w[base + 6 + i] & 0xF) | (((qh >> i) & 1) as u8) << 4;
                let l1 = (w[base + 6 + i] >> 4) | (((qh >> (i + 16)) & 1) as u8) << 4;
                t[i] = (l0 as i32 - 16) as f32 * d;
                t[i + 16] = (l1 as i32 - 16) as f32 * d;
            }
            for k in 0..8 {
                acc = vfmaq_f32(acc, vld1q_f32(t.as_ptr().add(k * 4)), vld1q_f32(x.as_ptr().add(q * 32 + k * 4)));
            }
        }
        *y.get_unchecked_mut(r - r0) = vaddvq_f32(acc);
    }
}

/// y = W x over row range [r0, r1); y is the chunk starting at r0.
fn gemv_range(w: &[u8], dtype: u32, cols: usize, x: &[f32], y: &mut [f32], r0: usize, r1: usize) {
    #[cfg(target_arch = "aarch64")]
    {
        if std::arch::is_aarch64_feature_detected!("neon") && (dtype == 8 || dtype == 6) {
            unsafe {
                if dtype == 8 {
                    gemv_q80_neon(w, cols, x, y, r0, r1);
                } else {
                    gemv_q50_neon(w, cols, x, y, r0, r1);
                }
            }
            return;
        }
    }
    gemv_scalar(w, dtype, cols, x, y, r0, r1);
}

/// y = W x, W is rows x cols (rows = dims[1], cols = dims[0]).
pub fn gemv(w: &[u8], dtype: u32, rows: usize, cols: usize, x: &[f32], y: &mut [f32]) {
    gemv_range(w, dtype, cols, x, y, 0, rows);
}

type Job = std::sync::Arc<dyn Fn(usize, usize) + Send + Sync>;

struct Inner {
    gen: u64,
    done_gen: u64,
    job: Option<Job>,
    shutdown: bool,
}

struct Shared {
    mu: std::sync::Mutex<Inner>,
    cv_s: std::sync::Condvar,
    cv_d: std::sync::Condvar,
    cursor: std::sync::atomic::AtomicUsize,
    end: std::sync::atomic::AtomicUsize,
    chunk: std::sync::atomic::AtomicUsize,
    exited: std::sync::atomic::AtomicUsize,
}

/// Persistent worker pool: spawning threads per matmul costs more than the work on Android.
pub struct Pool {
    n: usize,
    shared: std::sync::Arc<Shared>,
    handles: Option<Vec<std::thread::JoinHandle<()>>>,
}

impl Pool {
    pub fn new() -> Self {
        use std::sync::atomic::Ordering;
        let n = std::env::var("Glen_THREADS")
            .ok()
            .and_then(|v| v.parse::<usize>().ok())
            .filter(|&v| v >= 1 && v <= 16)
            .unwrap_or_else(|| std::thread::available_parallelism().map(|v| v.get().min(8)).unwrap_or(4).max(1));
        let shared = std::sync::Arc::new(Shared {
            mu: std::sync::Mutex::new(Inner { gen: 0, done_gen: 0, job: None, shutdown: false }),
            cv_s: std::sync::Condvar::new(),
            cv_d: std::sync::Condvar::new(),
            cursor: std::sync::atomic::AtomicUsize::new(0),
            end: std::sync::atomic::AtomicUsize::new(0),
            chunk: std::sync::atomic::AtomicUsize::new(128),
            exited: std::sync::atomic::AtomicUsize::new(0),
        });
        let mut handles = vec![];
        for _ in 0..n {
            let sh = shared.clone();
            handles.push(std::thread::spawn(move || {
                let mut my_gen = 0u64;
                loop {
                    let job = {
                        let mut inner = sh.mu.lock().unwrap();
                        while inner.gen == my_gen && !inner.shutdown {
                            inner = sh.cv_s.wait(inner).unwrap();
                        }
                        if inner.shutdown {
                            return;
                        }
                        my_gen = inner.gen;
                        inner.job.clone().expect("pool job")
                    };
                    let chunk = sh.chunk.load(Ordering::SeqCst);
                    loop {
                        let r0 = sh.cursor.fetch_add(chunk, Ordering::SeqCst);
                        let end = sh.end.load(Ordering::SeqCst);
                        if r0 >= end {
                            break;
                        }
                        job(r0, (r0 + chunk).min(end));
                    }
                    if sh.exited.fetch_add(1, Ordering::SeqCst) + 1 == n {
                        sh.exited.store(0, Ordering::SeqCst);
                        let mut inner = sh.mu.lock().unwrap();
                        inner.done_gen = my_gen;
                        sh.cv_d.notify_one();
                    }
                }
            }));
        }
        Pool { n, shared, handles: Some(handles) }
    }

    /// Run job over row ranges covering [0, rows). Blocks until done.
    pub fn run<F: Fn(usize, usize) + Send + Sync + 'static>(&self, rows: usize, job: F) {
        use std::sync::atomic::Ordering;
        // The old floor was a flat rows < 256, which quietly excluded the
        // narrow projections. Qwen2.5-0.5B's k and v are 2 kv heads by 64
        // dimensions, so 128 rows: those two matmuls per layer ran on one thread
        // while q, o and the ffns used all of them. The test is now on the work
        // rather than on a row count nobody can justify, and the chunk floor is
        // low enough that four threads can actually be handed a piece.
        if rows < 32 || self.n <= 1 {
            job(0, rows);
            return;
        }
        self.shared.cursor.store(0, Ordering::SeqCst);
        self.shared.end.store(rows, Ordering::SeqCst);
        self.shared.chunk.store((rows / self.n).max(16), Ordering::SeqCst);
        {
            let mut inner = self.shared.mu.lock().unwrap();
            inner.job = Some(std::sync::Arc::new(job));
            inner.gen += 1;
            self.shared.cv_s.notify_all();
        }
        {
            let mut inner = self.shared.mu.lock().unwrap();
            while inner.done_gen != inner.gen {
                inner = self.shared.cv_d.wait(inner).unwrap();
            }
            inner.job = None;
        }
    }
}

impl Drop for Pool {
    fn drop(&mut self) {
        {
            let mut inner = self.shared.mu.lock().unwrap();
            inner.shutdown = true;
            inner.gen += 1;
            self.shared.cv_s.notify_all();
        }
        for h in self.handles.take().unwrap() {
            let _ = h.join();
        }
    }
}

/// Threaded y = W x: rows split across cores.
pub fn gemv_mt(w: &[u8], dtype: u32, rows: usize, cols: usize, x: &[f32], y: &mut [f32], pool: &Pool) {
    assert!(y.len() >= rows);
    if matches!(dtype, 6 | 8 | 12 | 14 | 42 | 142) {
        let qx = quant_x(x);
        let wptr = w.as_ptr() as usize;
        let wlen = w.len();
        let yptr = y.as_mut_ptr() as usize;
        let ylen = y.len();
        pool.run(rows, move |r0: usize, r1: usize| {
            // SAFETY: run blocks until all ranges finish; ranges are disjoint rows; slices rebuilt from live refs.
            let w = unsafe { std::slice::from_raw_parts(wptr as *const u8, wlen) };
            let y = unsafe { std::slice::from_raw_parts_mut(yptr as *mut f32, ylen) };
            gemv_range_i(w, dtype, cols, &qx, &mut y[r0..r1], r0, r1);
        });
        return;
    }
    let wptr = w.as_ptr() as usize;
    let wlen = w.len();
    let xptr = x.as_ptr() as usize;
    let xlen = x.len();
    let yptr = y.as_mut_ptr() as usize;
    let ylen = y.len();
    pool.run(rows, move |r0: usize, r1: usize| {
        // SAFETY: run blocks until all ranges finish; ranges are disjoint rows; slices rebuilt from live refs.
        let w = unsafe { std::slice::from_raw_parts(wptr as *const u8, wlen) };
        let x = unsafe { std::slice::from_raw_parts(xptr as *const f32, xlen) };
        let y = unsafe { std::slice::from_raw_parts_mut(yptr as *mut f32, ylen) };
        gemv_range(w, dtype, cols, x, &mut y[r0..r1], r0, r1);
    });
}

pub fn deq_row_into(dtype: u32, blk: &[u8], o: &mut [f32]) {
    match dtype {
        8 => o.copy_from_slice(&deq_q80(blk)),
        6 => o.copy_from_slice(&deq_q50(blk)),
        12 => o.copy_from_slice(&deq_q4k(blk)),
        14 => o.copy_from_slice(&deq_q6k(blk)),
        42 | 142 => o.copy_from_slice(&deq_q20(blk)),
        _ => panic!("deq_row_into dtype {}", dtype),
    }
}

#[cfg(target_arch = "aarch64")]
unsafe fn dot_neon(a: &[f32], b: &[f32]) -> f32 {
    use std::arch::aarch64::*;
    debug_assert!(a.len() == b.len() && a.len() % 4 == 0);
    let mut acc = vdupq_n_f32(0.0);
    let n4 = a.len() / 4;
    for k in 0..n4 {
        acc = vfmaq_f32(acc, vld1q_f32(a.as_ptr().add(k * 4)), vld1q_f32(b.as_ptr().add(k * 4)));
    }
    vaddvq_f32(acc)
}

fn dot(a: &[f32], b: &[f32]) -> f32 {
    #[cfg(target_arch = "aarch64")]
    {
        if std::arch::is_aarch64_feature_detected!("neon") && a.len() % 4 == 0 {
            return unsafe { dot_neon(a, b) };
        }
    }
    let mut s = 0.0f32;
    for i in 0..a.len() {
        s += a[i] * b[i];
    }
    s
}

/// ---- int8 DOTPROD path (ggml-style): quantize activations once, integer dots ----
pub struct Qx {
    pub q: Vec<i8>,
    pub d: Vec<f32>,
    pub s: Vec<i32>,
    pub nb: usize, // 32-blocks per row
}

pub fn quant_x(x: &[f32]) -> Qx {
    quant_xn(x, 1, x.len())
}

pub fn quant_xn(xb: &[f32], n: usize, cols: usize) -> Qx {
    let nb = cols / 32;
    let mut q = vec![0i8; n * nb * 32];
    let mut d = vec![0f32; n * nb];
    let mut s = vec![0i32; n * nb];
    for bi in 0..n {
        for b in 0..nb {
            let mut amax = 0f32;
            for i in 0..32 {
                let a = xb[bi * cols + b * 32 + i].abs();
                if a > amax {
                    amax = a;
                }
            }
            let dd = if amax == 0.0 { 1.0 } else { amax / 127.0 };
            d[bi * nb + b] = dd;
            let mut sum = 0i32;
            for i in 0..32 {
                let v = (xb[bi * cols + b * 32 + i] / dd).round().clamp(-127.0, 127.0) as i8;
                q[(bi * nb + b) * 32 + i] = v;
                sum += v as i32;
            }
            s[bi * nb + b] = sum;
        }
    }
    Qx { q, d, s, nb }
}

fn vdoti(a: &[i8], b: &[i8]) -> i32 {
    debug_assert_eq!(a.len(), b.len());
    // Fast path: this crate builds with +dotprod (see .cargo/config.toml), so the
    // runtime HWCAP check runs ZERO times. Fallback keeps other-host builds working.
    #[cfg(target_feature = "dotprod")]
    {
        return unsafe { vdoti_dot(a, b) };
    }
    #[cfg(not(target_feature = "dotprod"))]
    {
        #[cfg(target_arch = "aarch64")]
        {
            if std::arch::is_aarch64_feature_detected!("dotprod") {
                return unsafe { vdoti_dot(a, b) };
            }
            if std::arch::is_aarch64_feature_detected!("neon") {
                return unsafe { vdoti_dot(a, b) };
            }
        }
        let mut s = 0i32;
        for i in 0..a.len() {
            s += a[i] as i32 * b[i] as i32;
        }
        s
    }
}

#[cfg(target_arch = "aarch64")]
#[target_feature(enable = "dotprod")]
unsafe fn vdoti_sdot(a: &[i8], b: &[i8]) -> i32 {
    use std::arch::asm;
    let n = a.len() & !15;
    let (mut ap, mut bp) = (a.as_ptr(), b.as_ptr());
    let mut rem = n;
    let mut sum: i32;
    asm!(
        "movi v0.4s, #0",
        "cbz {rem:w}, 2f",
        "1:",
        "ld1 {{ v1.16b }}, [{ap}], #16",
        "ld1 {{ v2.16b }}, [{bp}], #16",
        "sdot v0.4s, v1.16b, v2.16b",
        "subs {rem:w}, {rem:w}, #16",
        "b.ne 1b",
        "2:",
        "addv s4, v0.4s",
        "umov {s:w}, v4.s[0]",
        ap = inout(reg) ap,
        bp = inout(reg) bp,
        rem = inout(reg) rem,
        s = lateout(reg) sum,
        out("v0") _,
        out("v1") _,
        out("v2") _,
        out("v4") _,
        options(nostack, readonly)
    );
    let mut i = n;
    while i < a.len() {
        sum += *a.get_unchecked(i) as i32 * *b.get_unchecked(i) as i32;
        i += 1;
    }
    sum
}

#[cfg(target_arch = "aarch64")]
unsafe fn vdoti_dot(a: &[i8], b: &[i8]) -> i32 {
    use std::arch::aarch64::*;
    let mut acc = vdupq_n_s32(0);
    let mut i = 0;
    while i + 16 <= a.len() {
        let av = vld1q_s8(a.as_ptr().add(i));
        let bv = vld1q_s8(b.as_ptr().add(i));
        acc = vpadalq_s16(acc, vmull_s8(vget_low_s8(av), vget_low_s8(bv)));
        acc = vpadalq_s16(acc, vmull_s8(vget_high_s8(av), vget_high_s8(bv)));
        i += 16;
    }
    let mut s = vaddvq_s32(acc);
    while i < a.len() {
        s += a[i] as i32 * b[i] as i32;
        i += 1;
    }
    s
}

fn uq50(blk: &[u8]) -> ([i8; 32], f32) {
    let d = f16_to_f32(u16::from_le_bytes([blk[0], blk[1]]));
    let qh = u32::from_le_bytes([blk[2], blk[3], blk[4], blk[5]]);
    let mut t = [0i8; 32];
    for i in 0..16 {
        let l0 = (blk[6 + i] & 0xF) | (((qh >> i) & 1) as u8) << 4;
        let l1 = (blk[6 + i] >> 4) | (((qh >> (i + 16)) & 1) as u8) << 4;
        t[i] = l0 as i8 - 16;
        t[i + 16] = l1 as i8 - 16;
    }
    (t, d)
}

fn uq4k(blk: &[u8]) -> ([i8; 256], [f32; 8], [f32; 8]) {
    let d = f16_to_f32(u16::from_le_bytes([blk[0], blk[1]]));
    let dm = f16_to_f32(u16::from_le_bytes([blk[2], blk[3]]));
    let sc = &blk[4..16];
    let qs = &blk[16..144];
    let mut q = [0i8; 256];
    let mut kd = [0f32; 8];
    let mut km = [0f32; 8];
    for g in 0..4 {
        let (s0, m0) = k4_sc_min(2 * g, sc);
        let (s1, m1) = k4_sc_min(2 * g + 1, sc);
        kd[2 * g] = d * s0 as f32;
        km[2 * g] = dm * m0 as f32;
        kd[2 * g + 1] = d * s1 as f32;
        km[2 * g + 1] = dm * m1 as f32;
        for l in 0..32 {
            q[g * 64 + l] = (qs[g * 32 + l] & 0xF) as i8;
            q[g * 64 + 32 + l] = (qs[g * 32 + l] >> 4) as i8;
        }
    }
    (q, kd, km)
}

fn uq6k(blk: &[u8]) -> ([i8; 256], [f32; 16], f32) {
    let ql = &blk[0..128];
    let qh = &blk[128..192];
    let d = f16_to_f32(u16::from_le_bytes([blk[208], blk[209]]));
    let mut q = [0i8; 256];
    let mut sc = [0f32; 16];
    for i in 0..16 {
        sc[i] = blk[192 + i] as i8 as f32;
    }
    for n in 0..256 {
        let chunk = n / 128;
        let m = n % 128;
        let t = m % 32;
        let sub = m / 32;
        let qb = chunk * 64 + t + if sub == 1 || sub == 3 { 32 } else { 0 };
        let low = (ql[qb] >> if sub >= 2 { 4 } else { 0 }) & 0xF;
        let high = (qh[chunk * 32 + t] >> (sub * 2)) & 3;
        q[n] = ((low | (high << 4)) as i32 - 32) as i8;
    }
    (q, sc, d)
}

fn row_q80(wrow: &[u8], nb: usize, qx: &Qx, base: usize) -> f32 {
    let mut s = 0f32;
    for q in 0..nb {
        let dw = f16_to_f32(u16::from_le_bytes([wrow[q * 34], wrow[q * 34 + 1]]));
        let wq: &[i8] = unsafe { std::slice::from_raw_parts(wrow.as_ptr().add(q * 34 + 2) as *const i8, 32) };
        let wx = vdoti(wq, &qx.q[(base + q) * 32..(base + q + 1) * 32]);
        s += dw * qx.d[base + q] * wx as f32;
    }
    s
}

fn row_q50(wrow: &[u8], nb: usize, qx: &Qx, base: usize) -> f32 {
    let mut s = 0f32;
    for q in 0..nb {
        let (t, dw) = uq50(&wrow[q * 22..(q + 1) * 22]);
        let wx = vdoti(&t, &qx.q[(base + q) * 32..(base + q + 1) * 32]);
        s += dw * qx.d[base + q] * wx as f32;
    }
    s
}

fn row_q4k(wrow: &[u8], nb: usize, qx: &Qx, base: usize) -> f32 {
    let mut s = 0f32;
    for q in 0..nb {
        let (t, kd, km) = uq4k(&wrow[q * 144..(q + 1) * 144]);
        let bq = base + q * 8;
        for g in 0..4 {
            let wx0 = vdoti(&t[g * 64..g * 64 + 32], &qx.q[(bq + 2 * g) * 32..(bq + 2 * g + 1) * 32]);
            s += kd[2 * g] * qx.d[bq + 2 * g] * wx0 as f32 - km[2 * g] * qx.d[bq + 2 * g] * qx.s[bq + 2 * g] as f32;
            let wx1 = vdoti(&t[g * 64 + 32..g * 64 + 64], &qx.q[(bq + 2 * g + 1) * 32..(bq + 2 * g + 2) * 32]);
            s += kd[2 * g + 1] * qx.d[bq + 2 * g + 1] * wx1 as f32 - km[2 * g + 1] * qx.d[bq + 2 * g + 1] * qx.s[bq + 2 * g + 1] as f32;
        }
    }
    s
}

fn row_q6k(wrow: &[u8], nb: usize, qx: &Qx, base: usize) -> f32 {
    let mut s = 0f32;
    for q in 0..nb {
        let (t, sc, dd) = uq6k(&wrow[q * 210..(q + 1) * 210]);
        let bq = base + q * 8;
        for b in 0..8 {
            for h in 0..2 {
                let wx = vdoti(&t[b * 32 + h * 16..b * 32 + h * 16 + 16], &qx.q[(bq + b) * 32 + h * 16..(bq + b) * 32 + h * 16 + 16]);
                s += dd * sc[b * 2 + h] * qx.d[bq + b] * wx as f32;
            }
        }
    }
    s
}

fn gemv_range_i(w: &[u8], dtype: u32, cols: usize, qx: &Qx, y: &mut [f32], r0: usize, r1: usize) {
    match dtype {
        8 => {
            let nb = cols / 32;
            for r in r0..r1 {
                y[r - r0] = row_q80(&w[r * nb * 34..], nb, qx, 0);
            }
        }
        6 => {
            let nb = cols / 32;
            for r in r0..r1 {
                y[r - r0] = row_q50(&w[r * nb * 22..], nb, qx, 0);
            }
        }
        12 => {
            let nb = cols / 256;
            for r in r0..r1 {
                y[r - r0] = row_q4k(&w[r * nb * 144..], nb, qx, 0);
            }
        }
        14 => {
            let nb = cols / 256;
            for r in r0..r1 {
                y[r - r0] = row_q6k(&w[r * nb * 210..], nb, qx, 0);
            }
        }
        42 | 142 => {
            let nb = cols / 128;
            for r in r0..r1 {
                y[r - r0] = row_q20(&w[r * nb * 34..], nb, qx, 0);
            }
        }
        _ => panic!("gemv_range_i dtype {}", dtype),
    }
}

/// 2-bit code byte to four signed code values, precomputed once.
const fn make_q20_exp() -> [[i8; 4]; 256] {
    let mut t = [[0i8; 4]; 256];
    let mut i = 0;
    while i < 256 {
        t[i][0] = (i & 3) as i8;
        t[i][1] = ((i >> 2) & 3) as i8;
        t[i][2] = ((i >> 4) & 3) as i8;
        t[i][3] = ((i >> 6) & 3) as i8;
        i += 1;
    }
    t
}
static Q20_EXP: [[i8; 4]; 256] = make_q20_exp();

/// Q2_0 g128 row dot with int8 activations.
/// weight = (code - 1) * dw, activation = xq * dx, so the block dot is
/// dw * dx * (sum(code * xq) - sum(xq)), all integer except the final scale.
fn row_q20(wrow: &[u8], nb: usize, qx: &Qx, base: usize) -> f32 {
    let mut s = 0f32;
    let mut wq = [0i8; 32];
    for q in 0..nb {
        let dw = f16_to_f32(u16::from_le_bytes([wrow[q * 34], wrow[q * 34 + 1]]));
        let mut acc = 0f32;
        for sb in 0..4 {
            let codes = &wrow[q * 34 + 2 + sb * 8..q * 34 + 2 + sb * 8 + 8];
            for j in 0..8 {
                let e = Q20_EXP[codes[j] as usize];
                wq[j * 4] = e[0];
                wq[j * 4 + 1] = e[1];
                wq[j * 4 + 2] = e[2];
                wq[j * 4 + 3] = e[3];
            }
            let xb = base + q * 4 + sb;
            let dotc = vdoti(&wq, &qx.q[xb * 32..(xb + 1) * 32]);
            acc += (dotc - qx.s[xb]) as f32 * qx.d[xb];
        }
        s += dw * acc;
    }
    s
}

fn brow_q20(wrow: &[u8], nb: usize, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r: usize) {
    for bi in 0..n {
        yb[bi * rf + r] = row_q20(wrow, nb, qx, bi * qx.nb);
    }
}

/// Batched Q2_0 row: expand each 2-bit block once, dot it with every batch item.
/// Prefill reads each weight byte once instead of once per token.
fn brow_q20_multi(wrow: &[u8], nb: usize, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r: usize) {
    let mut acc = vec![0f32; n];
    let mut wq = [0i8; 32];
    for q in 0..nb {
        let dw = f16_to_f32(u16::from_le_bytes([wrow[q * 34], wrow[q * 34 + 1]]));
        for sb in 0..4 {
            let codes = &wrow[q * 34 + 2 + sb * 8..q * 34 + 2 + sb * 8 + 8];
            for j in 0..8 {
                let e = Q20_EXP[codes[j] as usize];
                wq[j * 4] = e[0];
                wq[j * 4 + 1] = e[1];
                wq[j * 4 + 2] = e[2];
                wq[j * 4 + 3] = e[3];
            }
            for bi in 0..n {
                let xb = bi * qx.nb + q * 4 + sb;
                let dotc = vdoti(&wq, &qx.q[xb * 32..(xb + 1) * 32]);
                acc[bi] += dw * (dotc - qx.s[xb]) as f32 * qx.d[xb];
            }
        }
    }
    for bi in 0..n {
        yb[bi * rf + r] = acc[bi];
    }
}

fn brow_q80(wrow: &[u8], nb: usize, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r: usize) {
    for bi in 0..n {
        let mut s = 0f32;
        let base = bi * qx.nb;
        for q in 0..nb {
            let dw = f16_to_f32(u16::from_le_bytes([wrow[q * 34], wrow[q * 34 + 1]]));
            let wq: &[i8] = unsafe { std::slice::from_raw_parts(wrow.as_ptr().add(q * 34 + 2) as *const i8, 32) };
            let wx = vdoti(wq, &qx.q[(base + q) * 32..(base + q + 1) * 32]);
            s += dw * qx.d[base + q] * wx as f32;
        }
        yb[bi * rf + r] = s;
    }
}

fn brow_q50(wrow: &[u8], nb: usize, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r: usize) {
    let mut ts = vec![([0i8; 32], 0f32); nb];
    for q in 0..nb {
        ts[q] = uq50(&wrow[q * 22..(q + 1) * 22]);
    }
    for bi in 0..n {
        let mut s = 0f32;
        let base = bi * qx.nb;
        for q in 0..nb {
            let wx = vdoti(&ts[q].0, &qx.q[(base + q) * 32..(base + q + 1) * 32]);
            s += ts[q].1 * qx.d[base + q] * wx as f32;
        }
        yb[bi * rf + r] = s;
    }
}

fn brow_q4k(wrow: &[u8], nb: usize, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r: usize) {
    let mut us: Vec<([i8; 256], [f32; 8], [f32; 8])> = vec![([0i8; 256], [0f32; 8], [0f32; 8]); nb];
    for q in 0..nb {
        us[q] = uq4k(&wrow[q * 144..(q + 1) * 144]);
    }
    for bi in 0..n {
        let mut s = 0f32;
        let bb = bi * qx.nb;
        for q in 0..nb {
            let (t, kd, km) = &us[q];
            let bq = bb + q * 8;
            for g in 0..4 {
                let wx0 = vdoti(&t[g * 64..g * 64 + 32], &qx.q[(bq + 2 * g) * 32..(bq + 2 * g + 1) * 32]);
                s += kd[2 * g] * qx.d[bq + 2 * g] * wx0 as f32 - km[2 * g] * qx.d[bq + 2 * g] * qx.s[bq + 2 * g] as f32;
                let wx1 = vdoti(&t[g * 64 + 32..g * 64 + 64], &qx.q[(bq + 2 * g + 1) * 32..(bq + 2 * g + 2) * 32]);
                s += kd[2 * g + 1] * qx.d[bq + 2 * g + 1] * wx1 as f32 - km[2 * g + 1] * qx.d[bq + 2 * g + 1] * qx.s[bq + 2 * g + 1] as f32;
            }
        }
        yb[bi * rf + r] = s;
    }
}

fn brow_q6k(wrow: &[u8], nb: usize, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r: usize) {
    let mut us: Vec<([i8; 256], [f32; 16], f32)> = vec![([0i8; 256], [0f32; 16], 0.0); nb];
    for q in 0..nb {
        us[q] = uq6k(&wrow[q * 210..(q + 1) * 210]);
    }
    for bi in 0..n {
        let mut s = 0f32;
        let bb = bi * qx.nb;
        for q in 0..nb {
            let (t, sc, dd) = &us[q];
            let bq = bb + q * 8;
            for b in 0..8 {
                for h in 0..2 {
                    let wx = vdoti(&t[b * 32 + h * 16..b * 32 + h * 16 + 16], &qx.q[(bq + b) * 32 + h * 16..(bq + b) * 32 + h * 16 + 16]);
                    s += *dd * sc[b * 2 + h] * qx.d[bq + b] * wx as f32;
                }
            }
        }
        yb[bi * rf + r] = s;
    }
}

fn gemm_batch_1i(w: &[u8], dtype: u32, cols: usize, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r0: usize, r1: usize) {
    assert_eq!(yb.len(), n * rf);
    match dtype {
        8 => {
            let nb = cols / 32;
            for r in r0..r1 {
                brow_q80(&w[r * nb * 34..], nb, qx, n, yb, rf, r);
            }
        }
        6 => {
            let nb = cols / 32;
            for r in r0..r1 {
                brow_q50(&w[r * nb * 22..], nb, qx, n, yb, rf, r);
            }
        }
        12 => {
            let nb = cols / 256;
            for r in r0..r1 {
                brow_q4k(&w[r * nb * 144..], nb, qx, n, yb, rf, r);
            }
        }
        14 => {
            let nb = cols / 256;
            for r in r0..r1 {
                brow_q6k(&w[r * nb * 210..], nb, qx, n, yb, rf, r);
            }
        }
        42 | 142 => {
            let nb = cols / 128;
            for r in r0..r1 {
                if n > 1 {
                    brow_q20_multi(&w[r * nb * 34..], nb, qx, n, yb, rf, r);
                } else {
                    brow_q20(&w[r * nb * 34..], nb, qx, n, yb, rf, r);
                }
            }
        }
        _ => panic!("gemm_batch_1i dtype {}", dtype),
    }
}

/// One thread's share of batched GEMM: rows [r0, r1), out layout [n][r1-r0].
fn gemm_batch_1(w: &[u8], dtype: u32, cols: usize, xb: &[f32], n: usize, out: &mut [f32], r0: usize, r1: usize) {
    let rr = r1 - r0;
    assert_eq!(out.len(), n * rr);
    if dtype == 0 {
        let f: &[f32] = unsafe { std::slice::from_raw_parts(w.as_ptr() as *const f32, w.len() / 4) };
        for r in r0..r1 {
            let row = &f[r * cols..(r + 1) * cols];
            for bi in 0..n {
                out[bi * rr + (r - r0)] = dot(row, &xb[bi * cols..(bi + 1) * cols]);
            }
        }
        return;
    }
    if dtype == 1 {
        let mut tmp = vec![0f32; cols];
        for r in r0..r1 {
            for c in 0..cols {
                tmp[c] = f16_to_f32(u16::from_le_bytes([w[(r * cols + c) * 2], w[(r * cols + c) * 2 + 1]]));
            }
            for bi in 0..n {
                out[bi * rr + (r - r0)] = dot(&tmp, &xb[bi * cols..(bi + 1) * cols]);
            }
        }
        return;
    }
    let (bs, be) = match dtype {
        8 => (34, 32),
        6 => (22, 32),
        12 => (144, 256),
        14 => (210, 256),
        42 | 142 => (34, 128),
        _ => panic!("gemm_batch_1 dtype {}", dtype),
    };
    let nb = cols / be;
    let mut tmp = vec![0f32; cols];
    for r in r0..r1 {
        for q in 0..nb {
            deq_row_into(dtype, &w[(r * nb + q) * bs..(r * nb + q + 1) * bs], &mut tmp[q * be..(q + 1) * be]);
        }
        for bi in 0..n {
            out[bi * rr + (r - r0)] = dot(&tmp, &xb[bi * cols..(bi + 1) * cols]);
        }
    }
}

/// One thread's share of batched GEMM writing strided into full [n][rf] output.
fn gemm_batch_1s(w: &[u8], dtype: u32, cols: usize, xb: &[f32], n: usize, yb: &mut [f32], rf: usize, r0: usize, r1: usize) {
    assert_eq!(yb.len(), n * rf);
    if dtype == 0 {
        let f: &[f32] = unsafe { std::slice::from_raw_parts(w.as_ptr() as *const f32, w.len() / 4) };
        for r in r0..r1 {
            let row = &f[r * cols..(r + 1) * cols];
            for bi in 0..n {
                yb[bi * rf + r] = dot(row, &xb[bi * cols..(bi + 1) * cols]);
            }
        }
        return;
    }
    if dtype == 1 {
        let mut tmp = vec![0f32; cols];
        for r in r0..r1 {
            for c in 0..cols {
                tmp[c] = f16_to_f32(u16::from_le_bytes([w[(r * cols + c) * 2], w[(r * cols + c) * 2 + 1]]));
            }
            for bi in 0..n {
                yb[bi * rf + r] = dot(&tmp, &xb[bi * cols..(bi + 1) * cols]);
            }
        }
        return;
    }
    let (bs, be) = match dtype {
        8 => (34usize, 32usize),
        6 => (22, 32),
        12 => (144, 256),
        14 => (210, 256),
        42 | 142 => (34, 128),
        _ => panic!("gemm_batch_1s dtype {}", dtype),
    };
    let nb = cols / be;
    let mut tmp = vec![0f32; cols];
    for r in r0..r1 {
        for q in 0..nb {
            deq_row_into(dtype, &w[(r * nb + q) * bs..(r * nb + q + 1) * bs], &mut tmp[q * be..(q + 1) * be]);
        }
        for bi in 0..n {
            yb[bi * rf + r] = dot(&tmp, &xb[bi * cols..(bi + 1) * cols]);
        }
    }
}

/// Batched Y = W X: xb is [n][cols] row-major, yb is [n][rows]. One weight read serves all n.
pub fn gemm_batch_mt(w: &[u8], dtype: u32, rows: usize, cols: usize, xb: &[f32], n: usize, yb: &mut [f32], pool: &Pool) {
    assert_eq!(xb.len(), n * cols);
    assert_eq!(yb.len(), n * rows);
    if n == 0 || rows == 0 {
        return;
    }
    if matches!(dtype, 6 | 8 | 12 | 14 | 42 | 142) {
        let qx = quant_xn(xb, n, cols);
        let wptr = w.as_ptr() as usize;
        let wlen = w.len();
        let yptr = yb.as_mut_ptr() as usize;
        let ylen = yb.len();
        pool.run(rows, move |r0: usize, r1: usize| {
            // SAFETY: run blocks until all ranges finish; ranges are disjoint rows; slices rebuilt from live refs.
            let w = unsafe { std::slice::from_raw_parts(wptr as *const u8, wlen) };
            let yb = unsafe { std::slice::from_raw_parts_mut(yptr as *mut f32, ylen) };
            gemm_batch_1i(w, dtype, cols, &qx, n, yb, rows, r0, r1);
        });
        return;
    }
    if rows < 32 {
        gemm_batch_1(w, dtype, cols, xb, n, yb, 0, rows);
        return;
    }
    let wptr = w.as_ptr() as usize;
    let wlen = w.len();
    let xptr = xb.as_ptr() as usize;
    let xlen = xb.len();
    let yptr = yb.as_mut_ptr() as usize;
    let ylen = yb.len();
    pool.run(rows, move |r0: usize, r1: usize| {
        // SAFETY: run blocks until all ranges finish; ranges are disjoint rows; slices rebuilt from live refs.
        let w = unsafe { std::slice::from_raw_parts(wptr as *const u8, wlen) };
        let xb = unsafe { std::slice::from_raw_parts(xptr as *const f32, xlen) };
        let yb = unsafe { std::slice::from_raw_parts_mut(yptr as *mut f32, ylen) };
        gemm_batch_1s(w, dtype, cols, xb, n, yb, rows, r0, r1);
    });
}

/// Fused single-token pair: two mats sharing one input, ONE pool dispatch, ONE activation quant.
/// Uses the dedicated single-token kernel (no per-call batch overhead).
pub fn gemv2_mt(w1: &[u8], d1: u32, r1: usize, w2: &[u8], d2: u32, r2: usize, cols: usize, x: &[f32], y1: &mut [f32], y2: &mut [f32], pool: &Pool) {
    assert_eq!(x.len(), cols);
    assert_eq!(y1.len(), r1);
    assert_eq!(y2.len(), r2);
    if !(matches!(d1, 6 | 8 | 12 | 14 | 42 | 142) && matches!(d2, 6 | 8 | 12 | 14 | 42 | 142)) {
        gemv_mt(w1, d1, r1, cols, x, y1, pool);
        gemv_mt(w2, d2, r2, cols, x, y2, pool);
        return;
    }
    let qx = quant_x(x);
    let rows = r1.max(r2);
    let (w1p, w1l, w2p, w2l) = (w1.as_ptr() as usize, w1.len(), w2.as_ptr() as usize, w2.len());
    let (y1p, y1l, y2p, y2l) = (y1.as_mut_ptr() as usize, y1.len(), y2.as_mut_ptr() as usize, y2.len());
    pool.run(rows, move |a: usize, b: usize| {
        // SAFETY: run blocks until done; ranges are disjoint rows; slices rebuilt from live refs.
        let w1 = unsafe { std::slice::from_raw_parts(w1p as *const u8, w1l) };
        let w2 = unsafe { std::slice::from_raw_parts(w2p as *const u8, w2l) };
        let y1 = unsafe { std::slice::from_raw_parts_mut(y1p as *mut f32, y1l) };
        let y2 = unsafe { std::slice::from_raw_parts_mut(y2p as *mut f32, y2l) };
        if a < r1 {
            let e = b.min(r1);
            gemv_range_i(w1, d1, cols, &qx, &mut y1[a..e], a, e);
        }
        if a < r2 {
            let e = b.min(r2);
            gemv_range_i(w2, d2, cols, &qx, &mut y2[a..e], a, e);
        }
    });
}

/// Fused single-token triple, same pattern.
pub fn gemv3_mt(w1: &[u8], d1: u32, r1: usize, w2: &[u8], d2: u32, r2: usize, w3: &[u8], d3: u32, r3: usize, cols: usize, x: &[f32], y1: &mut [f32], y2: &mut [f32], y3: &mut [f32], pool: &Pool) {
    assert_eq!(x.len(), cols);
    assert_eq!(y1.len(), r1);
    assert_eq!(y2.len(), r2);
    assert_eq!(y3.len(), r3);
    if !(matches!(d1, 6 | 8 | 12 | 14 | 42 | 142) && matches!(d2, 6 | 8 | 12 | 14 | 42 | 142) && matches!(d3, 6 | 8 | 12 | 14 | 42 | 142)) {
        gemv_mt(w1, d1, r1, cols, x, y1, pool);
        gemv_mt(w2, d2, r2, cols, x, y2, pool);
        gemv_mt(w3, d3, r3, cols, x, y3, pool);
        return;
    }
    let qx = quant_x(x);
    let rows = r1.max(r2).max(r3);
    let (w1p, w1l, w2p, w2l, w3p, w3l) = (w1.as_ptr() as usize, w1.len(), w2.as_ptr() as usize, w2.len(), w3.as_ptr() as usize, w3.len());
    let (y1p, y1l, y2p, y2l, y3p, y3l) = (y1.as_mut_ptr() as usize, y1.len(), y2.as_mut_ptr() as usize, y2.len(), y3.as_mut_ptr() as usize, y3.len());
    pool.run(rows, move |a: usize, b: usize| {
        // SAFETY: run blocks until done; ranges are disjoint rows; slices rebuilt from live refs.
        let w1 = unsafe { std::slice::from_raw_parts(w1p as *const u8, w1l) };
        let w2 = unsafe { std::slice::from_raw_parts(w2p as *const u8, w2l) };
        let w3 = unsafe { std::slice::from_raw_parts(w3p as *const u8, w3l) };
        let y1 = unsafe { std::slice::from_raw_parts_mut(y1p as *mut f32, y1l) };
        let y2 = unsafe { std::slice::from_raw_parts_mut(y2p as *mut f32, y2l) };
        let y3 = unsafe { std::slice::from_raw_parts_mut(y3p as *mut f32, y3l) };
        if a < r1 {
            let e = b.min(r1);
            gemv_range_i(w1, d1, cols, &qx, &mut y1[a..e], a, e);
        }
        if a < r2 {
            let e = b.min(r2);
            gemv_range_i(w2, d2, cols, &qx, &mut y2[a..e], a, e);
        }
        if a < r3 {
            let e = b.min(r3);
            gemv_range_i(w3, d3, cols, &qx, &mut y3[a..e], a, e);
        }
    });
}

/// Fused pair: two mats sharing one input, ONE pool dispatch, ONE activation quant.
/// Falls back to two separate calls for non-int dtypes.
pub fn gemm2_batch_mt(w1: &[u8], d1: u32, r1: usize, w2: &[u8], d2: u32, r2: usize, cols: usize, xb: &[f32], n: usize, y1: &mut [f32], y2: &mut [f32], pool: &Pool) {
    assert_eq!(xb.len(), n * cols);
    assert_eq!(y1.len(), n * r1);
    assert_eq!(y2.len(), n * r2);
    if n == 0 {
        return;
    }
    if !(matches!(d1, 6 | 8 | 12 | 14 | 42 | 142) && matches!(d2, 6 | 8 | 12 | 14 | 42 | 142)) {
        gemm_batch_mt(w1, d1, r1, cols, xb, n, y1, pool);
        gemm_batch_mt(w2, d2, r2, cols, xb, n, y2, pool);
        return;
    }
    let qx = quant_xn(xb, n, cols);
    let rows = r1.max(r2);
    let (w1p, w1l, w2p, w2l) = (w1.as_ptr() as usize, w1.len(), w2.as_ptr() as usize, w2.len());
    let (y1p, y1l, y2p, y2l) = (y1.as_mut_ptr() as usize, y1.len(), y2.as_mut_ptr() as usize, y2.len());
    pool.run(rows, move |a: usize, b: usize| {
        // SAFETY: run blocks until done; ranges are disjoint rows; slices rebuilt from live refs.
        let w1 = unsafe { std::slice::from_raw_parts(w1p as *const u8, w1l) };
        let w2 = unsafe { std::slice::from_raw_parts(w2p as *const u8, w2l) };
        let y1 = unsafe { std::slice::from_raw_parts_mut(y1p as *mut f32, y1l) };
        let y2 = unsafe { std::slice::from_raw_parts_mut(y2p as *mut f32, y2l) };
        if a < r1 {
            gemm_batch_1i(w1, d1, cols, &qx, n, y1, r1, a, b.min(r1));
        }
        if a < r2 {
            gemm_batch_1i(w2, d2, cols, &qx, n, y2, r2, a, b.min(r2));
        }
    });
}

/// Fused triple: three mats sharing one input, ONE pool dispatch, ONE activation quant.
pub fn gemm3_batch_mt(w1: &[u8], d1: u32, r1: usize, w2: &[u8], d2: u32, r2: usize, w3: &[u8], d3: u32, r3: usize, cols: usize, xb: &[f32], n: usize, y1: &mut [f32], y2: &mut [f32], y3: &mut [f32], pool: &Pool) {
    assert_eq!(xb.len(), n * cols);
    assert_eq!(y1.len(), n * r1);
    assert_eq!(y2.len(), n * r2);
    assert_eq!(y3.len(), n * r3);
    if n == 0 {
        return;
    }
    if !(matches!(d1, 6 | 8 | 12 | 14 | 42 | 142) && matches!(d2, 6 | 8 | 12 | 14 | 42 | 142) && matches!(d3, 6 | 8 | 12 | 14 | 42 | 142)) {
        gemm_batch_mt(w1, d1, r1, cols, xb, n, y1, pool);
        gemm_batch_mt(w2, d2, r2, cols, xb, n, y2, pool);
        gemm_batch_mt(w3, d3, r3, cols, xb, n, y3, pool);
        return;
    }
    let qx = quant_xn(xb, n, cols);
    let rows = r1.max(r2).max(r3);
    let (w1p, w1l, w2p, w2l, w3p, w3l) = (w1.as_ptr() as usize, w1.len(), w2.as_ptr() as usize, w2.len(), w3.as_ptr() as usize, w3.len());
    let (y1p, y1l, y2p, y2l, y3p, y3l) = (y1.as_mut_ptr() as usize, y1.len(), y2.as_mut_ptr() as usize, y2.len(), y3.as_mut_ptr() as usize, y3.len());
    pool.run(rows, move |a: usize, b: usize| {
        // SAFETY: run blocks until done; ranges are disjoint rows; slices rebuilt from live refs.
        let w1 = unsafe { std::slice::from_raw_parts(w1p as *const u8, w1l) };
        let w2 = unsafe { std::slice::from_raw_parts(w2p as *const u8, w2l) };
        let w3 = unsafe { std::slice::from_raw_parts(w3p as *const u8, w3l) };
        let y1 = unsafe { std::slice::from_raw_parts_mut(y1p as *mut f32, y1l) };
        let y2 = unsafe { std::slice::from_raw_parts_mut(y2p as *mut f32, y2l) };
        let y3 = unsafe { std::slice::from_raw_parts_mut(y3p as *mut f32, y3l) };
        if a < r1 {
            gemm_batch_1i(w1, d1, cols, &qx, n, y1, r1, a, b.min(r1));
        }
        if a < r2 {
            gemm_batch_1i(w2, d2, cols, &qx, n, y2, r2, a, b.min(r2));
        }
        if a < r3 {
            gemm_batch_1i(w3, d3, cols, &qx, n, y3, r3, a, b.min(r3));
        }
    });
}

/// Cached unpacked K-quants: unpacked ONCE at load, skipping per-token uq4k/uq6k.
/// Same math as row_q4k/row_q6k, weights only (activations still quantized per call).
pub struct KU {
    pub kind: u8, // 12 = Q4_K, 14 = Q6_K
    pub nb: usize,
    pub t: Vec<i8>,  // nblocks*256
    pub a: Vec<f32>, // q4k: nblocks*8 kd | q6k: nblocks*16 sc
    pub b: Vec<f32>, // q4k: nblocks*8 km | q6k: nblocks*1 d
}
pub fn unpack_ku(dtype: u32, w: &[u8], rows: usize, cols: usize) -> KU {
    assert!(dtype == 12 || dtype == 14);
    let nb = cols / 256;
    let nblocks = rows * nb;
    let mut ku = KU {
        kind: dtype as u8,
        nb,
        t: vec![0i8; nblocks * 256],
        a: vec![0f32; nblocks * if dtype == 12 { 8 } else { 16 }],
        b: vec![0f32; nblocks * if dtype == 12 { 8 } else { 1 }],
    };
    for r in 0..rows {
        for q in 0..nb {
            let bi = r * nb + q;
            if dtype == 12 {
                let (t, kd, km) = uq4k(&w[bi * 144..(bi + 1) * 144]);
                ku.t[bi * 256..(bi + 1) * 256].copy_from_slice(&t);
                ku.a[bi * 8..(bi + 1) * 8].copy_from_slice(&kd);
                ku.b[bi * 8..(bi + 1) * 8].copy_from_slice(&km);
            } else {
                let (t, sc, dd) = uq6k(&w[bi * 210..(bi + 1) * 210]);
                ku.t[bi * 256..(bi + 1) * 256].copy_from_slice(&t);
                ku.a[bi * 16..(bi + 1) * 16].copy_from_slice(&sc);
                ku.b[bi] = dd;
            }
        }
    }
    ku
}
impl KU {
    pub fn bytes(&self) -> usize {
        self.t.len() + (self.a.len() + self.b.len()) * 4
    }
}

fn row_q4k_c(ku: &KU, row: usize, nb: usize, qx: &Qx, base: usize) -> f32 {
    let mut s = 0f32;
    for q in 0..nb {
        let bi = row * nb + q;
        let t = &ku.t[bi * 256..(bi + 1) * 256];
        let kd = &ku.a[bi * 8..(bi + 1) * 8];
        let km = &ku.b[bi * 8..(bi + 1) * 8];
        let bq = base + q * 8;
        for g in 0..4 {
            let wx0 = vdoti(&t[g * 64..g * 64 + 32], &qx.q[(bq + 2 * g) * 32..(bq + 2 * g + 1) * 32]);
            s += kd[2 * g] * qx.d[bq + 2 * g] * wx0 as f32 - km[2 * g] * qx.d[bq + 2 * g] * qx.s[bq + 2 * g] as f32;
            let wx1 = vdoti(&t[g * 64 + 32..g * 64 + 64], &qx.q[(bq + 2 * g + 1) * 32..(bq + 2 * g + 2) * 32]);
            s += kd[2 * g + 1] * qx.d[bq + 2 * g + 1] * wx1 as f32 - km[2 * g + 1] * qx.d[bq + 2 * g + 1] * qx.s[bq + 2 * g + 1] as f32;
        }
    }
    s
}

fn row_q6k_c(ku: &KU, row: usize, nb: usize, qx: &Qx, base: usize) -> f32 {
    let mut s = 0f32;
    for q in 0..nb {
        let bi = row * nb + q;
        let t = &ku.t[bi * 256..(bi + 1) * 256];
        let sc = &ku.a[bi * 16..(bi + 1) * 16];
        let dd = ku.b[bi];
        let bq = base + q * 8;
        for b in 0..8 {
            for h in 0..2 {
                let wx = vdoti(&t[b * 32 + h * 16..b * 32 + h * 16 + 16], &qx.q[(bq + b) * 32 + h * 16..(bq + b) * 32 + h * 16 + 16]);
                s += dd * sc[b * 2 + h] * qx.d[bq + b] * wx as f32;
            }
        }
    }
    s
}

fn brow_q4k_c(ku: &KU, row: usize, nb: usize, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r: usize) {
    for bi in 0..n {
        let mut s = 0f32;
        let bb = bi * qx.nb;
        for q in 0..nb {
            let gi = row * nb + q;
            let t = &ku.t[gi * 256..(gi + 1) * 256];
            let kd = &ku.a[gi * 8..(gi + 1) * 8];
            let km = &ku.b[gi * 8..(gi + 1) * 8];
            let bq = bb + q * 8;
            for g in 0..4 {
                let wx0 = vdoti(&t[g * 64..g * 64 + 32], &qx.q[(bq + 2 * g) * 32..(bq + 2 * g + 1) * 32]);
                s += kd[2 * g] * qx.d[bq + 2 * g] * wx0 as f32 - km[2 * g] * qx.d[bq + 2 * g] * qx.s[bq + 2 * g] as f32;
                let wx1 = vdoti(&t[g * 64 + 32..g * 64 + 64], &qx.q[(bq + 2 * g + 1) * 32..(bq + 2 * g + 2) * 32]);
                s += kd[2 * g + 1] * qx.d[bq + 2 * g + 1] * wx1 as f32 - km[2 * g + 1] * qx.d[bq + 2 * g + 1] * qx.s[bq + 2 * g + 1] as f32;
            }
        }
        yb[bi * rf + r] = s;
    }
}

fn brow_q6k_c(ku: &KU, row: usize, nb: usize, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r: usize) {
    for bi in 0..n {
        let mut s = 0f32;
        let bb = bi * qx.nb;
        for q in 0..nb {
            let gi = row * nb + q;
            let t = &ku.t[gi * 256..(gi + 1) * 256];
            let sc = &ku.a[gi * 16..(gi + 1) * 16];
            let dd = ku.b[gi];
            let bq = bb + q * 8;
            for b in 0..8 {
                for h in 0..2 {
                    let wx = vdoti(&t[b * 32 + h * 16..b * 32 + h * 16 + 16], &qx.q[(bq + b) * 32 + h * 16..(bq + b) * 32 + h * 16 + 16]);
                    s += dd * sc[b * 2 + h] * qx.d[bq + b] * wx as f32;
                }
            }
        }
        yb[bi * rf + r] = s;
    }
}

/// Single-token y = W x over cached K-quants.
pub fn gemv_ku_mt(ku: &KU, rows: usize, cols: usize, x: &[f32], y: &mut [f32], pool: &Pool) {
    assert_eq!(x.len(), cols);
    assert!(y.len() >= rows);
    let nb = cols / 256;
    assert_eq!(ku.nb, nb);
    let qx = quant_x(x);
    let kup = ku as *const KU as usize;
    let yptr = y.as_mut_ptr() as usize;
    let ylen = y.len();
    let kind = ku.kind;
    pool.run(rows, move |a: usize, b: usize| {
        // SAFETY: run blocks until done; ranges are disjoint rows; ku shared read-only.
        let ku = unsafe { &*(kup as *const KU) };
        let y = unsafe { std::slice::from_raw_parts_mut(yptr as *mut f32, ylen) };
        for r in a..b {
            y[r] = if kind == 12 { row_q4k_c(ku, r, nb, &qx, 0) } else { row_q6k_c(ku, r, nb, &qx, 0) };
        }
    });
}

fn gemm_ku_1(ku: &KU, qx: &Qx, n: usize, yb: &mut [f32], rf: usize, r0: usize, r1: usize) {
    assert_eq!(yb.len(), n * rf);
    let nb = ku.nb;
    for r in r0..r1 {
        if ku.kind == 12 {
            brow_q4k_c(ku, r, nb, qx, n, yb, rf, r);
        } else {
            brow_q6k_c(ku, r, nb, qx, n, yb, rf, r);
        }
    }
}

/// Batched Y = W X over cached K-quants.
pub fn gemm_ku_batch_mt(ku: &KU, rows: usize, cols: usize, xb: &[f32], n: usize, yb: &mut [f32], pool: &Pool) {
    assert_eq!(xb.len(), n * cols);
    assert_eq!(yb.len(), n * rows);
    if n == 0 || rows == 0 {
        return;
    }
    assert_eq!(ku.nb, cols / 256);
    let qx = quant_xn(xb, n, cols);
    let kup = ku as *const KU as usize;
    let yptr = yb.as_mut_ptr() as usize;
    let ylen = yb.len();
    pool.run(rows, move |a: usize, b: usize| {
        // SAFETY: run blocks until done; ranges are disjoint rows; ku shared read-only.
        let ku = unsafe { &*(kup as *const KU) };
        let yb = unsafe { std::slice::from_raw_parts_mut(yptr as *mut f32, ylen) };
        gemm_ku_1(ku, &qx, n, yb, rows, a, b);
    });
}

/// dequant whole small tensor (norms, biases) to f32.
pub fn dequant_all(w: &[u8], dtype: u32, ne: usize) -> Vec<f32> {
    match dtype {
        0 => {
            let f: &[f32] = unsafe { std::slice::from_raw_parts(w.as_ptr() as *const f32, ne) };
            f.to_vec()
        }
        1 => {
            let mut o = Vec::with_capacity(ne);
            for i in 0..ne {
                o.push(f16_to_f32(u16::from_le_bytes([w[i * 2], w[i * 2 + 1]])));
            }
            o
        }
        8 => {
            let mut o = Vec::with_capacity(ne);
            for q in 0..ne / 32 {
                o.extend_from_slice(&deq_q80(&w[q * 34..(q + 1) * 34]));
            }
            o
        }
        6 => {
            let mut o = Vec::with_capacity(ne);
            for q in 0..ne / 32 {
                o.extend_from_slice(&deq_q50(&w[q * 22..(q + 1) * 22]));
            }
            o
        }
        _ => panic!("dequant_all dtype {}", dtype),
    }
}
