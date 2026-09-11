#!/usr/bin/env bash
#
# machine-init — bring a bare machine to the point where chezmoi can take over.
#
#   curl -fsSL https://raw.githubusercontent.com/hughcameron/machine-init/main/install.sh | bash
#
# What it does, in order: system prerequisites, Homebrew, chezmoi/age/gh, the
# 1Password CLI, the age identity, GitHub access, then `chezmoi init --apply`
# against the private config repo. It stops there on purpose — installing the
# full Brewfile, yazi plugins and project repos is a handful of commands you
# run with a working shell and a debugger, rather than a long unattended script
# that fails halfway on a machine with no tooling.
#
# Safe to re-run. It never overwrites an existing age key and never prints one.
#
# Environment overrides:
#   CONFIG_REPO                  private chezmoi source (default below)
#   OP_AGE_ITEM                  op:// reference to the age identity
#   AGE_KEY_PATH                 where to write it
#   OP_SERVICE_ACCOUNT_TOKEN     non-interactive 1Password auth (see README)
#   MACHINE_INIT_ASSUME_YES      skip confirmation prompts
#   LOG_FILE                     default $TMPDIR/machine-init.log

set -euo pipefail

: "${CONFIG_REPO:=git@github.com:hughcameron/config.git}"
: "${LOG_FILE:=${TMPDIR:-/tmp}/machine-init.log}"

# When piped from curl there is no script directory to source from, so fetch the
# library files the same way. When cloned, use the local copies.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
LIB_BASE="${LIB_BASE:-https://raw.githubusercontent.com/hughcameron/machine-init/main/lib}"

LIB_TMP=""
cleanup() { [ -n "$LIB_TMP" ] && rm -rf "$LIB_TMP"; }
trap cleanup EXIT

source_lib() {
  local name="$1"
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/lib/$name" ]; then
    # shellcheck disable=SC1090
    . "$SCRIPT_DIR/lib/$name"
    return
  fi
  # Piped from curl: bash's own stdin is the script, so fetch to a temp file
  # rather than trying to source through it.
  [ -n "$LIB_TMP" ] || LIB_TMP="$(mktemp -d)"
  curl -fsSL "$LIB_BASE/$name" -o "$LIB_TMP/$name" \
    || { echo "could not fetch $name from $LIB_BASE" >&2; exit 1; }
  # shellcheck disable=SC1090
  . "$LIB_TMP/$name"
}

source_lib common.sh
source_lib prereqs.sh
source_lib credentials.sh

main() {
  : >"$LOG_FILE"
  log "machine-init starting"
  log "log file: $LOG_FILE"

  require_non_root
  detect_platform

  if ! confirm "Bootstrap this machine from $CONFIG_REPO?"; then
    die "cancelled"
  fi

  install_system_prereqs
  install_homebrew
  install_core_tools
  install_op

  fetch_age_key
  authenticate_github

  step "chezmoi handoff"
  if [ -d "$HOME/.local/share/chezmoi/.git" ] || chezmoi source-path >/dev/null 2>&1; then
    log "chezmoi source already initialised; applying"
    chezmoi apply || die "chezmoi apply failed"
  else
    log "initialising chezmoi from $CONFIG_REPO"
    chezmoi init --apply "$CONFIG_REPO" || die "chezmoi init failed"
  fi

  step "done"
  log "chezmoi has applied your configuration. Remaining manual steps:"
  log ""
  log "  brew bundle install --file ~/.config/homebrew/brewfile-\$(uname -s | tr 'A-Z' 'a-z').txt"
  log "  ya pkg install                 # yazi plugins"
  log "  gh repo clone ...              # project repos"
  log ""
  log "Full log: $LOG_FILE"
}

main "$@"
