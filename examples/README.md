# Example Proofs

This directory contains pre-prepared `input.json` files for testing different proof types.

## Structure

```
examples/
├── fibonacci/              # Regular Fibonacci proof
│   └── input.json
├── factorial/              # Regular Factorial proof
│   └── input.json
├── fibonacci-bootloader/   # Fibonacci proof via bootloader
│   └── input.json
└── factorial-bootloader/   # Factorial proof via bootloader
    └── input.json
```

## Usage

### Regular Proofs

Test regular (non-bootloader) proofs:

```bash
cargo run --bin test example fibonacci
cargo run --bin test example factorial
```

### Bootloader Proofs

Test bootloader proofs:

```bash
cargo run --bin test example fibonacci --bootloader
cargo run --bin test example factorial --bootloader
```

## Updating Examples

To update example files with newly generated proofs, manually copy files from your proof generation tool:

```bash
# For regular proofs
cp /path/to/fibonacci/input.json examples/fibonacci/input.json
cp /path/to/factorial/input.json examples/factorial/input.json

# For bootloader proofs (note: both use the same file)
cp /path/to/bootloader/input.json examples/factorial-bootloader/input.json
cp /path/to/bootloader/input.json examples/fibonacci-bootloader/input.json
```

## Note

These files are pre-generated and ready to use for testing. They contain complete proof data prepared for EVM verification.
