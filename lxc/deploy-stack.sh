#!/bin/bash
################################################################################
# Brother Eye Media Stack - Deployment Script
# 
# This script deploys the complete Docker-based media stack inside LXC 110.
# It clones the repository, decrypts secrets, and starts all containers.
#
# Usage: Run this script INSIDE the LXC container as mediauser
#   ./deploy-stack.sh [--clean] [--skip-git]
#
# Options:
#   --clean     Remove existing deployment and start fresh
#   --skip-git  Skip git clone/pull (use existing repository)
#
# Prerequisites:
#   - setup-base.sh already executed
#   - GPG key imported for git-crypt decryption
#   - Network connectivity to GitHub and Docker Hub
#
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="git@github.com:yourusername/brother-eye-media-stack.git"  # UPDATE THIS
DOCKER_DIR="/opt/docker"
REPO_DIR="${DOCKER_DIR}/brother-eye-media-stack"
COMPOSE_FILE="${REPO_DIR}/docker/docker-compose.yml"
ENV_EXAMPLE="${REPO_DIR}/docker/.env.example"
ENV_PROD="${REPO_DIR}/secrets/.env.production"
REQUIRED_USER="mediauser"
LXC_IP="192.168.80.10"  # UPDATE if different

# Parse command line arguments
CLEAN_DEPLOY=false
SKIP_GIT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_DEPLOY=true
            shift
            ;;
        --skip-git)
            SKIP_GIT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--clean] [--skip-git]"
            exit 1
            ;;
    esac
done

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

log_step() {
    echo
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

check_user() {
    if [[ $(whoami) != "${REQUIRED_USER}" ]]; then
        log_error "This script must be run as ${REQUIRED_USER}"
        log_info "Switch user with: su - ${REQUIRED_USER}"
        exit 1
    fi
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    local deps=("docker" "git" "git-crypt" "gpg")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Please run setup-base.sh first"
        exit 1
    fi
    
    log_success "All dependencies found"
}

check_docker() {
    log_info "Checking Docker daemon..."
    
    if ! docker ps &> /dev/null; then
        log_error "Cannot connect to Docker daemon"
        log_info "Ensure Docker is running and you're in the docker group"
        exit 1
    fi
    
    log_success "Docker daemon is accessible"
}

################################################################################
# Git Operations
################################################################################

clone_or_update_repo() {
    if [[ "${SKIP_GIT}" == true ]]; then
        log_warning "Skipping git operations (--skip-git flag)"
        
        if [[ ! -d "${REPO_DIR}" ]]; then
            log_error "Repository directory not found: ${REPO_DIR}"
            log_info "Remove --skip-git flag to clone the repository"
            exit 1
        fi
        
        return 0
    fi
    
    log_step "Git Repository Management"
    
    if [[ -d "${REPO_DIR}" ]]; then
        if [[ "${CLEAN_DEPLOY}" == true ]]; then
            log_warning "Removing existing repository (--clean flag)"
            rm -rf "${REPO_DIR}"
        else
            log_info "Repository exists. Pulling latest changes..."
            cd "${REPO_DIR}"
            
            # Stash any local changes
            if ! git diff-index --quiet HEAD --; then
                log_warning "Uncommitted changes detected. Stashing..."
                git stash
            fi
            
            git pull
            log_success "Repository updated"
            return 0
        fi
    fi
    
    log_info "Cloning repository from ${REPO_URL}..."
    
    # Ensure parent directory exists
    mkdir -p "${DOCKER_DIR}"
    cd "${DOCKER_DIR}"
    
    # Clone the repository
    if ! git clone "${REPO_URL}"; then
        log_error "Failed to clone repository"
        log_info "Ensure:"
        log_info "  1. SSH key is configured: ssh -T git@github.com"
        log_info "  2. Repository URL is correct in this script"
        log_info "  3. You have access to the repository"
        exit 1
    fi
    
    log_success "Repository cloned successfully"
}

################################################################################
# Secret Management
################################################################################

setup_git_crypt() {
    log_step "Secret Decryption (git-crypt)"
    
    cd "${REPO_DIR}"
    
    # Check if git-crypt is already unlocked
    if git-crypt status &> /dev/null; then
        log_success "Repository is already unlocked"
        return 0
    fi
    
    log_info "Unlocking encrypted secrets..."
    
    # Check if GPG key is available
    if ! gpg --list-keys &> /dev/null; then
        log_error "No GPG keys found"
        log_info "Import your GPG key first:"
        log_info "  gpg --import /path/to/your/private-key.asc"
        exit 1
    fi
    
    # Attempt to unlock
    if ! git-crypt unlock; then
        log_error "Failed to unlock repository"
        log_info "Possible reasons:"
        log_info "  1. GPG key not imported"
        log_info "  2. GPG key not added to git-crypt (check .git-crypt/keys)"
        log_info "  3. Wrong GPG key"
        exit 1
    fi
    
    log_success "Secrets decrypted successfully"
}

setup_environment() {
    log_step "Environment Configuration"
    
    cd "${REPO_DIR}/docker"
    
    # Check if production .env exists
    if [[ -f "${ENV_PROD}" ]]; then
        log_success "Production environment file found: ${ENV_PROD}"
        
        # Verify it's decrypted (check if it contains actual values, not encrypted data)
        if file "${ENV_PROD}" | grep -q "GPG"; then
            log_error "Environment file is still encrypted"
            log_info "Ensure git-crypt unlock succeeded"
            exit 1
        fi
    else
        log_warning "Production .env not found at: ${ENV_PROD}"
        
        # Check if .env.example exists
        if [[ ! -f "${ENV_EXAMPLE}" ]]; then
            log_error ".env.example not found at: ${ENV_EXAMPLE}"
            exit 1
        fi
        
        log_info "Creating .env.production from .env.example..."
        mkdir -p "$(dirname ${ENV_PROD})"
        cp "${ENV_EXAMPLE}" "${ENV_PROD}"
        
        log_warning "IMPORTANT: Edit ${ENV_PROD} with your actual values before proceeding"
        log_info "Required values to set:"
        log_info "  - VPN credentials (WIREGUARD_PRIVATE_KEY, etc.)"
        log_info "  - API keys (PROWLARR_API_KEY, etc.)"
        log_info "  - Passwords and tokens"
        echo
        read -p "Press Enter after editing .env.production, or Ctrl+C to abort..."
    fi
    
    # Create symlink for docker compose to find .env
    if [[ ! -L "${REPO_DIR}/docker/.env" ]]; then
        log_info "Creating .env symlink..."
        ln -sf "${ENV_PROD}" "${REPO_DIR}/docker/.env"
    fi
    
    log_success "Environment configured"
}

################################################################################
# Docker Deployment
################################################################################

pull_docker_images() {
    log_step "Pulling Docker Images"
    
    cd "${REPO_DIR}/docker"
    
    log_info "This may take several minutes depending on your connection..."
    
    if ! docker compose pull; then
        log_warning "Some images failed to pull, but continuing..."
    else
        log_success "All Docker images pulled"
    fi
}

start_containers() {
    log_step "Starting Docker Containers"
    
    cd "${REPO_DIR}/docker"
    
    if [[ "${CLEAN_DEPLOY}" == true ]]; then
        log_info "Removing existing containers (--clean flag)..."
        docker compose down -v 2>/dev/null || true
    fi
    
    log_info "Starting all services..."
    
    # Start containers in detached mode
    if ! docker compose up -d; then
        log_error "Failed to start containers"
        log_info "Check logs with: docker compose logs"
        exit 1
    fi
    
    log_success "Containers started"
}

wait_for_services() {
    log_step "Waiting for Services to Initialize"
    
    log_info "Giving services 30 seconds to start up..."
    
    for i in {1..30}; do
        echo -n "."
        sleep 1
    done
    echo
    
    log_success "Initial startup period complete"
}

################################################################################
# Verification
################################################################################

verify_deployment() {
    log_step "Verifying Deployment"
    
    cd "${REPO_DIR}/docker"
    
    # Get container status
    local running=$(docker compose ps --format json | jq -r '. | select(.State == "running") | .Service' | wc -l)
    local total=$(docker compose ps --format json | jq -r '.Service' | wc -l)
    
    log_info "Container Status: ${running}/${total} running"
    
    # Display container states
    echo
    docker compose ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}"
    echo
    
    # Check for any containers that are not running
    local not_running=$(docker compose ps --format json | jq -r '. | select(.State != "running") | .Service')
    
    if [[ -n "${not_running}" ]]; then
        log_warning "Some containers are not running:"
        echo "${not_running}"
        echo
        log_info "Check logs with: docker compose logs <service_name>"
    else
        log_success "All containers are running!"
    fi
    
    # Check VPN connectivity (Gluetun)
    if docker compose ps gluetun --format json | jq -r '.State' | grep -q "running"; then
        log_info "Checking VPN connection..."
        sleep 5  # Give Gluetun time to establish VPN
        
        local vpn_ip=$(docker compose exec -T gluetun wget -qO- ifconfig.me 2>/dev/null || echo "unknown")
        log_info "VPN Exit IP: ${vpn_ip}"
        
        if [[ "${vpn_ip}" == "unknown" ]]; then
            log_warning "Could not verify VPN connection"
        fi
    fi
}

################################################################################
# Display Access Information
################################################################################

display_access_info() {
    log_step "Access Information"
    
    cat <<EOF

${GREEN}Brother Eye Media Stack - Deployed Successfully!${NC}

${CYAN}Service Access URLs:${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ${YELLOW}Media Server:${NC}
    Jellyfin        http://${LXC_IP}:8096

  ${YELLOW}Download Management:${NC}
    NZBGet          http://${LXC_IP}:6789
    Prowlarr        http://${LXC_IP}:9696

  ${YELLOW}Content Automation:${NC}
    Sonarr          http://${LXC_IP}:8989
    Radarr          http://${LXC_IP}:7878
    Bazarr          http://${LXC_IP}:6767

  ${YELLOW}Request Management:${NC}
    Jellyseerr      http://${LXC_IP}:5055

  ${YELLOW}VPN Status:${NC}
    Gluetun         http://${LXC_IP}:8000

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${CYAN}Default Credentials:${NC}
  - Jellyfin: Set up on first login
  - NZBGet: nzbget / tegbzn6789
  - Other *arr apps: No auth by default (configure in settings)

${CYAN}Useful Commands:${NC}
  View logs:           docker compose logs -f [service]
  Restart service:     docker compose restart [service]
  Stop all:            docker compose down
  Update containers:   docker compose pull && docker compose up -d

${CYAN}Management Script:${NC}
  For easier management: ./manage-stack.sh

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${YELLOW}Next Steps:${NC}
  1. Configure Prowlarr indexers
  2. Connect Sonarr/Radarr to Prowlarr
  3. Set up NZBGet news server accounts
  4. Configure Jellyfin media libraries
  5. Set up Jellyseerr with Jellyfin

${GREEN}Deployment complete! Happy streaming! 🎬${NC}

EOF
}

################################################################################
# Cleanup on Error
################################################################################

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up..."
    
    if [[ -d "${REPO_DIR}/docker" ]]; then
        cd "${REPO_DIR}/docker"
        docker compose down 2>/dev/null || true
    fi
    
    log_info "Check the error messages above for troubleshooting"
    exit 1
}

trap cleanup_on_error ERR

################################################################################
# Main Execution
################################################################################

main() {
    echo
    log_step "Brother Eye Media Stack Deployment"
    echo "  Repository: ${REPO_URL}"
    echo "  Target: ${DOCKER_DIR}"
    echo "  Clean deploy: ${CLEAN_DEPLOY}"
    echo "  Skip git: ${SKIP_GIT}"
    echo
    
    check_user
    check_dependencies
    check_docker
    
    clone_or_update_repo
    setup_git_crypt
    setup_environment
    pull_docker_images
    start_containers
    wait_for_services
    verify_deployment
    display_access_info
    
    log_success "Deployment workflow complete!"
}

# Run main function
main "$@"
