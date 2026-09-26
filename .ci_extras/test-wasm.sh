#!/bin/sh
#
# Build moka for WASI targets and run the full test suite under Wasmtime.
#
# Usage: ./.ci_extras/test-wasm.sh
#
# Set WASMTIME to use an existing wasmtime binary. Otherwise, a pinned version is
# downloaded into target/wasmtime. Newer Wasmtime releases removed the
# `-S threads` (wasi-threads) flag, which the threaded test run needs.

set -eu

WASMTIME_VERSION=37.0.0

# The test run needs `panic = "unwind"` on wasm so that tests which catch panics
# (`should_panic`, `handle_panic_*`) can run. That requires rebuilding std with
# `-Zbuild-std` and the wasm exception-handling proposal. Pin the nightly:
# starting with nightly-2026-08-13, std on `wasm32-wasip1-threads` no longer runs
# thread-local destructors when a spawned thread exits, so crossbeam-epoch never
# reclaims garbage deferred by exited threads.
NIGHTLY=nightly-2026-08-12

if [ -z "${WASMTIME:-}" ]; then
    dir="target/wasmtime/wasmtime-v${WASMTIME_VERSION}-x86_64-linux"
    if [ ! -x "$dir/wasmtime" ]; then
        mkdir -p target/wasmtime
        curl -sSL "https://github.com/bytecodealliance/wasmtime/releases/download/v${WASMTIME_VERSION}/wasmtime-v${WASMTIME_VERSION}-x86_64-linux.tar.xz" |
            tar xJ -C target/wasmtime
    fi
    WASMTIME="$(pwd)/$dir/wasmtime"
fi

set -x

rustup target add wasm32-wasip1 wasm32-wasip2 wasm32-wasip1-threads
rustup toolchain install "$NIGHTLY" --profile minimal --component rust-src \
    --target wasm32-wasip1-threads

# Stable toolchain: the library and all tests build for each WASI target.
for target in wasm32-wasip1 wasm32-wasip2 wasm32-wasip1-threads; do
    cargo build --lib --target "$target" -F sync,future
    cargo build --lib --target "$target" -F sync,future,logging,quanta
    cargo test --no-run --target "$target" -F sync,future --lib --tests
done

# Run every test on the wasi-threads target (many tests spawn threads) with
# `panic = "unwind"`. `--dir .` lets the tests read files in the crate directory.
UNWIND_FLAGS="-Cpanic=unwind -Ctarget-feature=+exception-handling -Cllvm-args=-wasm-use-legacy-eh=false"
export CARGO_TARGET_DIR=target/wasm-unwind
export CARGO_TARGET_WASM32_WASIP1_THREADS_RUNNER="$WASMTIME run --dir . -W threads=y,exceptions=y -S threads=y"

wasm_test() {
    cargo "+$NIGHTLY" test -Zbuild-std=std,panic_unwind --target wasm32-wasip1-threads "$@"
}

RUSTFLAGS="$UNWIND_FLAGS" wasm_test -F sync,future --lib --tests

# Timing-sensitive tests gated by `run_flaky_tests`, run one at a time in release
# mode as the native CI does.
for t in \
    "sync sync::cache::tests::test_key_lock_used_by_immediate_removal_notifications" \
    "sync sync::cache::tests::drop_value_immediately_after_eviction" \
    "sync sync::segment::tests::drop_value_immediately_after_eviction" \
    "sync sync::cache::tests::ensure_gc_runs_when_dropping_cache" \
    "future future::cache::tests::drop_value_immediately_after_eviction" \
    "future future::cache::tests::ensure_gc_runs_when_dropping_cache"; do
    set -- $t
    RUSTFLAGS="$UNWIND_FLAGS --cfg run_flaky_tests" wasm_test --release -F "$1" --lib "$2" -- --exact
done
