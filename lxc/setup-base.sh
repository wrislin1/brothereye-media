#!/bin/bash
################################################################################
# Brother Eye Media Stack - LXC Base Setup Script
# 
# This script prepares an LXC container (110) for the Docker-based media stack.
# It installs Docker, creates users, sets up directories, and configures logging.
#
# Usage: Run this script INSIDE the LXC container as root
#   ./setup-base.sh
#
# Prerequisites:
#   - LXC 110 already created (via proxmox/create-media-stack-lxc.sh)
#   - NFS storage mounted (via proxmox/bind-mount-storage.sh)
#   - Internet connectivity for package downloads
#
# What this script does:
#   1. Updates system packages
#   2. Installs Docker Engine (official repository)
#   3. Creates mediauser (UID 1000, GID 100)
#   4. Sets up directory structure for configs and logs
#   5. Configures Docker daemon with logging limits
#   6. Installs git-crypt and GPG for secrets management
#   7. Performs verification checks
#
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
MEDIAUSER="mediauser"
MEDIAUSER_UID=1000
MEDIAUSER_GID=100
DOCKER_DIR="/opt/docker"
CONFIG_DIR="${DOCKER_DIR}/config"
COMPOSE_DIR="${DOCKER_DIR}/compose"
LOG_DIR="/var/log/docker"
MEDIA_MOUNT="/mnt/media"

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_internet() {
    log_info "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "No internet connectivity. Please check network configuration."
        exit 1
    fi
    log_success "Internet connectivity verified"
}

################################################################################
# System Update
################################################################################

update_system() {
    log_info "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        git \
        vim \
        htop \
        ncdu \
        rsync
    log_success "System packages updated"
}

################################################################################
# Docker Installation
################################################################################

install_docker() {
    log_info "Checking if Docker is already installed..."
    
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_warning "Docker is already installed (version: ${DOCKER_VERSION})"
        read -p "Do you want to reinstall Docker? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping Docker installation"
            return 0
        fi
    fi

    log_info "Installing Docker Engine from official repository..."
    
    # Remove old versions if present
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker Engine installed successfully"
    docker --version
}

################################################################################
# Docker Configuration
################################################################################

configure_docker() {
    log_info "Configuring Docker daemon..."
    
    # Create Docker config directory
    mkdir -p /etc/docker
    
    # Configure Docker daemon with logging limits and other optimizations
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "userland-proxy": false,
  "live-restore": true
}
EOF
    
    # Restart Docker to apply changes
    systemctl restart docker
    
    log_success "Docker daemon configured"
}

################################################################################
# User Creation
################################################################################

create_mediauser() {
    log_info "Creating mediauser (UID: ${MEDIAUSER_UID}, GID: ${MEDIAUSER_GID})..."
    
    # Check if group exists
    if getent group ${MEDIAUSER_GID} &> /dev/null; then
        EXISTING_GROUP=$(getent group ${MEDIAUSER_GID} | cut -d: -f1)
        log_warning "GID ${MEDIAUSER_GID} already exists (group: ${EXISTING_GROUP})"
    else
        groupadd -g ${MEDIAUSER_GID} ${MEDIAUSER}
        log_success "Group '${MEDIAUSER}' created with GID ${MEDIAUSER_GID}"
    fi
    
    # Check if user exists
    if id "${MEDIAUSER}" &> /dev/null; then
        EXISTING_UID=$(id -u ${MEDIAUSER})
        EXISTING_GID=$(id -g ${MEDIAUSER})
        log_warning "User '${MEDIAUSER}' already exists (UID: ${EXISTING_UID}, GID: ${EXISTING_GID})"
        
        if [[ ${EXISTING_UID} -ne ${MEDIAUSER_UID} ]] || [[ ${EXISTING_GID} -ne ${MEDIAUSER_GID} ]]; then
            log_error "Existing user has different UID/GID. Please manually resolve this conflict."
            exit 1
        fi
    else
        useradd -u ${MEDIAUSER_UID} -g ${MEDIAUSER_GID} -m -s /bin/bash ${MEDIAUSER}
        log_success "User '${MEDIAUSER}' created with UID ${MEDIAUSER_UID}"
    fi
    
    # Add mediauser to docker group
    usermod -aG docker ${MEDIAUSER}
    log_success "User '${MEDIAUSER}' added to docker group"
}

################################################################################
# Directory Structure
################################################################################

create_directories() {
    log_info "Creating directory structure..."
    
    # Create main Docker directory
    mkdir -p ${DOCKER_DIR}
    mkdir -p ${CONFIG_DIR}
    mkdir -p ${COMPOSE_DIR}
    mkdir -p ${LOG_DIR}
    
    # Create subdirectories for each service
    local services=("jellyfin" "sonarr" "radarr" "prowlarr" "nzbget" "gluetun" "bazarr" "jellyseerr" "caddy")
    for service in "${services[@]}"; do
        mkdir -p ${CONFIG_DIR}/${service}
        log_info "  Created config directory for ${service}"
    done
    
    # Set ownership
    chown -R ${MEDIAUSER}:${MEDIAUSER_GID} ${DOCKER_DIR}
    chown -R ${MEDIAUSER}:${MEDIAUSER_GID} ${LOG_DIR}
    
    # Set permissions
    chmod -R 755 ${DOCKER_DIR}
    chmod -R 755 ${LOG_DIR}
    
    log_success "Directory structure created"
}

################################################################################
# Git and Encryption Tools
################################################################################

install_git_crypt() {
    log_info "Installing git-crypt and GPG tools..."
    
    apt-get install -y git-crypt gnupg2
    
    log_success "git-crypt and GPG tools installed"
}

################################################################################
# Verify Mount Points
################################################################################

verify_storage() {
    log_info "Verifying storage mount points..."
    
    if [[ ! -d "${MEDIA_MOUNT}" ]]; then
        log_warning "Media mount point ${MEDIA_MOUNT} does not exist"
        log_warning "You may need to run the bind-mount-storage.sh script on Proxmox host"
    elif mountpoint -q "${MEDIA_MOUNT}"; then
        log_success "Media storage mounted at ${MEDIA_MOUNT}"
        
        # Check permissions
        if [[ -w "${MEDIA_MOUNT}" ]]; then
            log_success "Media storage is writable"
        else
            log_warning "Media storage is not writable. Check permissions."
        fi
    else
        log_warning "${MEDIA_MOUNT} exists but is not a mount point"
    fi
}

################################################################################
# System Hardening (Optional)
################################################################################

basic_hardening() {
    log_info "Applying basic system hardening..."
    
    # Enable automatic security updates (optional)
    apt-get install -y unattended-upgrades
    dpkg-reconfigure -plow unattended-upgrades
    
    # Configure firewall (if needed)
    if command -v ufw &> /dev/null; then
        log_info "UFW detected. Configure manually if needed."
    fi
    
    log_success "Basic hardening applied"
}

################################################################################
# Verification
################################################################################

verify_installation() {
    log_info "Verifying installation..."
    
    # Check Docker
    if ! docker run --rm hello-world &> /dev/null; then
        log_error "Docker verification failed"
        exit 1
    fi
    log_success "Docker is working correctly"
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose plugin not found"
        exit 1
    fi
    log_success "Docker Compose plugin is available"
    
    # Check user
    if ! id ${MEDIAUSER} &> /dev/null; then
        log_error "User '${MEDIAUSER}' not found"
        exit 1
    fi
    log_success "User '${MEDIAUSER}' exists"
    
    # Check directories
    if [[ ! -d "${DOCKER_DIR}" ]]; then
        log_error "Docker directory not found"
        exit 1
    fi
    log_success "Directory structure verified"
    
    # Check git-crypt
    if ! command -v git-crypt &> /dev/null; then
        log_error "git-crypt not installed"
        exit 1
    fi
    log_success "git-crypt is installed"
}

################################################################################
# Display Summary
################################################################################

display_summary() {
    echo
    echo "=========================================="
    echo "  Brother Eye LXC Setup Complete!"
    echo "=========================================="
    echo
    echo "System Information:"
    echo "  - Docker Version: $(docker --version | awk '{print $3}' | sed 's/,//')"
    echo "  - Docker Compose: $(docker compose version | awk '{print $4}')"
    echo "  - Media User: ${MEDIAUSER} (UID: ${MEDIAUSER_UID}, GID: ${MEDIAUSER_GID})"
    echo
    echo "Directories Created:"
    echo "  - Docker Root: ${DOCKER_DIR}"
    echo "  - Configs: ${CONFIG_DIR}"
    echo "  - Compose Files: ${COMPOSE_DIR}"
    echo "  - Logs: ${LOG_DIR}"
    echo
    echo "Next Steps:"
    echo "  1. Clone your Brother Eye repository to ${DOCKER_DIR}"
    echo "  2. Set up git-crypt with your GPG key"
    echo "  3. Run deploy-stack.sh to start all containers"
    echo
    echo "Useful Commands:"
    echo "  - Switch to mediauser: su - ${MEDIAUSER}"
    echo "  - Check Docker: docker ps"
    echo "  - View logs: docker compose logs -f"
    echo
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "Starting Brother Eye LXC base setup..."
    echo
    
    check_root
    check_internet
    
    update_system
    install_docker
    configure_docker
    create_mediauser
    create_directories
    install_git_crypt
    verify_storage
    basic_hardening
    verify_installation
    
    display_summary
    
    log_success "Setup complete! Your LXC container is ready for the Docker stack."
}

# Run main function
main "$@"
