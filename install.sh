#!/bin/sh
# Bootstrap: install chezmoi (if missing) and apply this repo.
#
#   git clone https://github.com/akefirad/dotfiles.git ~/.dotfiles
#   ~/.dotfiles/install.sh
#
# Idempotent and non-interactive-safe: on a TTY it prompts for git identity, whether
# to clone the private overlay, the Powerlevel10k repo, and which optional tools to install;
# in CI/containers it takes derived defaults (honoring GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL
# and the INSTALL_* env), skipping the private clone unless PRIVATE_GH_TOKEN is set.
#
# Re-run to reconfigure the optional tools (INSTALL_* env or the prompt); changing one
# clears chezmoi's run-state cache so the run_onchange installers re-fire — with a
# confirmation first. Example: INSTALL_CLAUDE_CODE=1 ~/.dotfiles/install.sh

set -e # exit on error

bin_dir="$HOME/.local/bin"
chezmoi_config="$HOME/.config/chezmoi/chezmoi.yaml"

ensure_chezmoi() {
  if [ "$(command -v chezmoi)" ]; then
    chezmoi=chezmoi
    return 0
  fi
  chezmoi="$bin_dir/chezmoi"
  if [ "$(command -v curl)" ]; then
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$bin_dir"
  elif [ "$(command -v wget)" ]; then
    sh -c "$(wget -qO- get.chezmoi.io)" -- -b "$bin_dir"
  else
    echo "install.sh: need curl or wget to install chezmoi" >&2
    exit 1
  fi
}

# Clone the private overlay into ./private (gitignored), a per-machine sibling clone so
# forkers can point at their own private repo (or none). The URL is derived from THIS
# repo's origin: same host/owner, repo name with a leading dot (dotfiles -> .dotfiles).
# The token is used only in-process — never written to disk, the clone's .git/config,
# the URL, shell history, or visible in `ps` (the helper holds a literal $TOKEN; git
# expands it at runtime). Skipped when there's no origin, no token, or it's already
# cloned. (Not gated on clawbots: the overlay holds no secrets, and the non-interactive
# build path already skips it for lack of a token.)
clone_private() {
  origin=$(git -C "$script_dir" remote get-url origin 2>/dev/null || true)
  [ -n "$origin" ] || { echo "private: no origin remote; skipping." >&2; return 0; }

  # Parse host + owner/repo with shell builtins (no sed — the ssh form contains
  # '@'/':' which collide with sed delimiters).
  case "$origin" in
    *://*)  tmp=${origin#*://}; host=${tmp%%/*}; path=${tmp#*/} ;;   # https://host/owner/repo
    *@*:*)  tmp=${origin#*@};   host=${tmp%%:*}; path=${tmp#*:} ;;   # git@host:owner/repo
    *)      echo "private: cannot parse origin ($origin); skipping." >&2; return 0 ;;
  esac
  path=${path%.git}
  owner=${path%/*}
  repo=${path##*/}
  priv_url="https://$host/$owner/.$repo.git"

  dest="$script_dir/private"
  [ -e "$dest/.git" ] && { echo "private: already present at $dest." >&2; return 0; }

  # Token from $PRIVATE_GH_TOKEN, else prompt on a TTY (echo off); skip otherwise.
  token="${PRIVATE_GH_TOKEN:-}"
  if [ -z "$token" ]; then
    if [ -t 0 ]; then
      printf 'Clone private overlay %s ? token (blank to skip): ' "$priv_url" >&2
      stty -echo 2>/dev/null || true
      IFS= read -r token || true
      stty echo 2>/dev/null || true
      printf '\n' >&2
    else
      echo "private: no token, non-interactive; skipping ($priv_url)." >&2
      return 0
    fi
  fi
  [ -n "$token" ] || { echo "private: skipped." >&2; return 0; }

  echo "private: cloning $priv_url -> $dest" >&2
  # shellcheck disable=SC2016
  TOKEN="$token" GIT_TERMINAL_PROMPT=0 git \
    -c credential.helper= \
    -c credential.helper='!f() { echo username=x-access-token; echo "password=$TOKEN"; }; f' \
    clone "$priv_url" "$dest" \
    && echo "private: cloned." >&2 \
    || echo "private: clone failed (check token / scope)." >&2
}

# Default for an optional-tool switch: off on a clawbot, on for a human; Hermes off
# everywhere (mirrors the clawbot-aware defaults in .chezmoi.yaml.tmpl).
install_flag_default() {
  case "$1" in
    hermes) echo 0 ;;
    *) if [ -n "${CLAWBOT:-}" ]; then echo 0; else echo 1; fi ;;
  esac
}

# Resolve one optional-tool switch: ambient env wins; else the persisted value ($2); else
# the default ($3). On a TTY, prompt with the resolved value as the default. The prompt
# is written to stderr so the chosen value (printed to stdout) can be captured.
#   $1=env var name  $2=persisted value  $3=default  $4=prompt label
resolve_install_flag() {
  eval "_rif_env=\${$1:-}"
  if   [ -n "$_rif_env" ]; then _rif_val="$_rif_env"
  elif [ -n "$2" ];        then _rif_val="$2"
  else                          _rif_val="$3"; fi
  # This runs inside $(...), so stdout is the capture pipe — test stdin and stderr
  # (where the prompt is written), NOT stdout, or the prompt would never show.
  if [ -t 0 ] && [ -t 2 ]; then
    printf '%s? (1/0) [%s]: ' "$4" "$_rif_val" >&2
    read -r _rif_in || true
    [ -n "$_rif_in" ] && _rif_val="$_rif_in"
  fi
  printf '%s' "$_rif_val"
}

# First install only: derive git identity and the Powerlevel10k repo default from this
# repo's origin, prompting on a TTY to override the identity. Sets $git_name,
# $git_email and $p10k_repo; the p10k prompt itself is deferred to write_initial_config
# so it lands just after the private-overlay prompt.
derive_identity() {
  owner=""
  remote_url=$(git -C "$script_dir" remote get-url origin 2>/dev/null || true)
  if [ -n "$remote_url" ]; then
    owner=$(printf '%s' "$remote_url" | sed -E 's@.*[:/]([^/]+)/[^/]+(\.git)?$@\1@')
  fi

  git_name="${GIT_AUTHOR_NAME:-${owner:-Anonymous}}"

  git_email="${GIT_AUTHOR_EMAIL:-}"
  if [ -z "$git_email" ]; then
    if [ -n "$owner" ]; then
      git_email=$(git -C "$script_dir" log --author="$owner" -1 --format='%ae' 2>/dev/null || true)
    fi
    [ -z "$git_email" ] && git_email="${git_name}@localhost"
  fi

  p10k_repo="https://github.com/romkatv/powerlevel10k.git"
  if [ -n "$owner" ]; then
    candidate="https://github.com/$owner/powerlevel10k.git"
    if git ls-remote --exit-code "$candidate" HEAD >/dev/null 2>&1; then
      p10k_repo="$candidate"
    fi
  fi

  # Show the derived defaults, let the user override.
  # Non-interactive runs silently keep the derived values.
  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Git user.name [%s]: '  "$git_name";  read -r input || true; [ -n "$input" ] && git_name="$input"
    printf 'Git user.email [%s]: ' "$git_email"; read -r input || true; [ -n "$input" ] && git_email="$input"
  fi
  return 0   # the trailing `&& assign` above is 1 on empty input; don't trip `set -e`
}

# First install only: prompt for the Powerlevel10k repo and the optional-tool switches,
# then write the initial chezmoi config. Pre-populating these keeps chezmoi's
# promptStringOnce from re-asking on the first `init`; the INSTALL_* values are
# reconciled on later runs by reconcile_install_flags. Needs $git_name/$git_email/
# $p10k_repo from derive_identity.
write_initial_config() {
  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Powerlevel10k repo URL [%s]: ' "$p10k_repo"; read -r input || true; [ -n "$input" ] && p10k_repo="$input"
    echo "Optional tools (1=install, 0=skip):" >&2
  fi
  cc=$(resolve_install_flag INSTALL_CLAUDE_CODE "" "$(install_flag_default claudeCode)" "Install Claude Code")
  oc=$(resolve_install_flag INSTALL_OPENCODE   "" "$(install_flag_default opencode)"   "Install opencode")
  hm=$(resolve_install_flag INSTALL_HERMES     "" "$(install_flag_default hermes)"     "Install Hermes")

  mkdir -p "$(dirname "$chezmoi_config")"
  cat > "$chezmoi_config" <<EOF
data:
  git:
    name: "$git_name"
    email: "$git_email"
  p10k:
    repo: "$p10k_repo"
  install:
    claudeCode: "$cc"
    opencode: "$oc"
    hermes: "$hm"
EOF
}

# Re-run only: reconfigure the optional-tool switches on an already-provisioned box. For
# each switch, resolve env > persisted > default (prompting on a TTY) and write the
# result back to chezmoi.yaml. When a switch's prior value actually changes, the
# run_onchange installers won't re-fire on their own (they hash by content, not by the
# switch value), so chezmoi's run-state cache must be cleared — which re-runs ALL
# onchange scripts (idempotent). That's hinted and confirmed first. Works the same on
# Linux and macOS: the cache clear re-runs whatever each OS uses to install (Linux's
# per-tool scripts, macOS's `brew bundle`).
reconcile_install_flags() {
  yq_bin="$HOME/.local/bin/yq"
  command -v "$yq_bin" >/dev/null 2>&1 || yq_bin="$(command -v yq 2>/dev/null || true)"
  if [ -z "$yq_bin" ]; then
    echo "install: yq not found; skipping optional-tool reconcile (run 'chezmoi apply' once)." >&2
    return 0
  fi

  if [ -t 0 ] && [ -t 2 ]; then
    echo "Optional tools (1=install, 0=skip; Enter keeps current):" >&2
  fi

  install_changed=0
  for _key in claudeCode opencode hermes; do
    case "$_key" in
      claudeCode) _env=INSTALL_CLAUDE_CODE; _label="Claude Code" ;;
      opencode)   _env=INSTALL_OPENCODE;    _label="opencode"    ;;
      hermes)     _env=INSTALL_HERMES;      _label="Hermes"       ;;
    esac
    # mikefarah yq prints the scalar (e.g. `1`) or `null` for an absent key; normalize
    # both null and any quoted form to a bare value.
    _cur=$("$yq_bin" ".data.install.${_key}" "$chezmoi_config" 2>/dev/null || echo "null")
    [ "$_cur" = "null" ] && _cur=""
    case "$_cur" in \"*\") _cur=${_cur#\"}; _cur=${_cur%\"} ;; esac
    _new=$(resolve_install_flag "$_env" "$_cur" "$(install_flag_default "$_key")" "Install $_label")
    if [ "$_new" != "$_cur" ]; then
      "$yq_bin" -i ".data.install.${_key} = \"${_new}\"" "$chezmoi_config"
      # Only a change from a real prior value needs the cache clear; seeding an absent
      # key (a config that predates install:) just records the resolved default.
      [ -n "$_cur" ] && install_changed=1
    fi
  done

  [ "$install_changed" = 1 ] || return 0

  printf '\n' >&2
  echo "install: an optional-tool switch changed. To apply it the installers must re-run," >&2
  echo "         which means clearing chezmoi's run-state cache (state bucket" >&2
  echo "         'entryState'). That re-runs ALL provisioning scripts — idempotent, but" >&2
  echo "         slower than a normal apply." >&2
  _clear=1
  if [ -t 0 ] && [ -t 2 ]; then
    printf 'install: clear the cache and reapply now? [y/N]: ' >&2
    read -r _ans || true
    case "${_ans:-}" in [Yy]*) _clear=1 ;; *) _clear=0 ;; esac
  fi
  if [ "$_clear" = 1 ]; then
    echo "install: clearing run-state cache…" >&2
    "$chezmoi" state delete-bucket --bucket=entryState >/dev/null 2>&1 || true
  else
    echo "install: cache left intact — the switch is saved but won't take effect until the" >&2
    echo "         installers re-run. Re-run install.sh and confirm, or run:" >&2
    echo "         chezmoi state delete-bucket --bucket=entryState && chezmoi apply" >&2
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────────
ensure_chezmoi

# POSIX way to get the script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

# chezmoi.yaml existing decides first-install vs reconfigure. Capture it now, before
# write_initial_config creates it. (To reconfigure identity/p10k, delete the config and
# re-run; the optional tools reconcile on every run via reconcile_install_flags.)
config_existed=0; [ -f "$chezmoi_config" ] && config_existed=1

# Derive + prompt identity before cloning the private overlay so the two
# "which repository?" prompts (private overlay, then Powerlevel10k) stay adjacent.
if [ "$config_existed" = 0 ]; then derive_identity; fi

# Runs on every invocation; its own checks skip when there's no origin/token or it's
# already cloned.
clone_private || true

if [ "$config_existed" = 0 ]; then
  write_initial_config
else
  reconcile_install_flags
fi

# exec: replace this process with chezmoi, which renders the config template (prompting
# for any optional tools not yet persisted) and applies the target state.
exec "$chezmoi" init --apply "--source=$script_dir"
