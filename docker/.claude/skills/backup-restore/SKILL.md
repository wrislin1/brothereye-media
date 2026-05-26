---
name: backup-restore
description: Plan or verify media server backup and restore coverage for Git-tracked configs, .env secrets, Docker volumes, and media library paths.
argument-hint: [inventory|restore-plan]
disable-model-invocation: true
allowed-tools: Bash
---

Run from `/opt/brothereye-media`. Manual invocation only.

Use this to inventory backup coverage or produce a restore order. This skill should not run destructive restore commands unless the user explicitly asks and confirms the target.

## Inventory

```bash
echo "=== git tracked configs ==="
git ls-files

echo "=== local secret/state files that need separate secure backup ==="
for p in docker/.env docker/.env.production secrets/; do
  [[ -e "$p" ]] && ls -l "$p" || echo "missing $p"
done

echo "=== docker volumes ==="
docker volume ls

echo "=== compose services ==="
docker compose -f docker/docker-compose.yml config --services 2>/dev/null || true

echo "=== media library paths (check mount points) ==="
df -h | grep -E '(media|movies|tv|downloads|nzbget)' || echo "(no media mounts detected — verify manually)"
```

## Restore Order

1. Clone the repo.
2. Restore `.env`, `.env.production`, and `secrets/` from secure backup (NOT from Git).
3. Restore Docker volumes for services with persistent state:
   - Jellyfin (library metadata, users, watch history)
   - Sonarr/Radarr (databases, custom formats, profiles)
   - Prowlarr (indexer configs)
   - Bazarr (subtitle configs)
   - NZBGet (queue state)
4. Verify media library mount points are available.
5. Start the stack: `docker compose up -d`
6. Verify with `/docker-stack-health`.

## What needs backup vs. what doesn't

| Component | Needs backup? | Why |
|---|---|---|
| `.env` / `.env.production` | YES (secure) | API keys, credentials — not in git |
| `secrets/` | YES (secure) | Encrypted secrets |
| Jellyfin volume | YES | User data, watch history, metadata |
| Sonarr/Radarr volumes | YES | Databases, custom formats |
| Prowlarr volume | YES | Indexer configurations |
| NZBGet volume | OPTIONAL | Queue can be rebuilt |
| Gluetun config | In git | VPN provider config |
| Media files | SEPARATE | Large; use NAS/RAID, not Docker backup |
| Docker images | NO | Re-pulled on `docker compose pull` |
