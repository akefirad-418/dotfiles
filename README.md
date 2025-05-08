# My Dotfiles

[chezmoi](https://www.chezmoi.io/) dotfiles that serve double duty: a full macOS
home-directory setup for a human, **and** a lean config for *clawbots* (autonomous
agents — usually headless Linux). Two switches decide which layer a machine gets; 
the personal/desktop layer is gated off on clawbots.

## Bootstrap

```sh
git clone https://github.com/akefirad/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

`install.sh` installs chezmoi into `~/.local/bin` if absent, seeds git identity,
then runs `chezmoi init --apply`. Idempotent and non-interactive-safe.

On macOS, if the Command Line Developer Tools aren't installed, `git clone` will
trigger their install — finish it, then re-run.

## Switches

**Identity/policy switches** (`CLAWBOT`, `INSTALL_*`) are resolved **once** at
`chezmoi init` and baked into `~/.config/chezmoi/chezmoi.yaml`; `apply`/`update`
reuse the baked values. Precedence: **previously-persisted → outside env (first
init) → default** — set once at provisioning, stable thereafter. (Persisted-first
is deliberate: chezmoi re-injects `scriptEnv` into the environment when it runs, so
on a re-init a fresh `CLAWBOT=…` can't override the baked value.) To **change** an
`INSTALL_*` switch on an already-applied box, just **re-run `install.sh`** — pass the env
(`INSTALL_CLAUDE_CODE=1 ~/.dotfiles/install.sh`) or answer its prompt; it reconciles the
value and clears chezmoi's run-state cache so the installer re-fires (asking first), the
same way on Linux and macOS. For the other switches (`CLAWBOT`, `SEED_*`), **set** the key
directly in `~/.config/chezmoi/chezmoi.yaml` (*deleting* it re-resolves to the default, not
your new value) and re-run `chezmoi init`.

**`GUI` is different** — a live property of the machine (is a display attached
*now*?), so it's **not** baked. It's detected at runtime, re-evaluated on every
apply, by `env.sh` (shells) and the gui-gated scripts. Override a single run with
`GUI=0|1 chezmoi apply`.

| env var | persisted? | values | default |
|---|---|---|---|
| `CLAWBOT` | yes (`.clawbot`) | `auto` → hostname; any other string → used verbatim; unset/empty → not a clawbot | `""` |
| `INSTALL_CLAUDE_CODE` | yes (`.install.claudeCode`) | `0` skips Claude Code | `1` |
| `INSTALL_OPENCODE` | yes (`.install.opencode`) | `0` skips opencode | `1` |
| `INSTALL_HERMES` | yes (`.install.hermes`) | `1` installs Hermes (Linux; macOS is a manual `.dmg`) | `0` |
| `GUI` | no (runtime) | `1`/`true`/`yes` or `0`/`false`/`no`; else macOS→true, Linux→true iff `$DISPLAY`/`$WAYLAND_DISPLAY` is set | OS-derived |

There is no seed switch: a clawbot is by definition behind the gateway, so it always
gets **fake** placeholder creds for gateway injection (see
[Clawbots](#clawbots--the-egress-firewall)) — seeded per tool, only where that tool is
installed (`.clawbot` ∧ `INSTALL_*`). A human box is never seeded.

`.clawbot` (agent vs. human) and GUI (has a desktop) are **orthogonal** — a
macOS clawbot can have a GUI yet must not get personal apps:

|         | GUI                 | headless          |
|---------|---------------------|-------------------|
| human   | full personal setup | (rare)            |
| clawbot | minimal + chrome/vscode | minimal CLI only |

Provision a headless Linux clawbot: `CLAWBOT=auto ~/.dotfiles/install.sh`.

### How the values reach things

One resolution, three deliveries:

1. **chezmoi templates** (`.chezmoiignore.tmpl`, `.chezmoiexternals/`) read
   `.clawbot` from config `data`.
2. **scripts** read `$CLAWBOT`/`$INSTALL_*` — injected via chezmoi `scriptEnv`
   (scripts stay native `.sh`, no templating, so they shellcheck). `$GUI` they
   detect themselves at runtime.
3. **login shells** source `~/.config/shell/clawbot.env` (generated) via
   `env.sh`, so a booted box shows the resolved `CLAWBOT` even if the ambient env
   passed something else (e.g. `CLAWBOT=auto` surfaces as the hostname). `env.sh`
   also detects and exports a live `GUI`.

A boot service started outside a shell must source `~/.config/shell/env.sh`
itself to see the resolved values.

## What's gated

| layer | applied when |
|---|---|
| headless essentials (tier-1 CLI tools, git/shell env, apt deps, AWS CLI) | always |
| Claude Code / opencode | always, unless `INSTALL_CLAUDE_CODE=0` / `INSTALL_OPENCODE=0` |
| Hermes (Linux) | only when `INSTALL_HERMES=1` (off by default) |
| personal CLI niceties (oh-my-zsh, p10k, fzf, aliases, full tool set) | `not .clawbot` |
| personal desktop apps & tweaks (Homebrew casks/mas, terminals, Karabiner, Spotlight) | `not .clawbot` **and** `.gui` |
| agent GUI apps (google-chrome, visual-studio-code) | `.clawbot` **and** `.gui` |

## Tool install strategy (3 tiers)

1. **Release binary** → `~/.local/bin`, declared in
   [`home/.chezmoiexternals/shared.yaml.tmpl`](home/.chezmoiexternals/shared.yaml.tmpl).
   Clawbot minimal set (always): `rg fd jq gh uv uvx mise`. Personal extras
   (`bun bat fzf k9s helm …`) are gated `not .clawbot`; `btop`/`eza` are tier-1 on
   **Linux only** (macOS has no release binary for them, so it uses brew there).
2. **Package manager** → per-OS scripts in [`home/.chezmoiscripts/`](home/.chezmoiscripts/):
   macOS `brew bundle` (incl. the `claude-code` cask + `opencode` formula, all roles); personal
   Linux uses **apt** for distro tools (`git-delta httpie tree shellcheck`). No Linuxbrew.
3. **Vendor installer** → AWS CLI v2 (both OSes); on **Linux**, Claude Code (`~/.local/bin`) and opencode (`~/.opencode/bin`), sudo-free, plus Hermes (opt-in, `INSTALL_HERMES=1`; macOS is a manual `.dmg`).

Language runtimes (Node, Java, …) are not provisioned — install and version them yourself (`mise` is on PATH for that).

## Clawbots & the egress firewall

A *clawbot* provisions itself **from this repo**: its container image runs
`git clone …/dotfiles && CLAWBOT=1 install.sh`, landing exactly the headless
layer above — no personal apps, optional tools off unless asked for. "What a clawbot
gets" is just this repo with `.clawbot` set.

The network cage those agents run inside lives in [`clawtilla/`](clawtilla) (a
submodule): a Docker Compose stack on top of
[clawpatrol](https://github.com/denoland/clawpatrol) that gives each agent a
single, audited egress chokepoint. The dotfiles are the *provisioning* half;
clawtilla is the *containment* half. They meet at **credential injection**:

- On a clawbot (which always runs behind the gateway) chezmoi seeds **fake**
  placeholder creds into the agent's home, per installed tool: signatureless
  Codex/ChatGPT tokens for Hermes and OpenCode
  ([`home/dot_hermes/`](home/dot_hermes),
  [`home/dot_local/share/opencode/`](home/dot_local/share/opencode); a far-future
  `exp` skips device-login), and a Telegram bot-token placeholder for Hermes
  (`~/.hermes/.env`). Each is gated on `.clawbot` ∧ the tool's `INSTALL_*`, so a tool
  you didn't install is never seeded and a human box is never touched.
- The clawtilla gateway brings those upstreams into scope, terminates TLS, and
  swaps the placeholder for the **real** secret at the wire — so the agent never
  holds a usable secret. See [`clawtilla/README.md`](clawtilla/README.md).

## Private overlay (optional)

Private dotfiles live in a separate repo cloned into `private/` (gitignored,
*not* a submodule). `install.sh` clones it first: on a TTY it prompts for a token
(hidden); non-interactively it runs only if `PRIVATE_GH_TOKEN` is set. The URL is
derived from this repo's `origin` (repo name prefixed with a dot). The token is
used only in-process — never written to disk, the clone's config, the URL, shell
history, or `ps`.

Once cloned, the public tree *reaches into* it through chezmoi `symlink_*.tmpl`
entries that point at `private/home/…` — e.g. `~/.claude/settings.json`,
`~/.config/shell/env.local.sh`, and `~/.docker/config.json` become live symlinks
into the overlay. With no overlay present those symlinks dangle and are silently
skipped (`env.sh` guards its source; the rest stay inert), so the public repo
always stands on its own. (Provisioning a clawbot is non-interactive with no
token, so a clawbot never gets the overlay.)

## Layout

```
install.sh                         bootstrap (chezmoi + private clone + init --apply)
update.py                          bump pinned tool versions in .chezmoidata.yaml
home/                              chezmoi source root (.chezmoiroot points here)
  .chezmoi.yaml.tmpl               switch resolution + identity + archive-name matrix
  .chezmoidata.yaml                tool registry (repo + pinned version)
  .chezmoiignore.tmpl              per-role + per-OS gating
  .chezmoiexternals/shared.yaml.tmpl   tier-1 downloads (minimal always; extras gated)
  .chezmoiscripts/
    run_after_90-verify.sh                      post-apply check
    darwin/  00-install 01-packages 02-apps after_00-configure
    linux/   00-install 01-packages 02-apps 03-awscli 04-claude-code 05-opencode 06-hermes after_00-configure
  modify_dot_bashrc, modify_dot_profile   managed block sourcing the files below
  dot_config/shell/   env.sh  bashrc.sh  aliases.sh  functions.sh  clawbot.env.tmpl
  dot_config/git/{config.tmpl,ignore}
  dot_hermes/, dot_local/share/opencode/   fake-cred seeders (gateway injection)
  **/symlink_*.tmpl                live symlinks into the private overlay
clawtilla/                         submodule: the egress firewall the clawbots run in
oss/hermes-agent/                  submodule: Hermes agent upstream (opt-in install)
private/                           optional private overlay — gitignored sibling clone
test/                              Docker-based provisioning tests (run.sh)
.devcontainer/                     Dev Container that bootstraps via install.sh
```

## Day-to-day

```sh
chezmoi apply            # apply pending changes
chezmoi apply -nv        # dry-run, verbose
chezmoi update           # git pull + apply
chezmoi -R apply         # force-refresh externals (re-download)
chezmoi managed          # list managed paths
```

## Testing

```sh
test/run.sh verify       # build Ubuntu image, run install.sh as a clawbot, assert layout
test/run.sh reconfigure  # re-run install.sh with INSTALL_CLAUDE_CODE=1; assert it installs
test/run.sh bash         # interactive shell in the built image
```

## Known gaps / TODO

- **Checksums.** Externals have no `checksum.sha256` yet — downloads are trusted.
