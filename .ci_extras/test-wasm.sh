#!/bin/sh
#
# Build moka for WASI targets and run the test suite under Wasmtime.
#
# Usage: ./.ci_extras/test-wasm.sh
#
# Set WASMTIME to use an existing wasmtime binary. Otherwise, a pinned version is
# downloaded into target/wasmtime. Newer Wasmtime releases removed the
# `-S threads` (wasi-threads) flag, which the threaded test run needs.

set -eu

WASMTIME_VERSION=37.0.0

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

for target in wasm32-wasip1 wasm32-wasip2; do
    cargo build --lib --target "$target" -F sync,future
    cargo build --lib --target "$target" -F sync,future,logging,quanta
    cargo test --no-run --target "$target" -F sync,future --lib --tests
done

# Many tests spawn threads, so run them on the wasi-threads target. `--dir .`
# lets the tests read files in the crate directory. Wasm uses `panic = "abort"`,
# so tests that expect to catch a panic cannot run and are skipped.
CARGO_TARGET_WASM32_WASIP1_THREADS_RUNNER="$WASMTIME run --dir . -W threads=y -S threads=y" \
    cargo test --target wasm32-wasip1-threads -F sync,future --lib --tests -- --skip panic
