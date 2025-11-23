# GOAD Proxmox Installer - Project Summary

## Overview

This project provides a complete automation solution for deploying Game Of Active Directory (GOAD) on Proxmox VE 9.1. It includes scripts for installation, configuration, monitoring, and cleanup.

## Project Structure

```
goadeployer/
├── install_goad_proxmox.sh          # Main installation orchestrator
├── goad_config.conf.example         # Configuration template
├── README.md                        # Complete documentation
├── QUICKSTART.md                    # Quick start guide
├── LICENSE                          # MIT License
├── .gitignore                       # Git ignore rules
│
├── scripts/
│   ├── setup_network.sh            # Network configuration (VLAN, NAT)
│   ├── provision_vms.sh            # VM creation and setup
│   ├── cleanup_goad.sh             # Cleanup/rollback functionality
│   └── check_status.sh             # Installation status checker
│
├── logs/                           # Installation logs (auto-generated)
├── templates/                      # Templates directory
└── GOAD/                          # GOAD repository (downloaded during install)
```

## Components

### 1. Main Installation Script (`install_goad_proxmox.sh`)

**Features:**
- Prerequisites verification (Ansible, Python, dependencies)
- Proxmox API connectivity check
- Resource availability verification
- Network setup orchestration
- GOAD repository management
- VM provisioning coordination
- GOAD deployment with Ansible
- Comprehensive logging
- Progress indicators
- Error handling and cleanup

**Usage:**
```bash
./install_goad_proxmox.sh
```

### 2. Configuration File (`goad_config.conf.example`)

**Sections:**
- Proxmox connection settings
- API credentials
- Storage configuration
- Network settings (VLAN, subnet, gateway)
- VM specifications (5 VMs with resource allocations)
- Windows template configuration
- GOAD variant selection
- Security settings
- WireGuard VPN configuration
- Notification settings

**Usage:**
```bash
cp goad_config.conf.example goad_config.conf
# Edit with your settings
nano goad_config.conf
```

### 3. Network Setup Script (`scripts/setup_network.sh`)

**Functionality:**
- Creates Linux bridge (vmbr50) for VLAN 50
- Configures network gateway (192.168.50.1)
- Sets up NAT for internet access
- Configures IP forwarding
- Installs and configures iptables rules
- Optional DNS forwarder setup with dnsmasq
- Network verification

**Features:**
- Automatic backup of network configuration
- Persistent iptables rules
- Support for both local and remote Proxmox hosts

### 4. VM Provisioning Script (`scripts/provision_vms.sh`)

**Functionality:**
- Creates 5 VMs with proper specifications
- Configures VM network (VLAN 50)
- Attaches Windows Server ISOs
- Adds VirtIO drivers
- Generates Ansible inventory
- Creates Packer templates for automation
- Provides Windows installation instructions

**VMs Created:**
- DC01 (800): Domain Controller - sevenkingdoms.local
- DC02 (801): Domain Controller - north.sevenkingdoms.local
- DC03 (802): Domain Controller - essos.local
- SRV02 (803): Server - sevenkingdoms.local
- SRV03 (804): Server - essos.local

**Packer Integration:**
- Automated Windows installation templates
- VirtIO driver installation scripts
- WinRM enablement scripts

### 5. Cleanup Script (`scripts/cleanup_goad.sh`)

**Modes:**
- Complete cleanup (everything)
- VMs only
- Network only
- GOAD repository only
- Logs only

**Features:**
- Interactive mode with confirmation
- Command-line arguments support
- Safe deletion with multiple confirmations
- Proper VM shutdown before deletion
- Network configuration restoration
- iptables rules cleanup

**Usage:**
```bash
# Interactive mode
./scripts/cleanup_goad.sh

# Command-line mode
./scripts/cleanup_goad.sh --complete
./scripts/cleanup_goad.sh --vms-only
```

### 6. Status Checker (`scripts/check_status.sh`)

**Checks:**
- Network configuration (bridge, IP, NAT)
- VM status (running/stopped)
- VM connectivity (ping test)
- GOAD repository status
- Ansible connectivity (WinRM)
- Domain deployment status (DNS resolution)
- Proxmox resource usage

**Output:**
- Color-coded status indicators
- Tabular VM status display
- Installation phase detection
- Next step recommendations

**Usage:**
```bash
./scripts/check_status.sh
```

## Documentation

### README.md
Comprehensive documentation including:
- Detailed installation guide
- Configuration reference
- Network architecture diagrams
- VM specifications
- Troubleshooting guide
- FAQ section
- Security warnings
- Resource links

### QUICKSTART.md
Streamlined 5-step installation guide:
1. Clone repository
2. Create API token
3. Configure settings
4. Upload ISOs
5. Run installer

Includes:
- Windows installation steps
- IP configuration guide
- WinRM setup commands
- Verification steps

### CONNECTION_GUIDE.md
Auto-generated during installation:
- WireGuard VPN setup guide
- RDP access instructions
- WinRM/PowerShell remoting
- Security best practices

## Technical Details

### Network Architecture

```
Internet
    ↓
┌─────────┐
│  vmbr0  │ (Main bridge with internet)
└────┬────┘
     │ NAT
┌────▼────┐
│ vmbr50  │ (GOAD isolated network)
│ VLAN 50 │
│ .50.1   │
└────┬────┘
     │
   ┌─┴─┬─────┬─────┬─────┐
   │   │     │     │     │
  DC01 DC02 DC03 SRV02 SRV03
```

### VM Resource Allocation

| Component | Total Required |
|-----------|---------------|
| RAM       | 20 GB         |
| CPU       | 10 cores      |
| Storage   | 300 GB        |

### Domain Structure

```
sevenkingdoms.local (Forest Root)
├── DC01 (Primary DC)
└── north.sevenkingdoms.local (Child Domain)
    └── DC02 (Child DC)

essos.local (Separate Forest)
└── DC03 (Primary DC)

Trust: sevenkingdoms.local ↔ essos.local (Forest Trust)
```

## Installation Flow

1. **Prerequisites Check**
   - Verify commands (ansible, git, curl, jq)
   - Install missing dependencies
   - Check Python requirements
   - Verify Proxmox API access
   - Check available resources

2. **Network Setup**
   - Create vmbr50 bridge
   - Configure VLAN 50
   - Set IP address (192.168.50.1/24)
   - Enable IP forwarding
   - Configure NAT rules
   - Make rules persistent

3. **GOAD Repository**
   - Clone from GitHub
   - Install Ansible collections
   - Install Python requirements

4. **VM Provisioning**
   - Create 5 VMs via Proxmox API
   - Attach storage and network
   - Configure boot order
   - Generate Ansible inventory
   - Create Packer templates

5. **Windows Installation** (Manual/Packer)
   - Install Windows Server
   - Load VirtIO drivers
   - Configure static IPs
   - Enable WinRM
   - Set administrator password

6. **GOAD Deployment**
   - Run Ansible playbooks
   - Configure Active Directory
   - Create domains and forests
   - Set up trust relationships
   - Create vulnerable configurations
   - Deploy users and groups

7. **Post-Installation**
   - Display VM information
   - Generate connection guide
   - Create WireGuard setup instructions

## Configuration Requirements

### Proxmox

- **Version**: 9.1 or later
- **Storage**: NFS configured
- **API Access**: Token with Administrator role
- **Network**: Available interface for VLAN tagging

### Resources

- **RAM**: 96 GB total (38 GB for VMs minimum)
- **CPU**: 20 cores recommended
- **Storage**: 300 GB free on NFS
- **Network**: Gigabit recommended

### Software Prerequisites

- Ansible 2.9+
- Python 3.8+
- Git
- curl, jq
- sshpass
- iptables

## Security Considerations

### Network Isolation

- GOAD VMs on isolated VLAN 50
- No direct internet exposure
- NAT for outbound only
- Access via VPN only

### Credentials

- Configuration file contains secrets
- Added to .gitignore
- WinRM uses basic auth (lab only)
- Default password: Password123! (change recommended)

### Vulnerable Lab Warning

⚠️ GOAD is **intentionally vulnerable**:
- Do NOT connect to production networks
- Do NOT expose to public internet
- Only for learning and authorized testing
- Keep isolated and access via VPN only

## Logging

All operations logged to:
```
logs/goad_install_YYYYMMDD_HHMMSS.log
```

Log includes:
- Timestamps for all operations
- Prerequisites check results
- Network configuration steps
- VM creation details
- Ansible playbook output
- Error messages and stack traces

## Error Handling

- Automatic cleanup on critical errors
- Rollback capability via cleanup script
- Detailed error messages in logs
- Manual recovery procedures in documentation

## Extensibility

### Adding Custom VMs

Edit `goad_config.conf`:
```bash
CUSTOM_VM_VMID="805"
CUSTOM_VM_NAME="GOAD-CUSTOM"
CUSTOM_VM_CORES="2"
CUSTOM_VM_MEMORY="4096"
CUSTOM_VM_DISK_SIZE="60G"
CUSTOM_VM_IP="192.168.50.30"
```

Update `provision_vms.sh` to include custom VM.

### Different GOAD Variants

Change in `goad_config.conf`:
```bash
GOAD_VARIANT="GOAD-Light"  # Options: GOAD, GOAD-Light, SCCM, NHA
```

Adjust VM count and specifications accordingly.

### Custom Network Range

Update in `goad_config.conf`:
```bash
NETWORK_SUBNET="10.0.50.0/24"
NETWORK_GATEWAY="10.0.50.1"
# Update all VM IPs accordingly
DC01_IP="10.0.50.10"
# etc...
```

## Maintenance

### Updating GOAD

```bash
cd GOAD
git pull
cd ansible
ansible-playbook -i ../ad/GOAD/data/inventory main.yml
```

### Backing Up VMs

```bash
# Backup VM
vzdump 800 --mode snapshot --compress gzip --storage nfs-storage

# Restore VM
qmrestore /path/to/backup.vma.gz 800
```

### Snapshots

```bash
# Create snapshot
qm snapshot 800 before_changes

# Rollback snapshot
qm rollback 800 before_changes

# Delete snapshot
qm delsnapshot 800 before_changes
```

## Testing

### Verify Installation

```bash
# Check status
./scripts/check_status.sh

# Test Ansible connectivity
cd GOAD/ansible
ansible all -i ../ad/GOAD/data/inventory -m win_ping

# Test domain resolution
nslookup sevenkingdoms.local 192.168.50.10
```

### Connect to VMs

```bash
# RDP
xfreerdp /v:192.168.50.10 /u:administrator@sevenkingdoms.local /p:Password123!

# WinRM
evil-winrm -i 192.168.50.10 -u administrator -p 'Password123!' -d sevenkingdoms.local
```

## Troubleshooting

Common issues and solutions documented in:
- README.md - Troubleshooting section
- Installation logs in `logs/` directory
- Check status with `scripts/check_status.sh`

## Future Enhancements

Potential improvements:
- [ ] Automated Windows installation via Packer
- [ ] Support for multiple Proxmox clusters
- [ ] Automated WireGuard VPN setup
- [ ] Web-based installation dashboard
- [ ] Email/Slack notifications
- [ ] VM template pre-building
- [ ] Terraform provider support
- [ ] Multiple GOAD variant support in single installation

## Contributing

Contributions welcome:
1. Fork repository
2. Create feature branch
3. Make changes
4. Submit pull request

## License

MIT License - See LICENSE file

GOAD itself is maintained by Orange Cyberdefense under separate license.

## Support

- Documentation: README.md, QUICKSTART.md
- Status check: `./scripts/check_status.sh`
- Logs: `logs/goad_install_*.log`
- Issues: GitHub issue tracker

## Acknowledgments

- Orange Cyberdefense for GOAD
- Proxmox team for Proxmox VE
- Community contributors

---

**Project Status**: Production Ready ✅

**Last Updated**: November 2025

**Version**: 1.0.0
