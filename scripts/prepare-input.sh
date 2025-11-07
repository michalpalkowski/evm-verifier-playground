#!/bin/bash
# Wrapper script for Rust prepare-input tool

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CARGO_TOML="$SCRIPT_DIR/prepare_input/Cargo.toml"

if [ ! -f "$CARGO_TOML" ]; then
    echo "Error: Cargo.toml not found at $CARGO_TOML" >&2
    exit 1
fi

cargo run --release --manifest-path "$CARGO_TOML" -- "$@"
