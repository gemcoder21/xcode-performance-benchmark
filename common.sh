#!/bin/sh
# Shared functions for iOS and Android benchmarks

# Clean device name: remove possessive prefixes like "John's " or "sou's "
clean_device_name() {
    echo "$1" | sed "s/^[^']*'s //"
}

collect_base_system_info() {
    RAW_DEVICE_NAME=$(scutil --get ComputerName 2>/dev/null || hostname)
    DEVICE_NAME=$(clean_device_name "$RAW_DEVICE_NAME")
    CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    CORES=$(sysctl -n hw.ncpu)
    MEMORY_BYTES=$(sysctl -n hw.memsize)
    MEMORY_GB=$((MEMORY_BYTES / 1073741824))
    OS_VERSION=$(sw_vers -productVersion)

    case "$CHIP" in
        *Apple*)
            CHIP_SHORT=$(echo "$CHIP" | sed 's/Apple //')
            ;;
        *)
            CHIP_SHORT="$CHIP"
            ;;
    esac
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

install_just() {
    if ! command -v just >/dev/null 2>&1; then
        echo "Installing just..."
        brew install just
    fi
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

sort_table_by_total_time() {
    readme_file=$1
    section_pattern=$2

    # Find section boundaries
    section_start=$(grep -n "$section_pattern" "$readme_file" | head -1 | cut -d: -f1)
    if [ -z "$section_start" ]; then
        return
    fi

    # Find where data rows start
    data_start=$((section_start + 4))

    # Find next section or end of file
    next_section=$(tail -n +$((section_start + 1)) "$readme_file" | grep -n "^### \|^---\|^## " | head -1 | cut -d: -f1)
    if [ -n "$next_section" ]; then
        section_end=$((section_start + next_section - 1))
    else
        section_end=$(wc -l < "$readme_file" | tr -d ' ')
    fi

    # Find last data row (rows starting with |)
    data_end=$data_start
    for i in $(seq $data_start $section_end); do
        line=$(sed -n "${i}p" "$readme_file")
        if echo "$line" | grep -q "^| "; then
            data_end=$i
        else
            break
        fi
    done

    # If we have data rows, sort them
    if [ "$data_end" -ge "$data_start" ]; then
        # Extract data rows, sort by total time (last column), then replace
        sorted_rows=$(sed -n "${data_start},${data_end}p" "$readme_file" | while read -r row; do
            # Extract total time and convert to seconds for sorting
            total_str=$(echo "$row" | awk -F'|' '{print $(NF-1)}' | xargs)
            total_secs=$(parse_time_to_seconds "$total_str")
            echo "$total_secs|$row"
        done | sort -t'|' -k1 -n | cut -d'|' -f2-)

        # Create temp file with sorted content
        {
            head -n $((data_start - 1)) "$readme_file"
            echo "$sorted_rows"
            tail -n +$((data_end + 1)) "$readme_file"
        } > "$readme_file.tmp"
        mv "$readme_file.tmp" "$readme_file"
    fi
}

print_section_header() {
    title=$1
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                    $title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_results_box() {
    phase1_name=$1
    phase1_time=$2
    phase2_name=$3
    phase2_time=$4
    phase3_name=$5
    phase3_time=$6
    total_time=$7

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                      Benchmark Results                       ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║ %-20s %40s ║\n" "$phase1_name:" "$(format_duration $phase1_time)"
    printf "║ %-20s %40s ║\n" "$phase2_name:" "$(format_duration $phase2_time)"
    printf "║ %-20s %40s ║\n" "$phase3_name:" "$(format_duration $phase3_time)"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║ %-20s %40s ║\n" "Total Time:" "$(format_duration $total_time)"
    echo "╚══════════════════════════════════════════════════════════════╝"
}
