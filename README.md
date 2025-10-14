# 🎯 Brother Eye Media Stack

**Privacy-first, self-hosted media automation stack running on Proxmox LXC with Docker**

A comprehensive, security-hardened media server infrastructure featuring automated downloading, organization, and streaming—all managed through infrastructure-as-code.

---

## 📋 Overview

Brother Eye is a complete media automation stack designed for privacy-conscious self-hosters. It combines Usenet downloading, automated TV/Movie management, subtitle handling, and media streaming into a single LXC container running Docker Compose with modular service definitions.

### Key Features

✅ **Privacy-First Architecture** - All Usenet traffic routed through WireGuard VPN with kill-switch  
✅ **Modular Docker Compose** - Each service in separate, manageable YAML files  
✅ **Hardware Transcoding** - GPU passthrough for efficient Jellyfin transcoding  
✅ **Encrypted Secrets** - git-crypt encryption for sensitive configuration  
✅ **NFS Storage** - Network storage properly mounted and bind-mounted to containers  
✅ **VLAN Segmentation** - Network isolation for security (integrated with OPNsense)  
✅ **Automated Management** - Scripts for deployment, updates, backups, and health checks  
✅ **Infrastructure as Code** - Everything version controlled and reproducible  

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Proxmox Host (192.168.80.10)                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  LXC 110: media-stack (192.168.80.110)               │  │
│  │                                                       │  │
│  │  ┌──────────────┐      ┌──────────────┐             │  │
│  │  │   Gluetun    │◄─────│   NZBGet     │             │  │
│  │  │  (WireGuard  │ VPN  │  (Downloads) │             │  │
│  │  │   Tunnel)    │      │  Port: 6789  │             │  │
│  │  └──────────────┘      └──────────────┘             │  │
│  │                                                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │  │
│  │  │  Jellyfin    │  │   Sonarr     │  │ Prowlarr  │  │  │
│  │  │  (Streaming) │  │   (TV Shows) │  │ (Indexers)│  │  │
│  │  │  Port: 8096  │  │  Port: 8989  │  │ Port:9696 │  │  │
│  │  │  + GPU       │  └──────────────┘  └───────────┘  │  │
│  │  └──────────────┘                                    │  │
│  │                                                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │  │
│  │  │   Radarr     │  │   Bazarr     │  │Jellyseerr │  │  │
│  │  │  (Movies)    │  │  (Subtitles) │  │ (Requests)│  │  │
│  │  │  Port: 7878  │  │  Port: 6767  │  │ Port:5055 │  │  │
│  │  └──────────────┘  └──────────────┘  └───────────┘  │  │
│  │                                                       │  │
│  │  Storage Mounts:                                     │  │
│  │  /mnt/media      ← NFS from NAS (192.168.70.10)     │  │
│  │  /mnt/downloads  ← NFS from NAS (192.168.70.10)     │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

- Proxmox VE 8.x host
- NAS with NFSv4 exports (e.g., OpenMediaVault)
- WireGuard VPN endpoint (for Usenet privacy)
- GPU for hardware transcoding (optional but recommended)
- Git, GPG, and git-crypt installed

### One-Command Deployment

```bash
# 1. Clone the repository
git clone git@github.com:YOUR_USERNAME/brother-eye-media-stack.git
cd brother-eye-media-stack

# 2. Initialize git-crypt (follow prompts)
git-crypt unlock

# 3. Configure environment
cp docker/.env.example docker/.env.production
nano docker/.env.production  # Fill in your credentials

# 4. Run deployment (on Proxmox host)
./proxmox/create-media-stack-lxc.sh
./proxmox/bind-mount-storage.sh 110
./proxmox/pass-gpu-to-lxc.sh 110

# 5. Deploy stack (inside LXC)
pct start 110
pct enter 110
cd /opt/media-stack
./deploy-stack.sh
```

**Detailed deployment guide:** See [DEPLOYMENT.md](DEPLOYMENT.md)

---

## 📦 Services

| Service | Port | Purpose | VPN |
|---------|------|---------|-----|
| **Jellyfin** | 8096 | Media streaming server with GPU transcoding | No |
| **Sonarr** | 8989 | TV show automation and management | No |
| **Radarr** | 7878 | Movie automation and management | No |
| **Prowlarr** | 9696 | Centralized indexer management | No |
| **NZBGet** | 6789 | Usenet downloader | **Yes** |
| **Bazarr** | 6767 | Subtitle downloader and manager | No |
| **Jellyseerr** | 5055 | Media request management | No |
| **Gluetun** | - | WireGuard VPN container (for NZBGet) | N/A |
| **Caddy** | 80/443 | Reverse proxy (optional) | No |

**Access:** `http://192.168.80.110:<port>`

---

## 🗂️ Repository Structure

```
brother-eye-media-stack/
├── .gitignore                    # Sensitive file exclusions
├── .gitattributes                # git-crypt encryption rules
├── GPG-SETUP.md                  # Encryption setup guide
├── SETUP-REPO.sh                 # Repository initialization script
├── README.md                     # This file
├── DEPLOYMENT.md                 # Detailed deployment guide
│
├── docs/                         # Additional documentation
│   ├── architecture.md           # System design details
│   └── troubleshooting.md        # Common issues and solutions
│
├── proxmox/                      # Proxmox host scripts
│   ├── create-media-stack-lxc.sh # LXC container creation
│   ├── bind-mount-storage.sh     # NFS mount binding
│   └── pass-gpu-to-lxc.sh        # GPU passthrough helper
│
├── lxc/                          # LXC container scripts
│   ├── setup-base.sh             # Base system setup
│   ├── deploy-stack.sh           # Stack deployment
│   └── manage-stack.sh           # Service management tool
│
├── docker/                       # Docker Compose configuration
│   ├── docker-compose.yml        # Main orchestrator (includes)
│   ├── .env.example              # Environment variable template
│   └── compose/                  # Individual service definitions
│       ├── gluetun.yml           # VPN container
│       ├── nzbget.yml            # Downloader
│       ├── prowlarr.yml          # Indexer manager
│       ├── sonarr.yml            # TV automation
│       ├── radarr.yml            # Movie automation
│       ├── bazarr.yml            # Subtitles
│       ├── jellyfin.yml          # Media server
│       ├── jellyseerr.yml        # Request management
│       └── caddy.yml             # Reverse proxy
│
├── scripts/                      # Utility scripts
│   ├── backup-configs.sh         # Configuration backup
│   ├── restore-configs.sh        # Configuration restore
│   ├── update-all.sh             # Update all containers
│   └── health-check.sh           # Service health verification
│
└── secrets/                      # Encrypted sensitive files
    ├── .env.production           # Production credentials (encrypted)
    └── wireguard/                # VPN configurations (encrypted)
```

---

## 🔐 Security Features

### Network Isolation
- **VPN Routing:** All Usenet traffic through WireGuard with kill-switch
- **VLAN Segmentation:** Media services isolated in dedicated VLAN (80)
- **NFS Security:** Storage network separated (VLAN 70)

### Encryption
- **git-crypt:** Transparent encryption of sensitive files in repository
- **GPG Keys:** Per-user access control for encrypted secrets
- **VPN Tunnel:** End-to-end encryption for download traffic

### Access Control
- **Unprivileged LXC:** Container runs without root privileges
- **Docker User Mapping:** Services run as non-root user (UID 1000)
- **NFS Permissions:** Read-only mounts where appropriate

---

## 🛠️ Technology Stack

### Infrastructure
- **Proxmox VE 8.x** - Virtualization platform
- **LXC Containers** - Lightweight containerization
- **Debian 12** - Base operating system

### Container Platform
- **Docker 24+** - Container runtime
- **Docker Compose 2.20+** - Service orchestration
- **LinuxServer.io Images** - Maintained container images

### Networking
- **OPNsense** - Firewall and VPN gateway
- **WireGuard** - Modern VPN protocol
- **NFSv4** - Network file system

### Storage
- **Btrfs** - Modern filesystem with compression and snapshots
- **NFS** - Network storage for media and downloads

### Media Stack
- **Jellyfin** - Open-source media server
- **Sonarr/Radarr** - Media automation (*arr stack)
- **NZBGet** - Usenet downloader
- **Prowlarr** - Indexer manager

---

## 📚 Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Step-by-step deployment guide
- **[GPG-SETUP.md](GPG-SETUP.md)** - Encryption setup instructions
- **[docs/architecture.md](docs/architecture.md)** - Detailed system design
- **[docs/troubleshooting.md](docs/troubleshooting.md)** - Common issues and fixes
- **[secrets/README.md](secrets/README.md)** - Secrets management guide
- **[config/README.md](config/README.md)** - Configuration directory info

---

## 🔄 Management

### Daily Operations

```bash
# Start all services
cd /opt/media-stack
./manage-stack.sh start

# Stop all services
./manage-stack.sh stop

# View logs
./manage-stack.sh logs <service-name>

# Update containers
./manage-stack.sh update
```

### Backup & Restore

```bash
# Backup configurations
../scripts/backup-configs.sh

# Restore from backup
../scripts/restore-configs.sh /path/to/backup.tar.gz
```

### Health Monitoring

```bash
# Check service health
../scripts/health-check.sh
```

---

## 🐛 Troubleshooting

### Common Issues

**NFS mount not visible in container:**
- Verify Proxmox host mount: `df -h | grep nas`
- Check bind mount in container: `pct config 110 | grep mp`
- Restart container: `pct restart 110`

**VPN not routing traffic:**
- Check Gluetun logs: `docker compose logs gluetun`
- Verify kill-switch: `docker compose exec nzbget curl ifconfig.me`
- Should show VPS IP, not home IP

**GPU not available in Jellyfin:**
- Verify device passthrough: `ls -l /dev/dri`
- Check permissions: `groups` (should include `render` or `video`)
- Restart Jellyfin: `docker compose restart jellyfin`

**See [docs/troubleshooting.md](docs/troubleshooting.md) for more**

---

## 🤝 Contributing

This is a personal infrastructure project, but if you find it useful:
- ⭐ Star the repository
- 🐛 Report issues
- 💡 Suggest improvements

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details

---

## 🙏 Acknowledgments

Built with knowledge from:
- [LinuxServer.io](https://www.linuxserver.io/) - Excellent Docker images
- [TRaSH Guides](https://trash-guides.info/) - *arr stack configuration
- [Servarr Wiki](https://wiki.servarr.com/) - Sonarr/Radarr documentation
- [Jellyfin Documentation](https://jellyfin.org/docs/)
- Homelab and selfhosted communities on Reddit

Inspired by the principles of:
- Privacy-first computing
- Infrastructure as code
- Self-hosted alternatives to cloud services
- Open-source software

---

## 📊 Project Status

**Current Status:** ✅ Production Ready

**Last Updated:** October 2025

**Tested On:**
- Proxmox VE 8.2
- Debian 12 (Bookworm)
- Docker 24.0.7
- Docker Compose 2.23.0

---

<p align="center">
  <strong>Built with ❤️ for the self-hosted community</strong>
</p>

<p align="center">
  <em>Because your data should be yours</em>
</p>
