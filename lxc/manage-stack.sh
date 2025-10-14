#!/bin/bash
################################################################################
# Brother Eye Media Stack - Management Helper Tool
# 
# This script provides an interactive menu for common Docker stack operations.
# It simplifies daily management tasks without needing to remember commands.
#
# Usage: Run this script INSIDE the LXC container as mediauser
#   ./manage-stack.sh [command]
#
# Commands:
#   status       Show container status
#   logs         View logs (interactive service selection)
#   restart      Restart service (interactive service selection)
#   update       Pull and update all containers
#   backup       Backup configurations
#   restore      Restore from backup
#   health       Run health checks
#   shell        Open shell in container
#   menu         Show interactive menu (default)
#
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
DOCKER_DIR="/opt/docker"
REPO_DIR="${DOCKER_DIR}/brother-eye-media-stack"
COMPOSE_DIR="${REPO_DIR}/docker"
BACKUP_SCRIPT="${REPO_DIR}/scripts/backup-configs.sh"
RESTORE_SCRIPT="${REPO_DIR}/scripts/restore-configs.sh"
HEALTH_SCRIPT="${REPO_DIR}/scripts/health-check.sh"

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}Brother Eye Media Stack - Management Console${NC}         ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
}

check_compose_dir() {
    if [[ ! -d "${COMPOSE_DIR}" ]]; then
        log_error "Docker compose directory not found: ${COMPOSE_DIR}"
        log_info "Please run deploy-stack.sh first"
        exit 1
    fi
    cd "${COMPOSE_DIR}"
}

press_enter() {
    echo
    read -p "Press Enter to continue..."
}

################################################################################
# Status Display
################################################################################

show_status() {
    print_header
    echo -e "${BOLD}Container Status${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    check_compose_dir
    
    # Get running containers count
    local running=$(docker compose ps --format json 2>/dev/null | jq -r '. | select(.State == "running") | .Service' | wc -l)
    local total=$(docker compose ps --format json 2>/dev/null | jq -r '.Service' | wc -l)
    
    if [[ ${total} -eq 0 ]]; then
        log_warning "No containers found. Stack may not be deployed."
        return 1
    fi
    
    echo -e "${GREEN}Running: ${running}/${total}${NC}"
    echo
    
    # Display detailed status
    docker compose ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check for unhealthy containers
    local unhealthy=$(docker compose ps --format json 2>/dev/null | jq -r '. | select(.State != "running") | .Service')
    
    if [[ -n "${unhealthy}" ]]; then
        echo
        log_warning "Containers not running:"
        echo "${unhealthy}" | while read -r service; do
            echo "  - ${service}"
        done
    fi
}

################################################################################
# Log Viewer
################################################################################

view_logs() {
    local service=$1
    
    print_header
    echo -e "${BOLD}Viewing logs for: ${CYAN}${service}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log_info "Press Ctrl+C to exit logs"
    echo
    sleep 2
    
    check_compose_dir
    docker compose logs -f --tail=100 "${service}"
}

select_service_for_logs() {
    print_header
    echo -e "${BOLD}Select Service to View Logs${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    check_compose_dir
    
    # Get list of services
    local services=($(docker compose ps --services 2>/dev/null))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log_error "No services found"
        press_enter
        return
    fi
    
    # Add "All" option
    services=("all" "${services[@]}")
    
    # Display menu
    local i=1
    for service in "${services[@]}"; do
        echo "  ${i}) ${service}"
        ((i++))
    done
    echo "  0) Back to main menu"
    echo
    
    read -p "Select service [0-${#services[@]}]: " choice
    
    if [[ ${choice} -eq 0 ]]; then
        return
    elif [[ ${choice} -ge 1 ]] && [[ ${choice} -le ${#services[@]} ]]; then
        local selected="${services[$((choice-1))]}"
        if [[ "${selected}" == "all" ]]; then
            view_logs ""
        else
            view_logs "${selected}"
        fi
    else
        log_error "Invalid selection"
        press_enter
    fi
}

################################################################################
# Service Management
################################################################################

restart_service() {
    local service=$1
    
    print_header
    echo -e "${BOLD}Restarting service: ${CYAN}${service}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    check_compose_dir
    
    log_info "Restarting ${service}..."
    
    if docker compose restart "${service}"; then
        log_success "${service} restarted successfully"
    else
        log_error "Failed to restart ${service}"
    fi
    
    press_enter
}

stop_service() {
    local service=$1
    
    print_header
    echo -e "${BOLD}Stopping service: ${CYAN}${service}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    check_compose_dir
    
    log_info "Stopping ${service}..."
    
    if docker compose stop "${service}"; then
        log_success "${service} stopped successfully"
    else
        log_error "Failed to stop ${service}"
    fi
    
    press_enter
}

start_service() {
    local service=$1
    
    print_header
    echo -e "${BOLD}Starting service: ${CYAN}${service}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    check_compose_dir
    
    log_info "Starting ${service}..."
    
    if docker compose start "${service}"; then
        log_success "${service} started successfully"
    else
        log_error "Failed to start ${service}"
    fi
    
    press_enter
}

select_service_for_action() {
    local action=$1
    local action_func=$2
    
    print_header
    echo -e "${BOLD}Select Service to ${action}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    check_compose_dir
    
    # Get list of services
    local services=($(docker compose ps --services 2>/dev/null))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log_error "No services found"
        press_enter
        return
    fi
    
    # Display menu
    local i=1
    for service in "${services[@]}"; do
        local state=$(docker compose ps "${service}" --format json 2>/dev/null | jq -r '.State')
        echo "  ${i}) ${service} [${state}]"
        ((i++))
    done
    echo "  0) Back to main menu"
    echo
    
    read -p "Select service [0-${#services[@]}]: " choice
    
    if [[ ${choice} -eq 0 ]]; then
        return
    elif [[ ${choice} -ge 1 ]] && [[ ${choice} -le ${#services[@]} ]]; then
        local selected="${services[$((choice-1))]}"
        ${action_func} "${selected}"
    else
        log_error "Invalid selection"
        press_enter
    fi
}

################################################################################
# Stack Operations
################################################################################

stop_all() {
    print_header
    echo -e "${BOLD}Stop All Services${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    log_warning "This will stop all running containers"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        press_enter
        return
    fi
    
    check_compose_dir
    
    log_info "Stopping all services..."
    
    if docker compose stop; then
        log_success "All services stopped"
    else
        log_error "Failed to stop some services"
    fi
    
    press_enter
}

start_all() {
    print_header
    echo -e "${BOLD}Start All Services${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    check_compose_dir
    
    log_info "Starting all services..."
    
    if docker compose start; then
        log_success "All services started"
    else
        log_error "Failed to start some services"
    fi
    
    press_enter
}

restart_all() {
    print_header
    echo -e "${BOLD}Restart All Services${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    log_warning "This will restart all running containers"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        press_enter
        return
    fi
    
    check_compose_dir
    
    log_info "Restarting all services..."
    
    if docker compose restart; then
        log_success "All services restarted"
    else
        log_error "Failed to restart some services"
    fi
    
    press_enter
}

################################################################################
# Update Operations
################################################################################

update_stack() {
    print_header
    echo -e "${BOLD}Update All Containers${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    log_warning "This will pull new images and recreate containers"
    log_info "Any containers with updates will be restarted"
    echo
    read -p "Continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        press_enter
        return
    fi
    
    check_compose_dir
    
    log_info "Pulling latest images..."
    docker compose pull
    echo
    
    log_info "Recreating updated containers..."
    docker compose up -d
    echo
    
    log_success "Update complete!"
    
    press_enter
}

################################################################################
# Backup/Restore Operations
################################################################################

run_backup() {
    print_header
    echo -e "${BOLD}Backup Configurations${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    if [[ ! -x "${BACKUP_SCRIPT}" ]]; then
        log_error "Backup script not found or not executable: ${BACKUP_SCRIPT}"
        press_enter
        return
    fi
    
    log_info "Running backup script..."
    echo
    
    "${BACKUP_SCRIPT}"
    
    press_enter
}

run_restore() {
    print_header
    echo -e "${BOLD}Restore Configurations${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    if [[ ! -x "${RESTORE_SCRIPT}" ]]; then
        log_error "Restore script not found or not executable: ${RESTORE_SCRIPT}"
        press_enter
        return
    fi
    
    log_warning "This will restore configurations from backup"
    log_warning "Current configurations will be overwritten"
    echo
    read -p "Continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        press_enter
        return
    fi
    
    log_info "Running restore script..."
    echo
    
    "${RESTORE_SCRIPT}"
    
    press_enter
}

################################################################################
# Health Check
################################################################################

run_health_check() {
    print_header
    echo -e "${BOLD}Health Check${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    if [[ ! -x "${HEALTH_SCRIPT}" ]]; then
        log_error "Health check script not found or not executable: ${HEALTH_SCRIPT}"
        press_enter
        return
    fi
    
    log_info "Running health checks..."
    echo
    
    "${HEALTH_SCRIPT}"
    
    press_enter
}

################################################################################
# Shell Access
################################################################################

open_shell() {
    local service=$1
    
    print_header
    echo -e "${BOLD}Opening shell in: ${CYAN}${service}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    check_compose_dir
    
    log_info "Opening shell... (type 'exit' to return)"
    echo
    sleep 1
    
    docker compose exec "${service}" /bin/bash || docker compose exec "${service}" /bin/sh
}

select_service_for_shell() {
    print_header
    echo -e "${BOLD}Select Service for Shell Access${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    check_compose_dir
    
    # Get list of running services
    local services=($(docker compose ps --format json 2>/dev/null | jq -r '. | select(.State == "running") | .Service'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log_error "No running services found"
        press_enter
        return
    fi
    
    # Display menu
    local i=1
    for service in "${services[@]}"; do
        echo "  ${i}) ${service}"
        ((i++))
    done
    echo "  0) Back to main menu"
    echo
    
    read -p "Select service [0-${#services[@]}]: " choice
    
    if [[ ${choice} -eq 0 ]]; then
        return
    elif [[ ${choice} -ge 1 ]] && [[ ${choice} -le ${#services[@]} ]]; then
        local selected="${services[$((choice-1))]}"
        open_shell "${selected}"
    else
        log_error "Invalid selection"
        press_enter
    fi
}

################################################################################
# Interactive Menu
################################################################################

show_menu() {
    print_header
    
    # Display quick status
    check_compose_dir
    local running=$(docker compose ps --format json 2>/dev/null | jq -r '. | select(.State == "running") | .Service' | wc -l)
    local total=$(docker compose ps --format json 2>/dev/null | jq -r '.Service' | wc -l)
    
    echo -e "${BOLD}Quick Status:${NC} ${GREEN}${running}${NC}/${total} containers running"
    echo
    echo -e "${BOLD}Main Menu${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "  ${CYAN}Status & Monitoring${NC}"
    echo "    1) Show container status"
    echo "    2) View logs"
    echo "    3) Run health check"
    echo
    echo "  ${CYAN}Service Management${NC}"
    echo "    4) Restart service"
    echo "    5) Stop service"
    echo "    6) Start service"
    echo "    7) Shell into container"
    echo
    echo "  ${CYAN}Stack Operations${NC}"
    echo "    8) Restart all services"
    echo "    9) Stop all services"
    echo "   10) Start all services"
    echo "   11) Update all containers"
    echo
    echo "  ${CYAN}Backup & Restore${NC}"
    echo "   12) Backup configurations"
    echo "   13) Restore from backup"
    echo
    echo "    0) Exit"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

process_menu_choice() {
    local choice=$1
    
    case ${choice} in
        1)
            show_status
            press_enter
            ;;
        2)
            select_service_for_logs
            ;;
        3)
            run_health_check
            ;;
        4)
            select_service_for_action "Restart" "restart_service"
            ;;
        5)
            select_service_for_action "Stop" "stop_service"
            ;;
        6)
            select_service_for_action "Start" "start_service"
            ;;
        7)
            select_service_for_shell
            ;;
        8)
            restart_all
            ;;
        9)
            stop_all
            ;;
        10)
            start_all
            ;;
        11)
            update_stack
            ;;
        12)
            run_backup
            ;;
        13)
            run_restore
            ;;
        0)
            print_header
            echo "Goodbye!"
            echo
            exit 0
            ;;
        *)
            log_error "Invalid option"
            press_enter
            ;;
    esac
}

interactive_menu() {
    while true; do
        show_menu
        read -p "Select option [0-13]: " choice
        process_menu_choice "${choice}"
    done
}

################################################################################
# Main Execution
################################################################################

main() {
    # Check if command provided
    if [[ $# -gt 0 ]]; then
        case $1 in
            status)
                show_status
                ;;
            logs)
                if [[ $# -gt 1 ]]; then
                    view_logs "$2"
                else
                    select_service_for_logs
                fi
                ;;
            restart)
                if [[ $# -gt 1 ]]; then
                    restart_service "$2"
                else
                    select_service_for_action "Restart" "restart_service"
                fi
                ;;
            update)
                update_stack
                ;;
            backup)
                run_backup
                ;;
            restore)
                run_restore
                ;;
            health)
                run_health_check
                ;;
            shell)
                if [[ $# -gt 1 ]]; then
                    open_shell "$2"
                else
                    select_service_for_shell
                fi
                ;;
            menu|*)
                interactive_menu
                ;;
        esac
    else
        interactive_menu
    fi
}

# Run main function
main "$@"
