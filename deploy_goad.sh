#!/bin/bash

################################################################################
# GOAD Deployment Script - Resume After Windows Installation
#
# This script resumes GOAD deployment after Windows has been installed on VMs.
# It skips VM creation and goes straight to GOAD Ansible deployment.
#
# Usage: ./deploy_goad.sh
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
LOG_FILE="${LOG_DIR}/goad_deploy_${TIMESTAMP}.log"

################################################################################
# Logging Functions
################################################################################

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
║     GOAD Deployment - Resume After Windows Installation      ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

print_prerequisites() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════╗
║                    PREREQUISITES CHECK                        ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  Before running this script, ensure:                          ║
║                                                                ║
║  ✅ Windows Server is FULLY INSTALLED on all 5 VMs            ║
║  ✅ Static IP addresses are configured                        ║
║  ✅ WinRM is enabled and accessible                            ║
║  ✅ Firewall allows port 5985                                  ║
║  ✅ Administrator password is set correctly                     ║
║                                                                ║
║  If Windows is NOT installed yet, run:                         ║
║    ./setup_windows.sh                                          ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

EOF
}

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
        "DC01_IP"
        "DC02_IP"
        "DC03_IP"
        "SRV02_IP"
        "SRV03_IP"
        "WINDOWS_ADMIN_PASSWORD"
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

    # Check for required commands
    local required_commands=(
        "ansible"
        "ansible-playbook"
        "python3"
    )

    local missing_deps=()
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            missing_deps+=("${cmd}")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_deps[*]}"
        log_info "Please install: apt install ansible python3 python3-pip"
        exit 1
    fi

    # Check if GOAD directory exists
    if [[ ! -d "${GOAD_DIR}" ]]; then
        log_warning "GOAD directory not found at ${GOAD_DIR}"
        log_info "Downloading GOAD repository..."
        download_goad
    else
        log_success "GOAD repository found"
    fi

    # Check Python requirements
    log_info "Checking Python requirements..."
    
    # Check if we need --break-system-packages flag
    if python3 -m pip --version 2>&1 | grep -q "externally-managed"; then
        pip3 install --quiet --break-system-packages --upgrade pip proxmoxer requests pywinrm 2>&1 | tee -a "${LOG_FILE}" || true
    else
        pip3 install --quiet --upgrade pip proxmoxer requests pywinrm 2>&1 | tee -a "${LOG_FILE}" || true
    fi

    log_success "Prerequisites check completed"
}

download_goad() {
    log_info "Cloning GOAD repository..."
    git clone https://github.com/Orange-Cyberdefense/GOAD.git "${GOAD_DIR}" 2>&1 | tee -a "${LOG_FILE}"
    
    cd "${GOAD_DIR}"
    log_info "Current GOAD version: $(git describe --tags --always 2>/dev/null || echo 'unknown')"
    
    log_success "GOAD repository ready"
}

install_goad_dependencies() {
    log_step "Installing GOAD dependencies..."

    cd "${GOAD_DIR}"

    # Install Ansible collections
    if [[ -f "ansible/requirements.yml" ]]; then
        log_info "Installing Ansible collections..."
        ansible-galaxy collection install -r ansible/requirements.yml 2>&1 | tee -a "${LOG_FILE}"
    fi

    # Install Python requirements if exists
    if [[ -f "requirements.txt" ]]; then
        log_info "Installing Python requirements..."
        # Check if we need --break-system-packages flag
        if python3 -m pip --version 2>&1 | grep -q "externally-managed"; then
            pip3 install --break-system-packages -r requirements.txt 2>&1 | tee -a "${LOG_FILE}"
        else
            pip3 install -r requirements.txt 2>&1 | tee -a "${LOG_FILE}"
        fi
    fi

    log_success "GOAD dependencies installed"
}

################################################################################
# Ansible Inventory Generation
################################################################################

generate_ansible_inventory() {
    log_step "Generating Ansible inventory for GOAD..."

    local inventory_dir="${GOAD_DIR}/ad/GOAD/data"
    local inventory_file="${inventory_dir}/inventory"

    # Create inventory directory if it doesn't exist
    mkdir -p "${inventory_dir}"

    # Use default password if not set
    local admin_password="${WINDOWS_ADMIN_PASSWORD:-Password123!}"

    cat > "${inventory_file}" << EOF
# GOAD Ansible Inventory for Proxmox
# Generated by GOAD Proxmox Installer

[default]
; Note: ansible is executed from wsl2 so ip are mandatory
dc01 ansible_host=${DC01_IP} dns_domain=dc01 dict_key=dc01
dc02 ansible_host=${DC02_IP} dns_domain=dc01 dict_key=dc02
dc03 ansible_host=${DC03_IP} dns_domain=dc02 dict_key=dc03
srv02 ansible_host=${SRV02_IP} dns_domain=dc01 dict_key=srv02
srv03 ansible_host=${SRV03_IP} dns_domain=dc02 dict_key=srv03

[domain]
dc01
dc02
dc03

[parent_dc]
dc01
dc03

[child_dc]
dc02

[dc]
dc01
dc02
dc03

[server]
srv02
srv03

[workstation]

[trust]

[laps_dc]
dc01
dc02
dc03

[laps_server]
srv02
srv03

[laps_workstation]

[adcs]
srv02

[adcs_customtemplates]

[iis]
srv02

[mssql]
srv02

[mssql_ssms]

[mssql_reporting]

[webdav]

[defender_on]

[defender_off]

[extensions]

[no_update]

[update]

[all:vars]
; domain_name : folder inside ad/
domain_name=GOAD

force_dns_server=no
dns_server=8.8.8.8

; adapter created by vagrant and virtualbox (comment if you use vmware or other)
; network_adapter=Ethernet

; winrm connection (windows)
ansible_user=Administrator
ansible_password=${admin_password}
ansible_connection=winrm
ansible_winrm_server_cert_validation=ignore
ansible_winrm_operation_timeout_sec=400
ansible_winrm_read_timeout_sec=500

; proxy settings (the lab need internet for some install, if you are behind a proxy you should set the proxy here)
enable_http_proxy=no
ad_http_proxy=
ad_https_proxy=
EOF

    log_success "Ansible inventory generated: ${inventory_file}"
}

################################################################################
# VM Connectivity Check
################################################################################

check_vm_connectivity() {
    log_step "Checking VM connectivity via WinRM..."

    local vms=(
        "${DC01_IP}:DC01"
        "${DC02_IP}:DC02"
        "${DC03_IP}:DC03"
        "${SRV02_IP}:SRV02"
        "${SRV03_IP}:SRV03"
    )

    local failed_vms=()
    local admin_password="${WINDOWS_ADMIN_PASSWORD:-Password123!}"

    for vm_entry in "${vms[@]}"; do
        IFS=':' read -r ip name <<< "${vm_entry}"
        log_info "Testing ${name} (${ip})..."

        # Test WinRM connectivity
        if ansible all -i "${ip}," -m win_ping -e "ansible_user=Administrator ansible_password=${admin_password} ansible_connection=winrm ansible_winrm_server_cert_validation=ignore" &> /dev/null; then
            log_success "${name} is reachable via WinRM"
        else
            log_error "${name} (${ip}) is NOT reachable via WinRM"
            failed_vms+=("${name} (${ip})")
        fi
    done

    if [[ ${#failed_vms[@]} -gt 0 ]]; then
        log_error "The following VMs are not reachable:"
        for vm in "${failed_vms[@]}"; do
            log_error "  - ${vm}"
        done
        echo
        log_info "Please ensure:"
        log_info "  1. Windows is fully installed on all VMs"
        log_info "  2. Static IPs are configured correctly"
        log_info "  3. WinRM is enabled on all VMs"
        log_info "  4. Firewall allows WinRM (port 5985)"
        echo
        log_info "To enable WinRM on Windows VMs, run these PowerShell commands:"
        log_info "  winrm quickconfig -force"
        log_info "  Set-Item WSMan:\\localhost\\Service\\Auth\\Basic -Value \$true"
        log_info "  Set-Item WSMan:\\localhost\\Service\\AllowUnencrypted -Value \$true"
        log_info "  netsh advfirewall firewall add rule name=\"WinRM HTTP\" protocol=TCP dir=in localport=5985 action=allow"
        echo
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "All VMs are reachable via WinRM"
    fi
}

################################################################################
# GOAD Deployment
################################################################################

deploy_goad() {
    log_step "Deploying GOAD with Ansible..."

    cd "${GOAD_DIR}/ansible"

    # Verify inventory exists
    local inventory_file="../ad/GOAD/data/inventory"
    if [[ ! -f "${inventory_file}" ]]; then
        log_error "Ansible inventory not found: ${inventory_file}"
        log_info "Generating inventory..."
        generate_ansible_inventory
    fi

    log_info "Running GOAD provisioning playbooks..."
    log_warning "This will take 1-2 hours. Please be patient..."
    log_info "You can monitor progress in the log file: ${LOG_FILE}"
    echo

    # Run the GOAD provisioning
    ANSIBLE_COMMAND="ansible-playbook -i ../ad/GOAD/data/inventory main.yml"

    log_info "Executing: ${ANSIBLE_COMMAND}"
    echo

    if ${ANSIBLE_COMMAND} 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "GOAD deployment completed successfully!"
    else
        log_error "GOAD deployment failed. Check the log file for details: ${LOG_FILE}"
        exit 1
    fi
}

################################################################################
# Post-Deployment
################################################################################

post_deploy() {
    log_step "Running post-deployment tasks..."

    cat << EOF | tee -a "${LOG_FILE}"

╔════════════════════════════════════════════════════════════════╗
║                   GOAD Deployment Complete!                    ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  Your GOAD lab is now ready for penetration testing!          ║
║                                                                ║
║  Domain: sevenkingdoms.local                                   ║
║    - DC01  (${DC01_IP}) - Domain Controller                ║
║    - DC02  (${DC02_IP}) - Domain Controller (north.*)      ║
║    - SRV02 (${SRV02_IP}) - Server                           ║
║                                                                ║
║  Domain: essos.local                                           ║
║    - DC03  (${DC03_IP}) - Domain Controller                ║
║    - SRV03 (${SRV03_IP}) - Server                           ║
║                                                                ║
║  Default Credentials:                                          ║
║    Administrator / Password123!                                ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

EOF

    log_info "You can now connect to your VMs:"
    log_info "  RDP: xfreerdp /v:${DC01_IP} /u:administrator@sevenkingdoms.local /p:Password123!"
    log_info "  WinRM: evil-winrm -i ${DC01_IP} -u administrator -p 'Password123!' -d sevenkingdoms.local"
    echo
}

################################################################################
# Main Function
################################################################################

main() {
    # Create log directory if it doesn't exist
    mkdir -p "${LOG_DIR}"

    # Print banner
    print_banner
    
    # Print prerequisites
    print_prerequisites
    
    read -p "Have you completed Windows installation and WinRM setup on all VMs? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Please complete Windows installation first!"
        log_info "Run './setup_windows.sh' for detailed instructions"
        exit 1
    fi

    log_info "GOAD deployment started at $(date)"
    log_info "Log file: ${LOG_FILE}"
    echo

    # Load configuration
    load_config

    # Check prerequisites
    check_prerequisites

    # Install GOAD dependencies
    install_goad_dependencies

    # Generate Ansible inventory
    generate_ansible_inventory

    # Check VM connectivity
    check_vm_connectivity

    # Deploy GOAD
    deploy_goad

    # Post-deployment
    post_deploy

    # Final message
    echo
    log_success "════════════════════════════════════════════════════════════════"
    log_success "GOAD Deployment Completed Successfully!"
    log_success "════════════════════════════════════════════════════════════════"
    log_info "Installation log: ${LOG_FILE}"
    log_info ""
    log_warning "Remember: This is a vulnerable lab. Keep it isolated!"
    echo
}

# Run main function
main "$@"

