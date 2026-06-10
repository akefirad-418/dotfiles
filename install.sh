#!/bin/sh
# Bootstrap: install chezmoi (if missing) and apply this repo.
#
#   git clone https://github.com/akefirad-418/dotfiles.git ~/.dotfiles
#   ~/.dotfiles/install.sh
#
# Idempotent and non-interactive-safe: on a TTY it prompts for git identity
# with derived defaults; in CI/containers it silently takes the defaults.
set -e # exit on error

bin_dir="$HOME/.local/bin"

if [ "$(command -v chezmoi)" ]; then
  chezmoi=chezmoi
else
  chezmoi="$bin_dir/chezmoi"
  if [ "$(command -v curl)" ]; then
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$bin_dir"
  elif [ "$(command -v wget)" ]; then
    sh -c "$(wget -qO- get.chezmoi.io)" -- -b "$bin_dir"
  else
    echo "install.sh: need curl or wget to install chezmoi" >&2
    exit 1
  fi
fi

# POSIX way to get the script's own directory (the repo root).
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

# Pre-seed chezmoi's config so promptStringOnce in home/.chezmoi.yaml.tmpl
# doesn't block. Skipped if the config already exists (re-runs keep prior
# values). To reconfigure: rm ~/.config/chezmoi/chezmoi.yaml and re-run.
chezmoi_config="$HOME/.config/chezmoi/chezmoi.yaml"
if [ ! -f "$chezmoi_config" ]; then
  # Derive identity from the repo's git remote/history when available.
  owner=""
  remote_url=$(git -C "$script_dir" remote get-url origin 2>/dev/null || true)
  [ -n "$remote_url" ] && owner=$(printf '%s' "$remote_url" | sed -E 's@.*[:/]([^/]+)/[^/]+(\.git)?$@\1@')

  git_name="${GIT_AUTHOR_NAME:-${owner:-agent}}"
  git_email="${GIT_AUTHOR_EMAIL:-}"
  if [ -z "$git_email" ]; then
    [ -n "$owner" ] && git_email=$(git -C "$script_dir" log -1 --format='%ae' 2>/dev/null || true)
    [ -z "$git_email" ] && git_email="${git_name}@localhost"
  fi

  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Git user.name [%s]: '  "$git_name";  read input || true; [ -n "$input" ] && git_name="$input"
    printf 'Git user.email [%s]: ' "$git_email"; read input || true; [ -n "$input" ] && git_email="$input"
  fi

  mkdir -p "$(dirname "$chezmoi_config")"
  cat > "$chezmoi_config" <<EOF
data:
  git:
    name: "$git_name"
    email: "$git_email"
EOF
fi

# Replace this process with chezmoi; applies the source state from this repo.
exec "$chezmoi" init --apply "--source=$script_dir"
