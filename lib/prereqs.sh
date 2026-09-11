# shellcheck shell=bash
# Everything that must exist before Homebrew can run, plus Homebrew itself.

install_system_prereqs() {
  step "system prerequisites"

  if [ "$OS" = darwin ]; then
    if ! xcode-select -p >/dev/null 2>&1; then
      log "installing Xcode command line tools (a GUI dialog will appear)"
      xcode-select --install || true
      log "waiting for command line tools..."
      until xcode-select -p >/dev/null 2>&1; do sleep 10; done
    fi
    log "xcode command line tools present"
    return 0
  fi

  detect_pkg_mgr
  case "$PKG" in
    apt)
      sudo apt-get update -qq
      sudo apt-get install -y -qq curl git unzip build-essential procps file
      ;;
    pacman)
      sudo pacman -Sy --needed --noconfirm curl git unzip base-devel procps-ng file
      ;;
    dnf)
      sudo dnf install -y -q curl git unzip @development-tools procps-ng file
      ;;
    zypper)
      sudo zypper --non-interactive install curl git unzip gcc make procps file
      ;;
  esac
  log "system prerequisites installed via $PKG"
}

install_homebrew() {
  step "homebrew"

  if have brew; then
    log "brew already present at $(command -v brew)"
  else
    log "installing homebrew (non-interactive)"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      >>"$LOG_FILE" 2>&1 || die "homebrew install failed; see $LOG_FILE"
  fi

  # Put brew on PATH for the rest of this script regardless of shell rc state.
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$candidate" ]; then
      eval "$("$candidate" shellenv)"
      break
    fi
  done

  have brew || die "brew installed but not on PATH"
  log "brew ready: $(brew --version | head -1)"
}

# chezmoi, age and gh are the three tools the handoff needs. Everything else
# comes later from the Brewfile the private repo deploys.
install_core_tools() {
  step "core tools (chezmoi, age, gh)"
  for pkg in chezmoi age gh; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      log "$pkg already installed"
    else
      log "installing $pkg"
      brew install "$pkg" >>"$LOG_FILE" 2>&1 || die "failed to install $pkg"
    fi
  done
}

# 1Password CLI. On macOS it is a cask. On Linux it is NOT available through
# Homebrew at all, so we take the official static binary — which also avoids
# committing to apt vs pacman.
install_op() {
  step "1Password CLI"

  if have op; then
    log "op already present: $(op --version 2>/dev/null || echo unknown)"
    return 0
  fi

  if [ "$OS" = darwin ]; then
    brew install --cask 1password-cli >>"$LOG_FILE" 2>&1 \
      || die "failed to install 1password-cli cask"
    log "op installed via cask"
    return 0
  fi

  local version url tmp
  version="${OP_VERSION:-2.39.0}"
  url="https://cache.agilebits.com/dist/1P/op2/pkg/v${version}/op_linux_${ARCH}_v${version}.zip"
  tmp="$(mktemp -d)"

  log "downloading op ${version} for linux/${ARCH}"
  curl -fsSL "$url" -o "$tmp/op.zip" || die "could not download op from $url"
  unzip -q -o "$tmp/op.zip" -d "$tmp" || die "could not unzip op archive"
  sudo install -m 0755 "$tmp/op" /usr/local/bin/op || die "could not install op"
  rm -rf "$tmp"
  log "op installed to /usr/local/bin/op"
}
