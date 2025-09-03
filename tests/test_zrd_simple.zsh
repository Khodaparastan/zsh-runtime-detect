#!/usr/bin/env zsh

# Simple test suite for zrd.zsh platform detection library
# This test works around known command execution issues and tests what actually works

setopt extended_glob
autoload -U colors && colors

# Test configuration
TEST_LIB_PATH="${0:A:h}/../zrd.zsh"

# Test counters
typeset -gi TESTS_TOTAL=0
typeset -gi TESTS_PASSED=0
typeset -gi TESTS_FAILED=0

# Test utilities
print_header() {
    print -P "%F{cyan}=================================%f"
    print -P "%F{cyan}$1%f"
    print -P "%F{cyan}=================================%f"
}

print_section() {
    print -P "\n%F{yellow}--- $1 ---%f"
}

test_pass() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    print -P "  %F{green}✓%f $test_name"
}

test_fail() {
    local test_name="$1" details="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    print -P "  %F{red}✗%f $test_name"
    [[ -n "$details" ]] && print -P "    $details"
}

test_condition() {
    local condition="$1" test_name="$2" details="$3"
    if eval "$condition"; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "$details"
    fi
}

# Main test runner
run_tests() {
    print_header "Simple zrd.zsh Library Test Suite"

    # Check if library exists
    if [[ ! -f "$TEST_LIB_PATH" ]]; then
        print -P "%F{red}ERROR: Library not found at $TEST_LIB_PATH%f"
        exit 1
    fi

    print -P "Library: $TEST_LIB_PATH"
    print -P "Platform: $OSTYPE\n"

    # Test 1: Library Loading
    print_section "Library Loading"

    if source "$TEST_LIB_PATH" 2>/dev/null; then
        test_pass "Library loads without syntax errors"

        # Check if key constants are defined
        test_condition '[[ -n "$__ZRD_MODULE_VERSION" ]]' "Module version constant defined" "Version: $__ZRD_MODULE_VERSION"
        test_condition '[[ -n "$__ZRD_API_VERSION" ]]' "API version constant defined" "API: $__ZRD_API_VERSION"
        test_condition '(( ${+__ZRD_MODULE_LOADED} ))' "Module loaded flag set"

    else
        test_fail "Library loads without syntax errors"
        exit 1
    fi

    # Test 2: Core Functions Exist
    print_section "Function Availability"

    local -a core_functions=(
        zrd_detect zrd_available zrd_refresh zrd_summary
        zrd_info zrd_is zrd_arch zrd_paths zrd_status zrd_cleanup
    )

    local func
    for func in "${core_functions[@]}"; do
        test_condition "typeset -f $func >/dev/null 2>&1" "Function $func is defined"
    done

    # Test 3: Basic Detection
    print_section "Basic Detection"

    # Try detection (may fail due to command issues but should not crash)
    if zrd_detect 2>/dev/null; then
        test_pass "zrd_detect executes without crashing"

        # Test availability after detection
        if zrd_available 2>/dev/null; then
            test_pass "zrd_available returns true after detection"
        else
            test_fail "zrd_available returns true after detection"
        fi

    else
        test_fail "zrd_detect executes without crashing" "May be due to command execution issues"
    fi

    # Test 4: Configuration System
    print_section "Configuration"

    # Test configuration variables exist
    test_condition '(( ${+ZRD_CFG_DEBUG} ))' "ZRD_CFG_DEBUG variable exists"
    test_condition '(( ${+ZRD_CFG_CACHE_TTL} ))' "ZRD_CFG_CACHE_TTL variable exists"
    test_condition '(( ${+ZRD_CFG_AUTO_DETECT} ))' "ZRD_CFG_AUTO_DETECT variable exists"

    # Test configuration bounds
    local validation_result
    validation_result=$(zsh -c "
        ZRD_CFG_DEBUG=999
        source '$TEST_LIB_PATH' 2>&1 | grep -c 'out of bounds'
    " 2>/dev/null)

    if [[ "$validation_result" -gt 0 ]]; then
        test_pass "Configuration validation works (debug level)"
    else
        test_fail "Configuration validation works (debug level)" "Expected validation message not found"
    fi

    # Test 5: Platform Detection Logic
    print_section "Platform Detection Logic"

    # Test platform normalization function exists and works
    if typeset -f __zrd_normalize_platform >/dev/null 2>&1; then
        test_pass "Platform normalization function exists"

        local test_result
        test_result=$(__zrd_normalize_platform "darwin")
        test_condition '[[ "$test_result" == "darwin" ]]' "Platform normalization works" "darwin -> $test_result"

        test_result=$(__zrd_normalize_platform "linux")
        test_condition '[[ "$test_result" == "linux" ]]' "Platform normalization works for linux" "linux -> $test_result"
    else
        test_fail "Platform normalization function exists"
    fi

    # Test architecture normalization
    if typeset -f __zrd_normalize_arch >/dev/null 2>&1; then
        test_pass "Architecture normalization function exists"

        local test_result
        test_result=$(__zrd_normalize_arch "arm64")
        test_condition '[[ "$test_result" == "aarch64" ]]' "Architecture normalization works" "arm64 -> $test_result"
    else
        test_fail "Architecture normalization function exists"
    fi

    # Test 6: Error Handling
    print_section "Error Handling"

    # Test that functions handle invalid arguments gracefully
    if ! zrd_info invalid_type 2>/dev/null; then
        test_pass "zrd_info rejects invalid types"
    else
        test_fail "zrd_info rejects invalid types"
    fi

    if ! zrd_is 2>/dev/null; then
        test_pass "zrd_is requires arguments"
    else
        test_fail "zrd_is requires arguments"
    fi

    # Test 7: Information Functions
    print_section "Information Functions"

    # Try to run detection first
    zrd_detect 2>/dev/null

    # Test info function with version (should always work)
    local version_output
    if version_output=$(zrd_info version 2>/dev/null) && [[ -n "$version_output" ]]; then
        test_pass "zrd_info version works"
    else
        test_fail "zrd_info version works" "Output: '$version_output'"
    fi

    # Test API version
    local api_output
    if api_output=$(zrd_info api-version 2>/dev/null) && [[ -n "$api_output" ]]; then
        test_pass "zrd_info api-version works"
    else
        test_fail "zrd_info api-version works" "Output: '$api_output'"
    fi

    # Test 8: Platform Detection (if working)
    print_section "Platform Detection Tests"

    # Test current platform detection
    case "$OSTYPE" in
    darwin*)
        if zrd_is macos 2>/dev/null; then
            test_pass "Correctly detects macOS"
        else
            test_fail "Correctly detects macOS" "Current OSTYPE: $OSTYPE"
        fi

        if zrd_is unix 2>/dev/null; then
            test_pass "Correctly detects Unix"
        else
            test_fail "Correctly detects Unix"
        fi

        if ! zrd_is linux 2>/dev/null; then
            test_pass "Correctly rejects Linux on macOS"
        else
            test_fail "Correctly rejects Linux on macOS"
        fi
        ;;
    linux*)
        if zrd_is linux 2>/dev/null; then
            test_pass "Correctly detects Linux"
        else
            test_fail "Correctly detects Linux"
        fi

        if ! zrd_is macos 2>/dev/null; then
            test_pass "Correctly rejects macOS on Linux"
        else
            test_fail "Correctly rejects macOS on Linux"
        fi
        ;;
    *)
        test_fail "Unknown platform" "OSTYPE: $OSTYPE"
        ;;
    esac

    # Test 9: Cache System
    print_section "Cache System"

    # Test cache variables exist
    test_condition '(( ${+__ZRD_CACHE_DETECTED} ))' "Cache detection flag exists"
    test_condition '(( ${+__ZRD_CACHE_TIME} ))' "Cache time variable exists"

    # Test refresh function
    if zrd_refresh 2>/dev/null; then
        test_pass "zrd_refresh executes without error"
    else
        test_fail "zrd_refresh executes without error"
    fi

    # Test 10: Cleanup
    print_section "Cleanup"

    # Test status function
    if zrd_status >/dev/null 2>&1; then
        test_pass "zrd_status executes without error"
    else
        test_fail "zrd_status executes without error"
    fi

    # Test cleanup function exists and is callable
    if typeset -f zrd_cleanup >/dev/null 2>&1; then
        test_pass "zrd_cleanup function exists"
    else
        test_fail "zrd_cleanup function exists"
    fi

    # Test 11: Security Features
    print_section "Security Features"

    # Test whitelist exists
    test_condition '(( ${+__ZRD_WHITELIST_CMDS} ))' "Command whitelist exists"

    # Test find command function
    if typeset -f __zrd_find_cmd >/dev/null 2>&1; then
        test_pass "Command finding function exists"

        # Test with a known command
        if __zrd_find_cmd "uname" >/dev/null 2>&1; then
            test_pass "Can find whitelisted commands"
        else
            test_fail "Can find whitelisted commands" "uname not found in whitelist paths"
        fi
    else
        test_fail "Command finding function exists"
    fi

    # Test 12: Auto-detect Feature
    print_section "Auto-detect Feature"

    # Test auto-detect disabled by default
    local auto_detect_val=$ZRD_CFG_AUTO_DETECT
    test_condition '(( ZRD_CFG_AUTO_DETECT == 0 ))' "Auto-detect disabled by default"

    # Final Summary
    print_header "Test Results Summary"
    print -P "Total tests: $TESTS_TOTAL"
    print -P "%F{green}Passed: $TESTS_PASSED%f"
    print -P "%F{red}Failed: $TESTS_FAILED%f"

    if ((TESTS_TOTAL > 0)); then
        local pass_rate=$(((TESTS_PASSED * 100) / TESTS_TOTAL))
        print -P "Pass rate: ${pass_rate}%"
    fi

    if ((TESTS_FAILED == 0)); then
        print -P "\n%F{green}All tests passed!%f"
        return 0
    else
        print -P "\n%F{yellow}Some tests failed. This may be expected due to environment limitations.%f"
        return 1
    fi
}

# Run the tests
run_tests "$@"
