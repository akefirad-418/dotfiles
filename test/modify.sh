#!/usr/bin/env bash
# Host-side behavioral tests for the FAKE-Codex-creds modify_ scripts
# (home/dot_hermes + home/dot_local/share/opencode). Runs the ACTUAL scripts
# with controlled stdin + the gate env ($CLAWBOT ∧ the tool's $INSTALL_*) and
# asserts the safety contract:
# (~/.hermes/.env is seeded by the Hermes after-script, not a modify_, so it's
#  covered by the Docker verify, not here.)
#   - gated + absent  -> emit a valid seed (fresh first-build path, no jq)
#   - gated + existing -> MERGE: other providers/keys survive, ours seeded
#   - not gated + existing -> byte-for-byte passthrough (human box untouched)
#   - not gated + absent  -> empty output (chezmoi creates no file)
#   - clawbot but tool not installed -> NOT seeded (consumer gate)
# Read-only: the scripts only read stdin and write stdout; nothing on disk.
set -uo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
OC="$REPO_ROOT/home/dot_local/share/opencode/modify_private_auth.json"
HM="$REPO_ROOT/home/dot_hermes/modify_private_auth.json"

command -v jq >/dev/null 2>&1 || { echo "modify.sh: jq not found; skipping." >&2; exit 0; }

pass=0; fail=0
ok(){ printf '  ✅ %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  ❌ %s%s\n' "$1" "${2:+  -> $2}"; fail=$((fail+1)); }
# jc NAME JSON FILTER  — assert jq FILTER is true over JSON
jc(){ if printf '%s' "$2" | jq -e "$3" >/dev/null 2>&1; then ok "$1"; else no "$1" "$2"; fi; }
# run SCRIPT GATE STDIN -> script stdout. GATE=1 means "should seed": set CLAWBOT and
# BOTH INSTALL_* to it, so either script's compound gate ($CLAWBOT ∧ its INSTALL_*)
# fires. GATE=0 -> all off -> not gated. (Consumer-gate cases below set env directly.)
# NOTE: $(run ...) strips trailing newlines — fine for JSON/empty checks, but
# use `exact` (file cmp) for byte-for-byte passthrough assertions.
run(){ printf '%s' "$3" | CLAWBOT="$2" INSTALL_HERMES="$2" INSTALL_OPENCODE="$2" sh "$1"; }
# exact NAME SCRIPT GATE INPUT — assert script output equals INPUT byte-for-byte
exact(){ local a b; a=$(mktemp); b=$(mktemp)
  printf '%s' "$4" > "$a"
  printf '%s' "$4" | CLAWBOT="$3" INSTALL_HERMES="$3" INSTALL_OPENCODE="$3" sh "$2" > "$b"
  if cmp -s "$a" "$b"; then ok "$1"; else no "$1" "$(od -c "$b" | tail -2)"; fi
  rm -f "$a" "$b"; }

echo "==> opencode modify script"
jc "gated+absent emits valid seed" "$(run "$OC" 1 "")" \
   '.openai.type=="oauth" and (.openai.access|startswith("eyJ")) and .openai.expires==4102444800000'
jc "gated+existing MERGES (other provider survives)" \
   "$(run "$OC" 1 '{"anthropic":{"type":"oauth","access":"REAL-CLAUDE"},"keep":42}')" \
   '.anthropic.access=="REAL-CLAUDE" and .keep==42 and .openai.type=="oauth"'
# byte-exact passthrough, INCLUDING trailing newline
exact "not-gated passthrough is byte-exact (keeps trailing newline)" "$OC" 0 $'{"anthropic":{"access":"REAL"}}\n'
out=$(run "$OC" 0 ""); [ -z "$out" ] && ok "not-gated+absent emits nothing" || no "not-gated+absent emits nothing" "$out"
# consumer gate: clawbot but OpenCode not installed -> NOT seeded
out=$(printf '%s' "" | CLAWBOT=1 INSTALL_OPENCODE=0 sh "$OC")
[ -z "$out" ] && ok "clawbot + no INSTALL_OPENCODE -> no seed" || no "clawbot + no INSTALL_OPENCODE -> no seed" "$out"
# re-apply over our own prior seed must still keep a sibling provider
jc "re-apply keeps sibling provider" "$(run "$OC" 1 "$(run "$OC" 1 '{"anthropic":{"access":"REAL"}}')")" \
   '.anthropic.access=="REAL" and .openai.type=="oauth"'

echo
echo "==> hermes modify script"
jc "gated+absent emits valid seed" "$(run "$HM" 1 "")" \
   '.providers["openai-codex"].auth_mode=="chatgpt" and (.credential_pool["openai-codex"][0].source=="device_code") and .active_provider=="openai-codex"'
jc "gated+existing MERGES (providers, pool, active_provider survive)" \
   "$(run "$HM" 1 '{"providers":{"nous":{"x":1}},"active_provider":"nous","credential_pool":{"nous":[{"a":1}]}}')" \
   '.providers.nous.x==1 and .credential_pool.nous[0].a==1 and (.providers["openai-codex"]!=null) and .active_provider=="nous"'
exact "not-gated passthrough is byte-exact (keeps trailing newline)" "$HM" 0 $'{"providers":{"nous":{"x":1}}}\n'
out=$(run "$HM" 0 ""); [ -z "$out" ] && ok "not-gated+absent emits nothing" || no "not-gated+absent emits nothing" "$out"
# consumer gate: clawbot but Hermes not installed -> NOT seeded
out=$(printf '%s' "" | CLAWBOT=1 INSTALL_HERMES=0 sh "$HM")
[ -z "$out" ] && ok "clawbot + no INSTALL_HERMES -> no seed" || no "clawbot + no INSTALL_HERMES -> no seed" "$out"

echo
echo "==> $pass passed, $fail failed"
[ "$fail" -eq 0 ]
