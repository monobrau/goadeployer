# GOAD Proxmox Installer

> Automated deployment of [Game Of Active Directory (GOAD)](https://github.com/Orange-Cyberdefense/GOAD) on Proxmox VE 9.1

**GOAD** is a vulnerable Active Directory lab environment designed for penetration testing practice and learning AD attack techniques. This installer provides a simplified alternative to the [official Terraform-based method](https://github.com/Orange-Cyberdefense/GOAD) with enhanced automation.

[![Lab Type](https://img.shields.io/badge/Lab-5_VMs_|_2_Forests_|_3_Domains-blue)]()
[![RAM Required](https://img.shields.io/badge/RAM-20GB-orange)]()
[![Time](https://img.shields.io/badge/Setup_Time-4--6_hours-green)]()
[![Proxmox](https://img.shields.io/badge/Proxmox-9.1-red)]()

---

## 🎯 What You Get

| Component | Details |
|-----------|---------|
| **VMs** | 5 Windows Servers (2016/2019) |
| **Domains** | sevenkingdoms.local, north.sevenkingdoms.local, essos.local |
| **Network** | Isolated VLAN 50 (192.168.50.0/24) |
| **Vulnerabilities** | 25+ AD attack techniques (Kerberoasting, DCSync, etc.) |
| **Setup** | Fully automated with one command |

---

## ⚡ Quick Start

### Prerequisites
- Proxmox VE 9.1+ with NFS storage
- 20GB RAM minimum (96GB system recommended)
- 10 CPU cores minimum
- 300GB storage
- Windows Server ISOs (2016 & 2019)

### Installation (3 steps)

```bash
# 1. Clone and configure
git clone <this-repo>
cd goadeployer
cp goad_config.conf.example goad_config.conf
nano goad_config.conf  # Update: PROXMOX_HOST, API token, storage

# 2. Run installer
chmod +x install_goad_proxmox.sh scripts/*.sh
./install_goad_proxmox.sh

# 3. Check status
./scripts/check_status.sh
```

**That's it!** The installer handles network setup, VM creation, and GOAD deployment.

> 📘 **First time?** See [QUICKSTART.md](QUICKSTART.md) for detailed step-by-step guide.

---

## 📋 Installation Methods

<table>
<tr>
<th>This Installer</th>
<th>Official GOAD</th>
</tr>
<tr>
<td>

✅ No templates needed
✅ Complete automation
✅ Network auto-config
✅ Progress tracking
✅ Easy cleanup
✅ Better for learning

</td>
<td>

✅ Official support
✅ Faster (with templates)
✅ Regular updates
✅ Production-ready
✅ Terraform-based
✅ Community support

</td>
</tr>
<tr>
<td><b>Best for:</b> First-time users, learning</td>
<td><b>Best for:</b> Experienced users, teams</td>
</tr>
</table>

**Compare methods:** See [INSTALLATION_METHODS.md](INSTALLATION_METHODS.md)

---

## 🏗️ Lab Architecture

### VM Specifications
Based on official GOAD Proxmox provider:

| VM | Role | OS | IP | RAM | CPU | Disk |
|----|------|----|-------|-----|-----|------|
| **DC01** | Domain Controller | 2019 | 192.168.50.10 | 3GB | 2 | 60GB |
| **DC02** | Child DC (north.*) | 2019 | 192.168.50.11 | 3GB | 2 | 60GB |
| **DC03** | Domain Controller | 2016 | 192.168.50.12 | 3GB | 2 | 60GB |
| **SRV02** | MSSQL + IIS + ADCS | 2019 | 192.168.50.22 | 6GB* | 2 | 60GB |
| **SRV03** | Application Server | 2016 | 192.168.50.23 | 5GB* | 2 | 60GB |

**Total:** 20GB RAM, 10 cores, 300GB disk

> *SRV02/SRV03 need more RAM for database and application services

### Domain Structure

```
sevenkingdoms.local (Forest)
├── DC01 (Root DC)
└── north.sevenkingdoms.local (Child Domain)
    └── DC02 (Child DC)
    └── SRV02 (Server)

essos.local (Forest)
└── DC03 (Root DC)
    └── SRV03 (Server)

Trust: sevenkingdoms.local ↔ essos.local
```

### Network Topology

```
Internet → vmbr0 (NAT) → vmbr50 (VLAN 50) → GOAD VMs
           Proxmox       192.168.50.1/24     .10, .11, .12, .22, .23
```

---

## ⚙️ Configuration

### Minimal Config (Required)

Edit `goad_config.conf`:

```bash
# Proxmox connection
PROXMOX_HOST="192.168.1.100"      # Your Proxmox IP
PROXMOX_NODE="pve"                # Node name
PROXMOX_STORAGE="nfs-storage"     # Storage name

# API credentials (create in Proxmox UI)
PROXMOX_API_USER="root@pam!goad"
PROXMOX_API_TOKEN_SECRET="xxxx"   # From Proxmox API Tokens

# Network (defaults are fine for most users)
VLAN_ID="50"
NETWORK_SUBNET="192.168.50.0/24"
```

### Create API Token

In Proxmox Web UI:
1. **Datacenter → Permissions → API Tokens**
2. Click **Add**
3. User: `root@pam`, Token ID: `goad`
4. **Privilege Separation:** Uncheck ✓
5. Copy the secret (shown once!)

### Optional: Upload Windows ISOs

Download evaluation ISOs (180-day trial):
- [Windows Server 2019](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019)
- [Windows Server 2016](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2016)
- [VirtIO Drivers](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)

Upload via: **Proxmox → Node → Storage → ISO Images → Upload**

---

## 🚀 Usage

### Main Commands

```bash
# Install GOAD (full installation - creates VMs)
./install_goad_proxmox.sh

# Get Windows installation instructions
./setup_windows.sh

# Resume deployment after Windows installation
./deploy_goad.sh

# Check installation status
./scripts/check_status.sh

# Cleanup everything
./scripts/cleanup_goad.sh --complete
```

### Windows Installation

**IMPORTANT:** After the installer creates VMs, you MUST install Windows and configure WinRM BEFORE running `deploy_goad.sh`.

**Option 1: Use the Windows Setup Guide (Recommended)**
```bash
# Get step-by-step instructions
./setup_windows.sh
```

**Option 2: Manual Installation**

For each VM (DC01, DC02, DC03, SRV02, SRV03):

1. **Install Windows Server:**
   - Open VM console in Proxmox
   - Boot from Windows Server ISO
   - Select "Windows Server 20XX Standard Evaluation (Desktop Experience)"
   - **Load VirtIO drivers** when selecting disk (from 2nd CD-ROM)
   - Complete installation
   - Set Administrator password: `Password123!`

2. **Configure Static IP (PowerShell as Administrator):**
```powershell
# DC01 (192.168.50.10)
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.10 -PrefixLength 24 -DefaultGateway 192.168.50.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.10

# DC02 (192.168.50.11) - Use DC01 as DNS
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.11 -PrefixLength 24 -DefaultGateway 192.168.50.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.10

# DC03 (192.168.50.12) - Use itself as DNS
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.12 -PrefixLength 24 -DefaultGateway 192.168.50.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.12

# SRV02 (192.168.50.22) - Use DC01 as DNS
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.22 -PrefixLength 24 -DefaultGateway 192.168.50.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.10

# SRV03 (192.168.50.23) - Use DC03 as DNS
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.23 -PrefixLength 24 -DefaultGateway 192.168.50.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.12
```

3. **Enable WinRM (Required for Ansible):**
```powershell
winrm quickconfig -force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow
```

**VM IP Mapping:** DC01=.10, DC02=.11, DC03=.12, SRV02=.22, SRV03=.23

### Continue GOAD Deployment

**ONLY after Windows is installed and WinRM is enabled on ALL 5 VMs:**

```bash
# Run the deployment script to continue with GOAD setup
./deploy_goad.sh
```

This script will:
- ✅ Verify prerequisites (Ansible, GOAD repo, dependencies)
- ✅ Generate Ansible inventory
- ✅ Test WinRM connectivity to all VMs
- ✅ Deploy GOAD with Ansible (takes 1-2 hours)

**⚠️ Important:** The script will FAIL if Windows is not installed or WinRM is not configured. Make sure you've completed the Windows installation steps above first!

### Accessing Your Lab

**From Proxmox host:**
```bash
# RDP
xfreerdp /v:192.168.50.10 /u:administrator@sevenkingdoms.local /p:Password123!

# PowerShell Remoting
evil-winrm -i 192.168.50.10 -u administrator -p 'Password123!' -d sevenkingdoms.local
```

**From external network:** Set up WireGuard VPN (see [CONNECTION_GUIDE.md](CONNECTION_GUIDE.md))

---

## 🔧 Troubleshooting

<details>
<summary><b>API Connection Failed</b></summary>

```bash
# Test API connectivity
curl -k -H "Authorization: PVEAPIToken=root@pam!goad=your-token" \
  https://YOUR_PROXMOX_IP:8006/api2/json/version

# Check token has permissions (should see JSON response)
```
</details>

<details>
<summary><b>Insufficient Resources</b></summary>

```bash
# Check available resources
pvesh get /nodes/pve/status
free -h
df -h

# Reduce VM RAM in goad_config.conf if needed
```
</details>

<details>
<summary><b>Network Issues</b></summary>

```bash
# Verify bridge exists
ip link show vmbr50

# Check NAT rules
iptables -t nat -L -n -v | grep 192.168.50

# Test connectivity from Proxmox
ping 192.168.50.10
```
</details>

<details>
<summary><b>WinRM Connection Failed</b></summary>

```bash
# Test from installer machine
nc -zv 192.168.50.10 5985

# On Windows VM, check WinRM
winrm enumerate winrm/config/listener
Get-NetFirewallRule -Name "WinRM*"
```
</details>

<details>
<summary><b>Ansible Playbook Errors</b></summary>

```bash
# Test connectivity
cd GOAD/ansible
ansible all -i ../ad/GOAD/data/inventory -m win_ping

# Run with verbose output
ansible-playbook -i ../ad/GOAD/data/inventory main.yml -vvv
```
</details>

**More help:** Check `logs/goad_install_*.log` or [full troubleshooting guide](#detailed-troubleshooting)

---

## 🧹 Cleanup

```bash
# Complete removal (VMs + network + everything)
./scripts/cleanup_goad.sh --complete

# Interactive menu (choose what to remove)
./scripts/cleanup_goad.sh

# Remove only VMs
./scripts/cleanup_goad.sh --vms-only
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | Step-by-step beginner guide |
| [INSTALLATION_METHODS.md](INSTALLATION_METHODS.md) | Compare installation approaches |
| [OFFICIAL_GOAD_INTEGRATION.md](OFFICIAL_GOAD_INTEGRATION.md) | Technical details & compatibility |
| [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) | Architecture & components |
| [CONNECTION_GUIDE.md](CONNECTION_GUIDE.md) | VPN & remote access (auto-generated) |

---

## ❓ FAQ

**Q: How long does installation take?**
A: 4-6 hours total (mostly Windows installation). Automated parts take ~30 min.

**Q: Do I need Windows licenses?**
A: No, use evaluation editions (180-day trial).

**Q: Can I use local storage instead of NFS?**
A: Yes, set `PROXMOX_STORAGE="local-lvm"` in config.

**Q: Can I access from outside my network?**
A: Yes, via WireGuard VPN. See [CONNECTION_GUIDE.md](CONNECTION_GUIDE.md).

**Q: How do I update GOAD?**
A: `cd GOAD && git pull && cd ansible && ansible-playbook -i ../ad/GOAD/data/inventory main.yml`

**Q: Can I deploy GOAD-Light instead?**
A: Yes, edit `goad_config.conf`: `GOAD_VARIANT="GOAD-Light"` and adjust VM count.

**Q: What vulnerabilities are included?**
A: Kerberoasting, AS-REP Roasting, DCSync, Unconstrained Delegation, Constrained Delegation, NTLM Relay, GPP Passwords, ACL Abuse, and 20+ more.

---

## ⚠️ Security Warning

**GOAD is intentionally vulnerable!**

- ❌ **DO NOT** expose to the internet
- ❌ **DO NOT** connect to production networks
- ✅ **ONLY** access via secure VPN
- ✅ Keep isolated on VLAN 50

This is a learning environment for authorized penetration testing practice only.

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

---

## 📄 License

MIT License - See [LICENSE](LICENSE)

GOAD itself: © Orange Cyberdefense (separate license)

---

## 🙏 Acknowledgments

- **[Orange Cyberdefense](https://github.com/Orange-Cyberdefense)** for creating GOAD
- **Proxmox** team for Proxmox VE
- All contributors

---

## 🔗 Resources

- [Official GOAD Repository](https://github.com/Orange-Cyberdefense/GOAD)
- [GOAD Documentation](https://github.com/Orange-Cyberdefense/GOAD/wiki)
- [Proxmox Documentation](https://pve.proxmox.com/pve-docs/)
- [WireGuard Quick Start](https://www.wireguard.com/quickstart/)

---

<div align="center">

**Happy Hacking! 🎯**

*Practice safely. Test ethically. Learn continuously.*

</div>

---

## 📖 Detailed Sections

<details>
<summary><b>Detailed Installation Steps</b></summary>

### Phase 1: Pre-Installation

1. **Verify Proxmox Resources**
   ```bash
   pvesh get /nodes/pve/status
   ```

2. **Configure NFS Storage** (if not already done)
   ```bash
   pvesm add nfs nfs-storage --server 192.168.1.50 --export /mnt/nfs --content images,vztmpl,iso
   ```

3. **Upload ISOs** to Proxmox storage

### Phase 2: Automated Setup

The installer automatically:
- ✅ Checks prerequisites (Ansible, Python, etc.)
- ✅ Creates VLAN 50 bridge (vmbr50)
- ✅ Configures NAT for internet access
- ✅ Downloads GOAD repository
- ✅ Creates 5 VMs with proper specs
- ✅ Generates Ansible inventory

### Phase 3: Windows Installation

**Manual Installation (2-3 hours):**
Repeat for each VM (DC01, DC02, DC03, SRV02, SRV03):

1. Access VM console in Proxmox
2. Boot from Windows ISO
3. Select "Windows Server 20XX Standard Evaluation (Desktop Experience)"
4. **Load VirtIO drivers** when selecting disk (from 2nd CD-ROM)
5. Complete Windows installation
6. Set Administrator password: `Password123!`
7. Configure static IP (see PowerShell commands above)
8. Enable WinRM (see PowerShell commands above)

**Automated Installation with Packer (1 hour):**
```bash
cd packer
packer build windows-server-2019.pkr.hcl
```

### Phase 4: GOAD Deployment

Once all VMs are ready with WinRM enabled:

```bash
cd GOAD/ansible
ansible-playbook -i ../ad/GOAD/data/inventory main.yml
```

This takes 1-2 hours and:
- Creates AD domains and forests
- Establishes trust relationships
- Creates users, groups, OUs
- Configures vulnerable settings
- Installs MSSQL, IIS, ADCS
- Sets up file shares and services

### Phase 5: Verification

```bash
# Check all VMs are reachable
./scripts/check_status.sh

# Test Ansible connectivity
cd GOAD/ansible
ansible all -i ../ad/GOAD/data/inventory -m win_ping

# Test domain resolution
nslookup sevenkingdoms.local 192.168.50.10
```

</details>

<details>
<summary><b>Detailed Troubleshooting</b></summary>

### Installer Issues

**Prerequisite installation fails:**
```bash
# Manually install dependencies
apt update
apt install -y ansible git curl jq sshpass python3 python3-pip
pip3 install proxmoxer requests pywinrm
```

**GOAD repository clone fails:**
```bash
# Check internet connectivity
ping github.com

# Clone manually
git clone https://github.com/Orange-Cyberdefense/GOAD.git
```

### Network Issues

**Bridge creation fails:**
```bash
# Check if bridge already exists
ip link show vmbr50

# Manually create bridge
cat >> /etc/network/interfaces << EOF
auto vmbr50
iface vmbr50 inet static
    address 192.168.50.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
EOF
ifup vmbr50
```

**NAT not working:**
```bash
# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1

# Add NAT rule
iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -o vmbr0 -j MASQUERADE
iptables -A FORWARD -i vmbr50 -o vmbr0 -j ACCEPT
iptables -A FORWARD -i vmbr0 -o vmbr50 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save rules
apt install iptables-persistent
iptables-save > /etc/iptables/rules.v4
```

### VM Issues

**VM won't start:**
```bash
# Check VM status
qm status 800

# Check VM config
qm config 800

# Check storage
pvesm status
```

**Cannot access VM console:**
```bash
# Restart VM
qm stop 800
qm start 800

# Check QEMU process
ps aux | grep kvm
```

**Windows installation loops:**
- Remove installation ISO from VM config
- Only keep VirtIO ISO attached

### GOAD Deployment Issues

**Ansible timeout:**
```bash
# Increase timeouts in ansible.cfg
[defaults]
timeout = 3600

[winrm]
operation_timeout_sec = 600
read_timeout_sec = 700
```

**Domain creation fails:**
```powershell
# On DC01, check DC promotion
Get-WindowsFeature AD-Domain-Services
Get-ADDomainController
```

**Trust relationship fails:**
```powershell
# On DC01
nltest /domain_trusts
nltest /sc_query:essos.local

# Reset trust if needed
netdom trust sevenkingdoms.local /d:essos.local /remove
```

**Services not starting:**
```bash
# Check Ansible logs
tail -f logs/goad_install_*.log

# Verify services on Windows
Get-Service | Where-Object {$_.Name -like "*SQL*"}
Get-Website
```

</details>

<details>
<summary><b>Advanced Configuration</b></summary>

### Custom Network Range

Edit `goad_config.conf`:
```bash
NETWORK_SUBNET="10.0.50.0/24"
NETWORK_GATEWAY="10.0.50.1"
DC01_IP="10.0.50.10"
DC02_IP="10.0.50.11"
DC03_IP="10.0.50.12"
SRV02_IP="10.0.50.22"
SRV03_IP="10.0.50.23"
NETWORK_DNS="10.0.50.10"
```

### Custom VM Resources

```bash
# Reduce RAM (minimum viable)
DC01_MEMORY="2048"
DC02_MEMORY="2048"
DC03_MEMORY="2048"
SRV02_MEMORY="4096"
SRV03_MEMORY="4096"

# Increase CPU for faster deployment
DC01_CORES="4"
SRV02_CORES="4"
```

### Multiple GOAD Instances

To run multiple GOAD labs:

```bash
# Instance 1: VLAN 50, IPs .50.x
VLAN_ID="50"
NETWORK_SUBNET="192.168.50.0/24"
VM_ID_START="800"

# Instance 2: VLAN 60, IPs .60.x
VLAN_ID="60"
NETWORK_SUBNET="192.168.60.0/24"
VM_ID_START="900"
```

### WireGuard VPN Setup

**On Proxmox host:**
```bash
# Install WireGuard
apt install wireguard

# Generate keys
wg genkey | tee privatekey | wg pubkey > publickey

# Configure
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = $(cat privatekey)

PostUp = iptables -A FORWARD -i wg0 -o vmbr50 -j ACCEPT
PostUp = iptables -A FORWARD -i vmbr50 -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o vmbr50 -j MASQUERADE

[Peer]
PublicKey = <CLIENT_PUBLIC_KEY>
AllowedIPs = 10.0.0.2/32
EOF

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
```

**Client configuration:**
```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.0.2/24

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = YOUR_PROXMOX_IP:51820
AllowedIPs = 10.0.0.0/24, 192.168.50.0/24
PersistentKeepalive = 25
```

### Packer Automation

Build Windows templates automatically:

```bash
cd packer

# Create variables file
cat > proxmox.vars.hcl << EOF
proxmox_host = "192.168.1.100"
proxmox_node = "pve"
proxmox_api_user = "root@pam!goad"
proxmox_api_token = "your-token-here"
EOF

# Build templates
packer build -var-file=proxmox.vars.hcl windows-server-2019.pkr.hcl
packer build -var-file=proxmox.vars.hcl windows-server-2016.pkr.hcl
```

### Integration with Official GOAD

Use our network setup with official GOAD Terraform:

```bash
# 1. Use our network setup
./scripts/setup_network.sh

# 2. Switch to official GOAD
cd /path/to/GOAD
./goad.sh -t install -p proxmox -l GOAD

# 3. Use our status checker
cd /path/to/goadeployer
./scripts/check_status.sh
```

</details>
