# shellcheck shell=bash
# Hand the machine to chezmoi: clone the private repo and apply it.

chezmoi_handoff() {
  step "chezmoi handoff"

  # With no config file, `chezmoi source-path` still exits 0 and prints the
  # default directory, so its exit status says nothing. Look for the clone.
  local src cloned want
  src="$(chezmoi source-path 2>/dev/null || true)"
  if [ -n "$src" ] && [ -d "$src/.git" ]; then
    log "chezmoi source already at $src; applying"
    chezmoi apply || die "chezmoi apply failed"
    return 0
  fi

  # `chezmoi init --apply` clones into the default directory before it reads the
  # repo's config template, so a template that sets sourceDir leaves the clone
  # where the new config no longer looks, and the apply fails. Clone and write
  # the config first, move the clone to where the config says, then apply.
  cloned="$src"
  log "initialising chezmoi from $CONFIG_REPO"
  chezmoi init "$CONFIG_REPO" || die "chezmoi init failed"
  want="$(chezmoi source-path)"
  if [ "$want" != "$cloned" ]; then
    if [ -e "$want" ]; then
      log "keeping the source already at $want; the clone at $cloned is unused"
    else
      if ! { mkdir -p "$(dirname "$want")" && mv "$cloned" "$want"; }; then
        die "could not move the source from $cloned to $want"
      fi
      log "moved the source to $want, where its config puts it"
    fi
  fi
  chezmoi apply || die "chezmoi apply failed"
}
