#!/bin/sh
# Shared (OS-agnostic), POSIX sh: post-apply sanity check. Confirms the managed
# tier-1 binaries exist and are executable, and that ~/.local/bin is on PATH.
# Non-fatal — prints a report and exits 0 so a missing optional tool doesn't abort
# `apply`. (The Docker contract in test/verify.sh is the strict, fatal version.)
set -u

bin_dir="$HOME/.local/bin"
tools="rg fd jq gh uv uvx mise aws"

echo "verify: checking ${bin_dir}"
for t in $tools; do
  if [ -x "$bin_dir/$t" ] || command -v "$t" >/dev/null 2>&1; then
    echo "  ok   $t"
  else
    echo "  MISS $t"
  fi
done

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "verify: WARNING $bin_dir is not on PATH for this shell (open a new shell or source ~/.bashrc)" ;;
esac
