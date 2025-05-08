# shellcheck shell=sh
# Shared PATH and tool initialization, sourced by both bash and zsh from
# their interactive rc files. Keep POSIX-compatible: no [[ ]], no zsh-only
# expansions.

# Resolved CLAWBOT for this machine (baked by chezmoi). Sourced first so the rest
# of the environment — and any process started from a login shell — sees the
# resolved value regardless of what the ambient env was set to.
[ -r "$HOME/.config/shell/clawbot.env" ] && . "$HOME/.config/shell/clawbot.env"

# GUI is a live property (is a display attached now?), not baked: detect it each
# time so it tracks reality. An explicit GUI in the environment wins.
case "${GUI:-}" in
  1|true|yes) GUI=true ;;
  0|false|no) GUI=false ;;
  *) if [ "$(uname)" = Darwin ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then GUI=true; else GUI=false; fi ;;
esac
export GUI

# Agents run non-interactively: never block on an editor/pager waiting for a key.
# Only forced on clawbots, so a human's own EDITOR/PAGER on a personal box is kept.
if [ -n "${CLAWBOT:-}" ]; then
  export EDITOR="${EDITOR:-vi}"
  export PAGER="${PAGER:-cat}"
  export GIT_PAGER="${GIT_PAGER:-cat}"
  export AWS_PAGER="${AWS_PAGER:-}"   # empty = no pager (overrides ~/.aws/config cli_pager)
fi

export CDK_DISABLE_CLI_TELEMETRY=true

export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

if [ -d "/opt/homebrew/bin" ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -d "/home/linuxbrew/.linuxbrew/bin" ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

export KREW_ROOT="$HOME/.krew"
if [ -d "$KREW_ROOT/bin" ]; then
  export PATH="$KREW_ROOT/bin:$PATH"
fi

# opencode's Linux installer drops the binary here (macOS uses brew, on the normal PATH).
if [ -d "$HOME/.opencode/bin" ]; then
  export PATH="$HOME/.opencode/bin:$PATH"
fi

export JETBRAINS_DIR="$HOME/Library/Application Support/JetBrains"
if [ -d "$JETBRAINS_DIR/Toolbox/scripts" ]; then
  export PATH="$PATH:$JETBRAINS_DIR/Toolbox/scripts"
fi

# mise (version manager; used for Java/JVM and other runtimes): activate so
# installed tools are on PATH and env (JAVA_HOME, …) is set. Activation is
# shell-specific (bash/zsh only); no-op until mise is installed.
if command -v mise >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(mise activate zsh)"
  elif [ -n "${BASH_VERSION:-}" ]; then
    eval "$(mise activate bash)"
  fi
fi

# zoxide needs explicit init for bash; zsh gets it via the OMZ zoxide plugin.
if [ -n "${BASH_VERSION:-}" ] && command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi

# Optional private overlay: symlinked into private/ when that sibling clone is
# present (set up by install.sh). Holds per-machine values (AWS_DEFAULT_REGION
# etc.) that don't belong in the public repo. Dangling symlinks are silently
# skipped.
[ -r "$HOME/.config/shell/env.local.sh" ] && . "$HOME/.config/shell/env.local.sh"
