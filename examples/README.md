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
make test-program PROGRAM=fibonacci
make test-program PROGRAM=factorial
```

Or use shortcuts:
```bash
make test-fibonacci
make test-factorial
```

### Bootloader Proofs

Test bootloader proofs:

```bash
make test-program-bootloader PROGRAM=fibonacci
make test-program-bootloader PROGRAM=factorial
```

Or use shortcuts:
```bash
make test-fibonacci-bootloader
make test-factorial-bootloader
```

## Updating Examples

To update example files with newly generated proofs, use the make target:

```bash
# Generate and prepare proofs first
make prepare PROGRAM=fibonacci
make prepare PROGRAM=factorial
make bootloader-prepare PROGRAM=factorial

# Then update all examples at once
make update-examples
```

Or manually copy files:

```bash
# For regular proofs
make prepare PROGRAM=fibonacci
cp work/fibonacci/input.json examples/fibonacci/input.json

make prepare PROGRAM=factorial
cp work/factorial/input.json examples/factorial/input.json

# For bootloader proofs (note: both use the same file)
make bootloader-prepare PROGRAM=factorial
cp work/bootloader/input.json examples/factorial-bootloader/input.json
cp work/bootloader/input.json examples/fibonacci-bootloader/input.json
```

## Note

These files are pre-generated and ready to use for testing. They contain complete proof data prepared for EVM verification.
