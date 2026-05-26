#!/usr/bin/env bash
# Collect lightweight ground-truth context for /session-summary.
# Best-effort: always exits 0 with whatever it could gather.
set -uo pipefail

emit() { printf '%s\n' "$*"; }

emit "### Working directory"
emit "- \`$(pwd)\`"
emit

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit "### Repo"
  remote="$(git remote get-url origin 2>/dev/null || echo '(no origin)')"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  emit "- remote: \`$remote\`"
  emit "- branch: \`$branch\`"
  emit

  emit "### Uncommitted changes (\`git status --short\`)"
  emit '```'
  git status --short 2>/dev/null || echo "(none / not a repo)"
  emit '```'
  emit

  emit "### Diffstat (uncommitted)"
  emit '```'
  git diff --stat 2>/dev/null || true
  emit '```'
  emit

  emit "### Recent commits (last 10)"
  emit '```'
  git log --oneline -10 2>/dev/null || echo "(no commits)"
  emit '```'
  emit

  for base in origin/main origin/master main master; do
    if git rev-parse --verify "$base" >/dev/null 2>&1; then
      emit "### Ahead of \`$base\` (\`git diff --stat $base..HEAD\`)"
      emit '```'
      git diff --stat "$base..HEAD" 2>/dev/null || true
      emit '```'
      emit
      break
    fi
  done
else
  emit "### Repo"
  emit "- (not inside a git work tree)"
  emit
fi
