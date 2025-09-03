# zrd.zsh Quick Reference

> **Fast lookup for zsh-runtime-detect functions and usage patterns**

## 🚀 Quick Start

```bash
# Download and use
curl -fsSL https://raw.githubusercontent.com/khodaparastan/zsh-runtime-detect/main/zrd.zsh -o zrd.zsh
source zrd.zsh

# Basic usage
if zrd_is macos; then
    echo "Running on macOS: $(zrd_summary)"
fi
```

## 📋 Function Reference

### Core Functions

| Function        | Purpose                      | Example                         |
|-----------------|------------------------------|---------------------------------|
| `zrd_detect`    | Run platform detection       | `zrd_detect`                    |
| `zrd_available` | Check if detection completed | `zrd_available && echo "Ready"` |
| `zrd_refresh`   | Clear cache and re-detect    | `zrd_refresh`                   |
| `zrd_cleanup`   | Remove all zrd variables     | `zrd_cleanup`                   |
| `zrd_status`    | Show detection status        | `zrd_status`                    |

### Information Functions

| Function            | Purpose                  | Example Output                                       |
|---------------------|--------------------------|------------------------------------------------------|
| `zrd_summary`       | Platform/architecture    | `darwin/aarch64`                                     |
| `zrd_info summary`  | Same as zrd_summary      | `linux/x86_64`                                       |
| `zrd_info extended` | Detailed information     | `macOS 14.0 on Apple Silicon (native)`               |
| `zrd_info json`     | JSON format              | `{"platform":"darwin","architecture":"aarch64",...}` |
| `zrd_info hostname` | System hostname          | `my-macbook.local`                                   |
| `zrd_info username` | Current username         | `john`                                               |
| `zrd_info flags`    | Active environment flags | `native,interactive`                                 |
| `zrd_info version`  | Library version          | `2.2.3`                                              |

### Platform Detection

| Function         | Detects             | Example                                     |
|------------------|---------------------|---------------------------------------------|
| `zrd_is macos`   | macOS/Darwin        | `zrd_is macos && brew install package`      |
| `zrd_is linux`   | Linux distributions | `zrd_is linux && apt install package`       |
| `zrd_is bsd`     | BSD variants        | `zrd_is bsd && pkg install package`         |
| `zrd_is unix`    | Unix-like systems   | `zrd_is unix && echo "POSIX compatible"`    |
| `zrd_is windows` | Windows (via WSL)   | `zrd_is windows && echo "Windows detected"` |

### Architecture Detection

| Function         | Detects          | Example                               |
|------------------|------------------|---------------------------------------|
| `zrd_is x86_64`  | 64-bit Intel/AMD | `zrd_is x86_64 && echo "x86_64 arch"` |
| `zrd_is aarch64` | 64-bit ARM       | `zrd_is aarch64 && echo "ARM64 arch"` |
| `zrd_is arm`     | 32-bit ARM       | `zrd_is arm && echo "ARM32 arch"`     |

### Environment Detection

| Function             | Detects                     | Example                                     |
|----------------------|-----------------------------|---------------------------------------------|
| `zrd_is container`   | Docker/Podman/LXC           | `zrd_is container && echo "In container"`   |
| `zrd_is vm`          | Virtual machine             | `zrd_is vm && echo "In VM"`                 |
| `zrd_is wsl`         | Windows Subsystem for Linux | `zrd_is wsl && echo "In WSL"`               |
| `zrd_is ssh`         | SSH session                 | `zrd_is ssh && echo "Remote session"`       |
| `zrd_is ci`          | CI/CD environment           | `zrd_is ci && echo "In CI"`                 |
| `zrd_is root`        | Running as root             | `zrd_is root && echo "Admin privileges"`    |
| `zrd_is interactive` | Interactive shell           | `zrd_is interactive && echo "User session"` |
| `zrd_is termux`      | Termux (Android)            | `zrd_is termux && echo "Android terminal"`  |

### Architecture Queries

| Function                   | Returns             | Example Output             |
|----------------------------|---------------------|----------------------------|
| `zrd_arch name`            | Architecture name   | `aarch64`, `x86_64`, `arm` |
| `zrd_arch bits`            | Architecture bits   | `64`, `32`                 |
| `zrd_arch family`          | Architecture family | `arm`, `x86`               |
| `zrd_arch endian`          | Byte order          | `little`, `big`            |
| `zrd_arch instruction-set` | Instruction set     | `ARMv8-A`, `x86_64`        |

### Path Functions

| Function            | Returns                 | Example Path                                      |
|---------------------|-------------------------|---------------------------------------------------|
| `zrd_paths temp`    | Temporary directory     | `/tmp`, `/var/folders/...`                        |
| `zrd_paths config`  | Configuration directory | `~/.config`, `~/Library/Preferences`              |
| `zrd_paths cache`   | Cache directory         | `~/.cache`, `~/Library/Caches`                    |
| `zrd_paths data`    | Data directory          | `~/.local/share`, `~/Library/Application Support` |
| `zrd_paths runtime` | Runtime directory       | `/run/user/1000`, `/tmp`                          |
| `zrd_paths home`    | Home directory          | `$HOME`                                           |

## 🔧 Configuration

Set these environment variables before sourcing:

| Variable              | Default | Purpose              |
|-----------------------|---------|----------------------|
| `ZRD_CFG_AUTO_DETECT` | `0`     | Auto-detect on load  |
| `ZRD_CFG_DEBUG`       | `0`     | Debug level (0-3)    |
| `ZRD_CFG_CACHE_TTL`   | `300`   | Cache TTL in seconds |
| `ZRD_CFG_CMD_TIMEOUT` | `10`    | Command timeout      |

```bash
export ZRD_CFG_AUTO_DETECT=1
export ZRD_CFG_DEBUG=1
source zrd.zsh
```

## 💡 Common Patterns

### Multi-Platform Package Installation

```bash
install_package() {
    local pkg=$1
    if zrd_is macos; then
        brew install "$pkg"
    elif zrd_is linux; then
        case $ZRD_DISTRO in
            ubuntu|debian) sudo apt install -y "$pkg" ;;
            centos|rhel|fedora) sudo yum install -y "$pkg" ;;
            arch) sudo pacman -S --noconfirm "$pkg" ;;
        esac
    elif zrd_is bsd; then
        sudo pkg install -y "$pkg"
    fi
}
```

### Environment-Aware Configuration

```bash
configure_app() {
    if zrd_is container; then
        export LOG_LEVEL=WARN
        export CACHE_ENABLED=false
    elif zrd_is ci; then
        export LOG_LEVEL=ERROR
        export PARALLEL_JOBS=2
    else
        export LOG_LEVEL=INFO
        export PARALLEL_JOBS=$(nproc 2>/dev/null || echo 4)
    fi
}
```

### Adaptive Aliases

```bash
if zrd_is macos; then
    alias ls='ls -G'
    alias open='open'
elif zrd_is linux; then
    alias ls='ls --color=auto'
    alias open='xdg-open'
elif zrd_is wsl; then
    alias open='explorer.exe'
    alias pbcopy='clip.exe'
fi
```

### Architecture-Specific Builds

```bash
build_app() {
    local flags=""
    if [[ $(zrd_arch family) == "arm" ]]; then
        flags="-march=armv8-a"
        if zrd_is macos; then
            flags="$flags -arch arm64"
        fi
    elif [[ $(zrd_arch family) == "x86" ]]; then
        flags="-march=native"
        if zrd_is macos; then
            flags="$flags -arch x86_64"
        fi
    fi

    make CFLAGS="$flags" -j$(zrd_is container && echo 2 || nproc)
}
```

### Container Detection

```bash
setup_container_env() {
    if zrd_is container; then
        echo "Container environment detected"

        # Container-specific optimizations
        export NODE_OPTIONS="--max-old-space-size=512"
        export MAKEFLAGS="-j2"

        if zrd_is ci; then
            echo "CI container detected"
            export CI_OPTIMIZED=true
        fi
    fi
}
```

### JSON Integration

```bash
create_system_report() {
    local report=$(zrd_info json)

    # Extract specific fields
    local platform=$(echo "$report" | jq -r '.platform')
    local arch=$(echo "$report" | jq -r '.architecture')

    # Create custom report
    jq -n \
        --arg platform "$platform" \
        --arg arch "$arch" \
        --argjson system "$report" \
        '{
            app: "my-app",
            version: "1.0.0",
            system: $system,
            deployment: {
                platform: $platform,
                architecture: $arch,
                optimized_for: ($arch == "aarch64" and $platform == "darwin")
            }
        }'
}
```

## 🎯 Platform-Specific Examples

### macOS

```bash
if zrd_is macos; then
    # Architecture-specific handling
    if [[ $(zrd_arch name) == "aarch64" ]]; then
        export HOMEBREW_PREFIX="/opt/homebrew"
        export ARCHFLAGS="-arch arm64"
    else
        export HOMEBREW_PREFIX="/usr/local"
        export ARCHFLAGS="-arch x86_64"
    fi

    # macOS-specific commands
    alias flush-dns='sudo dscacheutil -flushcache'
    alias show-hidden='defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder'
fi
```

### Linux

```bash
if zrd_is linux; then
    # Distribution-specific package managers
    case $ZRD_DISTRO in
        ubuntu|debian)
            alias install='sudo apt install'
            alias search='apt search'
            ;;
        arch)
            alias install='sudo pacman -S'
            alias search='pacman -Ss'
            ;;
        fedora)
            alias install='sudo dnf install'
            alias search='dnf search'
            ;;
    esac
fi
```

### Containers

```bash
if zrd_is container; then
    # Container optimizations
    export DEBIAN_FRONTEND=noninteractive
    export PYTHONUNBUFFERED=1

    # Minimal package installations
    alias apt-get='apt-get --no-install-recommends'

    # Container health checks
    health_check() {
        curl -f http://localhost:8080/health || exit 1
    }
fi
```

## ⚡ Performance Tips

- **Use caching**: Detection results are cached for 5 minutes by default
- **Check availability**: Use `zrd_available` before multiple queries
- **Batch operations**: Multiple `zrd_is` calls use the same cached data
- **Container optimization**: Set `ZRD_CFG_CACHE_TTL=60` in containers

## 🐛 Debugging

```bash
# Enable debug output
export ZRD_CFG_DEBUG=2
source zrd.zsh

# Check detection status
zrd_status

# View JSON output for debugging
zrd_info json | jq .

# Test specific detection
zrd_is macos && echo "macOS detected" || echo "Not macOS"
```

## 📚 See Also

- [Full Documentation](README.md)
- [Examples](examples/README.md)
- [Architecture Guide](ARCHITECTURE.md)
- [Contributing](CONTRIBUTING.md)
