#!/bin/bash

################################################################################
# GOAD Proxmox Installer - Cleanup/Rollback Script
#
# This script removes GOAD installation from Proxmox:
# - Stops and deletes VMs
# - Removes network configuration
# - Cleans up ISOs (optional)
# - Removes firewall rules
################################################################################

set -euo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"

# Check if config exists
if [[ -f "${SCRIPT_DIR}/goad_config.conf" ]]; then
    source "${SCRIPT_DIR}/goad_config.conf"
else
    echo "Warning: Configuration file not found. Using default values."
    PROXMOX_HOST="${PROXMOX_HOST:-localhost}"
    PROXMOX_NODE="${PROXMOX_NODE:-pve}"
    BRIDGE_NAME="${BRIDGE_NAME:-vmbr50}"
    VLAN_ID="${VLAN_ID:-50}"
    VM_ID_START="${VM_ID_START:-800}"
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@"
}

################################################################################
# Confirmation
################################################################################

confirm_cleanup() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════╗
║                        GOAD CLEANUP WARNING                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  This script will PERMANENTLY DELETE the following:                      ║
║                                                                          ║
║    • All GOAD VMs (DC01, DC02, DC03, SRV02, SRV03)                      ║
║    • VM disks and configurations                                         ║
║    • Network bridge and VLAN configuration                               ║
║    • Firewall rules and NAT configuration                                ║
║                                                                          ║
║  This action CANNOT be undone!                                           ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝

EOF

    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi

    read -p "Last chance! Type 'DELETE' to proceed: " -r
    if [[ ! $REPLY == "DELETE" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

################################################################################
# Proxmox API Helper
################################################################################

pve_api() {
    local method=$1
    local endpoint=$2
    local data=${3:-}

    # Skip if no API credentials
    if [[ -z "${PROXMOX_API_USER:-}" ]] || [[ -z "${PROXMOX_API_TOKEN_SECRET:-}" ]]; then
        log_warning "No API credentials, skipping API call"
        return 0
    fi

    local url="https://${PROXMOX_HOST}:8006/api2/json${endpoint}"
    local auth_header="Authorization: PVEAPIToken=${PROXMOX_API_USER}=${PROXMOX_API_TOKEN_SECRET}"

    if [[ -n "${data}" ]]; then
        curl -sk -X "${method}" -H "${auth_header}" --data "${data}" "${url}" 2>/dev/null || true
    else
        curl -sk -X "${method}" -H "${auth_header}" "${url}" 2>/dev/null || true
    fi
}

################################################################################
# VM Cleanup
################################################################################

stop_vm() {
    local vmid=$1

    log_info "Stopping VM ${vmid}..."

    # Check if VM exists
    local vm_exists=$(pve_api GET "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/current" | jq -r '.data.status // "stopped"' 2>/dev/null || echo "stopped")

    if [[ "${vm_exists}" == "running" ]]; then
        log_info "VM ${vmid} is running, stopping..."
        pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/stop"
        sleep 5
    fi

    # Force stop if still running
    local still_running=$(pve_api GET "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/current" | jq -r '.data.status // "stopped"' 2>/dev/null || echo "stopped")
    if [[ "${still_running}" == "running" ]]; then
        log_warning "Force stopping VM ${vmid}..."
        pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/stop" "forceStop=1"
        sleep 5
    fi

    log_success "VM ${vmid} stopped"
}

delete_vm() {
    local vmid=$1
    local name=$2

    log_info "Deleting VM ${vmid} (${name})..."

    # Stop VM first
    stop_vm "${vmid}"

    # Delete VM
    local delete_result=$(pve_api DELETE "/nodes/${PROXMOX_NODE}/qemu/${vmid}")

    if [[ $? -eq 0 ]]; then
        log_success "VM ${vmid} (${name}) deleted"
    else
        log_warning "Failed to delete VM ${vmid}, may not exist"
    fi
}

cleanup_all_vms() {
    log_info "Cleaning up all GOAD VMs..."

    # Delete VMs based on configuration
    local vm_ids=(
        "${DC01_VMID:-800}:${DC01_NAME:-GOAD-DC01}"
        "${DC02_VMID:-801}:${DC02_NAME:-GOAD-DC02}"
        "${DC03_VMID:-802}:${DC03_NAME:-GOAD-DC03}"
        "${SRV02_VMID:-803}:${SRV02_NAME:-GOAD-SRV02}"
        "${SRV03_VMID:-804}:${SRV03_NAME:-GOAD-SRV03}"
    )

    for vm_info in "${vm_ids[@]}"; do
        local vmid="${vm_info%%:*}"
        local name="${vm_info##*:}"
        delete_vm "${vmid}" "${name}"
    done

    log_success "All VMs cleaned up"
}

################################################################################
# Network Cleanup
################################################################################

cleanup_nat_rules() {
    log_info "Cleaning up NAT and firewall rules..."

    # Remove iptables rules
    if iptables -t nat -C POSTROUTING -s ${NETWORK_SUBNET:-192.168.50.0/24} -o ${INTERNET_INTERFACE:-vmbr0} -j MASQUERADE 2>/dev/null; then
        iptables -t nat -D POSTROUTING -s ${NETWORK_SUBNET:-192.168.50.0/24} -o ${INTERNET_INTERFACE:-vmbr0} -j MASQUERADE
        log_success "NAT rule removed"
    fi

    if iptables -C FORWARD -i ${BRIDGE_NAME} -o ${INTERNET_INTERFACE:-vmbr0} -j ACCEPT 2>/dev/null; then
        iptables -D FORWARD -i ${BRIDGE_NAME} -o ${INTERNET_INTERFACE:-vmbr0} -j ACCEPT
        log_success "Forward rule removed"
    fi

    if iptables -C FORWARD -i ${INTERNET_INTERFACE:-vmbr0} -o ${BRIDGE_NAME} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        iptables -D FORWARD -i ${INTERNET_INTERFACE:-vmbr0} -o ${BRIDGE_NAME} -m state --state RELATED,ESTABLISHED -j ACCEPT
        log_success "Return forward rule removed"
    fi

    # Save iptables rules
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4
        log_success "iptables rules saved"
    fi
}

cleanup_bridge() {
    log_info "Cleaning up network bridge ${BRIDGE_NAME}..."

    # Bring down the bridge
    if ip link show "${BRIDGE_NAME}" &> /dev/null; then
        log_info "Bringing down bridge ${BRIDGE_NAME}..."
        ip link set "${BRIDGE_NAME}" down 2>/dev/null || true

        # Remove bridge
        ip link delete "${BRIDGE_NAME}" 2>/dev/null || true
        log_success "Bridge ${BRIDGE_NAME} removed"
    else
        log_info "Bridge ${BRIDGE_NAME} does not exist"
    fi

    # Remove from network configuration
    if [[ -f /etc/network/interfaces ]]; then
        log_info "Removing bridge from /etc/network/interfaces..."

        # Create backup
        cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S)

        # Remove bridge configuration
        sed -i "/# GOAD Lab Network/,/^$/d" /etc/network/interfaces
        log_success "Bridge configuration removed from interfaces file"
    fi
}

cleanup_dnsmasq() {
    log_info "Cleaning up dnsmasq configuration..."

    if [[ -f /etc/dnsmasq.d/goad.conf ]]; then
        rm -f /etc/dnsmasq.d/goad.conf
        systemctl restart dnsmasq 2>/dev/null || true
        log_success "dnsmasq configuration removed"
    else
        log_info "No dnsmasq configuration found"
    fi
}

cleanup_network() {
    log_info "Cleaning up network configuration..."

    cleanup_nat_rules
    cleanup_bridge
    cleanup_dnsmasq

    log_success "Network cleanup completed"
}

################################################################################
# ISO Cleanup (Optional)
################################################################################

cleanup_isos() {
    read -p "Do you want to delete downloaded ISOs? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping ISO cleanup"
        return 0
    fi

    log_info "Cleaning up ISOs..."

    # This would require Proxmox API or SSH access
    log_warning "ISO cleanup not implemented yet"
    log_info "Please manually delete ISOs from Proxmox storage if needed"
}

################################################################################
# GOAD Repository Cleanup
################################################################################

cleanup_goad_repo() {
    read -p "Do you want to delete the GOAD repository? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping GOAD repository"
        return 0
    fi

    log_info "Removing GOAD repository..."

    if [[ -d "${SCRIPT_DIR}/GOAD" ]]; then
        rm -rf "${SCRIPT_DIR}/GOAD"
        log_success "GOAD repository removed"
    else
        log_info "GOAD repository not found"
    fi
}

################################################################################
# Log Cleanup
################################################################################

cleanup_logs() {
    read -p "Do you want to delete log files? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping log files"
        return 0
    fi

    log_info "Cleaning up log files..."

    if [[ -d "${SCRIPT_DIR}/logs" ]]; then
        rm -rf "${SCRIPT_DIR}/logs"/*
        log_success "Log files removed"
    else
        log_info "No log files found"
    fi
}

################################################################################
# Complete Cleanup
################################################################################

complete_cleanup() {
    log_info "Performing complete cleanup of GOAD installation..."

    # Cleanup VMs
    cleanup_all_vms

    # Cleanup network
    cleanup_network

    # Optional cleanups
    cleanup_isos
    cleanup_goad_repo
    cleanup_logs

    log_success "Complete cleanup finished"
}

################################################################################
# Selective Cleanup Options
################################################################################

show_menu() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════╗
║                      GOAD Cleanup Options                                ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  1. Complete cleanup (VMs + Network + Everything)                        ║
║  2. Remove VMs only                                                      ║
║  3. Remove network configuration only                                    ║
║  4. Remove GOAD repository only                                          ║
║  5. Remove log files only                                                ║
║  6. Exit                                                                 ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝

EOF

    read -p "Select an option (1-6): " -n 1 -r
    echo
    return $REPLY
}

selective_cleanup() {
    show_menu
    local choice=$?

    case $choice in
        1)
            confirm_cleanup
            complete_cleanup
            ;;
        2)
            confirm_cleanup
            cleanup_all_vms
            ;;
        3)
            confirm_cleanup
            cleanup_network
            ;;
        4)
            cleanup_goad_repo
            ;;
        5)
            cleanup_logs
            ;;
        6)
            log_info "Exiting cleanup script"
            exit 0
            ;;
        *)
            log_error "Invalid option"
            exit 1
            ;;
    esac
}

################################################################################
# Main Function
################################################################################

main() {
    log_info "GOAD Cleanup Script"
    echo

    # Check if running with arguments
    if [[ $# -gt 0 ]]; then
        case $1 in
            --complete)
                confirm_cleanup
                complete_cleanup
                ;;
            --vms-only)
                confirm_cleanup
                cleanup_all_vms
                ;;
            --network-only)
                confirm_cleanup
                cleanup_network
                ;;
            --help)
                echo "Usage: $0 [OPTION]"
                echo ""
                echo "Options:"
                echo "  --complete      Complete cleanup (VMs + Network + Everything)"
                echo "  --vms-only      Remove VMs only"
                echo "  --network-only  Remove network configuration only"
                echo "  --help          Show this help message"
                echo ""
                echo "If no option is provided, interactive menu will be shown"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
        esac
    else
        # Interactive mode
        selective_cleanup
    fi

    echo
    log_success "════════════════════════════════════════════════════════════════"
    log_success "Cleanup completed successfully"
    log_success "════════════════════════════════════════════════════════════════"
}

main "$@"
