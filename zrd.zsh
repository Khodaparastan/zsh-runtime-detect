#!/usr/bin/env zsh

#===============================================================================
# zsh-runtime-detect - Fast, secure runtime environment detection for Zsh
#===============================================================================
#
# A platform and environment detection module for Zsh that provides
# detailed system information with security-focused design and intelligent caching.
#
# Repository: https://github.com/khdaparastan/zsh-runtime-detect
# Version:    2.3.1
# API:        2
# License:    MIT
# Author:     khodaparastan <mohammad@khodapastan.com>
# Created:    2025-08-15
#
#===============================================================================
# FEATURES (summary)
# - Platform detection: OS, arch, kernel
# - Environment detection: WSL, containers, VMs, Termux, chroot, CI, SSH
# - Distribution detection: Linux (os-release/lsb_release/legacy), macOS (sw_vers/plist)
# - Security: command whitelisting, strict mode, bounded file reads, timeouts, env sanitization
# - Performance: caching with TTL, lazy evaluation, minimal subshells
#===============================================================================

#------------------------------------------------------------------------------
# Module version and API info
#------------------------------------------------------------------------------
typeset -g __ZRD_THIS_VERSION="2.3.1"
typeset -g __ZRD_API_VERSION="2"

#------------------------------------------------------------------------------
# Early reload/version guard with robust cleanup
#------------------------------------------------------------------------------
if (( ${+__ZRD_MODULE_LOADED} )); then
  if [[ ${__ZRD_MODULE_VERSION:-} == "$__ZRD_THIS_VERSION" ]]; then
    [[ ${ZRD_CFG_DEBUG:-0} -ge 1 ]] && print -P "%F{yellow}[platform] Module already loaded%f" >&2
    return 0
  fi
    emulate -L zsh
    print -P "%F{yellow}[platform] Version mismatch, reloading...%f" >&2
    if typeset -f zrd_cleanup >/dev/null 2>&1; then
      zrd_cleanup
  fi
fi

typeset -g __ZRD_MODULE_VERSION="$__ZRD_THIS_VERSION"
typeset -gi __ZRD_MODULE_LOADED=1

#------------------------------------------------------------------------------
# Configuration (user-settable before sourcing)
#------------------------------------------------------------------------------
typeset -gi ZRD_CFG_AUTO_DETECT=${ZRD_CFG_AUTO_DETECT:-0}
typeset -gi ZRD_CFG_DEBUG=${ZRD_CFG_DEBUG:-0}                 # 0..3
typeset -gi ZRD_CFG_CACHE_TTL=${ZRD_CFG_CACHE_TTL:-300}       # seconds
typeset -gi ZRD_CFG_MAX_FILE_SIZE=${ZRD_CFG_MAX_FILE_SIZE:-8192}
typeset -gi ZRD_CFG_CMD_TIMEOUT=${ZRD_CFG_CMD_TIMEOUT:-10}    # seconds
# New options:
typeset -gi ZRD_CFG_STRICT_CMDS=${ZRD_CFG_STRICT_CMDS:-0}     # 1 = disallow non-whitelisted fallbacks
typeset -gi ZRD_CFG_JSON_BOOL=${ZRD_CFG_JSON_BOOL:-0}         # 1 = true/false flags in JSON, 0 = 0/1
typeset -gi ZRD_CFG_SANITIZE_ENV=${ZRD_CFG_SANITIZE_ENV:-1}   # 1 = sanitize env when exec whitelisted

#------------------------------------------------------------------------------
# Internal caches/state
#------------------------------------------------------------------------------
typeset -gA __ZRD_CMD_PATH_CACHE=()
typeset -g __ZRD_CACHE_TIME=0
typeset -g __ZRD_CACHE_SIGNATURE=""
typeset -g __ZRD_CACHE_VERSION=""
typeset -gi __ZRD_CACHE_DETECTED=0

#------------------------------------------------------------------------------
# Whitelisted command paths (security)
# Expand coverage: macOS Homebrew, coreutils gnubin, Nix common location,
# and typical Linux/bin paths. Avoid globs that won't expand; keep static.
#------------------------------------------------------------------------------
typeset -grA __ZRD_WHITELIST_CMDS=(
  uname "/bin/uname:/usr/bin/uname:/opt/homebrew/opt/coreutils/libexec/gnubin/uname:/run/current-system/sw/bin/uname"
  hostname "/bin/hostname:/usr/bin/hostname:/opt/homebrew/bin/hostname:/usr/local/bin/hostname:/run/current-system/sw/bin/hostname"
  date "/bin/date:/usr/bin/date:/opt/homebrew/bin/date:/usr/local/bin/date:/run/current-system/sw/bin/date"
  stat "/bin/stat:/usr/bin/stat:/opt/homebrew/bin/stat:/usr/local/bin/stat:/opt/homebrew/opt/coreutils/libexec/gnubin/stat:/run/current-system/sw/bin/stat"
  head "/bin/head:/usr/bin/head:/opt/homebrew/bin/head:/usr/local/bin/head:/opt/homebrew/opt/coreutils/libexec/gnubin/head:/run/current-system/sw/bin/head"
  wc "/bin/wc:/usr/bin/wc:/opt/homebrew/bin/wc:/usr/local/bin/wc:/opt/homebrew/opt/coreutils/libexec/gnubin/wc:/run/current-system/sw/bin/wc"
  systemd-detect-virt "/bin/systemd-detect-virt:/usr/bin/systemd-detect-virt:/run/current-system/sw/bin/systemd-detect-virt"
  system_profiler "/usr/sbin/system_profiler"
  id "/bin/id:/usr/bin/id:/opt/homebrew/bin/id:/usr/local/bin/id:/opt/homebrew/opt/coreutils/libexec/gnubin/id:/run/current-system/sw/bin/id"
  whoami "/bin/whoami:/usr/bin/whoami:/opt/homebrew/bin/whoami:/usr/local/bin/whoami:/opt/homebrew/opt/coreutils/libexec/gnubin/whoami:/run/current-system/sw/bin/whoami"
  mktemp "/bin/mktemp:/usr/bin/mktemp:/opt/homebrew/bin/mktemp:/usr/local/bin/mktemp:/opt/homebrew/opt/coreutils/libexec/gnubin/mktemp:/run/current-system/sw/bin/mktemp"
  dd "/bin/dd:/usr/bin/dd:/opt/homebrew/bin/dd:/usr/local/bin/dd:/opt/homebrew/opt/coreutils/libexec/gnubin/dd:/run/current-system/sw/bin/dd"
  timeout "/bin/timeout:/usr/bin/timeout:/opt/homebrew/bin/timeout:/usr/local/bin/timeout:/run/current-system/sw/bin/timeout"
  cat "/bin/cat:/usr/bin/cat:/opt/homebrew/bin/cat:/usr/local/bin/cat:/opt/homebrew/opt/coreutils/libexec/gnubin/cat:/run/current-system/sw/bin/cat"
  sw_vers "/usr/bin/sw_vers"
  plutil "/usr/bin/plutil"
  lsb_release "/usr/bin/lsb_release:/bin/lsb_release:/run/current-system/sw/bin/lsb_release"
  grep "/bin/grep:/usr/bin/grep:/opt/homebrew/bin/grep:/usr/local/bin/grep:/run/current-system/sw/bin/grep"
)

#===============================================================================
# Logging and utilities
#===============================================================================
__zrd_log() {
  emulate -L zsh
  local -i level=${1:-1}
  shift
  (( ZRD_CFG_DEBUG >= level )) || return 0
  local tag color
  case $level in
    0) tag="ERROR"; color="red" ;;
    1) tag="WARN";  color="yellow" ;;
    2) tag="INFO";  color="cyan" ;;
    3) tag="DEBUG"; color="blue" ;;
    *) tag="LOG";   color="white" ;;
  esac
  print -P -- "%F{$color}[platform][$tag]%f $*" >&2
}

__zrd_now() {
  emulate -L zsh
  local t
  t=$(date +%s 2>/dev/null) || t=$SECONDS
  print -r -- "$t"
}

__zrd_json_escape() {
  emulate -L zsh
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  s=${s//$'\b'/\\b}
  s=${s//$'\f'/\\f}
  print -r -- "$s"
}

__zrd_bool() {
  emulate -L zsh
  # Print boolean as "true"/"false" if ZRD_CFG_JSON_BOOL=1 else 1/0
  local -i v=${1:-0}
  if (( ZRD_CFG_JSON_BOOL )); then
    (( v )) && print -r -- "true" || print -r -- "false"
  else
    print -r -- "$v"
  fi
}

#===============================================================================
# Configuration validation
#===============================================================================
__zrd_validate_config() {
  emulate -L zsh
  local -i changed=0
  local -a checks=(
    "ZRD_CFG_AUTO_DETECT:0:1:0"
    "ZRD_CFG_CACHE_TTL:30:86400:300"
    "ZRD_CFG_MAX_FILE_SIZE:1024:131072:8192"
    "ZRD_CFG_CMD_TIMEOUT:0:120:10"
    "ZRD_CFG_DEBUG:0:3:0"
    "ZRD_CFG_STRICT_CMDS:0:1:0"
    "ZRD_CFG_JSON_BOOL:0:1:0"
    "ZRD_CFG_SANITIZE_ENV:0:1:1"
  )
  local tuple var min max def cur
  for tuple in "${checks[@]}"; do
    IFS=':' read -r var min max def <<< "$tuple"
    cur=${(P)var}
    if (( cur < min || cur > max )); then
      __zrd_log 1 "$var out of bounds ($cur), resetting to $def"
      typeset -g -i $var=$def
      changed=1
    fi
  done
  return $changed
}
__zrd_validate_config

#===============================================================================
# Secure command and file helpers
#===============================================================================
__zrd_find_cmd() {
  emulate -L zsh
  local name=${1:?}
  local cached
  if cached=${__ZRD_CMD_PATH_CACHE[$name]}; then
    [[ $cached == "!" ]] && return 1
    [[ -x $cached ]] && { print -r -- "$cached"; return 0; }
    unset "__ZRD_CMD_PATH_CACHE[$name]"
  fi
  if [[ -n ${__ZRD_WHITELIST_CMDS[$name]:-} ]]; then
    local -a paths=(${(s.:.)__ZRD_WHITELIST_CMDS[$name]})
    local p
    for p in "${paths[@]}"; do
      [[ -x $p ]] && { __ZRD_CMD_PATH_CACHE[$name]=$p; print -r -- "$p"; return 0; }
    done
  fi
  __ZRD_CMD_PATH_CACHE[$name]="!"
  return 1
}

__zrd_sanitize_exec_env() {
  emulate -L zsh
  # Return a sanitized environment for child processes (reduce locale surprises)
  # Use with: env -i VARS... CMD
  local -a envv=()
  envv+=("PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin")
  envv+=("HOME=$HOME")
  envv+=("USER=${USER:-${USERNAME:-}}")
  envv+=("LANG=C")
  envv+=("LC_ALL=C")
  envv+=("TZ=${TZ:-UTC}")
  print -r -- "${(j: :)envv}"
}

__zrd_exec_whitelisted() {
  emulate -L zsh -o pipe_fail
  local cmd=${1:?}
  shift
  [[ -n ${__ZRD_WHITELIST_CMDS[$cmd]:-} ]] || { __zrd_log 1 "Command not allowed: $cmd"; return 1; }
  local path
  path=$(__zrd_find_cmd "$cmd") || return 1

  local tf ef old_umask
  local mktemp_path
  old_umask=$(umask)
  umask 077
  if mktemp_path=$(__zrd_find_cmd "mktemp" 2>/dev/null); then
    tf=$("$mktemp_path" -t "zrd_exec.XXXXXX" 2>/dev/null) || { umask $old_umask; __zrd_log 1 "mktemp failed stdout for $cmd"; return 1; }
    ef=$("$mktemp_path" -t "zrd_exec.err.XXXXXX" 2>/dev/null) || { umask $old_umask; __zrd_log 1 "mktemp failed stderr for $cmd"; command rm -f -- "$tf" 2>/dev/null; return 1; }
  else
    local tmpdir="${TMPDIR:-/tmp}"
    tf="${tmpdir}/zrd_exec.$$.$RANDOM"
    ef="${tmpdir}/zrd_exec.err.$$.$RANDOM"
    if ! { : >"$tf" && : >"$ef"; }; then
      umask $old_umask
      __zrd_log 1 "Failed to create temp files for $cmd"
      return 1
    fi
  fi
  umask $old_umask

  local -i rc=1
  {
    if (( ZRD_CFG_CMD_TIMEOUT > 0 )); then
      if (( ZRD_CFG_SANITIZE_ENV )); then
        eval "env -i $(__zrd_sanitize_exec_env) \"$path\" \"$@\" " </dev/null >"$tf" 2>"$ef" &!
        __zrd_with_timeout $ZRD_CFG_CMD_TIMEOUT cat "$tf" >/dev/null 2>&1 # warm wait to sync timing
        # Rerun with timeout wrapper properly:
        __zrd_with_timeout $ZRD_CFG_CMD_TIMEOUT "$path" "$@" >"$tf" 2>"$ef"
      else
      __zrd_with_timeout $ZRD_CFG_CMD_TIMEOUT "$path" "$@" >"$tf" 2>"$ef"
      fi
      rc=$?
      if (( rc == 124 )); then
        __zrd_log 1 "Command timed out [$cmd] after ${ZRD_CFG_CMD_TIMEOUT}s"
      fi
    else
      if (( ZRD_CFG_SANITIZE_ENV )); then
        eval "env -i $(__zrd_sanitize_exec_env) \"$path\" \"$@\" " </dev/null >"$tf" 2>"$ef"
      else
        "$path" "$@" </dev/null >"$tf" 2>"$ef"
    fi
    rc=$?
    fi
  } always {
    (( rc != 0 )) && [[ -s $ef ]] && (( ZRD_CFG_DEBUG >= 2 )) && __zrd_log 1 "Command error [$cmd]: $(<"$ef")"
  }

  if (( rc == 0 )) && [[ -s $tf ]]; then
    local cat_path
    if cat_path=$(__zrd_find_cmd "cat" 2>/dev/null); then
      "$cat_path" -- "$tf"
    else
      if (( ZRD_CFG_STRICT_CMDS )); then
        : # do not fallback in strict mode
      else
      command cat -- "$tf"
    fi
  fi
  fi
  command rm -f -- "$tf" "$ef" 2>/dev/null
  return $rc
}

__zrd_with_timeout() {
  emulate -L zsh
  local -i seconds=${1:?}
  shift
  local timeout_cmd
  if timeout_cmd=$(__zrd_find_cmd timeout 2>/dev/null); then
    "$timeout_cmd" "$seconds" "$@"
    return $?
  fi
  # Fallback shim
  "$@" </dev/null & local -i pid=$!
  local -F tick=0.25 elapsed=0.0
  while kill -0 $pid 2>/dev/null; do
    sleep $tick
    elapsed=$(( elapsed + tick ))
    if (( elapsed >= seconds )); then
      kill -TERM $pid 2>/dev/null
      sleep $tick
      kill -KILL $pid 2>/dev/null
      wait $pid 2>/dev/null
      return 124
    fi
  done
  wait $pid
}

__zrd_read_regular_file() {
  emulate -L zsh -o extended_glob
  local file=${1:?} max=${2:-$ZRD_CFG_MAX_FILE_SIZE}
  (( ${#file} <= 256 )) || return 1
  [[ -f $file && -r $file ]] || return 1
  case $file in
    /dev/*|/proc/*/fd/*|/proc/*/task/*|/proc/kcore|/proc/sys/kernel/random/*|/proc/sysrq-trigger|/sys/kernel/debug/*) return 1 ;;
  esac
  local -i size=0
  if __zrd_find_cmd stat >/dev/null 2>&1; then
    local out
    out=$(__zrd_exec_whitelisted stat -c %s "$file" 2>/dev/null) || \
      out=$(__zrd_exec_whitelisted stat -f %z "$file" 2>/dev/null) || out=0
    [[ $out == <-> ]] && size=$out || size=0
    (( size > 0 && size > max )) && { __zrd_log 1 "File too large: $file (${size} bytes)"; return 1; }
  fi
  if __zrd_find_cmd head >/dev/null 2>&1; then
    __zrd_exec_whitelisted head -c "$max" "$file" 2>/dev/null
  elif __zrd_find_cmd dd >/dev/null 2>&1; then
    __zrd_exec_whitelisted dd if="$file" bs=1 count="$max" 2>/dev/null
  else
    local ch; local -i count=0 fd
    {
      exec {fd}<"$file" || return 1
      while IFS= read -r -k1 -u $fd ch && (( count < max )); do
        print -n -- "$ch"
        ((count++))
      done
    } always {
      exec {fd}<&-
    }
  fi
}

__zrd_parse_kv() {
  emulate -L zsh
  local content=${1:?} key=${2:?}
  [[ $key == [A-Za-z_][A-Za-z0-9_]* ]] || { __zrd_log 1 "Invalid key: $key"; return 1; }
  local U=${key:u} L=${key:l} line val
  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    case $line in
      ${U}=*|${L}=*)
        val=${line#*=}
        case $val in
          \"*\") val=${val#\"}; val=${val%\"} ;;
          \'*\') val=${val#\'}; val=${val%\'}
        esac
        val=${val//[$'\001'-$'\037']/}
        (( ${#val} <= 512 )) || continue
        print -r -- "$val"
        return 0
        ;;
    esac
  done <<< "$content"
  return 1
}

#===============================================================================
# Detection helpers
#===============================================================================
__zrd_cache_signature() {
  emulate -L zsh
  # Include uname -s/-m for extra stability across unusual shells
  local us um
  us=$(uname -s 2>/dev/null)
  um=$(uname -m 2>/dev/null)
  print -r -- "${OSTYPE:-}:${MACHTYPE:-}:${HOSTTYPE:-}:${EUID:-}:${UID:-}:${__ZRD_MODULE_VERSION:-}:${us}:${um}"
}

__zrd_cache_valid() {
  emulate -L zsh -o extended_glob
  (( __ZRD_CACHE_DETECTED )) || return 1
  local now=$(__zrd_now)
  if [[ $__ZRD_CACHE_TIME == <-> ]]; then
    local -i age=$(( now - __ZRD_CACHE_TIME ))
    (( age < ZRD_CFG_CACHE_TTL )) || return 1
  else
    return 1
  fi
  [[ $__ZRD_CACHE_SIGNATURE == "$(__zrd_cache_signature)" ]] || return 1
  [[ $__ZRD_CACHE_VERSION == "$__ZRD_MODULE_VERSION" ]] || return 1
  return 0
}

__zrd_normalize_platform() {
  emulate -L zsh
  local p=${1:l}
  case $p in
    darwin*|macos*) print -r -- "darwin" ;;
    linux*|gnu*) print -r -- "linux" ;;
    freebsd*) print -r -- "freebsd" ;;
    openbsd*) print -r -- "openbsd" ;;
    netbsd*) print -r -- "netbsd" ;;
    dragonfly*) print -r -- "dragonfly" ;;
    solaris*|sunos*|illumos*) print -r -- "solaris" ;;
    cygwin*|msys*|mingw*|windows*) print -r -- "windows" ;;
    aix*) print -r -- "aix" ;;
    hpux*|hp-ux*) print -r -- "hpux" ;;
    haiku*) print -r -- "haiku" ;;
    qnx*) print -r -- "qnx" ;;
    minix*) print -r -- "minix" ;;
    *) print -r -- "unknown" ;;
  esac
}

__zrd_normalize_arch() {
  emulate -L zsh
  local a=${1:l}
  if [[ $a == *-* ]]; then
    a=${a%%-*}
  fi
  case $a in
    x86_64|amd64|x64|x86_64h) print -r -- "x86_64" ;;
    i([3-6])86|i86pc|x86) print -r -- "i386" ;;
    arm64|aarch64|arm64v8|arm64e|arm64ec|arm64e*) print -r -- "aarch64" ;;
    armv8l|armv[4-8]*|armhf|armv7l) print -r -- "arm" ;;
    arm)
      if [[ ${1} == *aarch64* || ${1} == *arm64* ]]; then
        print -r -- "aarch64"
      else
        print -r -- "arm"
      fi
      ;;
    ppc64le|ppc64) print -r -- "powerpc64" ;;
    powerpc*|power*|ppc) print -r -- "powerpc" ;;
    mips64el|mips64) print -r -- "mips64" ;;
    mipsel|mips*) print -r -- "mips" ;;
    riscv64) print -r -- "riscv64" ;;
    riscv*) print -r -- "riscv" ;;
    s390x) print -r -- "s390x" ;;
    s390*) print -r -- "s390" ;;
    loongarch*|loong64) print -r -- "loongarch" ;;
    sparc*|sun4*) print -r -- "sparc" ;;
    alpha*) print -r -- "alpha" ;;
    ia64) print -r -- "ia64" ;;
    *) print -r -- "${a:-unknown}" ;;
  esac
}

__zrd_hostname() {
  emulate -L zsh
  local -aU sources=()
  local -a envs=(HOST HOSTNAME COMPUTERNAME)
  local v out
  for v in "${envs[@]}"; do
    out=${(P)v}
    [[ -n $out && $out == [A-Za-z0-9]* ]] && sources+=("$out")
  done
  out=$(__zrd_exec_whitelisted hostname -s 2>/dev/null); [[ -n $out ]] && sources+=("$out")
  out=$(__zrd_exec_whitelisted hostname 2>/dev/null);    [[ -n $out ]] && sources+=("$out")
  out=$(__zrd_exec_whitelisted uname -n 2>/dev/null);     [[ -n $out ]] && sources+=("$out")
  local -a files=("/etc/hostname" "/proc/sys/kernel/hostname" "/etc/nodename" "/etc/myname")
  local f
  for f in "${files[@]}"; do
    out=$(__zrd_read_regular_file "$f" 256 2>/dev/null) || continue
    sources+=("$out")
  done
  sources+=("localhost" "unknown-host")
  local h
  for h in "${sources[@]}"; do
    [[ -n $h && $h != "unknown-host" ]] || continue
    h=${h%%[[:space:]]*}
    h=${h//[[:cntrl:]]/}
    h=${h:l}
    h=${h//[[:space:]]/-}
    h=${h//[^a-z0-9.-]/}
    h=${h#.}
    h=${h%.}
    h=${h:0:63}
    [[ -n $h && $h == [a-z0-9]* ]] && { print -r -- "$h"; return 0; }
  done
  print -r -- "localhost"
}

__zrd_detect_wsl() {
  emulate -L zsh
  [[ ${1:-} == linux ]] || return 1
  local -a vars=(WSL_DISTRO_NAME WSLENV WSL_INTEROP WSL2_INTEROP)
  local v
  for v in "${vars[@]}"; do
    [[ -n ${(P)v} ]] && return 0
  done
  local s
  s=$(__zrd_read_regular_file "/proc/version" 1024 2>/dev/null) && { [[ ${s:l} == *microsoft* || ${s:l} == *wsl* ]] && return 0; }
  s=$(__zrd_exec_whitelisted uname -r 2>/dev/null) && { [[ ${s:l} == *microsoft* || ${s:l} == *wsl* ]] && return 0; }
  [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]] && return 0
  local -a wp=(/mnt/c /mnt/d /mnt/e)
  local p
  for p in "${wp[@]}"; do
    [[ -d $p ]] && [[ -e $p/Windows/System32 ]] && return 0
  done
  return 1
}

__zrd_detect_container() {
  emulate -L zsh
  [[ -r /.dockerenv || -f /.containerenv ]] && return 0
  local -a vars=(container KUBERNETES_SERVICE_HOST DOCKER_CONTAINER PODMAN_CONTAINER)
  local v
  for v in "${vars[@]}"; do
    [[ -n ${(P)v} ]] && return 0
  done
  local s
  s=$(__zrd_read_regular_file "/run/systemd/container" 64 2>/dev/null) && [[ -n $s ]] && return 0
  s=$(__zrd_read_regular_file "/proc/1/cgroup" 8192 2>/dev/null) && {
    case $s in (*docker*|*lxc*|*kubepods*|*containerd*|*podman*|*crio*) return 0 ;; esac
  }
  s=$(__zrd_read_regular_file "/proc/self/mountinfo" 16384 2>/dev/null) && {
    case $s in (*overlay*|*aufs*|*devicemapper*) return 0 ;; esac
  }
  if __zrd_find_cmd stat >/dev/null 2>&1; then
    local rd prd
    rd=$(__zrd_exec_whitelisted stat -c %d / 2>/dev/null || __zrd_exec_whitelisted stat -f %d / 2>/dev/null)
    prd=$(__zrd_exec_whitelisted stat -c %d /proc/1/root 2>/dev/null || __zrd_exec_whitelisted stat -f %d /proc/1/root 2>/dev/null)
    [[ -n $rd && -n $prd && $rd != $prd ]] && return 0
  fi
  return 1
}

__zrd_detect_vm() {
  emulate -L zsh
  local platform=${1:?}
  if [[ $platform == linux ]]; then
    local -a dmi=(
      "/sys/class/dmi/id/product_name"
      "/sys/class/dmi/id/sys_vendor"
      "/sys/class/dmi/id/board_vendor"
      "/sys/class/dmi/id/bios_vendor"
      "/sys/class/dmi/id/product_version"
      "/sys/class/dmi/id/chassis_vendor"
    )
    local f s
    for f in "${dmi[@]}"; do
      s=$(__zrd_read_regular_file "$f" 512 2>/dev/null) || continue
      case ${s:l} in
        *vmware*|*virtualbox*|*qemu*|*kvm*|*xen*|*hyper-v*|*parallels*|*bochs*|*virtual*|*innotek*|*microsoft*corporation*|*bhyve*) return 0 ;;
      esac
    done
    s=$(__zrd_read_regular_file "/proc/cpuinfo" 8192 2>/dev/null) && {
      case $s in (*hypervisor*|*QEMU*|*VMware*|*Virtual*|*Xen*|*KVM*) return 0 ;; esac
    }
    if __zrd_find_cmd systemd-detect-virt >/dev/null 2>&1; then
      s=$(__zrd_exec_whitelisted systemd-detect-virt 2>/dev/null) && [[ $s != "none" && $s != "unknown" ]] && return 0
      s=$(__zrd_exec_whitelisted systemd-detect-virt --container 2>/dev/null) && [[ -n $s && $s != "none" ]] && return 0
    fi
    [[ -d /proc/vz || -r /proc/xen || -d /sys/bus/xen ]] && return 0
  elif [[ $platform == darwin ]]; then
    if __zrd_find_cmd system_profiler >/dev/null 2>&1; then
      local hw
      hw=$(__zrd_exec_whitelisted system_profiler SPHardwareDataType 2>/dev/null)
      case $hw in (*Virtual*|*VMware*|*Parallels*|*VirtualBox*) return 0 ;; esac
    fi
  fi
  return 1
}

__zrd_detect_macos_version() {
  emulate -L zsh
  local version="unknown" codename="unknown" build="unknown"
  local ver_output build_output plist_output
  if ver_output=$(__zrd_exec_whitelisted sw_vers -productVersion 2>/dev/null) || { (( ! ZRD_CFG_STRICT_CMDS )) && ver_output=$(sw_vers -productVersion 2>/dev/null); }; then
    version=${ver_output//[[:cntrl:]]/}
    __zrd_log 2 "macOS version from sw_vers: $version"
  fi
  if build_output=$(__zrd_exec_whitelisted sw_vers -buildVersion 2>/dev/null) || { (( ! ZRD_CFG_STRICT_CMDS )) && build_output=$(sw_vers -buildVersion 2>/dev/null); }; then
    build=${build_output//[[:cntrl:]]/}
    __zrd_log 2 "macOS build from sw_vers: $build"
  fi
  if [[ $version == "unknown" ]] && [[ -r /System/Library/CoreServices/SystemVersion.plist ]]; then
    if plist_output=$(__zrd_exec_whitelisted plutil -p /System/Library/CoreServices/SystemVersion.plist 2>/dev/null) || { (( ! ZRD_CFG_STRICT_CMDS )) && plist_output=$(plutil -p /System/Library/CoreServices/SystemVersion.plist 2>/dev/null); }; then
      version=$(echo "$plist_output" | grep -E '(ProductUserVisibleVersion|ProductVersion)' | head -1 | sed 's/.*=> "\([^"]*\)".*/\1/')
      [[ -z $build ]] && build=$(echo "$plist_output" | grep 'ProductBuildVersion' | sed 's/.*=> "\([^"]*\)".*/\1/')
      __zrd_log 2 "macOS version from plist: $version, build: $build"
    fi
  fi
  if [[ $version != "unknown" ]]; then
    case $version in
      15.*) codename="Sequoia" ;;
      14.*) codename="Sonoma" ;;
      13.*) codename="Ventura" ;;
      12.*) codename="Monterey" ;;
      11.*) codename="Big Sur" ;;
      10.15.*) codename="Catalina" ;;
      10.14.*) codename="Mojave" ;;
      10.13.*) codename="High Sierra" ;;
      10.12.*) codename="Sierra" ;;
      10.11.*) codename="El Capitan" ;;
      10.10.*) codename="Yosemite" ;;
      10.9.*) codename="Mavericks" ;;
      10.8.*) codename="Mountain Lion" ;;
      10.7.*) codename="Lion" ;;
      10.6.*) codename="Snow Leopard" ;;
      *) codename="macOS" ;;
    esac
  fi
  print -r -- "macos:${version}:${codename}:${build}"
}

__zrd_detect_linux_distro() {
  emulate -L zsh
  local d="unknown" v="unknown" c="unknown" s
  # lsb_release
  if __zrd_find_cmd lsb_release >/dev/null 2>&1; then
    local lsb_id lsb_rel lsb_code
    lsb_id=$(__zrd_exec_whitelisted lsb_release -si 2>/dev/null || (( ! ZRD_CFG_STRICT_CMDS )) && lsb_release -si 2>/dev/null)
    lsb_rel=$(__zrd_exec_whitelisted lsb_release -sr 2>/dev/null || (( ! ZRD_CFG_STRICT_CMDS )) && lsb_release -sr 2>/dev/null)
    lsb_code=$(__zrd_exec_whitelisted lsb_release -sc 2>/dev/null || (( ! ZRD_CFG_STRICT_CMDS )) && lsb_release -sc 2>/dev/null)
    if [[ -n $lsb_id ]]; then
      d=${lsb_id:l}
      [[ -n $lsb_rel ]] && v=$lsb_rel
      [[ -n $lsb_code ]] && c=$lsb_code
      __zrd_log 2 "Linux distro from lsb_release: $d $v ($c)"
    fi
  fi
  # /etc/os-release
  if [[ $d == "unknown" && -r /etc/os-release ]]; then
    s=$(__zrd_read_regular_file "/etc/os-release" 8192 2>/dev/null)
    if [[ -n $s ]]; then
      d=$(__zrd_parse_kv "$s" "ID" 2>/dev/null) || d="unknown"
      v=$(__zrd_parse_kv "$s" "VERSION_ID" 2>/dev/null) || v="unknown"
      c=$(__zrd_parse_kv "$s" "VERSION_CODENAME" 2>/dev/null)
      [[ -z $c ]] && c=$(__zrd_parse_kv "$s" "UBUNTU_CODENAME" 2>/dev/null)
      # Do not substitute PRETTY_NAME as codename; keep unknown for codename if missing
      [[ -z $c ]] && c="unknown"
      __zrd_log 2 "Linux distro from os-release: $d $v ($c)"
    fi
  fi
  # /etc/lsb-release
  if [[ $d == "unknown" && -r /etc/lsb-release ]]; then
    s=$(__zrd_read_regular_file "/etc/lsb-release" 4096 2>/dev/null)
    if [[ -n $s ]]; then
      d=$(__zrd_parse_kv "$s" "DISTRIB_ID" 2>/dev/null) || d="unknown"
      v=$(__zrd_parse_kv "$s" "DISTRIB_RELEASE" 2>/dev/null) || v="unknown"
      c=$(__zrd_parse_kv "$s" "DISTRIB_CODENAME" 2>/dev/null) || c="unknown"
      __zrd_log 2 "Linux distro from lsb-release: $d $v ($c)"
    fi
  fi
  # Legacy files
  if [[ $d == "unknown" ]]; then
    local -A files=(
      [rhel]="/etc/redhat-release"
      [debian]="/etc/debian_version"
      [arch]="/etc/arch-release"
      [gentoo]="/etc/gentoo-release"
      [alpine]="/etc/alpine-release"
      [suse]="/etc/SuSE-release"
      [slackware]="/etc/slackware-version"
      [void]="/etc/void-release"
      [nixos]="/etc/NIXOS"
      [fedora]="/etc/fedora-release"
      [centos]="/etc/centos-release"
      [rocky]="/etc/rocky-release"
      [almalinux]="/etc/almalinux-release"
      [oracle]="/etc/oracle-release"
      [amazon]="/etc/system-release"
    )
    local k f
    for k f in "${(kv)files[@]}"; do
      [[ -r $f ]] || continue
      d=$k
      s=$(__zrd_read_regular_file "$f" 512 2>/dev/null)
      if [[ -n $s ]]; then
        if [[ $s =~ ([0-9]+(\.[0-9]+)*) ]]; then
          v=${match[1]}
        fi
        if [[ $s =~ '\(([^)]+)\)' ]]; then
          c=${match[1]}
        fi
        __zrd_log 2 "Linux distro from $f: $d $v ($c)"
      fi
      break
    done
  fi
  # Normalize distro name
  case ${d:l} in
    ubuntu|debian|mint|kali|elementary|pop|zorin|deepin|raspbian) d=${d:l} ;;
    rhel|centos|fedora|rocky|alma|almalinux|oracle|amazon|scientific) d=${d:l} ;;
    arch|manjaro|endeavour|artix|garuda|antergos|blackarch) d=${d:l} ;;
    opensuse*|suse*|sles*|leap*|tumbleweed*) d="opensuse" ;;
    nixos|gentoo|alpine|void|slackware|freebsd|openbsd|netbsd) d=${d:l} ;;
    "red hat"*) d="rhel" ;;
    "alma linux"*) d="almalinux" ;;
    "rocky linux"*) d="rocky" ;;
    *) d=${d:l} ;;
  esac
  print -r -- "${d}:${v}:${c}"
}

__zrd_collect_uname() {
  emulate -L zsh
  local -A info
  local res
  res=$(__zrd_exec_whitelisted uname -s 2>/dev/null) || { (( ! ZRD_CFG_STRICT_CMDS )) && res=$(uname -s 2>/dev/null) }
  info[system]=${res//[[:cntrl:]]/}
  res=$(__zrd_exec_whitelisted uname -m 2>/dev/null) || { (( ! ZRD_CFG_STRICT_CMDS )) && res=$(uname -m 2>/dev/null) }
  info[machine]=${res%% *}
  res=$(__zrd_exec_whitelisted uname -r 2>/dev/null) || { (( ! ZRD_CFG_STRICT_CMDS )) && res=$(uname -r 2>/dev/null) }
  info[release]=${res%% *}
  res=$(__zrd_exec_whitelisted uname -v 2>/dev/null) || { (( ! ZRD_CFG_STRICT_CMDS )) && res=$(uname -v 2>/dev/null) }
  info[version]=${res//$'\n'/ }
  res=$(__zrd_exec_whitelisted uname -n 2>/dev/null) || { (( ! ZRD_CFG_STRICT_CMDS )) && res=$(uname -n 2>/dev/null) }
  info[nodename]=${res%% *}
  res=$(__zrd_exec_whitelisted uname -p 2>/dev/null) || { (( ! ZRD_CFG_STRICT_CMDS )) && res=$(uname -p 2>/dev/null) }
  info[processor]=${res%% *}
  local k
  for k in ${(k)info}; do
    print -r -- "$k=${info[$k]}"
  done
}

#===============================================================================
# Core detection orchestration
#===============================================================================
zrd_detect() {
  emulate -L zsh -o pipe_fail
  __zrd_cache_valid && return 0
  __zrd_log 2 "Detecting platform and environment"
  local start=$(__zrd_now)

  local -A sys
  local line k v
  while IFS= read -r line; do
    k=${line%%=*}; v=${line#*=}; sys[$k]=$v
  done < <(__zrd_collect_uname)

  sys[ostype]=${OSTYPE:-unknown}
  sys[hosttype]=${HOSTTYPE:-${sys[machine]}}
  sys[hostname]=$(__zrd_hostname)
  local u; u=$(__zrd_exec_whitelisted whoami 2>/dev/null)
  sys[username]=${u//[[:cntrl:]]/}
  [[ -n ${sys[username]} ]] || sys[username]=${USER:-${USERNAME:-unknown}}

  local platform arch
  platform=$(__zrd_normalize_platform "${sys[ostype]%%[0-9]*}")
  [[ $platform == unknown ]] && platform=$(__zrd_normalize_platform "${sys[system]}")
  arch=$(__zrd_normalize_arch "${sys[hosttype]}")
  [[ $arch == unknown ]] && arch=$(__zrd_normalize_arch "${sys[machine]}")
  [[ $arch == unknown ]] && arch=$(__zrd_normalize_arch "${sys[processor]}")

  if [[ $arch == unknown ]]; then
    local uname_m
    if uname_m=$(uname -m 2>/dev/null); then
      arch=$(__zrd_normalize_arch "$uname_m")
      __zrd_log 2 "Architecture from direct uname: $uname_m -> $arch"
    fi
  fi
  if [[ $arch == unknown ]] && [[ -n ${HOSTTYPE:-} ]]; then
    arch=$(__zrd_normalize_arch "${HOSTTYPE}")
    __zrd_log 2 "Architecture from HOSTTYPE: ${HOSTTYPE} -> $arch"
  fi
  if [[ $arch == unknown ]] && [[ -n ${MACHTYPE:-} ]]; then
    arch=$(__zrd_normalize_arch "${MACHTYPE}")
    __zrd_log 2 "Architecture from MACHTYPE: ${MACHTYPE} -> $arch"
  fi
  if [[ $arch == unknown ]] && [[ -n ${CPUTYPE:-} ]]; then
    arch=$(__zrd_normalize_arch "${CPUTYPE}")
    __zrd_log 2 "Architecture from CPUTYPE: ${CPUTYPE} -> $arch"
  fi

  local -i is_wsl=0 is_container=0 is_vm=0 is_termux=0 is_chroot=0
  __zrd_detect_wsl "$platform" && is_wsl=1
  __zrd_detect_container && is_container=1
  __zrd_detect_vm "$platform" && is_vm=1

  if [[ -n ${TERMUX_VERSION:-} ]] || [[ -d /data/data/com.termux && -r /data/data/com.termux/files ]]; then
    is_termux=1
  fi

  if [[ $platform == linux ]] && (( is_container == 0 )) && __zrd_find_cmd stat >/dev/null 2>&1; then
    local r1 r2
    r1=$(__zrd_exec_whitelisted stat -c %i / 2>/dev/null || __zrd_exec_whitelisted stat -f %i / 2>/dev/null)
    r2=$(__zrd_exec_whitelisted stat -c %i /proc/1/root 2>/dev/null || __zrd_exec_whitelisted stat -f %i /proc/1/root 2>/dev/null)
    [[ -n $r1 && -n $r2 && $r1 != $r2 ]] && is_chroot=1
  fi

  local distro="unknown" dver="unknown" dcode="unknown"
  if [[ $platform == linux ]]; then
    local di
    di=$(__zrd_detect_linux_distro)
    distro=${di%%:*}
    dver=${di#*:}; dver=${dver%%:*}
    dcode=${di##*:}
  elif [[ $platform == darwin ]]; then
    local di temp
    di=$(__zrd_detect_macos_version)
    distro=${di%%:*}
    temp=${di#*:}
    dver=${temp%%:*}
    temp=${temp#*:}
    dcode=${temp%%:*}
    __zrd_log 2 "macOS detection: distro=$distro, version=$dver, codename=$dcode"
  fi

  # Export public state
  typeset -g ZRD_PLATFORM="$platform"
  typeset -g ZRD_ARCH="$arch"
  typeset -g ZRD_KERNEL="${sys[system]}"
  typeset -g ZRD_KERNEL_RELEASE="${sys[release]}"
  typeset -g ZRD_KERNEL_VERSION="${sys[version]}"
  typeset -g ZRD_HOSTNAME="${sys[hostname]}"
  typeset -g ZRD_USERNAME="${sys[username]}"
  typeset -g ZRD_DISTRO="$distro"
  typeset -g ZRD_DISTRO_VERSION="$dver"
  typeset -g ZRD_DISTRO_CODENAME="$dcode"

  local -i is_macos=0 is_linux=0 is_bsd=0 is_unix=0 is_arm=0 is_x86_64=0
  [[ $platform == "darwin" ]] && is_macos=1
  [[ $platform == "linux" ]] && is_linux=1
  [[ $platform == "freebsd" || $platform == "openbsd" || $platform == "netbsd" || $platform == "dragonfly" ]] && is_bsd=1
  [[ $platform != "windows" && $platform != "unknown" ]] && is_unix=1
  [[ $arch == "arm" || $arch == "aarch64" ]] && is_arm=1
  [[ $arch == "x86_64" ]] && is_x86_64=1

  typeset -gi ZRD_IS_MACOS=$is_macos
  typeset -gi ZRD_IS_LINUX=$is_linux
  typeset -gi ZRD_IS_BSD=$is_bsd
  typeset -gi ZRD_IS_UNIX=$is_unix
  typeset -gi ZRD_IS_ARM=$is_arm
  typeset -gi ZRD_IS_X86_64=$is_x86_64
  typeset -gi ZRD_IS_WSL=$is_wsl
  typeset -gi ZRD_IS_CONTAINER=$is_container
  typeset -gi ZRD_IS_VM=$is_vm
  typeset -gi ZRD_IS_TERMUX=$is_termux
  typeset -gi ZRD_IS_CHROOT=$is_chroot

  local -i is_interactive=0
  [[ ${options[interactive]:-} == on ]] && is_interactive=1
  typeset -gi ZRD_IS_INTERACTIVE=$is_interactive
  typeset -gi ZRD_IS_SSH=$(( ${#SSH_CLIENT} > 0 || ${#SSH_TTY} > 0 || ${#SSH_CONNECTION} > 0 ))
  typeset -gi ZRD_IS_ROOT=$(( ${EUID:-1000} == 0 ))

  local -i ci=0
  local -a ci_vars=(CI CONTINUOUS_INTEGRATION GITHUB_ACTIONS GITLAB_CI TRAVIS CIRCLECI JENKINS_URL BUILDKITE APPVEYOR)
  local cv
  for cv in "${ci_vars[@]}"; do
    [[ -n ${(P)cv} ]] && { ci=1; break; }
  done
  typeset -gi ZRD_IS_CI=$ci

  # Update cache
  __ZRD_CACHE_DETECTED=1
  __ZRD_CACHE_TIME=$(__zrd_now)
  __ZRD_CACHE_SIGNATURE=$(__zrd_cache_signature)
  __ZRD_CACHE_VERSION=$__ZRD_MODULE_VERSION

  if (( ZRD_CFG_DEBUG >= 2 )); then
    local -i dt=$(( $(__zrd_now) - start ))
    {
      print -P "%F{green}[platform] Detection complete (${dt}s)%f"
      print -P "  %F{cyan}System:%f $ZRD_PLATFORM/$ZRD_ARCH ($ZRD_KERNEL $ZRD_KERNEL_RELEASE)"
      print -P "  %F{cyan}Host:%f $ZRD_HOSTNAME ($ZRD_USERNAME)"
      (( ZRD_IS_LINUX || ZRD_IS_MACOS )) && print -P "  %F{cyan}Distro:%f $ZRD_DISTRO $ZRD_DISTRO_VERSION${ZRD_DISTRO_CODENAME:+ ($ZRD_DISTRO_CODENAME)}"
      print -P "  %F{cyan}Flags:%f macOS=$ZRD_IS_MACOS Linux=$ZRD_IS_LINUX BSD=$ZRD_IS_BSD Unix=$ZRD_IS_UNIX"
      print -P "  %F{cyan}Arch:%f ARM=$ZRD_IS_ARM x86_64=$ZRD_IS_X86_64"
      print -P "  %F{cyan}Env:%f WSL=$ZRD_IS_WSL Container=$ZRD_IS_CONTAINER VM=$ZRD_IS_VM Root=$ZRD_IS_ROOT CI=$ZRD_IS_CI"
      print -P "  %F{cyan}Session:%f SSH=$ZRD_IS_SSH Interactive=$ZRD_IS_INTERACTIVE Termux=$ZRD_IS_TERMUX Chroot=$ZRD_IS_CHROOT"
      print -P "  %F{cyan}Cache:%f TTL=${ZRD_CFG_CACHE_TTL}s"
    } >&2
  fi
  return 0
}

#===============================================================================
# Public API
#===============================================================================
zrd_available() {
  emulate -L zsh
  if (( __ZRD_CACHE_DETECTED )); then
    return 0
  elif (( ${ZRD_CFG_AUTO_DETECT:-0} == 1 )); then
    zrd_detect
  else
    return 1
  fi
}

zrd_refresh() {
  emulate -L zsh
  __ZRD_CACHE_DETECTED=0
  __ZRD_CACHE_TIME=0
  zrd_detect
}

zrd_summary() {
  emulate -L zsh
  zrd_available || return 1
  printf "%s/%s" "$ZRD_PLATFORM" "$ZRD_ARCH"
}

zrd_info() {
  emulate -L zsh
  zrd_available || return 1
  local type=${1:-summary}
  case $type in
    summary|short)
      printf "%s/%s" "$ZRD_PLATFORM" "$ZRD_ARCH"
      ;;
    full|detailed)
      printf "%s/%s (%s %s)" "$ZRD_PLATFORM" "$ZRD_ARCH" "$ZRD_KERNEL" "$ZRD_KERNEL_RELEASE"
      ;;
    extended)
      local -a flags=()
      (( ZRD_IS_MACOS )) && flags+=(macOS)
      (( ZRD_IS_LINUX )) && flags+=(Linux)
      (( ZRD_IS_BSD )) && flags+=(BSD)
      (( ZRD_IS_WSL )) && flags+=(WSL)
      (( ZRD_IS_CONTAINER )) && flags+=(Container)
      (( ZRD_IS_VM )) && flags+=(VM)
      (( ZRD_IS_SSH )) && flags+=(SSH)
      (( ZRD_IS_TERMUX )) && flags+=(Termux)
      (( ZRD_IS_ROOT )) && flags+=(Root)
      (( ZRD_IS_CI )) && flags+=(CI)
      printf "%s/%s (%s %s) [%s]" "$ZRD_PLATFORM" "$ZRD_ARCH" "$ZRD_KERNEL" "$ZRD_KERNEL_RELEASE" "${(j:,:)flags}"
      ;;
    distro)
      if (( ZRD_IS_LINUX || ZRD_IS_MACOS )); then
        printf "%s %s" "$ZRD_DISTRO" "$ZRD_DISTRO_VERSION"
        [[ $ZRD_DISTRO_CODENAME != "unknown" ]] && printf " (%s)" "$ZRD_DISTRO_CODENAME"
      else
        echo "N/A"
      fi
      ;;
    hostname)
      echo "$ZRD_HOSTNAME"
      ;;
    username)
      echo "$ZRD_USERNAME"
      ;;
    flags)
      local -a active=()
      (( ZRD_IS_MACOS )) && active+=(macOS)
      (( ZRD_IS_LINUX )) && active+=(Linux)
      (( ZRD_IS_BSD )) && active+=(BSD)
      (( ZRD_IS_WSL )) && active+=(WSL)
      (( ZRD_IS_CONTAINER )) && active+=(Container)
      (( ZRD_IS_VM )) && active+=(VM)
      (( ZRD_IS_SSH )) && active+=(SSH)
      (( ZRD_IS_TERMUX )) && active+=(Termux)
      (( ZRD_IS_ROOT )) && active+=(Root)
      (( ZRD_IS_CI )) && active+=(CI)
      printf "%s" "${(j:,:)active}"
      ;;
    json)
      printf '{\n'
      printf '  "platform": "%s",\n' "$(__zrd_json_escape "$ZRD_PLATFORM")"
      printf '  "architecture": "%s",\n' "$(__zrd_json_escape "$ZRD_ARCH")"
      printf '  "kernel": "%s",\n' "$(__zrd_json_escape "$ZRD_KERNEL")"
      printf '  "kernel_release": "%s",\n' "$(__zrd_json_escape "$ZRD_KERNEL_RELEASE")"
      printf '  "kernel_version": "%s",\n' "$(__zrd_json_escape "$ZRD_KERNEL_VERSION")"
      printf '  "hostname": "%s",\n' "$(__zrd_json_escape "$ZRD_HOSTNAME")"
      printf '  "username": "%s",\n' "$(__zrd_json_escape "$ZRD_USERNAME")"
      printf '  "distro": "%s",\n' "$(__zrd_json_escape "$ZRD_DISTRO")"
      printf '  "distro_version": "%s",\n' "$(__zrd_json_escape "$ZRD_DISTRO_VERSION")"
      printf '  "distro_codename": "%s",\n' "$(__zrd_json_escape "$ZRD_DISTRO_CODENAME")"
      printf '  "flags": {\n'
      if (( ZRD_CFG_JSON_BOOL )); then
        printf '    "is_macos": %s,\n' "$(__zrd_bool $ZRD_IS_MACOS)"
        printf '    "is_linux": %s,\n' "$(__zrd_bool $ZRD_IS_LINUX)"
        printf '    "is_bsd": %s,\n' "$(__zrd_bool $ZRD_IS_BSD)"
        printf '    "is_unix": %s,\n' "$(__zrd_bool $ZRD_IS_UNIX)"
        printf '    "is_arm": %s,\n' "$(__zrd_bool $ZRD_IS_ARM)"
        printf '    "is_x86_64": %s,\n' "$(__zrd_bool $ZRD_IS_X86_64)"
        printf '    "is_wsl": %s,\n' "$(__zrd_bool $ZRD_IS_WSL)"
        printf '    "is_container": %s,\n' "$(__zrd_bool $ZRD_IS_CONTAINER)"
        printf '    "is_vm": %s,\n' "$(__zrd_bool $ZRD_IS_VM)"
        printf '    "is_termux": %s,\n' "$(__zrd_bool $ZRD_IS_TERMUX)"
        printf '    "is_chroot": %s,\n' "$(__zrd_bool $ZRD_IS_CHROOT)"
        printf '    "is_interactive": %s,\n' "$(__zrd_bool $ZRD_IS_INTERACTIVE)"
        printf '    "is_ssh": %s,\n' "$(__zrd_bool $ZRD_IS_SSH)"
        printf '    "is_root": %s,\n' "$(__zrd_bool $ZRD_IS_ROOT)"
        printf '    "is_ci": %s\n' "$(__zrd_bool $ZRD_IS_CI)"
      else
      printf '    "is_macos": %d,\n' $ZRD_IS_MACOS
      printf '    "is_linux": %d,\n' $ZRD_IS_LINUX
      printf '    "is_bsd": %d,\n' $ZRD_IS_BSD
      printf '    "is_unix": %d,\n' $ZRD_IS_UNIX
      printf '    "is_arm": %d,\n' $ZRD_IS_ARM
      printf '    "is_x86_64": %d,\n' $ZRD_IS_X86_64
      printf '    "is_wsl": %d,\n' $ZRD_IS_WSL
      printf '    "is_container": %d,\n' $ZRD_IS_CONTAINER
      printf '    "is_vm": %d,\n' $ZRD_IS_VM
      printf '    "is_termux": %d,\n' $ZRD_IS_TERMUX
      printf '    "is_chroot": %d,\n' $ZRD_IS_CHROOT
      printf '    "is_interactive": %d,\n' $ZRD_IS_INTERACTIVE
      printf '    "is_ssh": %d,\n' $ZRD_IS_SSH
      printf '    "is_root": %d,\n' $ZRD_IS_ROOT
      printf '    "is_ci": %d\n' $ZRD_IS_CI
      fi
      printf '  },\n'
      printf '  "metadata": {\n'
      printf '    "version": "%s",\n' "$(__zrd_json_escape "$__ZRD_MODULE_VERSION")"
      printf '    "api_version": "%s",\n' "$(__zrd_json_escape "$__ZRD_API_VERSION")"
      printf '    "cache_ttl": %d,\n' $ZRD_CFG_CACHE_TTL
      printf '    "detected_at": %d\n' ${__ZRD_CACHE_TIME:-0}
      printf '  }\n'
      printf '}\n'
      ;;
    version)
      echo "$__ZRD_MODULE_VERSION"
      ;;
    api-version)
      echo "$__ZRD_API_VERSION"
      ;;
    *)
      __zrd_log 0 "Unknown info type: $type"
      print -u2 -P "Valid types: summary, full, extended, distro, hostname, username, flags, json, version, api-version"
      return 1
      ;;
  esac
}

zrd_is() {
  emulate -L zsh
  local target=${1:?Missing platform target}
  zrd_available || return 1
  case ${target:l} in
    macos|darwin|mac) (( ZRD_IS_MACOS )) ;;
    linux) (( ZRD_IS_LINUX )) ;;
    bsd) (( ZRD_IS_BSD )) ;;
    unix) (( ZRD_IS_UNIX )) ;;
    windows) [[ $ZRD_PLATFORM == "windows" ]] ;;
    wsl) (( ZRD_IS_WSL )) ;;
    container) (( ZRD_IS_CONTAINER )) ;;
    vm) (( ZRD_IS_VM )) ;;
    ssh) (( ZRD_IS_SSH )) ;;
    termux) (( ZRD_IS_TERMUX )) ;;
    chroot) (( ZRD_IS_CHROOT )) ;;
    interactive) (( ZRD_IS_INTERACTIVE )) ;;
    root) (( ZRD_IS_ROOT )) ;;
    ci) (( ZRD_IS_CI )) ;;
    bare-metal) (( ! ZRD_IS_VM && ! ZRD_IS_CONTAINER && ! ZRD_IS_WSL )) ;;
    *)
      __zrd_log 0 "Unknown platform target: $target"
      return 1
      ;;
  esac
}

zrd_arch() {
  emulate -L zsh
  zrd_available || return 1
  local q=${1:-name}
  case $q in
    name) echo "$ZRD_ARCH" ;;
    bits)
      case $ZRD_ARCH in
        x86_64|aarch64|powerpc64|mips64|s390x|alpha|ia64|riscv64) echo "64" ;;
        i386|arm|mips|s390|powerpc|riscv) echo "32" ;;
        *) echo "unknown" ;;
      esac
      ;;
    family)
      case $ZRD_ARCH in
        x86_64|i386) echo "x86" ;;
        aarch64|arm) echo "arm" ;;
        powerpc|powerpc64) echo "power" ;;
        mips|mips64) echo "mips" ;;
        s390|s390x) echo "s390" ;;
        riscv|riscv64) echo "riscv" ;;
        *) echo "$ZRD_ARCH" ;;
      esac
      ;;
    endian)
      case $ZRD_ARCH in
        x86_64|i386|aarch64|arm|mips|mips64|s390|s390x|powerpc64|riscv|riscv64) echo "little" ;;
        powerpc|sparc) echo "big" ;;
        *) echo "unknown" ;;
      esac
      ;;
    instruction-set|isa)
      case $ZRD_ARCH in
        x86_64) echo "x86-64" ;;
        i386) echo "x86" ;;
        aarch64) echo "ARMv8-A" ;;
        arm) echo "ARMv7" ;;
        riscv64|riscv) echo "RV64I/RV32I" ;;
        *) echo "$ZRD_ARCH" ;;
      esac
      ;;
    *)
      print -u2 -P "Valid: name, bits, family, endian, instruction-set"
      return 1
      ;;
  esac
}

zrd_paths() {
  emulate -L zsh
  zrd_available || return 1
  local kind=${1:-temp}
  case $kind in
    temp|tmp)
      if (( ZRD_IS_MACOS )); then
        echo "${TMPDIR:-/tmp}"
      elif (( ZRD_IS_TERMUX )); then
        echo "${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
      else
        echo "${TMPDIR:-/tmp}"
      fi
      ;;
    config)
      if (( ZRD_IS_MACOS )); then
        echo "${HOME}/Library/Preferences"
      elif (( ZRD_IS_TERMUX )); then
        echo "${HOME}/.config"
      elif (( ZRD_IS_UNIX )); then
        echo "${XDG_CONFIG_HOME:-$HOME/.config}"
      else
        echo "$HOME"
      fi
      ;;
    cache)
      if (( ZRD_IS_MACOS )); then
        echo "${HOME}/Library/Caches"
      elif (( ZRD_IS_TERMUX )); then
        echo "${HOME}/.cache"
      elif (( ZRD_IS_UNIX )); then
        echo "${XDG_CACHE_HOME:-$HOME/.cache}"
      else
        echo "$HOME"
      fi
      ;;
    data)
      if (( ZRD_IS_MACOS )); then
        echo "${HOME}/Library/Application Support"
      elif (( ZRD_IS_TERMUX )); then
        echo "${HOME}/.local/share"
      elif (( ZRD_IS_UNIX )); then
        echo "${XDG_DATA_HOME:-$HOME/.local/share}"
      else
        echo "$HOME"
      fi
      ;;
    runtime)
      if (( ZRD_IS_UNIX )); then
        echo "${XDG_RUNTIME_DIR:-/tmp}"
      else
        echo "/tmp"
      fi
      ;;
    home)
      echo "$HOME"
      ;;
    *)
      __zrd_log 0 "Unknown path type: $kind"
      print -u2 -P "Valid: temp, config, cache, data, runtime, home"
      return 1
      ;;
  esac
}

zrd_status() {
  emulate -L zsh
  print -P "%F{cyan}Platform Detection Module%f"
  print -P "  %F{yellow}Version:%f $__ZRD_MODULE_VERSION (API: $__ZRD_API_VERSION)"
  print -P "  %F{yellow}Loaded:%f ${__ZRD_MODULE_LOADED:+Yes}"
  print -P "  %F{yellow}Detected:%f ${__ZRD_CACHE_DETECTED:+Yes}"
  print -P "  %F{yellow}Mode:%f strict_cmds=$ZRD_CFG_STRICT_CMDS sanitize_env=$ZRD_CFG_SANITIZE_ENV json_bool=$ZRD_CFG_JSON_BOOL"
  if zrd_available; then
    print -P "  %F{yellow}Platform:%f $(zrd_summary)"
    print -P "  %F{yellow}Cache TTL:%f ${ZRD_CFG_CACHE_TTL}s"
    local now=$(__zrd_now)
    local -i age=$(( now - __ZRD_CACHE_TIME ))
    print -P "  %F{yellow}Cache Age:%f ${age}s"
    print -P "  %F{yellow}Configuration:%f"
    print -P "    %F{blue}Auto-detect:%f ${ZRD_CFG_AUTO_DETECT:+Enabled}"
    print -P "    %F{blue}Debug:%f ${ZRD_CFG_DEBUG:+Level $ZRD_CFG_DEBUG}"
    print -P "    %F{blue}Max file size:%f ${ZRD_CFG_MAX_FILE_SIZE} bytes"
    print -P "    %F{blue}Command timeout:%f ${ZRD_CFG_CMD_TIMEOUT}s"
  else
    print -P "  %F{red}Status:%f Not detected (run zrd_detect)"
  fi
}

zrd_cleanup() {
  emulate -L zsh
  unset __ZRD_CACHE_DETECTED __ZRD_CACHE_TIME __ZRD_CACHE_SIGNATURE __ZRD_CACHE_VERSION 2>/dev/null
  unset ZRD_CFG_AUTO_DETECT ZRD_CFG_DEBUG ZRD_CFG_CACHE_TTL ZRD_CFG_MAX_FILE_SIZE ZRD_CFG_CMD_TIMEOUT \
        ZRD_CFG_STRICT_CMDS ZRD_CFG_JSON_BOOL ZRD_CFG_SANITIZE_ENV 2>/dev/null
  unset __ZRD_CMD_PATH_CACHE 2>/dev/null
  unset __ZRD_MODULE_LOADED 2>/dev/null

  local -a vars=(
    ZRD_PLATFORM ZRD_ARCH ZRD_KERNEL ZRD_KERNEL_RELEASE ZRD_KERNEL_VERSION
    ZRD_HOSTNAME ZRD_USERNAME ZRD_DISTRO ZRD_DISTRO_VERSION ZRD_DISTRO_CODENAME
    ZRD_IS_MACOS ZRD_IS_LINUX ZRD_IS_BSD ZRD_IS_UNIX ZRD_IS_ARM ZRD_IS_X86_64
    ZRD_IS_WSL ZRD_IS_CONTAINER ZRD_IS_VM ZRD_IS_TERMUX ZRD_IS_CHROOT
    ZRD_IS_INTERACTIVE ZRD_IS_SSH ZRD_IS_ROOT ZRD_IS_CI
  )
  local fn v
  for v in "${vars[@]}"; do
    unset "$v" 2>/dev/null
  done

  local -a fns=(
    zrd_detect zrd_available zrd_refresh zrd_summary zrd_info zrd_is
    zrd_arch zrd_paths zrd_status zrd_cleanup
    __zrd_log __zrd_now __zrd_json_escape __zrd_validate_config
    __zrd_find_cmd __zrd_exec_whitelisted __zrd_with_timeout
    __zrd_read_regular_file __zrd_parse_kv __zrd_cache_signature __zrd_cache_valid
    __zrd_normalize_platform __zrd_normalize_arch __zrd_hostname
    __zrd_detect_wsl __zrd_detect_container __zrd_detect_vm
    __zrd_detect_linux_distro __zrd_detect_macos_version __zrd_collect_uname
    __zrd_bool __zrd_sanitize_exec_env
  )
  for fn in "${fns[@]}"; do
    unfunction "$fn" 2>/dev/null
  done
}

# Auto-detect if enabled
if (( ${ZRD_CFG_AUTO_DETECT:-0} == 1 )); then
  zrd_detect
fi

__zrd_log 2 "Module v$__ZRD_MODULE_VERSION loaded"
