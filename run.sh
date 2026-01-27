#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/gem-ios"
RESULTS_FILE="$SCRIPT_DIR/results.csv"
README_FILE="$SCRIPT_DIR/README.md"
REPO_URL="https://github.com/gemwalletcom/gem-ios.git"

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
    DEVICE_NAME=$(scutil --get ComputerName 2>/dev/null || hostname)
    CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    CORES=$(sysctl -n hw.ncpu)
    MEMORY_BYTES=$(sysctl -n hw.memsize)
    MEMORY_GB=$((MEMORY_BYTES / 1073741824))
    MACOS_VERSION=$(sw_vers -productVersion)
    XCODE_VERSION=$(xcodebuild -version | head -1 | awk '{print $2}')
    XCODE_BUILD=$(xcodebuild -version | tail -1 | awk '{print $3}')

    case "$CHIP" in
        *Apple*)
            CHIP_SHORT=$(echo "$CHIP" | sed 's/Apple //')
            ;;
        *)
            CHIP_SHORT="$CHIP"
            ;;
    esac
}

collect_code_stats() {
    # Count Swift lines (excluding Packages/Build and derived data)
    SWIFT_LINES=$(find . -name "*.swift" -not -path "./Packages/Build/*" -not -path "./build/*" -not -path "./.build/*" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
    SWIFT_FILES=$(find . -name "*.swift" -not -path "./Packages/Build/*" -not -path "./build/*" -not -path "./.build/*" | wc -l | tr -d ' ')

    # Count Rust lines in core/
    RUST_LINES=$(find ./core -name "*.rs" -not -path "./core/target/*" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
    RUST_FILES=$(find ./core -name "*.rs" -not -path "./core/target/*" | wc -l | tr -d ' ')

    # Format with thousands separator
    SWIFT_LINES_FMT=$(printf "%'d" "$SWIFT_LINES" 2>/dev/null || echo "$SWIFT_LINES")
    RUST_LINES_FMT=$(printf "%'d" "$RUST_LINES" 2>/dev/null || echo "$RUST_LINES")
}

print_system_info() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              Gem Wallet iOS Build Benchmark                  ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Device:     $DEVICE_NAME"
    echo "║ Chip:       $CHIP_SHORT"
    echo "║ Cores:      $CORES"
    echo "║ Memory:     ${MEMORY_GB}GB"
    echo "║ macOS:      $MACOS_VERSION"
    echo "║ Xcode:      $XCODE_VERSION ($XCODE_BUILD)"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

install_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        case "$(uname -m)" in
            arm64)
                eval "$(/opt/homebrew/bin/brew shellenv)"
                ;;
            *)
                eval "$(/usr/local/bin/brew shellenv)"
                ;;
        esac
    fi
}

install_rust() {
    if ! command -v rustc >/dev/null 2>&1; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        . "$HOME/.cargo/env"
    fi
}

check_prerequisites() {
    echo "Checking and installing prerequisites..."

    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "Error: Xcode command line tools not found. Please install Xcode from the App Store."
        exit 1
    fi

    install_homebrew
    install_rust

    if ! command -v just >/dev/null 2>&1; then
        echo "Installing just..."
        brew install just
    fi

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

run_benchmark() {
    phase=$1
    cmd=$2
    description=$3

    echo "[$phase] $description..." >&2

    START_TIME=$(date +%s)

    eval "$cmd" > /dev/null 2>&1

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo "[$phase] Completed in ${DURATION}s" >&2
    echo "$DURATION"
}

format_duration() {
    seconds=$1
    minutes=$((seconds / 60))
    remaining_seconds=$((seconds % 60))

    if [ "$minutes" -gt 0 ]; then
        echo "${minutes}m ${remaining_seconds}s"
    else
        echo "${seconds}s"
    fi
}

save_results() {
    rust_time=$1
    spm_time=$2
    build_time=$3
    total_time=$4
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ ! -f "$RESULTS_FILE" ]; then
        echo "timestamp,device,chip,cores,memory_gb,macos,xcode,rust_build_sec,spm_resolve_sec,xcode_build_sec,total_sec,git_commit" > "$RESULTS_FILE"
    fi

    echo "$timestamp,\"$DEVICE_NAME\",\"$CHIP_SHORT\",$CORES,$MEMORY_GB,$MACOS_VERSION,$XCODE_VERSION,$rust_time,$spm_time,$build_time,$total_time,$BENCHMARK_COMMIT" >> "$RESULTS_FILE"
}

parse_time_to_seconds() {
    time_str=$1
    minutes=0
    seconds=0

    # Handle "Xm Ys" format
    if echo "$time_str" | grep -q "m"; then
        minutes=$(echo "$time_str" | sed 's/m.*//')
        seconds=$(echo "$time_str" | sed 's/.*m //' | sed 's/s//')
    else
        # Handle "Xs" format
        seconds=$(echo "$time_str" | sed 's/s//')
    fi

    echo $((minutes * 60 + seconds))
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
    new_row="| $DEVICE_NAME | $CHIP_SHORT | $CORES | ${MEMORY_GB}GB | $MACOS_VERSION | $rust_fmt | $spm_fmt | $build_fmt | $total_fmt |"

    # Find the Xcode version section
    section_header="### Xcode $XCODE_VERSION"

    if ! grep -q "$section_header" "$README_FILE"; then
        echo "Warning: Section '$section_header' not found in README.md"
        echo "Please add results manually"
        return
    fi

    # Check if this device already has an entry
    existing_line=$(grep "| $DEVICE_NAME |" "$README_FILE" | head -1)

    if [ -n "$existing_line" ]; then
        # Extract existing total time (last column before final |)
        existing_total=$(echo "$existing_line" | awk -F'|' '{print $(NF-1)}' | xargs)
        existing_seconds=$(parse_time_to_seconds "$existing_total")

        if [ "$total_time" -lt "$existing_seconds" ]; then
            # New time is better, replace the line
            escaped_line=$(echo "$existing_line" | sed 's/[[\.*^$()+?{|]/\\&/g')
            sed -i '' "s|$escaped_line|$new_row|" "$README_FILE"
            echo "README.md updated with faster results (${total_fmt} vs ${existing_total})"
        else
            echo "Existing result is faster or equal (${existing_total} vs ${total_fmt}), not updating README"
        fi
    else
        # No existing entry, add new row after the table separator line
        line_num=$(grep -n "$section_header" "$README_FILE" | head -1 | cut -d: -f1)
        insert_line=$((line_num + 5))

        sed -i '' "${insert_line}a\\
${new_row}
" "$README_FILE"

        echo "README.md updated with results"
    fi
}

print_results() {
    rust_time=$1
    spm_time=$2
    build_time=$3
    total_time=$4

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                      Benchmark Results                       ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║ %-20s %40s ║\n" "Rust Core Build:" "$(format_duration $rust_time)"
    printf "║ %-20s %40s ║\n" "SPM Resolve:" "$(format_duration $spm_time)"
    printf "║ %-20s %40s ║\n" "Xcode Build:" "$(format_duration $build_time)"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║ %-20s %40s ║\n" "Total Time:" "$(format_duration $total_time)"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Results saved to: $RESULTS_FILE"
}

main() {
    echo ""
    collect_system_info
    print_system_info

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                    Installing Dependencies                     "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    check_prerequisites
    checkout_benchmark_commit
    setup_rust_version
    install_toolchains
    clean_build

    echo ""
    echo "Collecting code stats..."
    collect_code_stats

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                      Running Benchmark                         "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Codebase size (commit $BENCHMARK_COMMIT):"
    echo "  Swift: $SWIFT_LINES_FMT lines ($SWIFT_FILES files)"
    echo "  Rust:  $RUST_LINES_FMT lines ($RUST_FILES files)"
    echo ""

    TOTAL_START=$(date +%s)

    RUST_TIME=$(run_benchmark "1/3" "just generate-stone" "Building Rust Core (Gemstone)")
    SPM_TIME=$(run_benchmark "2/3" "just spm-resolve" "Resolving SPM Dependencies")
    BUILD_TIME=$(run_benchmark "3/3" "just build" "Building Xcode Project")

    TOTAL_END=$(date +%s)
    TOTAL_TIME=$((TOTAL_END - TOTAL_START))

    save_results "$RUST_TIME" "$SPM_TIME" "$BUILD_TIME" "$TOTAL_TIME"
    update_readme "$RUST_TIME" "$SPM_TIME" "$BUILD_TIME" "$TOTAL_TIME"
    print_results "$RUST_TIME" "$SPM_TIME" "$BUILD_TIME" "$TOTAL_TIME"
}

main "$@"
