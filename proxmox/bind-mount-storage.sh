#!/bin/bash
# Brother Eye Media Stack - Storage Bind Mount Script
# Binds NFS storage from Proxmox host into LXC container
# Run this on Proxmox host: ./bind-mount-storage.sh <CTID>
# Example: ./bind-mount-storage.sh 110

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NFS_MOUNT_POINT="/mnt/pve/nas"
MEDIA_SOURCE="${NFS_MOUNT_POINT}/Media"
DOWNLOADS_SOURCE="${NFS_MOUNT_POINT}/Downloads"

# Banner
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Brother Eye Media Stack${NC}"
echo -e "${CYAN}   Storage Bind Mount Setup${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Check if running on Proxmox
if ! command -v pct &> /dev/null; then
    echo -e "${RED}✗ Error: This script must be run on a Proxmox host${NC}"
    exit 1
fi

# Check arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}✗ Error: No container ID specified${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 <CTID>"
    echo ""
    echo -e "${YELLOW}Example:${NC}"
    echo "  $0 110"
    echo ""
    exit 1
fi

CTID=$1

echo -e "${YELLOW}Target Container: ${CYAN}${CTID}${NC}"
echo ""

# Verify container exists
if ! pct status ${CTID} &>/dev/null; then
    echo -e "${RED}✗ Error: Container ${CTID} does not exist${NC}"
    echo ""
    echo -e "${YELLOW}Available containers:${NC}"
    pct list
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Container ${CTID} exists${NC}"
echo ""

# Check if NFS is mounted on host
echo -e "${YELLOW}Checking NFS mount on Proxmox host...${NC}"
echo ""

if ! mountpoint -q ${NFS_MOUNT_POINT}; then
    echo -e "${RED}✗ Error: NFS not mounted at ${NFS_MOUNT_POINT}${NC}"
    echo ""
    echo -e "${YELLOW}Mount NFS first with:${NC}"
    echo "  mkdir -p ${NFS_MOUNT_POINT}"
    echo "  mount -t nfs4 192.168.70.10:/ ${NFS_MOUNT_POINT}"
    echo ""
    echo -e "${YELLOW}Or run the NFS setup script:${NC}"
    echo "  ./setup-nfs-on-proxmox.sh"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ NFS mounted at ${NFS_MOUNT_POINT}${NC}"
echo ""

# Verify source directories exist
echo -e "${YELLOW}Verifying source directories...${NC}"
echo ""

if [ ! -d "${MEDIA_SOURCE}" ]; then
    echo -e "${RED}✗ Error: Media directory not found: ${MEDIA_SOURCE}${NC}"
    echo ""
    echo "Available directories:"
    ls -la ${NFS_MOUNT_POINT}
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Media directory found: ${MEDIA_SOURCE}${NC}"

if [ ! -d "${DOWNLOADS_SOURCE}" ]; then
    echo -e "${RED}✗ Error: Downloads directory not found: ${DOWNLOADS_SOURCE}${NC}"
    echo ""
    echo "Available directories:"
    ls -la ${NFS_MOUNT_POINT}
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Downloads directory found: ${DOWNLOADS_SOURCE}${NC}"
echo ""

# Check if bind mounts already exist
echo -e "${YELLOW}Checking existing mounts...${NC}"
echo ""

EXISTING_MOUNTS=$(pct config ${CTID} | grep "^mp" || true)

if [ -n "$EXISTING_MOUNTS" ]; then
    echo -e "${YELLOW}⚠ Existing mount points found:${NC}"
    echo "$EXISTING_MOUNTS"
    echo ""
    
    read -p "Remove existing mounts and recreate? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Removing existing mount points...${NC}"
        
        # Remove all mp entries
        for mp in $(echo "$EXISTING_MOUNTS" | cut -d: -f1); do
            pct set ${CTID} -delete ${mp}
            echo -e "${GREEN}✓ Removed ${mp}${NC}"
        done
        echo ""
    else
        echo ""
        echo -e "${BLUE}Keeping existing mounts${NC}"
        echo "Note: New mounts will be added with next available mp number"
        echo ""
    fi
fi

# Display mount configuration
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Mount Configuration${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo -e "${YELLOW}Mount Point 0 (Media - Read/Write):${NC}"
echo -e "  Source:      ${CYAN}${MEDIA_SOURCE}${NC}"
echo -e "  Destination: ${CYAN}/mnt/media${NC}"
echo -e "  Access:      ${CYAN}Read/Write${NC}"
echo ""
echo -e "${YELLOW}Mount Point 1 (Downloads - Read/Write):${NC}"
echo -e "  Source:      ${CYAN}${DOWNLOADS_SOURCE}${NC}"
echo -e "  Destination: ${CYAN}/mnt/downloads${NC}"
echo -e "  Access:      ${CYAN}Read/Write${NC}"
echo ""

# Confirm
read -p "Create bind mounts in container ${CTID}? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Operation cancelled${NC}"
    exit 0
fi

echo ""

# Check if container is running
CONTAINER_STATUS=$(pct status ${CTID} | awk '{print $2}')

if [ "$CONTAINER_STATUS" = "running" ]; then
    echo -e "${YELLOW}Container ${CTID} is running${NC}"
    echo -e "${YELLOW}Stopping container to modify mount configuration...${NC}"
    
    pct stop ${CTID}
    
    # Wait for complete shutdown
    echo -n "Waiting for shutdown"
    for i in {1..10}; do
        sleep 1
        echo -n "."
        if [ "$(pct status ${CTID} | awk '{print $2}')" = "stopped" ]; then
            break
        fi
    done
    echo ""
    echo -e "${GREEN}✓ Container stopped${NC}"
    echo ""
    
    NEED_START=true
else
    echo -e "${BLUE}Container ${CTID} is already stopped${NC}"
    echo ""
    NEED_START=false
fi

# Create bind mounts
echo -e "${YELLOW}Creating bind mounts...${NC}"
echo ""

# Mount Point 0: Media (read/write for Sonarr/Radarr to organize files)
echo -e "Creating mp0 (Media)..."
pct set ${CTID} -mp0 ${MEDIA_SOURCE},mp=/mnt/media

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Media mount created: ${MEDIA_SOURCE} → /mnt/media${NC}"
else
    echo -e "${RED}✗ Failed to create media mount${NC}"
    exit 1
fi

# Mount Point 1: Downloads (read/write for NZBGet and import)
echo -e "Creating mp1 (Downloads)..."
pct set ${CTID} -mp1 ${DOWNLOADS_SOURCE},mp=/mnt/downloads

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Downloads mount created: ${DOWNLOADS_SOURCE} → /mnt/downloads${NC}"
else
    echo -e "${RED}✗ Failed to create downloads mount${NC}"
    exit 1
fi

echo ""

# Verify configuration
echo -e "${YELLOW}Verifying mount configuration...${NC}"
echo ""

pct config ${CTID} | grep "^mp"
echo ""

# Start container if it was running
if [ "$NEED_START" = true ]; then
    echo -e "${YELLOW}Starting container ${CTID}...${NC}"
    pct start ${CTID}
    
    # Wait for startup
    echo -n "Waiting for startup"
    for i in {1..15}; do
        sleep 1
        echo -n "."
        if [ "$(pct status ${CTID} | awk '{print $2}')" = "running" ]; then
            break
        fi
    done
    echo ""
    echo -e "${GREEN}✓ Container started${NC}"
    echo ""
fi

# Verify mounts inside container
echo -e "${YELLOW}Verifying mounts inside container...${NC}"
echo ""

sleep 3  # Give container time to fully initialize

echo -e "${CYAN}Mount points:${NC}"
pct exec ${CTID} -- df -h | grep -E "Filesystem|/mnt" || true
echo ""

echo -e "${CYAN}Media directory:${NC}"
if pct exec ${CTID} -- test -d /mnt/media; then
    echo -e "${GREEN}✓ /mnt/media exists${NC}"
    pct exec ${CTID} -- ls -la /mnt/media | head -10
else
    echo -e "${RED}✗ /mnt/media not found${NC}"
fi
echo ""

echo -e "${CYAN}Downloads directory:${NC}"
if pct exec ${CTID} -- test -d /mnt/downloads; then
    echo -e "${GREEN}✓ /mnt/downloads exists${NC}"
    pct exec ${CTID} -- ls -la /mnt/downloads | head -10
else
    echo -e "${RED}✗ /mnt/downloads not found${NC}"
fi
echo ""

# Success summary
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}   Bind Mounts Created Successfully!${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

echo -e "${YELLOW}Configuration Summary:${NC}"
echo ""
echo -e "  ${CYAN}Proxmox Host:${NC}"
echo -e "    ${MEDIA_SOURCE}"
echo -e "    ${DOWNLOADS_SOURCE}"
echo ""
echo -e "  ${CYAN}↓ Bind Mounted Into ↓${NC}"
echo ""
echo -e "  ${CYAN}LXC ${CTID}:${NC}"
echo -e "    /mnt/media"
echo -e "    /mnt/downloads"
echo ""
echo -e "  ${CYAN}↓ Docker Volumes ↓${NC}"
echo ""
echo -e "  ${CYAN}Docker Containers:${NC}"
echo -e "    Jellyfin:  /media (read-only)"
echo -e "    Sonarr:    /media + /downloads (read-write)"
echo -e "    Radarr:    /media + /downloads (read-write)"
echo -e "    NZBGet:    /downloads (read-write)"
echo -e "    Bazarr:    /media (read-write)"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo -e "1. ${CYAN}Pass GPU to container (optional for Jellyfin transcoding):${NC}"
echo -e "   ./pass-gpu-to-lxc.sh ${CTID}"
echo ""
echo -e "2. ${CYAN}Copy Docker Compose files:${NC}"
echo -e "   pct push ${CTID} docker/docker-compose.yml /opt/media-stack/docker-compose.yml"
echo -e "   pct push ${CTID} docker/.env.production /opt/media-stack/.env"
echo -e "   pct push ${CTID} -r docker/compose /opt/media-stack/compose"
echo ""
echo -e "3. ${CYAN}Deploy the stack:${NC}"
echo -e "   pct enter ${CTID}"
echo -e "   cd /opt/media-stack"
echo -e "   ./deploy-stack.sh"
echo ""

echo -e "${GREEN}Storage is ready! 🎉${NC}"
echo ""
