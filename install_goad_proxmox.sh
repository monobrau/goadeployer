#!/bin/bash

################################################################################
# GOAD Proxmox Installer - Main Installation Script
#
# This script automates the installation and configuration of Game Of Active
# Directory (GOAD) on Proxmox VE 9.1
#
# Author: GOAD Proxmox Installer
# Version: 1.0.0
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
CONFIG_FILE="${SCRIPT_DIR}/goad_config.conf"
GOAD_DIR="${SCRIPT_DIR}/GOAD"

# Log file with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/goad_install_${TIMESTAMP}.log"

################################################################################
# Logging Functions
################################################################################

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@" | tee -a "${LOG_FILE}"
}

log_step() {
    echo -e "${MAGENTA}[STEP]${NC} $@" | tee -a "${LOG_FILE}"
}

print_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     GOAD Proxmox Installer v1.0.0                            ║
║     Game Of Active Directory - Proxmox VE 9.1                ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

progress_bar() {
    local current=$1
    local total=$2
    local description=$3
    local percentage=$((current * 100 / total))
    local completed=$((percentage / 2))
    local remaining=$((50 - completed))

    printf "\r${CYAN}Progress:${NC} ["
    printf "%${completed}s" | tr ' ' '='
    printf "%${remaining}s" | tr ' ' ' '
    printf "] %3d%% - %s" "$percentage" "$description"
}

################################################################################
# Error Handling
################################################################################

cleanup_on_error() {
    log_error "Installation failed! Check log file: ${LOG_FILE}"
    log_info "To clean up partial installation, run: ./scripts/cleanup_goad.sh"
    exit 1
}

trap cleanup_on_error ERR

################################################################################
# Configuration Loading
################################################################################

load_config() {
    log_step "Loading configuration from ${CONFIG_FILE}"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_info "Please copy goad_config.conf.example to goad_config.conf and configure it"
        exit 1
    fi

    # Source the configuration file
    source "${CONFIG_FILE}"

    # Validate required variables
    local required_vars=(
        "PROXMOX_HOST"
        "PROXMOX_NODE"
        "PROXMOX_API_USER"
        "PROXMOX_API_TOKEN_NAME"
        "PROXMOX_API_TOKEN_SECRET"
        "PROXMOX_STORAGE"
        "VLAN_ID"
        "BRIDGE_NAME"
        "NETWORK_SUBNET"
        "NETWORK_GATEWAY"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required configuration variable ${var} is not set"
            exit 1
        fi
    done

    log_success "Configuration loaded successfully"
}

################################################################################
# Prerequisites Check
################################################################################

check_prerequisites() {
    log_step "Checking prerequisites..."
    local missing_deps=()

    # Check for required commands
    local required_commands=(
        "ansible"
        "ansible-playbook"
        "git"
        "curl"
        "jq"
        "sshpass"
        "python3"
        "pip3"
    )

    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            missing_deps+=("${cmd}")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warning "Missing dependencies: ${missing_deps[*]}"
        log_info "Installing missing dependencies..."
        install_dependencies "${missing_deps[@]}"
    else
        log_success "All required commands are available"
    fi

    # Check Python requirements
    check_python_requirements

    # Check connectivity to Proxmox
    check_proxmox_connectivity

    # Check available resources
    check_proxmox_resources

    log_success "Prerequisites check completed"
}

install_dependencies() {
    local deps=("$@")
    log_info "Installing: ${deps[*]}"

    # Detect package manager
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y ansible git curl jq sshpass python3 python3-pip
    elif command -v dnf &> /dev/null; then
        dnf install -y ansible git curl jq sshpass python3 python3-pip
    elif command -v yum &> /dev/null; then
        yum install -y ansible git curl jq sshpass python3 python3-pip
    else
        log_error "Could not detect package manager. Please install dependencies manually."
        exit 1
    fi

    log_success "Dependencies installed"
}

check_python_requirements() {
    log_info "Checking Python requirements..."

    # Check if packages are already installed
    local missing_packages=()
    
    if ! python3 -c "import ansible" &> /dev/null; then
        missing_packages+=("ansible")
    fi
    if ! python3 -c "import proxmoxer" &> /dev/null; then
        missing_packages+=("proxmoxer")
    fi
    if ! python3 -c "import requests" &> /dev/null; then
        missing_packages+=("requests")
    fi
    if ! python3 -c "import winrm" &> /dev/null; then
        missing_packages+=("pywinrm")
    fi
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_success "All Python requirements already installed"
        return 0
    fi
    
    log_info "Installing missing Python packages: ${missing_packages[*]}"
    
    # Try installing via apt first (for packages available in Debian repos)
    if command -v apt-get &> /dev/null; then
        if apt-get install -y python3-ansible python3-requests &> /dev/null 2>&1; then
            log_info "Installed ansible and requests via apt"
            missing_packages=($(echo "${missing_packages[@]}" | tr ' ' '\n' | grep -v "ansible\|requests"))
        fi
    fi
    
    # Install remaining packages with pip (use --break-system-packages for Debian)
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_info "Installing via pip: ${missing_packages[*]}"
        
        # Check if we need --break-system-packages flag
        if python3 -m pip --version 2>&1 | grep -q "externally-managed"; then
            log_warning "Using --break-system-packages flag (Debian externally-managed environment)"
            pip3 install --break-system-packages --upgrade pip &> /dev/null || true
            pip3 install --break-system-packages "${missing_packages[@]}" || {
                log_error "Failed to install Python packages"
                log_info "You may need to install manually:"
                log_info "  pip3 install --break-system-packages ${missing_packages[*]}"
                return 1
            }
        else
            pip3 install --upgrade pip &> /dev/null || true
            pip3 install "${missing_packages[@]}" || {
                log_error "Failed to install Python packages"
                return 1
            }
        fi
    fi

    log_success "Python requirements satisfied"
}

check_proxmox_connectivity() {
    log_info "Checking Proxmox API connectivity..."

    local api_url="https://${PROXMOX_HOST}:8006/api2/json/version"
    local auth_header="Authorization: PVEAPIToken=${PROXMOX_API_USER}=${PROXMOX_API_TOKEN_SECRET}"

    if curl -sk -H "${auth_header}" "${api_url}" &> /dev/null; then
        log_success "Successfully connected to Proxmox API"
    else
        log_error "Failed to connect to Proxmox API at ${PROXMOX_HOST}"
        log_error "Please check your Proxmox host, API token, and network connectivity"
        exit 1
    fi
}

check_proxmox_resources() {
    log_info "Checking Proxmox resources..."

    local api_url="https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/status"
    local auth_header="Authorization: PVEAPIToken=${PROXMOX_API_USER}=${PROXMOX_API_TOKEN_SECRET}"

    local response=$(curl -sk -H "${auth_header}" "${api_url}")
    local total_mem=$(echo "${response}" | jq -r '.data.memory.total // 0')
    local used_mem=$(echo "${response}" | jq -r '.data.memory.used // 0')
    local total_mem_gb=$((total_mem / 1024 / 1024 / 1024))
    local available_mem_gb=$(((total_mem - used_mem) / 1024 / 1024 / 1024))

    log_info "Total Memory: ${total_mem_gb}GB, Available: ${available_mem_gb}GB"

    # GOAD requires approximately 38GB RAM for 5 VMs
    local required_mem=38
    if [[ ${available_mem_gb} -lt ${required_mem} ]]; then
        log_warning "Available memory (${available_mem_gb}GB) is less than recommended (${required_mem}GB)"
        log_warning "Installation may fail or VMs may not perform well"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Sufficient resources available"
    fi
}

################################################################################
# Network Setup
################################################################################

setup_network() {
    log_step "Setting up network configuration..."

    if [[ -f "${SCRIPTS_DIR}/setup_network.sh" ]]; then
        bash "${SCRIPTS_DIR}/setup_network.sh"
    else
        log_error "Network setup script not found: ${SCRIPTS_DIR}/setup_network.sh"
        exit 1
    fi

    log_success "Network configuration completed"
}

################################################################################
# GOAD Repository Setup
################################################################################

download_goad() {
    log_step "Downloading GOAD repository..."

    if [[ -d "${GOAD_DIR}" ]]; then
        log_warning "GOAD directory already exists at ${GOAD_DIR}"
        log_info "Updating existing repository..."
        cd "${GOAD_DIR}"
        git pull
    else
        log_info "Cloning GOAD repository..."
        git clone https://github.com/Orange-Cyberdefense/GOAD.git "${GOAD_DIR}"
    fi

    cd "${GOAD_DIR}"
    log_info "Current GOAD version: $(git describe --tags --always)"

    log_success "GOAD repository ready"
}

install_goad_dependencies() {
    log_step "Installing GOAD dependencies..."

    cd "${GOAD_DIR}"

    # Install Ansible collections and requirements
    if [[ -f "ansible/requirements.yml" ]]; then
        log_info "Installing Ansible collections..."
        ansible-galaxy collection install -r ansible/requirements.yml
    fi

    # Install Python requirements if exists
    if [[ -f "requirements.txt" ]]; then
        log_info "Installing Python requirements..."
        # Check if we need --break-system-packages flag
        if python3 -m pip --version 2>&1 | grep -q "externally-managed"; then
            pip3 install --break-system-packages -r requirements.txt
        else
            pip3 install -r requirements.txt
        fi
    fi

    log_success "GOAD dependencies installed"
}

################################################################################
# VM Provisioning
################################################################################

provision_vms() {
    log_step "Provisioning VMs on Proxmox..."

    if [[ -f "${SCRIPTS_DIR}/provision_vms.sh" ]]; then
        # Packer is now the default, but allow override with --manual flag
        bash "${SCRIPTS_DIR}/provision_vms.sh" "${@}"
    else
        log_error "VM provisioning script not found: ${SCRIPTS_DIR}/provision_vms.sh"
        exit 1
    fi

    log_success "VM provisioning completed"
}

################################################################################
# GOAD Deployment
################################################################################

deploy_goad() {
    log_step "Deploying GOAD with Ansible..."

    cd "${GOAD_DIR}/ansible"

    # Create inventory for Proxmox
    log_info "Configuring Ansible inventory..."
    create_ansible_inventory

    # Run GOAD provisioning playbooks
    log_info "Running GOAD provisioning playbooks (this may take 1-2 hours)..."
    log_warning "Please be patient, this is a long process..."

    # Run the GOAD provisioning
    ANSIBLE_COMMAND="ansible-playbook -i ../ad/GOAD/data/inventory main.yml"

    log_info "Executing: ${ANSIBLE_COMMAND}"

    if ${ANSIBLE_COMMAND} 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "GOAD deployment completed successfully"
    else
        log_error "GOAD deployment failed. Check the log file for details."
        exit 1
    fi
}

create_ansible_inventory() {
    log_info "Creating Ansible inventory configuration..."

    # This will be handled by the provision_vms.sh script
    # which will create the appropriate inventory based on the VMs created

    log_success "Ansible inventory configured"
}

################################################################################
# Post-Installation
################################################################################

post_install() {
    log_step "Running post-installation tasks..."

    # Display VM information
    display_vm_info

    # Create connection guide
    create_connection_guide

    log_success "Post-installation tasks completed"
}

display_vm_info() {
    log_info "GOAD Lab VMs:"
    cat << EOF | tee -a "${LOG_FILE}"

╔════════════════════════════════════════════════════════════════╗
║                   GOAD Lab VM Information                      ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  Domain: sevenkingdoms.local                                   ║
║    - DC01  (192.168.50.10) - Domain Controller                ║
║    - DC02  (192.168.50.11) - Domain Controller (north.*)      ║
║    - SRV02 (192.168.50.22) - Server                           ║
║                                                                ║
║  Domain: essos.local                                           ║
║    - DC03  (192.168.50.12) - Domain Controller                ║
║    - SRV03 (192.168.50.23) - Server                           ║
║                                                                ║
║  Network: 192.168.50.0/24 (VLAN 50)                           ║
║  Gateway: 192.168.50.1                                         ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

EOF
}

create_connection_guide() {
    local guide_file="${SCRIPT_DIR}/CONNECTION_GUIDE.md"

    cat > "${guide_file}" << 'EOF'
# GOAD Lab Connection Guide

## Network Access

Your GOAD lab is running on an isolated network (VLAN 50) with the subnet 192.168.50.0/24.

### VPN Access (WireGuard)

To access the lab externally, you'll need to configure WireGuard VPN on your Proxmox host.

1. Install WireGuard on Proxmox:
   ```bash
   apt update
   apt install wireguard
   ```

2. Generate WireGuard keys:
   ```bash
   wg genkey | tee privatekey | wg pubkey > publickey
   ```

3. Create WireGuard configuration at `/etc/wireguard/wg0.conf`:
   ```ini
   [Interface]
   Address = 10.0.0.1/24
   ListenPort = 51820
   PrivateKey = <your-private-key>

   # Forward traffic to GOAD network
   PostUp = iptables -A FORWARD -i wg0 -o vmbr50 -j ACCEPT
   PostUp = iptables -A FORWARD -i vmbr50 -o wg0 -j ACCEPT
   PostUp = iptables -t nat -A POSTROUTING -o vmbr50 -j MASQUERADE
   PostDown = iptables -D FORWARD -i wg0 -o vmbr50 -j ACCEPT
   PostDown = iptables -D FORWARD -i vmbr50 -o wg0 -j ACCEPT
   PostDown = iptables -t nat -D POSTROUTING -o vmbr50 -j MASQUERADE

   [Peer]
   # Client configuration
   PublicKey = <client-public-key>
   AllowedIPs = 10.0.0.2/32
   ```

4. Enable and start WireGuard:
   ```bash
   systemctl enable wg-quick@wg0
   systemctl start wg-quick@wg0
   ```

5. Configure client with route to GOAD network:
   ```ini
   [Interface]
   Address = 10.0.0.2/24
   PrivateKey = <client-private-key>

   [Peer]
   PublicKey = <server-public-key>
   Endpoint = <your-proxmox-ip>:51820
   AllowedIPs = 10.0.0.0/24, 192.168.50.0/24
   PersistentKeepalive = 25
   ```

## VM Credentials

Default credentials for the GOAD lab:

### Domain Accounts

- **Domain Admin**: `sevenkingdoms.local\administrator` / `Password123!`
- **Domain Admin**: `essos.local\administrator` / `Password123!`

### Local Accounts

Check the GOAD documentation for specific user accounts created during provisioning.

## Connecting to VMs

### RDP Access

```bash
xfreerdp /v:192.168.50.10 /u:administrator@sevenkingdoms.local /p:Password123! /cert-ignore
```

### WinRM Access (PowerShell Remoting)

```bash
evil-winrm -i 192.168.50.10 -u administrator -p 'Password123!' -d sevenkingdoms.local
```

## Lab Information

- **DC01** (192.168.50.10): Primary Domain Controller - sevenkingdoms.local
- **DC02** (192.168.50.11): Domain Controller - north.sevenkingdoms.local
- **DC03** (192.168.50.12): Domain Controller - essos.local
- **SRV02** (192.168.50.22): Server - sevenkingdoms.local
- **SRV03** (192.168.50.23): Server - essos.local

## Troubleshooting

If you cannot reach the VMs:

1. Verify WireGuard is running: `systemctl status wg-quick@wg0`
2. Check routing: `ip route` should show route to 192.168.50.0/24
3. Verify firewall rules: `iptables -L -v -n`
4. Test connectivity: `ping 192.168.50.10`

## Security Warning

This is a vulnerable-by-design lab environment. Do NOT expose it to the public internet.
Only access via secure VPN connection.

EOF

    log_success "Connection guide created: ${guide_file}"
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    # Create log directory if it doesn't exist
    mkdir -p "${LOG_DIR}"

    # Print banner
    print_banner

    log_info "Installation started at $(date)"
    log_info "Log file: ${LOG_FILE}"
    echo

    # Load configuration
    load_config

    # Check prerequisites
    check_prerequisites

    # Setup network
    setup_network

    # Download GOAD
    download_goad

    # Install GOAD dependencies
    install_goad_dependencies

    # Provision VMs
    provision_vms

    # Deploy GOAD
    deploy_goad

    # Post-installation
    post_install

    # Final message
    echo
    log_success "════════════════════════════════════════════════════════════════"
    log_success "GOAD Installation Completed Successfully!"
    log_success "════════════════════════════════════════════════════════════════"
    log_info "Installation log: ${LOG_FILE}"
    log_info "Connection guide: ${SCRIPT_DIR}/CONNECTION_GUIDE.md"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Configure WireGuard VPN for external access"
    log_info "  2. Review the connection guide for VM access details"
    log_info "  3. Start your penetration testing practice!"
    log_info ""
    log_warning "Remember: This is a vulnerable lab. Keep it isolated!"
    echo
}

# Run main function
main "$@"
