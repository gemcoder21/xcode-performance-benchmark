# Gem Wallet iOS Build Benchmark

A simple tool to benchmark the full build time of Gem Wallet iOS, including Rust core compilation.

## Prerequisites

Xcode must be installed from the App Store. All other dependencies are installed automatically.

## Usage

```bash
sh run.sh
```

## Results

> ⚠️ Results from different Xcode versions should not be compared directly.
> Each Xcode version uses a specific commit for consistent benchmarking.

### Xcode 26.2

**Commit:** `28c46f7f` | **Rust:** `1.92.0`

| Device | Chip | Cores | RAM | macOS | Rust | SPM | Build | Total |
|--------|------|-------|-----|-------|------|-----|-------|-------|
| Mac Studio | M4 Max | 16 | 64GB | 26.2 | 1m 14s | 2s | 41s | 1m 57s |

### How to Submit Your Results

1. Run the benchmark: `sh run.sh`
2. Results are automatically added to this README
3. Submit a PR

### Column Descriptions

| Column | Description |
|--------|-------------|
| Device | Mac model and year |
| Chip | Apple Silicon or Intel CPU |
| Cores | Number of CPU cores |
| RAM | Memory capacity |
| macOS | macOS version |
| Xcode | Xcode version |
| Rust | Rust core build time (Gemstone FFI) |
| SPM | Swift Package Manager dependency resolution |
| Build | Xcode project build time |
| Total | Complete benchmark time |

## What Gets Benchmarked

1. **Rust Core Build** - Compiles the Gemstone FFI framework from Rust
2. **SPM Resolve** - Resolves all Swift Package Manager dependencies
3. **Xcode Build** - Clean build of the full Gem Wallet iOS project

