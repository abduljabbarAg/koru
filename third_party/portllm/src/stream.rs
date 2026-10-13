//! Reading a model larger than RAM.
//!
//! The problem is not file size, it is *how many copies* exist at once. A
//! 468 MB file held in RAM is one copy. Decode every layer's int8 weights up
//! front and you hold two more copies as i8, and the page cache plus the
//! decoded copy plus the decoded scratch is what actually exhausts a phone.
//!
//! So the file is mapped rather than read, and a block's weights are decoded
//! when that block runs and released when it is done. The kernel pulls bytes
//! through the mapping on demand; the operating system evicts what has not
//! been touched recently, which is exactly the policy we want and costs us
//! nothing to implement.
//!
//! What this deliberately does not do: prefetch. Reading ahead of the router is
//! a separate idea and it is only meaningful when the next block is already
//! known, which sparse models make possible and dense ones do not.

use std::fs::File;
use std::io;
use std::os::unix::io::AsRawFd;

/// A read-only mapping of the model file.
///
/// `as_raw_fd` is stored because `memmap2` is not a dependency and this crate
/// has none. A `File` is kept alive to guarantee the descriptor outlives the
/// mapping.
pub struct MappedFile {
    file: File,
    ptr: *const u8,
    len: usize,
}

// SAFETY: the mapping is read-only and nothing here mutates it. The File is
// owned, so the descriptor cannot be closed out from under the mapping.
unsafe impl Send for MappedFile {}
unsafe impl Sync for MappedFile {}

impl MappedFile {
    pub fn open(path: &std::path::Path) -> io::Result<Self> {
        let file = File::open(path)?;
        let len = file.metadata()?.len() as usize;
        if len == 0 {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "empty file"));
        }

        let ptr = unsafe {
            libc_mmap(
                std::ptr::null_mut(),
                len,
                PROT_READ,
                MAP_PRIVATE,
                file.as_raw_fd(),
            )
        };
        if ptr as isize == -1 || ptr.is_null() {
            return Err(io::Error::last_os_error());
        }

        Ok(MappedFile {
            file,
            ptr: ptr as *const u8,
            len,
        })
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Borrow `n` bytes at `offset`. The caller keeps the borrow alive only as
    /// long as it uses it, so nothing outlives the mapping.
    pub fn slice(&self, offset: u64, n: usize) -> io::Result<&[u8]> {
        let start = offset as usize;
        let end = start.checked_add(n).ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidData, "offset overflow")
        })?;
        if end > self.len {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                format!("read [{start}, {end}) past the end of a {} byte file", self.len),
            ));
        }
        Ok(unsafe { std::slice::from_raw_parts(self.ptr.add(start), n) })
    }

    pub fn advise_random(&self) {
        // Random access pattern: the kernel should not try to read ahead
        // linearly, because we will not read linearly.
        unsafe { libc_madvise(self.ptr as *mut _, self.len, MADV_RANDOM) };
    }

    pub fn advise_sequential(&self) {
        unsafe { libc_madvise(self.ptr as *mut _, self.len, MADV_SEQUENTIAL) };
    }
}

impl Drop for MappedFile {
    fn drop(&mut self) {
        unsafe {
            libc_munmap(self.ptr as *mut _, self.len);
        }
        // `file` drops after this body, so the descriptor outlives the unmap.
    }
}

// The handful of libc entry points this needs, declared directly so the crate
// keeps its zero-dependency property.
extern "C" {
    fn mmap(
        addr: *mut core::ffi::c_void,
        length: usize,
        prot: i32,
        flags: i32,
        fd: i32,
        offset: i64,
    ) -> *mut core::ffi::c_void;
    fn munmap(addr: *mut core::ffi::c_void, length: usize) -> i32;
    fn madvise(addr: *mut core::ffi::c_void, length: usize, advice: i32) -> i32;
}

const PROT_READ: i32 = 1;
const MAP_PRIVATE: i32 = 2;
const MADV_RANDOM: i32 = 1;
const MADV_SEQUENTIAL: i32 = 2;

// SAFETY: these are thin wrappers over libc and take only plain scalars.
unsafe fn libc_mmap(
    addr: *mut core::ffi::c_void,
    len: usize,
    prot: i32,
    flags: i32,
    fd: i32,
) -> *mut core::ffi::c_void {
    mmap(addr, len, prot, flags, fd, 0)
}

unsafe fn libc_madvise(addr: *mut core::ffi::c_void, len: usize, advice: i32) -> i32 {
    madvise(addr, len, advice)
}

unsafe fn libc_munmap(addr: *mut core::ffi::c_void, len: usize) -> i32 {
    munmap(addr, len)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn tmpfile(name: &str, bytes: &[u8]) -> std::path::PathBuf {
        let p = std::env::temp_dir().join(name);
        let mut f = File::create(&p).unwrap();
        f.write_all(bytes).unwrap();
        p
    }

    #[test]
    fn maps_and_reads_the_whole_file() {
        let data: Vec<u8> = (0..4096u32).map(|i| (i % 251) as u8).collect();
        let p = tmpfile("portllm_map_all.bin", &data);
        let m = MappedFile::open(&p).expect("map");
        assert_eq!(m.len(), data.len());
        assert_eq!(m.slice(0, data.len()).unwrap(), &data[..]);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn reads_a_window_from_the_middle() {
        let data: Vec<u8> = (0..8192u32).map(|i| (i % 97) as u8).collect();
        let p = tmpfile("portllm_map_mid.bin", &data);
        let m = MappedFile::open(&p).expect("map");
        assert_eq!(m.slice(1000, 32).unwrap(), &data[1000..1032]);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn the_last_byte_is_reachable() {
        let data = vec![7u8; 1024];
        let p = tmpfile("portllm_map_last.bin", &data);
        let m = MappedFile::open(&p).expect("map");
        assert_eq!(m.slice(1023, 1).unwrap(), &[7]);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn a_read_past_the_end_is_an_error_not_a_crash() {
        let data = vec![0u8; 512];
        let p = tmpfile("portllm_map_oob.bin", &data);
        let m = MappedFile::open(&p).expect("map");
        assert!(m.slice(500, 100).is_err(), "overflow past the end must fail");
        assert!(m.slice(512, 1).is_err(), "exactly past the end must fail");
        assert!(m.slice(u64::MAX, 1).is_err(), "offset overflow must fail");
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn an_empty_file_is_rejected() {
        let p = tmpfile("portllm_map_empty.bin", &[]);
        assert!(MappedFile::open(&p).is_err(), "empty file must not map");
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn advice_calls_are_harmless() {
        let data = vec![1u8; 2048];
        let p = tmpfile("portllm_map_adv.bin", &data);
        let m = MappedFile::open(&p).expect("map");
        m.advise_random();
        m.advise_sequential();
        assert_eq!(m.slice(0, 4).unwrap(), &[1, 1, 1, 1]);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn real_model_maps_without_reading_it_all() {
        let p = std::path::Path::new("/tmp/qwen05b-good.gguf");
        if !p.exists() {
            return;
        }
        let m = MappedFile::open(p).expect("map the model");
        assert_eq!(m.len() as u64, std::fs::metadata(p).unwrap().len());
        let header = crate::gguf::read_header(p).expect("header");
        let t = header.tensors.first().expect("a tensor");
        let n = t.bytes().expect("sized") as usize;
        let s = m.slice(header.data_offset + t.name_offset, n).expect("slice");
        assert_eq!(s.len(), n);
    }
}