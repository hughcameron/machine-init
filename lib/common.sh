# shellcheck shell=bash
# Shared helpers: logging, platform detection, guards.
# Sourced by install.sh. Not executable on its own.

: "${LOG_FILE:=${TMPDIR:-/tmp}/machine-init.log}"

log() {
  printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOG_FILE" >&2
}

die() {
  log "FATAL: $*"
  log "Log kept at $LOG_FILE"
  exit 1
}

step() {
  log ""
  log "=== $* ==="
}

have() { command -v "$1" >/dev/null 2>&1; }

# Detect platform once. Sets OS and ARCH.
detect_platform() {
  case "$(uname -s)" in
    Darwin) OS=darwin ;;
    Linux)  OS=linux ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac

  case "$(uname -m)" in
    arm64|aarch64) ARCH=arm64 ;;
    x86_64|amd64)  ARCH=amd64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac

  export OS ARCH
  log "platform: $OS/$ARCH"
}

# Which package manager bootstraps the prerequisites Homebrew itself needs.
# Kept distro-agnostic on purpose: Ubuntu on the mini PC today, possibly an
# Arch-based desktop later, and neither should need a new branch here.
detect_pkg_mgr() {
  if   have apt-get; then PKG=apt
  elif have pacman;  then PKG=pacman
  elif have dnf;     then PKG=dnf
  elif have zypper;  then PKG=zypper
  else die "no supported package manager found (apt/pacman/dnf/zypper)"
  fi
  export PKG
  log "package manager: $PKG"
}

# Refuse to run as root. Homebrew will not install as root, and a bootstrap that
# creates root-owned files in $HOME leaves a machine that is worse than bare.
require_non_root() {
  if [ "$(id -u)" -eq 0 ]; then
    die "run as your own user, not root (sudo is used per-command where needed)"
  fi
}

confirm() {
  # Non-interactive runs (cloud-init) must not block on a prompt.
  if [ -n "${MACHINE_INIT_ASSUME_YES:-}" ] || [ ! -t 0 ]; then
    return 0
  fi
  printf '%s [y/N] ' "$1" >&2
  read -r reply
  case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}
