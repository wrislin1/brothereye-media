#!/bin/bash
# ============================================================================
# Brother Eye Media Stack - Health Check Script
# ============================================================================
# File: scripts/health-check.sh
# Purpose: Comprehensive health monitoring for all services
#
# Description:
#   - Checks if all containers are running and healthy
#   - Verifies network connectivity between services
#   - Monitors disk space on critical mounts
#   - Tests service accessibility via web UIs
#   - Validates configuration files
#   - Monitors system resources (CPU, memory, load)
#   - Checks VPN tunnel status
#   - Generates detailed health report
#
# Usage:
#   ./health-check.sh [OPTIONS]
#
# Options:
#   --verbose            Show detailed output
#   --json               Output in JSON format
#   --no-color           Disable colored output
#   --quiet              Show only errors
#   --service SERVICE    Check only specified service
#   --help               Show this help message
#
# Examples:
#   ./health-check.sh                    # Standard health check
#   ./health-check.sh --verbose          # Detailed output
#   ./health-check.sh --json             # JSON output
#   ./health-check.sh --service sonarr   # Check only Sonarr
#
# Exit Codes:
#   0 - All checks passed
#   1 - Some checks failed (warnings)
#   2 - Critical checks failed (errors)
#
# Scheduling via Cron:
#   # Run health check every hour
#   0 * * * * /opt/brother-eye-media-stack/scripts/health-check.sh --quiet
#
#   # Daily detailed report at 8 AM
#   0 8 * * * /opt/brother-eye-media-stack/scripts/health-check.sh --verbose
#
# ============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# ============================================================================
# Configuration
# ============================================================================

# Configuration paths
CONFIG_ROOT="/opt/docker/config"
COMPOSE_DIR="/opt/brother-eye-media-stack/docker"

# Media paths
MEDIA_ROOT="/mnt/media"

# Log file
LOG_DIR="/var/log/brother-eye"
LOG_FILE="${LOG_DIR}/health-check.log"

# Services and their ports
declare -A SERVICE_PORTS=(
    ["jellyfin"]="8096"
    ["sonarr"]="8989"
    ["radarr"]="7878"
    ["prowlarr"]="9696"
    ["nzbget"]="6789"
    ["bazarr"]="6767"
    ["jellyseerr"]="5055"
    ["caddy"]="80"
)

# Disk space thresholds (percentage)
DISK_WARNING_THRESHOLD=80
DISK_CRITICAL_THRESHOLD=90

# Resource thresholds
CPU_WARNING_THRESHOLD=80
CPU_CRITICAL_THRESHOLD=95
MEMORY_WARNING_THRESHOLD=85
MEMORY_CRITICAL_THRESHOLD=95

# Parse command line options
VERBOSE=false
JSON_OUTPUT=false
NO_COLOR=false
QUIET=false
SPECIFIC_SERVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            NO_COLOR=true
            shift
            ;;
        --no-color)
            NO_COLOR=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --service)
            SPECIFIC_SERVICE="$2"
            shift 2
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
# Color Definitions
# ============================================================================

if [[ "${NO_COLOR}" == "true" ]]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    MAGENTA=""
    BOLD=""
    RESET=""
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    RESET='\033[0m'
fi

# Status symbols
CHECK_MARK="✓"
CROSS_MARK="✗"
WARNING_MARK="⚠"

# ============================================================================
# Global Variables
# ============================================================================

CHECKS_PASSED=0
CHECKS_WARNED=0
CHECKS_FAILED=0
EXIT_CODE=0

# JSON output storage
declare -a JSON_RESULTS=()

# ============================================================================
# Functions
# ============================================================================

# Print status with color
print_status() {
    local status="$1"
    local message="$2"
    
    if [[ "${QUIET}" == "true" ]] && [[ "${status}" == "PASS" ]]; then
        return
    fi
    
    case "${status}" in
        "PASS")
            echo -e "${GREEN}${CHECK_MARK}${RESET} ${message}"
            ((CHECKS_PASSED++))
            ;;
        "WARN")
            echo -e "${YELLOW}${WARNING_MARK}${RESET} ${message}"
            ((CHECKS_WARNED++))
            if [[ ${EXIT_CODE} -lt 1 ]]; then
                EXIT_CODE=1
            fi
            ;;
        "FAIL")
            echo -e "${RED}${CROSS_MARK}${RESET} ${message}"
            ((CHECKS_FAILED++))
            EXIT_CODE=2
            ;;
        "INFO")
            if [[ "${VERBOSE}" == "true" ]]; then
                echo -e "${CYAN}ℹ${RESET} ${message}"
            fi
            ;;
    esac
}

# Add result to JSON output
add_json_result() {
    local category="$1"
    local check="$2"
    local status="$3"
    local details="$4"
    
    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        JSON_RESULTS+=("{\"category\":\"${category}\",\"check\":\"${check}\",\"status\":\"${status}\",\"details\":\"${details}\"}")
    fi
}

# Print section header
print_header() {
    local header="$1"
    
    if [[ "${QUIET}" != "true" ]]; then
        echo ""
        echo -e "${BOLD}${BLUE}=== ${header} ===${RESET}"
    fi
}

# Check if Docker is running
check_docker() {
    print_header "Docker Status"
    
    if ! command -v docker &> /dev/null; then
        print_status "FAIL" "Docker is not installed"
        add_json_result "docker" "installed" "FAIL" "Docker command not found"
        return 1
    fi
    
    print_status "PASS" "Docker is installed"
    add_json_result "docker" "installed" "PASS" "Docker command available"
    
    if ! docker info &> /dev/null; then
        print_status "FAIL" "Docker daemon is not running"
        add_json_result "docker" "daemon" "FAIL" "Docker daemon not responding"
        return 1
    fi
    
    print_status "PASS" "Docker daemon is running"
    add_json_result "docker" "daemon" "PASS" "Docker daemon active"
    
    return 0
}

# Check container status
check_containers() {
    print_header "Container Status"
    
    local services_to_check=("${!SERVICE_PORTS[@]}")
    
    if [[ -n "${SPECIFIC_SERVICE}" ]]; then
        services_to_check=("${SPECIFIC_SERVICE}")
    fi
    
    for service in "${services_to_check[@]}"; do
        # Check if container exists
        if ! docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
            print_status "INFO" "${service}: Not deployed"
            add_json_result "containers" "${service}" "INFO" "Container not found"
            continue
        fi
        
        # Check if container is running
        if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            # Check health status if available
            local health_status
            health_status=$(docker inspect --format='{{.State.Health.Status}}' "${service}" 2>/dev/null || echo "none")
            
            if [[ "${health_status}" == "healthy" ]]; then
                print_status "PASS" "${service}: Running (healthy)"
                add_json_result "containers" "${service}" "PASS" "Running and healthy"
            elif [[ "${health_status}" == "unhealthy" ]]; then
                print_status "FAIL" "${service}: Running (unhealthy)"
                add_json_result "containers" "${service}" "FAIL" "Container unhealthy"
            elif [[ "${health_status}" == "starting" ]]; then
                print_status "WARN" "${service}: Running (starting)"
                add_json_result "containers" "${service}" "WARN" "Health check starting"
            else
                print_status "PASS" "${service}: Running (no health check)"
                add_json_result "containers" "${service}" "PASS" "Running without health check"
            fi
        else
            # Container exists but not running
            local container_status
            container_status=$(docker inspect --format='{{.State.Status}}' "${service}" 2>/dev/null || echo "unknown")
            print_status "FAIL" "${service}: Stopped (${container_status})"
            add_json_result "containers" "${service}" "FAIL" "Container stopped: ${container_status}"
        fi
    done
}

# Check network connectivity
check_network() {
    print_header "Network Connectivity"
    
    # Check if media-network exists
    if ! docker network ls --format '{{.Name}}' | grep -q "^media-network$"; then
        print_status "FAIL" "media-network not found"
        add_json_result "network" "media-network" "FAIL" "Network does not exist"
        return 1
    fi
    
    print_status "PASS" "media-network exists"
    add_json_result "network" "media-network" "PASS" "Network present"
    
    # Test connectivity between services
    local test_pairs=(
        "sonarr:prowlarr:9696"
        "radarr:prowlarr:9696"
        "sonarr:gluetun:6789"
        "radarr:gluetun:6789"
        "jellyseerr:jellyfin:8096"
        "jellyseerr:sonarr:8989"
        "jellyseerr:radarr:7878"
    )
    
    for pair in "${test_pairs[@]}"; do
        IFS=':' read -r source target port <<< "${pair}"
        
        # Skip if either container doesn't exist
        if ! docker ps --format '{{.Names}}' | grep -q "^${source}$"; then
            continue
        fi
        if ! docker ps --format '{{.Names}}' | grep -q "^${target}$"; then
            continue
        fi
        
        # Test connection
        if docker exec "${source}" wget -q --spider --timeout=5 "http://${target}:${port}" 2>/dev/null; then
            print_status "PASS" "${source} → ${target}:${port}"
            add_json_result "network" "${source}-${target}" "PASS" "Connection successful"
        else
            print_status "WARN" "${source} → ${target}:${port} (unreachable)"
            add_json_result "network" "${source}-${target}" "WARN" "Connection failed"
        fi
    done
}

# Check VPN status
check_vpn() {
    print_header "VPN Status"
    
    # Check if gluetun is running
    if ! docker ps --format '{{.Names}}' | grep -q "^gluetun$"; then
        print_status "WARN" "Gluetun container not running"
        add_json_result "vpn" "gluetun" "WARN" "Container not running"
        return 1
    fi
    
    # Check VPN connection status
    local vpn_status
    vpn_status=$(docker exec gluetun wget -qO- http://localhost:8000/v1/openvpn/status 2>/dev/null || echo "unknown")
    
    if [[ "${vpn_status}" == *"running"* ]] || docker exec gluetun ip link show tun0 &>/dev/null; then
        print_status "PASS" "VPN tunnel is active"
        add_json_result "vpn" "tunnel" "PASS" "Tunnel active"
        
        # Get public IP through VPN
        local vpn_ip
        vpn_ip=$(docker exec gluetun wget -qO- https://api.ipify.org 2>/dev/null || echo "unknown")
        print_status "INFO" "VPN IP: ${vpn_ip}"
        add_json_result "vpn" "public-ip" "INFO" "${vpn_ip}"
    else
        print_status "FAIL" "VPN tunnel is down"
        add_json_result "vpn" "tunnel" "FAIL" "Tunnel not active"
    fi
}

# Check disk space
check_disk_space() {
    print_header "Disk Space"
    
    local mounts=(
        "/opt/docker/config"
        "${MEDIA_ROOT}"
        "${MEDIA_ROOT}/downloads"
        "${MEDIA_ROOT}/TV"
        "${MEDIA_ROOT}/Movies"
    )
    
    for mount in "${mounts[@]}"; do
        if [[ ! -d "${mount}" ]]; then
            print_status "WARN" "${mount}: Not mounted"
            add_json_result "disk" "${mount}" "WARN" "Directory not found"
            continue
        fi
        
        local usage
        usage=$(df -h "${mount}" | awk 'NR==2 {print $5}' | sed 's/%//')
        local available
        available=$(df -h "${mount}" | awk 'NR==2 {print $4}')
        
        if [[ ${usage} -ge ${DISK_CRITICAL_THRESHOLD} ]]; then
            print_status "FAIL" "${mount}: ${usage}% used (${available} free) - CRITICAL"
            add_json_result "disk" "${mount}" "FAIL" "${usage}% used, ${available} free"
        elif [[ ${usage} -ge ${DISK_WARNING_THRESHOLD} ]]; then
            print_status "WARN" "${mount}: ${usage}% used (${available} free)"
            add_json_result "disk" "${mount}" "WARN" "${usage}% used, ${available} free"
        else
            print_status "PASS" "${mount}: ${usage}% used (${available} free)"
            add_json_result "disk" "${mount}" "PASS" "${usage}% used, ${available} free"
        fi
    done
}

# Check service accessibility
check_service_accessibility() {
    print_header "Service Accessibility"
    
    local services_to_check=("${!SERVICE_PORTS[@]}")
    
    if [[ -n "${SPECIFIC_SERVICE}" ]]; then
        services_to_check=("${SPECIFIC_SERVICE}")
    fi
    
    for service in "${services_to_check[@]}"; do
        local port="${SERVICE_PORTS[$service]}"
        
        # Skip if container not running
        if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            continue
        fi
        
        # Special handling for NZBGet (accessed via gluetun)
        local target="${service}"
        if [[ "${service}" == "nzbget" ]]; then
            target="gluetun"
        fi
        
        # Test if service responds
        if timeout 5 bash -c "echo > /dev/tcp/localhost/${port}" 2>/dev/null; then
            print_status "PASS" "${service}: Accessible on port ${port}"
            add_json_result "accessibility" "${service}" "PASS" "Port ${port} accessible"
        else
            print_status "WARN" "${service}: Not accessible on port ${port}"
            add_json_result "accessibility" "${service}" "WARN" "Port ${port} not accessible"
        fi
    done
}

# Check system resources
check_system_resources() {
    print_header "System Resources"
    
    # CPU usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | awk '{print int($1)}')
    
    if [[ ${cpu_usage} -ge ${CPU_CRITICAL_THRESHOLD} ]]; then
        print_status "FAIL" "CPU usage: ${cpu_usage}% - CRITICAL"
        add_json_result "resources" "cpu" "FAIL" "${cpu_usage}%"
    elif [[ ${cpu_usage} -ge ${CPU_WARNING_THRESHOLD} ]]; then
        print_status "WARN" "CPU usage: ${cpu_usage}%"
        add_json_result "resources" "cpu" "WARN" "${cpu_usage}%"
    else
        print_status "PASS" "CPU usage: ${cpu_usage}%"
        add_json_result "resources" "cpu" "PASS" "${cpu_usage}%"
    fi
    
    # Memory usage
    local mem_total mem_used mem_usage
    mem_total=$(free | awk 'NR==2 {print $2}')
    mem_used=$(free | awk 'NR==2 {print $3}')
    mem_usage=$((mem_used * 100 / mem_total))
    
    local mem_human
    mem_human=$(free -h | awk 'NR==2 {print $3 "/" $2}')
    
    if [[ ${mem_usage} -ge ${MEMORY_CRITICAL_THRESHOLD} ]]; then
        print_status "FAIL" "Memory usage: ${mem_usage}% (${mem_human}) - CRITICAL"
        add_json_result "resources" "memory" "FAIL" "${mem_usage}%"
    elif [[ ${mem_usage} -ge ${MEMORY_WARNING_THRESHOLD} ]]; then
        print_status "WARN" "Memory usage: ${mem_usage}% (${mem_human})"
        add_json_result "resources" "memory" "WARN" "${mem_usage}%"
    else
        print_status "PASS" "Memory usage: ${mem_usage}% (${mem_human})"
        add_json_result "resources" "memory" "PASS" "${mem_usage}%"
    fi
    
    # Load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    print_status "INFO" "Load average: ${load_avg}"
    add_json_result "resources" "load" "INFO" "${load_avg}"
}

# Check configuration files
check_configurations() {
    print_header "Configuration Files"
    
    local services_to_check=("${!SERVICE_PORTS[@]}")
    
    if [[ -n "${SPECIFIC_SERVICE}" ]]; then
        services_to_check=("${SPECIFIC_SERVICE}")
    fi
    
    for service in "${services_to_check[@]}"; do
        local config_dir="${CONFIG_ROOT}/${service}"
        
        if [[ ! -d "${config_dir}" ]]; then
            print_status "WARN" "${service}: Config directory missing"
            add_json_result "config" "${service}" "WARN" "Directory not found"
        else
            local file_count
            file_count=$(find "${config_dir}" -type f 2>/dev/null | wc -l)
            print_status "PASS" "${service}: Config directory exists (${file_count} files)"
            add_json_result "config" "${service}" "PASS" "${file_count} files present"
        fi
    done
}

# Generate summary report
generate_summary() {
    if [[ "${QUIET}" == "true" ]] && [[ ${CHECKS_FAILED} -eq 0 ]]; then
        return
    fi
    
    echo ""
    echo -e "${BOLD}${MAGENTA}=========================================${RESET}"
    echo -e "${BOLD}${MAGENTA}         HEALTH CHECK SUMMARY${RESET}"
    echo -e "${BOLD}${MAGENTA}=========================================${RESET}"
    echo ""
    
    local total_checks=$((CHECKS_PASSED + CHECKS_WARNED + CHECKS_FAILED))
    
    echo -e "${GREEN}Passed:  ${CHECKS_PASSED}/${total_checks}${RESET}"
    echo -e "${YELLOW}Warnings: ${CHECKS_WARNED}/${total_checks}${RESET}"
    echo -e "${RED}Failed:   ${CHECKS_FAILED}/${total_checks}${RESET}"
    echo ""
    
    if [[ ${CHECKS_FAILED} -eq 0 ]] && [[ ${CHECKS_WARNED} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All systems operational${RESET}"
    elif [[ ${CHECKS_FAILED} -eq 0 ]]; then
        echo -e "${YELLOW}${BOLD}⚠ Some warnings detected${RESET}"
    else
        echo -e "${RED}${BOLD}✗ Critical issues detected${RESET}"
    fi
    
    echo ""
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Exit code: ${EXIT_CODE}"
    echo ""
}

# Generate JSON output
generate_json() {
    if [[ "${JSON_OUTPUT}" != "true" ]]; then
        return
    fi
    
    local json_content
    json_content=$(printf '%s\n' "${JSON_RESULTS[@]}" | paste -sd ',' -)
    
    cat <<EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "exit_code": ${EXIT_CODE},
  "summary": {
    "passed": ${CHECKS_PASSED},
    "warned": ${CHECKS_WARNED},
    "failed": ${CHECKS_FAILED}
  },
  "checks": [${json_content}]
}
EOF
}

# Main health check function
main_health_check() {
    if [[ "${QUIET}" != "true" ]]; then
        echo -e "${BOLD}${CYAN}Brother Eye Media Stack - Health Check${RESET}"
        echo -e "${CYAN}Started: $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    fi
    
    # Create log directory if needed
    mkdir -p "${LOG_DIR}"
    
    # Run all checks
    check_docker
    check_containers
    check_network
    check_vpn
    check_disk_space
    check_service_accessibility
    check_system_resources
    check_configurations
    
    # Generate output
    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        generate_json
    else
        generate_summary
    fi
}

# ============================================================================
# Main Script
# ============================================================================

main_health_check

exit ${EXIT_CODE}
