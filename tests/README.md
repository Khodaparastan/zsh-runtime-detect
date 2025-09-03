# zrd.zsh Testing Suite

This directory contains a comprehensive testing suite for the zsh-runtime-detect library (`zrd.zsh`).

## Test Files

### Core Tests

- **`test_zrd_simple.zsh`** - Basic functionality tests that verify core library features
- **`test_zrd_final.zsh`** - Comprehensive test suite with detailed validation
- **`test_z.zsh`** - Extended test suite with pattern matching support
- **`benchmark_zrd.zsh`** - Performance benchmarking and analysis

### Test Coverage

The test suite covers:

✅ **Library Loading & Initialization**

- Module version and API constants
- Function availability
- Configuration validation
- Error handling

✅ **Core Detection Functions**

- `zrd_detect()` - Primary detection function
- `zrd_available()` - Availability checking
- `zrd_refresh()` - Cache invalidation

✅ **Information Functions**

- `zrd_info()` - Information queries (summary, json, extended, etc.)
- `zrd_summary()` - Quick platform/arch summary
- `zrd_arch()` - Architecture details
- `zrd_paths()` - Platform-appropriate paths

✅ **Boolean Detection Functions**

- `zrd_is()` - Platform/environment detection (macos, linux, container, etc.)

✅ **Platform & Architecture Normalization**

- Platform name normalization (darwin, linux, freebsd, etc.)
- Architecture normalization (arm64→aarch64, amd64→x86_64, etc.)

✅ **Security Features**

- Command whitelisting
- File validation
- Input sanitization

✅ **Caching System**

- TTL-based caching
- Cache signature validation
- Performance optimization

✅ **Configuration System**

- Variable bounds checking
- Default value enforcement
- Environment variable processing

## Running Tests

### Quick Test

```bash
# Run basic functionality test
zsh test_zrd_simple.zsh
```

### Comprehensive Test

```bash
# Run full test suite
zsh test_zrd_final.zsh
```

### Pattern-Based Testing

```bash
# Run specific test categories
zsh test_z.zsh "test_platform*"
zsh test_z.zsh "test_arch*"
```

### Performance Benchmarking

```bash
# Quick benchmark (10 iterations)
zsh benchmark_zrd.zsh quick

# Full benchmark (100 iterations)
zsh benchmark_zrd.zsh

# Custom iteration count
zsh benchmark_zrd.zsh 50
```

## Test Results

The tests are designed to work across different platforms and environments:

### Expected Results

- **macOS (Apple Silicon)**: All tests should pass
- **macOS (Intel)**: All tests should pass
- **Linux**: All tests should pass
- **BSD**: Most tests should pass (some may be skipped)
- **Containers**: Tests should pass with container-specific adjustments
- **CI/CD**: Tests should pass with CI optimizations

### Performance Benchmarks

Typical performance characteristics:

| Operation | Expected Performance |
|-----------|---------------------|
| Library Loading | 10-20ms |
| First Detection | 10-50ms |
| Cached Detection | <1ms |
| Info Queries | <1ms |
| Boolean Checks | <1ms |

## Test Structure

### Test Categories

1. **Library Loading** - Verifies the library loads correctly and initializes properly
2. **Function Availability** - Confirms all expected functions are defined
3. **Basic Detection** - Tests core detection functionality
4. **Configuration System** - Validates configuration handling
5. **Platform Detection Logic** - Tests platform-specific detection
6. **Architecture Functions** - Validates architecture detection and queries
7. **Path Functions** - Tests platform-appropriate path resolution
8. **Error Handling** - Ensures graceful error handling
9. **Security Features** - Validates security controls
10. **JSON Output** - Tests structured output functionality
11. **Cache System** - Validates caching behavior
12. **Status & Cleanup** - Tests utility functions

### Test Utilities

The test suite includes several utility functions:

- `test_pass()` / `test_fail()` - Test result recording
- `test_condition()` - Conditional test execution
- `assert_equals()` / `assert_not_empty()` - Assertion functions
- `run_in_clean_env()` - Clean environment test execution
- `skip_test()` - Test skipping for unsupported scenarios

## Test Results Storage

Test results are saved to:

- `test_results/` - Individual test run results
- `benchmark_results/` - Performance benchmark data

## Troubleshooting

### Common Issues

**Test fails with "Library not found"**

- Ensure `zrd.zsh` is present in the parent directory
- Check file permissions

**Configuration validation tests fail**

- This may indicate the library's validation logic has changed
- Review the validation bounds in `zrd.zsh`

**Platform detection tests fail**

- Verify the current platform is supported
- Check if detection is working: `source ../zrd.zsh && zrd_detect && zrd_summary`

**Performance tests show inconsistent results**

- Performance can vary based on system load
- Run multiple times to get average performance
- Consider using the benchmark script for more reliable metrics

### Debug Mode

Enable debug output by setting:

```bash
export ZRD_CFG_DEBUG=2
zsh test_zrd_simple.zsh
```

This will provide additional diagnostic information about the library's operation during testing.

## Contributing to Tests

When adding new features to `zrd.zsh`:

1. Add corresponding tests to verify functionality
2. Update existing tests if behavior changes
3. Ensure tests work across supported platforms
4. Add performance benchmarks for new functions
5. Update this README with new test categories

### Test Development Guidelines

- **Comprehensive**: Test both success and failure cases
- **Portable**: Ensure tests work across platforms
- **Performant**: Tests should run quickly
- **Isolated**: Each test should be independent
- **Descriptive**: Use clear test names and error messages
