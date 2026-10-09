// The gate.
//
// One question: is it safe to load a model right now? If not, say why and stop.
//
// Why here and not somewhere cleverer. Loading weights is the most expensive
// thing this program does, so the cheapest possible place to refuse is before it
// starts. Everything here is a subprocess and a status code, deliberately: a
// nervous system that had to be linked in to be consulted would be a second
// thing to keep in step, and the whole claim is that these are separate
// programs agreeing on a boundary.
//
// The contract with axonspark is its exit code, and nothing else:
//
//   0  allowed
//   2  refused
//
// Anything else, including a crash or a missing binary, is treated as allowed.
// That is a real decision and it goes the safe way for the user, because a
// missing guard must not brick a phone. It is *not* the safe way for the
// device, so the missing case is loud rather than silent: the caller can see it.

use std::process::Command;

/// What the guard said, and why.
pub struct Refusal {
    pub reason: String,
    /// True when the guard could not be consulted at all, as opposed to
    /// consulting it and being told no.
    pub unreachable: bool,
}

/// Ask axonspark whether a run may start.
///
/// Returns `None` when the answer is yes, and never panics: a guard that takes
/// the model down with it would be worse than no guard.
pub fn check() -> Option<Refusal> {
    let exe = std::env::var("AXONSPARK_GUARD").unwrap_or_else(|_| "axonspark".to_string());
    let out = match Command::new(&exe).arg("--quiet").output() {
        Ok(o) => o,
        Err(e) => {
            return Some(Refusal {
                reason: format!("could not run the guard {}: {}", exe, e),
                unreachable: true,
            })
        }
    };
    match out.status.code() {
        // 0 means ready or degraded, and both allow a start. The distinction
        // matters for a policy decision later; it does not change whether to
        // load weights.
        Some(0) => None,
        Some(2) => Some(Refusal {
            reason: String::from_utf8_lossy(&out.stdout)
                .lines()
                .last()
                .unwrap_or("refused, with no reason given")
                .trim()
                .to_string(),
            unreachable: false,
        }),
        Some(other) => Some(Refusal {
            reason: format!("the guard exited {} rather than 0 or 2", other),
            unreachable: true,
        }),
        // Killed by a signal, so no code at all. Treated as unreachable rather
        // than as a refusal, and said out loud.
        None => Some(Refusal {
            reason: "the guard was killed rather than answering".to_string(),
            unreachable: true,
        }),
    }
}

/// Convenience for `main`: the message to print, if the run must not proceed.
pub fn refusal_message() -> Option<String> {
    check().map(|r| {
        if r.unreachable {
            format!(
                "the safety guard could not be consulted ({}). \
                 Continuing anyway. Install axonspark or set GLEN_GUARD=0 to \
                 silence this.",
                r.reason
            )
        } else {
            r.reason
        }
    })
}
