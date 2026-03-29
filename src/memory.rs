//! Memory protection utilities for sensitive buffers.
//!
//! - `lock_buffer` / `unlock_buffer`: pin memory in RAM via mlock/munlock
//!   so the kernel cannot page it to swap or hibernation.
//! - `disable_core_dumps`: set RLIMIT_CORE to 0 so crash dumps cannot
//!   contain sensitive data.

use std::sync::atomic::{AtomicBool, Ordering};

/// Pin a memory region in RAM. Returns `true` on success.
/// Failure is non-fatal — mlock is defense-in-depth.
pub fn lock_buffer(ptr: *const u8, len: usize) -> bool {
    if ptr.is_null() || len == 0 {
        return true;
    }
    unsafe { libc::mlock(ptr as *const libc::c_void, len) == 0 }
}

/// Release a previously locked memory region.
pub fn unlock_buffer(ptr: *const u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    unsafe {
        libc::munlock(ptr as *const libc::c_void, len);
    }
}

static CORE_DUMPS_DISABLED: AtomicBool = AtomicBool::new(false);

/// Disable core dumps for this process (RLIMIT_CORE = 0).
/// Safe to call multiple times; only the first call takes effect.
pub fn disable_core_dumps() {
    if CORE_DUMPS_DISABLED.swap(true, Ordering::SeqCst) {
        return;
    }
    unsafe {
        let rlim = libc::rlimit {
            rlim_cur: 0,
            rlim_max: 0,
        };
        libc::setrlimit(libc::RLIMIT_CORE, &rlim);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mlock_munlock_does_not_panic() {
        let buf = vec![42u8; 4096];
        let ok = lock_buffer(buf.as_ptr(), buf.len());
        // mlock may fail in restricted environments; just verify no panic
        if ok {
            unlock_buffer(buf.as_ptr(), buf.len());
        }
    }

    #[test]
    fn mlock_null_and_empty_are_safe() {
        assert!(lock_buffer(std::ptr::null(), 0));
        unlock_buffer(std::ptr::null(), 0);
        let buf = vec![0u8; 0];
        assert!(lock_buffer(buf.as_ptr(), 0));
    }

    #[test]
    fn disable_core_dumps_does_not_panic() {
        disable_core_dumps();
        // Second call is a no-op
        disable_core_dumps();
    }
}
