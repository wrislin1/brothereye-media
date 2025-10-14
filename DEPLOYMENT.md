# 🚀 Brother Eye Media Stack - Deployment Guide

Complete step-by-step guide to deploy the Brother Eye media stack from scratch.

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Phase 1: Repository Setup](#phase-1-repository-setup)
4. [Phase 2: NFS Storage Configuration](#phase-2-nfs-storage-configuration)
5. [Phase 3: LXC Container Creation](#phase-3-lxc-container-creation)
6. [Phase 4: Base System Setup](#phase-4-base-system-setup)
7. [Phase 5: Storage Mounting](#phase-5-storage-mounting)
8. [Phase 6: GPU Passthrough](#phase-6-gpu-passthrough)
9. [Phase 7: Docker Stack Deployment](#phase-7-docker-stack-deployment)
10. [Phase 8: Service Configuration](#phase-8-service-configuration)
11. [Phase 9: Verification & Testing](#phase-9-verification--testing)
12. [Post-Deployment](#post-deployment)
13. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Hardware Requirements

- **Proxmox Host:**
  - 8+ CPU cores (for VM host + LXC)
  - 16+ GB RAM (8 GB for Proxmox, 8+ GB for LXC)
  - 50+ GB storage for LXC root filesystem
  - GPU (optional, for hardware transcoding)

- **NAS:**
  - NFSv4 server configured
  - Sufficient storage for media library
  - Gigabit network connection (minimum)

### Software Requirements

- **Proxmox VE 8.x** installed and configured
- **NAS with NFS exports** (e.g., OpenMediaVault 7)
- **WireGuard VPN endpoint** (your VPS with WireGuard server)
- **Git, GPG, git-crypt** on Proxmox host

### Network Requirements

- **VLAN 80** configured for media services (192.168.80.0/24)
- **VLAN 70** configured for NAS storage (192.168.70.0/24)
- **Static IP assignments:**
  - Proxmox host: 192.168.80.10
  - NAS: 192.168.70.10
  - LXC media-stack: 192.168.80.110
- **Firewall rules** allowing necessary traffic between VLANs
- **DNS resolution** for internal and external queries

### Credentials Needed

Before starting, gather:
- ☐ Usenet provider credentials (Newshosting, Easynews, etc.)
- ☐ WireGuard VPN configuration (private key, endpoint, etc.)
- ☐ Indexer credentials (for Prowlarr)
- ☐ Email for notifications (optional)

---

## Pre-Deployment Checklist

### On Proxmox Host

```bash
# Verify Proxmox version
pveversion

# Check available storage
pvesm status

# Verify Debian 12 template exists
pveam list local | grep debian-12

# If not, download it
pveam download local debian-12-standard_12.12-1_amd64.tar.zst

# Check NFS connectivity to NAS
ping -c 3 192.168.70.10

# Test NFS mount (should list exports)
showmount -e 192.168.70.10
```

### On NAS

```bash
# Verify NFS exports are active
exportfs -v

# Expected output should include:
# /export/Media    192.168.80.10(...)
# /export/Downloads 192.168.80.10(...)
# /export          192.168.80.10(...,fsid=0,...)

# Check NFS service is running
systemctl status nfs-server
```

### Network Verification

```bash
# From Proxmox host, verify routing
ip route | grep 192.168.70.0
ip route | grep 192.168.80.0

# Verify VLAN interfaces
ip addr show | grep vmbr0
```

---

## Phase 1: Repository Setup

### 1.1 Clone Repository

```bash
# On Proxmox host or your management machine
cd /root
git clone git@github.com:YOUR_USERNAME/brother-eye-media-stack.git
cd brother-eye-media-stack
```

### 1.2 Initialize git-crypt

**If this is your first time:**

```bash
# Generate GPG key (if you don't have one)
# Follow prompts in GPG-SETUP.md
gpg --full-generate-key

# Initialize git-crypt
git-crypt init
git-crypt add-gpg-user YOUR_GPG_KEY_ID

# Create production environment file
cp docker/.env.example docker/.env.production
```

**If cloning on another machine:**

```bash
# Import your GPG private key
gpg --import /path/to/brother-eye-gpg-private.asc

# Unlock the repository
git-crypt unlock

# Verify secrets are decrypted
cat docker/.env.production
# Should show readable text, not binary gibberish
```

### 1.3 Configure Environment Variables

```bash
# Edit production environment file
nano docker/.env.production
```

**Fill in these critical values:**
- `WIREGUARD_PRIVATE_KEY` - Your WireGuard client private key
- `WIREGUARD_PUBLIC_KEY` - Your VPS WireGuard server public key
- `WIREGUARD_ENDPOINT_IP` - Your VPS IP address
- `NZBGET_NEWSHOSTING_USERNAME` - Newshosting username
- `NZBGET_NEWSHOSTING_PASSWORD` - Newshosting password
- `NZBGET_EASYNEWS_USERNAME` - Easynews username
- `NZBGET_EASYNEWS_PASSWORD` - Easynews password

**Save and commit (will be encrypted automatically):**
```bash
git add docker/.env.production
git commit -m "Add production credentials (encrypted)"
git push
```

---

## Phase 2: NFS Storage Configuration

### 2.1 Mount NFS on Proxmox Host

**Critical Lesson Learned:** LXC containers cannot mount NFS directly. Mount on Proxmox host first, then bind mount into containers.

```bash
# Create mount point
mkdir -p /mnt/pve/nas

# Test mount manually first
mount -t nfs4 192.168.70.10:/ /mnt/pve/nas

# Verify mount
df -h | grep nas
ls -la /mnt/pve/nas
# Should see: Media/, Downloads/, Backup/

# If successful, add to fstab for persistence
echo "192.168.70.10:/ /mnt/pve/nas nfs4 nfsvers=4,hard,intr,rsize=8192,wsize=8192,timeo=14 0 0" >> /etc/fstab

# Verify fstab
mount -a
df -h | grep nas
```

**Troubleshooting:**
```bash
# If mount fails with "No such file or directory"
# This is NFSv4 pseudofilesystem - mount root, not subdirectories

# WRONG:
mount -t nfs4 192.168.70.10:/export/Media /mnt/pve/nas

# CORRECT:
mount -t nfs4 192.168.70.10:/ /mnt/pve/nas
```

### 2.2 Verify NFS Mount Contents

```bash
# Check permissions
ls -la /mnt/pve/nas/Media
ls -la /mnt/pve/nas/Downloads

# Should show directories owned by your NAS user
# Example: drwxrwsr-x root users ...

# Verify you can write (if needed)
touch /mnt/pve/nas/Downloads/test.txt
rm /mnt/pve/nas/Downloads/test.txt
```

---

## Phase 3: LXC Container Creation

### 3.1 Create LXC Container

```bash
cd /root/brother-eye-media-stack/proxmox

# Make scripts executable
chmod +x *.sh

# Create the container
./create-media-stack-lxc.sh

# Follow prompts and confirm creation
```

**Script creates:**
- **LXC 110** with hostname `media-stack`
- **IP:** 192.168.80.110/24
- **Resources:** 8 cores, 12 GB RAM, 50 GB disk
- **Features:** Nesting enabled (for Docker)

### 3.2 Verify Container Creation

```bash
# Check container status
pct status 110

# List containers
pct list | grep 110

# View configuration
pct config 110
```

### 3.3 Start Container

```bash
# Start the container
pct start 110

# Wait a few seconds for boot
sleep 5

# Verify it's running
pct status 110
```

---

## Phase 4: Base System Setup

### 4.1 Copy Setup Scripts

```bash
# From Proxmox host
cd /root/brother-eye-media-stack

# Copy LXC scripts into container
pct push 110 lxc/setup-base.sh /root/setup-base.sh
pct push 110 lxc/deploy-stack.sh /root/deploy-stack.sh
pct push 110 lxc/manage-stack.sh /root/manage-stack.sh
```

### 4.2 Enter Container and Run Base Setup

```bash
# Enter the container
pct enter 110

# Make scripts executable
chmod +x /root/*.sh

# Run base setup (installs Docker, creates users, directories)
./setup-base.sh

# This will:
# - Update system packages
# - Install Docker and Docker Compose
# - Install NFS client utilities
# - Create mediauser (UID 1000, GID 100)
# - Create /opt/media-stack directory structure
# - Configure Docker logging

# Exit container after setup completes
exit
```

### 4.3 Verify Base Setup

```bash
# From Proxmox host, check inside container
pct exec 110 -- docker --version
pct exec 110 -- docker compose version
pct exec 110 -- id mediauser
pct exec 110 -- ls -la /opt/media-stack
```

---

## Phase 5: Storage Mounting

### 5.1 Stop Container (Required for Bind Mounts)

```bash
# Must stop container to modify mount configuration
pct stop 110

# Wait for complete shutdown
sleep 3
```

### 5.2 Bind Mount NFS into Container

```bash
cd /root/brother-eye-media-stack/proxmox

# Bind mount storage
./bind-mount-storage.sh 110

# This creates two bind mounts:
# Host: /mnt/pve/nas/Media      → LXC: /mnt/media
# Host: /mnt/pve/nas/Downloads  → LXC: /mnt/downloads
```

### 5.3 Verify Mounts Configuration

```bash
# Check LXC configuration
pct config 110 | grep mp

# Expected output:
# mp0: /mnt/pve/nas/Media,mp=/mnt/media
# mp1: /mnt/pve/nas/Downloads,mp=/mnt/downloads
```

### 5.4 Start Container and Verify Mounts

```bash
# Start container
pct start 110

# Wait for boot
sleep 5

# Verify mounts inside container
pct exec 110 -- df -h | grep mnt
pct exec 110 -- ls -la /mnt/media
pct exec 110 -- ls -la /mnt/downloads

# Should see media files and download directories
```

---

## Phase 6: GPU Passthrough

**Optional but recommended for Jellyfin hardware transcoding**

### 6.1 Identify GPU on Host

```bash
# List DRI devices
ls -l /dev/dri

# Expected output (example):
# drwxr-xr-x  2 root root         100 Oct 12 10:00 by-path
# crw-rw----+ 1 root video  226,   0 Oct 12 10:00 card0  # iGPU (Intel/AMD)
# crw-rw----+ 1 root video  226,   1 Oct 12 10:00 card1  # Discrete GPU
# crw-rw----+ 1 root render 226, 128 Oct 12 10:00 renderD128

# Identify which is your target GPU (check with vainfo or similar)
# In this example, card1 is AMD Vega GPU
```

### 6.2 Stop Container and Pass GPU

```bash
# Stop container
pct stop 110

# Pass GPU devices (adjust card number if needed)
./pass-gpu-to-lxc.sh 110

# This runs:
# pct set 110 -dev0 /dev/dri/card1,gid=104
# pct set 110 -dev1 /dev/dri/renderD128,gid=104

# Start container
pct start 110
sleep 5
```

### 6.3 Verify GPU Inside Container

```bash
# Check GPU devices inside container
pct exec 110 -- ls -l /dev/dri

# Should see:
# crw-rw---- 1 root video  226,   1 Oct 12 10:00 card1
# crw-rw---- 1 root render 226, 128 Oct 12 10:00 renderD128

# Verify mediauser has access
pct exec 110 -- su - mediauser -c "ls -l /dev/dri"
```

---

## Phase 7: Docker Stack Deployment

### 7.1 Copy Docker Compose Files

```bash
# From Proxmox host
cd /root/brother-eye-media-stack

# Copy all Docker files to container
pct push 110 docker/docker-compose.yml /opt/media-stack/docker-compose.yml
pct push 110 docker/.env.production /opt/media-stack/.env
pct push 110 -r docker/compose /opt/media-stack/compose

# Verify files are in place
pct exec 110 -- ls -la /opt/media-stack/
```

### 7.2 Deploy the Stack

```bash
# Enter container
pct enter 110

# Navigate to stack directory
cd /opt/media-stack

# Run deployment script
./deploy-stack.sh

# This will:
# - Verify prerequisites (Docker, mounts, .env)
# - Pull all container images
# - Start all services with docker compose up -d
# - Show service status
```

### 7.3 Monitor Initial Startup

```bash
# Watch all container logs
docker compose logs -f

# Press Ctrl+C when you see services are up

# Check status
docker compose ps

# All services should show "Up" (healthy status)
```

### 7.4 Verify Each Service Started

```bash
# Individual service checks
docker compose ps gluetun      # VPN should be Up
docker compose ps nzbget       # Downloader should be Up
docker compose ps jellyfin     # Media server should be Up
docker compose ps sonarr       # TV automation should be Up
docker compose ps radarr       # Movie automation should be Up
docker compose ps prowlarr     # Indexer manager should be Up
docker compose ps bazarr       # Subtitles should be Up
docker compose ps jellyseerr   # Requests should be Up

# Check for any errors
docker compose logs --tail=50 | grep -i error
```

---

## Phase 8: Service Configuration

### 8.1 Verify VPN is Working (Critical!)

```bash
# Inside LXC container, check NZBGet's external IP
docker compose exec nzbget curl -s ifconfig.me

# Should show your VPS IP, NOT your home IP
# If it shows home IP, VPN is not working - STOP HERE

# Check Gluetun logs
docker compose logs gluetun | tail -20

# Should see: "Wireguard is up"
```

### 8.2 Access Services

From your workstation browser:

- **Jellyfin:** http://192.168.80.110:8096
- **Sonarr:** http://192.168.80.110:8989
- **Radarr:** http://192.168.80.110:7878
- **Prowlarr:** http://192.168.80.110:9696
- **NZBGet:** http://192.168.80.110:6789
- **Bazarr:** http://192.168.80.110:6767
- **Jellyseerr:** http://192.168.80.110:5055

### 8.3 Configure Jellyfin

1. **Initial Setup Wizard:**
   - Language: English
   - Username: Your admin username
   - Password: Strong password

2. **Add Media Libraries:**
   - Click "Add Media Library"
   - Type: Movies
   - Folders: `/media/Movies`
   - Click "Add Media Library"
   - Type: TV Shows
   - Folders: `/media/TV`

3. **Hardware Acceleration (if GPU passed through):**
   - Dashboard → Playback → Transcoding
   - Hardware acceleration: **VAAPI**
   - Save

4. **Test Playback:**
   - Add a test video file
   - Try playing it
   - Check GPU usage: `nvidia-smi` or `radeontop` on host

### 8.4 Configure Prowlarr (Indexer Manager)

1. **Initial Setup:**
   - Open http://192.168.80.110:9696
   - Set authentication (username/password)

2. **Add Indexers:**
   - Settings → Indexers → Add Indexer
   - Add your Usenet indexers (e.g., NZBgeek, DrunkenSlug)
   - Test each indexer

3. **Connect to Apps:**
   - Settings → Apps → Add Application
   - **Sonarr:**
     - Prowlarr Server: http://localhost:9696
     - Sonarr Server: http://sonarr:8989
     - API Key: (get from Sonarr Settings → General)
   - **Radarr:**
     - Prowlarr Server: http://localhost:9696
     - Radarr Server: http://radarr:7878
     - API Key: (get from Radarr Settings → General)
   - Click "Sync App Indexers" - Prowlarr will push indexers to Sonarr/Radarr

### 8.5 Configure NZBGet

1. **Open:** http://192.168.80.110:6789
2. **Default credentials:** nzbget / tegbzn6789
3. **Settings → SECURITY:**
   - Change ControlUsername
   - Change ControlPassword

4. **Settings → PATHS:**
   - MainDir: `/downloads`
   - DestDir: `/downloads/complete`
   - InterDir: `/downloads/incomplete`

5. **Settings → NEWS-SERVERS:**
   - Add Newshosting server (already configured from .env)
   - Add Easynews server (already configured from .env)
   - Test connections

6. **Settings → DOWNLOAD QUEUE:**
   - ArticleCache: 500 (or higher if you have RAM)
   - Save and reload NZBGet

### 8.6 Configure Sonarr (TV Shows)

1. **Settings → Media Management:**
   - Enable "Rename Episodes"
   - Standard Episode Format: `{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}`
   - Root Folders → Add Root Folder: `/media/TV`

2. **Settings → Download Clients:**
   - Add Download Client: NZBGet
   - Host: `nzbget`
   - Port: `6789`
   - Username/Password: (from NZBGet)
   - Category: `sonarr`
   - Test and Save

3. **Settings → Indexers:**
   - Should already have indexers from Prowlarr sync
   - If not, sync from Prowlarr again

4. **Settings → Connect (Notifications):**
   - Add Connection: Jellyfin
   - Host: `jellyfin`
   - Port: `8096`
   - API Key: (get from Jellyfin Dashboard → API Keys)
   - Test and Save

### 8.7 Configure Radarr (Movies)

1. **Settings → Media Management:**
   - Enable "Rename Movies"
   - Standard Movie Format: `{Movie Title} ({Release Year}) {Quality Full}`
   - Root Folders → Add Root Folder: `/media/Movies`

2. **Settings → Download Clients:**
   - Add Download Client: NZBGet
   - Host: `nzbget`
   - Port: `6789`
   - Username/Password: (from NZBGet)
   - Category: `radarr`
   - Test and Save

3. **Settings → Indexers:**
   - Should already have indexers from Prowlarr
   - If not, sync from Prowlarr

4. **Settings → Connect:**
   - Add Connection: Jellyfin
   - Host: `jellyfin`
   - Port: `8096`
   - API Key: (from Jellyfin)
   - Test and Save

### 8.8 Configure Bazarr (Subtitles)

1. **Settings → Languages:**
   - Add languages you want (e.g., English)
   - Enable "Single Language"

2. **Settings → Providers:**
   - Enable subtitle providers (OpenSubtitles, etc.)
   - Add credentials if needed

3. **Settings → Sonarr:**
   - Address: `http://sonarr:8989`
   - API Key: (from Sonarr)
   - Test and Save

4. **Settings → Radarr:**
   - Address: `http://radarr:7878`
   - API Key: (from Radarr)
   - Test and Save

### 8.9 Configure Jellyseerr (Requests)

1. **Initial Setup:**
   - Open http://192.168.80.110:5055
   - Sign in with Jellyfin account

2. **Settings → Jellyfin:**
   - Server URL: `http://jellyfin:8096`
   - Connect and authorize

3. **Settings → Services:**
   - **Sonarr:**
     - Server: `http://sonarr:8989`
     - API Key: (from Sonarr)
     - Quality Profile: HD - 720p/1080p
     - Root Folder: `/media/TV`
   - **Radarr:**
     - Server: `http://radarr:7878`
     - API Key: (from Radarr)
     - Quality Profile: HD - 720p/1080p
     - Root Folder: `/media/Movies`

---

## Phase 9: Verification & Testing

### 9.1 Test Download Flow

**Add a test TV show in Sonarr:**

1. Open Sonarr → Series → Add New
2. Search for a show (e.g., "Rick and Morty")
3. Select a season/episode
4. Monitor: Selected episodes
5. Click "Add and Search"

**Monitor the flow:**
```bash
# Watch NZBGet queue
# Open http://192.168.80.110:6789

# Watch Sonarr activity
# Open http://192.168.80.110:8989 → Activity → Queue

# Check file appears in media directory
pct exec 110 -- ls -lah /mnt/media/TV/

# Verify Jellyfin detects it
# Open Jellyfin, refresh library, check if episode appears
```

### 9.2 Test VPN Kill-Switch

**CRITICAL SECURITY TEST:**

```bash
# Inside LXC container
docker compose stop gluetun

# Wait 10 seconds
sleep 10

# Try to download with NZBGet
# It should FAIL - no internet access without VPN

# Check NZBGet logs
docker compose logs nzbget | tail -20
# Should show connection errors

# Restart VPN
docker compose start gluetun
sleep 10

# Verify VPN is up
docker compose exec nzbget curl -s ifconfig.me
# Should show VPS IP again

# NZBGet downloads should resume
```

### 9.3 Test GPU Transcoding (if applicable)

1. Play a video in Jellyfin that requires transcoding
   - Choose a quality lower than source
   - Or use a client that doesn't support the codec

2. On Proxmox host, monitor GPU usage:
```bash
# For Intel/AMD
watch -n 1 cat /sys/kernel/debug/dri/0/amdgpu_pm_info
# Or
intel_gpu_top

# For Nvidia
nvidia-smi -l 1
```

3. Should see GPU usage spike during playback

### 9.4 Verify All Services Healthy

```bash
# Inside LXC container
cd /opt/media-stack

# Check all services
docker compose ps

# All should show "Up (healthy)" or "Up"

# Run health check script
../scripts/health-check.sh

# Should show all services passing
```

---

## Post-Deployment

### Backup Configuration

```bash
# Run initial backup
cd /root/brother-eye-media-stack
./scripts/backup-configs.sh

# Backups stored in: /root/backups/brother-eye-YYYYMMDD-HHMMSS.tar.gz
```

### Schedule Automatic Backups

```bash
# Add to crontab
crontab -e

# Add line (daily backup at 3 AM):
0 3 * * * /root/brother-eye-media-stack/scripts/backup-configs.sh
```

### Monitor Services

```bash
# Inside LXC container
cd /opt/media-stack

# Use management script
./manage-stack.sh status    # Show status
./manage-stack.sh logs      # View all logs
./manage-stack.sh restart   # Restart all services
```

### Optional: Setup Caddy Reverse Proxy

If you want to access services via subdomains:

```bash
# Edit docker-compose.yml to uncomment Caddy
nano docker-compose.yml
# Uncomment: # - compose/caddy.yml

# Restart stack
docker compose up -d
```

---

## Troubleshooting

### Issue: NFS Mount Not Visible in Container

**Symptoms:** `/mnt/media` is empty inside container

**Solution:**
```bash
# Check mount on Proxmox host
df -h | grep nas

# If not mounted:
mount -a

# Verify LXC bind mount
pct config 110 | grep mp

# Restart container
pct restart 110
```

### Issue: VPN Not Routing Traffic

**Symptoms:** NZBGet shows home IP instead of VPS IP

**Solution:**
```bash
# Check Gluetun logs
docker compose logs gluetun | grep -i error

# Verify .env has correct VPN credentials
cat /opt/media-stack/.env | grep WIREGUARD

# Restart Gluetun
docker compose restart gluetun

# Test again
docker compose exec nzbget curl -s ifconfig.me
```

### Issue: Services Can't Communicate

**Symptoms:** Sonarr can't reach NZBGet, Jellyfin can't be notified

**Solution:**
```bash
# Verify all services on same Docker network
docker compose exec sonarr ping nzbget
docker compose exec radarr ping jellyfin

# Check Docker network
docker network ls
docker network inspect media-network

# Restart stack
docker compose restart
```

### Issue: Permission Denied on Media Files

**Symptoms:** Sonarr/Radarr can't move files

**Solution:**
```bash
# Check ownership on Proxmox host
ls -la /mnt/pve/nas/Media
ls -la /mnt/pve/nas/Downloads

# Verify mediauser UID matches NAS
pct exec 110 -- id mediauser
# Should show: uid=1000(mediauser) gid=100(users)

# Fix permissions if needed on NAS
# chown -R 1000:100 /path/to/media
```

### Issue: GPU Not Available

**Symptoms:** Jellyfin transcoding uses CPU

**Solution:**
```bash
# Check GPU devices in container
pct exec 110 -- ls -l /dev/dri

# If missing, ensure GPU is passed
pct config 110 | grep dev

# Repass GPU
pct stop 110
./proxmox/pass-gpu-to-lxc.sh 110
pct start 110

# Verify in Jellyfin
# Dashboard → Playback → Transcoding
# Hardware acceleration: VAAPI
```

---

## 🎉 Deployment Complete!

Your Brother Eye Media Stack is now fully deployed and operational.

**Access Points:**
- Jellyfin: http://192.168.80.110:8096
- Sonarr: http://192.168.80.110:8989
- Radarr: http://192.168.80.110:7878
- Prowlarr: http://192.168.80.110:9696
- NZBGet: http://192.168.80.110:6789
- Bazarr: http://192.168.80.110:6767
- Jellyseerr: http://192.168.80.110:5055

**Next Steps:**
1. Add your favorite TV shows and movies to Sonarr/Radarr
2. Configure quality profiles and preferred release formats
3. Set up notifications (Discord, Telegram, email)
4. Schedule library scans in Jellyfin
5. Invite users to Jellyseerr for content requests

**Enjoy your privacy-first, self-hosted media automation! 🍿**
