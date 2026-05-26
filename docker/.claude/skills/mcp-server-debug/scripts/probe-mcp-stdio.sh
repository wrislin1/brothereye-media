#!/usr/bin/env bash
# probe-mcp-stdio.sh — send an MCP `initialize` to a stdio command and print
# the first JSON-RPC line received. Exits 0 if a line came back, 2 on no
# response within --wait seconds, 3 on bad usage.
#
# Usage:
#   probe-mcp-stdio.sh [--wait SECONDS] -- <command> [args...]
#   probe-mcp-stdio.sh [--wait SECONDS] "<full shell command>"
set -euo pipefail

WAIT=10
PROTO_VERSION="2024-11-05"

usage() {
  sed -n '2,10p' "$0" >&2
  exit 3
}

if [ "${1:-}" = "--wait" ]; then
  shift
  [ $# -ge 1 ] || usage
  WAIT="$1"
  shift
fi
[ $# -ge 1 ] || usage

if [ "${1:-}" = "--" ]; then
  shift
  [ $# -ge 1 ] || usage
  MODE=argv
else
  if [ $# -ne 1 ]; then
    echo "probe-mcp-stdio: pass argv via '--' or one shell string" >&2
    usage
  fi
  MODE=shell
fi

INIT_MSG=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"%s","capabilities":{},"clientInfo":{"name":"probe-mcp-stdio","version":"0"}}}' "$PROTO_VERSION")

OUT_FILE=$(mktemp -t mcp-probe.XXXXXX)
ERR_FILE=$(mktemp -t mcp-probe.XXXXXX)
trap 'rm -f "$OUT_FILE" "$ERR_FILE"' EXIT

run_target() {
  if [ "$MODE" = "argv" ]; then
    "$@" >"$OUT_FILE" 2>"$ERR_FILE"
  else
    bash -c "$1" >"$OUT_FILE" 2>"$ERR_FILE"
  fi
}

( printf '%s\n' "$INIT_MSG"; sleep "$WAIT" ) | run_target "$@" &
RUNNER_PID=$!

START=$(date +%s)
DEADLINE=$(( START + WAIT + 2 ))
FIRST_LINE=""
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -s "$OUT_FILE" ]; then
    FIRST_LINE=$(head -1 "$OUT_FILE")
    if [ -n "$FIRST_LINE" ]; then
      break
    fi
  fi
  sleep 0.1
done

kill "$RUNNER_PID" 2>/dev/null || true
wait "$RUNNER_PID" 2>/dev/null || true

if [ -z "$FIRST_LINE" ]; then
  echo "probe-mcp-stdio: NO RESPONSE within ${WAIT}s" >&2
  if [ -s "$ERR_FILE" ]; then
    echo "--- stderr ---" >&2
    head -40 "$ERR_FILE" >&2
  fi
  exit 2
fi

echo "$FIRST_LINE"

case "$FIRST_LINE" in
  '{'*) : ;;
  *)
    echo "probe-mcp-stdio: WARNING first line is not JSON" >&2
    ;;
esac
