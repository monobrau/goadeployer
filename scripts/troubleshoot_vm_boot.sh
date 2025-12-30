#!/bin/bash

################################################################################
# VM Boot Troubleshooting Script
#
# This script helps diagnose why VMs aren't booting
#
# Usage: ./scripts/troubleshoot_vm_boot.sh [VMID]
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/goad_config.conf"

# Load config if exists
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
fi

VMID="${1:-}"

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

check_vm_exists() {
    local vmid=$1
    if command -v qm &> /dev/null; then
        if qm list | grep -q "^[[:space:]]*${vmid}[[:space:]]"; then
            return 0
        fi
    fi
    return 1
}

check_vm_status() {
    local vmid=$1
    if command -v qm &> /dev/null; then
        local status=$(qm status "${vmid}" 2>/dev/null | awk '{print $2}')
        echo "${status}"
    else
        echo "unknown"
    fi
}

check_iso_attached() {
    local vmid=$1
    if command -v qm &> /dev/null; then
        local iso=$(qm config "${vmid}" 2>/dev/null | grep "^ide0:" | cut -d: -f2 | cut -d, -f1 | tr -d ' ')
        if [[ -n "${iso}" ]] && [[ "${iso}" != "none" ]]; then
            echo "${iso}"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

check_boot_order() {
    local vmid=$1
    if command -v qm &> /dev/null; then
        local boot=$(qm config "${vmid}" 2>/dev/null | grep "^boot:" | cut -d: -f2 | tr -d ' ')
        echo "${boot}"
    else
        echo ""
    fi
}

check_machine_type() {
    local vmid=$1
    if command -v qm &> /dev/null; then
        local machine=$(qm config "${vmid}" 2>/dev/null | grep "^machine:" | cut -d: -f2 | tr -d ' ' || echo "default")
        echo "${machine}"
    else
        echo "unknown"
    fi
}

check_iso_exists() {
    local iso_path=$1
    if command -v qm &> /dev/null; then
        # Extract storage and filename
        local storage=$(echo "${iso_path}" | cut -d: -f1)
        local filename=$(echo "${iso_path}" | cut -d: -f2)
        
        # Check if ISO exists in storage
        if pvesm list "${storage}" 2>/dev/null | grep -q "${filename}"; then
            return 0
        fi
    fi
    return 1
}

troubleshoot_vm() {
    local vmid=$1
    
    log_info "Troubleshooting VM ${vmid}..."
    echo
    
    # Check if VM exists
    if ! check_vm_exists "${vmid}"; then
        log_error "VM ${vmid} does not exist!"
        return 1
    fi
    
    log_success "VM ${vmid} exists"
    
    # Check VM status
    local status=$(check_vm_status "${vmid}")
    log_info "VM Status: ${status}"
    
    if [[ "${status}" == "running" ]]; then
        log_warning "VM is already running. Check the console to see what's happening."
        log_info "Open console: qm terminal ${vmid}"
    elif [[ "${status}" == "stopped" ]]; then
        log_info "VM is stopped. Checking configuration..."
    fi
    
    echo
    log_info "Checking VM Configuration..."
    
    # Check ISO attachment
    local iso=$(check_iso_attached "${vmid}")
    if [[ -z "${iso}" ]]; then
        log_error "No ISO attached to ide0!"
        log_info "Fix: qm set ${vmid} --ide0 ${PROXMOX_STORAGE:-local}:iso/YOUR_ISO.iso,media=cdrom"
    else
        log_success "ISO attached: ${iso}"
        
        # Check if ISO exists
        if check_iso_exists "${iso}"; then
            log_success "ISO file exists in storage"
        else
            log_error "ISO file NOT FOUND in storage: ${iso}"
            log_info "Please verify the ISO exists and path is correct"
        fi
    fi
    
    # Check boot order
    local boot_order=$(check_boot_order "${vmid}")
    if [[ -z "${boot_order}" ]]; then
        log_error "Boot order not configured!"
        log_info "Fix: qm set ${vmid} --boot order=ide0;scsi0"
    else
        log_success "Boot order: ${boot_order}"
        if [[ "${boot_order}" != *"ide0"* ]]; then
            log_warning "Boot order doesn't include ide0 (CD-ROM)!"
            log_info "Fix: qm set ${vmid} --boot order=ide0;scsi0"
        fi
    fi
    
    # Check machine type
    local machine=$(check_machine_type "${vmid}")
    log_info "Machine type: ${machine}"
    
    # Check disk
    log_info "Checking disk configuration..."
    if command -v qm &> /dev/null; then
        local disk=$(qm config "${vmid}" 2>/dev/null | grep "^scsi0:" || echo "")
        if [[ -z "${disk}" ]]; then
            log_error "No disk configured!"
        else
            log_success "Disk configured: ${disk}"
        fi
    fi
    
    # Check network
    log_info "Checking network configuration..."
    if command -v qm &> /dev/null; then
        local network=$(qm config "${vmid}" 2>/dev/null | grep "^net0:" || echo "")
        if [[ -z "${network}" ]]; then
            log_warning "No network configured (may be OK for initial boot)"
        else
            log_success "Network configured: ${network}"
        fi
    fi
    
    echo
    log_info "Recommended Fixes:"
    echo "  1. Ensure ISO is attached: qm set ${vmid} --ide0 ${PROXMOX_STORAGE:-local}:iso/YOUR_ISO.iso,media=cdrom"
    echo "  2. Set boot order: qm set ${vmid} --boot order=ide0;scsi0"
    echo "  3. Start VM: qm start ${vmid}"
    echo "  4. Open console: qm terminal ${vmid}"
    echo
}

main() {
    if [[ -z "${VMID}" ]]; then
        log_info "Checking all GOAD VMs..."
        echo
        
        local vms=(
            "${DC01_VMID:-800}:DC01"
            "${DC02_VMID:-801}:DC02"
            "${DC03_VMID:-802}:DC03"
            "${SRV02_VMID:-803}:SRV02"
            "${SRV03_VMID:-804}:SRV03"
        )
        
        for vm_entry in "${vms[@]}"; do
            IFS=':' read -r vmid name <<< "${vm_entry}"
            echo "════════════════════════════════════════════════════════════"
            troubleshoot_vm "${vmid}"
            echo
        done
    else
        troubleshoot_vm "${VMID}"
    fi
}

main "$@"

