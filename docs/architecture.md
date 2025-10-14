# 🏗️ Brother Eye Media Stack - Architecture Documentation

Deep dive into the technical architecture, design decisions, and implementation details.

---

## 📋 Table of Contents

1. [System Overview](#system-overview)
2. [Infrastructure Layer](#infrastructure-layer)
3. [Network Architecture](#network-architecture)
4. [Storage Architecture](#storage-architecture)
5. [Container Architecture](#container-architecture)
6. [VPN and Privacy Layer](#vpn-and-privacy-layer)
7. [Service Communication](#service-communication)
8. [GPU Passthrough](#gpu-passthrough)
9. [Security Model](#security-model)
10. [Design Decisions and Trade-offs](#design-decisions-and-trade-offs)
11. [Lessons Learned](#lessons-learned)

---

## System Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          BROTHER EYE NETWORK                            │
│                                                                         │
│  ┌─────────────────┐                    ┌──────────────────────────┐   │
│  │   OPNsense      │◄───────────────────│  VPS WireGuard Server    │   │
│  │   Firewall      │  VPN Tunnel        │  (10.200.0.1)            │   │
│  │   (Gateway)     │  Policy Routing    │  Privacy Endpoint        │   │
│  └────────┬────────┘                    └──────────────────────────┘   │
│           │                                                             │
│  ┌────────┴─────────────────────────────────────────────────┐          │
│  │                    VLAN SEGMENTATION                      │          │
│  ├───────────────┬───────────────┬──────────────┬───────────┤          │
│  │ VLAN 10 Mgmt  │ VLAN 20 Trust │ VLAN 70 NAS  │ VLAN 80   │          │
│  │ (Admin)       │ (Clients)     │ (Storage)    │ (Media)   │          │
│  └───────────────┴───────────────┴──────┬───────┴─────┬─────┘          │
│                                          │             │                │
│                   ┌──────────────────────┘             │                │
│                   │                                    │                │
│            ┌──────▼──────┐                      ┌──────▼──────┐         │
│            │    NAS      │                      │   Proxmox   │         │
│            │  OMV 7      │                      │   Host      │         │
│            │ (NFS Server)│                      │  (Hyperv.)  │         │
│            │ 192.168.    │                      │ 192.168.    │         │
│            │   70.10     │                      │   80.10     │         │
│            └─────────────┘                      └──────┬──────┘         │
│                  │                                     │                │
│                  │  NFSv4 Mount                        │                │
│                  │  (fsid=0 root)                      │                │
│                  └─────────────────────────────────────┤                │
│                         /mnt/pve/nas                   │                │
│                                                        │                │
│                                              ┌─────────▼────────┐       │
│                                              │  LXC 110         │       │
│                                              │  media-stack     │       │
│                                              │  192.168.80.110  │       │
│                                              │                  │       │
│                                              │  [Docker Engine] │       │
│                                              │  8 Containers    │       │
│                                              └──────────────────┘       │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Overview

| Layer | Component | Purpose | Technology |
|-------|-----------|---------|------------|
| **Network** | OPNsense | Firewall, VPN gateway, VLAN routing | FreeBSD, WireGuard |
| **Storage** | NAS (OMV7) | Central storage, NFS server | Debian 12, Btrfs |
| **Compute** | Proxmox Host | Hypervisor, container host | Proxmox VE 8.x |
| **Container** | LXC 110 | Docker host, service isolation | Debian 12 LXC |
| **Orchestration** | Docker Compose | Service management | Docker 24+ |
| **Services** | 8 Containers | Media stack applications | LinuxServer.io images |

---

## Infrastructure Layer

### Proxmox Hypervisor

**Role:** Provides virtualization platform and resource management

**Configuration:**
```yaml
Host: Dell Inspiron 5575
CPU: AMD Ryzen 5 2500U (4 cores, 8 threads)
RAM: 12 GB DDR4
Storage: 1 TB NVMe SSD
Network: Gigabit Ethernet
GPU: AMD Vega 8 (integrated)
```

**Why Proxmox?**
- ✅ Enterprise-grade hypervisor, free and open-source
- ✅ LXC container support (lightweight vs. full VMs)
- ✅ Web-based management interface
- ✅ Built on Debian (familiar, stable)
- ✅ Excellent device passthrough support (GPU, USB, etc.)
- ✅ Backup and snapshot capabilities

### LXC vs. VM Decision

**Chose LXC Container over full VM:**

**Advantages:**
- **Resource Efficiency:** LXC shares host kernel (minimal overhead)
  - VM would need dedicated RAM for guest OS (2-4 GB)
  - LXC uses ~100 MB for container overhead
- **Performance:** Near-native performance (no hypervisor layer)
- **Storage:** No disk image overhead, direct filesystem
- **Boot Time:** Seconds vs. minutes for VM

**Trade-offs:**
- ❌ Less isolation than VM (shares kernel with host)
- ❌ Must be same architecture as host (Linux only)
- ✅ But: For our use case (trusted applications, same network), isolation is sufficient

### Single LXC vs. Multiple LXCs

**Chose Single LXC with Docker over 8 Individual LXCs:**

**Original Plan (8 LXCs):**
```
110 - Jellyfin    (4 cores, 4 GB)
111 - Sonarr      (2 cores, 2 GB)
112 - Radarr      (2 cores, 2 GB)
113 - Prowlarr    (1 core,  1 GB)
114 - NZBGet      (2 cores, 2 GB)
115 - Caddy       (1 core, 512 MB)
116 - Jellyseerr  (1 core,  1 GB)
117 - Bazarr      (1 core,  1 GB)
─────────────────────────────────
Total: 14 cores, 15.5 GB (overprovisioned)
```

**Current Design (1 LXC):**
```
110 - media-stack (8 cores, 12 GB)
  └─ Docker: 8 containers with dynamic resource sharing
```

**Benefits:**
- **Resource Efficiency:** Services idle 90% of time, share resources dynamically
- **Simpler Management:** One container to start/stop/backup
- **Unified Networking:** Services communicate via Docker networks (no external hops)
- **Easier Updates:** One `docker compose pull` vs. 8 LXC updates
- **Single Configuration:** One compose file, one .env file

**When to Use Multiple LXCs Instead:**
- Different security contexts (untrusted vs. trusted apps)
- Different update cycles (prod vs. test)
- Completely separate networks with strict isolation
- Multi-tenant environment

---

## Network Architecture

### VLAN Design

```
┌───────────────────────────────────────────────────────────────┐
│                      OPNsense Router                          │
│                   (192.168.0.1 - Gateway)                     │
└───────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┘
        │       │       │       │       │       │       │
   ┌────▼───┬───▼───┬───▼───┬───▼───┬───▼───┬───▼───┬───▼───┐
   │VLAN 10 │VLAN 20│VLAN 30│VLAN 40│VLAN 50│VLAN 70│VLAN 80│
   │  Mgmt  │ Trust │  Lab  │  IoT  │ Guest │  NAS  │ Media │
   └────────┴───────┴───────┴───────┴───────┴───┬───┴───┬───┘
                                                 │       │
                                            ┌────▼───┐ ┌─▼────┐
                                            │  NAS   │ │ LXC  │
                                            │ .70.10 │ │.80.110│
                                            └────────┘ └──────┘
```

### Network Segmentation Rules

**VLAN 70 (Storage - 192.168.70.0/24):**
- **Purpose:** NAS and backup storage
- **Access:** Only from Mgmt (10) and Trusted (20) VLANs
- **Isolation:** Cannot initiate connections to other VLANs
- **Services:** NFSv4, SMB (for Windows clients if needed)

**VLAN 80 (Media - 192.168.80.0/24):**
- **Purpose:** Media services (Jellyfin, *arr stack)
- **Access:** Clients in Trusted VLAN can access services
- **Isolation:** Cannot reach IoT or Guest VLANs
- **Services:** HTTP/HTTPS for web UIs, streaming

**Firewall Rules (OPNsense):**
```
# Allow Trusted → Media (for accessing services)
VLAN 20 → VLAN 80: Allow TCP 8096,8989,7878,9696,6789,5055,6767

# Allow Media → Storage (for NFS access)
VLAN 80 → VLAN 70: Allow TCP/UDP 2049 (NFS)

# Allow Media → Internet (for metadata, indexers)
VLAN 80 → WAN: Allow (but NZBGet goes through VPN)

# Deny all other inter-VLAN traffic by default
```

### DNS Resolution

**Internal DNS (Unbound on OPNsense):**
- All clients use 192.168.10.1 (OPNsense) as DNS server
- Unbound performs recursive resolution (no forwarders)
- Local domain: `brothereye.local`
- Split DNS: Internal zones resolve to private IPs

**DNS Query Flow:**
```
Client Query "jellyfin.brothereye.local"
  ↓
OPNsense Unbound (192.168.10.1)
  ↓
Local Zone Check → Found: 192.168.80.110
  ↓
Return to Client
```

---

## Storage Architecture

### Storage Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                      NAS (OMV7)                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Physical Disks                                      │   │
│  │  - 1TB NVMe: System + Scratch (ext4)                 │   │
│  │  - 4TB SSD: Active Media (Btrfs + compression)       │   │
│  │  - 8TB HDD: Backups (ext4)                           │   │
│  └───────────────────┬──────────────────────────────────┘   │
│                      │                                       │
│  ┌───────────────────▼──────────────────────────────────┐   │
│  │  Filesystem Layer                                    │   │
│  │  /srv/dev-disk-by-uuid-.../Media      → /export/Media│   │
│  │  /srv/dev-disk-by-uuid-.../Downloads  → /export/Down.│   │
│  │  /srv/dev-disk-by-uuid-.../Backup     → /export/Back.│   │
│  └───────────────────┬──────────────────────────────────┘   │
│                      │                                       │
│  ┌───────────────────▼──────────────────────────────────┐   │
│  │  NFSv4 Exports (fsid=0 pseudofilesystem)            │   │
│  │  /export              (root, fsid=0, ro)             │   │
│  │  /export/Media        (fsid=UUID, rw)                │   │
│  │  /export/Downloads    (fsid=UUID, rw)                │   │
│  │  /export/Backup       (fsid=UUID, rw)                │   │
│  └───────────────────┬──────────────────────────────────┘   │
└────────────────────│─────────────────────────────────────┘
                     │ NFSv4
         ┌───────────▼─────────────┐
         │   Proxmox Host          │
         │   mount -t nfs4         │
         │   192.168.70.10:/       │
         │   /mnt/pve/nas          │
         └───────────┬─────────────┘
                     │ Bind Mount
         ┌───────────▼─────────────┐
         │   LXC 110               │
         │   /mnt/media            │
         │   /mnt/downloads        │
         └───────────┬─────────────┘
                     │ Docker Volumes
         ┌───────────▼─────────────┐
         │   Docker Containers     │
         │   - Jellyfin: /media:ro │
         │   - Sonarr: /media:rw   │
         │   - NZBGet: /downloads  │
         └─────────────────────────┘
```

### NFSv4 Pseudofilesystem (Critical Lesson)

**Problem Encountered:**
```bash
# WRONG - This fails:
mount -t nfs4 192.168.70.10:/export/Media /mnt/media
# Error: No such file or directory
```

**Root Cause:**
When an NFS export has `fsid=0`, it becomes the NFSv4 **pseudofilesystem root**. You must mount the root (`/`), not subdirectories.

**Solution:**
```bash
# CORRECT - Mount the root:
mount -t nfs4 192.168.70.10:/ /mnt/pve/nas

# Then access subdirectories:
ls /mnt/pve/nas/Media
ls /mnt/pve/nas/Downloads
```

**NAS Export Configuration:**
```bash
# /etc/exports on NAS
/export                192.168.80.10(ro,fsid=0,root_squash,subtree_check,secure)
/export/Media          192.168.80.10(fsid=UUID,rw,sync,no_subtree_check,no_root_squash)
/export/Downloads      192.168.80.10(fsid=UUID,rw,sync,no_subtree_check,no_root_squash)
```

**Key Points:**
- `/export` has `fsid=0` → NFSv4 root
- Subdirectories have unique `fsid` (UUID) for proper handling
- `no_root_squash` allows root in container to access files
- `sync` ensures writes are committed before ACK

### LXC Container Storage Mounts

**Why LXC Can't Mount NFS Directly:**

**Unprivileged containers lack CAP_SYS_ADMIN capability needed for mount()**

**Solution: Bind Mounts from Host**

```bash
# On Proxmox host, edit LXC config:
pct set 110 -mp0 /mnt/pve/nas/Media,mp=/mnt/media
pct set 110 -mp1 /mnt/pve/nas/Downloads,mp=/mnt/downloads

# This adds to /etc/pve/lxc/110.conf:
mp0: /mnt/pve/nas/Media,mp=/mnt/media
mp1: /mnt/pve/nas/Downloads,mp=/mnt/downloads
```

**How Bind Mounts Work:**
1. Proxmox mounts NFS at `/mnt/pve/nas` (host filesystem)
2. Proxmox binds host directory into container namespace
3. Container sees `/mnt/media` (actually host's `/mnt/pve/nas/Media`)
4. No additional NFS client in container needed

### Docker Volume Mounts

**From LXC to Docker containers:**

```yaml
# docker-compose.yml (Jellyfin example)
services:
  jellyfin:
    volumes:
      - /mnt/media:/media:ro  # Read-only (safety)

# Sonarr/Radarr need write access:
  sonarr:
    volumes:
      - /mnt/media:/media:rw
      - /mnt/downloads:/downloads:rw
```

**Permission Mapping:**

```
NAS Filesystem:
  Owner: root (0)
  Group: users (100)
  Perms: drwxrwsr-x (2775)

LXC Container:
  mediauser: UID 1000, GID 100 (users)

Docker Containers:
  PUID=1000, PGID=100
  Containers run as UID 1000 → Matches mediauser
```

**Why This Works:**
- NAS files owned by GID 100 (users group)
- LXC mediauser in GID 100
- Docker containers use PUID=1000, PGID=100
- All three layers use same UID/GID → Seamless access

### Storage Performance Optimization

**Btrfs on 4TB SSD (Active Media):**

```bash
# Mount options:
/dev/sdb1 /srv/media btrfs compress=zstd:1,noatime 0 0
```

**Benefits:**
- `compress=zstd:1` → Transparent compression
  - Reduces write amplification on SSD
  - Saves 10-30% space (depending on content)
  - Minimal CPU overhead
- `noatime` → No access time updates
  - Reduces metadata writes
  - Improves performance for read-heavy workloads

**Btrfs Features Utilized:**
- **Snapshots:** Weekly snapshots for accidental deletion protection
- **Scrub:** Monthly bitrot detection
- **Compression:** Extends SSD lifespan

---

## Container Architecture

### Docker Compose Modular Structure

**Main Orchestrator (docker-compose.yml):**
```yaml
include:
  - compose/gluetun.yml       # VPN (foundation)
  - compose/nzbget.yml        # Depends on gluetun
  - compose/prowlarr.yml
  - compose/sonarr.yml
  - compose/radarr.yml
  - compose/bazarr.yml
  - compose/jellyfin.yml
  - compose/jellyseerr.yml
  # - compose/caddy.yml       # Optional

networks:
  media-network:
    driver: bridge
  vpn-network:
    driver: bridge
```

**Why Modular?**
- ✅ **Enable/Disable:** Comment out one line to disable service
- ✅ **Maintainability:** Each service isolated in own file
- ✅ **Reusability:** Copy `jellyfin.yml` to another project
- ✅ **Clarity:** 50 lines per file vs. 400 lines in one file
- ✅ **Git Diffs:** Changes to one service don't clutter history

### Container Dependency Flow

```
┌─────────────┐
│   Gluetun   │ ← Started first (VPN tunnel)
│   (VPN)     │
└──────┬──────┘
       │
       │ network_mode: service:gluetun
       │
┌──────▼──────┐
│   NZBGet    │ ← Routes ALL traffic through Gluetun
│ (Downloader)│
└──────┬──────┘
       │
       │ Downloads files
       │
┌──────▼──────┬───────────────┬──────────────┐
│  Prowlarr   │    Sonarr     │   Radarr     │
│ (Indexers)  │   (TV Auto)   │ (Movie Auto) │
└──────┬──────┴───────┬───────┴──────┬───────┘
       │              │              │
       │ Searches     │ Organizes    │ Organizes
       │              │              │
       └──────────────┴──────────────┘
                      │
                ┌─────▼─────┐
                │ Jellyfin  │ ← Serves media
                │ (Server)  │
                └───────────┘
```

### Resource Limits

**Docker Compose Resource Management:**

```yaml
# Example: Jellyfin with memory limit
services:
  jellyfin:
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 2G
```

**Strategy:**
- **No hard CPU limits** → Allow burst usage (transcoding, imports)
- **Memory limits** → Prevent OOM killing host
- **Reservations** → Guarantee minimum resources

**Current Allocation:**
- Jellyfin: 4 GB limit (transcoding needs memory)
- Sonarr/Radarr: 2 GB each
- Others: 1 GB each
- Total: ~12 GB (fits in LXC allocation)

---

## VPN and Privacy Layer

### Gluetun Container

**Purpose:** VPN tunnel with automatic kill-switch

**Architecture:**
```
┌────────────────────────────────────────────┐
│  Gluetun Container                         │
│  ┌──────────────────────────────────────┐  │
│  │  WireGuard Client                    │  │
│  │  - Connects to VPS (10.200.0.1)      │  │
│  │  - Creates wg0 interface              │  │
│  │  - Routes 0.0.0.0/0 through tunnel   │  │
│  └──────────────────────────────────────┘  │
│  ┌──────────────────────────────────────┐  │
│  │  Kill-Switch (iptables)              │  │
│  │  - Default policy: DROP               │  │
│  │  - Allow: wg0 interface only          │  │
│  │  - Block: eth0 (host network)         │  │
│  └──────────────────────────────────────┘  │
│  ┌──────────────────────────────────────┐  │
│  │  HTTP Proxy (optional)               │  │
│  │  - Port 8888 for other containers    │  │
│  └──────────────────────────────────────┘  │
└────────────────────────────────────────────┘
         ▲
         │ network_mode: service:gluetun
         │
┌────────┴──────────┐
│     NZBGet        │
│  (Shares network  │
│   stack with      │
│   Gluetun)        │
└───────────────────┘
```

**NZBGet Network Configuration:**

```yaml
services:
  nzbget:
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
```

**What This Does:**
- NZBGet doesn't create its own network interface
- It uses Gluetun's network stack (including wg0)
- **ALL** NZBGet traffic goes through VPN
- If VPN drops, Gluetun's iptables rules block traffic → Kill-switch

**Verification:**
```bash
# Check NZBGet's external IP (should be VPS IP)
docker compose exec nzbget curl -s ifconfig.me

# Compare to Jellyfin's IP (should be home IP)
docker compose exec jellyfin curl -s ifconfig.me
```

### Alternative: OPNsense Policy Routing

**Original Design (Not Used):**

```
┌──────────────────────────────────────────┐
│  OPNsense Firewall                       │
│  ┌────────────────────────────────────┐  │
│  │  WireGuard Client                  │  │
│  │  Interface: wg0                    │  │
│  │  Gateway: 10.200.0.1               │  │
│  └────────────────────────────────────┘  │
│  ┌────────────────────────────────────┐  │
│  │  Policy Routing Rule               │  │
│  │  Source: 192.168.80.114 (NZBGet)  │  │
│  │  Gateway: wg0                      │  │
│  └────────────────────────────────────┘  │
│  ┌────────────────────────────────────┐  │
│  │  Kill-Switch Rule                  │  │
│  │  Block: 192.168.80.114 → WAN      │  │
│  │  (if wg0 is down)                  │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

**Why Gluetun Instead:**
- ✅ Portable (VPN config lives with Docker stack)
- ✅ Service-level isolation (only NZBGet uses VPN)
- ✅ Easier troubleshooting (logs in Docker)
- ✅ No firewall configuration needed
- ✅ Works regardless of network topology

**When to Use OPNsense Policy Routing:**
- Multiple non-Docker services need VPN
- Centralized VPN management preferred
- VLAN-wide VPN routing (entire subnet through VPN)

---

## Service Communication

### Docker Networks

```yaml
networks:
  media-network:
    name: media-network
    driver: bridge
    ipam:
      config:
        - subnet: 172.18.0.0/16

  vpn-network:
    name: vpn-network
    driver: bridge
    internal: true  # No external access
```

**Network Topology:**

```
┌────────────────────────────────────────────────────────────┐
│  media-network (172.18.0.0/16)                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │Jellyfin  │  │ Sonarr   │  │ Radarr   │  │Prowlarr  │   │
│  │.18.0.10  │  │.18.0.11  │  │.18.0.12  │  │.18.0.13  │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│       │             │             │             │          │
│       └─────────────┴─────────────┴─────────────┘          │
│                     Can communicate                        │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│  vpn-network (172.19.0.0/16) - internal only              │
│  ┌──────────┐                                              │
│  │ Gluetun  │◄───── NZBGet (shares network stack)         │
│  │.19.0.10  │                                              │
│  └──────────┘                                              │
│  No direct access from other containers                    │
└────────────────────────────────────────────────────────────┘
```

### Service Discovery

**Docker DNS Resolution:**

Services resolve each other by container name:

```bash
# From Sonarr container:
ping jellyfin        # Resolves to jellyfin's container IP
ping radarr          # Resolves to radarr's container IP
ping nzbget          # Resolves to gluetun's IP (shared network)
```

**API Communication Example:**

```
Sonarr wants to notify Jellyfin of new episode:
  ↓
Sonarr → POST http://jellyfin:8096/Library/Refresh
  ↓
Docker DNS → Resolves "jellyfin" to 172.18.0.10
  ↓
Jellyfin receives request, refreshes library
```

### NZBGet Communication

**Challenge:** NZBGet uses Gluetun's network stack

```yaml
# NZBGet doesn't have its own IP
network_mode: "service:gluetun"
```

**How Sonarr/Radarr Connect:**

```
Sonarr → http://gluetun:6789 (NZBGet's port)
         ↓
  Resolves to Gluetun container IP
         ↓
  Reaches Gluetun, which forwards to NZBGet
         ↓
  NZBGet receives request
```

**Port Publishing:**

```yaml
gluetun:
  ports:
    - "6789:6789"  # NZBGet port published on Gluetun
```

---

## GPU Passthrough

### Implementation

**GPU on Proxmox Host:**
```bash
/dev/dri/card1      # AMD Vega 8 (or Intel QuickSync, Nvidia, etc.)
/dev/dri/renderD128 # Render node for VAAPI
```

**Pass to LXC:**
```bash
pct set 110 -dev0 /dev/dri/card1,gid=104
pct set 110 -dev1 /dev/dri/renderD128,gid=104

# gid=104 is "render" group in container
```

**Inside LXC:**
```bash
ls -l /dev/dri
# crw-rw---- 1 root render 226,   1 card1
# crw-rw---- 1 root render 226, 128 renderD128
```

**Docker Mount:**
```yaml
jellyfin:
  devices:
    - /dev/dri:/dev/dri
  group_add:
    - "104"  # render group
```

**Permission Flow:**

```
Host: /dev/dri/renderD128
  Owner: root:video (0:44)
  ↓
LXC (with -dev1 /dev/dri/renderD128,gid=104):
  Owner: root:render (0:104)
  ↓
Docker (with devices: /dev/dri):
  Owner: root:render (0:104)
  Container user (UID 1000) in group 104
  ↓
  Can access GPU
```

### Jellyfin Hardware Transcoding

**Configuration:**
```
Jellyfin Dashboard → Playback → Transcoding
  Hardware acceleration: VAAPI
  VA API Device: /dev/dri/renderD128
  Enable hardware decoding: All codecs
  Enable hardware encoding: H.264, HEVC
```

**How It Works:**

```
Client requests 1080p stream of 4K video
  ↓
Jellyfin detects transcoding needed
  ↓
Jellyfin calls FFmpeg with VAAPI flags:
  ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
         -i input.mkv -c:v h264_vaapi output.ts
  ↓
GPU decodes 4K → Scales to 1080p → Encodes H.264
  ↓
CPU usage: ~5% (vs. 100% without GPU)
```

**Performance:**

| Scenario | CPU Usage | GPU Usage |
|----------|-----------|-----------|
| Direct Play (no transcode) | ~2% | 0% |
| CPU Transcode 4K→1080p | 100% (1 stream max) | 0% |
| GPU Transcode 4K→1080p | ~5% | ~30-50% |

---

## Security Model

### Defense in Depth

**Layer 1: Network Isolation**
- VLAN segmentation prevents lateral movement
- Firewall rules enforce least-privilege access
- Media services isolated from IoT, guest networks

**Layer 2: Container Isolation**
- Unprivileged LXC (no host root)
- Docker containers run as non-root user (UID 1000)
- Read-only mounts where possible (Jellyfin → media)

**Layer 3: VPN Privacy**
- All Usenet traffic encrypted end-to-end
- Kill-switch prevents IP leaks
- No logs on VPS endpoint

**Layer 4: Encryption at Rest**
- git-crypt for secrets in repository
- NAS uses LUKS encryption (optional)
- Backups encrypted with GPG (optional)

### Attack Surface Analysis

**Exposed Services:**
- **None externally** (all services internal only)
- Access via WireGuard VPN for remote management

**Internal Attack Vectors:**

| Vector | Mitigation |
|--------|------------|
| Compromised container | Unprivileged, limited capabilities |
| Malicious media file | Jellyfin runs as non-root, sandboxed |
| Stolen credentials | git-crypt protects at-rest secrets |
| LAN-based attack | VLAN isolation, firewall rules |
| Physical access | LUKS disk encryption (NAS) |

---

## Design Decisions and Trade-offs

### Decision: Single LXC vs. Multiple LXCs

**Chose:** Single LXC with Docker

**Reasoning:**
- Services don't need strict isolation (all trusted)
- Resource efficiency (dynamic sharing)
- Simpler management
- Unified networking

**Trade-off:** Less isolation, shared kernel

### Decision: Gluetun vs. OPNsense VPN Routing

**Chose:** Gluetun container

**Reasoning:**
- Service-level VPN (only NZBGet)
- Portable configuration
- No firewall changes needed

**Trade-off:** More complex Docker setup

### Decision: NFS vs. SMB

**Chose:** NFSv4 for Linux environments

**Reasoning:**
- Better performance for Linux-to-Linux
- Lower CPU overhead
- Native kernel support

**Trade-off:** SMB easier for mixed Windows/Linux

### Decision: Modular Compose vs. Monolithic

**Chose:** Modular (include directive)

**Reasoning:**
- Maintainability (50 lines vs. 400)
- Easy to enable/disable services
- Better git history

**Trade-off:** Slightly more complex structure

---

## Lessons Learned

### NFSv4 Pseudofilesystem (Major Lesson)

**Problem:**
```bash
mount -t nfs4 192.168.70.10:/export/Media /mnt/media
# Error: No such file or directory
```

**Solution:**
```bash
mount -t nfs4 192.168.70.10:/ /mnt/pve/nas
```

**Lesson:** When NFS export has `fsid=0`, it's the pseudofilesystem root. Mount the root, then access subdirectories.

### LXC Can't Mount NFS (Major Lesson)

**Problem:**
```bash
# Inside unprivileged LXC:
mount -t nfs4 192.168.70.10:/ /mnt/media
# Error: Operation not permitted
```

**Solution:** Mount on Proxmox host, bind mount into LXC

**Lesson:** Unprivileged containers lack mount capability. Always mount on host, bind into container.

### GPU Passthrough Requires Both Devices

**Problem:** Passed `/dev/dri/card1` but Jellyfin still couldn't transcode

**Solution:** Also pass `/dev/dri/renderD128`

**Lesson:** VAAPI needs the render node, not just the card device.

### Docker network_mode vs. networks

**Problem:** NZBGet couldn't communicate with other services

**Solution:** Understand `network_mode: service:` shares network stack

**Lesson:** When using `network_mode: service:`, container doesn't join other networks. Publish ports on the parent container (Gluetun).

### User UID/GID Must Match Across Layers

**Problem:** Permission denied accessing NFS files from Docker

**Solution:** Use UID 1000, GID 100 everywhere (NAS, LXC, Docker)

**Lesson:** Plan UID/GID mapping before deployment. Changing later is painful.

---

## Performance Metrics

### Resource Usage (Idle State)

```
LXC Container:
  CPU: ~2-5%
  Memory: 3.5 GB / 12 GB
  Disk I/O: <1 MB/s

Individual Containers:
  Gluetun:     CPU 1%,  MEM 50 MB
  NZBGet:      CPU 0%,  MEM 150 MB
  Jellyfin:    CPU 1%,  MEM 800 MB
  Sonarr:      CPU 0%,  MEM 300 MB
  Radarr:      CPU 0%,  MEM 300 MB
  Prowlarr:    CPU 0%,  MEM 200 MB
  Bazarr:      CPU 0%,  MEM 200 MB
  Jellyseerr:  CPU 0%,  MEM 150 MB
```

### Resource Usage (Active)

```
During Jellyfin 4K→1080p transcode:
  CPU: 5-10% (with GPU)
  GPU: 40-60%
  Memory: 4.5 GB

During Sonarr/Radarr import (10 GB file):
  CPU: 15-30%
  Disk I/O: 200-500 MB/s (NVMe scratch)
  Network: Gigabit saturation
```

---

## Future Enhancements

### Considered But Not Implemented

- **Netdata:** System monitoring (planned)
- **Traefik:** Reverse proxy (Caddy sufficient for now)
- **Automated backups:** Script exists, needs cron scheduling
- **Multi-arch support:** All services x86_64 only (no ARM)
- **High availability:** Single host (no failover)

### Potential Improvements

- **2.5 GbE networking:** NAS and Proxmox host upgrade
- **Additional storage:** More media space (expand 4TB SSD)
- **Remote access:** Cloudflare Tunnel or Tailscale
- **Monitoring dashboard:** Grafana + Prometheus
- **Automated updates:** Watchtower or similar

---

**This architecture balances privacy, performance, and maintainability for a single-user media automation stack.**
