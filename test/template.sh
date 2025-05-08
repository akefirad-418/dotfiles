#!/usr/bin/env bash
# Host-side template tests (no Docker): assert switch resolution + per-role gating
# render correctly. Complements test/verify.sh (the Docker runtime contract, which
# only exercises clawbot + headless + Linux). Read-only: uses `chezmoi
# execute-template --init`, which never writes config or touches the real machine.
set -uo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
TMPL="$REPO_ROOT/home/.chezmoi.yaml.tmpl"
IGN="$REPO_ROOT/home/.chezmoiignore.tmpl"
EXT="$REPO_ROOT/home/.chezmoiexternals/shared.yaml.tmpl"
GIT="$REPO_ROOT/home/dot_config/git/config.tmpl"

if ! command -v chezmoi >/dev/null 2>&1; then echo "template.sh: chezmoi not found; skipping." >&2; exit 0; fi
if ! command -v ruby >/dev/null 2>&1; then echo "template.sh: ruby not found; skipping." >&2; exit 0; fi

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT

# Prompt answers so promptStringOnce doesn't block; --source decouples from the
# hardcoded sourceDir so this runs from any checkout path.
P=(-p git.name=test -p git.email=test@localhost -p p10k.repo=https://github.com/x/powerlevel10k.git --source "$REPO_ROOT")

pass=0; fail=0
assert_eq() { # NAME EXPECT ACTUAL
  if [ "$2" = "$3" ]; then printf '  ✅ %s\n' "$1"; pass=$((pass+1))
  else printf '  ❌ %s (expected [%s], got [%s])\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
assert_true()  { if [ "$2" -gt 0 ] 2>/dev/null; then printf '  ✅ %s\n' "$1"; pass=$((pass+1)); else printf '  ❌ %s (expected match, found none)\n' "$1"; fail=$((fail+1)); fi; }
assert_false() { if [ "$2" -eq 0 ] 2>/dev/null; then printf '  ✅ %s\n' "$1"; pass=$((pass+1)); else printf '  ❌ %s (expected none, found %s)\n' "$1" "$2"; fail=$((fail+1)); fi; }

# render-config "ENV ASSIGNMENTS" -> path to a temp config rendered from TMPL
# Unique .yaml config per call. mktemp (not a shared counter) so it works even
# though rc runs in a command-substitution subshell. chezmoi --config needs .yaml.
rc() { local base out; base="$(mktemp "$TMPD/cfg.XXXXXX")"; out="$base.yaml"; mv "$base" "$out"; # shellcheck disable=SC2086
  env $1 chezmoi execute-template --init "${P[@]}" < "$TMPL" > "$out"; echo "$out"; }
# yget DOTTED.PATH FILE -> value (bools print true/false)
yget() { ruby -ryaml -e 'p=ARGV[0].split("."); d=YAML.safe_load(File.read(ARGV[1])); p.each{|k| d=d[k]}; print d' "$1" "$2"; }
# render TEMPLATE CONFIG -> rendered text on stdout
render() { chezmoi --config "$2" execute-template --source "$REPO_ROOT" < "$1"; }
countlines() { grep -cE "$1" "$2" || true; }

echo "==> switch resolution"
# .clawbot is a boolean flag: any non-empty CLAWBOT -> "1", else "". No identity/hostname.
c=$(rc "");                         assert_eq "clawbot unset -> ''"        ""    "$(yget data.clawbot "$c")"
c=$(rc "CLAWBOT=clawbot-42");       assert_eq "CLAWBOT set -> '1'"         "1"   "$(yget data.clawbot "$c")"
c=$(rc "CLAWBOT=auto");             assert_eq "CLAWBOT=auto -> '1' (no hostname)" "1" "$(yget data.clawbot "$c")"
c=$(rc "CLAWBOT=1");                assert_eq "CLAWBOT=1 -> '1'"           "1"   "$(yget data.clawbot "$c")"
# install defaults are clawbot-aware: human box -> 1, clawbot -> 0. Explicit env wins.
c=$(rc "");                              assert_eq "claudeCode default (human)"   "1" "$(yget data.install.claudeCode "$c")"
c=$(rc "CLAWBOT=1");                     assert_eq "claudeCode default (clawbot)" "0" "$(yget data.install.claudeCode "$c")"
c=$(rc "CLAWBOT=1 INSTALL_CLAUDE_CODE=1"); assert_eq "INSTALL_CLAUDE_CODE=1 wins on clawbot" "1" "$(yget data.install.claudeCode "$c")"
c=$(rc "INSTALL_CLAUDE_CODE=0");         assert_eq "INSTALL_CLAUDE_CODE=0 (human)" "0" "$(yget data.install.claudeCode "$c")"
c=$(rc "");                              assert_eq "opencode default (human)"     "1" "$(yget data.install.opencode "$c")"
c=$(rc "CLAWBOT=1");                     assert_eq "opencode default (clawbot)"   "0" "$(yget data.install.opencode "$c")"
c=$(rc "CLAWBOT=1 INSTALL_OPENCODE=1");  assert_eq "INSTALL_OPENCODE=1 wins on clawbot" "1" "$(yget data.install.opencode "$c")"
# Hermes is OFF by default on every box (not clawbot-aware); INSTALL_HERMES=1 opts in.
c=$(rc "");                              assert_eq "hermes default (human)"   "0" "$(yget data.install.hermes "$c")"
c=$(rc "CLAWBOT=1");                     assert_eq "hermes default (clawbot)" "0" "$(yget data.install.hermes "$c")"
c=$(rc "INSTALL_HERMES=1");              assert_eq "INSTALL_HERMES=1 opts in" "1" "$(yget data.install.hermes "$c")"
# GUI is NOT baked (it's runtime-detected); it must not appear in data or scriptEnv.
c=$(rc "GUI=1");                    assert_eq "gui not baked into data"     ""          "$(yget data.gui "$c")"
                                    assert_eq "GUI not in scriptEnv"        ""          "$(yget scriptEnv.GUI "$c")"
# scriptEnv carries the resolved switches for native scripts. On a clawbot the
# install defaults are 0; a human box (below) gets 1.
c=$(rc "CLAWBOT=1");                assert_eq "scriptEnv.CLAWBOT" "1" "$(yget scriptEnv.CLAWBOT "$c")"
                                    assert_eq "scriptEnv.INSTALL_CLAUDE_CODE (clawbot)" "0" "$(yget scriptEnv.INSTALL_CLAUDE_CODE "$c")"
                                    assert_eq "scriptEnv.INSTALL_OPENCODE (clawbot)"    "0" "$(yget scriptEnv.INSTALL_OPENCODE "$c")"
                                    assert_eq "scriptEnv.INSTALL_HERMES (default off)"  "0" "$(yget scriptEnv.INSTALL_HERMES "$c")"
c=$(rc "INSTALL_HERMES=1");         assert_eq "scriptEnv.INSTALL_HERMES (opted in)"     "1" "$(yget scriptEnv.INSTALL_HERMES "$c")"
c=$(rc "");                         assert_eq "scriptEnv.INSTALL_CLAUDE_CODE (human)"   "1" "$(yget scriptEnv.INSTALL_CLAUDE_CODE "$c")"
                                    assert_eq "scriptEnv.INSTALL_OPENCODE (human)"      "1" "$(yget scriptEnv.INSTALL_OPENCODE "$c")"

echo
echo "==> no seed switch (seeding is derived from .clawbot ∧ INSTALL_*, not a knob)"
# The old SEED_CODEX_AUTH / SEED_HERMES_TELEGRAM_TOKEN switches were removed; the
# seeder scripts gate on $CLAWBOT directly. Lock that in: no seed* key leaks into
# data or scriptEnv.
c=$(rc "CLAWBOT=clawbot-42");  assert_eq "no data.seedCodexAuth"          "" "$(yget data.seedCodexAuth "$c")"
                              assert_eq "no data.seedGatewayCreds"       "" "$(yget data.seedGatewayCreds "$c")"
                              assert_eq "no scriptEnv.SEED_CODEX_AUTH"   "" "$(yget scriptEnv.SEED_CODEX_AUTH "$c")"
                              assert_eq "no scriptEnv.SEED_GATEWAY_CREDS" "" "$(yget scriptEnv.SEED_GATEWAY_CREDS "$c")"
# CLAWBOT (the actual seed gate) IS in scriptEnv for the seeder scripts.
                              assert_eq "scriptEnv.CLAWBOT carries the gate" "1" "$(yget scriptEnv.CLAWBOT "$c")"

echo
echo "==> GUI runtime detection in env.sh (live each apply, never baked)"
# Source the real env.sh in an isolated subshell (temp HOME so no clawbot.env /
# env.local.sh interfere) and read back the exported GUI for various inputs.
gui_detect() { ( set +u; export HOME="$TMPD/h"; mkdir -p "$HOME"
  if [ -n "$1" ]; then export GUI="$1"; else unset GUI; fi
  . "$REPO_ROOT/home/dot_config/shell/env.sh" >/dev/null 2>&1; printf '%s' "${GUI:-}" ); }
assert_eq "GUI=0 -> false" "false" "$(gui_detect 0)"
assert_eq "GUI=1 -> true"  "true"  "$(gui_detect 1)"
if [ "$(uname)" = Darwin ]; then assert_eq "unset on macOS -> true" "true" "$(gui_detect '')"; fi

echo
echo "==> persistence on re-init (persisted value wins; env only seeds first init)"
seed=$(rc "CLAWBOT=1 INSTALL_CLAUDE_CODE=0")
c2="$TMPD/reinit-noenv.yaml"; chezmoi --config "$seed" execute-template --init "${P[@]}" < "$TMPL" > "$c2"
assert_eq "clawbot persists when env unset"        "1" "$(yget data.clawbot "$c2")"
assert_eq "install persists when env unset"        "0" "$(yget data.install.claudeCode "$c2")"
# scriptEnv re-injects CLAWBOT, so a fresh env can't flip a persisted clawbot off on
# re-init — persisted wins by design. (To change: clear the key + re-init.)
c3="$TMPD/reinit-env.yaml"; CLAWBOT= chezmoi --config "$seed" execute-template --init "${P[@]}" < "$TMPL" > "$c3"
assert_eq "persisted wins over fresh env on re-init" "1" "$(yget data.clawbot "$c3")"

echo
echo "==> externals gating"
cb=$(rc "CLAWBOT=clawbot-42"); pf=$(rc "")
ext_cb="$(mktemp)"; render "$EXT" "$cb" > "$ext_cb"
ext_pf="$(mktemp)"; render "$EXT" "$pf" > "$ext_pf"
# Robust to tools moving between the ALWAYS and personal groups: check membership,
# not exact counts.
cb_n=$(countlines '^(\.local/bin/|\.config/)' "$ext_cb")
pf_n=$(countlines '^(\.local/bin/|\.config/)' "$ext_pf")
assert_true  "clawbot has the minimal binaries (rg+uv+mise)" "$(( $(countlines 'bin/rg:' "$ext_cb") + $(countlines 'bin/uv:' "$ext_cb") + $(countlines 'bin/mise:' "$ext_cb") ))"
assert_false "clawbot excludes personal-only (bat+fzf+k9s)"   "$(( $(countlines 'bin/bat:' "$ext_cb") + $(countlines 'bin/fzf:' "$ext_cb") + $(countlines 'bin/k9s:' "$ext_cb") ))"
assert_true  "personal externals > clawbot"                   "$(( pf_n - cb_n ))"
assert_false "no oh-my-zsh on clawbot"                        "$(countlines 'ohmyzsh' "$ext_cb")"
assert_true  "oh-my-zsh present on personal"                  "$(countlines 'ohmyzsh' "$ext_pf")"
assert_true  "bun in personal set"                            "$(countlines 'bin/bun:' "$ext_pf")"
assert_false "no bun on clawbot"                              "$(countlines 'bin/bun:' "$ext_cb")"
# btop/eza are Linux-only externals; this render is macOS, so they must be absent
# here (macOS uses brew for them).
assert_false "btop not a macOS external"                      "$(countlines 'bin/btop:' "$ext_pf")"
assert_false "eza not a macOS external"                       "$(countlines 'bin/eza:' "$ext_pf")"
echo
echo "==> .chezmoiignore gating"
ign_cb="$(mktemp)"; render "$IGN" "$cb" > "$ign_cb"
ign_pf="$(mktemp)"; render "$IGN" "$pf" > "$ign_pf"
assert_true  "clawbot ignores personal layer (alacritty)" "$(countlines 'alacritty' "$ign_cb")"
assert_false "personal does NOT ignore alacritty"         "$(countlines 'alacritty' "$ign_pf")"

echo
echo "==> git config gating"
git_cb="$(mktemp)"; render "$GIT" "$cb" > "$git_cb"
git_pf="$(mktemp)"; render "$GIT" "$pf" > "$git_pf"
assert_eq    "clawbot pager = cat"      "cat"   "$(awk '/^\[core\]/{c=1} c&&/pager =/{print $3; exit}' "$git_cb")"
assert_false "no delta sections on clawbot" "$(countlines 'delta' "$git_cb")"
assert_eq    "personal pager = delta"   "delta" "$(awk '/^\[core\]/{c=1} c&&/pager =/{print $3; exit}' "$git_pf")"
assert_true  "delta sections on personal" "$(countlines 'delta' "$git_pf")"

echo
echo "==> $pass passed, $fail failed"
[ "$fail" -eq 0 ]
