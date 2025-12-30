# GOAD Proxmox - Quick Start Guide

Get your GOAD lab running in 5 steps!

## Prerequisites

- Proxmox VE 9.1 running
- NFS storage configured
- 96GB RAM, 20 CPU cores available
- 300GB free storage

## Installation Steps

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/goadeployer.git
cd goadeployer
```

### 2. Create Proxmox API Token

In Proxmox web UI:
1. Go to: **Datacenter → Permissions → API Tokens**
2. Click **Add**
3. Create token: `root@pam!goad`
4. **Copy the secret** (shown only once!)

### 3. Configure

```bash
cp goad_config.conf.example goad_config.conf
nano goad_config.conf
```

Update these values:
```bash
PROXMOX_HOST="YOUR_PROXMOX_IP"
PROXMOX_API_TOKEN_SECRET="YOUR_TOKEN_SECRET"
PROXMOX_STORAGE="YOUR_NFS_STORAGE_NAME"
```

### 4. Upload Windows ISOs

Download and upload to Proxmox storage (via web UI):
- Windows Server 2019 Evaluation ISO
- Windows Server 2016 Evaluation ISO
- VirtIO drivers ISO

Download links:
- WS2019: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019
- WS2016: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2016
- VirtIO: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

### 5. Run Installer

```bash
chmod +x install_goad_proxmox.sh scripts/*.sh
./install_goad_proxmox.sh
```

## What Happens Next?

The installer will:

1. ✅ Check prerequisites (Ansible, Python, etc.)
2. ✅ Create network bridge on VLAN 50
3. ✅ Create 5 VMs for GOAD
4. ✅ **Automatically install Windows using Packer** (takes 1-2 hours)
5. ✅ Configure WinRM automatically

## Windows Installation (Manual - Optional)

**Note:** By default, Windows installation is automated using Packer. If you prefer manual installation or Packer fails, use the `--manual` flag:

```bash
./scripts/provision_vms.sh --manual
```

For each VM (DC01, DC02, DC03, SRV02, SRV03):

1. Open VM console in Proxmox
2. Install Windows Server (Desktop Experience)
3. Load VirtIO drivers during disk selection (from 2nd CD-ROM)
4. Set Administrator password: `Password123!`
5. Configure static IP in PowerShell:

```powershell
# Example for DC01 (192.168.50.10)
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.10 -PrefixLength 24 -DefaultGateway 192.168.50.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.50.10

# Enable WinRM
winrm quickconfig -force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
```

**VM IP Addresses:**
- DC01: 192.168.50.10
- DC02: 192.168.50.11
- DC03: 192.168.50.12
- SRV02: 192.168.50.22
- SRV03: 192.168.50.23

## Continue GOAD Deployment

After automated Windows installation completes (or manual installation if using --manual flag):

**Option 1: Use the deployment script (Recommended)**
```bash
./deploy_goad.sh
```

**Option 2: Manual deployment**
```bash
cd GOAD/ansible
ansible-playbook -i ../ad/GOAD/data/inventory main.yml
```

This takes 1-2 hours. Go grab coffee! ☕

The deployment script will:
- ✅ Check prerequisites
- ✅ Generate Ansible inventory
- ✅ Test WinRM connectivity
- ✅ Deploy GOAD automatically

## Access Your Lab

### From Proxmox Host

```bash
# RDP to DC01
xfreerdp /v:192.168.50.10 /u:administrator@sevenkingdoms.local /p:Password123!

# WinRM to DC01
evil-winrm -i 192.168.50.10 -u administrator -p 'Password123!' -d sevenkingdoms.local
```

### From External Network

Set up WireGuard VPN - see `CONNECTION_GUIDE.md` after installation.

## Verify Installation

```bash
# Test Ansible connectivity
cd GOAD/ansible
ansible all -i ../ad/GOAD/data/inventory -m win_ping

# Should see SUCCESS for all 5 VMs
```

## Troubleshooting

**VMs won't start?**
```bash
# Check Proxmox resources
pvesh get /nodes/pve/status
```

**Can't connect to VMs?**
```bash
# Verify network
ip addr show vmbr50
ping 192.168.50.10
```

**WinRM not working?**
```bash
# Test from installer machine
nc -zv 192.168.50.10 5985
```

Check full documentation: [README.md](README.md)

## Need Help?

1. Check logs: `tail -f logs/goad_install_*.log`
2. See [README.md](README.md) Troubleshooting section
3. Review [GOAD documentation](https://github.com/Orange-Cyberdefense/GOAD)

## Cleanup

To remove everything:
```bash
./scripts/cleanup_goad.sh --complete
```

---

**Time Estimate**: 3-4 hours total (with Packer automation)
- Setup & VM creation: 30 min
- Windows installation: 1-2 hours (automated with Packer) or 2-3 hours (manual with --manual flag)
- GOAD deployment: 1-2 hours

**Happy Hacking! 🎯**
