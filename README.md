# My Dotfiles

Minimal [chezmoi](https://www.chezmoi.io/) dotfiles for a coding agent on Linux
and macOS. Wires a small set of CLI tools onto `PATH`, a bash env, and git
config. No human-desktop cruft (no prompt themes, terminals, window managers).

## Bootstrap

```sh
git clone https://github.com/akefirad-418/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

`install.sh` installs chezmoi into `~/.local/bin` if absent, seeds git identity
(from the repo's git remote/history, or `$GIT_AUTHOR_NAME`/`$GIT_AUTHOR_EMAIL`,
or interactive prompt), then runs `chezmoi init --apply`. It is idempotent and
non-interactive-safe (CI/containers take derived defaults silently).

Already have chezmoi? `chezmoi init --apply --source=$PWD` from the clone.

## Tool install strategy (3 tiers, in preference order)

1. **Release binary** — download straight from a GitHub release into
   `~/.local/bin`. Declared in [`home/.chezmoiexternals/shared.yaml.tmpl`](home/.chezmoiexternals/shared.yaml.tmpl).
   This is the default; use it whenever upstream ships a usable binary.
2. **Package manager** — per-OS scripts under
   [`home/.chezmoiscripts/`](home/.chezmoiscripts/): macOS bootstraps Homebrew
   ([darwin/00-install](home/.chezmoiscripts/darwin/run_onchange_before_00-install.sh))
   then installs casks via `brew bundle`
   ([darwin/01-install-packages](home/.chezmoiscripts/darwin/run_onchange_before_01-install-packages.sh));
   Linux installs base deps via apt
   ([linux/00-install](home/.chezmoiscripts/linux/run_onchange_before_00-install.sh)).
3. **Vendor install script** — official installer into `~/.local` (sudo-free),
   in a per-OS `02-install-*` script. Used for AWS CLI v2
   ([linux](home/.chezmoiscripts/linux/run_onchange_before_02-install-awscli.sh),
   [darwin](home/.chezmoiscripts/darwin/run_onchange_before_02-install-awscli.sh)),
   which ships no usable release binary or v2 apt package. Version pinned inside
   the script (bump → run_onchange re-runs).

macOS GUI apps shipped as a `.dmg` from a release (no usable binary, prefer the
release over a cask) are installed by
[darwin/03-install-dmg-apps](home/.chezmoiscripts/darwin/run_onchange_before_03-install-dmg-apps.sh):
download → `hdiutil` mount → copy the `.app` into `~/Applications` → detach.
Version-pinned + idempotent via the bundle's `CFBundleShortVersionString`.

Seeded tools: tier 1 — `rg` (ripgrep), `fd`, `jq`, `gh`, `uv`+`uvx`, `fnm`; tier 3 — `aws` (CLI v2).
macOS casks (tier 2): `google-chrome`, `claude-code`, `cursor`, `voiceink`. macOS dmg apps: none configured (the dmg mechanism stays available).

## Layout

```
.chezmoiroot                       -> source state lives in home/
.chezmoiversion                    minimum chezmoi version
install.sh                         bootstrap (chezmoi + init --apply)
home/
  .chezmoi.yaml.tmpl               identity prompts + OS/arch release-name matrix
  .chezmoidata.yaml                tool registry: repo + pinned version
  .chezmoiignore.tmpl              per-OS gating: selects .chezmoiscripts/<os>/
  .chezmoiexternals/shared.yaml.tmpl   tier-1 release-binary downloads
  .chezmoiscripts/                 plain per-OS shell (no templating); the
    darwin/                          matching OS's dir is kept, the other
      run_onchange_before_00-install.sh           ensure Homebrew
      run_onchange_before_01-install-packages.sh  brew bundle casks
      run_onchange_before_02-install-awscli.sh    AWS CLI v2 (pkg, sudo-free)
      run_onchange_before_03-install-dmg-apps.sh  .dmg apps -> ~/Applications
    linux/
      run_onchange_before_00-install.sh           apt base deps (incl. unzip)
      run_onchange_before_02-install-awscli.sh    AWS CLI v2 (installer -i/-b)
    run_after_90-verify.sh         shared, OS-agnostic post-apply check
  modify_dot_bashrc, modify_dot_profile   ensure a marker-delimited managed
                                          block sourcing the files below;
                                          preserve any other content
  dot_config/shell/env.sh          PATH (~/.local/bin) + EDITOR/PAGER (sh)
  dot_config/shell/bashrc.sh       bash interactive niceties
  dot_config/git/{config.tmpl,ignore}
```

## Add a tool (tier 1)

1. Add `repo` + `version` to [`home/.chezmoidata.yaml`](home/.chezmoidata.yaml).
2. If the release asset name needs OS/arch logic, add an `archiveName*`
   fragment to [`home/.chezmoi.yaml.tmpl`](home/.chezmoi.yaml.tmpl).
3. Add an entry to [`home/.chezmoiexternals/shared.yaml.tmpl`](home/.chezmoiexternals/shared.yaml.tmpl)
   (`type: file` for a bare binary, `type: archive-file` + `path:` to pull one
   binary out of a tarball/zip).
4. `chezmoi apply`. Inspect first with `chezmoi apply --dry-run --verbose`.

## Day-to-day

```sh
chezmoi apply            # apply pending changes
chezmoi apply -nv        # dry-run, verbose
chezmoi update           # git pull + apply
chezmoi -R apply         # force-refresh externals (re-download)
chezmoi managed          # list managed paths
```

## Known gaps / TODO

- **Checksums.** Externals have no `checksum.sha256` yet — downloads are
  trusted blindly. Pin them before relying on this in production.
- **Non-interactive `bash -c`.** Such shells read neither `.bashrc` nor
  `.profile`. If your agent invokes tools via `bash -c`, set `BASH_ENV` to a
  file that sources `~/.config/shell/env.sh`, or call tools by absolute path.
- `~/.local/bin` must be on `PATH`; the verify script warns if it isn't.
