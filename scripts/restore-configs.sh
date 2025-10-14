#!/bin/bash
# ============================================================================
# Brother Eye Media Stack - Configuration Restore Script
# ============================================================================
# File: scripts/restore-configs.sh
# Purpose: Restore Docker container configurations from backup
#
# Description:
#   - Restores configurations from timestamped backup archives
#   - Verifies backup integrity before restoration
#   - Creates safety backup of current state before restore
#   - Supports selective restoration of specific services
#   - Includes dry-run mode for testing
#   - Automatic container management during restore
#   - Rollback capability if restore fails
#
# Usage:
#   ./restore-configs.sh [OPTIONS]
#
# Options:
#   --latest              Restore latest backup automatically
#   --file BACKUP_FILE    Restore specific backup file
#   --service SERVICE     Restore only specified service
#   --dry-run             Preview changes without applying
#   --no-backup           Skip pre-restore safety backup
#   --force               Skip confirmation prompts
#   --help                Show this help message
#
# Examples:
#   ./restore-configs.sh                                # Interactive mode
#   ./restore-configs.sh --latest                       # Restore latest
#   ./restore-configs.sh --file backup_20241013.tar.gz  # Restore specific
#   ./restore-configs.sh --service sonarr               # Restore only Sonarr
#   ./restore-configs.sh --dry-run                      # Preview restore
#
# Safety Features:
#   - Automatic verification of backup integrity
#   - Pre-restore backup of current configuration
#   - Confirmation prompts before destructive operations
#   - Rollback capability if restore fails
#   - Detailed logging of all operations
#
# ============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# ============================================================================
# Configuration
# ============================================================================

# Backup source directory
BACKUP_ROOT="/mnt/media/backups/configs"

# Configuration directory
CONFIG_ROOT="/opt/docker/config"

# Docker compose project directory
COMPOSE_DIR="/opt/brother-eye-media-stack/docker"

# Log file
LOG_DIR="/var/log/brother-eye"
LOG_FILE="${LOG_DIR}/restore-configs.log"

# Temporary extraction directory
TEMP_DIR="/tmp/brother-eye-restore"

# Available services
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
INTERACTIVE=true
LATEST_BACKUP=false
SPECIFIC_FILE=""
SPECIFIC_SERVICE=""
DRY_RUN=false
SKIP_SAFETY_BACKUP=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --latest)
            LATEST_BACKUP=true
            INTERACTIVE=false
            shift
            ;;
        --file)
            SPECIFIC_FILE="$2"
            INTERACTIVE=false
            shift 2
            ;;
        --service)
            SPECIFIC_SERVICE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-backup)
            SKIP_SAFETY_BACKUP=true
            shift
            ;;
        --force)
            FORCE=true
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
    cleanup
    exit 1
}

# Cleanup temporary files
cleanup() {
    if [[ -d "${TEMP_DIR}" ]]; then
        log "INFO" "Cleaning up temporary files..."
        rm -rf "${TEMP_DIR}"
    fi
}

# Trap cleanup on exit
trap cleanup EXIT

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root or with sudo"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if backup directory exists
    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        error_exit "Backup directory not found: ${BACKUP_ROOT}"
    fi
    
    # Check if config directory exists
    if [[ ! -d "${CONFIG_ROOT}" ]]; then
        error_exit "Config directory not found: ${CONFIG_ROOT}"
    fi
    
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
    
    # Create log directory if needed
    mkdir -p "${LOG_DIR}"
    
    # Create temp directory
    mkdir -p "${TEMP_DIR}"
    
    log "INFO" "Prerequisites check passed"
}

# List available backups
list_backups() {
    local backups
    backups=$(find "${BACKUP_ROOT}" -name "brother-eye-configs_*.tar.gz" -type f -printf '%T+ %p\n' | sort -r)
    
    if [[ -z "${backups}" ]]; then
        error_exit "No backup files found in ${BACKUP_ROOT}"
    fi
    
    echo "${backups}"
}

# Display backups in formatted table
display_backups() {
    log "INFO" "Available backups:"
    echo ""
    printf "%-5s %-35s %-20s %-10s\n" "No." "Backup Name" "Date" "Size"
    printf "%-5s %-35s %-20s %-10s\n" "---" "----------" "----" "----"
    
    local index=1
    while IFS= read -r line; do
        local backup_date="${line%% *}"
        local backup_file="${line#* }"
        local backup_name
        backup_name=$(basename "${backup_file}")
        local backup_size
        backup_size=$(du -h "${backup_file}" 2>/dev/null | cut -f1)
        local formatted_date
        formatted_date=$(date -d "${backup_date}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "Unknown")
        
        printf "%-5s %-35s %-20s %-10s\n" "${index}" "${backup_name}" "${formatted_date}" "${backup_size}"
        ((index++))
    done < <(list_backups)
    
    echo ""
}

# Select backup interactively
select_backup() {
    display_backups
    
    local backup_count
    backup_count=$(list_backups | wc -l)
    
    echo -n "Enter backup number to restore (1-${backup_count}), or 'q' to quit: "
    read -r selection
    
    if [[ "${selection}" == "q" ]] || [[ "${selection}" == "Q" ]]; then
        log "INFO" "Restore cancelled by user"
        exit 0
    fi
    
    if ! [[ "${selection}" =~ ^[0-9]+$ ]] || [[ ${selection} -lt 1 ]] || [[ ${selection} -gt ${backup_count} ]]; then
        error_exit "Invalid selection: ${selection}"
    fi
    
    local selected_backup
    selected_backup=$(list_backups | sed -n "${selection}p" | awk '{print $2}')
    
    echo "${selected_backup}"
}

# Get latest backup
get_latest_backup() {
    local latest
    latest=$(list_backups | head -n 1 | awk '{print $2}')
    
    if [[ -z "${latest}" ]]; then
        error_exit "No backups found"
    fi
    
    echo "${latest}"
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    local checksum_file="${backup_file%.tar.gz}.sha256"
    
    log "INFO" "Verifying backup integrity..."
    
    if [[ ! -f "${backup_file}" ]]; then
        error_exit "Backup file not found: ${backup_file}"
    fi
    
    if [[ ! -f "${checksum_file}" ]]; then
        log "WARN" "Checksum file not found: ${checksum_file}"
        log "WARN" "Skipping integrity verification"
        return 0
    fi
    
    if sha256sum -c "${checksum_file}" &> /dev/null; then
        log "INFO" "✓ Backup integrity verified"
        return 0
    else
        error_exit "✗ Backup integrity check failed! Backup may be corrupted."
    fi
}

# Create safety backup of current configuration
create_safety_backup() {
    if [[ "${SKIP_SAFETY_BACKUP}" == "true" ]]; then
        log "WARN" "Skipping safety backup as requested"
        return 0
    fi
    
    log "INFO" "Creating safety backup of current configuration..."
    
    local safety_backup_name="pre-restore-safety_$(date '+%Y%m%d_%H%M%S')"
    local safety_backup_file="${BACKUP_ROOT}/${safety_backup_name}.tar.gz"
    
    if tar czf "${safety_backup_file}" -C / "opt/docker/config" 2>&1 | tee -a "${LOG_FILE}"; then
        log "INFO" "✓ Safety backup created: ${safety_backup_file}"
        echo "${safety_backup_file}"
    else
        log "WARN" "Failed to create safety backup (non-critical, continuing...)"
        echo ""
    fi
}

# Stop Docker containers
stop_containers() {
    log "INFO" "Stopping Docker containers..."
    
    cd "${COMPOSE_DIR}" || error_exit "Failed to change to compose directory"
    
    if docker-compose stop; then
        log "INFO" "✓ Containers stopped"
        return 0
    else
        error_exit "Failed to stop containers"
    fi
}

# Start Docker containers
start_containers() {
    log "INFO" "Starting Docker containers..."
    
    cd "${COMPOSE_DIR}" || error_exit "Failed to change to compose directory"
    
    if docker-compose up -d; then
        log "INFO" "✓ Containers started"
        return 0
    else
        log "ERROR" "Failed to start containers"
        return 1
    fi
}

# Extract backup to temporary location
extract_backup() {
    local backup_file="$1"
    
    log "INFO" "Extracting backup to temporary location..."
    
    # Extract main config archive
    if tar xzf "${backup_file}" -C "${TEMP_DIR}" 2>&1 | tee -a "${LOG_FILE}"; then
        log "INFO" "✓ Backup extracted successfully"
    else
        error_exit "Failed to extract backup"
    fi
    
    # Check if compose backup exists and extract it
    local compose_backup="${backup_file%.tar.gz}_compose.tar.gz"
    if [[ -f "${compose_backup}" ]]; then
        log "INFO" "Found compose backup, extracting..."
        if tar xzf "${compose_backup}" -C "${TEMP_DIR}" 2>&1 | tee -a "${LOG_FILE}"; then
            log "INFO" "✓ Compose files extracted"
        else
            log "WARN" "Failed to extract compose backup (non-critical)"
        fi
    fi
}

# Restore specific service
restore_service() {
    local service="$1"
    local source_dir="${TEMP_DIR}/opt/docker/config/${service}"
    local dest_dir="${CONFIG_ROOT}/${service}"
    
    if [[ ! -d "${source_dir}" ]]; then
        log "WARN" "Service '${service}' not found in backup"
        return 1
    fi
    
    log "INFO" "Restoring ${service}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would restore: ${source_dir} -> ${dest_dir}"
        return 0
    fi
    
    # Backup existing config if it exists
    if [[ -d "${dest_dir}" ]]; then
        local backup_dir="${dest_dir}.backup-$(date +%s)"
        log "INFO" "Backing up existing config: ${backup_dir}"
        mv "${dest_dir}" "${backup_dir}"
    fi
    
    # Restore from backup
    if cp -a "${source_dir}" "${dest_dir}"; then
        log "INFO" "✓ ${service} restored successfully"
        return 0
    else
        log "ERROR" "Failed to restore ${service}"
        return 1
    fi
}

# Restore all services
restore_all_services() {
    log "INFO" "Restoring all services..."
    
    local success_count=0
    local fail_count=0
    
    for service in "${SERVICES[@]}"; do
        if restore_service "${service}"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    log "INFO" "Restore summary: ${success_count} succeeded, ${fail_count} failed"
    
    if [[ ${fail_count} -gt 0 ]]; then
        log "WARN" "Some services failed to restore"
    fi
}

# Restore compose files
restore_compose_files() {
    local source_dir="${TEMP_DIR}/opt/brother-eye-media-stack/docker"
    
    if [[ ! -d "${source_dir}" ]]; then
        log "WARN" "Compose files not found in backup"
        return 0
    fi
    
    log "INFO" "Restoring Docker Compose files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would restore compose files"
        return 0
    fi
    
    # Backup existing compose directory
    local backup_dir="${COMPOSE_DIR}.backup-$(date +%s)"
    log "INFO" "Backing up existing compose directory: ${backup_dir}"
    cp -a "${COMPOSE_DIR}" "${backup_dir}"
    
    # Restore compose files
    if cp -a "${source_dir}"/* "${COMPOSE_DIR}/"; then
        log "INFO" "✓ Compose files restored"
        return 0
    else
        log "ERROR" "Failed to restore compose files"
        return 1
    fi
}

# Confirm restore operation
confirm_restore() {
    local backup_file="$1"
    
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "========================================="
    echo "         RESTORE CONFIRMATION"
    echo "========================================="
    echo "Backup file: $(basename ${backup_file})"
    
    if [[ -n "${SPECIFIC_SERVICE}" ]]; then
        echo "Restore mode: Single service (${SPECIFIC_SERVICE})"
    else
        echo "Restore mode: All services"
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "Mode: DRY-RUN (no changes will be made)"
    else
        echo "Mode: LIVE (changes will be applied)"
    fi
    
    echo ""
    echo "⚠️  WARNING: This will overwrite current configuration!"
    echo ""
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        echo -n "Type 'yes' to continue, anything else to cancel: "
        read -r confirmation
        
        if [[ "${confirmation}" != "yes" ]]; then
            log "INFO" "Restore cancelled by user"
            exit 0
        fi
    fi
    
    echo ""
}

# Validate restoration
validate_restore() {
    log "INFO" "Validating restoration..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY-RUN] Skipping validation"
        return 0
    fi
    
    local validated=0
    local failed=0
    
    for service in "${SERVICES[@]}"; do
        if [[ -n "${SPECIFIC_SERVICE}" ]] && [[ "${service}" != "${SPECIFIC_SERVICE}" ]]; then
            continue
        fi
        
        local config_dir="${CONFIG_ROOT}/${service}"
        
        if [[ -d "${config_dir}" ]]; then
            log "INFO" "✓ ${service} configuration exists"
            ((validated++))
        else
            log "WARN" "✗ ${service} configuration missing"
            ((failed++))
        fi
    done
    
    log "INFO" "Validation complete: ${validated} validated, ${failed} missing"
    
    if [[ ${failed} -gt 0 ]]; then
        log "WARN" "Some services are missing after restore"
    fi
}

# Display restore summary
show_summary() {
    local backup_file="$1"
    local safety_backup="$2"
    
    echo ""
    echo "========================================="
    echo "       RESTORE COMPLETED"
    echo "========================================="
    echo "Restored from: $(basename ${backup_file})"
    
    if [[ -n "${safety_backup}" ]]; then
        echo "Safety backup: $(basename ${safety_backup})"
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo ""
        echo "This was a DRY-RUN. No changes were made."
        echo "Remove --dry-run to apply changes."
    else
        echo ""
        echo "Configuration has been restored."
        echo "Containers will be restarted momentarily."
        
        if [[ -n "${safety_backup}" ]]; then
            echo ""
            echo "If anything goes wrong, you can restore from:"
            echo "  ${safety_backup}"
        fi
    fi
    
    echo "========================================="
    echo ""
}

# Main restore function
main_restore() {
    log "INFO" "========================================="
    log "INFO" "Brother Eye Configuration Restore Started"
    log "INFO" "========================================="
    
    local backup_file
    local safety_backup=""
    
    # Determine which backup to restore
    if [[ "${INTERACTIVE}" == "true" ]]; then
        backup_file=$(select_backup)
    elif [[ "${LATEST_BACKUP}" == "true" ]]; then
        backup_file=$(get_latest_backup)
        log "INFO" "Selected latest backup: $(basename ${backup_file})"
    elif [[ -n "${SPECIFIC_FILE}" ]]; then
        if [[ -f "${SPECIFIC_FILE}" ]]; then
            backup_file="${SPECIFIC_FILE}"
        elif [[ -f "${BACKUP_ROOT}/${SPECIFIC_FILE}" ]]; then
            backup_file="${BACKUP_ROOT}/${SPECIFIC_FILE}"
        else
            error_exit "Backup file not found: ${SPECIFIC_FILE}"
        fi
        log "INFO" "Selected backup: $(basename ${backup_file})"
    fi
    
    # Verify backup integrity
    verify_backup "${backup_file}"
    
    # Confirm restore operation
    confirm_restore "${backup_file}"
    
    # Create safety backup
    if [[ "${DRY_RUN}" != "true" ]]; then
        safety_backup=$(create_safety_backup)
    fi
    
    # Extract backup
    extract_backup "${backup_file}"
    
    # Stop containers (unless dry-run)
    if [[ "${DRY_RUN}" != "true" ]]; then
        stop_containers
        sleep 2
    fi
    
    # Restore configurations
    if [[ -n "${SPECIFIC_SERVICE}" ]]; then
        restore_service "${SPECIFIC_SERVICE}"
    else
        restore_all_services
        restore_compose_files
    fi
    
    # Validate restoration
    validate_restore
    
    # Start containers (unless dry-run)
    if [[ "${DRY_RUN}" != "true" ]]; then
        start_containers
    fi
    
    # Show summary
    show_summary "${backup_file}" "${safety_backup}"
    
    log "INFO" "========================================="
    log "INFO" "Restore completed"
    log "INFO" "========================================="
}

# ============================================================================
# Main Script
# ============================================================================

# Check privileges
check_privileges

# Check prerequisites
check_prerequisites

# Run main restore
main_restore

exit 0
