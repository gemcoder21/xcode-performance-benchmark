#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/gem-ios"
README_FILE="$SCRIPT_DIR/README.md"
REPO_URL="https://github.com/gemwalletcom/gem-ios.git"

# Source shared functions
. "$SCRIPT_DIR/common.sh"

clone_repo() {
    if [ ! -d "$PROJECT_ROOT" ]; then
        echo "Cloning gem-ios repository..."
        git clone --recursive "$REPO_URL" "$PROJECT_ROOT"
    fi
}

clone_repo
cd "$PROJECT_ROOT"

# Get benchmark config for Xcode version
# Returns: BENCHMARK_COMMIT and BENCHMARK_RUST_VERSION
get_benchmark_config() {
    case "$1" in
        "26.2")
            BENCHMARK_COMMIT="28c46f7f"
            BENCHMARK_RUST_VERSION="1.92.0"
            ;;
        # Add new versions here:
        # "26.3")
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
    XCODE_VERSION=$(xcodebuild -version | head -1 | awk '{print $2}')
    XCODE_BUILD=$(xcodebuild -version | tail -1 | awk '{print $3}')
}

print_system_info() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║             Xcode Performance Build Benchmark                ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Device:     $DEVICE_NAME"
    echo "║ Chip:       $CHIP_SHORT"
    echo "║ Cores:      $CORES"
    echo "║ Memory:     ${MEMORY_GB}GB"
    echo "║ macOS:      $OS_VERSION"
    echo "║ Xcode:      $XCODE_VERSION ($XCODE_BUILD)"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

check_ios_simulator_runtime() {
    if ! xcrun simctl list runtimes 2>/dev/null | grep -q "^iOS"; then
        echo "Installing iOS simulator runtime..."
        xcodebuild -downloadPlatform iOS
    fi
}

check_prerequisites() {
    echo "Checking and installing prerequisites..."

    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "Error: Xcode command line tools not found. Please install Xcode from the App Store."
        exit 1
    fi

    check_ios_simulator_runtime

    install_homebrew
    install_rust
    install_just

    if ! command -v xcbeautify >/dev/null 2>&1; then
        echo "Installing xcbeautify..."
        brew install xcbeautify
    fi

    if ! command -v swiftformat >/dev/null 2>&1; then
        echo "Installing swiftformat..."
        brew install swiftformat
    fi

    if ! command -v swiftgen >/dev/null 2>&1; then
        echo "Installing swiftgen..."
        brew install swiftgen
    fi

    echo ""
    echo "Prerequisites installed:"
    echo "  Rust:        $(rustc --version | awk '{print $2}')"
    echo "  Just:        $(just --version | awk '{print $2}')"
    echo "  xcbeautify:  $(xcbeautify --version)"
    echo ""
}

install_toolchains() {
    echo "Installing Rust iOS toolchains..."
    just install-toolchains 2>/dev/null || true
}

checkout_benchmark_commit() {
    get_benchmark_config "$XCODE_VERSION"

    if [ -n "$BENCHMARK_COMMIT" ]; then
        echo "Benchmark config for Xcode $XCODE_VERSION:"
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
        echo "Warning: No benchmark config defined for Xcode $XCODE_VERSION"
        echo "Using current HEAD"
        BENCHMARK_COMMIT=$(git rev-parse --short HEAD)
    fi
}

setup_rust_version() {
    get_benchmark_config "$XCODE_VERSION"

    if [ -n "$BENCHMARK_RUST_VERSION" ]; then
        echo "Setting up Rust $BENCHMARK_RUST_VERSION for Xcode $XCODE_VERSION..."
        rustup install "$BENCHMARK_RUST_VERSION" 2>/dev/null || true
        rustup default "$BENCHMARK_RUST_VERSION"
        echo "  Rust version: $(rustc --version)"
    else
        echo "Warning: No Rust version defined for Xcode $XCODE_VERSION, using default"
        BENCHMARK_RUST_VERSION=$(rustc --version | awk '{print $2}')
    fi
}

clean_build() {
    echo "Cleaning previous build..."
    just clean 2>/dev/null || true
    rm -rf build/DerivedData 2>/dev/null || true
    # Clean Rust build cache for accurate benchmark
    cargo clean --manifest-path core/Cargo.toml 2>/dev/null || true
}

update_readme() {
    rust_time=$1
    spm_time=$2
    build_time=$3
    total_time=$4

    # Format times for display
    rust_fmt=$(format_duration "$rust_time")
    spm_fmt=$(format_duration "$spm_time")
    build_fmt=$(format_duration "$build_time")
    total_fmt=$(format_duration "$total_time")

    # Create the new table row
    new_row="| $DEVICE_NAME | $CHIP_SHORT | $CORES | ${MEMORY_GB}GB | $rust_fmt | $spm_fmt | $build_fmt | $total_fmt |"

    # Find the Xcode version section
    section_pattern="### Xcode $XCODE_VERSION"

    if ! grep -q "$section_pattern" "$README_FILE"; then
        echo "Warning: Section for Xcode $XCODE_VERSION not found in README.md"
        echo "Please add results manually"
        return
    fi

    # Find section boundaries to search within
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

    RUST_TIME=$(run_benchmark "1/3" "just generate-stone" "Building Rust Core (Gemstone)")
    SPM_TIME=$(run_benchmark "2/3" "just spm-resolve" "Resolving SPM Dependencies")
    BUILD_TIME=$(run_benchmark "3/3" "just build" "Building Xcode Project")

    TOTAL_END=$(date +%s)
    TOTAL_TIME=$((TOTAL_END - TOTAL_START))

    update_readme "$RUST_TIME" "$SPM_TIME" "$BUILD_TIME" "$TOTAL_TIME"
    print_results_box "Rust Core Build" "$RUST_TIME" "SPM Resolve" "$SPM_TIME" "Xcode Build" "$BUILD_TIME" "$TOTAL_TIME"
}

main "$@"
