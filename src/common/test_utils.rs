use std::sync::{
    atomic::{AtomicU32, Ordering},
    Arc,
};

#[derive(Debug, Default)]
pub(crate) struct Counters {
    inserted: AtomicU32,
    evicted: AtomicU32,
    invalidated: AtomicU32,
    value_created: AtomicU32,
    value_dropped: AtomicU32,
}

impl Counters {
    pub(crate) fn inserted(&self) -> u32 {
        self.inserted.load(Ordering::Acquire)
    }

    pub(crate) fn evicted(&self) -> u32 {
        self.evicted.load(Ordering::Acquire)
    }

    pub(crate) fn invalidated(&self) -> u32 {
        self.invalidated.load(Ordering::Acquire)
    }

    pub(crate) fn value_created(&self) -> u32 {
        self.value_created.load(Ordering::Acquire)
    }

    pub(crate) fn value_dropped(&self) -> u32 {
        self.value_dropped.load(Ordering::Acquire)
    }

    pub(crate) fn incl_inserted(&self) {
        self.inserted.fetch_add(1, Ordering::AcqRel);
    }

    pub(crate) fn incl_evicted(&self) {
        self.evicted.fetch_add(1, Ordering::AcqRel);
    }

    pub(crate) fn incl_invalidated(&self) {
        self.invalidated.fetch_add(1, Ordering::AcqRel);
    }

    pub(crate) fn incl_value_created(&self) {
        self.value_created.fetch_add(1, Ordering::AcqRel);
    }

    pub(crate) fn incl_value_dropped(&self) {
        self.value_dropped.fetch_add(1, Ordering::AcqRel);
    }
}

#[derive(Debug)]
pub(crate) struct Value {
    // blob: Vec<u8>,
    counters: Arc<Counters>,
}

impl Value {
    pub(crate) fn new(_blob: Vec<u8>, counters: &Arc<Counters>) -> Self {
        counters.incl_value_created();
        Self {
            // blob,
            counters: Arc::clone(counters),
        }
    }

    // pub(crate) fn blob(&self) -> &[u8] {
    //     &self.blob
    // }
}

impl Drop for Value {
    fn drop(&mut self) {
        self.counters.incl_value_dropped();
    }
}

/// Runs `f` and asserts that it panics with a message containing `expected`.
///
/// Use this instead of `#[should_panic]`, which libtest ignores on wasm targets
/// even when they are built with `panic = "unwind"`.
pub(crate) fn assert_panics_with<F: FnOnce()>(f: F, expected: &str) {
    let payload =
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)).expect_err("expected a panic");
    let message = payload
        .downcast_ref::<String>()
        .map(String::as_str)
        .or_else(|| payload.downcast_ref::<&str>().copied())
        .expect("panic payload is not a string");
    assert!(
        message.contains(expected),
        "panic message {message:?} does not contain {expected:?}"
    );
}
