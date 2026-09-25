//! Blocking lock types used by the cache.
//!
//! On most targets, these are re-exports of `parking_lot` types.
//!
//! On WebAssembly targets, `parking_lot` (without its `nightly` feature) cannot
//! park a thread and panics when a lock is contended, which happens on
//! multi-threaded wasm such as `wasm32-wasip1-threads`. So on wasm we provide
//! thin wrappers around `std::sync` locks that mimic the subset of the
//! `parking_lot` API used by this crate (no lock poisoning, `try_lock` returns
//! an `Option`).

#[cfg(not(target_family = "wasm"))]
pub(crate) use parking_lot::{Mutex, MutexGuard, RwLock};

#[cfg(target_family = "wasm")]
pub(crate) use self::wasm::{Mutex, MutexGuard, RwLock};

#[cfg(target_family = "wasm")]
mod wasm {
    use std::sync::{self, PoisonError, TryLockError};

    pub(crate) type MutexGuard<'a, T> = sync::MutexGuard<'a, T>;

    #[derive(Debug, Default)]
    pub(crate) struct Mutex<T: ?Sized>(sync::Mutex<T>);

    impl<T> Mutex<T> {
        pub(crate) const fn new(value: T) -> Self {
            Self(sync::Mutex::new(value))
        }
    }

    impl<T: ?Sized> Mutex<T> {
        pub(crate) fn lock(&self) -> MutexGuard<'_, T> {
            self.0.lock().unwrap_or_else(PoisonError::into_inner)
        }

        pub(crate) fn try_lock(&self) -> Option<MutexGuard<'_, T>> {
            match self.0.try_lock() {
                Ok(guard) => Some(guard),
                Err(TryLockError::Poisoned(e)) => Some(e.into_inner()),
                Err(TryLockError::WouldBlock) => None,
            }
        }
    }

    #[derive(Debug, Default)]
    pub(crate) struct RwLock<T: ?Sized>(sync::RwLock<T>);

    impl<T> RwLock<T> {
        pub(crate) const fn new(value: T) -> Self {
            Self(sync::RwLock::new(value))
        }
    }

    impl<T: ?Sized> RwLock<T> {
        pub(crate) fn read(&self) -> sync::RwLockReadGuard<'_, T> {
            self.0.read().unwrap_or_else(PoisonError::into_inner)
        }

        pub(crate) fn write(&self) -> sync::RwLockWriteGuard<'_, T> {
            self.0.write().unwrap_or_else(PoisonError::into_inner)
        }
    }
}
