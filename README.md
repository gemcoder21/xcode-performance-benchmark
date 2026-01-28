# Mobile Performance Build Benchmark

Full clean build times for [Gem Wallet](https://gemwallet.com) iOS and Android apps (Swift/Kotlin + Rust).

---

## iOS Results

Full clean build times for [Gem Wallet iOS](https://github.com/gemwalletcom/gem-ios) (Swift + Rust).

> Results from different Xcode versions are not comparable (different commits).

### Xcode 26.2 · macOS 26.2 · [`28c46f7f`](https://github.com/gemwalletcom/gem-ios/commit/28c46f7f) · Rust 1.92.0

| Device | Chip | Cores | RAM | Rust | SPM | Build | Total |
|--------|------|-------|-----|------|-----|-------|-------|
| Mac Studio | M4 Max | 16 | 64GB | 1m 6s | 1s | 37s | 1m 44s |
| Mac mini | M4 Pro | 12 | 48GB | 55s | 4s | 54s | 1m 53s |
| Mac Studio | M2 Ultra | 24 | 128GB | 1m 29s | 9s | 55s | 2m 33s |
| MacBook Pro | M4 Pro | 14 | 24GB | 2m 6s | 33s | 49s | 3m 28s |

### Run iOS Benchmark

Requires Xcode. All other dependencies install automatically.

```bash
sh run.sh
```

### What's Measured (iOS)

| Phase | Description |
|-------|-------------|
| Rust | Gemstone FFI framework (Rust to Swift via UniFFI) |
| SPM | Swift Package Manager resolution |
| Build | Xcode clean build |

---

## Android Results

Full clean build times for [Gem Wallet Android](https://github.com/gemwalletcom/gem-android) (Kotlin + Rust).

> Results from different AGP versions are not comparable (different commits).

### AGP 8.9 · Gradle 8.12 · [`16f0b353`](https://github.com/gemwalletcom/gem-android/commit/16f0b353) · Rust 1.92.0

| Device | Chip | Cores | RAM | Rust | Sync | Build | Total |
|--------|------|-------|-----|------|------|-------|-------|

### Run Android Benchmark

Requires Android SDK. All other dependencies install automatically.

```bash
sh run-android.sh
```

### What's Measured (Android)

| Phase | Description |
|-------|-------------|
| Rust | Gemstone FFI framework (Rust to Kotlin via UniFFI) |
| Sync | Gradle dependency resolution |
| Build | Gradle assembleRelease |

---

## Contributing

Results are added to this README automatically. Submit a PR to share your build times.
