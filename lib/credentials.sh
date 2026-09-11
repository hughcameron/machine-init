# shellcheck shell=bash
# The two credentials the handoff needs:
#   1. the age identity, so chezmoi can decrypt the private repo's secrets
#   2. GitHub access, so chezmoi can clone the private repo at all
#
# Nothing in here ever writes a secret to stdout, to the log, or to the shell
# history. The age key goes from `op` straight into a 0600 file.

: "${OP_AGE_ITEM:=op://Infra/Chezmoi Setup/keys.txt}"
: "${AGE_KEY_PATH:=$HOME/.config/chezmoi/age/keys.txt}"

# A service-account token is a bearer credential with no second factor. It is
# fine in a provisioning seed that is used once and discarded; it is not fine
# sitting on the disk of the machine whose secrets it unlocks, because then the
# age encryption protects nothing.
warn_if_token_persisted() {
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || return 0

  log "NOTE: authenticating with a 1Password service account token."
  log "      This token must NOT survive provisioning. Before you hand the"
  log "      machine over, confirm it is absent from shell rc files, systemd"
  log "      units, and the cloud-init seed left on disk, or expire it:"
  log "        op service-account ratelimit   # confirms which account is in use"
}

fetch_age_key() {
  step "age identity"

  if [ -s "$AGE_KEY_PATH" ]; then
    log "age key already present at $AGE_KEY_PATH — leaving it untouched"
    return 0
  fi

  have op || die "op is required to fetch the age key"
  warn_if_token_persisted

  if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    # `op account list` exits 0 with EMPTY output when no account is configured,
    # so its exit status cannot be used as the guard — test the output instead.
    if [ -z "$(op account list 2>/dev/null)" ]; then
      if [ ! -t 0 ]; then
        die "no 1Password account configured and no TTY to sign in on.
      Either run this from an interactive session, or provide a service
      account token in OP_SERVICE_ACCOUNT_TOKEN. See the README."
      fi
      log "no 1Password account configured; starting sign-in"
      op account add || die "1Password account setup failed"
    fi

    # Likewise, `eval \"\$(op signin)\"` reports eval's status, not op's: a failed
    # signin yields an empty string and eval succeeds. Capture it separately.
    local signin_env
    if ! signin_env="$(op signin 2>>"$LOG_FILE")" || [ -z "$signin_env" ]; then
      die "1Password sign-in failed; see $LOG_FILE"
    fi
    eval "$signin_env"
  fi

  mkdir -p "$(dirname "$AGE_KEY_PATH")"
  umask 077
  if ! op read "$OP_AGE_ITEM" > "$AGE_KEY_PATH" 2>>"$LOG_FILE"; then
    rm -f "$AGE_KEY_PATH"
    die "could not read age key from $OP_AGE_ITEM (check vault and item name)"
  fi
  chmod 600 "$AGE_KEY_PATH"

  # Validate shape without ever echoing the key.
  if ! grep -q '^AGE-SECRET-KEY-' "$AGE_KEY_PATH"; then
    rm -f "$AGE_KEY_PATH"
    die "$OP_AGE_ITEM did not contain an age secret key"
  fi
  log "age key written to $AGE_KEY_PATH (0600, contents not logged)"
}

authenticate_github() {
  step "github access"

  if gh auth status >/dev/null 2>&1; then
    log "gh already authenticated"
  else
    # gh auth login blocks forever without a TTY — closing stdin is not enough
    # to make it give up — so refuse rather than hang a provisioning run.
    [ -t 0 ] || die "GitHub authentication needs an interactive terminal.
      Run this from an SSH session rather than from cloud-init or a pipe."
    log "starting gh device-flow login — you will be given a code to enter"
    log "on another device at https://github.com/login/device"
    gh auth login --git-protocol ssh --hostname github.com \
      || die "gh auth login failed"
  fi

  # chezmoi clones over SSH, so gh's credential helper is not enough on its own;
  # an SSH key must be present and registered. gh can upload one for us.
  # Bounded: an unreachable or filtered github.com must not stall the run.
  if ! ssh -o StrictHostKeyChecking=accept-new \
           -o BatchMode=yes -o ConnectTimeout=10 \
           -T git@github.com 2>&1 | grep -q 'successfully authenticated'; then
    log "no working SSH key for github; generating and uploading one"
    gh auth refresh -h github.com -s admin:public_key >>"$LOG_FILE" 2>&1 || true
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      ssh-keygen -t ed25519 -N '' -C "$(hostname)-bootstrap" -f "$HOME/.ssh/id_ed25519" \
        >>"$LOG_FILE" 2>&1 || die "ssh-keygen failed"
    fi
    gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$(hostname) bootstrap" \
      >>"$LOG_FILE" 2>&1 || log "WARN: could not upload SSH key; add it manually"
  fi
  log "github access ready"
}
