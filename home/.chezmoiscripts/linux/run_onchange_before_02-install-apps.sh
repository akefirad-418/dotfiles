#!/usr/bin/env bash
# GUI-capable Linux clawbot only: a browser (for headed automation) + VS Code.
# Headless clawbots and personal machines skip this. Rare path — non-fatal so a
# missing apt/repo doesn't abort apply. $CLAWBOT from chezmoi scriptEnv; $GUI
# detected at runtime (a display attached now?).
set -uo pipefail

# GUI is environmental — detect at runtime (not baked). Explicit GUI in env wins.
case "${GUI:-}" in
  1|true|yes) GUI=true ;;
  0|false|no) GUI=false ;;
  *) if [ "$(uname)" = Darwin ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then GUI=true; else GUI=false; fi ;;
esac

if [ -z "${CLAWBOT:-}" ] || [ "$GUI" != true ]; then
  echo "apps: not a GUI clawbot — skipping."
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "apps: ⚠️  apt-get not found; skipping." >&2
  exit 0
fi

if [[ "$(id -u)" -eq 0 ]]; then sudo=""
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo="sudo"
else echo "apps: ⚠️  need root/passwordless sudo; skipping." >&2; exit 0; fi

arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

# Google Chrome (amd64-only .deb).
if ! command -v google-chrome >/dev/null 2>&1 && [ "$arch" = "amd64" ]; then
  echo "apps: installing Google Chrome…"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  if curl -fsSL -o "$tmp/chrome.deb" \
      https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb; then
    $sudo apt-get install -y "$tmp/chrome.deb" || echo "apps: ⚠️  Chrome install failed." >&2
  fi
fi

# VS Code via Microsoft's apt repo.
if ! command -v code >/dev/null 2>&1; then
  echo "apps: installing VS Code…"
  if curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor | $sudo tee /usr/share/keyrings/microsoft.gpg >/dev/null; then
    echo "deb [arch=$arch signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
      | $sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
    $sudo apt-get update -qq && $sudo apt-get install -y code || echo "apps: ⚠️  VS Code install failed." >&2
  fi
fi
