#!/usr/bin/env bash
# Strict post-install contract for a CLAWBOT on headless Linux (how test/run.sh
# provisions the container). Asserts the lean agent layout is present AND the
# personal/desktop layer is absent. Exits non-zero on any failure.
set -uo pipefail

# Load the shared env exactly as a login shell would (PATH, CLAWBOT/GUI, …).
[ -r "$HOME/.config/shell/env.sh" ] && . "$HOME/.config/shell/env.sh"
PATH="$HOME/.local/bin:$PATH"

pass=0; fail=0
ok()   { printf '  ✅ %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  ❌ %s%s\n' "$1" "${2:+  ($2)}"; fail=$((fail+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

# present NAME [CMD...] — CMD must succeed (defaults to: NAME is on PATH)
present() { local n="$1"; shift; if [ "$#" -eq 0 ]; then have "$n" && ok "$n" || no "$n" "not on PATH"; else eval "$*" >/dev/null 2>&1 && ok "$n" || no "$n" "$*"; fi; }
# absent NAME COND — COND must FAIL (i.e. the thing must not exist)
absent() { local n="$1"; shift; if eval "$*" >/dev/null 2>&1; then no "$n" "present but should be gated off"; else ok "$n absent"; fi; }

echo "==> tier-1 tools on PATH"
for t in rg fd jq yq gh uv uvx mise aws; do present "$t"; done

echo
echo "==> optional tools (clawbot defaults BOTH off; explicit INSTALL_* env wins)"
# verify.sh always runs as a clawbot, so the default is 0 (not installed).
if [ "${INSTALL_CLAUDE_CODE:-0}" = "0" ]; then
  absent "claude (clawbot default off)" "have claude"
else
  present "claude" "have claude"
fi
if [ "${INSTALL_OPENCODE:-0}" = "0" ]; then
  absent "opencode (clawbot default off)" "have opencode"
else
  present "opencode" "have opencode"
fi
# Hermes is off by default on every box; installed only when INSTALL_HERMES=1.
if [ "${INSTALL_HERMES:-0}" = "1" ]; then
  present "hermes" "have hermes"
else
  absent "hermes (default off)" "have hermes"
fi

echo
echo "==> switches in the shell env (CLAWBOT persisted; GUI detected at runtime)"
present "CLAWBOT flag set (=1)"    '[ "${CLAWBOT:-}" = "1" ]'
present "GUI detected false (headless)" '[ "${GUI:-}" = "false" ]'
present "GUI not exported from clawbot.env" '! grep -q "export GUI" "$HOME/.config/shell/clawbot.env"'
present "clawbot.env generated"    'test -r "$HOME/.config/shell/clawbot.env"'
present "CLAWBOT survives a fresh bash" 'test "$(bash -lc "printf %s \"\$CLAWBOT\"")" = "1"'

echo
echo "==> shared shell config"
present "env.sh"        'test -f "$HOME/.config/shell/env.sh"'
present "functions.sh"  'test -f "$HOME/.config/shell/functions.sh"'
present "bashrc.sh"     'test -f "$HOME/.config/shell/bashrc.sh"'
present ".bashrc managed block" 'grep -q "# >>> chezmoi-dotfiles (managed) >>>" "$HOME/.bashrc"'
present ".profile managed block" 'grep -q "# >>> chezmoi-dotfiles (managed) >>>" "$HOME/.profile"'
present "local-bin on login PATH" 'bash -lc "case \":\$PATH:\" in *:\$HOME/.local/bin:*) exit 0;; *) exit 1;; esac"'

echo
echo "==> zsh location"
present ".config/zsh/.zshenv" 'test -f "$HOME/.config/zsh/.zshenv"'
present ".zshenv symlink"     'test -L "$HOME/.zshenv"'

echo
echo "==> git"
present "git installed"   'have git'
present "git user.name"   'git config --global user.name  | grep -q .'
present "git user.email"  'git config --global user.email | grep -q .'
present "git pager = cat (clawbot)" '[ "$(git config --global core.pager)" = "cat" ]'

echo
echo "==> seeded fake creds (clawbot ∧ INSTALL_<tool>; default clawbot has all tools off)"
# Seeding is per tool now: a clawbot is seeded ONLY for the tools it installed. verify.sh
# always runs as a clawbot, so each check keys on the tool's INSTALL_* flag.
OC="$HOME/.local/share/opencode/auth.json"
HM="$HOME/.hermes/auth.json"
ENV_FILE="$HOME/.hermes/.env"
TG_PLACEHOLDER='0000000000:clawpatrol-placeholder-do-not-use'

if [ "${INSTALL_OPENCODE:-0}" = "1" ]; then
  present "opencode auth.json valid"  "jq -e . '$OC'"
  present "opencode oauth + fake JWT" "[ \"\$(jq -r .openai.type '$OC')\" = oauth ] && jq -re '.openai.access | startswith(\"eyJ\")' '$OC'"
  present "opencode exp far-future"   "[ \"\$(jq -r .openai.expires '$OC')\" = 4102444800000 ]"
else
  absent "opencode auth.json not seeded (OpenCode off)" "test -f '$OC'"
fi

if [ "${INSTALL_HERMES:-0}" = "1" ]; then
  present "hermes auth.json valid"            "jq -e . '$HM'"
  present "hermes pool seeded (device_code)"  "[ \"\$(jq -r '.credential_pool[\"openai-codex\"][0].source' '$HM')\" = device_code ]"
  present "hermes account_id claim present"   "jq -re '.providers[\"openai-codex\"].tokens.access_token' '$HM' | cut -d. -f2 | { p=\$(cat); pad=\$(( (4 - \${#p} % 4) % 4 )); printf '%s%*s' \"\$p\" \"\$pad\" '' | tr ' ' '=' | tr '_-' '/+' | base64 -d 2>/dev/null | jq -re '.\"https://api.openai.com/auth\".chatgpt_account_id'; }"
  present "hermes .env has fake TELEGRAM_BOT_TOKEN" "grep -qxF 'TELEGRAM_BOT_TOKEN=$TG_PLACEHOLDER' '$ENV_FILE'"
  # Non-destructive: .env must also carry the vendor default template (not just our
  # keys) — guards against pre-empting the defaults (the modify_-in-main-apply bug).
  present "hermes .env keeps vendor default template" "grep -q '^# Hermes Agent Environment Configuration' '$ENV_FILE'"
  present "hermes .env is the full template (>50 lines)" "[ \"\$(wc -l < '$ENV_FILE')\" -gt 50 ]"
else
  absent "hermes auth.json not seeded (Hermes off)"      "test -f '$HM'"
  absent "TELEGRAM_BOT_TOKEN not seeded (Hermes off)"    "grep -q '^TELEGRAM_BOT_TOKEN=' '$ENV_FILE'"
fi

echo
echo "==> personal / desktop layer must be ABSENT on a clawbot"
absent "oh-my-zsh"   'test -d "$HOME/.config/zsh/ohmyzsh" -o -d "$HOME/.config/ohmyzsh"'
absent "p10k"        'test -f "$HOME/.config/zsh/.p10k.zsh"'
absent ".zshrc"      'test -f "$HOME/.config/zsh/.zshrc"'
absent "aliases.sh"  'test -f "$HOME/.config/shell/aliases.sh"'
absent "Linuxbrew"   'test -d /home/linuxbrew/.linuxbrew'
absent "bat"         'have bat'
absent "fzf"         'have fzf'
absent "k9s"         'test -x "$HOME/.local/bin/k9s"'

echo
echo "==> $pass passed, $fail failed"
[ "$fail" -eq 0 ]
