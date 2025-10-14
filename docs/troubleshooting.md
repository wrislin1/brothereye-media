# 🔧 Brother Eye Media Stack - Troubleshooting Guide

Systematic approaches to diagnose and resolve common issues.

---

## 📋 Table of Contents

1. [General Debugging Approach](#general-debugging-approach)
2. [NFS and Storage Issues](#nfs-and-storage-issues)
3. [VPN and Gluetun Issues](#vpn-and-gluetun-issues)
4. [Docker and Networking Issues](#docker-and-networking-issues)
5. [Permission Issues](#permission-issues)
6. [GPU Passthrough Issues](#gpu-passthrough-issues)
7. [Service Communication Issues](#service-communication-issues)
8. [Performance Issues](#performance-issues)
9. [Container Issues](#container-issues)
10. [Backup and Recovery](#backup-and-recovery)

---

## General Debugging Approach

### Systematic Troubleshooting Steps

**1. Identify the Layer:**
```
Application → Docker → LXC → Proxmox → Network → Storage
```

**2. Check from Bottom Up:**
- Network connectivity (can hosts ping each other?)
- Storage access (is NFS mounted?)
- Container status (is LXC running?)
- Docker status (are containers up?)
- Application logs (what errors are shown?)

**3. Essential Commands:**

```bash
# Network
ping 192.168.70.10          # Can reach NAS?
ping 192.168.80.110         # Can reach LXC?

# Storage
df -h | grep nas            # Is NFS mounted?
ls -la /mnt/pve/nas         # Can list files?

# LXC
pct status 110              # Is container running?
pct enter 110               # Enter to investigate

# Docker
docker compose ps           # All containers up?
docker compose logs -f      # Live logs
docker stats                # Resource usage

# Services
curl http://localhost:8096  # Is Jellyfin responding?
```

### Log Locations

```bash
# Proxmox logs
journalctl -xe
cat /var/log/syslog

# LXC logs
pct enter 110
journalctl -u docker

# Docker logs
docker compose logs <service>
docker logs <container-name>

# Application logs (inside containers)
docker exec jellyfin cat /config/logs/jellyfin*.log
docker exec sonarr cat /config/logs/sonarr.txt
```

---

## NFS and Storage Issues

### Issue: NFS Mount Fails on Proxmox Host

**Symptoms:**
```bash
mount -t nfs4 192.168.70.10:/export/Media /mnt/pve/nas
mount.nfs4: mounting 192.168.70.10:/export/Media failed, 
reason given by server: No such file or directory
```

**Diagnosis:**
```bash
# Check if NAS is reachable
ping -c 3 192.168.70.10

# Check NFS exports on NAS
showmount -e 192.168.70.10
```

**Solution:**

This is the **NFSv4 pseudofilesystem issue**. When `/export` has `fsid=0`, you must mount the root:

```bash
# WRONG:
mount -t nfs4 192.168.70.10:/export/Media /mnt/pve/nas

# CORRECT:
mount -t nfs4 192.168.70.10:/ /mnt/pve/nas

# Verify mount
df -h | grep nas
ls -la /mnt/pve/nas/Media
```

**Permanent Fix:**
```bash
# Add to /etc/fstab
echo "192.168.70.10:/ /mnt/pve/nas nfs4 nfsvers=4,hard,intr,rsize=8192,wsize=8192,timeo=14 0 0" >> /etc/fstab

# Test fstab
mount -a
```

### Issue: NFS Mount "Stale File Handle"

**Symptoms:**
```bash
ls /mnt/pve/nas
ls: cannot access '/mnt/pve/nas': Stale file handle
```

**Diagnosis:**
```bash
# Check if NFS server restarted
systemctl status nfs-server  # On NAS

# Check mount status
mount | grep nas
```

**Solution:**
```bash
# Unmount stale mount
umount -f /mnt/pve/nas

# Remount
mount -a

# Verify
df -h | grep nas
```

**Prevention:**
```bash
# Use 'hard' mount option (already in fstab)
# hard mount will hang rather than error on network issues
# This prevents stale handles but may cause hangs
```

### Issue: Storage Not Visible in LXC Container

**Symptoms:**
```bash
pct enter 110
ls /mnt/media
# Empty or doesn't exist
```

**Diagnosis:**
```bash
# On Proxmox host, check if NFS is mounted
df -h | grep nas

# Check LXC bind mount configuration
pct config 110 | grep mp

# Expected:
# mp0: /mnt/pve/nas/Media,mp=/mnt/media
# mp1: /mnt/pve/nas/Downloads,mp=/mnt/downloads
```

**Solution:**

If bind mounts are missing:

```bash
# Stop container
pct stop 110

# Add bind mounts
pct set 110 -mp0 /mnt/pve/nas/Media,mp=/mnt/media
pct set 110 -mp1 /mnt/pve/nas/Downloads,mp=/mnt/downloads

# Start container
pct start 110

# Verify
pct enter 110
df -h | grep mnt
ls -la /mnt/media
```

If bind mounts exist but directories are empty:

```bash
# Verify Proxmox host has files
ls -la /mnt/pve/nas/Media

# If host has files but LXC doesn't:
pct restart 110
```

### Issue: Permission Denied in LXC/Docker

**Symptoms:**
```bash
docker compose logs sonarr
# Permission denied: '/media/TV/ShowName'
```

**Diagnosis:**
```bash
# Check ownership on Proxmox host
ls -la /mnt/pve/nas/Media

# Check user in LXC
pct exec 110 -- id mediauser

# Check Docker PUID/PGID
pct exec 110 -- cat /opt/media-stack/.env | grep PUID
```

**Solution:**

Ensure UID/GID consistency:

```bash
# On NAS: Files should be owned by GID 100 (users)
# On LXC: mediauser should be UID 1000, GID 100
# In Docker: PUID=1000, PGID=100

# Fix LXC user if needed
pct enter 110
usermod -u 1000 mediauser
groupmod -g 100 users

# Fix Docker .env if needed
nano /opt/media-stack/.env
# Set: PUID=1000, PGID=100

# Restart stack
docker compose restart
```

---

## VPN and Gluetun Issues

### Issue: VPN Not Routing NZBGet Traffic

**Symptoms:**
```bash
docker compose exec nzbget curl -s ifconfig.me
# Shows home IP instead of VPS IP
```

**Diagnosis:**
```bash
# Check Gluetun status
docker compose ps gluetun

# Check Gluetun logs
docker compose logs gluetun | tail -50

# Look for:
# "Wireguard is up"
# Or errors like "handshake failed"
```

**Solution:**

**If Gluetun is not up:**

```bash
# Check .env has correct VPN credentials
cat /opt/media-stack/.env | grep WIREGUARD

# Verify values:
# WIREGUARD_PRIVATE_KEY=your_key
# WIREGUARD_ENDPOINT_IP=your_vps_ip
# WIREGUARD_PUBLIC_KEY=vps_public_key

# Restart Gluetun
docker compose restart gluetun

# Wait 10 seconds
sleep 10

# Check logs
docker compose logs gluetun | grep -i "wireguard"

# Test again
docker compose exec nzbget curl -s ifconfig.me
```

**If credentials are wrong:**

```bash
# Fix .env
nano /opt/media-stack/.env

# Update WIREGUARD_* values

# Recreate container
docker compose up -d gluetun

# Test
docker compose exec nzbget curl -s ifconfig.me
```

### Issue: VPN Kill-Switch Not Working

**Symptoms:**
```bash
# Stop VPN
docker compose stop gluetun

# NZBGet still downloads (BAD!)
docker compose exec nzbget curl -s ifconfig.me
# Shows home IP
```

**Diagnosis:**

This means the kill-switch failed. NZBGet should **not** have internet when VPN is down.

**Solution:**

Verify NZBGet is using Gluetun's network:

```bash
# Check docker-compose.yml
cat docker/compose/nzbget.yml

# Should have:
# network_mode: "service:gluetun"
# NOT: networks: [media-network]

# If wrong, fix and recreate:
nano docker/compose/nzbget.yml
docker compose up -d nzbget
```

**Test Kill-Switch:**

```bash
# Stop VPN
docker compose stop gluetun

# Try to access internet from NZBGet
docker compose exec nzbget ping -c 3 8.8.8.8
# Should FAIL (timeout)

# Try to get IP
docker compose exec nzbget curl -s --max-time 5 ifconfig.me
# Should FAIL (timeout)

# If these succeed, kill-switch is broken. Re-check network_mode.

# Start VPN
docker compose start gluetun
sleep 10

# Now should work
docker compose exec nzbget curl -s ifconfig.me
# Should show VPS IP
```

### Issue: VPN Connected but NZBGet Can't Download

**Symptoms:**
- Gluetun logs show "Wireguard is up"
- NZBGet shows VPS IP
- But downloads fail with connection errors

**Diagnosis:**
```bash
# Check if DNS is working
docker compose exec nzbget nslookup google.com

# Check if ports are blocked
docker compose exec nzbget curl -v news.newshosting.com:443
```

**Solution:**

**DNS Issue:**
```bash
# Edit Gluetun config to use custom DNS
nano docker/compose/gluetun.yml

# Add environment variable:
environment:
  - DNS_ADDRESS=1.1.1.1

# Restart
docker compose up -d gluetun
```

**Firewall Issue on VPS:**
```bash
# On your VPS, ensure WireGuard allows all outbound
iptables -L -n -v
# Should have: ACCEPT all anywhere anywhere

# If blocked, fix on VPS
```

---

## Docker and Networking Issues

### Issue: Containers Can't Communicate

**Symptoms:**
```bash
docker compose logs sonarr
# Error: Connection refused: http://nzbget:6789
```

**Diagnosis:**
```bash
# Check if both containers are on same network
docker network inspect media-network

# Check if NZBGet is reachable
docker compose exec sonarr ping nzbget

# Special case: NZBGet uses gluetun network
docker compose exec sonarr ping gluetun
```

**Solution:**

**For NZBGet (uses Gluetun network):**

Other services must connect to **gluetun**, not **nzbget**:

```bash
# In Sonarr/Radarr settings:
# Download Client Host: gluetun
# Port: 6789
```

**For other services:**

Ensure they're on the media-network:

```bash
# Check compose file
cat docker/compose/sonarr.yml

# Should have:
networks:
  - media-network

# If missing, add and recreate
docker compose up -d sonarr
```

### Issue: Docker Compose Fails to Start

**Symptoms:**
```bash
docker compose up -d
# Error: invalid compose file
```

**Diagnosis:**
```bash
# Validate compose file
docker compose config

# Check syntax errors
# Often: indentation, missing quotes, wrong include paths
```

**Common Errors:**

**1. Include path wrong:**
```yaml
# WRONG:
include:
  - gluetun.yml

# CORRECT:
include:
  - compose/gluetun.yml
```

**2. Missing .env file:**
```bash
# Check if .env exists
ls -la /opt/media-stack/.env

# If missing, copy from example
cp docker/.env.example /opt/media-stack/.env
```

**3. Indentation error:**
```yaml
# WRONG (mixed spaces and tabs):
services:
	jellyfin:
  image: ...

# CORRECT (spaces only):
services:
  jellyfin:
    image: ...
```

### Issue: Port Already in Use

**Symptoms:**
```bash
docker compose up -d
# Error: bind: address already in use (port 8096)
```

**Diagnosis:**
```bash
# Find what's using the port
lsof -i :8096
# Or
ss -tulpn | grep 8096
```

**Solution:**

```bash
# If it's an old container
docker ps -a | grep 8096
docker rm -f <container-id>

# If it's another service
systemctl stop <service-name>

# Try again
docker compose up -d
```

---

## Permission Issues

### Issue: Sonarr/Radarr Can't Move Files

**Symptoms:**
```bash
# In Sonarr logs:
Permission denied: '/media/TV/Show Name/episode.mkv'
```

**Diagnosis:**
```bash
# Check file ownership
pct exec 110 -- ls -la /mnt/media/TV

# Check Docker user
docker compose exec sonarr id

# Should be: uid=1000(abc) gid=100(users)
```

**Solution:**

**Fix UID/GID in .env:**
```bash
nano /opt/media-stack/.env

# Ensure:
PUID=1000
PGID=100

# Restart affected containers
docker compose restart sonarr radarr
```

**Fix NAS permissions (if needed):**
```bash
# On NAS
chown -R 1000:100 /srv/.../Media
chmod -R 775 /srv/.../Media
```

### Issue: Jellyfin Can't Read Media Files

**Symptoms:**
- Media library scan finds 0 items
- Or: "Unable to read file"

**Diagnosis:**
```bash
# Check if mount is visible
docker compose exec jellyfin ls -la /media

# Check permissions
docker compose exec jellyfin cat /media/Movies/test.mkv
# Should NOT error
```

**Solution:**

**If mount is empty:**
```bash
# Verify LXC mount
pct exec 110 -- df -h | grep media

# If missing, fix bind mount (see Storage Issues)
```

**If permission denied:**
```bash
# Jellyfin should have read access
# Check .env PUID/PGID (should be 1000/100)

# Check mount is readable
docker compose exec jellyfin test -r /media/Movies && echo "OK"
```

---

## GPU Passthrough Issues

### Issue: GPU Not Visible in Jellyfin

**Symptoms:**
- Jellyfin Dashboard → Playback → Hardware Acceleration: VAAPI not listed
- Or transcoding uses CPU

**Diagnosis:**
```bash
# Check if GPU is in container
pct exec 110 -- ls -l /dev/dri

# Should show:
# crw-rw---- card1
# crw-rw---- renderD128
```

**Solution:**

**If devices missing in LXC:**

```bash
# Stop container
pct stop 110

# Pass GPU devices
pct set 110 -dev0 /dev/dri/card1,gid=104
pct set 110 -dev1 /dev/dri/renderD128,gid=104

# Start container
pct start 110

# Verify
pct exec 110 -- ls -l /dev/dri
```

**If devices in LXC but not in Jellyfin:**

Check Docker mount:

```bash
cat docker/compose/jellyfin.yml

# Should have:
devices:
  - /dev/dri:/dev/dri
group_add:
  - "104"  # render group

# If missing, add and recreate
docker compose up -d jellyfin
```

**Verify inside Jellyfin container:**

```bash
docker compose exec jellyfin ls -l /dev/dri
docker compose exec jellyfin vainfo
# Should show codec support
```

### Issue: VAAPI Transcoding Fails

**Symptoms:**
- Playback starts but stops after a few seconds
- Jellyfin logs: "Failed to initialize VAAPI"

**Diagnosis:**
```bash
# Check if VAAPI drivers are installed
docker compose exec jellyfin vainfo

# Should show:
# libva info: VA-API version 1.x
# libva info: Driver: radeonsi (or i965, iHD)
```

**Solution:**

**If vainfo fails:**

```bash
# Jellyfin container should have drivers pre-installed
# If not, check image version
docker compose pull jellyfin
docker compose up -d jellyfin
```

**Check Jellyfin config:**

```
Dashboard → Playback → Transcoding
  Hardware acceleration: VAAPI
  VA API Device: /dev/dri/renderD128  (NOT card1)
  Enable hardware decoding: All formats
```

**Test transcode:**
```bash
# Play a video, select a lower quality
# Monitor GPU usage on host:
intel_gpu_top  # Intel
radeontop      # AMD
nvidia-smi     # Nvidia
```

---

## Service Communication Issues

### Issue: Sonarr Can't Connect to NZBGet

**Symptoms:**
```bash
# Sonarr: Settings → Download Clients → Test
Error: Connection refused
```

**Diagnosis:**
```bash
# From Sonarr container, test connectivity
docker compose exec sonarr ping gluetun
docker compose exec sonarr curl http://gluetun:6789

# If fails, NZBGet or Gluetun is down
```

**Solution:**

**Use correct hostname:**
```
Sonarr → Download Clients → NZBGet
  Host: gluetun  (NOT nzbget, NOT localhost)
  Port: 6789
```

**Ensure Gluetun publishes port:**
```yaml
# docker/compose/gluetun.yml
services:
  gluetun:
    ports:
      - "6789:6789"  # Must publish NZBGet port
```

### Issue: Prowlarr Can't Sync to Sonarr/Radarr

**Symptoms:**
```bash
# Prowlarr: Apps → Sync
Error: Unable to connect
```

**Diagnosis:**
```bash
# Test from Prowlarr
docker compose exec prowlarr curl http://sonarr:8989
docker compose exec prowlarr curl http://radarr:7878
```

**Solution:**

**Check API keys:**
```
Prowlarr → Settings → Apps → Sonarr
  URL: http://sonarr:8989
  API Key: <get from Sonarr Settings → General>
```

**Verify networks:**
```bash
# All should be on media-network
docker inspect sonarr | grep NetworkMode
docker inspect prowlarr | grep NetworkMode
```

### Issue: Jellyfin Not Showing New Media

**Symptoms:**
- Sonarr/Radarr import succeeds
- Files are in /mnt/media
- Jellyfin doesn't show them

**Diagnosis:**
```bash
# Check if Jellyfin sees the files
docker compose exec jellyfin ls /media/TV/ShowName

# Check Jellyfin logs
docker compose logs jellyfin | grep -i error
```

**Solution:**

**Manual scan:**
```
Jellyfin → Dashboard → Libraries → Scan All Libraries
```

**Enable automatic scanning:**
```
Dashboard → Libraries → [Your Library] → Manage → 
  Enable: "Scan library on a schedule"
```

**Configure Sonarr/Radarr to notify Jellyfin:**
```
Sonarr → Settings → Connect → Add → Jellyfin
  Host: jellyfin
  Port: 8096
  API Key: <from Jellyfin Dashboard → API Keys>
  On Import: Checked
```

---

## Performance Issues

### Issue: Slow NFS Performance

**Symptoms:**
- File copies very slow (<50 MB/s)
- Media playback buffers

**Diagnosis:**
```bash
# Test NFS speed
dd if=/dev/zero of=/mnt/pve/nas/Media/test bs=1M count=1000
# Should see >100 MB/s on Gigabit

# Check network
iperf3 -s  # On NAS
iperf3 -c 192.168.70.10  # On Proxmox
```

**Solution:**

**Optimize NFS mount options:**
```bash
# Edit /etc/fstab
nano /etc/fstab

# Use:
192.168.70.10:/ /mnt/pve/nas nfs4 nfsvers=4,rsize=131072,wsize=131072,hard,intr,noatime 0 0

# Remount
umount /mnt/pve/nas
mount -a
```

**Check network:**
```bash
# Verify Gigabit link
ethtool eth0 | grep Speed
# Should show: Speed: 1000Mb/s

# Check for errors
ifconfig | grep errors
```

### Issue: High CPU Usage During Transcode

**Symptoms:**
- CPU at 100% when streaming
- Video playback stutters

**Diagnosis:**
```bash
# Check if GPU is being used
docker compose exec jellyfin cat /config/logs/jellyfin*.log | grep -i vaapi

# Monitor during playback
top
# If ffmpeg is at 100%, GPU not working
```

**Solution:**

See [GPU Passthrough Issues](#gpu-passthrough-issues) above.

### Issue: Container Using Too Much Memory

**Symptoms:**
```bash
docker stats
# One container using 8+ GB
```

**Solution:**

**Set memory limits:**
```yaml
# docker/compose/<service>.yml
services:
  <service>:
    deploy:
      resources:
        limits:
          memory: 2G
```

**Restart container:**
```bash
docker compose up -d <service>
```

---

## Container Issues

### Issue: Container Keeps Restarting

**Symptoms:**
```bash
docker compose ps
# Container shows "Restarting (1) 5 seconds ago"
```

**Diagnosis:**
```bash
# Check logs
docker compose logs <service> | tail -50

# Common causes:
# - Missing .env variables
# - Port conflict
# - Failed health check
# - Permission issue
```

**Solution:**

**Fix based on error in logs:**

```bash
# Missing env var:
nano /opt/media-stack/.env
# Add missing variable

# Port conflict:
lsof -i :<port>
# Kill conflicting process

# Permission:
# See Permission Issues section

# Restart
docker compose up -d <service>
```

### Issue: Cannot Remove Container

**Symptoms:**
```bash
docker rm -f jellyfin
# Error: container is running
```

**Solution:**
```bash
# Stop via compose
docker compose stop jellyfin

# Force remove
docker rm -f jellyfin

# Or remove all stopped containers
docker container prune
```

---

## Backup and Recovery

### Issue: Backup Script Fails

**Symptoms:**
```bash
./scripts/backup-configs.sh
# Error: No such file or directory
```

**Diagnosis:**
```bash
# Check if config directory exists
ls -la /opt/media-stack/config

# Check available disk space
df -h
```

**Solution:**

```bash
# Ensure config directory has data
ls -la /opt/media-stack/config/

# If empty, containers may not have created configs yet
# Start stack first
docker compose up -d

# Wait for containers to initialize
sleep 30

# Try backup again
./scripts/backup-configs.sh
```

### Issue: Restore Fails

**Symptoms:**
```bash
./scripts/restore-configs.sh backup.tar.gz
# Error: cannot overwrite existing files
```

**Solution:**

```bash
# Stop containers first
docker compose down

# Remove existing configs
rm -rf /opt/media-stack/config/*

# Restore
./scripts/restore-configs.sh /path/to/backup.tar.gz

# Start containers
docker compose up -d
```

---

## Quick Reference: Command Cheat Sheet

### Container Management
```bash
# Start all
docker compose up -d

# Stop all
docker compose down

# Restart one service
docker compose restart <service>

# View logs
docker compose logs -f <service>

# Execute command in container
docker compose exec <service> <command>

# See resource usage
docker stats
```

### Diagnostics
```bash
# Full status check
docker compose ps
pct status 110
df -h | grep nas
systemctl status docker

# Network test
ping 192.168.70.10
ping 192.168.80.110

# Check VPN
docker compose exec nzbget curl -s ifconfig.me

# Check GPU
pct exec 110 -- ls -l /dev/dri
```

### Reset Procedures
```bash
# Reset one service (keeps data)
docker compose stop <service>
docker compose rm -f <service>
docker compose up -d <service>

# Reset all (keeps data)
docker compose down
docker compose up -d

# Nuclear option (deletes all data)
docker compose down -v
rm -rf /opt/media-stack/config
rm -rf /opt/media-stack/cache
docker compose up -d
```

---

## Getting Help

If none of these solutions work:

1. **Check logs systematically** (Proxmox → LXC → Docker → Application)
2. **Search GitHub Issues** for Sonarr/Radarr/Jellyfin/etc.
3. **Reddit Communities:** /r/selfhosted, /r/sonarr, /r/jellyfin
4. **Discord Servers:** LinuxServer.io, Jellyfin, Servarr

**When asking for help, provide:**
- Exact error message
- Relevant logs (docker compose logs)
- What you've tried
- Output of diagnostic commands

---

**Most issues are solvable with systematic debugging. Start at the lowest layer (network/storage) and work up!**
