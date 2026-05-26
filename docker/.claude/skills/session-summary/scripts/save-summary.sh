#!/usr/bin/env bash
# Save a session-summary Markdown doc.
# Reads Markdown from stdin; writes to ~/.claude/session-summaries/ by default.
set -euo pipefail

DEST_DIR="${SESSION_SUMMARY_DIR:-$HOME/.claude/session-summaries}"
explicit_path=""
slug_arg=""
echo_saved=0

while (( $# > 0 )); do
  case "$1" in
    -o|--out)  explicit_path="$2"; shift 2 ;;
    --echo)    echo_saved=1; shift ;;
    -h|--help)
      cat <<USAGE
Usage:
  save-summary.sh                 default location, slug derived from first H1
  save-summary.sh --echo          write, then echo path + exact Markdown
  save-summary.sh <slug>          forced slug
  save-summary.sh -o <path>       explicit output path
USAGE
      exit 0 ;;
    *)         slug_arg="$1"; shift ;;
  esac
done

content="$(cat)"
if [[ -z "$content" ]]; then
  echo "save-summary.sh: empty input on stdin; refusing to write empty file" >&2
  exit 2
fi

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' \
    | cut -c1-40
}

if [[ -n "$explicit_path" ]]; then
  out="$explicit_path"
  mkdir -p "$(dirname "$out")"
else
  mkdir -p "$DEST_DIR"
  if [[ -n "$slug_arg" ]]; then
    slug="$(slugify "$slug_arg")"
  else
    first_h1="$(printf '%s' "$content" | awk '/^# /{print substr($0,3); exit}')"
    [[ -n "$first_h1" ]] || first_h1="session"
    slug="$(slugify "$first_h1")"
  fi
  [[ -n "$slug" ]] || slug="session"
  stamp="$(date +%Y-%m-%d-%H%M)"
  base="${stamp}-${slug}.md"
  out="$DEST_DIR/$base"
  n=2
  while [[ -e "$out" ]]; do
    out="$DEST_DIR/${stamp}-${slug}-${n}.md"
    n=$((n+1))
  done
fi

printf '%s' "$content" > "$out"
if [[ "$echo_saved" == 1 ]]; then
  printf 'Saved: %s\n\n' "$out"
  printf '%s' "$content"
else
  printf '%s\n' "$out"
fi
