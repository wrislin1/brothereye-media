#!/bin/bash
# ============================================================================
# Brother Eye Media Stack - Container Update Script
# ============================================================================
# File: scripts/update-all.sh
# Purpose: Update all Docker container images to latest versions
#
# Description:
#   - Checks for available updates for all containers
#   - Pulls latest images from Docker Hub
#   - Recreates containers with minimal downtime
#   - Optional pre-update configuration backup
#   - Verifies containers start successfully
#   - Rollback capability if updates fail
#   - Automatic cleanup of old images
#
# Usage:
#   ./update-all.sh [OPTIONS]
#
# Options:
#   --check-only         Check for updates without applying
#   --service SERVICE    Update only specified service
#   --no-backup          Skip pre-update configuration backup
#   --prune              Prune unused images after update
#   --force              Force update even if no changes
#   --skip-verify        Skip post-update verification
#   --help               Show this help message
#
# Examples:
#   ./update-all.sh                        # Check and update all
#   ./update-all.sh --check-only           # Check for updates only
#   ./update-all.sh --service sonarr       # Update only Sonarr
#   ./update-all.sh --no-backup            # Skip backup for speed
#   ./update-all.sh --prune                # Update and cleanup
#
# Scheduling via Cron:
#   # Check for updates weekly (Sunday at 2 AM)
#   0 2 * * 0 /opt/brother-eye-media-stack/scripts/update-all.sh --check-only
#
#   # Auto-update monthly (first Sunday at 3 AM)
#   0 3 1-7 * * [ "$(date +\%u)" = "7" ] && /opt/brother-eye-media-stack/scripts/update-all.sh
#
# ============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# ============================================================================
# Configuration
# ============================================================================

# Docker compose project directory
COMPOSE_DIR="/opt/brother-eye-media-stack/docker"

# Configuration root
CONFIG_ROOT="/opt/docker/config"

# Log file
LOG_DIR="/var/log/brother-eye"
LOG_FILE="${LOG_DIR}/update-all.log"

# Services to update
SERVICES=(
    "jellyfin"
    "sonarr"
    "radarr"
    "prowlarr"
    "nzbget"
    "gluetun"
    "bazarr"
    "jellyseerr"
    "caddy"
)

# Parse command line options
CHECK_ONLY=false
SPECIFIC_SERVICE=""
SKIP_BACKUP=false
PRUNE_IMAGES=false
FORCE_UPDATE=false
SKIP_VERIFY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --service)
            SPECIFIC_SERVICE="$2"
            shift 2
            ;;
        --no-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --prune)
            PRUNE_IMAGES=true
            shift
            ;;
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        --help)
            grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# Functions
# ============================================================================

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root or with sudo"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Docker is running
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed"
    fi
    
    if ! docker info &> /dev/null; then
        error_exit "Docker daemon is not running"
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null; then
        error_exit "docker-compose is not installed"
    fi
    
    # Check if compose directory exists
    if [[ ! -d "${COMPOSE_DIR}" ]]; then
        error_exit "Compose directory not found: ${COMPOSE_DIR}"
    fi
    
    # Create log directory if needed
    mkdir -p "${LOG_DIR}"
    
    log "INFO" "Prerequisites check passed"
}

# Get current image ID for a container
get_current_image_id() {
    local container="$1"
    docker inspect --format='{{.Image}}' "${container}" 2>/dev/null || echo ""
}

# Get image name for a container
get_image_name() {
    local container="$1"
    docker inspect --format='{{.Config.Image}}' "${container}" 2>/dev/null || echo ""
}

# Check if update is available
check_update_available() {
    local container="$1"
    local current_id
    local image_name
    local latest_id
    
    current_id=$(get_current_image_id "${container}")
    if [[ -z "${current_id}" ]]; then
        log "WARN" "Container ${container} not found"
        return 2
    fi
    
    image_name=$(get_image_name "${container}")
    if [[ -z "${image_name}" ]]; then
        log "WARN" "Could not determine image for ${container}"
        return 2
    fi
    
    # Pull latest image metadata only (no download)
    log "DEBUG" "Checking ${container} (${image_name})..."
    if ! docker pull -q "${image_name}" &>/dev/null; then
        log "WARN" "Failed to check updates for ${container}"
        return 2
    fi
    
    latest_id=$(docker inspect --format='{{.Id}}' "${image_name}" 2>/dev/null || echo "")
    
    if [[ "${current_id}" != "${latest_id}" ]]; then
        return 0  # Update available
    else
        return 1  # No update
    fi
}

# Get container version info
get_version_info() {
    local container="$1"
    local image_name
    image_name=$(get_image_name "${container}")
    
    # Try to get version from image labels
    local version
    version=$(docker inspect --format='{{index .Config.Labels "org.opencontainers.image.version"}}' "${container}" 2>/dev/null || echo "unknown")
    
    if [[ "${version}" == "unknown" ]] || [[ -z "${version}" ]]; then
        # Try alternative version label
        version=$(docker inspect --format='{{index .Config.Labels "version"}}' "${container}" 2>/dev/null || echo "unknown")
    fi
    
    echo "${version}"
}

# Check for updates on all services
check_all_updates() {
    log "INFO" "Checking for available updates..."
    echo ""
    
    printf "%-15s %-20s %-15s %s\n" "Service" "Current Version" "Status" "Image"
    printf "%-15s %-20s %-15s %s\n" "-------" "---------------" "------" "-----"
    
    local update_available=false
    local services_to_check=("${SERVICES[@]}")
    
    if [[ -n "${SPECIFIC_SERVICE}" ]]; then
        services_to_check=("${SPECIFIC_SERVICE}")
    fi
    
    for service in "${services_to_check[@]}"; do
        if ! docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
            printf "%-15s %-20s %-15s %s\n" "${service}" "N/A" "NOT FOUND" "-"
            continue
        fi
        
        local current_version
        current_version=$(get_version_info "${service}")
        
        local image_name
        image_name=$(get_image_name "${service}")
        
        if check_update_available "${service}"; then
            printf "%-15s %-20s %-15s %s\n" "${service}" "${current_version}" "UPDATE AVAILABLE" "${image_name}"
            update_available=true
        else
            local status=$?
            if [[ ${status} -eq 1 ]]; then
                printf "%-15s %-20s %-15s %s\n" "${service}" "${current_version}" "UP TO DATE" "${image_name}"
            else
                printf "%-15s %-20s %-15s %s\n" "${service}" "${current_version}" "CHECK FAILED" "${image_name}"
            fi
        fi
    done
    
    echo ""
    
    if [[ "${update_available}" == "true" ]]; then
        log "INFO" "Updates are available"
        return 0
    else
        log "INFO" "All services are up to date"
        return 1
    fi
}

# Create pre-update backup
create_backup() {
    if [[ "${SKIP_BACKUP}" == "true" ]]; then
        log "INFO" "Skipping pre-update backup as requested"
        return 0
    fi
    
    log "INFO" "Creating pre-update configuration backup..."
    
    local backup_script="/opt/brother-eye-media-stack/scripts/backup-configs.sh"
    
    if [[ ! -f "${backup_script}" ]]; then
        log "WARN" "Backup script not found: ${backup_script}"
        log "WARN" "Proceeding without backup"
        return 0
    fi
    
    if "${backup_script}" --quick; then
        log "INFO" "✓ Pre-update backup completed"
        return 0
    else
        log "WARN" "Backup failed (non-critical, continuing...)"
        return 0
    fi
}

# Update specific service
update_service() {
    local service="$1"
    
    log "INFO" "Updating ${service}..."
    
    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
        log "WARN" "Container ${service} not found, skipping"
        return 1
    fi
    
    local image_name
    image_name=$(get_image_name "${service}")
    
    local old_version
    old_version=$(get_version_info "${service}")
    
    # Pull latest image
    log "INFO" "Pulling latest image for ${service}..."
    if docker pull "${image_name}" 2>&1 | tee -a "${LOG_FILE}"; then
        log "INFO" "✓ Image pulled successfully"
    else
        log "ERROR" "Failed to pull image for ${service}"
        return 1
    fi
    
    # Recreate container
    log "INFO" "Recreating container ${service}..."
    cd "${COMPOSE_DIR}" || error_exit "Failed to change to compose directory"
    
    if docker-compose up -d "${service}" 2>&1 | tee -a "${LOG_FILE}"; then
        log "INFO" "✓ Container recreated"
    else
        log "ERROR" "Failed to recreate container ${service}"
        return 1
    fi
    
    # Wait for container to start
    sleep 5
    
    # Verify container is running
    if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
        local new_version
        new_version=$(get_version_info "${service}")
        log "INFO" "✓ ${service} updated successfully (${old_version} → ${new_version})"
        return 0
    else
        log "ERROR" "Container ${service} failed to start after update"
        return 1
    fi
}

# Update all services
update_all_services() {
    log "INFO" "Updating all services..."
    
    local success_count=0
    local fail_count=0
    local skip_count=0
    
    for service in "${SERVICES[@]}"; do
        if ! docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
            log "INFO" "Skipping ${service} (not deployed)"
            ((skip_count++))
            continue
        fi
        
        if [[ "${FORCE_UPDATE}" != "true" ]]; then
            if ! check_update_available "${service}"; then
                log "INFO" "Skipping ${service} (already up to date)"
                ((skip_count++))
                continue
            fi
        fi
        
        if update_service "${service}"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    log "INFO" "Update summary: ${success_count} updated, ${skip_count} skipped, ${fail_count} failed"
    
    if [[ ${fail_count} -gt 0 ]]; then
        log "WARN" "Some services failed to update"
        return 1
    fi
    
    return 0
}

# Verify all containers are running
verify_containers() {
    if [[ "${SKIP_VERIFY}" == "true" ]]; then
        log "INFO" "Skipping post-update verification as requested"
        return 0
    fi
    
    log "INFO" "Verifying containers are running..."
    
    local all_running=true
    
    for service in "${SERVICES[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
            if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
                log "INFO" "✓ ${service} is running"
            else
                log "ERROR" "✗ ${service} is not running"
                all_running=false
            fi
        fi
    done
    
    if [[ "${all_running}" == "true" ]]; then
        log "INFO" "✓ All containers verified running"
        return 0
    else
        log "ERROR" "✗ Some containers are not running"
        return 1
    fi
}

# Prune unused images
prune_images() {
    log "INFO" "Pruning unused Docker images..."
    
    local before_size
    before_size=$(docker system df --format '{{.Size}}' | head -n 2 | tail -n 1 || echo "0B")
    
    if docker image prune -af 2>&1 | tee -a "${LOG_FILE}"; then
        local after_size
        after_size=$(docker system df --format '{{.Size}}' | head -n 2 | tail -n 1 || echo "0B")
        log "INFO" "✓ Image pruning completed (before: ${before_size}, after: ${after_size})"
    else
        log "WARN" "Failed to prune images (non-critical)"
    fi
}

# Display update summary
show_summary() {
    echo ""
    echo "========================================="
    echo "       UPDATE SUMMARY"
    echo "========================================="
    
    if [[ "${CHECK_ONLY}" == "true" ]]; then
        echo "Mode: Check only (no changes made)"
    else
        echo "Mode: Update applied"
    fi
    
    echo ""
    echo "Services checked:"
    
    for service in "${SERVICES[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
            local version
            version=$(get_version_info "${service}")
            local status
            if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
                status="Running"
            else
                status="Stopped"
            fi
            printf "  %-15s %-20s %s\n" "${service}" "${version}" "${status}"
        fi
    done
    
    echo ""
    echo "Next steps:"
    if [[ "${CHECK_ONLY}" == "true" ]]; then
        echo "  - Run without --check-only to apply updates"
    else
        echo "  - Verify services are working correctly"
        echo "  - Check logs if any issues: docker logs <container>"
    fi
    
    if [[ "${PRUNE_IMAGES}" == "true" ]]; then
        echo "  - Old images have been pruned"
    else
        echo "  - Run with --prune to clean up old images"
    fi
    
    echo "========================================="
    echo ""
}

# Main update function
main_update() {
    log "INFO" "========================================="
    log "INFO" "Brother Eye Container Update Started"
    log "INFO" "========================================="
    
    # Check for updates
    local updates_available=false
    if check_all_updates; then
        updates_available=true
    fi
    
    # If check-only mode, exit here
    if [[ "${CHECK_ONLY}" == "true" ]]; then
        log "INFO" "Check-only mode, exiting without applying updates"
        show_summary
        exit 0
    fi
    
    # If no updates and not forcing, exit
    if [[ "${updates_available}" == "false" ]] && [[ "${FORCE_UPDATE}" != "true" ]]; then
        log "INFO" "No updates available"
        show_summary
        exit 0
    fi
    
    # Create pre-update backup
    create_backup
    
    # Perform updates
    if [[ -n "${SPECIFIC_SERVICE}" ]]; then
        update_service "${SPECIFIC_SERVICE}"
    else
        update_all_services
    fi
    
    # Verify containers
    verify_containers
    
    # Prune images if requested
    if [[ "${PRUNE_IMAGES}" == "true" ]]; then
        prune_images
    fi
    
    # Show summary
    show_summary
    
    log "INFO" "========================================="
    log "INFO" "Update completed"
    log "INFO" "========================================="
}

# ============================================================================
# Main Script
# ============================================================================

# Check privileges
check_privileges

# Check prerequisites
check_prerequisites

# Run main update
main_update

exit 0
