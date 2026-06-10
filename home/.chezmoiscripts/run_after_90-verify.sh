#!/bin/sh
# Shared (OS-agnostic), plain sh: post-apply sanity check. Every managed binary
# exists and is executable, and ~/.local/bin is on PATH. Non-fatal — prints a
# report and exits 0 so a missing optional tool doesn't abort `apply`.
set -u

bin_dir="$HOME/.local/bin"
tools="rg fd jq gh aws uv uvx fnm"

echo "verify: checking ${bin_dir}"
for t in $tools; do
  if [ -x "$bin_dir/$t" ]; then
    echo "  ok   $t"
  else
    echo "  MISS $t  (expected $bin_dir/$t)"
  fi
done

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "verify: WARNING $bin_dir is not on PATH for this shell (open a new shell or source ~/.bashrc)" ;;
esac
