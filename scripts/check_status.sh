#!/bin/bash

################################################################################
# GOAD Proxmox Installer - Status Checker
#
# This script checks the status of GOAD installation:
# - Network configuration
# - VM status
# - GOAD deployment progress
################################################################################

set -euo pipefail

# Source configuration if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
if [[ -f "${SCRIPT_DIR}/goad_config.conf" ]]; then
    source "${SCRIPT_DIR}/goad_config.conf"
else
    echo "Configuration file not found. Please run installer first."
    exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}           GOAD Proxmox Installation Status Check           ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

check_icon() {
    local status=$1
    if [[ "${status}" == "ok" ]]; then
        echo -e "${GREEN}✓${NC}"
    elif [[ "${status}" == "warn" ]]; then
        echo -e "${YELLOW}⚠${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
}

################################################################################
# Proxmox API Helper
################################################################################

pve_api() {
    local method=$1
    local endpoint=$2
    local url="https://${PROXMOX_HOST}:8006/api2/json${endpoint}"
    local auth_header="Authorization: PVEAPIToken=${PROXMOX_API_USER}=${PROXMOX_API_TOKEN_SECRET}"

    curl -sk -X "${method}" -H "${auth_header}" "${url}" 2>/dev/null || echo "{}"
}

################################################################################
# Check Network
################################################################################

check_network() {
    echo -e "${BLUE}[Network Configuration]${NC}"
    echo

    # Check bridge existence
    local bridge_exists=0
    if ip link show "${BRIDGE_NAME}" &> /dev/null; then
        bridge_exists=1
        echo -e "  $(check_icon ok) Bridge ${BRIDGE_NAME} exists"

        # Check IP address
        local bridge_ip=$(ip addr show "${BRIDGE_NAME}" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        if [[ "${bridge_ip}" == "${NETWORK_GATEWAY}" ]]; then
            echo -e "  $(check_icon ok) Bridge IP: ${bridge_ip}"
        else
            echo -e "  $(check_icon warn) Bridge IP: ${bridge_ip} (expected: ${NETWORK_GATEWAY})"
        fi
    else
        echo -e "  $(check_icon fail) Bridge ${BRIDGE_NAME} not found"
    fi

    # Check IP forwarding
    local ip_forward=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")
    if [[ "${ip_forward}" == "1" ]]; then
        echo -e "  $(check_icon ok) IP forwarding enabled"
    else
        echo -e "  $(check_icon fail) IP forwarding disabled"
    fi

    # Check NAT rules
    if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "MASQUERADE"; then
        echo -e "  $(check_icon ok) NAT rules configured"
    else
        echo -e "  $(check_icon warn) NAT rules not found"
    fi

    echo
}

################################################################################
# Check VMs
################################################################################

check_vms() {
    echo -e "${BLUE}[Virtual Machines]${NC}"
    echo

    local vms=(
        "${DC01_VMID}:${DC01_NAME}:${DC01_IP}"
        "${DC02_VMID}:${DC02_NAME}:${DC02_IP}"
        "${DC03_VMID}:${DC03_NAME}:${DC03_IP}"
        "${SRV02_VMID}:${SRV02_NAME}:${SRV02_IP}"
        "${SRV03_VMID}:${SRV03_NAME}:${SRV03_IP}"
    )

    printf "  %-6s %-20s %-10s %-15s %-10s\n" "VMID" "Name" "Status" "IP" "Ping"
    printf "  %s\n" "────────────────────────────────────────────────────────────────"

    for vm_info in "${vms[@]}"; do
        local vmid="${vm_info%%:*}"
        local rest="${vm_info#*:}"
        local name="${rest%%:*}"
        local ip="${rest##*:}"

        # Get VM status
        local vm_data=$(pve_api GET "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/current")
        local status=$(echo "${vm_data}" | jq -r '.data.status // "not found"')

        # Format status with color
        local status_display
        if [[ "${status}" == "running" ]]; then
            status_display="${GREEN}running${NC}"
        elif [[ "${status}" == "stopped" ]]; then
            status_display="${YELLOW}stopped${NC}"
        else
            status_display="${RED}not found${NC}"
        fi

        # Check ping
        local ping_result
        if ping -c 1 -W 2 "${ip}" &> /dev/null; then
            ping_result="${GREEN}online${NC}"
        else
            ping_result="${RED}offline${NC}"
        fi

        printf "  %-6s %-20s ${status_display}%-${NC}s %-15s ${ping_result}\n" \
            "${vmid}" "${name}" "" "${ip}"
    done

    echo
}

################################################################################
# Check GOAD Repository
################################################################################

check_goad_repo() {
    echo -e "${BLUE}[GOAD Repository]${NC}"
    echo

    if [[ -d "${SCRIPT_DIR}/GOAD" ]]; then
        echo -e "  $(check_icon ok) GOAD repository exists"

        cd "${SCRIPT_DIR}/GOAD"
        local git_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        local git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

        echo -e "  $(check_icon ok) Branch: ${git_branch}"
        echo -e "  $(check_icon ok) Commit: ${git_commit}"

        # Check for Ansible inventory
        if [[ -f "${SCRIPT_DIR}/GOAD/ad/GOAD/data/inventory" ]]; then
            echo -e "  $(check_icon ok) Ansible inventory exists"
        else
            echo -e "  $(check_icon warn) Ansible inventory not found"
        fi
    else
        echo -e "  $(check_icon fail) GOAD repository not found"
        echo -e "      Run installer to download GOAD"
    fi

    echo
}

################################################################################
# Check Ansible Connectivity
################################################################################

check_ansible() {
    echo -e "${BLUE}[Ansible Connectivity]${NC}"
    echo

    if [[ ! -d "${SCRIPT_DIR}/GOAD" ]]; then
        echo -e "  $(check_icon fail) GOAD repository not found"
        echo
        return
    fi

    cd "${SCRIPT_DIR}/GOAD/ansible"

    if [[ ! -f "../ad/GOAD/data/inventory" ]]; then
        echo -e "  $(check_icon warn) Inventory file not found"
        echo
        return
    fi

    # Test WinRM connectivity to each host
    local hosts=("dc01" "dc02" "dc03" "srv02" "srv03")

    for host in "${hosts[@]}"; do
        echo -n "  Testing ${host}... "
        if timeout 5 ansible "${host}" -i ../ad/GOAD/data/inventory -m win_ping &> /dev/null; then
            echo -e "$(check_icon ok) ${GREEN}Connected${NC}"
        else
            echo -e "$(check_icon fail) ${RED}Failed${NC}"
        fi
    done

    echo
}

################################################################################
# Check Deployment Status
################################################################################

check_deployment() {
    echo -e "${BLUE}[GOAD Deployment Status]${NC}"
    echo

    # Check if VMs are domain-joined
    local vms=(
        "${DC01_IP}:sevenkingdoms.local:DC01"
        "${DC02_IP}:north.sevenkingdoms.local:DC02"
        "${DC03_IP}:essos.local:DC03"
    )

    for vm_info in "${vms[@]}"; do
        IFS=':' read -r ip domain name <<< "${vm_info}"

        echo -n "  ${name} - Domain ${domain}... "

        # Try to resolve domain via DNS
        if timeout 2 nslookup "${domain}" "${ip}" &> /dev/null; then
            echo -e "$(check_icon ok) ${GREEN}Active${NC}"
        else
            echo -e "$(check_icon warn) ${YELLOW}Not resolved${NC}"
        fi
    done

    echo
}

################################################################################
# Resource Usage
################################################################################

check_resources() {
    echo -e "${BLUE}[Proxmox Resources]${NC}"
    echo

    local node_status=$(pve_api GET "/nodes/${PROXMOX_NODE}/status")

    local total_mem=$(echo "${node_status}" | jq -r '.data.memory.total // 0')
    local used_mem=$(echo "${node_status}" | jq -r '.data.memory.used // 0')
    local total_mem_gb=$((total_mem / 1024 / 1024 / 1024))
    local used_mem_gb=$((used_mem / 1024 / 1024 / 1024))
    local mem_percent=$((used_mem * 100 / total_mem))

    echo -e "  Memory: ${used_mem_gb}GB / ${total_mem_gb}GB (${mem_percent}%)"

    local cpu_usage=$(echo "${node_status}" | jq -r '.data.cpu // 0')
    local cpu_percent=$(echo "${cpu_usage} * 100" | bc 2>/dev/null || echo "0")
    printf "  CPU Usage: %.1f%%\n" "${cpu_percent}"

    echo
}

################################################################################
# Summary
################################################################################

print_summary() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                          Summary                            ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo

    # Determine installation phase
    local phase="Not Started"
    local next_step="Run ./install_goad_proxmox.sh"

    if [[ -d "${SCRIPT_DIR}/GOAD" ]]; then
        phase="VMs Created"
        next_step="Install Windows on all VMs and enable WinRM"
    fi

    if ip link show "${BRIDGE_NAME}" &> /dev/null; then
        phase="Network Configured"
    fi

    # Check if any VM is running
    local running_vms=0
    for vmid in {${DC01_VMID}..${SRV03_VMID}}; do
        local status=$(pve_api GET "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/current" | jq -r '.data.status // "stopped"')
        if [[ "${status}" == "running" ]]; then
            ((running_vms++))
        fi
    done

    if [[ ${running_vms} -gt 0 ]]; then
        phase="VMs Running (${running_vms}/5)"
        next_step="Complete Windows installation and run GOAD playbooks"
    fi

    # Check if GOAD is deployed
    if timeout 2 nslookup "sevenkingdoms.local" "${DC01_IP}" &> /dev/null; then
        phase="GOAD Deployed"
        next_step="Start penetration testing practice!"
    fi

    echo -e "  Installation Phase: ${GREEN}${phase}${NC}"
    echo -e "  Next Step: ${next_step}"
    echo
}

################################################################################
# Main
################################################################################

main() {
    print_header

    check_network
    check_vms
    check_goad_repo
    check_ansible
    check_deployment
    check_resources
    print_summary

    echo -e "${GREEN}Status check complete!${NC}"
    echo
}

main "$@"
