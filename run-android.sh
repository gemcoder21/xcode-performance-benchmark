#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/gem-android"
README_FILE="$SCRIPT_DIR/README.md"
REPO_URL="https://github.com/gemwalletcom/gem-android.git"

# Source shared functions
. "$SCRIPT_DIR/common.sh"

clone_repo() {
    if [ ! -d "$PROJECT_ROOT" ]; then
        echo "Cloning gem-android repository..."
        git clone --recursive "$REPO_URL" "$PROJECT_ROOT"
    fi
}

clone_repo
cd "$PROJECT_ROOT"

# Get benchmark config for Android Gradle Plugin version
# Returns: BENCHMARK_COMMIT and BENCHMARK_RUST_VERSION
get_benchmark_config() {
    case "$1" in
        "8.9")
            BENCHMARK_COMMIT="16f0b353"
            BENCHMARK_RUST_VERSION="1.92.0"
            ;;
        # Add new versions here:
        # "8.10")
        #     BENCHMARK_COMMIT="new_commit"
        #     BENCHMARK_RUST_VERSION="1.93.0"
        #     ;;
        *)
            BENCHMARK_COMMIT=""
            BENCHMARK_RUST_VERSION=""
            ;;
    esac
}

collect_system_info() {
    collect_base_system_info

    # Get Android SDK path
    if [ -n "$ANDROID_HOME" ]; then
        ANDROID_SDK_PATH="$ANDROID_HOME"
    elif [ -n "$ANDROID_SDK_ROOT" ]; then
        ANDROID_SDK_PATH="$ANDROID_SDK_ROOT"
    elif [ -d "$HOME/Library/Android/sdk" ]; then
        ANDROID_SDK_PATH="$HOME/Library/Android/sdk"
    elif [ -d "$HOME/Android/Sdk" ]; then
        ANDROID_SDK_PATH="$HOME/Android/Sdk"
    else
        ANDROID_SDK_PATH=""
    fi

    # Get AGP version from project
    if [ -f "gradle/libs.versions.toml" ]; then
        AGP_VERSION=$(grep 'agp\s*=' gradle/libs.versions.toml 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "Unknown")
    else
        AGP_VERSION="Unknown"
    fi

    # Get Gradle wrapper version
    if [ -f "gradle/wrapper/gradle-wrapper.properties" ]; then
        GRADLE_VERSION=$(grep 'distributionUrl' gradle/wrapper/gradle-wrapper.properties | sed 's/.*gradle-\([0-9.]*\)-.*/\1/' || echo "Unknown")
    else
        GRADLE_VERSION="Unknown"
    fi
}

print_system_info() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            Android Performance Build Benchmark               ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Device:     $DEVICE_NAME"
    echo "║ Chip:       $CHIP_SHORT"
    echo "║ Cores:      $CORES"
    echo "║ Memory:     ${MEMORY_GB}GB"
    echo "║ macOS:      $OS_VERSION"
    echo "║ Gradle:     $GRADLE_VERSION"
    echo "║ AGP:        $AGP_VERSION"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

install_java() {
    if ! command -v java >/dev/null 2>&1; then
        echo "Installing Java 17..."
        brew install openjdk@17
        echo "Please add Java to your PATH:"
        echo "  export PATH=\"/opt/homebrew/opt/openjdk@17/bin:\$PATH\""
        export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
    fi

    JAVA_VERSION=$(java -version 2>&1 | head -1 | awk -F '"' '{print $2}')
    echo "  Java version: $JAVA_VERSION"
}

check_android_sdk() {
    if [ -z "$ANDROID_SDK_PATH" ] || [ ! -d "$ANDROID_SDK_PATH" ]; then
        echo "Error: Android SDK not found."
        echo "Please install Android Studio or set ANDROID_HOME environment variable."
        echo ""
        echo "To install Android SDK manually:"
        echo "  1. Download Android Studio from https://developer.android.com/studio"
        echo "  2. Or set ANDROID_HOME to your SDK path"
        exit 1
    fi

    export ANDROID_HOME="$ANDROID_SDK_PATH"
    export ANDROID_SDK_ROOT="$ANDROID_SDK_PATH"
    echo "  Android SDK: $ANDROID_SDK_PATH"
}

check_prerequisites() {
    echo "Checking and installing prerequisites..."

    install_homebrew
    install_rust
    install_java
    check_android_sdk
    install_just

    echo ""
    echo "Prerequisites installed:"
    echo "  Rust:        $(rustc --version | awk '{print $2}')"
    echo "  Just:        $(just --version | awk '{print $2}')"
    echo ""
}

install_toolchains() {
    echo "Running bootstrap (installs Rust Android toolchains and NDK)..."
    just bootstrap 2>/dev/null || true
}

checkout_benchmark_commit() {
    get_benchmark_config "$AGP_VERSION"

    if [ -n "$BENCHMARK_COMMIT" ]; then
        echo "Benchmark config for AGP $AGP_VERSION:"
        echo "  Commit: $BENCHMARK_COMMIT"
        echo "  Rust:   $BENCHMARK_RUST_VERSION"
        echo ""
        echo "Checking out commit $BENCHMARK_COMMIT..."
        git fetch origin 2>/dev/null || true
        git checkout "$BENCHMARK_COMMIT" 2>/dev/null || {
            echo "Warning: Could not checkout commit $BENCHMARK_COMMIT, using current HEAD"
            BENCHMARK_COMMIT=$(git rev-parse --short HEAD)
        }
        git submodule update --init --recursive 2>/dev/null || true
    else
        echo "No specific benchmark commit defined for AGP $AGP_VERSION"
        echo "Using current HEAD"
        BENCHMARK_COMMIT=$(git rev-parse --short HEAD)
    fi
}

setup_rust_version() {
    get_benchmark_config "$AGP_VERSION"

    if [ -n "$BENCHMARK_RUST_VERSION" ]; then
        echo "Setting up Rust $BENCHMARK_RUST_VERSION..."
        rustup install "$BENCHMARK_RUST_VERSION" 2>/dev/null || true
        rustup default "$BENCHMARK_RUST_VERSION"
        echo "  Rust version: $(rustc --version)"
    else
        echo "Using default Rust version"
        BENCHMARK_RUST_VERSION=$(rustc --version | awk '{print $2}')
    fi
}

clean_build() {
    echo "Cleaning previous build..."
    ./gradlew clean 2>/dev/null || true
    rm -rf build 2>/dev/null || true
    rm -rf app/build 2>/dev/null || true
    rm -rf gemcore/build 2>/dev/null || true
    rm -rf .gradle 2>/dev/null || true
    # Clean all module build directories
    find . -name "build" -type d -maxdepth 2 -exec rm -rf {} \; 2>/dev/null || true
    # Clean Rust build cache for accurate benchmark
    if [ -d "core" ]; then
        cargo clean --manifest-path core/Cargo.toml 2>/dev/null || true
    fi
    # Clean cargo-ndk output and any generated Rust artifacts
    rm -rf gemcore/src/main/jniLibs 2>/dev/null || true
    rm -rf core/target 2>/dev/null || true
    find . -name "target" -type d -maxdepth 3 -exec rm -rf {} \; 2>/dev/null || true
}

update_readme() {
    rust_time=$1
    gradle_sync_time=$2
    build_time=$3
    total_time=$4

    # Format times for display
    rust_fmt=$(format_duration "$rust_time")
    sync_fmt=$(format_duration "$gradle_sync_time")
    build_fmt=$(format_duration "$build_time")
    total_fmt=$(format_duration "$total_time")

    # Create the new table row
    new_row="| $DEVICE_NAME | $CHIP_SHORT | $CORES | ${MEMORY_GB}GB | $rust_fmt | $sync_fmt | $build_fmt | $total_fmt |"

    # Find the AGP version section
    section_pattern="### AGP $AGP_VERSION"

    if ! grep -q "$section_pattern" "$README_FILE"; then
        echo "Warning: Section for AGP $AGP_VERSION not found in README.md"
        echo "Please add results manually"
        return
    fi

    # Find section boundaries
    section_start=$(grep -n "$section_pattern" "$README_FILE" | head -1 | cut -d: -f1)
    next_section=$(tail -n +$((section_start + 1)) "$README_FILE" | grep -n "^### \|^---\|^## " | head -1 | cut -d: -f1)
    if [ -n "$next_section" ]; then
        section_end=$((section_start + next_section - 1))
    else
        section_end=$(wc -l < "$README_FILE" | tr -d ' ')
    fi

    # Check if this device already has an entry in this section
    existing_line=$(sed -n "${section_start},${section_end}p" "$README_FILE" | grep "| $DEVICE_NAME |" | head -1)

    if [ -n "$existing_line" ]; then
        # Extract existing total time (last column before final |)
        existing_total=$(echo "$existing_line" | awk -F'|' '{print $(NF-1)}' | xargs)
        existing_seconds=$(parse_time_to_seconds "$existing_total")

        if [ "$total_time" -lt "$existing_seconds" ]; then
            # New time is better, replace the line
            escaped_line=$(echo "$existing_line" | sed 's/[[\.*^$()+?{]/\\&/g')
            sed -i '' "s#${escaped_line}#${new_row}#" "$README_FILE"
            echo "README.md updated with faster results (${total_fmt} vs ${existing_total})"
            sort_table_by_total_time "$README_FILE" "$section_pattern"
        else
            echo "Existing result is faster or equal (${existing_total} vs ${total_fmt}), not updating README"
        fi
    else
        # No existing entry, add new row after the table separator line
        line_num=$(grep -n "$section_pattern" "$README_FILE" | head -1 | cut -d: -f1)
        insert_line=$((line_num + 3))

        sed -i '' "${insert_line}a\\
${new_row}
" "$README_FILE"

        echo "README.md updated with results"
        sort_table_by_total_time "$README_FILE" "$section_pattern"
    fi
}

main() {
    echo ""
    collect_system_info
    print_system_info

    print_section_header "Installing Dependencies"
    check_prerequisites
    checkout_benchmark_commit
    setup_rust_version
    install_toolchains
    clean_build

    print_section_header "Running Benchmark"

    TOTAL_START=$(date +%s)

    # Phase 1: Build Rust core for Android
    RUST_TIME=$(run_benchmark "1/3" "just generate" "Building Rust Core (Gemstone)")

    # Phase 2: Gradle configuration/sync (triggers dependency resolution)
    GRADLE_SYNC_TIME=$(run_benchmark "2/3" "./gradlew tasks --quiet" "Resolving Gradle Dependencies")

    # Phase 3: Full Gradle build
    BUILD_TIME=$(run_benchmark "3/3" "./gradlew assembleRelease" "Building Android Project")

    TOTAL_END=$(date +%s)
    TOTAL_TIME=$((TOTAL_END - TOTAL_START))

    update_readme "$RUST_TIME" "$GRADLE_SYNC_TIME" "$BUILD_TIME" "$TOTAL_TIME"
    print_results_box "Rust Core Build" "$RUST_TIME" "Gradle Sync" "$GRADLE_SYNC_TIME" "Gradle Build" "$BUILD_TIME" "$TOTAL_TIME"
}

main "$@"
