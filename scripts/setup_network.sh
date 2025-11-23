#!/bin/bash

################################################################################
# GOAD Proxmox Installer - Network Setup Script
#
# This script configures the network for GOAD lab on Proxmox:
# - Creates Linux bridge for VLAN 50
# - Configures NAT for internet access
# - Sets up routing
################################################################################

set -euo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "${SCRIPT_DIR}/goad_config.conf"

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
# Proxmox API Helper Functions
################################################################################

proxmox_api_call() {
    local method=$1
    local endpoint=$2
    local data=${3:-}

    local url="https://${PROXMOX_HOST}:8006/api2/json${endpoint}"
    local auth_header="Authorization: PVEAPIToken=${PROXMOX_API_USER}=${PROXMOX_API_TOKEN_SECRET}"

    if [[ -n "${data}" ]]; then
        curl -sk -X "${method}" -H "${auth_header}" -d "${data}" "${url}"
    else
        curl -sk -X "${method}" -H "${auth_header}" "${url}"
    fi
}

################################################################################
# Network Configuration on Proxmox Node
################################################################################

configure_network_on_proxmox() {
    log_info "Configuring network on Proxmox node ${PROXMOX_NODE}..."

    # Check if bridge already exists
    if ssh_execute "ip link show ${BRIDGE_NAME}" &> /dev/null; then
        log_warning "Bridge ${BRIDGE_NAME} already exists"
        return 0
    fi

    # Create VLAN-aware bridge configuration
    log_info "Creating Linux bridge ${BRIDGE_NAME} for VLAN ${VLAN_ID}..."

    local network_config="/etc/network/interfaces"

    # Backup existing network configuration
    ssh_execute "cp ${network_config} ${network_config}.backup.$(date +%Y%m%d_%H%M%S)"

    # Add bridge configuration
    cat << EOF | ssh_execute "cat >> ${network_config}"

# GOAD Lab Network - VLAN ${VLAN_ID}
auto ${BRIDGE_NAME}
iface ${BRIDGE_NAME} inet static
    address ${NETWORK_GATEWAY}/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids ${VLAN_ID}
EOF

    # Bring up the interface
    ssh_execute "ifup ${BRIDGE_NAME}" || log_warning "Failed to bring up ${BRIDGE_NAME}, may require reboot"

    # Verify bridge creation
    if ssh_execute "ip link show ${BRIDGE_NAME}" &> /dev/null; then
        log_success "Bridge ${BRIDGE_NAME} created successfully"
    else
        log_error "Failed to create bridge ${BRIDGE_NAME}"
        return 1
    fi
}

################################################################################
# NAT Configuration
################################################################################

configure_nat() {
    if [[ "${ENABLE_NAT}" != "true" ]]; then
        log_info "NAT is disabled, skipping NAT configuration"
        return 0
    fi

    log_info "Configuring NAT for internet access..."

    # Enable IP forwarding
    ssh_execute "echo 1 > /proc/sys/net/ipv4/ip_forward"
    ssh_execute "sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf"
    ssh_execute "sysctl -p"

    # Configure iptables NAT rules
    log_info "Setting up iptables NAT rules..."

    # Check if rules already exist
    if ssh_execute "iptables -t nat -C POSTROUTING -s ${NETWORK_SUBNET} -o ${INTERNET_INTERFACE} -j MASQUERADE" &> /dev/null; then
        log_warning "NAT rules already exist"
    else
        # Add NAT rule
        ssh_execute "iptables -t nat -A POSTROUTING -s ${NETWORK_SUBNET} -o ${INTERNET_INTERFACE} -j MASQUERADE"

        # Add forwarding rules
        ssh_execute "iptables -A FORWARD -i ${BRIDGE_NAME} -o ${INTERNET_INTERFACE} -j ACCEPT"
        ssh_execute "iptables -A FORWARD -i ${INTERNET_INTERFACE} -o ${BRIDGE_NAME} -m state --state RELATED,ESTABLISHED -j ACCEPT"

        log_success "NAT rules configured"
    fi

    # Make iptables rules persistent
    install_iptables_persistent

    log_success "NAT configuration completed"
}

install_iptables_persistent() {
    log_info "Making iptables rules persistent..."

    # Check if iptables-persistent is installed
    if ! ssh_execute "dpkg -l | grep -q iptables-persistent"; then
        log_info "Installing iptables-persistent..."
        ssh_execute "DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent"
    fi

    # Save current rules
    ssh_execute "iptables-save > /etc/iptables/rules.v4"

    log_success "iptables rules saved"
}

################################################################################
# DNS Configuration
################################################################################

configure_dns() {
    log_info "Configuring DNS forwarder on gateway..."

    # Install dnsmasq for DNS forwarding
    if ! ssh_execute "command -v dnsmasq" &> /dev/null; then
        log_info "Installing dnsmasq..."
        ssh_execute "apt-get update && apt-get install -y dnsmasq"
    fi

    # Configure dnsmasq for GOAD network
    cat << EOF | ssh_execute "cat > /etc/dnsmasq.d/goad.conf"
# GOAD Lab DNS Configuration
interface=${BRIDGE_NAME}
bind-interfaces
domain=goad.local
dhcp-range=${NETWORK_SUBNET%.*}.100,${NETWORK_SUBNET%.*}.200,12h

# Static DNS entries for GOAD VMs
address=/dc01.sevenkingdoms.local/${DC01_IP}
address=/dc02.north.sevenkingdoms.local/${DC02_IP}
address=/dc03.essos.local/${DC03_IP}
address=/srv02.sevenkingdoms.local/${SRV02_IP}
address=/srv03.essos.local/${SRV03_IP}

# Forward other queries to public DNS
server=8.8.8.8
server=8.8.4.4
EOF

    # Restart dnsmasq
    ssh_execute "systemctl restart dnsmasq"
    ssh_execute "systemctl enable dnsmasq"

    log_success "DNS configuration completed"
}

################################################################################
# SSH Helper Functions
################################################################################

ssh_execute() {
    local command=$1

    # Execute command on Proxmox host via SSH
    # In a real scenario, you might need SSH key setup
    # For now, we'll use direct execution assuming we're on the Proxmox host

    if [[ "${PROXMOX_HOST}" == "localhost" ]] || [[ "${PROXMOX_HOST}" == "127.0.0.1" ]]; then
        bash -c "${command}"
    else
        ssh -o StrictHostKeyChecking=no "root@${PROXMOX_HOST}" "${command}"
    fi
}

################################################################################
# Network Verification
################################################################################

verify_network() {
    log_info "Verifying network configuration..."

    # Check bridge exists
    if ! ssh_execute "ip link show ${BRIDGE_NAME}" &> /dev/null; then
        log_error "Bridge ${BRIDGE_NAME} does not exist"
        return 1
    fi

    # Check IP address
    local bridge_ip=$(ssh_execute "ip addr show ${BRIDGE_NAME} | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")
    if [[ "${bridge_ip}" == "${NETWORK_GATEWAY}" ]]; then
        log_success "Bridge IP configured correctly: ${bridge_ip}"
    else
        log_warning "Bridge IP mismatch. Expected: ${NETWORK_GATEWAY}, Got: ${bridge_ip}"
    fi

    # Check IP forwarding
    local ip_forward=$(ssh_execute "cat /proc/sys/net/ipv4/ip_forward")
    if [[ "${ip_forward}" == "1" ]]; then
        log_success "IP forwarding enabled"
    else
        log_warning "IP forwarding not enabled"
    fi

    # Check NAT rules
    if ssh_execute "iptables -t nat -L POSTROUTING -n | grep -q MASQUERADE"; then
        log_success "NAT rules configured"
    else
        log_warning "NAT rules not found"
    fi

    log_success "Network verification completed"
}

################################################################################
# Alternative: Direct Configuration (if running on Proxmox host)
################################################################################

configure_network_direct() {
    log_info "Configuring network directly on Proxmox host..."

    # Check if we're running on the Proxmox host
    if [[ ! -f "/etc/pve/nodes/${PROXMOX_NODE}/config" ]]; then
        log_error "Not running on Proxmox host. Use SSH method instead."
        return 1
    fi

    # Create bridge if it doesn't exist
    if ! ip link show "${BRIDGE_NAME}" &> /dev/null; then
        log_info "Creating bridge ${BRIDGE_NAME}..."

        # Add to network configuration
        cat >> /etc/network/interfaces << EOF

# GOAD Lab Network - VLAN ${VLAN_ID}
auto ${BRIDGE_NAME}
iface ${BRIDGE_NAME} inet static
    address ${NETWORK_GATEWAY}/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids ${VLAN_ID}
EOF

        # Bring up interface
        ifup "${BRIDGE_NAME}"
    else
        log_info "Bridge ${BRIDGE_NAME} already exists"
    fi

    # Configure NAT
    if [[ "${ENABLE_NAT}" == "true" ]]; then
        # Enable IP forwarding
        echo 1 > /proc/sys/net/ipv4/ip_forward
        sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

        # Add iptables rules
        if ! iptables -t nat -C POSTROUTING -s ${NETWORK_SUBNET} -o ${INTERNET_INTERFACE} -j MASQUERADE &> /dev/null; then
            iptables -t nat -A POSTROUTING -s ${NETWORK_SUBNET} -o ${INTERNET_INTERFACE} -j MASQUERADE
            iptables -A FORWARD -i ${BRIDGE_NAME} -o ${INTERNET_INTERFACE} -j ACCEPT
            iptables -A FORWARD -i ${INTERNET_INTERFACE} -o ${BRIDGE_NAME} -m state --state RELATED,ESTABLISHED -j ACCEPT

            # Save rules
            if command -v iptables-persistent &> /dev/null; then
                iptables-save > /etc/iptables/rules.v4
            else
                DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
                iptables-save > /etc/iptables/rules.v4
            fi
        fi
    fi

    log_success "Direct network configuration completed"
}

################################################################################
# Main Function
################################################################################

main() {
    log_info "Starting network configuration for GOAD lab..."

    # Determine if we're on the Proxmox host or need to use SSH
    if [[ -f "/etc/pve/nodes/${PROXMOX_NODE}/config" ]] || hostname | grep -q "${PROXMOX_NODE}"; then
        log_info "Running directly on Proxmox host"
        configure_network_direct
    else
        log_info "Configuring via SSH/API"
        configure_network_on_proxmox
        configure_nat
    fi

    # Verify configuration
    verify_network

    log_success "Network setup completed successfully"
    log_info "Bridge: ${BRIDGE_NAME}"
    log_info "VLAN: ${VLAN_ID}"
    log_info "Subnet: ${NETWORK_SUBNET}"
    log_info "Gateway: ${NETWORK_GATEWAY}"
}

main "$@"
