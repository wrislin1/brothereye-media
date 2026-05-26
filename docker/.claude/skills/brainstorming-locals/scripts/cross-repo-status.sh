#!/usr/bin/env bash
# Cross-repo recon for multi-repo reviews.
#
# Prints, for each path supplied: working dir, remote, branch, HEAD,
# ahead-of-origin count, uncommitted file list, and last 5 commits.
#
# Usage:
#   cross-repo-status.sh /opt/brothereye-media /home/mediauser/riz-llm/brothereye
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <repo-path> [<repo-path> ...]" >&2
  exit 2
fi

bold()    { printf '\033[1m%s\033[0m\n' "$*"; }
section() { echo; bold "=== $* ==="; }

for repo in "$@"; do
  if [[ ! -d "$repo/.git" ]]; then
    section "$repo"
    echo "(not a git repo)"
    continue
  fi
  section "$repo"
  (
    cd "$repo"
    remote=$(git config --get remote.origin.url 2>/dev/null || echo "(no origin)")
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(detached)")
    head=$(git log -1 --format='%h %s' 2>/dev/null || echo "(no commits)")
    echo "remote: $remote"
    echo "branch: $branch"
    echo "HEAD:   $head"

    if git rev-parse --verify "@{u}" >/dev/null 2>&1; then
      ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo "?")
      behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo "?")
      echo "ahead/behind origin: $ahead/$behind"
    else
      echo "ahead/behind origin: (no upstream)"
    fi

    echo
    echo "uncommitted (git status --short):"
    status=$(git status --short 2>/dev/null || true)
    if [[ -z "$status" ]]; then
      echo "  (clean)"
    else
      echo "$status" | sed 's/^/  /'
    fi

    echo
    echo "last 5 commits:"
    git log --oneline -5 2>/dev/null | sed 's/^/  /' || echo "  (none)"
  )
done
