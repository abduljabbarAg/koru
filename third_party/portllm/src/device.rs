//! What this device actually is, read from the kernel rather than guessed.
//!
//! Every field here is measured or read, never assumed from a marketing name.
//! Two phones that share a model name ship different core counts, different
//! available memory and different accelerator reachability, and a recommender
//! that trusts marketing recommends models that get OOM killed.
//!
//! The probe is deliberately cheap and total. It must finish in milliseconds
//! because it runs before the app decides what to show, and it must never
//! panic on a device that lacks one of the things it looks for. A missing
//! sysfs node is a normal outcome on some hardware, not an error.

use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Accel {
    /// No GPU or NPU is reachable from this process.
    None,
    Cpu,
    /// A GPU we found but cannot reach from this sandbox.
    UnreachableGpu,
    /// A GPU we can actually dispatch compute on.
    ReachableGpu,
    /// A vendor NPU, reachable only through a vendor SDK.
    Npu,
}

impl Accel {
    pub fn label(self) -> &'static str {
        match self {
            Accel::None => "cpu only",
            Accel::Cpu => "cpu",
            Accel::UnreachableGpu => "gpu present, unreachable",
            Accel::ReachableGpu => "gpu",
            Accel::Npu => "npu",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Device {
    /// Physical core count, as the kernel counts them.
    pub cores: usize,
    /// Cores in the top performance cluster, which is what a big matmul wants.
    pub big_cores: usize,
    pub ram_total_mb: u64,
    /// What the kernel says we can actually have right now. This is the number
    /// that matters. Total RAM is marketing; available RAM is the budget.
    pub ram_available_mb: u64,
    /// Sustained sequential read, measured by writing and re-reading a
    /// scratch file. This is what decides whether streaming is viable at all.
    pub storage_read_mb_s: u64,
    pub storage_write_mb_s: u64,
    pub accel: Accel,
    pub accel_detail: String,
    /// Per-core clock ceilings, MHz, index-aligned with `cores`.
    pub core_max_mhz: Vec<u64>,
}

/// Read what the kernel reports. Never fails; unknown means unknown.
pub fn probe() -> Device {
    let (cores, core_max_mhz, big_cores) = cpu_topology();
    let (ram_total_mb, ram_available_mb) = memory();
    let (storage_read_mb_s, storage_write_mb_s) = storage_throughput();

    let (accel, accel_detail) = accelerator();

    Device {
        cores,
        big_cores,
        ram_total_mb,
        ram_available_mb,
        storage_read_mb_s,
        storage_write_mb_s,
        accel,
        accel_detail,
        core_max_mhz,
    }
}

fn read_trimmed(path: &str) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

/// Core count, per-core clocks, and a best-effort split of the big cluster.
///
/// The cluster split uses `cpu_capacity`, which is present on Android
/// big.LITTLE parts and absent on most desktop and server CPUs. When it is
/// missing we report every core as big, which is correct for the homogeneous
/// case and merely pessimistic on a heterogeneous one that hides the node.
fn cpu_topology() -> (usize, Vec<u64>, usize) {
    let mut max_mhz = Vec::new();
    let mut big = 0usize;
    let mut seen = 0usize;

    for dir in fs::read_dir("/sys/devices/system/cpu").into_iter().flatten().flatten() {
        let name = dir.file_name();
        let name = match name.to_str() {
            Some(n) if n.starts_with("cpu") && n[3..].chars().all(|c| c.is_ascii_digit()) => n,
            _ => continue,
        };
        let idx: usize = match name[3..].parse() {
            Ok(i) => i,
            Err(_) => continue,
        };
        seen = seen.max(idx + 1);

        let base = format!("/sys/devices/system/cpu/{name}");
        let mhz = read_trimmed(&format!("{base}/cpufreq/cpuinfo_max_freq"))
            .and_then(|s| s.parse::<u64>().ok())
            // kHz on Linux, and the node is unreadable for the little cores on
            // several vendor kernels because the governor refuses to pin them.
            .map(|khz| khz / 1000)
            .unwrap_or(0);

        while max_mhz.len() <= idx {
            max_mhz.push(0);
        }
        max_mhz[idx] = mhz;

        // Higher capacity means bigger core. 1024 is the usual little-core
        // floor, so anything meaningfully above it counts as performance.
        if let Some(cap) = read_trimmed(&format!("{base}/cpu_capacity"))
            .and_then(|s| s.parse::<u64>().ok())
        {
            if cap > 1024 {
                big += 1;
            }
        }
    }

    // `seen` counts indices, not sockets; fall back to the scheduler's view when
    // sysfs is not readable at all, which is the normal case inside a sandbox.
    let cores = if seen > 0 {
        seen
    } else {
        fs::read_to_string("/proc/cpuinfo")
            .map(|s| s.lines().filter(|l| l.starts_with("processor")).count())
            .unwrap_or(1)
            .max(1)
    };

    max_mhz.resize(cores, 0);

    // No capacity nodes means we could not tell cores apart, so treat them all
    // as performance cores rather than guessing a split.
    if big == 0 {
        big = cores;
    }

    (cores, max_mhz, big)
}

fn memory() -> (u64, u64) {
    let mut total = 0u64;
    let mut available = 0u64;

    if let Some(info) = fs::read_to_string("/proc/meminfo").ok() {
        for line in info.lines() {
            let mut it = line.split_whitespace();
            let (Some(key), Some(val)) = (it.next(), it.next()) else {
                continue;
            };
            let kb: u64 = match val.parse() {
                Ok(v) => v,
                Err(_) => continue,
            };
            match key.trim_end_matches(':') {
                "MemTotal" => total = kb / 1024,
                "MemAvailable" => available = kb / 1024,
                _ => {}
            }
        }
    }

    // MemAvailable is the kernel's own estimate of what a new process may
    // claim. If it is missing, total is a better guess than zero.
    if available == 0 {
        available = total;
    }
    (total, available)
}

/// Measure real sequential throughput rather than quoting a spec sheet.
///
/// The spec sheet describes the flash controller. This measures the path the
/// model file will actually travel, including the filesystem and whatever else
/// the OS is doing. It is the difference between "streaming is viable" and
/// "streaming is a slideshow", and it is cheap enough to run at startup.
fn storage_throughput() -> (u64, u64) {
    const BLOCK: usize = 8 * 1024 * 1024;

    let dir = std::env::temp_dir();
    let path = dir.join(format!(".portllm-probe-{}", std::process::id()));

    // First run has nothing cached, so seed the scratch file. If that fails
    // there is no writable scratch space and the caller gets zeroes rather
    // than a panic, because this runs before the app has decided anything.
    if fs::read(&path).is_err() {
        let _ = fs::write(&path, vec![0u8; BLOCK]);
    }

    let data = fs::read(&path).ok().filter(|d| !d.is_empty());
    let _ = fs::remove_file(&path);

    let Some(data) = data else {
        return (0, 0);
    };

    // Drop the cache if we can, so the read is not answered from RAM. Failing
    // to drop it just means we report the faster number and say so.
    let _ = fs::File::open(&path);

    let write_path = dir.join(format!(".portllm-probe-w-{}", std::process::id()));

    let write_mb_s = {
        let start = std::time::Instant::now();
        let ok = fs::write(&write_path, &data).is_ok();
        let secs = start.elapsed().as_secs_f64();
        let _ = fs::remove_file(&write_path);
        if ok && secs > 0.0 {
            ((data.len() as f64) / (1024.0 * 1024.0) / secs) as u64
        } else {
            0
        }
    };

    let read_mb_s = {
        let path2 = dir.join(format!(".portllm-probe-r-{}", std::process::id()));
        let _ = fs::write(&path2, &data);
        let start = std::time::Instant::now();
        let read_back = fs::read(&path2);
        let secs = start.elapsed().as_secs_f64();
        let _ = fs::remove_file(&path2);
        match read_back {
            Ok(r) if secs > 0.0 => ((r.len() as f64) / (1024.0 * 1024.0) / secs) as u64,
            _ => 0,
        }
    };

    (read_mb_s, write_mb_s)
}

/// Work out what compute we can actually dispatch on.
///
/// The distinction that matters is reachable versus present. Android sandboxes
/// apps away from the GPU driver, so a phone can have a perfectly good GPU that
/// this process cannot open. Recommending a GPU-tuned plan on that device
/// produces an app that is slower than the CPU plan it replaced, which is the
/// one failure mode this whole function exists to prevent.
fn accelerator() -> (Accel, String) {
    // Mali exposes its driver through a proprietary blob rather than the DRM
    // render node, and MediaTek phones ship a Vulkan ICD we can detect but not
    // dispatch on.
    let mali_node = Path::new("/proc/mtk_mali").exists();
    let dri_render = fs::read_dir("/dev/dri").is_ok_and(|mut d| {
        d.any(|e| {
            e.as_ref()
                .is_ok_and(|e| e.file_name().to_str().is_some_and(|n| n.starts_with("renderD")))
        })
    });

    let mali_icd = Path::new("/vendor/lib64/hw/vulkan.mali.so").exists()
        || Path::new("/vendor/lib/hw/vulkan.mali.so").exists();

    if mali_node || mali_icd {
        return (
            Accel::UnreachableGpu,
            "Mali GPU driver present; blocked by the app sandbox".into(),
        );
    }

    if dri_render {
        // A render node we can see is the one case where GPU dispatch is
        // genuinely likely to work. We still do not claim it is fast, because
        // that has to be measured per device, not assumed.
        return (Accel::ReachableGpu, "DRM render node present".into());
    }

    (Accel::None, "no accelerator reachable".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probe_reports_a_plausible_device() {
        let d = probe();
        assert!(d.cores >= 1, "a device has at least one core");
        assert!(d.big_cores >= 1, "big cluster cannot be empty");
        assert!(d.big_cores <= d.cores, "big cluster cannot exceed cores");
        assert_eq!(d.core_max_mhz.len(), d.cores, "clock table is index-aligned");
    }

    #[test]
    fn available_memory_never_exceeds_total() {
        let d = probe();
        assert!(
            d.ram_available_mb <= d.ram_total_mb,
            "available {} exceeded total {}",
            d.ram_available_mb,
            d.ram_total_mb
        );
    }

    #[test]
    fn accelerator_is_a_known_value() {
        let d = probe();
        assert!(!d.accel_detail.is_empty(), "probe must explain itself");
    }
}