#!/bin/bash

################################################################################
# Windows Installation Guide Script
#
# This script provides step-by-step instructions for installing Windows
# and configuring WinRM on all GOAD VMs before running deploy_goad.sh
#
# Usage: ./setup_windows.sh
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/goad_config.conf"

# Load config if exists
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
fi

# Default values
DC01_IP="${DC01_IP:-192.168.50.10}"
DC02_IP="${DC02_IP:-192.168.50.11}"
DC03_IP="${DC02_IP:-192.168.50.12}"
SRV02_IP="${SRV02_IP:-192.168.50.22}"
SRV03_IP="${SRV03_IP:-192.168.50.23}"
ADMIN_PASSWORD="${WINDOWS_ADMIN_PASSWORD:-Password123!}"

print_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     Windows Installation Guide for GOAD Lab                  ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

print_vm_info() {
    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║                    VM Configuration Summary                     ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  DC01  - ${DC01_IP}  - Windows Server 2019                    ║
║  DC02  - ${DC02_IP}  - Windows Server 2019                    ║
║  DC03  - ${DC03_IP}  - Windows Server 2016                    ║
║  SRV02 - ${SRV02_IP}  - Windows Server 2019                    ║
║  SRV03 - ${SRV03_IP}  - Windows Server 2016                    ║
║                                                                ║
║  Gateway: 192.168.50.1                                         ║
║  DNS: ${DC01_IP} (DC01)                                        ║
║  Password: ${ADMIN_PASSWORD}                                    ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

EOF
}

print_instructions() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════╗
║           Step-by-Step Windows Installation Guide              ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  IMPORTANT: Complete these steps for EACH VM                  ║
║                                                                ║
║  STEP 1: Install Windows Server                               ║
║  ──────────────────────────────────────────────────────────── ║
║  1. Open VM console in Proxmox Web UI                         ║
║  2. Boot from Windows Server ISO                               ║
║  3. Select "Windows Server 20XX Standard Evaluation"          ║
║     (Desktop Experience version - NOT Core!)                   ║
║  4. When prompted for disk:                                    ║
║     a. Click "Load driver"                                     ║
║     b. Browse to VirtIO ISO (usually E: drive)                ║
║     c. Navigate to: E:\vioscsi\w10\amd64\                     ║
║     d. Select "vioscsi.inf" and click OK                      ║
║  5. Complete Windows installation                              ║
║  6. Set Administrator password: Password123!                    ║
║                                                                ║
║  STEP 2: Configure Static IP Address                          ║
║  ──────────────────────────────────────────────────────────── ║
║  Open PowerShell as Administrator and run:                    ║
║                                                                ║
EOF

    echo -e "  ${CYAN}# For DC01 (192.168.50.10):${NC}"
    cat << 'DC01_SCRIPT'
  New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.10 -PrefixLength 24 -DefaultGateway 192.168.50.1
  Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.10
DC01_SCRIPT

    echo -e "\n  ${CYAN}# For DC02 (192.168.50.11):${NC}"
    cat << 'DC02_SCRIPT'
  New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.11 -PrefixLength 24 -DefaultGateway 192.168.50.1
  Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.10
DC02_SCRIPT

    echo -e "\n  ${CYAN}# For DC03 (192.168.50.12):${NC}"
    cat << 'DC03_SCRIPT'
  New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.12 -PrefixLength 24 -DefaultGateway 192.168.50.1
  Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.12
DC03_SCRIPT

    echo -e "\n  ${CYAN}# For SRV02 (192.168.50.22):${NC}"
    cat << 'SRV02_SCRIPT'
  New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.22 -PrefixLength 24 -DefaultGateway 192.168.50.1
  Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.10
SRV02_SCRIPT

    echo -e "\n  ${CYAN}# For SRV03 (192.168.50.23):${NC}"
    cat << 'SRV03_SCRIPT'
  New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.23 -PrefixLength 24 -DefaultGateway 192.168.50.1
  Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.12
SRV03_SCRIPT

    cat << 'EOF'

║                                                                ║
║  STEP 3: Enable WinRM (Required for Ansible)                   ║
║  ──────────────────────────────────────────────────────────── ║
║  Run these commands in PowerShell as Administrator:            ║
║                                                                ║
EOF

    cat << WINRM_SCRIPT
  winrm quickconfig -force
  Set-Item WSMan:\localhost\Service\Auth\Basic -Value \$true
  Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value \$true
  netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow
WINRM_SCRIPT

    cat << 'EOF'

║                                                                ║
║  STEP 4: Verify Connectivity                                  ║
║  ──────────────────────────────────────────────────────────── ║
║  From your Proxmox host or control machine, test:              ║
║                                                                ║
EOF

    echo -e "  ${CYAN}ping ${DC01_IP}${NC}"
    echo -e "  ${CYAN}nc -zv ${DC01_IP} 5985${NC}  # Test WinRM port"
    cat << 'EOF'

║                                                                ║
║  STEP 5: Run GOAD Deployment                                  ║
║  ──────────────────────────────────────────────────────────── ║
║  Once ALL 5 VMs are configured, run:                           ║
║                                                                ║
EOF

    echo -e "  ${GREEN}./deploy_goad.sh${NC}"
    cat << 'EOF'

║                                                                ║
╚════════════════════════════════════════════════════════════════╝

EOF
}

print_quick_reference() {
    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║                    Quick Reference Card                        ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  Copy this PowerShell script and run on EACH VM:              ║
║                                                                ║
EOF

    cat << 'POWERSHELL_SCRIPT'
# Configure Network and WinRM (Run as Administrator)
# Replace IP_ADDRESS with the correct IP for each VM

$IPAddress = "IP_ADDRESS"  # Change for each VM
$Gateway = "192.168.50.1"
$DNS = "192.168.50.10"     # Use DC01 IP for DC02/SRV02, DC03 IP for SRV03

# Configure static IP
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress $IPAddress -PrefixLength 24 -DefaultGateway $Gateway
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses $DNS

# Enable WinRM
winrm quickconfig -force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow

Write-Host "Configuration complete! IP: $IPAddress" -ForegroundColor Green
POWERSHELL_SCRIPT

    cat << EOF

║                                                                ║
║  VM-Specific IPs:                                             ║
║    DC01:  192.168.50.10 (DNS: 192.168.50.10)                  ║
║    DC02:  192.168.50.11 (DNS: 192.168.50.10)                  ║
║    DC03:  192.168.50.12 (DNS: 192.168.50.12)                  ║
║    SRV02: 192.168.50.22 (DNS: 192.168.50.10)                  ║
║    SRV03: 192.168.50.23 (DNS: 192.168.50.12)                  ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

EOF
}

main() {
    print_banner
    print_vm_info
    print_instructions
    print_quick_reference
    
    echo
    echo -e "${YELLOW}Note:${NC} You must complete Windows installation and WinRM configuration"
    echo -e "      on ALL 5 VMs before running ${GREEN}./deploy_goad.sh${NC}"
    echo
    echo -e "${CYAN}Tip:${NC} You can test WinRM connectivity with:"
    echo -e "      ${BLUE}ansible all -i '${DC01_IP},' -m win_ping -e 'ansible_user=Administrator ansible_password=${ADMIN_PASSWORD} ansible_connection=winrm'${NC}"
    echo
}

main "$@"

