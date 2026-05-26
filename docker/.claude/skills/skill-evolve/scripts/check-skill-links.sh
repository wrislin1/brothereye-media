#!/usr/bin/env bash
# Verify all skill directories have a SKILL.md file.
set -euo pipefail

skills_dir="$(cd "$(dirname "$0")/../.." && pwd)"
status=0

if [[ ! -d "$skills_dir" ]]; then
  echo "missing skill directory: .claude/skills" >&2
  exit 1
fi

shopt -s nullglob
for entry in "$skills_dir"/*/; do
  name="$(basename "$entry")"
  if [[ ! -f "$entry/SKILL.md" ]]; then
    echo "$name: missing SKILL.md" >&2
    status=1
  fi
done
shopt -u nullglob

if [[ "$status" == 0 ]]; then
  echo "skill structure OK — all skills have SKILL.md"
fi
exit "$status"
