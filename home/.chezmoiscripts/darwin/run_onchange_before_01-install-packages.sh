#!/usr/bin/env bash
# macOS packages via `brew bundle`, selected by role/environment ($CLAWBOT from
# chezmoi scriptEnv; $GUI detected at runtime):
#   personal (no clawbot)        -> formulae always; casks + mas only with a GUI
#   GUI clawbot                  -> google-chrome + visual-studio-code
#   headless clawbot             -> (optional tools only)
# Claude Code (cask) + opencode (formula) install in every role unless their
# INSTALL_* switch is 0 — CLIs a clawbot needs, so not GUI-gated. No --cleanup.
set -euo pipefail

# GUI is environmental — detect at runtime (not baked), re-evaluated each apply.
# An explicit GUI in the env wins. chezmoi passes the apply-time env to scripts.
case "${GUI:-}" in
  1|true|yes) GUI=true ;;
  0|false|no) GUI=false ;;
  *) if [ "$(uname)" = Darwin ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then GUI=true; else GUI=false; fi ;;
esac

# 00 put brew on PATH, but each chezmoi script runs in a fresh process.
if ! command -v brew >/dev/null 2>&1; then
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi
command -v brew >/dev/null 2>&1 || { echo "❌ Homebrew not found (run 00-install first)." >&2; exit 1; }

formulae=(
  awscli
  bash
  biome
  btop
  cloc
  cloudflared
  curl
  displayplacer
  dockutil
  eza
  ffmpeg
  git
  git-delta
  gnupg
  go
  golangci-lint
  httpie
  jj
  jless
  kubectx
  mas
  mise
  nmap
  pnpm
  qemu
  shellcheck
  thefuck
  tlrc
  tree
  wget
  xz
  yt-dlp
)

casks=(
  1password
  brave-browser
  cursor
  docker-desktop
  font-menlo-for-powerline
  font-meslo-for-powerlevel10k
  fork
  freelens
  ghostty
  google-chrome
  hammerspoon
  jetbrains-toolbox
  lapce
  meetingbar
  notion
  orka-desktop
  raycast
  slack
  stolendata-mpv
  telegram
  the-unarchiver
  visual-studio-code
  vlc
  voiceink
  wezterm
  whatsapp
  zoom
)

mas_apps=(
  "AdGuard for Safari: 1440147259"
  "GitHub Refined:     1519867270"
  "Step Two:           1448916662"
)

# Build the Brewfile for this machine.
brewfile() {
  local f c
  # Optional tools (Claude Code, opencode) on every macOS role unless toggled off — a clawbot needs them, so
  # they're NOT GUI-gated. Linux installs these via vendor scripts (linux/04, /05).
  [ "${INSTALL_CLAUDE_CODE:-1}" != "0" ] && echo 'cask "claude-code"'
  [ "${INSTALL_OPENCODE:-1}" != "0" ]    && echo 'brew "opencode"'
  if [ -z "${CLAWBOT:-}" ]; then
    for f in "${formulae[@]}"; do echo "brew \"$f\""; done
    if [ "$GUI" = true ]; then
      for c in "${casks[@]}"; do echo "cask \"$c\""; done
      if defaults read MobileMeAccounts Accounts &>/dev/null; then
        local e name id
        for e in "${mas_apps[@]}"; do
          name="${e%%:*}"; id="${e##*:}"
          echo "mas \"$name\", id: $id"
        done
      else
        echo "# (no Apple account — skipping Mac App Store apps)" >&2
      fi
    fi
  elif [ "$GUI" = true ]; then
    echo "cask \"google-chrome\""
    echo "cask \"visual-studio-code\""
  fi
}

bf="$(brewfile)"
if [ -z "$bf" ]; then
  echo "packages: headless clawbot — nothing to install."
  exit 0
fi

printf '%s\n' "$bf" | brew bundle --file=/dev/stdin
