#!/usr/bin/env zsh

# Performance benchmark script for zrd.zsh platform detection library
# Usage: ./benchmark_zrd.zsh [iterations]

setopt extended_glob
autoload -U colors && colors

# Benchmark configuration
BENCHMARK_LIB_PATH="${0:A:h}/../zrd.zsh"
BENCHMARK_ITERATIONS="${1:-100}"
BENCHMARK_RESULTS_DIR="${0:A:h}/benchmark_results"

# Timing utilities
get_time_ns() {
    if command -v gdate >/dev/null 2>&1; then
        gdate +%s%N
    elif [[ -r /proc/uptime ]]; then
        # Linux fallback
        awk '{print int($1 * 1000000000)}' /proc/uptime
    else
        # Fallback to seconds * 1e9
        echo $(($(date +%s) * 1000000000))
    fi
}

get_time_ms() {
    echo $(($(get_time_ns) / 1000000))
}

format_time() {
    local ns=$1
    local ms=$((ns / 1000000))
    local us=$(((ns % 1000000) / 1000))
    printf "%d.%03dms" $ms $us
}

print_header() {
    print -P "%F{cyan}=================================================================================%f"
    print -P "%F{cyan}$1%f"
    print -P "%F{cyan}=================================================================================%f"
}

print_section() {
    print -P "\n%F{yellow}--- $1 ---%f"
}

# Benchmark functions
benchmark_library_loading() {
    print_section "Library Loading Performance"

    local -a times=()
    local total_time=0
    local i

    print -P "Running $BENCHMARK_ITERATIONS iterations..."

    for ((i = 1; i <= BENCHMARK_ITERATIONS; i++)); do
        local start_time=$(get_time_ns)

        zsh -c "
            unset -m 'ZRD_*' '__ZRD_*' 2>/dev/null
            source '$BENCHMARK_LIB_PATH'
        " >/dev/null 2>&1

        local end_time=$(get_time_ns)
        local elapsed=$((end_time - start_time))

        times+=($elapsed)
        total_time=$((total_time + elapsed))

        if ((i % 10 == 0)); then
            printf "\rProgress: %d/%d" $i $BENCHMARK_ITERATIONS
        fi
    done

    printf "\n"

    # Calculate statistics
    local avg_time=$((total_time / BENCHMARK_ITERATIONS))
    local min_time=${times[1]}
    local max_time=${times[1]}

    for time in "${times[@]}"; do
        ((time < min_time)) && min_time=$time
        ((time > max_time)) && max_time=$time
    done

    # Calculate median (simple approximation)
    local sorted_times=(${(n)times})
    local median_time=${sorted_times[$(((BENCHMARK_ITERATIONS + 1) / 2))]}

    print -P "  Average: $(format_time $avg_time)"
    print -P "  Median:  $(format_time $median_time)"
    print -P "  Min:     $(format_time $min_time)"
    print -P "  Max:     $(format_time $max_time)"

    echo "$avg_time $median_time $min_time $max_time" > "$BENCHMARK_RESULTS_DIR/loading_times.txt"
}

benchmark_detection_performance() {
    print_section "Detection Performance"

    local -a times_first=()
    local -a times_cached=()
    local total_first=0
    local total_cached=0
    local i

    print -P "Running $BENCHMARK_ITERATIONS detection cycles..."

    for ((i = 1; i <= BENCHMARK_ITERATIONS; i++)); do
        # First detection (no cache)
        local start_time=$(get_time_ns)

        zsh -c "
            unset -m 'ZRD_*' '__ZRD_*' 2>/dev/null
            source '$BENCHMARK_LIB_PATH'
            zrd_detect
        " >/dev/null 2>&1

        local end_time=$(get_time_ns)
        local first_elapsed=$((end_time - start_time))

        # Cached detection
        start_time=$(get_time_ns)

        zsh -c "
            unset -m 'ZRD_*' '__ZRD_*' 2>/dev/null
            source '$BENCHMARK_LIB_PATH'
            zrd_detect  # First call
            zrd_detect  # Cached call
        " >/dev/null 2>&1

        end_time=$(get_time_ns)
        local cached_elapsed=$((end_time - start_time))

        times_first+=($first_elapsed)
        times_cached+=($cached_elapsed)
        total_first=$((total_first + first_elapsed))
        total_cached=$((total_cached + cached_elapsed))

        if ((i % 10 == 0)); then
            printf "\rProgress: %d/%d" $i $BENCHMARK_ITERATIONS
        fi
    done

    printf "\n"

    # Calculate statistics for first detection
    local avg_first=$((total_first / BENCHMARK_ITERATIONS))
    local min_first=${times_first[1]}
    local max_first=${times_first[1]}

    for time in "${times_first[@]}"; do
        ((time < min_first)) && min_first=$time
        ((time > max_first)) && max_first=$time
    done

    # Calculate statistics for cached detection
    local avg_cached=$((total_cached / BENCHMARK_ITERATIONS))
    local min_cached=${times_cached[1]}
    local max_cached=${times_cached[1]}

    for time in "${times_cached[@]}"; do
        ((time < min_cached)) && min_cached=$time
        ((time > max_cached)) && max_cached=$time
    done

    print -P "\n%F{cyan}First Detection (no cache):%f"
    print -P "  Average: $(format_time $avg_first)"
    print -P "  Min:     $(format_time $min_first)"
    print -P "  Max:     $(format_time $max_first)"

    print -P "\n%F{cyan}With Cache:%f"
    print -P "  Average: $(format_time $avg_cached)"
    print -P "  Min:     $(format_time $min_cached)"
    print -P "  Max:     $(format_time $max_cached)"

    if ((avg_first > 0)); then
        local speedup=$(((avg_first * 100) / avg_cached))
        print -P "\n%F{green}Cache speedup: ${speedup}% faster%f"
    fi

    # Save results
    {
        echo "first_avg:$avg_first"
        echo "first_min:$min_first"
        echo "first_max:$max_first"
        echo "cached_avg:$avg_cached"
        echo "cached_min:$min_cached"
        echo "cached_max:$max_cached"
    } > "$BENCHMARK_RESULTS_DIR/detection_times.txt"
}

benchmark_api_functions() {
    print_section "API Function Performance"

    local test_env="
        unset ZRD_* __ZRD_* 2>/dev/null
        source '$BENCHMARK_LIB_PATH'
        zrd_detect >/dev/null 2>&1
    "

    # Functions to benchmark
    local -A functions=(
        [zrd_summary]="zrd_summary"
        [zrd_info_summary]="zrd_info summary"
        [zrd_info_json]="zrd_info json"
        [zrd_info_extended]="zrd_info extended"
        [zrd_is_macos]="zrd_is macos"
        [zrd_arch_name]="zrd_arch name"
        [zrd_paths_temp]="zrd_paths temp"
        [zrd_status]="zrd_status"
    )

    local func_name func_call
    for func_name func_call in "${(kv)functions[@]}"; do
        local total_time=0
        local -a times=()
        local i

        printf "Benchmarking %-20s " "$func_name:"

        for ((i = 1; i <= 50; i++)); do  # Fewer iterations for API functions
            local start_time=$(get_time_ns)

            zsh -c "$test_env; $func_call" >/dev/null 2>&1

            local end_time=$(get_time_ns)
            local elapsed=$((end_time - start_time))

            times+=($elapsed)
            total_time=$((total_time + elapsed))
        done

        local avg_time=$((total_time / 50))
        printf "$(format_time $avg_time)\n"

        # Save to results
        echo "$func_name:$avg_time" >> "$BENCHMARK_RESULTS_DIR/api_times.txt"
    done
}

benchmark_memory_usage() {
    print_section "Memory Usage Analysis"

    # This is a rough estimation since zsh doesn't provide direct memory info
    local baseline_size
    local loaded_size
    local detected_size

    if command -v ps >/dev/null 2>&1; then
        # Get baseline memory
        baseline_size=$(zsh -c "sleep 1" & local pid=$!; ps -o rss= -p $pid 2>/dev/null; wait $pid)

        # Get memory with library loaded
        loaded_size=$(zsh -c "source '$BENCHMARK_LIB_PATH'; sleep 1" & local pid=$!; ps -o rss= -p $pid 2>/dev/null; wait $pid)

        # Get memory with detection
        detected_size=$(zsh -c "source '$BENCHMARK_LIB_PATH'; zrd_detect >/dev/null 2>&1; sleep 1" & local pid=$!; ps -o rss= -p $pid 2>/dev/null; wait $pid)

        if [[ -n "$baseline_size" && -n "$loaded_size" && -n "$detected_size" ]]; then
            local loading_overhead=$((loaded_size - baseline_size))
            local detection_overhead=$((detected_size - loaded_size))

            print -P "  Baseline memory:     ${baseline_size} KB"
            print -P "  With library loaded: ${loaded_size} KB (+${loading_overhead} KB)"
            print -P "  With detection:      ${detected_size} KB (+${detection_overhead} KB)"
            print -P "  Total overhead:      $((loaded_size - baseline_size + detection_overhead)) KB"
        else
            print -P "  %F{yellow}Memory measurement unavailable%f"
        fi
    else
        print -P "  %F{yellow}ps command not available for memory measurement%f"
    fi
}

benchmark_scalability() {
    print_section "Scalability Testing"

    print -P "Testing detection performance with multiple concurrent instances..."

    local -a concurrent_levels=(1 5 10 20)
    local level

    for level in "${concurrent_levels[@]}"; do
        printf "  Concurrent level %-2d: " $level

        local start_time=$(get_time_ns)

        local -a pids=()
        local i
        for ((i = 1; i <= level; i++)); do
            zsh -c "
                unset -m 'ZRD_*' '__ZRD_*' 2>/dev/null
                source '$BENCHMARK_LIB_PATH'
                zrd_detect >/dev/null 2>&1
            " &
            pids+=($!)
        done

        # Wait for all to complete
        for pid in "${pids[@]}"; do
            wait $pid
        done

        local end_time=$(get_time_ns)
        local total_time=$((end_time - start_time))
        local avg_time=$((total_time / level))

        printf "$(format_time $avg_time) per instance\n"

        echo "$level:$avg_time" >> "$BENCHMARK_RESULTS_DIR/scalability_times.txt"
    done
}

generate_report() {
    print_section "Generating Performance Report"

    local report_file="$BENCHMARK_RESULTS_DIR/performance_report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "zrd.zsh Performance Benchmark Report"
        echo "=============================================="
        echo "Generated: $(date)"
        echo "Platform: $OSTYPE"
        echo "Iterations: $BENCHMARK_ITERATIONS"
        echo ""

        if [[ -f "$BENCHMARK_RESULTS_DIR/loading_times.txt" ]]; then
            local -a loading_stats=($(cat "$BENCHMARK_RESULTS_DIR/loading_times.txt"))
            echo "Library Loading Performance:"
            echo "  Average: $(format_time ${loading_stats[1]})"
            echo "  Median:  $(format_time ${loading_stats[2]})"
            echo "  Min:     $(format_time ${loading_stats[3]})"
            echo "  Max:     $(format_time ${loading_stats[4]})"
            echo ""
        fi

        if [[ -f "$BENCHMARK_RESULTS_DIR/detection_times.txt" ]]; then
            echo "Detection Performance:"
            local line
            while IFS=: read -r key value; do
                case $key in
                    first_avg) echo "  First detection avg: $(format_time $value)" ;;
                    cached_avg) echo "  Cached detection avg: $(format_time $value)" ;;
                esac
            done < "$BENCHMARK_RESULTS_DIR/detection_times.txt"
            echo ""
        fi

        if [[ -f "$BENCHMARK_RESULTS_DIR/api_times.txt" ]]; then
            echo "API Function Performance:"
            local line
            while IFS=: read -r func_name time; do
                printf "  %-20s %s\n" "$func_name:" "$(format_time $time)"
            done < "$BENCHMARK_RESULTS_DIR/api_times.txt"
            echo ""
        fi

        if [[ -f "$BENCHMARK_RESULTS_DIR/scalability_times.txt" ]]; then
            echo "Scalability Performance:"
            local line
            while IFS=: read -r level time; do
                printf "  %2d concurrent: %s per instance\n" "$level" "$(format_time $time)"
            done < "$BENCHMARK_RESULTS_DIR/scalability_times.txt"
            echo ""
        fi

        echo "Benchmark completed successfully."

    } | tee "$report_file"

    print -P "\n%F{green}Report saved to: $report_file%f"
}

# Main benchmark runner
run_benchmarks() {
    print_header "zrd.zsh Performance Benchmark Suite"

    # Check if library exists
    if [[ ! -f "$BENCHMARK_LIB_PATH" ]]; then
        print -P "%F{red}ERROR: Library not found at $BENCHMARK_LIB_PATH%f"
        exit 1
    fi

    print -P "Library: $BENCHMARK_LIB_PATH"
    print -P "Iterations: $BENCHMARK_ITERATIONS"
    print -P "Platform: $OSTYPE"
    print -P ""

    # Create results directory
    mkdir -p "$BENCHMARK_RESULTS_DIR"

    # Clean up previous results
    rm -f "$BENCHMARK_RESULTS_DIR"/*.txt

    # Run benchmarks
    benchmark_library_loading
    benchmark_detection_performance
    benchmark_api_functions
    benchmark_memory_usage
    benchmark_scalability

    # Generate final report
    generate_report

    print_header "Benchmark Complete"
}

# Quick benchmark mode (fewer iterations)
run_quick_benchmark() {
    BENCHMARK_ITERATIONS=10
    print -P "%F{yellow}Running quick benchmark (10 iterations)...%f"
    run_benchmarks
}

# Script entry point
case "${1:-full}" in
    quick|fast)
        run_quick_benchmark
        ;;
    full|*)
        run_benchmarks
        ;;
esac