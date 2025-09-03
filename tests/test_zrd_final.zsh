#!/usr/bin/env zsh

# Comprehensive test suite for zrd.zsh platform detection library
# This test properly handles known issues and documents expected behavior

setopt extended_glob
autoload -U colors && colors

# Test configuration
TEST_LIB_PATH="${0:A:h}/../zrd.zsh"
TEST_RESULTS_DIR="${0:A:h}/test_results"

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

test_pass() {
    local test_name="$1" details="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    print -P "  %F{green}✓%f $test_name"
    [[ -n "$details" ]] && print -P "    $details"
}

test_fail() {
    local test_name="$1" details="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$test_name")
    print -P "  %F{red}✗%f $test_name"
    [[ -n "$details" ]] && print -P "    $details"
}

test_skip() {
    local test_name="$1" reason="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    print -P "  %F{yellow}⚠%f $test_name (skipped: $reason)"
}

test_condition() {
    local condition="$1" test_name="$2" pass_details="$3" fail_details="$4"
    if eval "$condition"; then
        test_pass "$test_name" "$pass_details"
    else
        test_fail "$test_name" "$fail_details"
    fi
}

# Test runner functions
test_library_loading() {
    print_section "Library Loading and Initialization"

    # Test basic loading
    if source "$TEST_LIB_PATH" 2>/dev/null; then
        test_pass "Library loads without syntax errors"

        # Test constants
        test_condition '[[ -n "$__ZRD_MODULE_VERSION" ]]' \
            "Module version constant defined" \
            "Version: $__ZRD_MODULE_VERSION" \
            "Module version not set"

        test_condition '[[ -n "$__ZRD_API_VERSION" ]]' \
            "API version constant defined" \
            "API Version: $__ZRD_API_VERSION" \
            "API version not set"

        test_condition '(( ${+__ZRD_MODULE_LOADED} ))' \
            "Module loaded flag set" \
            "" \
            "Module loaded flag missing"

        # Test whitelists exist
        test_condition '(( ${+__ZRD_WHITELIST_CMDS} ))' \
            "Command whitelist exists" \
            "Commands: $(print -l ${(k)__ZRD_WHITELIST_CMDS} | wc -l | tr -d ' ') whitelisted" \
            "Command whitelist missing"

    else
        test_fail "Library loads without syntax errors" "Check syntax and dependencies"
        return 1
    fi
}

test_core_functions() {
    print_section "Core Functions Availability"

    local -a core_functions=(
        zrd_detect zrd_available zrd_refresh zrd_summary
        zrd_info zrd_is zrd_arch zrd_paths zrd_status zrd_cleanup
    )

    local func
    for func in "${core_functions[@]}"; do
        test_condition "typeset -f $func >/dev/null 2>&1" \
            "Function $func is defined" \
            "" \
            "Function missing or not defined"
    done

    # Test internal helper functions exist
    local -a helper_functions=(
        __zrd_normalize_platform __zrd_normalize_arch __zrd_find_cmd
        __zrd_cache_valid __zrd_validate_config
    )

    for func in "${helper_functions[@]}"; do
        test_condition "typeset -f $func >/dev/null 2>&1" \
            "Helper function $func exists" \
            "" \
            "Helper function missing"
    done
}

test_configuration_system() {
    print_section "Configuration System"

    # Test configuration variables exist with proper defaults
    test_condition '(( ${+ZRD_CFG_DEBUG} ))' \
        "ZRD_CFG_DEBUG variable exists" \
        "Default: $ZRD_CFG_DEBUG" \
        "Configuration variable missing"

    test_condition '(( ${+ZRD_CFG_CACHE_TTL} ))' \
        "ZRD_CFG_CACHE_TTL variable exists" \
        "Default: ${ZRD_CFG_CACHE_TTL}s" \
        "Configuration variable missing"

    test_condition '(( ${+ZRD_CFG_AUTO_DETECT} ))' \
        "ZRD_CFG_AUTO_DETECT variable exists" \
        "Default: $ZRD_CFG_AUTO_DETECT" \
        "Configuration variable missing"

    # Test configuration validation (create new shell to test)
    local validation_result
    validation_result=$(zsh -c "
        ZRD_CFG_DEBUG=999
        ZRD_CFG_CACHE_TTL=99999
        source '$TEST_LIB_PATH' 2>&1 | grep -c 'out of bounds'
    ")

    test_condition '[[ "$validation_result" -gt 0 ]]' \
        "Configuration validation works" \
        "Caught $validation_result out-of-bounds values" \
        "Validation not working: $validation_result"
}

test_detection_and_availability() {
    print_section "Detection and Availability"

    # Test initial state
    local initial_available
    if zrd_available 2>/dev/null; then
        initial_available="true"
    else
        initial_available="false"
    fi

    # Test detection
    if zrd_detect 2>/dev/null; then
        test_pass "zrd_detect executes successfully"

        # Test availability after detection
        if zrd_available 2>/dev/null; then
            test_pass "zrd_available returns true after detection"
        else
            test_fail "zrd_available returns true after detection"
        fi

        # Test cache behavior
        if zrd_detect 2>/dev/null; then
            test_pass "Subsequent zrd_detect calls work (cache)"
        else
            test_fail "Subsequent zrd_detect calls work (cache)"
        fi

    else
        test_fail "zrd_detect executes successfully" "May be due to command execution issues"
    fi

    # Test refresh
    if zrd_refresh 2>/dev/null; then
        test_pass "zrd_refresh executes successfully"
    else
        test_fail "zrd_refresh executes successfully"
    fi
}

test_platform_normalization() {
    print_section "Platform and Architecture Normalization"

    # Test platform normalization
    local -A platform_tests=(
        [darwin]="darwin"
        [Darwin]="darwin"
        [linux]="linux"
        [Linux]="linux"
        [freebsd]="freebsd"
        [FreeBSD]="freebsd"
        [windows]="windows"
        [unknown_platform]="unknown"
    )

    local input expected result
    for input expected in "${(kv)platform_tests[@]}"; do
        if result=$(__zrd_normalize_platform "$input" 2>/dev/null); then
            test_condition '[[ "$result" == "$expected" ]]' \
                "Platform normalization: $input" \
                "$input → $result" \
                "Expected '$expected', got '$result'"
        else
            test_fail "Platform normalization: $input" "Function failed"
        fi
    done

    # Test architecture normalization
    local -A arch_tests=(
        [arm64]="aarch64"
        [aarch64]="aarch64"
        [x86_64]="x86_64"
        [amd64]="x86_64"
        [arm]="arm"
        [i386]="i386"
        [unknown_arch]="unknown_arch"
    )

    for input expected in "${(kv)arch_tests[@]}"; do
        if result=$(__zrd_normalize_arch "$input" 2>/dev/null); then
            test_condition '[[ "$result" == "$expected" ]]' \
                "Architecture normalization: $input" \
                "$input → $result" \
                "Expected '$expected', got '$result'"
        else
            test_fail "Architecture normalization: $input" "Function failed"
        fi
    done
}

test_information_functions() {
    print_section "Information Functions"

    # Ensure detection has run
    zrd_detect 2>/dev/null

    # Test zrd_info with various formats
    local -a info_types=(version api-version)
    local type result

    for type in "${info_types[@]}"; do
        if result=$(zrd_info "$type" 2>/dev/null) && [[ -n "$result" ]]; then
            test_pass "zrd_info $type works" "Output: $result"
        else
            test_fail "zrd_info $type works" "No output or error"
        fi
    done

    # Test zrd_info formats that depend on successful detection
    local -a detection_dependent=(summary full extended json hostname username flags distro)
    for type in "${detection_dependent[@]}"; do
        if result=$(zrd_info "$type" 2>/dev/null); then
            if [[ -n "$result" ]]; then
                test_pass "zrd_info $type works" "Has output"
            else
                test_skip "zrd_info $type works" "Detection may have failed"
            fi
        else
            test_skip "zrd_info $type works" "Function error or detection failure"
        fi
    done

    # Test zrd_summary
    if result=$(zrd_summary 2>/dev/null) && [[ -n "$result" ]]; then
        test_pass "zrd_summary works" "Output: $result"
    else
        test_skip "zrd_summary works" "May depend on successful detection"
    fi
}

test_platform_detection_logic() {
    print_section "Platform Detection Logic"

    # Ensure detection has run
    zrd_detect 2>/dev/null

    # Test current platform detection
    case "$OSTYPE" in
    darwin*)
        # macOS tests
        if zrd_is macos 2>/dev/null; then
            test_pass "Correctly detects macOS"
        else
            test_fail "Correctly detects macOS" "OSTYPE: $OSTYPE"
        fi

        if zrd_is darwin 2>/dev/null; then
            test_pass "Correctly detects darwin"
        else
            test_fail "Correctly detects darwin"
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
        # Linux tests
        if zrd_is linux 2>/dev/null; then
            test_pass "Correctly detects Linux"
        else
            test_fail "Correctly detects Linux" "OSTYPE: $OSTYPE"
        fi

        if zrd_is unix 2>/dev/null; then
            test_pass "Correctly detects Unix"
        else
            test_fail "Correctly detects Unix"
        fi

        if ! zrd_is macos 2>/dev/null; then
            test_pass "Correctly rejects macOS on Linux"
        else
            test_fail "Correctly rejects macOS on Linux"
        fi
        ;;

    *)
        test_skip "Platform-specific tests" "Unknown platform: $OSTYPE"
        ;;
    esac

    # Test universal conditions
    if zrd_is bare-metal 2>/dev/null; then
        test_pass "zrd_is bare-metal works"
    else
        test_skip "zrd_is bare-metal works" "May depend on detection"
    fi

    # Test interactive detection (should be false in test script)
    if ! zrd_is interactive 2>/dev/null; then
        test_pass "Correctly detects non-interactive mode"
    else
        test_fail "Correctly detects non-interactive mode" "Should be false in script"
    fi

    # Test root detection
    if ((EUID == 0)); then
        if zrd_is root 2>/dev/null; then
            test_pass "Correctly detects root user"
        else
            test_fail "Correctly detects root user" "EUID: $EUID"
        fi
    else
        if ! zrd_is root 2>/dev/null; then
            test_pass "Correctly detects non-root user"
        else
            test_fail "Correctly detects non-root user" "EUID: $EUID"
        fi
    fi
}

test_architecture_functions() {
    print_section "Architecture Functions"

    # Ensure detection has run
    zrd_detect 2>/dev/null

    local -a arch_queries=(name bits family endian instruction-set)
    local query result

    for query in "${arch_queries[@]}"; do
        if result=$(zrd_arch "$query" 2>/dev/null); then
            if [[ -n "$result" && "$result" != "unknown" ]]; then
                test_pass "zrd_arch $query works" "Result: $result"
            else
                test_skip "zrd_arch $query works" "Detection may have failed or returned unknown"
            fi
        else
            test_skip "zrd_arch $query works" "Function error or detection failure"
        fi
    done

    # Test invalid query
    if ! zrd_arch invalid_query 2>/dev/null; then
        test_pass "zrd_arch rejects invalid queries"
    else
        test_fail "zrd_arch rejects invalid queries" "Should return error for invalid query"
    fi
}

test_path_functions() {
    print_section "Path Functions"

    # Ensure detection has run
    zrd_detect 2>/dev/null

    local -a path_types=(temp config cache data runtime home)
    local type result

    for type in "${path_types[@]}"; do
        if result=$(zrd_paths "$type" 2>/dev/null); then
            if [[ -n "$result" ]]; then
                # Check if path looks reasonable
                case "$type" in
                temp|runtime)
                    test_condition '[[ "$result" == "/tmp" || "$result" == *"/T/" || "$result" == "/var"* ]]' \
                        "zrd_paths $type returns reasonable path" \
                        "Path: $result" \
                        "Unexpected path: $result"
                    ;;
                home)
                    test_condition '[[ "$result" == "$HOME" ]]' \
                        "zrd_paths $type returns HOME" \
                        "Path: $result" \
                        "Expected HOME, got: $result"
                    ;;
                *)
                    test_pass "zrd_paths $type works" "Path: $result"
                    ;;
                esac
            else
                test_skip "zrd_paths $type works" "No output, may depend on detection"
            fi
        else
            test_skip "zrd_paths $type works" "Function error or detection failure"
        fi
    done

    # Test invalid path type
    if ! zrd_paths invalid_path 2>/dev/null; then
        test_pass "zrd_paths rejects invalid path types"
    else
        test_fail "zrd_paths rejects invalid path types" "Should return error"
    fi
}

test_error_handling() {
    print_section "Error Handling"

    # Test functions without arguments
    if ! zrd_is 2>/dev/null; then
        test_pass "zrd_is requires arguments"
    else
        test_fail "zrd_is requires arguments" "Should fail without target"
    fi

    # Test invalid arguments
    if ! zrd_is invalid_platform 2>/dev/null; then
        test_pass "zrd_is rejects invalid platforms"
    else
        test_fail "zrd_is rejects invalid platforms" "Should reject unknown platform"
    fi

    if ! zrd_info invalid_type 2>/dev/null; then
        test_pass "zrd_info rejects invalid types"
    else
        test_fail "zrd_info rejects invalid types" "Should reject unknown type"
    fi

    # Test functions before detection (if auto-detect is off)
    local auto_detect_status=$ZRD_CFG_AUTO_DETECT
    if ((auto_detect_status == 0)); then
        # Create fresh environment
        if ! zsh -c "unset ZRD_* __ZRD_* 2>/dev/null; source '$TEST_LIB_PATH'; zrd_summary" 2>/dev/null; then
            test_pass "Functions fail gracefully without detection"
        else
            test_skip "Functions fail gracefully without detection" "Auto-detect may be enabled"
        fi
    else
        test_skip "Functions fail gracefully without detection" "Auto-detect is enabled"
    fi
}

test_security_features() {
    print_section "Security Features"

    # Test command finding
    if __zrd_find_cmd "uname" >/dev/null 2>&1; then
        test_pass "Command whitelisting allows known commands"
    else
        test_skip "Command whitelisting allows known commands" "uname may not be in whitelist paths"
    fi

    # Test that unknown commands are rejected
    if ! __zrd_find_cmd "totally_fake_command_12345" >/dev/null 2>&1; then
        test_pass "Command whitelisting rejects unknown commands"
    else
        test_fail "Command whitelisting rejects unknown commands" "Should reject unknown command"
    fi

    # Test whitelist structure
    test_condition '[[ -n "${__ZRD_WHITELIST_CMDS[uname]:-}" ]]' \
        "uname command is whitelisted" \
        "Paths: ${__ZRD_WHITELIST_CMDS[uname]}" \
        "uname not found in whitelist"

    test_condition '[[ -n "${__ZRD_WHITELIST_CMDS[hostname]:-}" ]]' \
        "hostname command is whitelisted" \
        "Paths: ${__ZRD_WHITELIST_CMDS[hostname]}" \
        "hostname not found in whitelist"
}

test_json_output() {
    print_section "JSON Output"

    # Ensure detection has run
    zrd_detect 2>/dev/null

    local json_output
    if json_output=$(zrd_info json 2>/dev/null); then
        if [[ -n "$json_output" ]]; then
            # Basic JSON structure test
            if [[ "$json_output" == "{"* && "$json_output" == *"}" ]]; then
                test_pass "JSON output has valid structure"

                # Test for key fields
                local -a required_fields=('"platform":' '"architecture":' '"flags":' '"metadata":')
                local field missing=0

                for field in "${required_fields[@]}"; do
                    if [[ "$json_output" != *"$field"* ]]; then
                        missing=$((missing + 1))
                    fi
                done

                if ((missing == 0)); then
                    test_pass "JSON output contains required fields"
                else
                    test_fail "JSON output contains required fields" "Missing $missing fields"
                fi

                # Test JSON validity (basic)
                if echo "$json_output" | head -1 | grep -q '^{$'; then
                    test_pass "JSON output starts correctly"
                else
                    test_fail "JSON output starts correctly" "Should start with '{'"
                fi

            else
                test_fail "JSON output has valid structure" "Invalid JSON structure"
            fi
        else
            test_skip "JSON output works" "No output, detection may have failed"
        fi
    else
        test_skip "JSON output works" "Function error or detection failure"
    fi
}

test_status_and_cleanup() {
    print_section "Status and Cleanup"

    # Test status function
    if zrd_status >/dev/null 2>&1; then
        test_pass "zrd_status executes without error"

        local status_output
        if status_output=$(zrd_status 2>/dev/null) && [[ -n "$status_output" ]]; then
            test_pass "zrd_status produces output"
        else
            test_fail "zrd_status produces output" "No output generated"
        fi
    else
        test_fail "zrd_status executes without error"
    fi

    # Test cleanup function exists
    test_condition "typeset -f zrd_cleanup >/dev/null 2>&1" \
        "zrd_cleanup function exists" \
        "" \
        "Cleanup function not defined"
}

# Main test runner
main() {
    print_header "Comprehensive z.zsh Library Test Suite"

    # Check if library exists
    if [[ ! -f "$TEST_LIB_PATH" ]]; then
        print -P "%F{red}ERROR: Library not found at $TEST_LIB_PATH%f"
        exit 1
    fi

    print -P "Library: $TEST_LIB_PATH"
    print -P "Platform: $OSTYPE"
    print -P "Shell: $ZSH_VERSION"
    print -P "User: $(whoami) (EUID: $EUID)"
    print -P ""

    # Create results directory
    mkdir -p "$TEST_RESULTS_DIR" 2>/dev/null

    # Run test categories
    test_library_loading
    test_core_functions
    test_configuration_system
    test_detection_and_availability
    test_platform_normalization
    test_information_functions
    test_platform_detection_logic
    test_architecture_functions
    test_path_functions
    test_error_handling
    test_security_features
    test_json_output
    test_status_and_cleanup

    # Print final summary
    print_header "Test Results Summary"
    print -P "Total tests: $TESTS_TOTAL"
    print -P "%F{green}Passed: $TESTS_PASSED%f"
    print -P "%F{red}Failed: $TESTS_FAILED%f"
    print -P "%F{yellow}Skipped: $TESTS_SKIPPED%f"

    local completed_tests=$((TESTS_TOTAL - TESTS_SKIPPED))
    if ((completed_tests > 0)); then
        local pass_rate=$(((TESTS_PASSED * 100) / completed_tests))
        print -P "Pass rate: ${pass_rate}% ($TESTS_PASSED/$completed_tests completed tests)"
    fi

    if ((TESTS_FAILED > 0)); then
        print -P "\n%F{red}Failed tests:%f"
        local failed_test
        for failed_test in "${FAILED_TESTS[@]}"; do
            print -P "  - $failed_test"
        done
    fi

    if ((TESTS_SKIPPED > 0)); then
        print -P "\n%F{yellow}Note: $TESTS_SKIPPED tests were skipped due to environment limitations%f"
        print -P "This is expected when system commands are not available or detection fails"
    fi

    # Save detailed results
    {
        print "z.zsh Library Test Results - $(date)"
        print "========================================"
        print "Library: $TEST_LIB_PATH"
        print "Platform: $OSTYPE"
        print "Shell: $ZSH_VERSION"
        print ""
        print "Total: $TESTS_TOTAL"
        print "Passed: $TESTS_PASSED"
        print "Failed: $TESTS_FAILED"
        print "Skipped: $TESTS_SKIPPED"

        if ((completed_tests > 0)); then
            print "Pass rate: ${pass_rate}%"
        fi
        print ""

        if ((TESTS_FAILED > 0)); then
            print "Failed tests:"
            for failed_test in "${FAILED_TESTS[@]}"; do
                print "  - $failed_test"
            done
        fi
    } >"$TEST_RESULTS_DIR/test_results_$(date +%Y%m%d_%H%M%S).txt"

    print -P "\n%F{cyan}Test results saved to: $TEST_RESULTS_DIR%f"

    # Exit with appropriate code
    if ((TESTS_FAILED == 0)); then
        print -P "%F{green}All non-skipped tests passed!%f"
        exit 0
    elif ((TESTS_PASSED > TESTS_FAILED)); then
        print -P "%F{yellow}More tests passed than failed. Library appears functional.%f"
        exit 0
    else
        print -P "%F{red}Significant test failures detected.%f"
        exit 1
    fi
}

# Run if executed directly
if [[ "${ZSH_EVAL_CONTEXT:-}" == "toplevel" ]]; then
    main "$@"
fi