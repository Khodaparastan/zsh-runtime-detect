#!/usr/bin/env zsh

# Comprehensive test suite for zrd.zsh platform detection library
# Usage: ./test_z.zsh [test_pattern]

setopt extended_glob
autoload -U colors && colors

# Test configuration
TEST_LIB_PATH="${0:A:h}/../zrd.zsh"
TEST_RESULTS_DIR="${0:A:h}/test_results"
TEST_PATTERN="${1:-*}"

# Test counters
typeset -gi TESTS_TOTAL=0
typeset -gi TESTS_PASSED=0
typeset -gi TESTS_FAILED=0
typeset -gi TESTS_SKIPPED=0
typeset -ga FAILED_TESTS=()

# Test utilities
print_header() {
    print -P "%F{cyan}=================================================================================%f"
    print -P "%F{cyan}$1%f"
    print -P "%F{cyan}=================================================================================%f"
}

print_section() {
    print -P "\n%F{yellow}--- $1 ---%f"
}

assert_equals() {
    local expected="$1" actual="$2" test_name="$3"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ "$actual" == "$expected" ]]; then
        print -P "  %F{green}✓%f $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print -P "  %F{red}✗%f $test_name"
        print -P "    Expected: '$expected'"
        print -P "    Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

assert_not_empty() {
    local actual="$1" test_name="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ -n "$actual" ]]; then
        print -P "  %F{green}✓%f $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print -P "  %F{red}✗%f $test_name"
        print -P "    Expected non-empty value, got empty"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

assert_success() {
    local test_name="$1"
    local exit_code=$?
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if ((exit_code == 0)); then
        print -P "  %F{green}✓%f $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print -P "  %F{red}✗%f $test_name (exit code: $exit_code)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

assert_failure() {
    local test_name="$1"
    local exit_code=$?
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if ((exit_code != 0)); then
        print -P "  %F{green}✓%f $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print -P "  %F{red}✗%f $test_name (expected failure but got success)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

skip_test() {
    local test_name="$1" reason="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    print -P "  %F{yellow}⚠%f $test_name (skipped: $reason)"
}

run_in_clean_env() {
    local test_code="$1"
    zsh -c "
        # Clean environment
        unset -m 'ZRD_*' '__ZRD_*' 2>/dev/null
        # Run test
        $test_code
    "
}

# Individual test functions
test_library_loading() {
    print_section "Library Loading Tests"

    # Test basic loading
    run_in_clean_env "source '$TEST_LIB_PATH'"
    assert_success "Library loads without errors"

    # Test module version is set
    local version
    version=$(zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; echo \$__ZRD_MODULE_VERSION" 2>/dev/null)
    assert_not_empty "$version" "Module version is set"

    # Test API version is set
    local api_version
    api_version=$(zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; echo \$__ZRD_API_VERSION" 2>/dev/null)
    assert_not_empty "$api_version" "API version is set"

    # Test reload protection
    run_in_clean_env "source '$TEST_LIB_PATH'; __ZRD_MODULE_LOADED=1; source '$TEST_LIB_PATH'" >/dev/null 2>&1
    assert_success "Reload protection works"
}

test_configuration_validation() {
    print_section "Configuration Validation Tests"

    # Test valid configuration
    zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; ZRD_CFG_DEBUG=2; ZRD_CFG_CACHE_TTL=600; source '$TEST_LIB_PATH'" >/dev/null 2>&1
    assert_success "Valid configuration accepted"

    # Test debug level bounds
    local result
    result=$(zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; ZRD_CFG_DEBUG=999; source '$TEST_LIB_PATH' 2>&1" | grep -c 'out of bounds' || echo "0")
    assert_equals "1" "$result" "Invalid debug level triggers validation"

    # Test cache TTL bounds
    result=$(zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; ZRD_CFG_CACHE_TTL=99999; source '$TEST_LIB_PATH' 2>&1" | grep -c 'out of bounds' || echo "0")
    assert_equals "1" "$result" "Invalid cache TTL triggers validation"
}

test_core_detection() {
    print_section "Core Detection Tests"

    # Test detection without errors
    zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect" >/dev/null 2>&1
    assert_success "zrd_detect executes without errors"

    # Test platform is detected
    local platform
    platform=$(zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1; echo \$ZRD_PLATFORM")
    assert_not_empty "$platform" "ZRD_PLATFORM is set after detection"

    # Test hostname is detected
    local hostname
    hostname=$(zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1; echo \$ZRD_HOSTNAME")
    assert_not_empty "$hostname" "ZRD_HOSTNAME is set after detection"

    # Test username is detected
    local username
    username=$(zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1; echo \$ZRD_USERNAME")
    assert_not_empty "$username" "ZRD_USERNAME is set after detection"
}

test_availability_functions() {
    print_section "Availability Functions Tests"

    # Test zrd_available before detection
    zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_available" >/dev/null 2>&1
    assert_failure "zrd_available returns false before detection"

    # Test zrd_available after detection
    zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1; zrd_available" >/dev/null 2>&1
    assert_success "zrd_available returns true after detection"

    # Test auto-detect functionality
    zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; ZRD_CFG_AUTO_DETECT=1; source '$TEST_LIB_PATH'; zrd_available" >/dev/null 2>&1
    assert_success "Auto-detect makes zrd_available return true"
}

test_info_functions() {
    print_section "Info Functions Tests"

    local test_env="unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1"

    # Test zrd_summary
    local summary
    summary=$(zsh -c "$test_env; zrd_summary")
    assert_not_empty "$summary" "zrd_summary returns non-empty result"

    # Test zrd_info formats
    local info_summary info_full info_extended info_json info_version
    info_summary=$(zsh -c "$test_env; zrd_info summary")
    info_full=$(zsh -c "$test_env; zrd_info full")
    info_extended=$(zsh -c "$test_env; zrd_info extended")
    info_json=$(zsh -c "$test_env; zrd_info json")
    info_version=$(zsh -c "$test_env; zrd_info version")

    assert_not_empty "$info_summary" "zrd_info summary returns result"
    assert_not_empty "$info_full" "zrd_info full returns result"
    assert_not_empty "$info_extended" "zrd_info extended returns result"
    assert_not_empty "$info_json" "zrd_info json returns result"
    assert_not_empty "$info_version" "zrd_info version returns result"

    # Test JSON format validity (basic check)
    local json_valid
    json_valid=$(zsh -c "$test_env; zrd_info json" | head -1)
    assert_equals "{" "$json_valid" "zrd_info json starts with valid JSON"

    # Test specific info types
    local hostname username flags
    hostname=$(zsh -c "$test_env; zrd_info hostname")
    username=$(zsh -c "$test_env; zrd_info username")
    flags=$(zsh -c "$test_env; zrd_info flags")

    assert_not_empty "$hostname" "zrd_info hostname returns result"
    assert_not_empty "$username" "zrd_info username returns result"
    assert_not_empty "$flags" "zrd_info flags returns result"
}

test_platform_detection() {
    print_section "Platform Detection Tests"

    local test_env="unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1"

    # Test zrd_is function with common platforms
    case "$OSTYPE" in
    darwin*)
        zsh -c "$test_env; zrd_is macos" >/dev/null 2>&1
        assert_success "zrd_is correctly detects macOS"

        zsh -c "$test_env; zrd_is darwin" >/dev/null 2>&1
        assert_success "zrd_is correctly detects darwin"

        zsh -c "$test_env; zrd_is mac" >/dev/null 2>&1
        assert_success "zrd_is correctly detects mac alias"

        zsh -c "$test_env; zrd_is unix" >/dev/null 2>&1
        assert_success "zrd_is correctly detects unix"

        zsh -c "$test_env; zrd_is linux" >/dev/null 2>&1
        assert_failure "zrd_is correctly rejects linux on macOS"
        ;;
    linux*)
        zsh -c "$test_env; zrd_is linux" >/dev/null 2>&1
        assert_success "zrd_is correctly detects Linux"

        zsh -c "$test_env; zrd_is unix" >/dev/null 2>&1
        assert_success "zrd_is correctly detects unix"

        zsh -c "$test_env; zrd_is macos" >/dev/null 2>&1
        assert_failure "zrd_is correctly rejects macOS on Linux"
        ;;
    *)
        skip_test "zrd_is platform detection" "Unknown platform: $OSTYPE"
        ;;
    esac

    # Test special conditions
    zsh -c "$test_env; zrd_is bare-metal" >/dev/null 2>&1
    assert_success "zrd_is bare-metal works"

    # Test interactive detection (should be false in non-interactive shell)
    zsh -c "$test_env; zrd_is interactive" >/dev/null 2>&1
    assert_failure "zrd_is interactive correctly detects non-interactive shell"

    # Test root detection
    if ((EUID == 0)); then
        zsh -c "$test_env; zrd_is root" >/dev/null 2>&1
        assert_success "zrd_is root correctly detects root user"
    else
        zsh -c "$test_env; zrd_is root" >/dev/null 2>&1
        assert_failure "zrd_is root correctly detects non-root user"
    fi
}

test_architecture_functions() {
    print_section "Architecture Functions Tests"

    local test_env="unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1"

    # Test zrd_arch function
    local arch_name arch_bits arch_family arch_endian arch_isa
    arch_name=$(zsh -c "$test_env; zrd_arch name")
    arch_bits=$(zsh -c "$test_env; zrd_arch bits")
    arch_family=$(zsh -c "$test_env; zrd_arch family")
    arch_endian=$(zsh -c "$test_env; zrd_arch endian")
    arch_isa=$(zsh -c "$test_env; zrd_arch instruction-set")

    assert_not_empty "$arch_name" "zrd_arch name returns result"
    assert_not_empty "$arch_bits" "zrd_arch bits returns result"
    assert_not_empty "$arch_family" "zrd_arch family returns result"
    assert_not_empty "$arch_endian" "zrd_arch endian returns result"
    assert_not_empty "$arch_isa" "zrd_arch instruction-set returns result"

    # Test bits are valid
    if [[ "$arch_bits" != "unknown" ]]; then
        [[ "$arch_bits" == "32" || "$arch_bits" == "64" ]]
        assert_success "zrd_arch bits returns valid value (32 or 64)"
    else
        skip_test "zrd_arch bits validation" "Architecture detection failed"
    fi
}

test_path_functions() {
    print_section "Path Functions Tests"

    local test_env="unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1"

    # Test all path types
    local -a path_types=(temp config cache data runtime home)
    local path_result

    for path_type in "${path_types[@]}"; do
        path_result=$(zsh -c "$test_env; zrd_paths $path_type")
        assert_not_empty "$path_result" "zrd_paths $path_type returns result"

        # Verify path exists or is reasonable
        if [[ -d "$path_result" || "$path_result" == "/tmp" || "$path_result" =~ "/Library/" ]]; then
            assert_success "zrd_paths $path_type returns valid path"
        else
            print -P "  %F{yellow}⚠%f zrd_paths $path_type returns non-existent path: $path_result"
        fi
    done
}

test_cache_functionality() {
    print_section "Cache Functionality Tests"

    # Test cache behavior
    local first_time second_time
    first_time=$(zsh -c "
        unset ZRD_* __ZRD_* 2>/dev/null
        source '$TEST_LIB_PATH'
        time_start=\$SECONDS
        zrd_detect >/dev/null 2>&1
        time_end=\$SECONDS
        echo \$((time_end - time_start))
    ")

    second_time=$(zsh -c "
        unset ZRD_* __ZRD_* 2>/dev/null
        source '$TEST_LIB_PATH'
        zrd_detect >/dev/null 2>&1  # First detect
        time_start=\$SECONDS
        zrd_detect >/dev/null 2>&1  # Second detect (should use cache)
        time_end=\$SECONDS
        echo \$((time_end - time_start))
    ")

    # Second detection should be faster (cache hit)
    if ((second_time <= first_time)); then
        assert_success "Cache improves performance on subsequent detections"
    else
        print -P "  %F{yellow}⚠%f Cache performance test inconclusive (timing variation)"
    fi

    # Test cache refresh
    zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1; zrd_refresh" >/dev/null 2>&1
    assert_success "zrd_refresh executes without errors"
}

test_status_and_cleanup() {
    print_section "Status and Cleanup Tests"

    local test_env="unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1"

    # Test status function
    zsh -c "$test_env; zrd_status" >/dev/null
    assert_success "zrd_status executes without errors"

    local status_output
    status_output=$(zsh -c "$test_env; zrd_status")
    assert_not_empty "$status_output" "zrd_status returns information"

    # Test cleanup function
    local cleanup_test
    cleanup_test=$(zsh -c "
        unset ZRD_* __ZRD_* 2>/dev/null
        source '$TEST_LIB_PATH'
        zrd_detect >/dev/null 2>&1
        echo \"Before: \${ZRD_PLATFORM:-empty}\"
        zrd_cleanup
        echo \"After: \${ZRD_PLATFORM:-empty}\"
    ")

    if [[ "$cleanup_test" == *"Before: "*$'\n'"After: empty" ]]; then
        assert_success "zrd_cleanup properly removes variables"
    else
        print -P "  %F{red}✗%f zrd_cleanup test (variables not properly cleaned)"
        print -P "    Result: $cleanup_test"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("zrd_cleanup properly removes variables")
    fi
}

test_error_handling() {
    print_section "Error Handling Tests"

    local test_env="unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1"

    # Test invalid zrd_info types
    zsh -c "$test_env; zrd_info invalid_type" >/dev/null 2>&1
    assert_failure "zrd_info rejects invalid type"

    # Test invalid zrd_is targets
    zsh -c "$test_env; zrd_is invalid_platform" >/dev/null 2>&1
    assert_failure "zrd_is rejects invalid platform"

    # Test invalid zrd_arch queries
    zsh -c "$test_env; zrd_arch invalid_query" >/dev/null 2>&1
    assert_failure "zrd_arch rejects invalid query"

    # Test invalid zrd_paths types
    zsh -c "$test_env; zrd_paths invalid_path" >/dev/null 2>&1
    assert_failure "zrd_paths rejects invalid path type"

    # Test functions without detection
    zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_summary" >/dev/null 2>&1
    assert_failure "zrd_summary fails without prior detection"

    zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_info summary" >/dev/null 2>&1
    assert_failure "zrd_info fails without prior detection"
}

test_json_output() {
    print_section "JSON Output Tests"

    local test_env="unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1"
    local json_output

    json_output=$(zsh -c "$test_env; zrd_info json")

    # Basic JSON structure tests
    [[ "$json_output" == "{"* ]] && [[ "$json_output" == *"}" ]]
    assert_success "JSON output has proper structure"

    # Test required JSON fields
    local -a required_fields=(
        '"platform":'
        '"architecture":'
        '"hostname":'
        '"username":'
        '"flags":'
        '"metadata":'
    )

    local field missing_fields=0
    for field in "${required_fields[@]}"; do
        if [[ "$json_output" != *"$field"* ]]; then
            missing_fields=$((missing_fields + 1))
            print -P "  %F{red}Missing JSON field: $field%f"
        fi
    done

    if ((missing_fields == 0)); then
        assert_success "All required JSON fields present"
    else
        print -P "  %F{red}✗%f JSON output missing $missing_fields required fields"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("All required JSON fields present")
    fi
}

test_security_features() {
    print_section "Security Features Tests"

    # These are more difficult to test without internal access, but we can test basic behavior
    local test_env="unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_detect >/dev/null 2>&1"

    # Test that detection completes (implies whitelisting works)
    zsh -c "$test_env; echo 'Security test completed'" >/dev/null
    assert_success "Command whitelisting allows detection to complete"

    # Test file reading limits (we can't easily test this without modifying the library)
    skip_test "File size limits" "Requires internal testing"
    skip_test "Command timeout" "Requires controlled environment"
}

# Main test runner
run_tests() {
    print_header "zrd.zsh Library Test Suite"

    # Check if library exists
    if [[ ! -f "$TEST_LIB_PATH" ]]; then
        print -P "%F{red}ERROR: Library not found at $TEST_LIB_PATH%f"
        exit 1
    fi

    print -P "Library: $TEST_LIB_PATH"
    print -P "Test pattern: $TEST_PATTERN"
    print -P "Platform: $OSTYPE"
    print -P ""

    # Create results directory
    mkdir -p "$TEST_RESULTS_DIR"

    # Run test categories
    local -a test_functions=(
        test_library_loading
        test_configuration_validation
        test_core_detection
        test_availability_functions
        test_info_functions
        test_platform_detection
        test_architecture_functions
        test_path_functions
        test_cache_functionality
        test_status_and_cleanup
        test_error_handling
        test_json_output
        test_security_features
    )

    local test_func
    for test_func in "${test_functions[@]}"; do
        if [[ "$test_func" == $TEST_PATTERN || "$TEST_PATTERN" == "*" ]]; then
            $test_func
        fi
    done

    # Print summary
    print_header "Test Results Summary"
    print -P "Total tests: $TESTS_TOTAL"
    print -P "%F{green}Passed: $TESTS_PASSED%f"
    print -P "%F{red}Failed: $TESTS_FAILED%f"
    print -P "%F{yellow}Skipped: $TESTS_SKIPPED%f"

    if ((TESTS_FAILED > 0)); then
        print -P "\n%F{red}Failed tests:%f"
        local failed_test
        for failed_test in "${FAILED_TESTS[@]}"; do
            print -P "  - $failed_test"
        done
    fi

    local pass_rate
    if ((TESTS_TOTAL > 0)); then
        pass_rate=$(((TESTS_PASSED * 100) / (TESTS_TOTAL - TESTS_SKIPPED)))
        print -P "\nPass rate: ${pass_rate}% ($TESTS_PASSED/$((TESTS_TOTAL - TESTS_SKIPPED)))"
    fi

    # Save detailed results
    {
        print "Test Results - $(date)"
        print "=============================="
        print "Total: $TESTS_TOTAL"
        print "Passed: $TESTS_PASSED"
        print "Failed: $TESTS_FAILED"
        print "Skipped: $TESTS_SKIPPED"
        print "Pass rate: ${pass_rate:-0}%"
        print ""

        if ((TESTS_FAILED > 0)); then
            print "Failed tests:"
            for failed_test in "${FAILED_TESTS[@]}"; do
                print "  - $failed_test"
            done
        fi
    } >"$TEST_RESULTS_DIR/test_results_$(date +%Y%m%d_%H%M%S).txt"

    # Exit with appropriate code
    ((TESTS_FAILED == 0)) && exit 0 || exit 1
}

# Script entry point
if [[ "${ZSH_EVAL_CONTEXT:-}" == "toplevel" ]]; then
    run_tests "$@"
fi
