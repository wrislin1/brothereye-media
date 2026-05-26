#!/usr/bin/env bash
# Verify that a running container has the same source files as the host build context.
#
# Usage:
#   verify-image-freshness.sh <service> [relpath]
#
# Exit codes:
#   0   identical — running image matches host source.
#   1   drift    — host and container differ; rebuild is needed.
#   2   setup failure.
set -euo pipefail

if [[ $# -lt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: verify-image-freshness.sh <service> [relpath]" >&2
  exit 2
fi

svc="$1"
relpath="${2:-}"

COMPOSE_DIR="/opt/brothereye-media/docker"
cd "$COMPOSE_DIR" 2>/dev/null \
  || { echo "verify-image-freshness: compose dir not found" >&2; exit 2; }

if ! docker ps --format '{{.Names}}' | grep -qx "$svc"; then
  echo "verify-image-freshness: container '$svc' is not running" >&2
  exit 2
fi

ctx="$(docker compose config --format json 2>/dev/null \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
svc = d.get('services', {}).get('$svc', {})
build = svc.get('build')
if isinstance(build, str):
    print(build)
elif isinstance(build, dict):
    print(build.get('context', ''))
" 2>/dev/null)" || ctx=""

if [[ -z "$ctx" || ! -d "$ctx" ]]; then
  echo "verify-image-freshness: could not resolve build context for '$svc'" >&2
  exit 2
fi

workdir="$(docker inspect "$svc" --format '{{.Config.WorkingDir}}' 2>/dev/null)"
[[ -n "$workdir" ]] || workdir="/app"

if [[ -z "$relpath" ]]; then
  relpath="$(cd "$ctx" && find . -type f \
      \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.sh' \) \
      -not -path './.*' -not -path './node_modules/*' -not -path './__pycache__/*' \
      -printf '%T@ %P\n' 2>/dev/null \
    | sort -rn | head -1 | cut -d' ' -f2-)"
  if [[ -z "$relpath" ]]; then
    echo "verify-image-freshness: no probe file found under $ctx" >&2
    exit 2
  fi
  echo "probe (auto-picked): $relpath" >&2
fi

host_file="$ctx/$relpath"
if [[ ! -r "$host_file" ]]; then
  echo "verify-image-freshness: host file not readable: $host_file" >&2
  exit 2
fi

container_path="$workdir/$relpath"
container_sha="$(docker exec "$svc" sha256sum "$container_path" 2>/dev/null | awk '{print $1}')"
if [[ -z "$container_sha" ]]; then
  echo "verify-image-freshness: could not read $container_path in '$svc'" >&2
  exit 2
fi

host_sha="$(sha256sum "$host_file" | awk '{print $1}')"

if [[ "$host_sha" == "$container_sha" ]]; then
  echo "PASS: $svc:$container_path matches host $host_file"
  exit 0
fi

cat >&2 <<EOF
DRIFT: $svc is running a different version of $relpath than the host.
  host sha256:      $host_sha
  container sha256: $container_sha

Rebuild: docker compose build $svc && docker compose up -d $svc
EOF
exit 1
