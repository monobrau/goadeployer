#!/bin/bash

################################################################################
# GOAD Proxmox Installer - VM Provisioning Script
#
# This script provisions the GOAD VMs on Proxmox:
# - Downloads Windows Server ISOs and VirtIO drivers
# - Creates VM templates
# - Clones VMs from templates
# - Configures network settings
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

pve_api() {
    local method=$1
    local endpoint=$2
    local data=${3:-}

    local url="https://${PROXMOX_HOST}:8006/api2/json${endpoint}"
    local auth_header="Authorization: PVEAPIToken=${PROXMOX_API_USER}=${PROXMOX_API_TOKEN_SECRET}"

    if [[ -n "${data}" ]]; then
        curl -sk -X "${method}" -H "${auth_header}" -H "Content-Type: application/x-www-form-urlencoded" --data "${data}" "${url}"
    else
        curl -sk -X "${method}" -H "${auth_header}" "${url}"
    fi
}

pve_wait_for_task() {
    local upid=$1
    local max_wait=600
    local waited=0

    log_info "Waiting for task to complete: ${upid}"

    while [[ $waited -lt $max_wait ]]; do
        local status=$(pve_api GET "/nodes/${PROXMOX_NODE}/tasks/${upid}/status" | jq -r '.data.status // "running"')

        if [[ "${status}" == "stopped" ]]; then
            local exitstatus=$(pve_api GET "/nodes/${PROXMOX_NODE}/tasks/${upid}/status" | jq -r '.data.exitstatus // "OK"')
            if [[ "${exitstatus}" == "OK" ]]; then
                log_success "Task completed successfully"
                return 0
            else
                log_error "Task failed with status: ${exitstatus}"
                return 1
            fi
        fi

        sleep 5
        waited=$((waited + 5))
    done

    log_error "Task timeout after ${max_wait} seconds"
    return 1
}

################################################################################
# ISO Management
################################################################################

download_iso() {
    local iso_url=$1
    local iso_name=$2
    local storage=${3:-local}

    log_info "Checking if ISO ${iso_name} exists..."

    # Check if ISO already exists
    local iso_exists=$(pve_api GET "/nodes/${PROXMOX_NODE}/storage/${storage}/content" | jq -r ".data[] | select(.volid | contains(\"${iso_name}\")) | .volid")

    if [[ -n "${iso_exists}" ]]; then
        log_success "ISO ${iso_name} already exists"
        return 0
    fi

    log_info "Downloading ISO: ${iso_name}"
    log_warning "This may take a while depending on your internet connection..."

    # Download ISO to Proxmox storage
    # Note: This requires manual intervention or pre-downloaded ISOs
    # For automation, ISOs should be pre-uploaded to Proxmox storage

    log_warning "Please manually upload ${iso_name} to Proxmox storage: ${storage}"
    log_info "You can upload via Proxmox web UI: Datacenter > ${PROXMOX_NODE} > ${storage} > ISO Images > Upload"
    log_info "Or use wget on the Proxmox host:"
    log_info "  cd /var/lib/vz/template/iso"
    log_info "  wget -O ${iso_name} '${iso_url}'"

    read -p "Press Enter when the ISO is uploaded and ready to continue..."
}

prepare_isos() {
    log_info "Preparing Windows ISOs and VirtIO drivers..."

    # For GOAD, we need Windows Server 2016 and 2019 ISOs
    # These must be manually downloaded due to licensing

    log_warning "Windows Server ISOs must be manually obtained from Microsoft"
    log_info "Please download the following ISOs:"
    log_info "  1. Windows Server 2019 Evaluation"
    log_info "  2. Windows Server 2016 Evaluation"
    log_info "  3. VirtIO drivers for Windows"

    log_info "Upload them to Proxmox storage: ${PROXMOX_STORAGE}"

    # VirtIO drivers can be downloaded automatically
    log_info "VirtIO drivers can be downloaded from: ${VIRTIO_ISO_URL}"

    read -p "Have you uploaded the required ISOs? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Please upload ISOs before continuing"
        exit 1
    fi

    log_success "ISOs prepared"
}

################################################################################
# VM Creation
################################################################################

create_vm() {
    local vmid=$1
    local name=$2
    local cores=$3
    local memory=$4
    local disk_size=$5
    local ip=$6
    local os_type=${7:-win2019}

    log_info "Creating VM ${vmid}: ${name}"

    # Check if VM already exists
    local vm_exists=$(pve_api GET "/nodes/${PROXMOX_NODE}/qemu" | jq -r ".data[] | select(.vmid == ${vmid}) | .vmid")

    if [[ -n "${vm_exists}" ]]; then
        log_warning "VM ${vmid} already exists, skipping creation"
        return 0
    fi

    # Determine which ISO to use
    local iso_name
    if [[ "${os_type}" == "win2016" ]]; then
        iso_name="${WIN2016_ISO_NAME}"
    else
        iso_name="${WIN2019_ISO_NAME}"
    fi

    # Create VM
    log_info "Creating VM with ID ${vmid}..."

    local create_data="vmid=${vmid}"
    create_data+="&name=${name}"
    create_data+="&cores=${cores}"
    create_data+="&memory=${memory}"
    create_data+="&net0=virtio,bridge=${BRIDGE_NAME},tag=${VLAN_ID}"
    create_data+="&scsihw=virtio-scsi-pci"
    create_data+="&ostype=win10"
    create_data+="&agent=1"

    local response=$(pve_api POST "/nodes/${PROXMOX_NODE}/qemu" "${create_data}")
    log_success "VM ${vmid} created"

    # Add disk
    log_info "Adding disk to VM ${vmid}..."
    local disk_data="scsi0=${PROXMOX_STORAGE}:${disk_size},format=qcow2"
    pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${disk_data}"

    # Add CD-ROM drives
    log_info "Configuring CD-ROM drives..."
    local cdrom_data="ide0=${PROXMOX_STORAGE}:iso/${iso_name},media=cdrom"
    cdrom_data+="&ide2=${PROXMOX_STORAGE}:iso/${VIRTIO_ISO_NAME},media=cdrom"
    pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${cdrom_data}"

    # Configure boot order
    local boot_data="boot=order=scsi0;ide0;ide2"
    pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${boot_data}"

    # Set CPU type
    local cpu_data="cpu=host"
    pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${cpu_data}"

    # Enable QEMU agent
    local agent_data="agent=1,fstrim_cloned_disks=1"
    pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${agent_data}"

    log_success "VM ${vmid} (${name}) configured successfully"
}

create_all_vms() {
    log_info "Creating all GOAD VMs..."

    # DC01 - sevenkingdoms.local
    create_vm "${DC01_VMID}" "${DC01_NAME}" "${DC01_CORES}" "${DC01_MEMORY}" "${DC01_DISK_SIZE}" "${DC01_IP}" "${DC01_OS_TYPE}"

    # DC02 - north.sevenkingdoms.local
    create_vm "${DC02_VMID}" "${DC02_NAME}" "${DC02_CORES}" "${DC02_MEMORY}" "${DC02_DISK_SIZE}" "${DC02_IP}" "${DC02_OS_TYPE}"

    # DC03 - essos.local
    create_vm "${DC03_VMID}" "${DC03_NAME}" "${DC03_CORES}" "${DC03_MEMORY}" "${DC03_DISK_SIZE}" "${DC03_IP}" "${DC03_OS_TYPE}"

    # SRV02 - sevenkingdoms.local
    create_vm "${SRV02_VMID}" "${SRV02_NAME}" "${SRV02_CORES}" "${SRV02_MEMORY}" "${SRV02_DISK_SIZE}" "${SRV02_IP}" "${SRV02_OS_TYPE}"

    # SRV03 - essos.local
    create_vm "${SRV03_VMID}" "${SRV03_NAME}" "${SRV03_CORES}" "${SRV03_MEMORY}" "${SRV03_DISK_SIZE}" "${SRV03_IP}" "${SRV03_OS_TYPE}"

    log_success "All VMs created successfully"
}

################################################################################
# Ansible Inventory Generation
################################################################################

generate_ansible_inventory() {
    log_info "Generating Ansible inventory for GOAD..."

    local inventory_dir="${SCRIPT_DIR}/GOAD/ad/GOAD/data"
    local inventory_file="${inventory_dir}/inventory"

    # Create inventory directory if it doesn't exist
    mkdir -p "${inventory_dir}"

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

[all:vars]
; domain_name : folder inside ad/
domain_name=GOAD

force_dns_server=no
dns_server=8.8.8.8

; adapter created by vagrant and virtualbox (comment if you use vmware or other)
; network_adapter=Ethernet

; winrm connection (windows)
ansible_user=Administrator
ansible_password=${WINDOWS_ADMIN_PASSWORD}
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
# VM Configuration Helper
################################################################################

configure_vm_networking() {
    log_info "VM networking will be configured during Windows installation"
    log_info "Please ensure the following static IPs are configured:"
    log_info "  DC01:  ${DC01_IP}"
    log_info "  DC02:  ${DC02_IP}"
    log_info "  DC03:  ${DC03_IP}"
    log_info "  SRV02: ${SRV02_IP}"
    log_info "  SRV03: ${SRV03_IP}"
    log_info ""
    log_info "Gateway: ${NETWORK_GATEWAY}"
    log_info "DNS: ${NETWORK_DNS}"
}

################################################################################
# Windows Installation Instructions
################################################################################

display_windows_install_instructions() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════╗
║                  Windows Installation Instructions                       ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  The VMs have been created but Windows is not yet installed.            ║
║  You have two options:                                                   ║
║                                                                          ║
║  OPTION 1: Manual Installation (Recommended for first-time users)       ║
║  ────────────────────────────────────────────────────────────────────   ║
║  1. Access each VM via Proxmox console                                   ║
║  2. Install Windows Server (use Evaluation edition)                      ║
║  3. During installation, load VirtIO drivers from the second CD-ROM      ║
║  4. Configure static IP addresses as shown below                         ║
║  5. Enable WinRM (run: winrm quickconfig -force)                         ║
║  6. Set administrator password to: Password123!                          ║
║                                                                          ║
║  OPTION 2: Use Packer to automate Windows installation                  ║
║  ────────────────────────────────────────────────────────────────────   ║
║  1. Install Packer on your machine                                       ║
║  2. Use the provided Packer templates in the 'packer' directory          ║
║  3. Build the templates: packer build windows-server-2019.json           ║
║  4. Import the built VMs to Proxmox                                      ║
║                                                                          ║
║  Static IP Configuration:                                                ║
║  ────────────────────────────────────────────────────────────────────   ║
EOF

    printf "║  DC01:  %-62s║\n" "${DC01_IP}/24"
    printf "║  DC02:  %-62s║\n" "${DC02_IP}/24"
    printf "║  DC03:  %-62s║\n" "${DC03_IP}/24"
    printf "║  SRV02: %-62s║\n" "${SRV02_IP}/24"
    printf "║  SRV03: %-62s║\n" "${SRV03_IP}/24"
    printf "║  Gateway: %-60s║\n" "${NETWORK_GATEWAY}"
    printf "║  DNS: %-64s║\n" "${NETWORK_DNS}"

    cat << 'EOF'
║                                                                          ║
║  After Windows installation is complete, run:                            ║
║    ./install_goad_proxmox.sh --skip-vm-creation                          ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝

EOF
}

################################################################################
# Packer Template Generation
################################################################################

generate_packer_templates() {
    log_info "Generating Packer templates for automated Windows installation..."

    local packer_dir="${SCRIPT_DIR}/packer"
    mkdir -p "${packer_dir}"

    # Windows Server 2019 Packer template
    cat > "${packer_dir}/windows-server-2019.pkr.hcl" << 'PACKER_EOF'
# Packer template for Windows Server 2019 on Proxmox

variable "proxmox_host" {
  type = string
}

variable "proxmox_node" {
  type = string
}

variable "proxmox_api_user" {
  type = string
}

variable "proxmox_api_token" {
  type = string
}

variable "iso_file" {
  type    = string
  default = "windows-server-2019.iso"
}

variable "virtio_iso_file" {
  type    = string
  default = "virtio-win.iso"
}

source "proxmox-iso" "windows-server-2019" {
  proxmox_url              = "https://${var.proxmox_host}:8006/api2/json"
  username                 = var.proxmox_api_user
  token                    = var.proxmox_api_token
  insecure_skip_tls_verify = true

  node                 = var.proxmox_node
  vm_name              = "windows-server-2019-template"
  template_description = "Windows Server 2019 template for GOAD"

  iso_file         = "local:iso/${var.iso_file}"
  iso_storage_pool = "local"
  unmount_iso      = true

  additional_iso_files {
    device           = "ide3"
    iso_file         = "local:iso/${var.virtio_iso_file}"
    iso_storage_pool = "local"
    unmount_iso      = true
  }

  os       = "win10"
  cores    = 2
  memory   = 4096
  scsi_controller = "virtio-scsi-pci"

  network_adapters {
    model  = "virtio"
    bridge = "vmbr50"
  }

  disks {
    type         = "scsi"
    disk_size    = "60G"
    storage_pool = "local-lvm"
    format       = "qcow2"
  }

  communicator = "winrm"
  winrm_username = "Administrator"
  winrm_password = "Password123!"
  winrm_timeout  = "4h"

  cloud_init              = false
  cloud_init_storage_pool = "local-lvm"
}

build {
  sources = ["source.proxmox-iso.windows-server-2019"]

  provisioner "powershell" {
    scripts = [
      "scripts/enable-winrm.ps1",
      "scripts/install-virtio-drivers.ps1"
    ]
  }
}
PACKER_EOF

    # Create Packer scripts directory
    mkdir -p "${packer_dir}/scripts"

    # Enable WinRM script
    cat > "${packer_dir}/scripts/enable-winrm.ps1" << 'POWERSHELL_EOF'
# Enable WinRM for Ansible
Write-Host "Enabling WinRM..."

# Configure WinRM
winrm quickconfig -force
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

# Configure firewall
netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow

Write-Host "WinRM enabled successfully"
POWERSHELL_EOF

    # Install VirtIO drivers script
    cat > "${packer_dir}/scripts/install-virtio-drivers.ps1" << 'POWERSHELL_EOF'
# Install VirtIO drivers
Write-Host "Installing VirtIO drivers..."

$virtioPath = "E:\*"
$drivers = Get-ChildItem -Path $virtioPath -Recurse -Filter "*.inf"

foreach ($driver in $drivers) {
    Write-Host "Installing driver: $($driver.FullName)"
    pnputil.exe /add-driver $driver.FullName /install
}

Write-Host "VirtIO drivers installed successfully"
POWERSHELL_EOF

    log_success "Packer templates generated in: ${packer_dir}"
}

################################################################################
# Main Function
################################################################################

main() {
    log_info "Starting VM provisioning for GOAD lab..."

    # Prepare ISOs
    prepare_isos

    # Create VMs
    create_all_vms

    # Generate Ansible inventory
    generate_ansible_inventory

    # Generate Packer templates for automated installation
    generate_packer_templates

    # Display installation instructions
    display_windows_install_instructions

    log_success "VM provisioning completed"
    log_warning "Please install Windows on each VM before proceeding with GOAD deployment"
}

main "$@"
