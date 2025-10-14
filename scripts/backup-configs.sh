#!/bin/bash
# ============================================================================
# Brother Eye Media Stack - Configuration Backup Script
# ============================================================================
# File: scripts/backup-configs.sh
# Purpose: Backup all Docker container configurations
#
# Description:
#   - Creates timestamped backup archives of all service configurations
#   - Optionally stops containers for consistent database backups
#   - Excludes cache directories and logs to save space
#   - Implements backup retention policy
#   - Verifies backup integrity with checksums
#   - Logs all operations for audit trail
#
# Usage:
#   ./backup-configs.sh [OPTIONS]
#
# Options:
#   --quick          Quick backup (don't stop containers)
#   --full           Full backup (include cache and logs)
#   --clean          Clean old backups based on retention
#   --verify-only    Only verify existing backups
#   --help           Show this help message
#
# Examples:
#   ./backup-configs.sh                    # Standard backup
#   ./backup-configs.sh --quick            # Quick backup
#   ./backup-configs.sh --full             # Full backup with cache
#   ./backup-configs.sh --clean            # Clean old backups
#
# Scheduling via Cron:
#   # Daily backup at 3 AM
#   0 3 * * * /opt/brother-eye-media-stack/scripts/backup-configs.sh --quick
#
#   # Weekly full backup on Sunday at 2 AM
#   0 2 * * 0 /opt/brother-eye-media-stack/scripts/backup-configs.sh --full
#
# ============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# ============================================================================
# Configuration
# ============================================================================

# Source directory (Docker configs)
CONFIG_ROOT="/opt/docker/config"

# Backup destination
BACKUP_ROOT="/mnt/media/backups/configs"

# Docker compose project directory
COMPOSE_DIR="/opt/brother-eye-media-stack/docker"

# Backup retention (keep last N backups)
RETENTION_DAYS=30
RETENTION_COUNT=10

# Log file
LOG_DIR="/var/log/brother-eye"
LOG_FILE="${LOG_DIR}/backup-configs.log"

# Services to backup
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

# Directories to exclude from backup (cache, temp, logs)
EXCLUDE_PATTERNS=(
    "*/cache/*"
    "*/Cache/*"
    "*/logs/*"
    "*/log/*"
    "*/Logs/*"
    "*/tmp/*"
    "*/temp/*"
    "*/transcodes/*"
    "*/MediaCover/*"
)

# Parse command line options
QUICK_BACKUP=false
FULL_BACKUP=false
CLEAN_ONLY=false
VERIFY_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            QUICK_BACKUP=true
            shift
            ;;
        --full)
            FULL_BACKUP=true
            shift
            ;;
        --clean)
            CLEAN_ONLY=true
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
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
    
    # Check if config directory exists
    if [[ ! -d "${CONFIG_ROOT}" ]]; then
        error_exit "Config directory not found: ${CONFIG_ROOT}"
    fi
    
    # Check if backup destination exists, create if not
    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        log "WARN" "Backup directory doesn't exist, creating: ${BACKUP_ROOT}"
        mkdir -p "${BACKUP_ROOT}" || error_exit "Failed to create backup directory"
    fi
    
    # Check available disk space (require at least 5GB free)
    local available_space
    available_space=$(df -BG "${BACKUP_ROOT}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ ${available_space} -lt 5 ]]; then
        error_exit "Insufficient disk space. Available: ${available_space}GB, Required: 5GB"
    fi
    
    # Check if Docker is installed and running
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
    
    # Create log directory if it doesn't exist
    mkdir -p "${LOG_DIR}"
    
    log "INFO" "Prerequisites check passed"
}

# Get list of running containers
get_running_containers() {
    docker ps --format '{{.Names}}' | grep -E "$(IFS="|"; echo "${SERVICES[*]}")" || true
}

# Stop Docker containers
stop_containers() {
    log "INFO" "Stopping Docker containers..."
    
    local running_containers
    running_containers=$(get_running_containers)
    
    if [[ -z "${running_containers}" ]]; then
        log "WARN" "No containers are currently running"
        return 0
    fi
    
    cd "${COMPOSE_DIR}" || error_exit "Failed to change to compose directory"
    
    if docker-compose stop; then
        log "INFO" "Containers stopped successfully"
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
        log "INFO" "Containers started successfully"
        return 0
    else
        log "ERROR" "Failed to start containers"
        return 1
    fi
}

# Create backup archive
create_backup() {
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_name="brother-eye-configs_${timestamp}"
    local backup_file="${BACKUP_ROOT}/${backup_name}.tar.gz"
    local backup_checksum="${BACKUP_ROOT}/${backup_name}.sha256"
    
    log "INFO" "Creating backup: ${backup_name}"
    
    # Build tar command with exclusions
    local tar_excludes=()
    if [[ "${FULL_BACKUP}" != "true" ]]; then
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            tar_excludes+=(--exclude="${pattern}")
        done
    fi
    
    # Create backup archive
    log "INFO" "Archiving configuration files..."
    if tar czf "${backup_file}" \
        "${tar_excludes[@]}" \
        -C / \
        "opt/docker/config" \
        2>&1 | tee -a "${LOG_FILE}"; then
        log "INFO" "Archive created successfully"
    else
        error_exit "Failed to create backup archive"
    fi
    
    # Also backup docker-compose files
    log "INFO" "Backing up Docker Compose files..."
    if tar czf "${BACKUP_ROOT}/${backup_name}_compose.tar.gz" \
        -C / \
        "opt/brother-eye-media-stack/docker" \
        2>&1 | tee -a "${LOG_FILE}"; then
        log "INFO" "Compose files backed up successfully"
    else
        log "WARN" "Failed to backup compose files (non-critical)"
    fi
    
    # Generate checksum
    log "INFO" "Generating checksum..."
    if sha256sum "${backup_file}" > "${backup_checksum}"; then
        log "INFO" "Checksum generated: $(basename ${backup_checksum})"
    else
        log "WARN" "Failed to generate checksum (non-critical)"
    fi
    
    # Get backup size
    local backup_size
    backup_size=$(du -h "${backup_file}" | cut -f1)
    log "INFO" "Backup completed: ${backup_file} (${backup_size})"
    
    # Create backup manifest
    create_manifest "${backup_name}"
}

# Create backup manifest
create_manifest() {
    local backup_name="$1"
    local manifest_file="${BACKUP_ROOT}/${backup_name}_manifest.txt"
    
    log "INFO" "Creating backup manifest..."
    
    cat > "${manifest_file}" <<EOF
Brother Eye Media Stack - Backup Manifest
==========================================
Backup Name: ${backup_name}
Created: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
Backup Type: $(if [[ "${FULL_BACKUP}" == "true" ]]; then echo "Full"; else echo "Standard"; fi)

Services Included:
$(for service in "${SERVICES[@]}"; do
    if [[ -d "${CONFIG_ROOT}/${service}" ]]; then
        echo "  ✓ ${service}"
    else
        echo "  ✗ ${service} (not found)"
    fi
done)

Excluded Patterns:
$(if [[ "${FULL_BACKUP}" != "true" ]]; then
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        echo "  - ${pattern}"
    done
else
    echo "  (none - full backup)"
fi)

Backup Files:
  - ${backup_name}.tar.gz
  - ${backup_name}_compose.tar.gz
  - ${backup_name}.sha256

Restore Instructions:
  1. Stop all containers:
     cd /opt/brother-eye-media-stack/docker && docker-compose down
  
  2. Restore configuration:
     tar xzf ${backup_name}.tar.gz -C /
  
  3. Restore compose files (if needed):
     tar xzf ${backup_name}_compose.tar.gz -C /
  
  4. Start containers:
     cd /opt/brother-eye-media-stack/docker && docker-compose up -d

For detailed restore instructions, see:
  /opt/brother-eye-media-stack/scripts/restore-configs.sh --help
==========================================
EOF
    
    log "INFO" "Manifest created: ${manifest_file}"
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    local checksum_file="${backup_file%.tar.gz}.sha256"
    
    if [[ ! -f "${checksum_file}" ]]; then
        log "WARN" "Checksum file not found for: $(basename ${backup_file})"
        return 1
    fi
    
    log "INFO" "Verifying backup: $(basename ${backup_file})"
    
    if sha256sum -c "${checksum_file}" &> /dev/null; then
        log "INFO" "Backup verification successful"
        return 0
    else
        log "ERROR" "Backup verification failed!"
        return 1
    fi
}

# Verify all existing backups
verify_all_backups() {
    log "INFO" "Verifying all existing backups..."
    
    local backup_files
    backup_files=$(find "${BACKUP_ROOT}" -name "*.tar.gz" -type f | sort)
    
    if [[ -z "${backup_files}" ]]; then
        log "WARN" "No backup files found"
        return 0
    fi
    
    local verified=0
    local failed=0
    
    while IFS= read -r backup_file; do
        if verify_backup "${backup_file}"; then
            ((verified++))
        else
            ((failed++))
        fi
    done <<< "${backup_files}"
    
    log "INFO" "Verification complete: ${verified} passed, ${failed} failed"
}

# Clean old backups
clean_old_backups() {
    log "INFO" "Cleaning old backups (retention: ${RETENTION_DAYS} days, keep ${RETENTION_COUNT} most recent)..."
    
    # Delete backups older than retention period
    local deleted_count=0
    while IFS= read -r old_file; do
        if [[ -n "${old_file}" ]]; then
            log "INFO" "Deleting old backup: $(basename ${old_file})"
            rm -f "${old_file}"
            rm -f "${old_file%.tar.gz}.sha256"
            rm -f "${old_file%.tar.gz}_manifest.txt"
            rm -f "${old_file%.tar.gz}_compose.tar.gz"
            ((deleted_count++))
        fi
    done < <(find "${BACKUP_ROOT}" -name "*.tar.gz" -type f -mtime +${RETENTION_DAYS} 2>/dev/null)
    
    # Keep only N most recent backups
    local backup_count
    backup_count=$(find "${BACKUP_ROOT}" -name "brother-eye-configs_*.tar.gz" -type f | wc -l)
    
    if [[ ${backup_count} -gt ${RETENTION_COUNT} ]]; then
        local excess=$((backup_count - RETENTION_COUNT))
        log "INFO" "Found ${backup_count} backups, removing ${excess} oldest..."
        
        while IFS= read -r old_file; do
            if [[ -n "${old_file}" ]]; then
                log "INFO" "Deleting excess backup: $(basename ${old_file})"
                rm -f "${old_file}"
                rm -f "${old_file%.tar.gz}.sha256"
                rm -f "${old_file%.tar.gz}_manifest.txt"
                rm -f "${old_file%.tar.gz}_compose.tar.gz"
                ((deleted_count++))
            fi
        done < <(find "${BACKUP_ROOT}" -name "brother-eye-configs_*.tar.gz" -type f -printf '%T+ %p\n' | sort | head -n ${excess} | cut -d' ' -f2-)
    fi
    
    if [[ ${deleted_count} -gt 0 ]]; then
        log "INFO" "Cleaned ${deleted_count} old backup(s)"
    else
        log "INFO" "No old backups to clean"
    fi
}

# List existing backups
list_backups() {
    log "INFO" "Existing backups:"
    
    local backup_files
    backup_files=$(find "${BACKUP_ROOT}" -name "brother-eye-configs_*.tar.gz" -type f -printf '%T+ %p\n' | sort -r)
    
    if [[ -z "${backup_files}" ]]; then
        log "INFO" "  No backups found"
        return 0
    fi
    
    echo ""
    printf "%-30s %-20s %-10s\n" "Backup Name" "Date" "Size"
    printf "%-30s %-20s %-10s\n" "----------" "----" "----"
    
    while IFS= read -r line; do
        local backup_date="${line%% *}"
        local backup_file="${line#* }"
        local backup_name
        backup_name=$(basename "${backup_file}")
        local backup_size
        backup_size=$(du -h "${backup_file}" | cut -f1)
        local formatted_date
        formatted_date=$(date -d "${backup_date}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "Unknown")
        
        printf "%-30s %-20s %-10s\n" "${backup_name}" "${formatted_date}" "${backup_size}"
    done <<< "${backup_files}"
    
    echo ""
}

# Main backup function
main_backup() {
    log "INFO" "========================================="
    log "INFO" "Brother Eye Configuration Backup Started"
    log "INFO" "========================================="
    
    local containers_were_stopped=false
    
    # Stop containers if not quick backup
    if [[ "${QUICK_BACKUP}" != "true" ]]; then
        stop_containers
        containers_were_stopped=true
        # Wait a moment for everything to settle
        sleep 3
    else
        log "INFO" "Quick backup mode: containers will remain running"
    fi
    
    # Create the backup
    create_backup
    
    # Restart containers if we stopped them
    if [[ "${containers_were_stopped}" == "true" ]]; then
        start_containers
    fi
    
    # Clean old backups
    clean_old_backups
    
    # List backups
    list_backups
    
    log "INFO" "========================================="
    log "INFO" "Backup completed successfully"
    log "INFO" "========================================="
}

# ============================================================================
# Main Script
# ============================================================================

# Check privileges
check_privileges

# Check prerequisites
check_prerequisites

# Handle different modes
if [[ "${VERIFY_ONLY}" == "true" ]]; then
    verify_all_backups
elif [[ "${CLEAN_ONLY}" == "true" ]]; then
    clean_old_backups
    list_backups
else
    main_backup
fi

exit 0
