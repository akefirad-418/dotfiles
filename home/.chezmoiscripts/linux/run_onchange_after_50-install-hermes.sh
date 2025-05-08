#!/usr/bin/env bash
# Tier 3 (vendor installer): Hermes agent CLI on Linux. Nous Research's official
# installer drops `hermes` sudo-free; macOS is a manual .dmg
# (https://hermes-assets.nousresearch.com/Hermes-Setup.dmg) — not provisioned here.
#
# An `after` script (not before): mise is a chezmoi external, applied with the
# rest of the target state *after* run_before_ scripts. We provision Node through
# mise, so this must run in the after phase — when mise exists on disk. (This is
# the same reason the old runtimes script was run_onchange_after_50.)
#
# Pinned, not install-if-latest: the installer fetches & checks out main, so we
# pass --commit to detach the checkout at a fixed upstream commit (HERMES_COMMIT)
# for reproducibility. Bump the SHA to upgrade.
#
# Runtime prereqs, so the vendor installer detects them and skips its own
# uncontrolled downloads:
#   node   — via mise (this repo's runtime manager), exposed on PATH via its
#            shims. The installer's check_node accepts node>=22.12, so node@24
#            satisfies it and the nodejs.org tarball fetch is skipped.
#   ffmpeg — optional (TTS voice messages only); installed via apt with an
#            apt-get update first. The vendor installer's own attempt skips the
#            update and fails on images with wiped apt lists (e.g. the clawbot base).
# Python 3.11 is deliberately left to the installer's managed uv (`uv python
# install`): pre-installing buys nothing since uv and mise pull the same
# python-build-standalone upstream. uv itself and Playwright/Chromium remain
# installer-owned. The mise step is best-effort — on failure the vendor installer
# falls back to fetching its own Node.
#
# --skip-setup skips the installer's interactive setup wizard. The wizard reads
# /dev/tty, so without this flag it launches whenever a terminal is attached (e.g. an
# interactive `bootstrap`) and only auto-skips when none is (so it stayed quiet at
# build time but surfaced under interactive provisioning). --non-interactive
# additionally skips other input-requiring stages. On a clawbot Hermes auth.json is
# seeded out-of-band by a chezmoi modify_ (dot_hermes/modify_private_auth.json), and the
# Telegram token placeholder + private dotenv fragment are seeded into ~/.hermes/.env
# near the end of THIS script (post-install — the installer ships .env.example but
# doesn't create .env). On a human box configure it interactively with `hermes setup`.
#
# Codex model pin: the vendor config.yaml ships model.default "anthropic/claude-opus-4.6".
# Seeding Codex auth sets only the provider (active_provider/auto-detect) — Hermes's
# codex login never rewrites model.default; only the interactive `/model` picker does
# (see hermes_cli/auth.py _update_config_for_provider, not called for codex). So a
# seeded box keeps the anthropic default and every inference call to the ChatGPT/Codex
# backend returns HTTP 400 "model not supported when using Codex with a ChatGPT
# account". On codex-seeded boxes (clawbots, $CLAWBOT) we therefore pin model.default to
# a Codex-served slug (see hermes_cli/codex_models.py DEFAULT_CODEX_MODELS). This must
# happen here, not in a chezmoi modify_ script: modify_ runs in the main apply phase,
# *before* this after-script's installer writes config.yaml, so it would no-op on a
# fresh box. The edit is key-aware (yq) and read-back-verified, so it survives the
# vendor reformatting that line and warns loudly if a bump restructures the key.
#
# OFF by default for every box. Opt in with INSTALL_HERMES=1 (resolved once at
# init, delivered via scriptEnv; see .chezmoi.yaml.tmpl). Flipping that flag on an
# existing box does NOT re-run this: run_onchange keys on a hash of the script's
# contents (chezmoi's entryState bucket), unchanged when only the scriptEnv flag flips
# — and `chezmoi apply --force` only suppresses prompts. Force it with:
#   chezmoi state delete-bucket --bucket=entryState && chezmoi apply
set -euo pipefail

# Pin github.com/NousResearch/hermes-agent to this commit. Bump to upgrade.
HERMES_COMMIT="f57ff7aef1d3d447e159511f3a3e9ed8ae0c7298"  # main @ 2026-06-21
# Codex/ChatGPT-served default model (bare slug, no "anthropic/"-style prefix).
# Live-verified working set: gpt-5.5, gpt-5.4, gpt-5.4-mini, gpt-5.3-codex
# (hermes_cli/codex_models.py:DEFAULT_CODEX_MODELS).
HERMES_CODEX_MODEL="gpt-5.5"

# The non-root installer drops the `hermes` launcher into ~/.local/bin (root/FHS
# would use /usr/local/bin); ~/.hermes is only the data home + managed uv, never
# the command. Re-add both command dirs so the install-if-missing check resolves
# regardless of layout — env.sh already has ~/.local/bin on the login PATH.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

if [ "${INSTALL_HERMES:-0}" != "1" ]; then
  echo "hermes: INSTALL_HERMES not set — skipping install."
  exit 0
fi

install_hermes() {
  # Prereq: ffmpeg (optional — used for TTS). The vendor installer runs `apt install
  # ffmpeg` with no `apt-get update`, which fails on images with wiped apt lists; do
  # it ourselves with the index refreshed first. Best-effort — TTS is degraded, not
  # fatal, if it fails.
  if command -v ffmpeg >/dev/null 2>&1; then
    echo "✅ ffmpeg already present."
  elif ! command -v apt-get >/dev/null 2>&1; then
    echo "⚠️  hermes: apt-get not found; leaving ffmpeg to the installer." >&2
  else
    if [ "$(id -u)" -eq 0 ]; then sudo=""
    elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo="sudo"
    else sudo="-"; fi
    if [ "$sudo" = "-" ]; then
      echo "⚠️  hermes: no root/passwordless sudo; leaving ffmpeg to the installer." >&2
    else
      echo "📦 hermes: installing ffmpeg via apt…"
      if $sudo apt-get update -qq && $sudo apt-get install -y --no-install-recommends ffmpeg; then
        echo "✅ ffmpeg installed."
      else
        echo "⚠️  hermes: ffmpeg apt install failed; continuing (TTS limited)." >&2
      fi
    fi
  fi

  # Prereq: Node 24 via mise. The installer needs node>=22.12; mise's node@24 clears
  # that, so check_node finds it on PATH and skips the nodejs.org download.
  mise="$HOME/.local/bin/mise"
  if [ -x "$mise" ]; then
    echo "📦 hermes: provisioning Node 24 via mise…"
    if "$mise" use --global node@24; then
      "$mise" reshim >/dev/null 2>&1 || true
      export PATH="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims:$PATH"
      echo "✅ node@24 via mise ($(node --version 2>/dev/null || echo '?'))."
    else
      echo "⚠️  hermes: mise node@24 failed; installer will fetch its own Node." >&2
    fi
  else
    echo "⚠️  hermes: mise not at $mise; installer will fetch its own Node." >&2
  fi

  echo "🤖 Installing Hermes (pinned ${HERMES_COMMIT:0:12})…"
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
    | bash -s -- --commit "$HERMES_COMMIT" --non-interactive --skip-setup
}

if command -v hermes >/dev/null 2>&1; then
  echo "✅ Hermes already installed."
else
  install_hermes
fi

# Pin the Codex default model (see header). Gated on $CLAWBOT — only a clawbot runs
# behind the gateway with seeded Codex creds; a human box keeps the vendor default.
# Runs whether or not we just installed, so an already-installed box still gets
# corrected. Idempotent and non-fatal.
#
# yq (chezmoi external, ALWAYS group) does a key-aware set — robust to the vendor
# changing that line's value/quoting on a HERMES_COMMIT bump, unlike a literal match.
# strenv() injects the value safely; the read-back guards against a vendor key
# rename/restructure that yq would silently no-op on.
if [ "${CLAWBOT:-0}" = "1" ]; then
  cfg="$HOME/.hermes/config.yaml"
  yq="$HOME/.local/bin/yq"
  command -v "$yq" >/dev/null 2>&1 || yq="$(command -v yq 2>/dev/null || true)"
  if [ ! -f "$cfg" ]; then
    echo "⚠️  hermes: $cfg not found; skipping Codex model pin." >&2
  elif [ -z "$yq" ]; then
    echo "⚠️  hermes: yq not found; skipping Codex model pin." >&2
  else
    model="$HERMES_CODEX_MODEL" "$yq" -i '.model.default = strenv(model)' "$cfg"
    got="$("$yq" '.model.default' "$cfg" 2>/dev/null || true)"
    if [ "$got" = "$HERMES_CODEX_MODEL" ]; then
      echo "✅ hermes: model.default pinned to $HERMES_CODEX_MODEL for Codex."
    else
      echo "⚠️  hermes: model.default is '$got' after yq edit (expected $HERMES_CODEX_MODEL);" >&2
      echo "    vendor config layout may have changed on this commit; check $cfg." >&2
    fi

    # Full unattended command execution on the sandboxed clawbot. The container +
    # clawpatrol egress firewall ARE the blast radius, so the in-agent approval
    # prompts add nothing here — and on an unattended gateway they would just hang a
    # command forever waiting for an approval nobody is there to give. config.yaml is
    # Hermes's LIVE security policy (tools/approval.py), so this single key covers
    # every surface (gateway, CLI, cron), unlike the process-scoped HERMES_YOLO_MODE
    # env var that exec'd sessions wouldn't inherit. cron_mode=approve does the same
    # for scheduled jobs (its own gate, default deny). The hardline floor (rm -rf /,
    # mkfs, dd-to-device, reboot, fork bombs) + the sudo-stdin guard stay enforced
    # regardless — "any command" here means any non-catastrophic command.
    "$yq" -i '.approvals.mode = "off" | .approvals.cron_mode = "approve"' "$cfg"
    got_appr="$("$yq" '.approvals.mode' "$cfg" 2>/dev/null || true)"
    case "$got_appr" in
      off|false) echo "✅ hermes: approvals.mode=off — agent runs any command unattended (hardline floor still enforced)." ;;
      *) echo "⚠️  hermes: approvals.mode is '$got_appr' after yq edit (expected off); check $cfg." >&2 ;;
    esac
  fi
fi

# Seed Telegram/runtime env into ~/.hermes/.env. MUST live here (after-script,
# post-install), NOT a chezmoi modify_ like auth.json: the installer ships the full
# default template at ~/.hermes/hermes-agent/.env.example but does NOT create .env on a
# --skip-setup run. A modify_ runs in MAIN APPLY (before this script), so it (a) can't
# read the template and (b) creates a bare .env that pre-empts the rich defaults — which
# wiped .env down to our keys. Here, post-install, the template exists, so we can
# establish it first and then add only our keys. Non-destructive: never rewrites the
# file wholesale.
if [ "${CLAWBOT:-0}" = "1" ]; then
  env_file="$HOME/.hermes/.env"
  example="$HOME/.hermes/hermes-agent/.env.example"
  mkdir -p "$HOME/.hermes"
  # Establish the rich default template if nothing has created .env yet (so seeding our
  # keys doesn't strand the box without Hermes's documented defaults). Then ensure it
  # exists even if the template is missing (vendor layout change).
  [ -f "$env_file" ] || { [ -f "$example" ] && cp "$example" "$env_file"; }
  [ -f "$env_file" ] || : > "$env_file"

  # set_env_kv KEY VALUE — authoritative in-place set: replace the active KEY= line if
  # present, else append. Preserves every other line (comments, the template, API keys a
  # user set). awk matches the literal "KEY=" prefix; a commented "# KEY=" is left intact.
  set_env_kv() {
    if grep -q "^$1=" "$env_file" 2>/dev/null; then
      _t=$(mktemp)
      awk -v k="$1" -v v="$2" 'index($0,k"=")==1{print k"="v;next}{print}' "$env_file" > "$_t" \
        && cat "$_t" > "$env_file" && rm -f "$_t"
    else
      printf '%s=%s\n' "$1" "$2" >> "$env_file"
    fi
  }

  set_env_kv TELEGRAM_BOT_TOKEN '0000000000:clawpatrol-placeholder-do-not-use'
  echo "✅ hermes: seeded fake TELEGRAM_BOT_TOKEN placeholder (gateway injects the real token)."

  # Merge the PRIVATE dotenv fragment from the cloned overlay ($PRIVATE_HERMES_ENV):
  # real settings (allowed users, home channel, …) live only there, never in the public
  # repo. One KEY=VALUE per line; blanks/comments/no-'=' skipped.
  if [ -n "${PRIVATE_HERMES_ENV:-}" ] && [ -f "$PRIVATE_HERMES_ENV" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|\#*) continue ;; esac
      key=${line%%=*}; [ "$key" = "$line" ] && continue
      set_env_kv "$key" "${line#*=}"
      echo "✅ hermes: provisioned $key from private overlay."
    done < "$PRIVATE_HERMES_ENV"
  fi
  chmod 600 "$env_file" 2>/dev/null || true
fi

# The interactive setup wizard is skipped (--skip-setup); point the user at it.
if command -v hermes >/dev/null 2>&1; then
  hermes --version || true
  if [ "${CLAWBOT:-0}" = "1" ]; then
    echo "✅ hermes: ready — Codex auth is seeded and the gateway injects real credentials at the wire. Run 'hermes' to start ('hermes setup' only to reconfigure)."
  else
    echo "✅ hermes: installed; the interactive setup wizard was skipped. Run 'hermes setup' to configure API keys/providers."
  fi
fi
