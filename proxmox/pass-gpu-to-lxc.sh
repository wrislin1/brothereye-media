#!/bin/bash
# Brother Eye Media Stack - GPU Passthrough Script
# Passes GPU devices from Proxmox host to LXC container
# Enables hardware transcoding in Jellyfin
# Run this on Proxmox host: ./pass-gpu-to-lxc.sh <CTID>
# Example: ./pass-gpu-to-lxc.sh 110

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
RENDER_GID=104  # render group ID in container

# Banner
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Brother Eye Media Stack${NC}"
echo -e "${CYAN}   GPU Passthrough Setup${NC}"
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

# Detect GPU devices on host
echo -e "${YELLOW}Detecting GPU devices on Proxmox host...${NC}"
echo ""

if [ ! -d /dev/dri ]; then
    echo -e "${RED}✗ Error: /dev/dri directory not found${NC}"
    echo ""
    echo "No GPU devices detected on this system."
    echo "GPU passthrough requires a GPU with video acceleration support."
    echo ""
    exit 1
fi

echo -e "${CYAN}Available DRI devices:${NC}"
ls -la /dev/dri/
echo ""

# Check for render node
if [ ! -e /dev/dri/renderD128 ]; then
    echo -e "${YELLOW}⚠ Warning: /dev/dri/renderD128 not found${NC}"
    echo "This is required for VAAPI. System may not support hardware acceleration."
    echo ""
fi

# Count GPU cards
CARD_COUNT=$(ls -1 /dev/dri/card* 2>/dev/null | wc -l)

if [ $CARD_COUNT -eq 0 ]; then
    echo -e "${RED}✗ Error: No GPU card devices found${NC}"
    echo ""
    echo "Expected to find /dev/dri/card0, card1, etc."
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Found ${CARD_COUNT} GPU card(s)${NC}"
echo ""

# Select GPU card
if [ $CARD_COUNT -eq 1 ]; then
    GPU_CARD=$(ls /dev/dri/card* | head -1)
    echo -e "${BLUE}Automatically selecting: ${GPU_CARD}${NC}"
    echo ""
else
    echo -e "${YELLOW}Multiple GPUs detected:${NC}"
    ls -la /dev/dri/card*
    echo ""
    echo -e "${YELLOW}Which GPU to pass through?${NC}"
    select GPU_CARD in $(ls /dev/dri/card*); do
        if [ -n "$GPU_CARD" ]; then
            break
        fi
    done
    echo ""
    echo -e "${BLUE}Selected: ${GPU_CARD}${NC}"
    echo ""
fi

# Extract card number (e.g., /dev/dri/card1 → card1)
GPU_CARD_NAME=$(basename $GPU_CARD)

# Display GPU info (if available)
echo -e "${YELLOW}GPU Information:${NC}"
if command -v lspci &> /dev/null; then
    lspci | grep -i vga
    lspci | grep -i 3d
    echo ""
fi

# Display configuration
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Passthrough Configuration${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo -e "${YELLOW}Devices to pass:${NC}"
echo -e "  Device 0: ${CYAN}${GPU_CARD}${NC} (GPU card)"
echo -e "  Device 1: ${CYAN}/dev/dri/renderD128${NC} (Render node for VAAPI)"
echo ""
echo -e "${YELLOW}Group ID:${NC}"
echo -e "  GID: ${CYAN}${RENDER_GID}${NC} (render group in container)"
echo ""
echo -e "${YELLOW}Purpose:${NC}"
echo -e "  Enable hardware transcoding in Jellyfin"
echo -e "  Reduce CPU usage from 100% to ~5% during transcode"
echo -e "  Support multiple concurrent streams"
echo ""

# Check if devices already passed
EXISTING_DEVS=$(pct config ${CTID} | grep "^dev" || true)

if [ -n "$EXISTING_DEVS" ]; then
    echo -e "${YELLOW}⚠ Existing device passthroughs found:${NC}"
    echo "$EXISTING_DEVS"
    echo ""
    
    read -p "Remove existing devices and recreate? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Removing existing devices...${NC}"
        
        # Remove all dev entries
        for dev in $(echo "$EXISTING_DEVS" | cut -d: -f1); do
            pct set ${CTID} -delete ${dev}
            echo -e "${GREEN}✓ Removed ${dev}${NC}"
        done
        echo ""
    else
        echo ""
        echo -e "${BLUE}Keeping existing devices${NC}"
        echo "Note: New devices will be added with next available dev number"
        echo ""
    fi
fi

# Confirm
read -p "Pass GPU devices to container ${CTID}? (y/N): " -n 1 -r
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
    echo -e "${YELLOW}Stopping container to modify device configuration...${NC}"
    
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

# Pass GPU devices
echo -e "${YELLOW}Passing GPU devices to container...${NC}"
echo ""

# Device 0: GPU card
echo -e "Passing device 0 (${GPU_CARD_NAME})..."
pct set ${CTID} -dev0 ${GPU_CARD},gid=${RENDER_GID}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ GPU card passed: ${GPU_CARD} → dev0${NC}"
else
    echo -e "${RED}✗ Failed to pass GPU card${NC}"
    exit 1
fi

# Device 1: Render node (required for VAAPI)
if [ -e /dev/dri/renderD128 ]; then
    echo -e "Passing device 1 (renderD128)..."
    pct set ${CTID} -dev1 /dev/dri/renderD128,gid=${RENDER_GID}
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Render node passed: /dev/dri/renderD128 → dev1${NC}"
    else
        echo -e "${RED}✗ Failed to pass render node${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ Skipping renderD128 (not found on host)${NC}"
fi

echo ""

# Verify configuration
echo -e "${YELLOW}Verifying device configuration...${NC}"
echo ""

pct config ${CTID} | grep "^dev"
echo ""

# Start container
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

# Verify devices inside container
echo -e "${YELLOW}Verifying GPU devices inside container...${NC}"
echo ""

sleep 3  # Give container time to fully initialize

echo -e "${CYAN}DRI devices in container:${NC}"
if pct exec ${CTID} -- test -d /dev/dri; then
    pct exec ${CTID} -- ls -la /dev/dri/
    echo ""
    echo -e "${GREEN}✓ GPU devices visible in container${NC}"
else
    echo -e "${RED}✗ /dev/dri not found in container${NC}"
    echo ""
fi
echo ""

# Check render group
echo -e "${CYAN}Checking render group in container:${NC}"
pct exec ${CTID} -- getent group render || echo "render:x:${RENDER_GID}:"
echo ""

# Test VAAPI (if container has vainfo)
echo -e "${CYAN}Testing VAAPI support:${NC}"
if pct exec ${CTID} -- command -v vainfo &>/dev/null; then
    pct exec ${CTID} -- vainfo 2>&1 | head -20 || true
else
    echo -e "${YELLOW}vainfo not installed in container${NC}"
    echo "This will be available once Jellyfin container is running"
fi
echo ""

# Success summary
echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}   GPU Passthrough Configured Successfully!${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

echo -e "${YELLOW}Configuration Summary:${NC}"
echo ""
echo -e "  ${CYAN}Proxmox Host:${NC}"
echo -e "    ${GPU_CARD}"
echo -e "    /dev/dri/renderD128"
echo ""
echo -e "  ${CYAN}↓ Passed to ↓${NC}"
echo ""
echo -e "  ${CYAN}LXC ${CTID}:${NC}"
echo -e "    /dev/dri/${GPU_CARD_NAME} (dev0)"
echo -e "    /dev/dri/renderD128 (dev1)"
echo -e "    Group: render (${RENDER_GID})"
echo ""
echo -e "  ${CYAN}↓ Mounted to ↓${NC}"
echo ""
echo -e "  ${CYAN}Jellyfin Container:${NC}"
echo -e "    devices: [/dev/dri:/dev/dri]"
echo -e "    group_add: [${RENDER_GID}]"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo -e "1. ${CYAN}Deploy Docker stack (if not already done):${NC}"
echo -e "   pct enter ${CTID}"
echo -e "   cd /opt/media-stack"
echo -e "   ./deploy-stack.sh"
echo ""
echo -e "2. ${CYAN}Configure Jellyfin hardware acceleration:${NC}"
echo -e "   • Open Jellyfin: http://192.168.80.110:8096"
echo -e "   • Dashboard → Playback → Transcoding"
echo -e "   • Hardware acceleration: ${CYAN}VAAPI${NC}"
echo -e "   • VA API Device: ${CYAN}/dev/dri/renderD128${NC}"
echo -e "   • Enable hardware decoding: ${CYAN}All formats${NC}"
echo -e "   • Save settings"
echo ""
echo -e "3. ${CYAN}Test hardware transcoding:${NC}"
echo -e "   • Play a video in Jellyfin"
echo -e "   • Select a quality lower than source (forces transcode)"
echo -e "   • On Proxmox host, monitor GPU usage:"
echo -e "     ${BLUE}# For Intel:${NC}  intel_gpu_top"
echo -e "     ${BLUE}# For AMD:${NC}    radeontop"
echo -e "     ${BLUE}# For Nvidia:${NC} nvidia-smi -l 1"
echo ""

echo -e "${YELLOW}Troubleshooting:${NC}"
echo ""
echo -e "  ${CYAN}If transcoding still uses CPU:${NC}"
echo -e "  • Verify Jellyfin sees GPU: Dashboard → Playback"
echo -e "  • Check Jellyfin logs: docker compose logs jellyfin | grep -i vaapi"
echo -e "  • Ensure VAAPI selected (not None or QSV)"
echo -e "  • Restart Jellyfin: docker compose restart jellyfin"
echo ""
echo -e "  ${CYAN}If devices not visible in container:${NC}"
echo -e "  • pct exec ${CTID} -- ls -l /dev/dri"
echo -e "  • Restart container: pct restart ${CTID}"
echo ""

echo -e "${GREEN}GPU passthrough is ready! 🎮${NC}"
echo ""
