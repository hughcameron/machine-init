#!/usr/bin/env bash
#
# Rehearse the bootstrap on a throwaway macOS VM, with a person at its console.
#
#   CONFIG_REPO=https://github.com/<owner>/<repo>.git test/macos-vm.sh [image]
#
# The interactive steps (sudo for Homebrew, the 1Password sign-in, the GitHub device code)
# are exactly what an unattended test cannot reach, and on a real machine they are where
# the bootstrap has failed. This boots a fresh VM from a Tart base image, opens its window
# so the 1Password app can be signed in there, and runs the bootstrap over SSH in this
# terminal so every prompt shows here. The VM is deleted at the end unless KEEP_VM is set.
#
# Needs Tart (brew install cirruslabs/cli/tart) on Apple silicon, and room for the image:
# a macOS base image is tens of gigabytes. Cirrus Labs' base images log in as admin/admin.
#
# Environment:
#   CONFIG_REPO   required: the private chezmoi repo, as for install.sh
#   VM_NAME       default machine-init-rehearsal
#   KEEP_VM       keep the VM afterwards (set to anything)
#   INSTALL_URL   default the published install.sh; point at a branch to test a change

set -euo pipefail

IMAGE="${1:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
VM_NAME="${VM_NAME:-machine-init-rehearsal}"
INSTALL_URL="${INSTALL_URL:-https://raw.githubusercontent.com/hughcameron/machine-init/main/install.sh}"
: "${CONFIG_REPO:?set CONFIG_REPO to your private chezmoi repo}"

log() { printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }

command -v tart >/dev/null || { log "needs Tart: brew install cirruslabs/cli/tart"; exit 1; }
[ "$(uname -m)" = arm64 ] || { log "Tart runs macOS VMs on Apple silicon only"; exit 1; }

# shellcheck disable=SC2329  # run by the EXIT trap
cleanup() {
  tart stop "$VM_NAME" >/dev/null 2>&1 || true
  if [ -z "${KEEP_VM:-}" ]; then
    tart delete "$VM_NAME" >/dev/null 2>&1 || true
    log "deleted VM $VM_NAME"
  else
    log "kept VM $VM_NAME (tart delete $VM_NAME to remove it)"
  fi
}

if tart list --quiet 2>/dev/null | grep -qx "$VM_NAME"; then
  log "VM $VM_NAME already exists; delete it or set VM_NAME"
  exit 1
fi

log "cloning $IMAGE as $VM_NAME (the first pull downloads the whole image)"
tart clone "$IMAGE" "$VM_NAME"
trap cleanup EXIT

log "starting $VM_NAME with its window open"
tart run "$VM_NAME" >/dev/null 2>&1 &

ip=""
for _ in $(seq 1 60); do
  ip="$(tart ip "$VM_NAME" 2>/dev/null || true)"
  [ -n "$ip" ] && break
  sleep 2
done
[ -n "$ip" ] || { log "the VM never reported an IP address"; exit 1; }
log "VM is at $ip; waiting for SSH"

SSH=(ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "admin@$ip")
for _ in $(seq 1 30); do
  "${SSH[@]}" true 2>/dev/null && break
  sleep 2
done

log "running the bootstrap in the VM; answer its prompts here (the VM's password is admin)"
log "for the 1Password step, sign in to the app in the VM's window, or press Enter to type it here"
status=0
"${SSH[@]}" "CONFIG_REPO='$CONFIG_REPO' bash <(curl -fsSL '$INSTALL_URL')" || status=$?
log "bootstrap exited with status $status"
exit "$status"
