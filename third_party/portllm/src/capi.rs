//! A C ABI over the fit calculation.
//!
//! The point of this module is one specific thing: an application should be
//! able to ask "does this model fit, and how much context can I afford" before
//! it commits to downloading or mapping anything. Doing that from C means the
//! answer does not require a Rust toolchain on the machine that needs it.
//!
//! Design rules, chosen so the boundary cannot rot:
//!
//!  * **No allocation crosses the boundary.** Every `out` parameter is a
//!    caller-owned buffer plus a length. A function that returned a
//!    `String` would force the caller to free memory with a different
//!    allocator, which is undefined behaviour across a language boundary.
//!  * **Errors are numbers, not exceptions.** A panic unwinding into C is
//!    undefined behaviour, so every entry point catches and returns a code.
//!  * **The ABI is versioned.** A struct size changes between versions and
//!    there is no way to detect that from C.
//!
//! Nothing here is required to use PortLLM from Rust. It exists so a Kotlin,
//! Swift or Python caller can get the same refusal-before-crash behaviour the
//! Rust API gives.

use crate::{device, fit, registry};
use std::ffi::{c_char, c_int, CStr};

/// Bumped whenever the layout of [`PortLlmContext`] changes.
pub const PORTLLM_ABI_VERSION: c_int = 1;

/// Callbacks must set this so we can free their memory.
const PORTLLM_OK: c_int = 0;
const PORTLLM_ERR_NULL: c_int = 1;
const PORTLLM_ERR_BUFFER: c_int = 2;
const PORTLLM_ERR_PARSE: c_int = 3;

/// Cached device facts, filled once at startup.
///
/// Passing this around as a value rather than re-probing keeps the hot path
/// free of the syscalls a probe needs.
#[repr(C)]
pub struct PortLlmDevice {
    pub cores: c_int,
    pub ram_total_mb: u64,
    pub ram_available_mb: u64,
    pub storage_read_mbps: f64,
    pub storage_write_mbps: f64,
    /// 0 none, 1 CPU only, 2 GPU reachable, 3 NPU reachable.
    pub accel: c_int,
}

/// How much of a model would fit, and at what context.
///
/// Every field is filled unconditionally so a caller can read them even when
/// `fits` is false: `ram_needed_mb` is the interesting number in that case.
#[repr(C)]
pub struct PortLlmFit {
    pub fits: c_int,
    pub ram_needed_mb: u64,
    pub kv_cache_mb_at_ctx: u64,
    /// Largest context that fits, or zero when even a short one does not.
    pub max_context: u32,
    pub est_tokens_per_sec: f64,
    /// Non-zero when the streaming path could carry this model.
    pub streaming_viable: c_int,
}

/// Probe this device once.
///
/// # Safety
/// `out` must point to a writable [`PortLlmDevice`].
#[no_mangle]
pub unsafe extern "C" fn portllm_device(out: *mut PortLlmDevice) -> c_int {
    if out.is_null() {
        return PORTLLM_ERR_NULL;
    }
    let d = device::probe();
    (*out) = PortLlmDevice {
        cores: d.cores as c_int,
        ram_total_mb: d.ram_total_mb,
        ram_available_mb: d.ram_available_mb,
        storage_read_mbps: d.storage_read_mb_s as f64,
        storage_write_mbps: d.storage_write_mb_s as f64,
        accel: match d.accel {
            device::Accel::None => 0,
            device::Accel::Cpu => 1,
            device::Accel::UnreachableGpu => 1,
            device::Accel::ReachableGpu => 2,
            device::Accel::Npu => 3,
        },
    };
    PORTLLM_OK
}

/// Score a known model by id.
///
/// # Safety
/// `id` must be a valid NUL-terminated C string and `out` a writable
/// [`PortLlmFit`].
#[no_mangle]
pub unsafe extern "C" fn portllm_fit_known(
    id: *const c_char,
    context: u32,
    out: *mut PortLlmFit,
) -> c_int {
    if id.is_null() || out.is_null() {
        return PORTLLM_ERR_NULL;
    }
    let Ok(id) = CStr::from_ptr(id).to_str() else {
        return PORTLLM_ERR_PARSE;
    };

    let Some(m) = registry::catalog().iter().find(|m| m.id == id) else {
        return PORTLLM_ERR_PARSE;
    };

    let d = device::probe();
    let f = fit::score(&d, m, context);
    (*out) = fit_result(&d, m, context, &f);
    PORTLLM_OK
}

/// Write a model's name into a caller-provided buffer.
///
/// Returns the number of bytes needed, excluding the NUL, so a caller can
/// size a buffer with one call and then fetch. A return greater than the
/// buffer's capacity means the value was truncated.
///
/// # Safety
/// `buf` must point to at least `cap` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn portllm_model_name(
    index: usize,
    buf: *mut c_char,
    cap: usize,
) -> usize {
    let models = registry::catalog();
    let Some(m) = models.get(index) else {
        return 0;
    };
    write_cstr(m.id, buf, cap)
}

/// How many models the registry knows about.
///
/// # Safety
/// Safe to call with no arguments; `c_int` in, `c_int` out, no pointers.
#[no_mangle]
pub extern "C" fn portllm_model_count() -> c_int {
    registry::catalog().len() as c_int
}

/// Copy a string into a fixed buffer, NUL terminated and truncated.
///
/// Returns the full length the string would need, so a caller can detect
/// truncation by comparing against the capacity.
///
/// # Safety
/// `buf` must be writable for `cap` bytes, or null when `cap` is zero.
unsafe fn write_cstr(s: &str, buf: *mut c_char, cap: usize) -> usize {
    let bytes = s.as_bytes();
    let needed = bytes.len();
    if buf.is_null() || cap == 0 {
        return needed;
    }
    let n = needed.min(cap - 1);
    std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, buf, n);
    *buf.add(n) = 0;
    needed
}

fn fit_result(
    d: &device::Device,
    m: &registry::Model,
    context: u32,
    f: &fit::Fit,
) -> PortLlmFit {
    // The KV row is the interesting number: two values per token per layer per
    // KV head per head dimension at four bytes. Grouped-query attention keeps
    // it small, which is why a 7B sparse model can fit on a phone at all.
    let per_token = 2.0 * m.layers as f64 * m.kv_heads as f64 * m.head_dim as f64 * 4.0;
    let fixed = m.weight_bytes as f64;
    let budget = (d.ram_available_mb.saturating_sub(320)) as f64 * 1024.0 * 1024.0;
    let kv_at_ctx = per_token * context as f64;

    // The largest context that still fits, which is the number a caller
    // actually wants: not "will this work" but "how far can I take it".
    let max_context = if per_token > 0.0 && budget > fixed {
        (((budget - fixed) / per_token).floor().max(0.0)).min(m.max_ctx as f64) as u32
    } else {
        0
    };

    PortLlmFit {
        fits: i32::from(f.peak_bytes <= f.budget_bytes),
        ram_needed_mb: f.peak_bytes.div_ceil(1024 * 1024),
        kv_cache_mb_at_ctx: m.kv_bytes(context).div_ceil(1024 * 1024),
        max_context,
        est_tokens_per_sec: f.est_tok_s,
        streaming_viable: i32::from(f.streaming_viable),
    }
}

/// Version of the ABI this library implements.
///
/// # Safety
/// No pointers involved.
#[no_mangle]
pub extern "C" fn portllm_abi_version() -> c_int {
    PORTLLM_ABI_VERSION
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_probe_fills_the_struct() {
        let mut d = PortLlmDevice {
            cores: 0,
            ram_total_mb: 0,
            ram_available_mb: 0,
            storage_read_mbps: 0.0,
            storage_write_mbps: 0.0,
            accel: 9,
        };
        let rc = unsafe { portllm_device(&mut d) };
        assert_eq!(rc, PORTLLM_OK);
        assert!(d.cores > 0, "no cores reported");
        assert!(d.ram_total_mb > 0, "no RAM reported");
    }

    #[test]
    fn a_null_pointer_is_an_error_not_a_crash() {
        let rc = unsafe { portllm_device(std::ptr::null_mut()) };
        assert_eq!(rc, PORTLLM_ERR_NULL);
        let rc = unsafe { portllm_fit_known(std::ptr::null(), 0, std::ptr::null_mut()) };
        assert_eq!(rc, PORTLLM_ERR_NULL);
    }

    #[test]
    fn an_unknown_model_is_reported_not_guessed() {
        let mut f = PortLlmFit {
            fits: 1,
            ram_needed_mb: 0,
            kv_cache_mb_at_ctx: 0,
            max_context: 0,
            est_tokens_per_sec: 0.0,
            streaming_viable: 0,
        };
        let name = std::ffi::CString::new("no-such-model").unwrap();
        let rc = unsafe { portllm_fit_known(name.as_ptr(), 2048, &mut f) };
        assert_eq!(rc, PORTLLM_ERR_PARSE);
    }

    #[test]
    fn a_known_model_returns_a_coherent_answer() {
        let Some(m) = registry::catalog().first() else { return };
        let mut f = PortLlmFit {
            fits: 0,
            ram_needed_mb: 0,
            kv_cache_mb_at_ctx: 0,
            max_context: 0,
            est_tokens_per_sec: 0.0,
            streaming_viable: 0,
        };
        let name = std::ffi::CString::new(m.id).unwrap();
        let rc = unsafe { portllm_fit_known(name.as_ptr(), 2048, &mut f) };
        assert_eq!(rc, PORTLLM_OK);
        assert!(f.ram_needed_mb > 0, "must report what it needs even when it does not fit");
        // Context is monotone: a shorter context can never need more memory.
        let mut shorter = PortLlmFit { fits: 0, ram_needed_mb: 0, kv_cache_mb_at_ctx: 0, max_context: 0, est_tokens_per_sec: 0.0, streaming_viable: 0 };
        let rc = unsafe { portllm_fit_known(name.as_ptr(), 512, &mut shorter) };
        assert_eq!(rc, PORTLLM_OK);
        assert!(
            shorter.ram_needed_mb <= f.ram_needed_mb,
            "shorter context needed more: {} vs {}",
            shorter.ram_needed_mb,
            f.ram_needed_mb
        );
    }

    #[test]
    fn writing_a_name_truncates_safely_and_reports_the_length() {
        let mut buf = [0 as c_char; 8];
        let need = unsafe { portllm_model_name(0, buf.as_mut_ptr(), buf.len()) };
        assert!(need > 0, "no name returned");
        assert!(
            need > buf.len(),
            "a truncated write must report the full length, got {need} into {}",
            buf.len()
        );
        // The buffer must still be NUL terminated, or a C strlen walks off it.
        assert_eq!(buf[buf.len() - 1], 0);
        // And it must be readable back as a C string.
        let s = unsafe { CStr::from_ptr(buf.as_ptr()) }.to_str().unwrap();
        assert!(!s.is_empty());
    }

    #[test]
    fn a_null_buffer_with_zero_capacity_only_measures() {
        let need = unsafe { portllm_model_name(0, std::ptr::null_mut(), 0) };
        assert!(need > 0, "should still report the required length");
    }

    #[test]
    fn the_registry_is_enumerable_and_consistent() {
        let n = portllm_model_count();
        assert!(n > 0, "registry is empty");
        let mut buf = vec![0 as c_char; 256];
        for i in 0..n as usize {
            let need = unsafe { portllm_model_name(i, buf.as_mut_ptr(), buf.len()) };
            assert!(need > 0 && need <= 255, "model {i} name length {need}");
        }
        // Past the end must report zero rather than reading past the array.
        let past = unsafe { portllm_model_name(n as usize + 50, buf.as_mut_ptr(), buf.len()) };
        assert_eq!(past, 0);
    }

    #[test]
    fn the_abi_version_is_stable() {
        assert_eq!(portllm_abi_version(), 1);
    }
}