# zsh-runtime-detect

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Zsh Version](https://img.shields.io/badge/zsh-5.0%2B-blue.svg)](https://www.zsh.org/)
[![Platform Support](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20BSD%20%7C%20WSL-lightgrey.svg)](#platform-support)
[![Architecture](https://img.shields.io/badge/arch-x86__64%20%7C%20ARM64%20%7C%20ARM-green.svg)](#architecture-support)

> **Intelligent runtime environment detection for Zsh scripts and applications**

A security-first Zsh library that provides platform, architecture, and environment detection capabilities. Built for modern DevOps workflows, CI/CD pipelines, and cross-platform automation.

## ✨ Features

### 🎯 **Comprehensive Detection**

- **Platform Detection**: macOS, Linux, BSD, Windows (WSL), Android (Termux)
- **Architecture Support**: x86_64, ARM64, ARM32, with detailed instruction set detection
- **Environment Recognition**: Containers, VMs, WSL, SSH sessions, CI/CD systems
- **Distribution Identification**: Ubuntu, Debian, CentOS, RHEL, Fedora, Arch, Alpine, and more

### 🚀 **Developer Experience**

- **Zero Dependencies**: Pure Zsh implementation, no external requirements
- **Intelligent Caching**: TTL-based caching with signature validation for optimal performance
- **Lazy Loading**: Detection runs only when needed, minimizing startup overhead
- **Rich API**: Simple boolean checks, detailed information queries, and JSON output

### 🔒 **Security First**

- **Command Whitelisting**: Only safe, verified commands are executed
- **Input Sanitization**: All inputs are validated and sanitized
- **Timeout Protection**: Prevents hanging on slow or unresponsive systems
- **File Validation**: Secure file reading with permission and type checks

### ⚡ **Performance Optimized**

- **Sub-millisecond Detection**: Cached results for lightning-fast subsequent calls
- **Minimal System Impact**: Efficient detection algorithms with fallback mechanisms
- **CI/CD Optimized**: Special optimizations for automated environments

## 🚀 Quick Start

### One-Line Installation

```bash
# Download and source in your script
curl -fsSL https://github.com/Khodaparastan/zsh-runtime-detect/blob/main/zrd.zsh -o zrd.zsh
source zrd.zsh
```

### Basic Usage

```zsh
#!/usr/bin/env zsh
source zrd.zsh

# Automatic detection on first use
if zrd_is macos; then
    echo "Running on macOS"
    brew install package
elif zrd_is linux; then
    echo "Running on Linux"
    apt install package
fi

# Get detailed information
echo "Platform: $(zrd_summary)"           # "macos/aarch64"
echo "Environment: $(zrd_info extended)"  # "macOS 14.0 on Apple Silicon (native)"
```

## 📚 API Reference

### Boolean Checks

```zsh
# Platform detection
zrd_is macos        # macOS/Darwin
zrd_is linux        # Linux distributions
zrd_is bsd          # FreeBSD, OpenBSD, NetBSD
zrd_is windows      # Windows (via WSL detection)

# Architecture detection
zrd_is x86_64       # 64-bit x86
zrd_is aarch64      # 64-bit ARM (Apple Silicon, etc.)
zrd_is arm          # 32-bit ARM

# Environment detection
zrd_is container    # Docker, Podman, LXC
zrd_is vm           # Virtual machine
zrd_is wsl          # Windows Subsystem for Linux
zrd_is ssh          # SSH session
zrd_is ci           # CI/CD environment
zrd_is root         # Running as root/administrator
```

### Information Queries

```zsh
# Summary information
zrd_summary                    # "linux/x86_64"
zrd_info extended             # "Ubuntu 22.04 on x86_64 (container)"

# Architecture details
zrd_arch name                 # "x86_64"
zrd_arch bits                 # "64"
zrd_arch family               # "x86"

# Platform paths
zrd_paths temp                # Platform-appropriate temp directory
zrd_paths config              # User config directory
zrd_paths cache               # Cache directory

# JSON output for APIs
zrd_info json                 # Complete JSON representation
```

## 🌟 Advanced Examples

### Multi-Platform Installer

```zsh
#!/usr/bin/env zsh
source zrd.zsh

install_package() {
    local package=$1

    if zrd_is macos; then
        if [[ $(zrd_arch name) == "aarch64" ]]; then
            # Apple Silicon optimization
            arch -arm64 brew install "$package"
        else
            brew install "$package"
        fi
    elif zrd_is linux; then
        case $ZRD_DISTRO in
            ubuntu|debian) sudo apt install -y "$package" ;;
            centos|rhel|fedora) sudo yum install -y "$package" ;;
            arch) sudo pacman -S --noconfirm "$package" ;;
        esac
    elif zrd_is bsd; then
        sudo pkg install -y "$package"
    fi
}
```

### Container-Aware Configuration

```zsh
#!/usr/bin/env zsh
source zrd.zsh

configure_app() {
    if zrd_is container; then
        echo "Configuring for container environment"

        if zrd_is ci; then
            # CI/CD optimizations
            export LOG_LEVEL=WARN
            export CACHE_ENABLED=false
        else
            # Development container
            export LOG_LEVEL=DEBUG
            export HOT_RELOAD=true
        fi

        # Resource-aware configuration
        if [[ $(zrd_arch family) == "arm" ]]; then
            export WORKER_PROCESSES=2  # ARM containers often have fewer cores
        fi
    else
        # Native environment
        export LOG_LEVEL=INFO
        export CACHE_ENABLED=true
    fi
}
```

### Adaptive Shell Configuration

```zsh
# In your .zshrc
source ~/.local/lib/zrd.zsh

# Platform-specific aliases
if zrd_is macos; then
    alias ls='ls -G'
    alias code='/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
elif zrd_is linux; then
    alias ls='ls --color=auto'
    alias open='xdg-open'
fi

# Environment-aware prompt
if zrd_is container; then
    PROMPT="📦 %n@%m:%~ $ "
elif zrd_is ssh; then
    PROMPT="🌐 %n@%m:%~ $ "
else
    PROMPT="%n@%m:%~ $ "
fi
```

## 🏗️ Architecture

zsh-runtime-detect follows a layered architecture designed for reliability, performance, and security:

```diagram
┌─────────────────────────────────────┐
│           Public API Layer          │  ← zrd_is, zrd_info, zrd_arch
├─────────────────────────────────────┤
│       Orchestration Layer           │  ← zrd_detect, caching, validation
├─────────────────────────────────────┤
│      Detection Engine Layer         │  ← Platform/arch/environment detection
├─────────────────────────────────────┤
│       Security Framework            │  ← Command whitelisting, timeouts
├─────────────────────────────────────┤
│       System Interface Layer        │  ← Safe system calls, file operations
└─────────────────────────────────────┘
```

### Key Design Principles

- **Security First**: All system interactions are filtered through security controls
- **Performance Optimized**: Intelligent caching and lazy loading minimize overhead
- **Reliability**: Comprehensive fallback mechanisms ensure robust operation
- **Maintainability**: Modular design with clear separation of concerns

## 📦 Platform Support

| Platform    | Status | Versions    | Architectures        |
|-------------|--------|-------------|----------------------|
| **macOS**   | ✅ Full | 10.15+      | x86_64, ARM64        |
| **Linux**   | ✅ Full | Kernel 3.0+ | x86_64, ARM64, ARM32 |
| **FreeBSD** | ✅ Full | 12.0+       | x86_64, ARM64        |
| **OpenBSD** | ✅ Full | 6.8+        | x86_64               |
| **NetBSD**  | ✅ Full | 9.0+        | x86_64               |
| **WSL**     | ✅ Full | WSL 1 & 2   | x86_64               |
| **Android** | ✅ Full | Termux      | ARM64, ARM32         |

### Distribution Support

| Distribution       | Detection | Package Manager | Service Manager |
|--------------------|-----------|-----------------|-----------------|
| Ubuntu/Debian      | ✅         | apt             | systemd         |
| CentOS/RHEL/Fedora | ✅         | yum/dnf         | systemd         |
| Arch Linux         | ✅         | pacman          | systemd         |
| Alpine Linux       | ✅         | apk             | OpenRC          |
| SUSE/openSUSE      | ✅         | zypper          | systemd         |

## 🔧 Environment Detection

### Container Support

- **Docker**: Full detection including container ID and image info
- **Podman**: Complete rootless container support
- **LXC/LXD**: System and application containers
- **Kubernetes**: Pod detection with namespace and service info
- **CI/CD**: GitHub Actions, GitLab CI, Jenkins, CircleCI, and more

### Virtualization Support

- **VMware**: ESXi, Workstation, Fusion
- **VirtualBox**: All versions
- **QEMU/KVM**: Including cloud instances
- **Hyper-V**: Windows and Azure VMs
- **Xen**: Citrix and open-source implementations

## 🚀 Installation

### Method 1: Direct Download

```bash
# Download to your project
curl -fsSL https://get.mkh.sh/zrd -o zrd.zsh

# Or install system-wide
sudo curl -fsSL https://get.mkh.sh/zrd -o /usr/local/lib/zrd.zsh
```

### Method 2: Git Clone

```bash
git clone https://github.com/khodaparastan/zsh-runtime-detect.git
cd zsh-runtime-detect
sudo cp zrd.zsh /usr/local/lib/
```

## ⚙️ Configuration

Configure zrd behavior using environment variables:

```bash
# Enable automatic detection (default: 1)
export ZRD_CFG_AUTO_DETECT=1

# Set cache TTL in seconds (default: 300)
export ZRD_CFG_CACHE_TTL=600

# Enable debug output (0=off, 1=info, 2=verbose, 3=trace)
export ZRD_CFG_DEBUG=1

# Custom timeout for commands (default: 5 seconds)
export ZRD_CFG_TIMEOUT=10
```

## 🧪 Testing

Run the comprehensive test suite:

```bash
# Basic functionality test
zsh tests/test_zrd_simple.zsh

# Full test suite
zsh tests/test_zrd_final.zsh

# Performance benchmark
zsh tests/benchmark_zrd.zsh
```

## 📊 Performance

Typical performance characteristics:

| Operation       | Cold Start | Cached |
|-----------------|------------|--------|
| First detection | 50-200ms   | -      |
| Boolean checks  | -          | <1ms   |
| Info queries    | -          | <1ms   |
| JSON output     | -          | 2-5ms  |

Memory usage: ~100KB for full detection data

### Development Setup

```bash
git clone https://github.com/khodaparastan/zsh-runtime-detect.git
cd zsh-runtime-detect

# Run tests
zsh tests/test_zrd_final.zsh

# Test in different environments
docker run -v "$PWD:/app" ubuntu:22.04 zsh /app/tests/test_zrd_simple.zsh
```

### Coding Standards

- **Security**: All system interactions must go through security framework
- **Performance**: Maintain sub-millisecond cached operation performance
- **Compatibility**: Support Zsh 5.0+ across all target platforms
- **Documentation**: Comprehensive inline documentation required

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Zsh Community**: For creating an amazing shell

---

<div align="center">

Made with ❤️ for the Zsh community

</div>
