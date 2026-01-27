# Xcode Performance Build Benchmark

Full clean build times for [Gem Wallet iOS](https://github.com/gemwalletcom/gem-ios) (Swift + Rust).

## Results

> Results from different Xcode versions are not comparable (different commits).

### Xcode 26.2 · macOS 26.2 · [`28c46f7f`](https://github.com/gemwalletcom/gem-ios/commit/28c46f7f) · Rust 1.92.0

| Device | Chip | Cores | RAM | Rust | SPM | Build | Total |
|--------|------|-------|-----|------|-----|-------|-------|
| Mac Studio | M4 Max | 16 | 64GB | 1m 6s | 1s | 37s | 1m 44s |

## Run

Requires Xcode. All other dependencies install automatically.

```bash
sh run.sh
```

Results are added to this README automatically. Submit a PR to share.

## What's Measured

| Phase | Description |
|-------|-------------|
| Rust | Gemstone FFI framework (Rust to Swift) |
| SPM | Swift Package Manager resolution |
| Build | Xcode clean build |
