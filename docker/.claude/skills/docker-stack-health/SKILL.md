---
name: docker-stack-health
description: Produce a concise read-only health report for the media server Docker stack, including container state, key HTTP endpoints, and logs for unhealthy services.
allowed-tools: Bash
---

Run from `/opt/brothereye-media/docker`.

Use this for broad stack triage before debugging individual services.

## Check

```bash
echo "=== container states ==="
docker compose ps -a 2>/dev/null || docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo "=== unhealthy or exited ==="
docker ps -a --filter "status=exited" --filter "status=restarting" --format '{{.Names}}: {{.Status}}' 2>/dev/null

echo "=== endpoint checks ==="
for svc in jellyfin:8096 sonarr:8989 radarr:7878 prowlarr:9696 bazarr:6767 jellyseerr:5055 nzbget:6789; do
  name="${svc%%:*}"
  port="${svc##*:}"
  code=$(curl -so /dev/null -w '%{http_code}' --max-time 5 "http://localhost:$port" 2>/dev/null || echo "000")
  if [[ "$code" == "000" ]]; then
    echo "  $name (:$port) — UNREACHABLE"
  elif [[ "$code" =~ ^[23] ]]; then
    echo "  $name (:$port) — OK ($code)"
  else
    echo "  $name (:$port) — ERROR ($code)"
  fi
done

echo "=== recent logs for failing containers ==="
for ctr in $(docker ps -a --filter "status=exited" --filter "status=restarting" --format '{{.Names}}' 2>/dev/null); do
  echo "--- $ctr ---"
  docker logs --tail 30 "$ctr" 2>&1 | tail -20
done
```

## Report

- Containers that are unhealthy, exited, or restarting.
- Endpoint failures for Jellyfin, Sonarr, Radarr, Prowlarr, Bazarr, Jellyseerr, NZBGet.
- Recent logs only for failing containers.

Do not restart containers from this skill. If a restart is warranted, state the exact command and ask for confirmation.

## After a rebuild — verify the image is fresh

`docker compose up -d` does not always replace the image. The container can stay healthy while running a previous build. Before claiming "the new code is live," compare:

```bash
scripts/verify-image-freshness.sh <service>
```

Exit 0 = identical, 1 = drift (with rebuild command), 2 = setup failure.

## Service-specific notes

### Gluetun (VPN container)
- *arr services route through Gluetun for download privacy.
- If downloads stall but the UI is responsive, check Gluetun first: `docker logs gluetun --tail 50 2>&1 | grep -iE 'error|warn|reconnect'`
- VPN connectivity: `docker exec gluetun curl -s ifconfig.me` should return a non-local IP.

### Jellyfin transcoding
- If Jellyfin reports unhealthy but is still serving, check transcoding temp dir space.
- Hardware transcoding requires the render group and device passthrough in compose.

### Port-binding edits need `--force-recreate`
`docker compose up -d` will replace a service when its image or environment changes, but a port-binding-only diff sometimes leaves the old binding in place. After editing `ports:` entries, run `docker compose up -d --force-recreate <service>`.
