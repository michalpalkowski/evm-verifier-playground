#!/bin/bash
set -e

# Wrapper for cairo-run that handles Python venv activation
# This script enters the stone-prover environment and runs cairo-run

# Save current directory
ORIG_DIR="$(pwd)"

# Configuration
STONE_PROVER_DIR="${STONE_PROVER_DIR:-/home/michal/Documents/stone-prover}"
VENV_NAME="${VENV_NAME:-venv39}"

# Check if stone-prover directory exists
if [ ! -d "$STONE_PROVER_DIR" ]; then
    echo "Error: Stone prover directory not found: $STONE_PROVER_DIR"
    echo "Please set STONE_PROVER_DIR in .env or ensure stone-prover is cloned"
    exit 1
fi

# Check if venv exists
if [ ! -f "$STONE_PROVER_DIR/$VENV_NAME/bin/activate" ]; then
    echo "Error: Python venv not found: $STONE_PROVER_DIR/$VENV_NAME"
    echo "Please set VENV_NAME in .env (default: venv39)"
    exit 1
fi

# Activate venv
cd "$STONE_PROVER_DIR"
source "$VENV_NAME/bin/activate"

# Return to original directory and run cairo-run
cd "$ORIG_DIR"
cairo-run "$@"
