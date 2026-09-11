# machine-init

Brings a bare machine to the point where [chezmoi](https://chezmoi.io) can take over, then gets out of the way.

This repo is public so that a machine with nothing on it — no SSH key, no package manager, no credentials — can fetch one script over plain HTTPS and start. It deliberately contains no configuration of its own. Everything that describes a machine lives in a separate private chezmoi repo, and this script's only job is to install enough tooling to reach it.

```sh
curl -fsSL https://raw.githubusercontent.com/hughcameron/machine-init/main/install.sh | bash
```

## What it does

Seven steps, in order, each idempotent: system prerequisites for the detected package manager, Homebrew, then `chezmoi`, `age` and `gh` from Homebrew, then the 1Password CLI, then the age identity, then GitHub access, then `chezmoi init --apply` against the private repo.

It stops at that handoff. Installing the full Brewfile, yazi plugins and project repos is a handful of commands you run afterwards with a working shell — which is a better place to be than halfway through a long unattended script on a machine that has no tooling to debug it. The script prints those remaining commands when it finishes.

## The two credentials

A bootstrap needs to solve a chicken-and-egg: the private repo holds the secrets, but you need a credential to reach the private repo, and another to decrypt what's inside it.

The **age identity** comes from 1Password. It is read with `op read` straight into `~/.config/chezmoi/age/keys.txt` with mode 0600, is never written to stdout or to the log, and an existing key is never overwritten.

**GitHub access** comes from `gh auth login` device flow — you get a code and enter it on another device. No long-lived GitHub token is stored in a vault, so there's nothing standing that could be lifted later. If no working SSH key is present, the script generates one and registers it.

## Headless machines

`op` normally leans on the desktop app for biometric unlock, which a headless box doesn't have. Two options.

Interactive sign-in works fine — `op account add` asks for email, Secret Key and password, and the script does this automatically when no account is configured. This is the default, and for a machine you provision once it is the right trade.

A [service account](https://www.1password.dev/service-accounts) removes the prompt entirely by authenticating with a bearer token in `OP_SERVICE_ACCOUNT_TOKEN`. Two properties make it safe to scope: a service account **cannot** be granted access to your Personal, Private, Employee or default Shared vault — only custom vaults you name — and its vault access is immutable after creation, so the blast radius is fixed the moment you make it.

The trap is worth stating plainly. A bootstrap token that lives on the machine it bootstraps is not a secret: anyone with the disk has both the token and the encrypted files it unlocks, so the encryption protects nothing. Put the token in the provisioning seed, use it once, and let it expire:

```sh
op service-account create "bootstrap" --vault "Machines:read_items" --expires-in 24h
```

The token is shown once at creation and never again, so store it in 1Password itself the moment you make one. The script warns whenever it sees the token set, with a reminder to confirm it hasn't survived into shell rc files, systemd units, or the seed left on disk.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `CONFIG_REPO` | `git@github.com:hughcameron/config.git` | private chezmoi source |
| `OP_AGE_ITEM` | `op://Machines/chezmoi-age-key/keys.txt` | where the age identity lives |
| `AGE_KEY_PATH` | `~/.config/chezmoi/age/keys.txt` | where to write it |
| `OP_SERVICE_ACCOUNT_TOKEN` | unset | non-interactive 1Password auth |
| `MACHINE_INIT_ASSUME_YES` | unset | skip confirmation prompts |
| `OP_VERSION` | `2.39.0` | pinned `op` version for the Linux binary |
| `LOG_FILE` | `$TMPDIR/machine-init.log` | timestamped run log |

## Platforms

macOS and Linux, on `arm64` or `amd64`. Linux prerequisites go through whichever of `apt`, `pacman`, `dnf` or `zypper` is present, and everything above that layer is Homebrew, so an Arch-based machine needs no new branch. The 1Password CLI is a Homebrew cask on macOS but isn't in Homebrew on Linux at all, so there the script takes the official static binary — which is also what keeps it distro-agnostic.
