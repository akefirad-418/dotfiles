#!/usr/bin/env bash
# Root step: let codex's bundled bubblewrap create user namespaces. Ubuntu 24.04+
# sets kernel.apparmor_restrict_unprivileged_userns=1, which confines any binary
# without its own AppArmor profile, so codex's sandbox fails on every command with
# "bwrap: setting up uid map: Permission denied". The profile below is Ubuntu's
# stock pattern for such apps (see /etc/apparmor.d/code). Non-fatal: without root
# it warns and skips.
set -uo pipefail

if [ ! -x "$HOME/.local/share/codex/codex-resources/bwrap" ]; then
  echo "codex-bwrap: codex's bundled bwrap is not installed; skipping."
  exit 0
fi

if [ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null)" != 1 ]; then
  echo "codex-bwrap: user namespaces are not restricted here; skipping."
  exit 0
fi

if [[ "$(id -u)" -eq 0 ]]; then sudo=""
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo="sudo"
else echo "codex-bwrap: ⚠️  need root/passwordless sudo; codex's sandbox fails until /etc/apparmor.d/codex-bwrap is loaded." >&2; exit 0; fi

profile=/etc/apparmor.d/codex-bwrap
$sudo tee "$profile" >/dev/null <<'EOF'
abi <abi/5.0>,
include <tunables/global>

profile codex-bwrap @{HOME}/.local/share/codex/codex-resources/bwrap flags=(unconfined) {
  userns,
  include if exists <local/codex-bwrap>
}
EOF
$sudo apparmor_parser -r "$profile" || echo "codex-bwrap: ⚠️  loading $profile failed." >&2
