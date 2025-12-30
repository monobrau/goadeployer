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

    # Create VM without network (add network interface separately to avoid format issues)
    log_info "Creating VM with ID ${vmid}..."
    
    if command -v qm &> /dev/null; then
        # Use qm command directly - more reliable and respects VM ID
        # Create VM without network interface (will be added separately)
        log_info "Creating VM using qm command..."
        if ! qm create "${vmid}" \
            --name "${name}" \
            --cores "${cores}" \
            --memory "${memory}" \
            --scsihw virtio-scsi-pci \
            --ostype win10 \
            --agent 1; then
            log_error "Failed to create VM ${vmid} using qm command"
            return 1
        fi
        log_success "VM ${vmid} created via qm command"
    else
        # Fallback to API if qm not available
        log_info "Creating VM using API..."
        local create_data="vmid=${vmid}"
        create_data+="&name=${name}"
        create_data+="&cores=${cores}"
        create_data+="&memory=${memory}"
        create_data+="&scsihw=virtio-scsi-pci"
        create_data+="&ostype=win10"
        create_data+="&agent=1"
        
        local response=$(pve_api POST "/nodes/${PROXMOX_NODE}/qemu" "${create_data}")
        
        # Check if API call succeeded
        local error=$(echo "${response}" | jq -r '.errors[0].message // empty' 2>/dev/null)
        if [[ -n "${error}" ]]; then
            log_error "Failed to create VM ${vmid}: ${error}"
            echo "${response}" | jq '.' >&2
            return 1
        fi
        
        # Extract task UPID and wait for VM creation to complete
        local upid=$(echo "${response}" | jq -r '.data // empty' 2>/dev/null)
        if [[ -n "${upid}" ]] && [[ "${upid}" =~ ^UPID: ]]; then
            log_info "VM creation task started: ${upid}"
            if ! pve_wait_for_task "${upid}"; then
                log_error "VM creation task failed"
                return 1
            fi
        else
            # Wait a bit for VM to be created
            sleep 3
        fi
        
        # Verify VM was created with correct ID
        local vm_check=$(pve_api GET "/nodes/${PROXMOX_NODE}/qemu" | jq -r ".data[] | select(.vmid == ${vmid}) | .vmid" 2>/dev/null)
        if [[ -z "${vm_check}" ]]; then
            log_error "VM ${vmid} creation reported success but VM not found"
            echo "API Response: ${response}" >&2
            return 1
        fi
        
        # Double-check the VM ID matches what we requested
        if [[ "${vm_check}" != "${vmid}" ]]; then
            log_error "VM created with wrong ID: expected ${vmid}, got ${vm_check}"
            log_error "This may indicate the VM ID was already in use or API issue"
            return 1
        fi
        
        log_success "VM ${vmid} created via API"
    fi
    
    # Add network interface using Proxmox CLI (qm) - more reliable than API
    log_info "Adding network interface to VM ${vmid}..."
    
    if command -v qm &> /dev/null; then
        # Use qm command directly (works when running on Proxmox node)
        if qm set "${vmid}" --net0 "virtio,bridge=${BRIDGE_NAME},tag=${VLAN_ID}" &> /dev/null; then
            log_success "Network interface added via qm CLI"
        else
            log_error "Failed to add network interface via qm CLI"
            log_info "VM created successfully. Please add network manually:"
            log_info "  Run: qm set ${vmid} --net0 virtio,bridge=${BRIDGE_NAME},tag=${VLAN_ID}"
            return 0  # Don't fail, VM is created
        fi
    else
        # Fallback: Try API (may not work due to format issues)
        log_warning "qm command not available, trying API (may fail)..."
        local net_data="net0=virtio,bridge=${BRIDGE_NAME},tag=${VLAN_ID}"
        local net_response=$(pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${net_data}")
        local net_error=$(echo "${net_response}" | jq -r '.errors[0].message // empty' 2>/dev/null)
        
        if [[ -n "${net_error}" ]]; then
            log_warning "Failed to add network via API: ${net_error}"
            log_info "VM created successfully. Please add network manually via Proxmox UI or qm command"
            return 0  # Don't fail, VM is created
        fi
        log_success "Network interface added via API"
    fi

    # Add disk
    log_info "Adding disk to VM ${vmid}..."
    # Strip "G" suffix from disk_size if present (Proxmox expects number in GiB, not "60G")
    local disk_size_gb="${disk_size}"
    disk_size_gb="${disk_size_gb%G}"  # Remove trailing G if present
    disk_size_gb="${disk_size_gb%g}"  # Remove trailing g if present
    
    if command -v qm &> /dev/null; then
        # Use qm command directly - more reliable
        log_info "Adding disk using qm command..."
        local disk_output
        disk_output=$(qm set "${vmid}" --scsi0 "${PROXMOX_STORAGE}:${disk_size_gb},format=qcow2" 2>&1)
        local disk_exit_code=$?
        if [[ ${disk_exit_code} -ne 0 ]]; then
            log_error "Failed to add disk to VM ${vmid} using qm command"
            log_error "Disk specification: ${PROXMOX_STORAGE}:${disk_size_gb},format=qcow2"
            log_error "Error output: ${disk_output}"
            return 1
        fi
        log_success "Disk added via qm command: ${PROXMOX_STORAGE}:${disk_size_gb}G"
        
        # Verify disk was created
        local disk_check
        disk_check=$(qm config "${vmid}" 2>/dev/null | grep -E "^scsi0:" || true)
        if [[ -z "${disk_check}" ]]; then
            log_warning "Disk may not have been created. Checking VM config..."
            qm config "${vmid}" | grep -E "scsi|ide" || true
        else
            log_info "Disk verified: ${disk_check}"
        fi
    else
        # Fallback to API if qm not available
        log_info "Adding disk using API..."
        local disk_data="scsi0=${PROXMOX_STORAGE}:${disk_size_gb},format=qcow2"
        local disk_response=$(pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${disk_data}")
        local disk_error=$(echo "${disk_response}" | jq -r '.errors[0].message // empty' 2>/dev/null)
        if [[ -n "${disk_error}" ]]; then
            log_error "Failed to add disk to VM ${vmid}: ${disk_error}"
            echo "${disk_response}" | jq '.' >&2
            return 1
        fi
        log_success "Disk added via API"
    fi

    # Add CD-ROM drives
    log_info "Configuring CD-ROM drives..."
    
    if command -v qm &> /dev/null; then
        # Use qm command directly (works when running on Proxmox node)
        # Add Windows ISO to ide0
        log_info "Attaching Windows ISO: ${iso_name}"
        if ! qm set "${vmid}" --ide0 "${PROXMOX_STORAGE}:iso/${iso_name},media=cdrom"; then
            log_error "Failed to attach Windows ISO to VM ${vmid}"
            log_error "ISO path: ${PROXMOX_STORAGE}:iso/${iso_name}"
            log_info "Please verify ISO exists and attach manually:"
            log_info "  qm set ${vmid} --ide0 ${PROXMOX_STORAGE}:iso/${iso_name},media=cdrom"
            return 1
        fi
        log_success "Windows ISO attached to ide0"
        
        # Add VirtIO ISO to ide2
        log_info "Attaching VirtIO ISO: ${VIRTIO_ISO_NAME}"
        if ! qm set "${vmid}" --ide2 "${PROXMOX_STORAGE}:iso/${VIRTIO_ISO_NAME},media=cdrom"; then
            log_warning "Failed to attach VirtIO ISO to VM ${vmid} (may not exist yet)"
            log_info "You can attach it later: qm set ${vmid} --ide2 ${PROXMOX_STORAGE}:iso/${VIRTIO_ISO_NAME},media=cdrom"
            # Don't fail for VirtIO ISO, it's optional
        else
            log_success "VirtIO ISO attached to ide2"
        fi
    else
        # Fallback: Try API (may not work due to format issues)
        log_warning "qm command not available, trying API..."
        local cdrom_data="ide0=${PROXMOX_STORAGE}:iso/${iso_name},media=cdrom"
        cdrom_data+="&ide2=${PROXMOX_STORAGE}:iso/${VIRTIO_ISO_NAME},media=cdrom"
        local cdrom_response=$(pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${cdrom_data}")
        local cdrom_error=$(echo "${cdrom_response}" | jq -r '.errors[0].message // empty' 2>/dev/null)
        
        if [[ -n "${cdrom_error}" ]]; then
            log_error "Failed to add CD-ROM via API: ${cdrom_error}"
            log_info "Please attach ISOs manually via Proxmox UI or qm command"
            return 1
        else
            log_success "CD-ROM drives configured via API"
        fi
    fi

    # Configure BIOS/UEFI and boot order
    log_info "Configuring BIOS and boot order..."
    if command -v qm &> /dev/null; then
        # Set BIOS (not UEFI) for Windows Server - more compatible
        qm set "${vmid}" --bios seabios &> /dev/null || true
        
        # Boot from ide0 (Windows ISO) first, then scsi0 (disk)
        # Note: ide2 (VirtIO) removed from boot order as it's not bootable
        if ! qm set "${vmid}" --boot "order=ide0;scsi0"; then
            log_warning "Failed to set boot order via qm, trying API..."
            local boot_data="boot=order=ide0;scsi0"
            pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${boot_data}" > /dev/null 2>&1
        else
            log_success "Boot order configured: ide0 (ISO) first, then scsi0 (disk)"
        fi
        
        # Verify boot order was set
        local boot_check=$(qm config "${vmid}" 2>/dev/null | grep "^boot:" || echo "")
        if [[ -z "${boot_check}" ]]; then
            log_warning "Boot order may not be set correctly. Please verify manually."
        fi
    else
        local boot_data="boot=order=ide0;scsi0"
        pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${boot_data}" > /dev/null 2>&1
    fi
    
    # Set CPU type
    log_info "Setting CPU type..."
    if command -v qm &> /dev/null; then
        qm set "${vmid}" --cpu host &> /dev/null || true
    else
        local cpu_data="cpu=host"
        pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${cpu_data}" > /dev/null 2>&1
    fi

    # Enable QEMU agent
    log_info "Enabling QEMU agent..."
    if command -v qm &> /dev/null; then
        qm set "${vmid}" --agent 1,fstrim_cloned_disks=1 &> /dev/null || true
    else
        local agent_data="agent=1,fstrim_cloned_disks=1"
        pve_api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" "${agent_data}" > /dev/null 2>&1
    fi

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

start_all_vms() {
    log_info "Starting all GOAD VMs to boot into Windows installer..."
    
    local vms=("${DC01_VMID}" "${DC02_VMID}" "${DC03_VMID}" "${SRV02_VMID}" "${SRV03_VMID}")
    local names=("${DC01_NAME}" "${DC02_NAME}" "${DC03_NAME}" "${SRV02_NAME}" "${SRV03_NAME}")
    
    for i in "${!vms[@]}"; do
        local vmid="${vms[$i]}"
        local name="${names[$i]}"
        
        log_info "Starting VM ${vmid}: ${name}..."
        if command -v qm &> /dev/null; then
            # Verify ISO is attached before starting
            local iso=$(qm config "${vmid}" 2>/dev/null | grep "^ide0:" | cut -d: -f2 | cut -d, -f1 | tr -d ' ')
            if [[ -z "${iso}" ]] || [[ "${iso}" == "none" ]]; then
                log_error "VM ${vmid} has no ISO attached! Cannot boot."
                log_info "Please attach ISO: qm set ${vmid} --ide0 ${PROXMOX_STORAGE}:iso/YOUR_ISO.iso,media=cdrom"
                continue
            fi
            
            # Check boot order
            local boot_order=$(qm config "${vmid}" 2>/dev/null | grep "^boot:" || echo "")
            if [[ -z "${boot_order}" ]]; then
                log_warning "VM ${vmid} has no boot order set. Setting it now..."
                qm set "${vmid}" --boot "order=ide0;scsi0" &> /dev/null || true
            fi
            
            # Start VM
            if qm start "${vmid}" &> /dev/null; then
                log_success "VM ${vmid} (${name}) started successfully"
                log_info "  ISO: ${iso}"
                log_info "  Console: qm terminal ${vmid}"
            else
                local status=$(qm status "${vmid}" 2>/dev/null | awk '{print $2}')
                if [[ "${status}" == "running" ]]; then
                    log_warning "VM ${vmid} is already running"
                else
                    log_error "Failed to start VM ${vmid}"
                    log_info "Check logs: journalctl -u pve-cluster -f"
                fi
            fi
        else
            log_warning "qm command not available, cannot start VM ${vmid}"
            log_info "Please start manually: qm start ${vmid}"
        fi
    done
    
    log_success "VM startup completed."
    log_info "If VMs don't boot, run: ./scripts/troubleshoot_vm_boot.sh"
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
║  3. IMPORTANT: Load VirtIO drivers BEFORE selecting disk:                ║
║     - Click "Load driver" button                                          ║
║     - Browse to the VirtIO ISO (usually E: drive)                        ║
║     - Navigate to: E:\vioscsi\w10\amd64\ (or similar)                   ║
║     - Select "vioscsi.inf" and click OK                                  ║
║     - Wait for driver to install                                         ║
║  4. If disk still shows as "Offline" or "Read-only":                     ║
║     - Press Shift+F10 to open command prompt                             ║
║     - Run: diskpart                                                       ║
║       > list disk                                                         ║
║       > select disk 0                                                     ║
║       > online disk                                                       ║
║       > attributes disk clear readonly                                    ║
║       > exit                                                              ║
║     - Close command prompt and click Refresh                             ║
║  5. Configure static IP addresses as shown below                         ║
║  6. Enable WinRM (run: winrm quickconfig -force)                         ║
║  7. Set administrator password to: Password123!                          ║
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

install_packer() {
    log_info "Checking for Packer installation..."
    
    if command -v packer &> /dev/null; then
        local packer_version=$(packer version | head -n1)
        log_success "Packer already installed: ${packer_version}"
        return 0
    fi
    
    log_info "Installing Packer..."
    
    # Detect architecture
    local arch=$(uname -m)
    if [[ "${arch}" != "x86_64" ]]; then
        log_error "Unsupported architecture: ${arch}. Please install Packer manually."
        return 1
    fi
    
    # Download and install Packer
    local packer_version="1.10.0"
    local packer_url="https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_amd64.zip"
    local temp_dir=$(mktemp -d)
    
    log_info "Downloading Packer ${packer_version}..."
    if ! curl -fsSL "${packer_url}" -o "${temp_dir}/packer.zip"; then
        log_error "Failed to download Packer"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    log_info "Extracting Packer..."
    unzip -q "${temp_dir}/packer.zip" -d "${temp_dir}"
    
    # Install to /usr/local/bin
    if [[ -w "/usr/local/bin" ]]; then
        sudo mv "${temp_dir}/packer" /usr/local/bin/
        sudo chmod +x /usr/local/bin/packer
    else
        # Try without sudo or install to user directory
        mkdir -p "${HOME}/.local/bin"
        mv "${temp_dir}/packer" "${HOME}/.local/bin/"
        chmod +x "${HOME}/.local/bin/packer"
        export PATH="${HOME}/.local/bin:${PATH}"
        log_info "Packer installed to ${HOME}/.local/bin (add to PATH if needed)"
    fi
    
    rm -rf "${temp_dir}"
    
    if command -v packer &> /dev/null; then
        log_success "Packer installed successfully"
        return 0
    else
        log_error "Packer installation failed. Please install manually."
        return 1
    fi
}

generate_packer_templates() {
    log_info "Generating Packer templates for automated Windows installation..."

    local packer_dir="${SCRIPT_DIR}/packer"
    mkdir -p "${packer_dir}"

    # Create variables file
    cat > "${packer_dir}/proxmox.vars.hcl" << EOF
proxmox_host = "${PROXMOX_HOST}"
proxmox_node = "${PROXMOX_NODE}"
proxmox_api_user = "${PROXMOX_API_USER}"
proxmox_api_token = "${PROXMOX_API_TOKEN_SECRET}"
storage_pool = "${PROXMOX_STORAGE}"
win2019_iso = "${WIN2019_ISO_NAME}"
win2016_iso = "${WIN2016_ISO_NAME}"
virtio_iso = "${VIRTIO_ISO_NAME}"
bridge_name = "${BRIDGE_NAME}"
vlan_id = "${VLAN_ID}"
admin_password = "${WINDOWS_ADMIN_PASSWORD}"
EOF

    # Windows Server 2019 Packer template
    cat > "${packer_dir}/windows-server-2019.pkr.hcl" << 'PACKER_EOF'
# Packer template for Windows Server 2019 on Proxmox

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1.1"
    }
  }
}

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

variable "storage_pool" {
  type = string
}

variable "win2019_iso" {
  type = string
}

variable "virtio_iso" {
  type = string
}

variable "bridge_name" {
  type = string
}

variable "vlan_id" {
  type = string
}

variable "admin_password" {
  type = string
  sensitive = true
}

source "proxmox-iso" "windows-server-2019" {
  proxmox_url              = "https://${var.proxmox_host}:8006/api2/json"
  username                 = var.proxmox_api_user
  token                    = var.proxmox_api_token
  insecure_skip_tls_verify = true

  node                 = var.proxmox_node
  vm_name              = "windows-server-2019-template"
  template_description = "Windows Server 2019 template for GOAD"

  iso_file         = "${var.storage_pool}:iso/${var.win2019_iso}"
  iso_storage_pool = var.storage_pool

  additional_iso_files {
    device           = "ide2"
    iso_file         = "${var.storage_pool}:iso/${var.virtio_iso}"
    iso_storage_pool = var.storage_pool
  }

  os       = "win10"
  cores    = 2
  memory   = 4096
  scsi_controller = "virtio-scsi-pci"

  network_adapters {
    model  = "virtio"
    bridge = var.bridge_name
    vlan_tag = var.vlan_id
  }

  disks {
    type         = "scsi"
    disk_size    = "60G"
    storage_pool = var.storage_pool
    format       = "qcow2"
  }

  # HTTP directory for autounattend.xml
  http_directory = "http"
  http_port_min  = 8000
  http_port_max  = 8100

  # Boot configuration - Windows Setup will automatically look for autounattend.xml
  boot_wait = "10s"

  communicator = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  winrm_timeout  = "4h"
  winrm_use_ssl  = false
  winrm_insecure = true

  cloud_init              = false
  cloud_init_storage_pool = var.storage_pool
}

build {
  sources = ["source.proxmox-iso.windows-server-2019"]

  provisioner "powershell" {
    scripts = [
      "scripts/enable-winrm.ps1",
      "scripts/install-virtio-drivers.ps1",
      "scripts/configure-network.ps1"
    ]
  }
}
PACKER_EOF

    # Windows Server 2016 Packer template
    cat > "${packer_dir}/windows-server-2016.pkr.hcl" << 'PACKER_EOF'
# Packer template for Windows Server 2016 on Proxmox

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1.1"
    }
  }
}

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

variable "storage_pool" {
  type = string
}

variable "win2016_iso" {
  type = string
}

variable "virtio_iso" {
  type = string
}

variable "bridge_name" {
  type = string
}

variable "vlan_id" {
  type = string
}

variable "admin_password" {
  type = string
  sensitive = true
}

source "proxmox-iso" "windows-server-2016" {
  proxmox_url              = "https://${var.proxmox_host}:8006/api2/json"
  username                 = var.proxmox_api_user
  token                    = var.proxmox_api_token
  insecure_skip_tls_verify = true

  node                 = var.proxmox_node
  vm_name              = "windows-server-2016-template"
  template_description = "Windows Server 2016 template for GOAD"

  iso_file         = "${var.storage_pool}:iso/${var.win2016_iso}"
  iso_storage_pool = var.storage_pool

  additional_iso_files {
    device           = "ide2"
    iso_file         = "${var.storage_pool}:iso/${var.virtio_iso}"
    iso_storage_pool = var.storage_pool
  }

  os       = "win10"
  cores    = 2
  memory   = 4096
  scsi_controller = "virtio-scsi-pci"

  network_adapters {
    model  = "virtio"
    bridge = var.bridge_name
    vlan_tag = var.vlan_id
  }

  disks {
    type         = "scsi"
    disk_size    = "60G"
    storage_pool = var.storage_pool
    format       = "qcow2"
  }

  # HTTP directory for autounattend.xml
  http_directory = "http"
  http_port_min  = 8000
  http_port_max  = 8100

  # Boot configuration - Windows Setup will automatically look for autounattend.xml
  boot_wait = "10s"

  communicator = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  winrm_timeout  = "4h"
  winrm_use_ssl  = false
  winrm_insecure = true

  cloud_init              = false
  cloud_init_storage_pool = var.storage_pool
}

build {
  sources = ["source.proxmox-iso.windows-server-2016"]

  provisioner "powershell" {
    scripts = [
      "scripts/enable-winrm.ps1",
      "scripts/install-virtio-drivers.ps1",
      "scripts/configure-network.ps1"
    ]
  }
}
PACKER_EOF

    # Create Packer scripts directory
    mkdir -p "${packer_dir}/scripts"
    mkdir -p "${packer_dir}/http"  # For autounattend.xml files
    mkdir -p "${packer_dir}/floppy"  # For floppy disk images

    # Create autounattend.xml for Windows Server 2019
    cat > "${packer_dir}/http/autounattend-2019.xml" << 'AUTOUNATTEND_EOF'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-US</InputLocale>
            <UserLocale>en-US</UserLocale>
            <UILanguage>en-US</UILanguage>
            <SystemLocale>en-US</SystemLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add">
                            <Order>1</Order>
                            <Type>Primary</Type>
                            <Size>61440</Size>
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Letter>C</Letter>
                            <Label>OS</Label>
                            <Format>NTFS</Format>
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>2</Value>
                        </MetaData>
                    </InstallFrom>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>1</PartitionID>
                    </InstallTo>
                </OSImage>
            </ImageInstall>
            <UserData>
                <AcceptEula>true</AcceptEula>
                <FullName>Administrator</FullName>
                <Organization>GOAD Lab</Organization>
            </UserData>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ComputerName>WIN-SERVER</ComputerName>
            <TimeZone>UTC</TimeZone>
        </component>
        <component name="Microsoft-Windows-ServerManager-SvrMgrNc" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DoNotOpenServerManagerAtLogon>true</DoNotOpenServerManagerAtLogon>
        </component>
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>cmd.exe /c powershell -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"</Path>
                    <Description>Install Chocolatey</Description>
                    <WillReboot>Never</WillReboot>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <AutoLogon>
                <Password>
                    <Value>Password123!</Value>
                    <PlainText>true</PlainText>
                </Password>
                <Enabled>true</Enabled>
                <Username>Administrator</Username>
            </AutoLogon>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>cmd.exe /c winrm quickconfig -force -q</CommandLine>
                    <Description>Enable WinRM</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <CommandLine>cmd.exe /c winrm set winrm/config/service @{AllowUnencrypted="true"}</CommandLine>
                    <Description>Configure WinRM</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <CommandLine>cmd.exe /c winrm set winrm/config/service/auth @{Basic="true"}</CommandLine>
                    <Description>Enable Basic Auth</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>4</Order>
                    <CommandLine>cmd.exe /c netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow</CommandLine>
                    <Description>Open WinRM Firewall</Description>
                </SynchronousCommand>
            </FirstLogonCommands>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>1</ProtectYourPC>
                <SkipMachineOOBE>true</SkipMachineOOBE>
                <SkipUserOOBE>true</SkipUserOOBE>
            </OOBE>
            <UserAccounts>
                <AdministratorPassword>
                    <Value>Password123!</Value>
                    <PlainText>true</PlainText>
                </AdministratorPassword>
            </UserAccounts>
        </component>
    </settings>
    <cpi:offlineImage cpi:source="wim:c:/install.wim#Windows Server 2019 SERVERSTANDARD" xmlns:cpi="urn:schemas-microsoft-com:cpi" />
</unattend>
AUTOUNATTEND_EOF

    # Create autounattend.xml for Windows Server 2016
    cat > "${packer_dir}/http/autounattend-2016.xml" << 'AUTOUNATTEND_EOF'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-US</InputLocale>
            <UserLocale>en-US</UserLocale>
            <UILanguage>en-US</UILanguage>
            <SystemLocale>en-US</SystemLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add">
                            <Order>1</Order>
                            <Type>Primary</Type>
                            <Size>61440</Size>
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Letter>C</Letter>
                            <Label>OS</Label>
                            <Format>NTFS</Format>
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>2</Value>
                        </MetaData>
                    </InstallFrom>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>1</PartitionID>
                    </InstallTo>
                </OSImage>
            </ImageInstall>
            <UserData>
                <AcceptEula>true</AcceptEula>
                <FullName>Administrator</FullName>
                <Organization>GOAD Lab</Organization>
            </UserData>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ComputerName>WIN-SERVER</ComputerName>
            <TimeZone>UTC</TimeZone>
        </component>
        <component name="Microsoft-Windows-ServerManager-SvrMgrNc" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DoNotOpenServerManagerAtLogon>true</DoNotOpenServerManagerAtLogon>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <AutoLogon>
                <Password>
                    <Value>Password123!</Value>
                    <PlainText>true</PlainText>
                </Password>
                <Enabled>true</Enabled>
                <Username>Administrator</Username>
            </AutoLogon>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>cmd.exe /c winrm quickconfig -force -q</CommandLine>
                    <Description>Enable WinRM</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <CommandLine>cmd.exe /c winrm set winrm/config/service @{AllowUnencrypted="true"}</CommandLine>
                    <Description>Configure WinRM</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <CommandLine>cmd.exe /c winrm set winrm/config/service/auth @{Basic="true"}</CommandLine>
                    <Description>Enable Basic Auth</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>4</Order>
                    <CommandLine>cmd.exe /c netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow</CommandLine>
                    <Description>Open WinRM Firewall</Description>
                </SynchronousCommand>
            </FirstLogonCommands>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>1</ProtectYourPC>
                <SkipMachineOOBE>true</SkipMachineOOBE>
                <SkipUserOOBE>true</SkipUserOOBE>
            </OOBE>
            <UserAccounts>
                <AdministratorPassword>
                    <Value>Password123!</Value>
                    <PlainText>true</PlainText>
                </AdministratorPassword>
            </UserAccounts>
        </component>
    </settings>
    <cpi:offlineImage cpi:source="wim:c:/install.wim#Windows Server 2016 SERVERSTANDARD" xmlns:cpi="urn:schemas-microsoft-com:cpi" />
</unattend>
AUTOUNATTEND_EOF

    # Enable WinRM script
    cat > "${packer_dir}/scripts/enable-winrm.ps1" << 'POWERSHELL_EOF'
# Enable WinRM for Ansible
Write-Host "Enabling WinRM..."

# Configure WinRM
winrm quickconfig -force -q
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

# Find VirtIO CD-ROM (usually E: drive)
$virtioDrive = Get-WmiObject Win32_CDROMDrive | Where-Object { $_.Drive -ne $null } | Select-Object -First 1
if ($virtioDrive) {
    $virtioPath = $virtioDrive.Drive + "\"
    Write-Host "Found VirtIO ISO at: $virtioPath"
    
    # Install storage driver (vioscsi)
    $scsiDriver = Get-ChildItem -Path $virtioPath -Recurse -Filter "vioscsi.inf" | Select-Object -First 1
    if ($scsiDriver) {
        Write-Host "Installing storage driver: $($scsiDriver.FullName)"
        pnputil.exe /add-driver $scsiDriver.FullName /install
    }
    
    # Install network driver (netkvm)
    $netDriver = Get-ChildItem -Path $virtioPath -Recurse -Filter "netkvm.inf" | Select-Object -First 1
    if ($netDriver) {
        Write-Host "Installing network driver: $($netDriver.FullName)"
        pnputil.exe /add-driver $netDriver.FullName /install
    }
} else {
    Write-Warning "VirtIO ISO not found, drivers may need manual installation"
}

Write-Host "VirtIO drivers installation completed"
POWERSHELL_EOF

    # Configure network script (basic - IPs will be set later)
    cat > "${packer_dir}/scripts/configure-network.ps1" << 'POWERSHELL_EOF'
# Basic network configuration
Write-Host "Configuring network..."

# Enable network adapter (will be configured with static IPs later via Ansible)
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if ($adapter) {
    Write-Host "Network adapter found: $($adapter.Name)"
    # Network will be configured with static IPs during GOAD deployment
} else {
    Write-Warning "No active network adapter found"
}

Write-Host "Network configuration completed"
POWERSHELL_EOF

    # Create floppy disk images with autounattend.xml (more reliable than HTTP for Proxmox)
    log_info "Creating floppy disk images with autounattend.xml..."
    
    # Create floppy disk image for Windows Server 2019
    if command -v mkfs.msdos &> /dev/null || command -v mkdosfs &> /dev/null; then
        # Create 1.44MB floppy disk image
        dd if=/dev/zero of="${packer_dir}/floppy/autounattend-2019.img" bs=1024 count=1440 2>/dev/null
        mkfs.msdos -F 12 "${packer_dir}/floppy/autounattend-2019.img" 2>/dev/null || mkdosfs -F 12 "${packer_dir}/floppy/autounattend-2019.img" 2>/dev/null
        
        # Mount and copy autounattend.xml
        local mnt_dir=$(mktemp -d)
        if mount -o loop "${packer_dir}/floppy/autounattend-2019.img" "${mnt_dir}" 2>/dev/null; then
            cp "${packer_dir}/http/autounattend-2019.xml" "${mnt_dir}/autounattend.xml"
            umount "${mnt_dir}" 2>/dev/null
            rmdir "${mnt_dir}" 2>/dev/null
            log_success "Created floppy disk image for Windows Server 2019"
        else
            log_warning "Could not create floppy disk image (may need root or loop device support)"
            log_info "Will use HTTP directory method instead"
        fi
        
        # Create floppy disk image for Windows Server 2016
        dd if=/dev/zero of="${packer_dir}/floppy/autounattend-2016.img" bs=1024 count=1440 2>/dev/null
        mkfs.msdos -F 12 "${packer_dir}/floppy/autounattend-2016.img" 2>/dev/null || mkdosfs -F 12 "${packer_dir}/floppy/autounattend-2016.img" 2>/dev/null
        
        if mount -o loop "${packer_dir}/floppy/autounattend-2016.img" "${mnt_dir}" 2>/dev/null; then
            cp "${packer_dir}/http/autounattend-2016.xml" "${mnt_dir}/autounattend.xml"
            umount "${mnt_dir}" 2>/dev/null
            rmdir "${mnt_dir}" 2>/dev/null
            log_success "Created floppy disk image for Windows Server 2016"
        fi
    else
        log_warning "mkfs.msdos/mkdosfs not available, skipping floppy disk creation"
        log_info "Windows Setup will look for autounattend.xml via HTTP or manual methods"
    fi

    log_success "Packer templates generated in: ${packer_dir}"
}

install_windows_with_packer() {
    log_info "Installing Windows using Packer automation..."
    
    # Check if Packer is installed
    if ! command -v packer &> /dev/null; then
        log_info "Packer not found, installing..."
        if ! install_packer; then
            log_error "Failed to install Packer. Falling back to manual installation."
            return 1
        fi
    fi
    
    local packer_dir="${SCRIPT_DIR}/packer"
    local vars_file="proxmox.vars.hcl"
    local log_file="${SCRIPT_DIR}/logs/packer_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "${SCRIPT_DIR}/logs"
    
    # Change to packer directory so relative paths work
    cd "${packer_dir}" || {
        log_error "Failed to change to packer directory: ${packer_dir}"
        return 1
    }
    
    # Remove any unmount_iso references from templates (safety check)
    log_info "Cleaning up Packer templates..."
    sed -i '/unmount_iso/d' "windows-server-2019.pkr.hcl" 2>/dev/null || true
    sed -i '/unmount_iso/d' "windows-server-2016.pkr.hcl" 2>/dev/null || true
    
    # Initialize Packer plugins (this downloads the Proxmox plugin if needed)
    log_info "Initializing Packer plugins..."
    if ! packer init "windows-server-2019.pkr.hcl" 2>&1 | tee -a "${log_file}"; then
        log_error "Failed to initialize Packer plugins. Check log: ${log_file}"
        cd - > /dev/null
        return 1
    fi
    
    # Validate templates before building
    log_info "Validating Packer templates..."
    if ! packer validate -var-file="${vars_file}" "windows-server-2019.pkr.hcl" 2>&1 | tee -a "${log_file}"; then
        log_error "Template validation failed. Check log: ${log_file}"
        cd - > /dev/null
        return 1
    fi
    
    if ! packer validate -var-file="${vars_file}" "windows-server-2016.pkr.hcl" 2>&1 | tee -a "${log_file}"; then
        log_error "Template validation failed. Check log: ${log_file}"
        cd - > /dev/null
        return 1
    fi
    
    # Build Windows Server 2019 template
    log_info "Building Windows Server 2019 template (this will take 30-60 minutes)..."
    log_warning "This is a long process. Progress will be logged to: ${log_file}"
    if packer build -var-file="${vars_file}" "windows-server-2019.pkr.hcl" 2>&1 | tee -a "${log_file}"; then
        log_success "Windows Server 2019 template built successfully"
    else
        log_error "Failed to build Windows Server 2019 template. Check log: ${log_file}"
        cd - > /dev/null
        return 1
    fi
    
    # Build Windows Server 2016 template
    log_info "Building Windows Server 2016 template (this will take 30-60 minutes)..."
    if packer build -var-file="${vars_file}" "windows-server-2016.pkr.hcl" 2>&1 | tee -a "${log_file}"; then
        log_success "Windows Server 2016 template built successfully"
    else
        log_error "Failed to build Windows Server 2016 template. Check log: ${log_file}"
        cd - > /dev/null
        return 1
    fi
    
    # Return to original directory
    cd - > /dev/null
    
    log_success "Windows templates built. Now cloning templates to create GOAD VMs..."
    
    # Clone templates to create actual VMs
    clone_vms_from_templates
    
    log_success "Windows installation completed via Packer"
}

clone_vms_from_templates() {
    log_info "Cloning templates to create GOAD VMs..."
    
    # Find template VM IDs (Packer creates templates with specific names)
    local win2019_template=$(qm list | grep "windows-server-2019-template" | awk '{print $1}' | head -n1)
    local win2016_template=$(qm list | grep "windows-server-2016-template" | awk '{print $1}' | head -n1)
    
    if [[ -z "${win2019_template}" ]]; then
        log_error "Windows Server 2019 template not found. Check Packer build logs."
        return 1
    fi
    
    if [[ -z "${win2016_template}" ]]; then
        log_error "Windows Server 2016 template not found. Check Packer build logs."
        return 1
    fi
    
    log_info "Found templates: Win2019=${win2019_template}, Win2016=${win2016_template}"
    
    # Clone Windows Server 2019 template for DC01, DC02, SRV02
    for vmid in "${DC01_VMID}" "${DC02_VMID}" "${SRV02_VMID}"; do
        local name
        case "${vmid}" in
            "${DC01_VMID}") name="${DC01_NAME}" ;;
            "${DC02_VMID}") name="${DC02_NAME}" ;;
            "${SRV02_VMID}") name="${SRV02_NAME}" ;;
        esac
        
        # Check if VM already exists
        if qm list | grep -q "^[[:space:]]*${vmid}[[:space:]]"; then
            log_warning "VM ${vmid} already exists, skipping clone"
            continue
        fi
        
        log_info "Cloning template ${win2019_template} to VM ${vmid}: ${name}..."
        if qm clone "${win2019_template}" "${vmid}" --name "${name}" --full --storage "${PROXMOX_STORAGE}"; then
            log_success "VM ${vmid} cloned successfully"
            # Configure network
            qm set "${vmid}" --net0 "virtio,bridge=${BRIDGE_NAME},tag=${VLAN_ID}"
            # Configure resources based on VM type
            case "${vmid}" in
                "${DC01_VMID}")
                    qm set "${vmid}" --cores "${DC01_CORES}" --memory "${DC01_MEMORY}"
                    ;;
                "${DC02_VMID}")
                    qm set "${vmid}" --cores "${DC02_CORES}" --memory "${DC02_MEMORY}"
                    ;;
                "${SRV02_VMID}")
                    qm set "${vmid}" --cores "${SRV02_CORES}" --memory "${SRV02_MEMORY}"
                    ;;
            esac
        else
            log_error "Failed to clone VM ${vmid}"
        fi
    done
    
    # Clone Windows Server 2016 template for DC03, SRV03
    for vmid in "${DC03_VMID}" "${SRV03_VMID}"; do
        local name
        case "${vmid}" in
            "${DC03_VMID}") name="${DC03_NAME}" ;;
            "${SRV03_VMID}") name="${SRV03_NAME}" ;;
        esac
        
        # Check if VM already exists
        if qm list | grep -q "^[[:space:]]*${vmid}[[:space:]]"; then
            log_warning "VM ${vmid} already exists, skipping clone"
            continue
        fi
        
        log_info "Cloning template ${win2016_template} to VM ${vmid}: ${name}..."
        if qm clone "${win2016_template}" "${vmid}" --name "${name}" --full --storage "${PROXMOX_STORAGE}"; then
            log_success "VM ${vmid} cloned successfully"
            # Configure network
            qm set "${vmid}" --net0 "virtio,bridge=${BRIDGE_NAME},tag=${VLAN_ID}"
            # Configure resources
            case "${vmid}" in
                "${DC03_VMID}")
                    qm set "${vmid}" --cores "${DC03_CORES}" --memory "${DC03_MEMORY}"
                    ;;
                "${SRV03_VMID}")
                    qm set "${vmid}" --cores "${SRV03_CORES}" --memory "${SRV03_MEMORY}"
                    ;;
            esac
        else
            log_error "Failed to clone VM ${vmid}"
        fi
    done
}

################################################################################
# Main Function
################################################################################

main() {
    local use_packer=true  # Packer is now the default
    
    # Check for flags
    if [[ "${1:-}" == "--manual" ]] || [[ "${1:-}" == "--no-packer" ]]; then
        use_packer=false
    fi
    # Keep --use-packer for explicit enable (backwards compatibility)
    if [[ "${1:-}" == "--use-packer" ]] || [[ "${1:-}" == "--automated" ]]; then
        use_packer=true
    fi
    
    log_info "Starting VM provisioning for GOAD lab..."

    # Prepare ISOs
    prepare_isos

    if [[ "${use_packer}" == "true" ]]; then
        log_info "Using Packer for automated Windows installation..."
        
        # Generate Packer templates
        generate_packer_templates
        
        # Install Windows using Packer
        if install_windows_with_packer; then
            log_success "Windows installed automatically via Packer"
        else
            log_error "Packer installation failed. Falling back to manual installation."
            log_info "VMs will be created but Windows must be installed manually."
            create_all_vms
            start_all_vms
            display_windows_install_instructions
        fi
    else
        # Create VMs manually
        create_all_vms
        
        # Start all VMs to boot into Windows installer
        start_all_vms
        
        # Generate Packer templates for optional use
        generate_packer_templates
        
        # Display installation instructions
        display_windows_install_instructions
    fi

    # Generate Ansible inventory
    generate_ansible_inventory

    log_success "VM provisioning completed"
    
    if [[ "${use_packer}" == "true" ]]; then
        log_info "Windows installed automatically. VMs are ready for GOAD deployment."
        log_info "Run: ./deploy_goad.sh"
    else
        log_warning "Please install Windows on each VM before proceeding with GOAD deployment"
        log_info "Or re-run without --manual flag for automated installation"
    fi
}

main "$@"
