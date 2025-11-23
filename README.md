# GOAD Proxmox Installer

Automated installation and configuration script for deploying [Game Of Active Directory (GOAD)](https://github.com/Orange-Cyberdefense/GOAD) on Proxmox VE 9.1.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Configuration](#configuration)
- [Network Architecture](#network-architecture)
- [VM Details](#vm-details)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [FAQ](#faq)

## Overview

This project provides a complete automation suite for deploying the GOAD (Game Of Active Directory) vulnerable Active Directory lab environment on Proxmox VE. GOAD is designed for penetration testing practice and learning Active Directory attack techniques.

> **Official GOAD Repository:** https://github.com/Orange-Cyberdefense/GOAD

The full GOAD lab consists of:
- **5 Windows VMs** across **2 forests** and **3 domains**
- Realistic Active Directory misconfigurations
- Multiple attack vectors for practice
- Isolated network environment

### Installation Methods

GOAD officially supports Proxmox through their Terraform provider. This repository provides an **alternative installation method** with enhanced automation and ease of use for beginners. See [INSTALLATION_METHODS.md](INSTALLATION_METHODS.md) for a comparison of approaches.

## Features

- ✅ **Automated Installation**: Complete automation from start to finish
- ✅ **Prerequisites Check**: Validates system requirements before installation
- ✅ **Network Configuration**: Automatic VLAN and bridge setup
- ✅ **VM Provisioning**: Creates and configures all required VMs
- ✅ **Progress Tracking**: Real-time installation progress with logs
- ✅ **Rollback Support**: Complete cleanup/rollback functionality
- ✅ **WireGuard VPN**: Guides for secure external access
- ✅ **Comprehensive Logging**: Detailed logs for troubleshooting
- ✅ **Configuration File**: Easy customization via config file

## Requirements

### Hardware Requirements

- **CPU**: 20+ cores recommended (10 cores minimum)
- **RAM**: 96GB total (20GB minimum for GOAD VMs + overhead)
  - Based on official GOAD specs: DC01(3GB) + DC02(3GB) + DC03(3GB) + SRV02(6GB) + SRV03(5GB) = 20GB
- **Storage**: 300GB free space on NFS storage
- **Network**: Dedicated network interface for VLAN 50

> **Note:** RAM requirements are based on the official GOAD Proxmox provider specifications. SRV02 and SRV03 require more RAM than DCs due to running MSSQL, IIS, and other services.

### Software Requirements

- **Proxmox VE**: Version 9.1 or later
- **Operating System**: Debian-based Linux for control machine
- **Network**: NFS storage configured on Proxmox

### Control Machine Requirements

The machine running the installer needs:
- Ansible 2.9+
- Python 3.8+
- Git
- curl, jq
- sshpass
- Proxmox API access

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/goadeployer.git
cd goadeployer
```

### 2. Configure Proxmox API Access

First, create an API token in Proxmox:

1. Login to Proxmox web interface
2. Navigate to: **Datacenter → Permissions → API Tokens**
3. Click **Add** and create a token named `goad` for user `root@pam`
4. **Important**: Copy the token secret, it's only shown once!
5. Set permissions: **Datacenter → Permissions → Add → User Permission**
   - Path: `/`
   - User: `root@pam`
   - Role: `Administrator`

### 3. Create Configuration File

```bash
cp goad_config.conf.example goad_config.conf
nano goad_config.conf
```

Update the following required values:

```bash
PROXMOX_HOST="192.168.1.100"          # Your Proxmox IP
PROXMOX_NODE="pve"                    # Your Proxmox node name
PROXMOX_API_USER="root@pam!goad"
PROXMOX_API_TOKEN_SECRET="your-secret-here"  # From step 2
PROXMOX_STORAGE="nfs-storage"         # Your NFS storage name
```

### 4. Run the Installer

```bash
chmod +x install_goad_proxmox.sh
chmod +x scripts/*.sh
./install_goad_proxmox.sh
```

The installer will:
1. ✅ Check prerequisites
2. ✅ Setup network (VLAN 50, bridge vmbr50)
3. ✅ Download GOAD repository
4. ✅ Create 5 VMs
5. ✅ Provide Windows installation instructions
6. ⏳ Deploy GOAD with Ansible (after Windows installation)

## Detailed Installation

### Phase 1: Preparation

1. **Verify Proxmox Resources**
   ```bash
   # On Proxmox host, check available resources
   pvesh get /nodes/pve/status
   ```

2. **Configure NFS Storage**

   If you haven't already configured NFS storage:
   ```bash
   # Example: Add NFS storage via CLI
   pvesm add nfs nfs-storage --server 192.168.1.50 --export /mnt/nfs --content images,vztmpl,iso
   ```

3. **Upload Windows ISOs**

   Download Windows Server evaluation ISOs:
   - [Windows Server 2019](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019)
   - [Windows Server 2016](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2016)
   - [VirtIO Drivers](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)

   Upload to Proxmox: **Node → Storage → ISO Images → Upload**

### Phase 2: Network Setup

The installer automatically creates:

```
┌─────────────────────────────────────────┐
│         Internet                        │
└───────────┬─────────────────────────────┘
            │
     ┌──────▼──────┐
     │   vmbr0     │  (Main bridge)
     │  (NAT out)  │
     └──────┬──────┘
            │
     ┌──────▼──────┐
     │   vmbr50    │  (GOAD bridge)
     │  VLAN 50    │
     │ 192.168.50.1│
     └──────┬──────┘
            │
    ┌───────┴────────┬──────┬──────┬──────┐
    │                │      │      │      │
┌───▼───┐   ┌───▼───┐ ┌──▼──┐ ┌──▼──┐ ┌──▼──┐
│ DC01  │   │ DC02  │ │DC03 │ │SRV02│ │SRV03│
│ .10   │   │ .11   │ │.12  │ │ .22 │ │ .23 │
└───────┘   └───────┘ └─────┘ └─────┘ └─────┘
```

### Phase 3: Windows Installation

After VM creation, you need to install Windows on each VM. Two options:

#### Option A: Manual Installation (Recommended for beginners)

1. **Access VM Console** via Proxmox web UI
2. **Install Windows Server**:
   - Select "Windows Server 2019 Standard Evaluation (Desktop Experience)"
   - During disk selection, load VirtIO drivers from second CD-ROM
   - Complete installation
3. **Configure Network** with static IP:
   ```powershell
   # In Windows PowerShell (run as Administrator)
   New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.10 -PrefixLength 24 -DefaultGateway 192.168.50.1
   Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.10
   ```
4. **Enable WinRM**:
   ```powershell
   winrm quickconfig -force
   Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
   Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
   New-NetFirewallRule -Name "WinRM HTTP" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5985
   ```
5. **Set Administrator Password**: `Password123!`

Repeat for all 5 VMs with their respective IP addresses.

#### Option B: Automated with Packer

```bash
cd packer

# Install Packer
wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip
unzip packer_1.9.4_linux_amd64.zip
sudo mv packer /usr/local/bin/

# Build Windows Server 2019 template
packer build -var "proxmox_host=${PROXMOX_HOST}" \
             -var "proxmox_node=${PROXMOX_NODE}" \
             -var "proxmox_api_user=${PROXMOX_API_USER}" \
             -var "proxmox_api_token=${PROXMOX_API_TOKEN_SECRET}" \
             windows-server-2019.pkr.hcl
```

### Phase 4: GOAD Deployment

Once all VMs have Windows installed and WinRM enabled:

```bash
# Resume installation (if you stopped after Windows installation)
./install_goad_proxmox.sh --skip-vm-creation

# Or manually run GOAD provisioning
cd GOAD/ansible
ansible-playbook -i ../ad/GOAD/data/inventory main.yml
```

This phase takes **1-2 hours** and will:
- Configure Active Directory domains
- Create users, groups, and organizational units
- Set up vulnerable configurations
- Configure trust relationships

## Configuration

### Main Configuration File: `goad_config.conf`

Key configuration options:

```bash
# Proxmox Settings
PROXMOX_HOST="192.168.1.100"
PROXMOX_NODE="pve"
PROXMOX_STORAGE="nfs-storage"

# Network Settings
VLAN_ID="50"
BRIDGE_NAME="vmbr50"
NETWORK_SUBNET="192.168.50.0/24"
NETWORK_GATEWAY="192.168.50.1"

# VM Resources
DC01_CORES="2"
DC01_MEMORY="4096"
DC01_DISK_SIZE="60G"

# Security
WINDOWS_ADMIN_PASSWORD="Password123!"
```

### VM Specifications

Based on official GOAD Proxmox provider:

| VM    | Role                          | OS      | IP             | RAM  | CPU | Disk |
|-------|-------------------------------|---------|----------------|------|-----|------|
| DC01  | Domain Controller (SK)        | 2019    | 192.168.50.10  | 3GB  | 2   | 60GB |
| DC02  | Domain Controller (North.SK)  | 2019    | 192.168.50.11  | 3GB  | 2   | 60GB |
| DC03  | Domain Controller (Essos)     | 2016    | 192.168.50.12  | 3GB  | 2   | 60GB |
| SRV02 | Server (SK) - MSSQL, IIS      | 2019    | 192.168.50.22  | 6GB* | 2   | 60GB |
| SRV03 | Server (Essos) - Services     | 2016    | 192.168.50.23  | 5GB* | 2   | 60GB |

**Total**: 20GB RAM, 10 CPU cores, 300GB disk

*SRV02 and SRV03 require more RAM for running MSSQL Server, IIS, and application services.

## Network Architecture

### VLAN 50 Details

- **Network**: 192.168.50.0/24
- **Gateway**: 192.168.50.1 (vmbr50 on Proxmox)
- **DNS**: 192.168.50.10 (DC01)
- **DHCP**: Disabled (static IPs only)

### Internet Access

NAT is configured from vmbr50 → vmbr0 for:
- Windows updates during installation
- Downloading required tools
- GOAD provisioning

### External Access via WireGuard

See [CONNECTION_GUIDE.md](CONNECTION_GUIDE.md) for WireGuard VPN setup.

## VM Details

### Domain Structure

```
Forest: sevenkingdoms.local
├── Domain: sevenkingdoms.local (DC01)
└── Child Domain: north.sevenkingdoms.local (DC02)

Forest: essos.local
└── Domain: essos.local (DC03)

Forest Trust: sevenkingdoms.local ↔ essos.local
```

### Default Credentials

| Account | Username | Password | Domain |
|---------|----------|----------|--------|
| Domain Admin | administrator | Password123! | sevenkingdoms.local |
| Domain Admin | administrator | Password123! | essos.local |

**Note**: GOAD creates many additional users with various privilege levels. See GOAD documentation for complete user list.

### Attack Vectors

The GOAD lab includes vulnerabilities such as:
- Kerberoasting
- AS-REP Roasting
- DCSync
- Unconstrained Delegation
- Constrained Delegation
- NTLM Relay
- GPP Passwords
- ACL Abuse
- And many more...

## Troubleshooting

### Installation Issues

**Problem**: Cannot connect to Proxmox API

```bash
# Test API connectivity
curl -k -H "Authorization: PVEAPIToken=root@pam!goad=your-token" \
  https://192.168.50.1:8006/api2/json/version
```

**Problem**: Insufficient resources

```bash
# Check Proxmox resources
pvesh get /nodes/pve/status
free -h
df -h
```

**Problem**: Network not accessible

```bash
# On Proxmox host
ip link show vmbr50
ip addr show vmbr50
iptables -t nat -L -n -v
```

### VM Issues

**Problem**: Cannot connect to VMs via WinRM

```bash
# Test WinRM connectivity
nc -zv 192.168.50.10 5985

# From Windows VM, verify WinRM
winrm enumerate winrm/config/listener
```

**Problem**: VMs cannot reach internet

```bash
# On Proxmox host, verify NAT
iptables -t nat -L POSTROUTING -n -v
cat /proc/sys/net/ipv4/ip_forward  # Should be 1
```

### GOAD Deployment Issues

**Problem**: Ansible playbook fails

```bash
# Check Ansible connectivity
cd GOAD/ansible
ansible all -i ../ad/GOAD/data/inventory -m win_ping

# Enable verbose output
ansible-playbook -i ../ad/GOAD/data/inventory main.yml -vvv
```

**Problem**: Domain trust issues

```powershell
# On DC01, verify trust
nltest /domain_trusts
```

### Logs

Check installation logs:
```bash
# Latest installation log
ls -lt logs/
tail -f logs/goad_install_YYYYMMDD_HHMMSS.log
```

## Cleanup

### Complete Cleanup

Remove everything (VMs, network, configuration):

```bash
./scripts/cleanup_goad.sh --complete
```

### Selective Cleanup

Interactive menu for selective cleanup:

```bash
./scripts/cleanup_goad.sh
```

Options:
1. Complete cleanup
2. Remove VMs only
3. Remove network configuration only
4. Remove GOAD repository only
5. Remove log files only

### Manual Cleanup

If scripts fail, manual cleanup:

```bash
# Delete VMs
for vmid in {800..804}; do
  qm stop $vmid
  qm destroy $vmid
done

# Remove bridge
ip link set vmbr50 down
ip link delete vmbr50

# Remove NAT rules
iptables -t nat -D POSTROUTING -s 192.168.50.0/24 -o vmbr0 -j MASQUERADE
```

## FAQ

### Q: How long does installation take?

**A**:
- VM creation: ~15 minutes
- Windows installation (manual): ~30 minutes per VM = 2.5 hours
- Windows installation (Packer): ~1 hour
- GOAD provisioning: 1-2 hours

**Total**: 4-6 hours depending on method

### Q: Can I use a different network subnet?

**A**: Yes, edit `goad_config.conf` and change `NETWORK_SUBNET`, `NETWORK_GATEWAY`, and all VM IP addresses.

### Q: Can I run this on a different Proxmox version?

**A**: The scripts are designed for Proxmox 9.1 but should work on 8.x with minor modifications.

### Q: Do I need a license for Windows Server?

**A**: No, you can use Windows Server Evaluation editions (180-day trial).

### Q: Can I access the lab from outside my network?

**A**: Yes, set up WireGuard VPN. See [CONNECTION_GUIDE.md](CONNECTION_GUIDE.md).

### Q: How do I update GOAD?

**A**:
```bash
cd GOAD
git pull
cd ansible
ansible-playbook -i ../ad/GOAD/data/inventory main.yml
```

### Q: Can I create GOAD-Light instead?

**A**: Yes, edit `goad_config.conf` and change `GOAD_VARIANT="GOAD-Light"`, then adjust VM configurations.

### Q: What if I want to use local storage instead of NFS?

**A**: Change `PROXMOX_STORAGE="local-lvm"` in `goad_config.conf`.

## Security Warning

⚠️ **IMPORTANT**: GOAD is a **vulnerable-by-design** environment for penetration testing practice.

- **DO NOT** expose to the internet
- **DO NOT** connect to production networks
- **ONLY** access via secure VPN
- Keep it isolated in VLAN 50

## Resources

- [GOAD GitHub Repository](https://github.com/Orange-Cyberdefense/GOAD)
- [GOAD Documentation](https://github.com/Orange-Cyberdefense/GOAD/wiki)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [WireGuard Documentation](https://www.wireguard.com/quickstart/)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is provided as-is under the MIT License.

GOAD itself is maintained by Orange Cyberdefense and has its own license.

## Support

For issues:
1. Check [Troubleshooting](#troubleshooting) section
2. Review logs in `logs/` directory
3. Open an issue on GitHub

## Acknowledgments

- **Orange Cyberdefense** for creating GOAD
- **Proxmox** team for Proxmox VE
- All contributors to this project

---

**Happy Hacking! 🎯**

*Remember: This is a learning environment. Always practice ethical hacking and obtain proper authorization before testing real systems.*
