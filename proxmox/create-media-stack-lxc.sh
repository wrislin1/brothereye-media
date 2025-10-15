#!/bin/bash
# Brother Eye Media Stack - LXC Container Creation
# Creates LXC 110 (media-stack) on Proxmox host
# Run this on Proxmox host: ./create-media-stack-lxc.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CTID=110
HOSTNAME="media-stack"
IP="192.168.80.110"
GATEWAY="192.168.80.1"
DNS="192.168.10.1"
SEARCHDOMAIN="brothereye.local"
CORES=8
MEMORY=12288  # 16 GB
SWAP=0
DISK=50       # GB
STORAGE="local-lvm"
TEMPLATE="local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"

# Banner
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Brother Eye Media Stack${NC}"
echo -e "${CYAN}   LXC Container Creation${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Check if running on Proxmox
if ! command -v pct &> /dev/null; then
    echo -e "${RED}✗ Error: This script must be run on a Proxmox host${NC}"
    echo ""
    echo "pct command not found. Are you running this on Proxmox VE?"
    exit 1
fi

echo -e "${GREEN}✓ Running on Proxmox host${NC}"
echo ""

# Check if template exists
echo -e "${YELLOW}Checking prerequisites...${NC}"
echo ""

if ! pvesm list local | grep -q "debian-12-standard_12.12-1"; then
    echo -e "${RED}✗ Debian 12 template not found${NC}"
    echo ""
    echo -e "${YELLOW}Download template with:${NC}"
    echo "  pveam update"
    echo "  pveam download local debian-12-standard_12.12-1_amd64.tar.zst"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Debian 12 template found${NC}"
echo ""

# Check storage exists
if ! pvesm status | grep -q "$STORAGE"; then
    echo -e "${RED}✗ Storage '$STORAGE' not found${NC}"
    echo ""
    echo "Available storage:"
    pvesm status
    echo ""
    read -p "Enter storage name to use: " STORAGE
fi

echo -e "${GREEN}✓ Storage '$STORAGE' available${NC}"
echo ""

# Display configuration
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Container Configuration${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo -e "${YELLOW}Container Details:${NC}"
echo -e "  CTID:           ${CYAN}${CTID}${NC}"
echo -e "  Hostname:       ${CYAN}${HOSTNAME}${NC}"
echo -e "  IP Address:     ${CYAN}${IP}/24${NC}"
echo -e "  Gateway:        ${CYAN}${GATEWAY}${NC}"
echo -e "  DNS Server:     ${CYAN}${DNS}${NC}"
echo ""
echo -e "${YELLOW}Resources:${NC}"
echo -e "  CPU Cores:      ${CYAN}${CORES}${NC}"
echo -e "  Memory:         ${CYAN}${MEMORY} MB (12 GB)${NC}"
echo -e "  Swap:           ${CYAN}${SWAP} MB${NC}"
echo -e "  Disk:           ${CYAN}${DISK} GB${NC}"
echo -e "  Storage:        ${CYAN}${STORAGE}${NC}"
echo ""
echo -e "${YELLOW}Features:${NC}"
echo -e "  Nesting:        ${GREEN}Enabled${NC} (for Docker)"
echo -e "  Unprivileged:   ${GREEN}Yes${NC} (security)"
echo -e "  Auto-start:     ${GREEN}Yes${NC} (on boot)"
echo ""

# Check if container already exists
if pct status ${CTID} &>/dev/null; then
    echo -e "${YELLOW}⚠ Warning: Container ${CTID} already exists!${NC}"
    echo ""
    pct status ${CTID}
    echo ""
    pct config ${CTID} | grep -E "hostname|net0"
    echo ""
    
    read -p "Delete and recreate? This will destroy all data! (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Stopping container ${CTID}...${NC}"
        pct stop ${CTID} 2>/dev/null || true
        sleep 3
        
        echo -e "${YELLOW}Destroying container ${CTID}...${NC}"
        pct destroy ${CTID}
        sleep 2
        
        echo -e "${GREEN}✓ Old container removed${NC}"
        echo ""
    else
        echo ""
        echo -e "${BLUE}Operation cancelled${NC}"
        exit 0
    fi
fi

# Confirm creation
echo -e "${YELLOW}Ready to create container${NC}"
echo ""
read -p "Create LXC ${CTID} (${HOSTNAME})? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Operation cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Creating container...${NC}"
echo ""

# Create the container
pct create ${CTID} ${TEMPLATE} \
    --hostname ${HOSTNAME} \
    --cores ${CORES} \
    --memory ${MEMORY} \
    --swap ${SWAP} \
    --storage ${STORAGE} \
    --rootfs ${STORAGE}:${DISK} \
    --net0 name=eth0,bridge=vmbr0,firewall=1,gw=${GATEWAY},ip=${IP}/24,type=veth \
    --nameserver ${DNS} \
    --searchdomain ${SEARCHDOMAIN} \
    --features nesting=1,keyctl=1 \
    --unprivileged 1 \
    --onboot 1 \
    --start 0 \
    --description "Brother Eye Media Stack - Unified Docker container for Jellyfin, Sonarr, Radarr, Prowlarr, NZBGet, Bazarr, Jellyseerr, and Caddy"

# Check creation status
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Container created successfully!${NC}"
else
    echo ""
    echo -e "${RED}✗ Failed to create container${NC}"
    exit 1
fi

# Display result
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}   Container Created Successfully!${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Show container info
echo -e "${YELLOW}Container Status:${NC}"
pct status ${CTID}
echo ""

echo -e "${YELLOW}Container Configuration:${NC}"
pct config ${CTID} | head -20
echo ""

echo -e "${YELLOW}Container List:${NC}"
pct list | grep -E "VMID|${CTID}"
echo ""

# Display next steps
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Next Steps${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

echo -e "${YELLOW}1. Start the container:${NC}"
echo -e "   ${CYAN}pct start ${CTID}${NC}"
echo ""

echo -e "${YELLOW}2. Prepare base system (copy and run scripts inside container):${NC}"
echo -e "   ${CYAN}pct push ${CTID} lxc/setup-base.sh /root/setup-base.sh${NC}"
echo -e "   ${CYAN}pct push ${CTID} lxc/deploy-stack.sh /root/deploy-stack.sh${NC}"
echo -e "   ${CYAN}pct push ${CTID} lxc/manage-stack.sh /root/manage-stack.sh${NC}"
echo -e "   ${CYAN}pct enter ${CTID}${NC}"
echo -e "   ${CYAN}chmod +x /root/*.sh${NC}"
echo -e "   ${CYAN}./setup-base.sh${NC}"
echo -e "   ${CYAN}exit${NC}"
echo ""

echo -e "${YELLOW}3. Mount NFS storage:${NC}"
echo -e "   ${CYAN}pct stop ${CTID}${NC}"
echo -e "   ${CYAN}./bind-mount-storage.sh ${CTID}${NC}"
echo ""

echo -e "${YELLOW}4. Pass GPU for hardware transcoding (optional):${NC}"
echo -e "   ${CYAN}./pass-gpu-to-lxc.sh ${CTID}${NC}"
echo ""

echo -e "${YELLOW}5. Start container and deploy Docker stack:${NC}"
echo -e "   ${CYAN}pct start ${CTID}${NC}"
echo -e "   ${CYAN}pct enter ${CTID}${NC}"
echo -e "   ${CYAN}cd /opt/media-stack${NC}"
echo -e "   ${CYAN}./deploy-stack.sh${NC}"
echo ""

echo -e "${YELLOW}6. Access services:${NC}"
echo -e "   Jellyfin:    ${CYAN}http://${IP}:8096${NC}"
echo -e "   Sonarr:      ${CYAN}http://${IP}:8989${NC}"
echo -e "   Radarr:      ${CYAN}http://${IP}:7878${NC}"
echo -e "   Prowlarr:    ${CYAN}http://${IP}:9696${NC}"
echo -e "   NZBGet:      ${CYAN}http://${IP}:6789${NC}"
echo -e "   Bazarr:      ${CYAN}http://${IP}:6767${NC}"
echo -e "   Jellyseerr:  ${CYAN}http://${IP}:5055${NC}"
echo ""

echo -e "${YELLOW}Useful Commands:${NC}"
echo -e "   ${CYAN}pct start ${CTID}${NC}         # Start container"
echo -e "   ${CYAN}pct stop ${CTID}${NC}          # Stop container"
echo -e "   ${CYAN}pct restart ${CTID}${NC}       # Restart container"
echo -e "   ${CYAN}pct enter ${CTID}${NC}         # Enter container shell"
echo -e "   ${CYAN}pct status ${CTID}${NC}        # Check status"
echo -e "   ${CYAN}pct config ${CTID}${NC}        # View configuration"
echo ""

echo -e "${GREEN}Container ${CTID} (${HOSTNAME}) is ready!${NC}"
echo ""
