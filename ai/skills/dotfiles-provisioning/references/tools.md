# Tools: tier mechanics and examples

How tool installs are wired in this repo. Read this before editing, then copy the
closest existing entry rather than writing from scratch. Source of truth is the
README's **"Tool install strategy (3 tiers)"** section plus the files below.

The tiers are numbered by preference: **tier 1 → tier 2 → tier 3 → root**. Tier 3
(a bespoke vendor installer) is the fallback used only when no clean package
exists — e.g. the AWS CLI script notes *"There is no v2 apt package; AWS ships an
official installer."*

## Tier 1 — release binary → `~/.local/bin`

A single static binary published as a release asset, downloaded straight to
`~/.local/bin` (no root). Three coordinated files:

1. **`home/.chezmoidata.yaml`** — the registry: pinned `repo` + `version`.
   ```yaml
   ripgrep:
     repo: https://github.com/BurntSushi/ripgrep
     version: 15.1.0
   ```
2. **`home/.chezmoiexternals/shared.yaml.tmpl`** — the download entry. Pick the
   chezmoi external `type`:
   - `file` — a bare binary (e.g. `jq`, `yq`, `mise`, `fx`);
   - `archive-file` — pull one path out of a tar/zip (most tools);
   - `git-repo` — a checkout (oh-my-zsh, plugins).
   ```yaml
   .local/bin/rg:
     type: archive-file
     url: {{ .tools.ripgrep.repo }}/releases/download/{{ .tools.ripgrep.version }}/ripgrep-{{ .tools.ripgrep.version }}-{{ .archiveNameRipgrep }}.tar.gz
     executable: true
     path: ripgrep-{{ .tools.ripgrep.version }}-{{ .archiveNameRipgrep }}/rg
   ```
3. **`home/.chezmoi.yaml.tmpl`** — the `archiveName*` matrix: map this tool's
   per-OS/arch release-asset naming. Match the upstream's convention (GoReleaser
   `Linux_x86_64`, Rust target triples `x86_64-unknown-linux-gnu`, etc.). Add one
   `archiveName<Tool>` line, modeled on an existing tool that ships the same way.

**Gating** lives in `shared.yaml.tmpl`: the lean "always" set is at the top; the
`{{ if not .clawbot }}` block holds personal-only extras; a nested
`{{ if eq .chezmoi.os "linux" }}` covers Linux-only tier-1 tools (e.g. `btop`,
`eza`, which have no macOS release binary). Put your tool where its audience is.

**Version bumps:** `update.py` queries GitHub for the latest release and rewrites
the `version` fields in `.chezmoidata.yaml` (`./update.py --dry-run` to preview).

## Tier 2 — package manager

A distro/brew package, via per-OS scripts in `home/.chezmoiscripts/`:
- **macOS:** `darwin/run_onchange_before_01-install-packages.sh` builds a Brewfile
  (formulae always; casks + mas only with a GUI) and runs `brew bundle`. Add your
  formula/cask to the right array.
- **Linux:** `linux/run_onchange_before_01-install-packages.sh` uses `apt` — but
  it is **personal-only**: it exits early when `$CLAWBOT` is set. Base prerequisites
  every box needs go in `linux/run_onchange_before_00-install.sh` instead.

**Note on the existing Linux apt script:** `01-install-packages.sh` is gated
personal-only (it exits when `$CLAWBOT` is set) simply because the tools listed in
it are personal — that's a gating choice for those specific tools, *not* a
limitation. A clawbot has root and can use `apt` fine. If you add a tier-2 tool a
clawbot needs, just don't gate it personal-only.

## Tier 3 — vendor installer

An official installer that supports a sudo-free install into a user prefix, when
neither a release binary nor a package fits. Models:
`linux/run_onchange_before_03-install-awscli.sh` (AWS CLI v2 via `-i`/`-b` into
`~/.local`) and the shared `run_onchange_before_04-install-claude-code.sh`
(both OSes, at the `.chezmoiscripts` root). Conventions to copy:

- `#!/usr/bin/env bash`, `set -euo pipefail`, **no chezmoi templating** (stays a
  native `.sh` so it passes `shellcheck`; switches arrive via `scriptEnv` as env
  vars like `$CLAWBOT`/`$INSTALL_*`).
- **Pin the version** in the script; bumping it changes the file hash and
  re-triggers `run_onchange`.
- **Install-if-missing / idempotent:** no-op when the pinned version is present.
- Install into `~/.local` (sudo-free); fall back to root only as a last resort
  (see "Root / system installs" below).
- Note: `run_onchange_` keys on the script's *contents* hash. Flipping only a
  `scriptEnv` flag won't re-run it; force with
  `chezmoi state delete-bucket --bucket=entryState && chezmoi apply`.

## Root / system installs (sudo)

Prefer a sudo-free tier above; only touch the system when nothing else fits. When
a script *must* run a privileged command (`apt-get`, writing under `/usr`, `/etc`),
**never assume root** — copy the guard idiom every apt script here already uses. It
uses `sudo` only when not already root, and only when sudo is **passwordless**
(`sudo -n`), so it never hangs on an interactive password prompt (there's no human
on a clawbot):

```sh
if [ "$(id -u)" -eq 0 ]; then sudo=""
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo="sudo"
else echo "❌ need root or passwordless sudo." >&2; exit 1; fi
$sudo apt-get update -qq
$sudo apt-get install -y --no-install-recommends "${pkgs[@]}"
```

Then run every privileged command through `$sudo` (empty when already root). Pick
the no-privilege branch by how essential the tool is:
- **Base prerequisite the box can't work without** → hard-fail (`exit 1`), like
  `00-install.sh` / `01-install-packages.sh`.
- **Optional / nice-to-have** → warn and skip (`exit 0`), like `02-install-apps.sh`
  and the hermes ffmpeg step (`sudo="-"` sentinel → skip that piece, continue).

If *you're* the agent running the apply and the box has neither root nor
passwordless sudo, don't try to work around it — the install can't complete here.
Open the PR and hand the privileged run to the owner (SKILL.md Step 4).

## Vendored source (reference / building)

An open-source tool's source can also be added as a git **submodule** under `oss/`
(e.g. `oss/chezmoi`, `oss/hermes-agent`) — for reference or building from source.
This is separate from the three install tiers; it doesn't put anything on PATH.

## Worked examples

- **`rg` (ripgrep) — tier 1.** The three-file pattern above. Ships `archive-file`
  tarballs with Rust target-triple names; arm64 Linux uses `gnu`, x86_64 Linux uses
  `musl` (see the `archiveNameRipgrep` line — a tool-specific quirk worth checking
  per upstream).
- **`aws` (AWS CLI v2) — tier 3.** No v2 apt package, so a vendor installer:
  `03-install-awscli.sh` downloads the official zip and runs `aws/install -i
  ~/.local/aws-cli -b ~/.local/bin`, with `--update` when already present. Pinned
  `version`, idempotent version check, `set -euo pipefail`, no templating.
