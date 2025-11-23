# GOAD Installation Methods for Proxmox

This document explains the different methods to deploy GOAD on Proxmox and when to use each approach.

## Official GOAD Method (Terraform + Ansible)

GOAD officially supports Proxmox through their **built-in Terraform provider**. This is the recommended method for production use.

### Prerequisites

1. **Pre-built Windows Templates on Proxmox:**
   - `WinServer2019_x64` template
   - `WinServer2016_x64` template

2. **Terraform installed** on your control machine

3. **Ansible installed** with required collections

### Official Method Steps

```bash
# 1. Clone GOAD repository
git clone https://github.com/Orange-Cyberdefense/GOAD.git
cd GOAD

# 2. Install Python dependencies
./goad.sh -t install

# 3. Configure Proxmox provider
# Edit: ad/GOAD/providers/proxmox/terraform.tfvars
# Set your Proxmox credentials and settings

# 4. Provision infrastructure with Terraform
./goad.sh -t install -p proxmox -l GOAD

# 5. Configure with Ansible (automatic)
# GOAD will automatically run Ansible playbooks
```

### Advantages

✅ **Official Support** - Maintained by Orange Cyberdefense
✅ **Regular Updates** - Gets new features and bug fixes
✅ **Community Support** - Large user base
✅ **Pre-built Templates** - Faster deployment
✅ **Tested Configuration** - Proven to work

### Disadvantages

❌ **Requires Templates** - Must build Windows templates first
❌ **Terraform Knowledge** - Need to understand Terraform
❌ **Less Customization** - Harder to modify for specific needs

## Custom Installer Method (This Repository)

Our custom installer provides a **simplified, script-based approach** with more automation and customization options.

### Prerequisites

1. **Proxmox API Access** with token
2. **NFS Storage** configured
3. **Basic Linux knowledge**

### Custom Installer Steps

```bash
# 1. Clone this repository
git clone <this-repo>
cd goadeployer

# 2. Configure
cp goad_config.conf.example goad_config.conf
nano goad_config.conf

# 3. Run installer
./install_goad_proxmox.sh

# 4. Install Windows on VMs (manual or Packer)
# Follow on-screen instructions

# 5. Complete GOAD deployment
# Installer will run Ansible playbooks
```

### Advantages

✅ **No Templates Needed** - Can build from ISO
✅ **Automated Setup** - Network, NAT, everything configured
✅ **Easy Configuration** - Simple config file
✅ **Progress Tracking** - Real-time status and logs
✅ **Rollback Support** - Complete cleanup scripts
✅ **Status Monitoring** - Check installation progress
✅ **Better for Learning** - Understand each step

### Disadvantages

❌ **Manual Windows Install** - Unless using Packer
❌ **Longer Setup Time** - More steps involved
❌ **Third-party Tool** - Not officially supported

## Method Comparison

| Feature | Official GOAD | Custom Installer |
|---------|--------------|------------------|
| Setup Time | 2-3 hours | 4-6 hours |
| Templates Required | Yes | No |
| Terraform Required | Yes | No |
| Automation Level | High | Very High |
| Customization | Medium | High |
| Learning Curve | Medium | Low |
| Support | Official | Community |
| Updates | Automatic | Manual |

## Recommended Approach

### Use Official GOAD Method If:

- ✅ You have pre-built Windows templates
- ✅ You're familiar with Terraform
- ✅ You want official support
- ✅ You plan to update GOAD frequently
- ✅ You're deploying in production/team environment

### Use Custom Installer If:

- ✅ You're learning GOAD for the first time
- ✅ You don't have Windows templates
- ✅ You want complete automation (network, NAT, etc.)
- ✅ You need more customization
- ✅ You prefer bash scripts over Terraform
- ✅ You're doing a one-time setup

## Hybrid Approach

You can also combine both methods:

1. **Use our installer for network setup:**
   ```bash
   ./scripts/setup_network.sh
   ```

2. **Use official GOAD for VM provisioning:**
   ```bash
   cd GOAD
   ./goad.sh -t install -p proxmox -l GOAD
   ```

This gives you the best of both worlds: automated network setup + official VM provisioning.

## Building Windows Templates for Official Method

If you want to use the official method but don't have templates, you can build them:

### Option 1: Use Our Packer Templates

```bash
cd packer
packer build -var-file=proxmox.vars.hcl windows-server-2019.pkr.hcl
packer build -var-file=proxmox.vars.hcl windows-server-2016.pkr.hcl
```

### Option 2: Use Official Packer

GOAD includes Packer configurations:

```bash
cd GOAD/packer/proxmox
packer build -var-file=variables.pkrvars.hcl windows_server_2019.pkr.hcl
```

### Option 3: Manual Template Creation

1. Create a VM manually in Proxmox
2. Install Windows Server
3. Install VirtIO drivers
4. Install QEMU Guest Agent
5. Sysprep the system
6. Convert VM to template
7. Name it `WinServer2019_x64` or `WinServer2016_x64`

## VM Specifications (Official GOAD)

Both methods use these specifications:

| VM | OS | RAM | CPU | Disk | IP |
|----|----|----|-----|------|-----|
| DC01 | Win 2019 | 3 GB | 2 | 60 GB | .10 |
| DC02 | Win 2019 | 3 GB | 2 | 60 GB | .11 |
| DC03 | Win 2016 | 3 GB | 2 | 60 GB | .12 |
| SRV02 | Win 2019 | 6 GB | 2 | 60 GB | .22 |
| SRV03 | Win 2016 | 5 GB | 2 | 60 GB | .23 |

**Total:** 20 GB RAM, 10 cores, 300 GB disk

**Note:** SRV02 and SRV03 require more RAM because they run additional services:
- **SRV02:** MSSQL Server, IIS, ADCS
- **SRV03:** Various application services

## Network Configuration

Both methods use the same network configuration:

- **Subnet:** 192.168.50.0/24
- **Gateway:** 192.168.50.1
- **DNS:** 192.168.50.10 (DC01)
- **VLAN:** 50 (isolated network)

## Troubleshooting

### Official Method Issues

**Problem:** Templates not found

```bash
# List available templates
pvesh get /nodes/pve/qemu
# Build templates using Packer
```

**Problem:** Terraform errors

```bash
# Initialize Terraform
cd ad/GOAD/providers/proxmox
terraform init
terraform plan
```

### Custom Installer Issues

**Problem:** Network not accessible

```bash
# Check network setup
./scripts/check_status.sh
```

**Problem:** VMs not starting

```bash
# Check resources
pvesh get /nodes/pve/status
```

## Migration Between Methods

### From Custom Installer to Official GOAD

1. Keep VMs created by custom installer
2. Export VM configurations
3. Import into GOAD Terraform state
4. Run Ansible separately

### From Official GOAD to Custom Installer

1. Use existing VMs from GOAD deployment
2. Skip VM creation in custom installer
3. Run network setup only
4. Use GOAD's Ansible directly

## Support and Resources

### Official GOAD

- **Repository:** https://github.com/Orange-Cyberdefense/GOAD
- **Documentation:** https://github.com/Orange-Cyberdefense/GOAD/tree/main/docs
- **Issues:** https://github.com/Orange-Cyberdefense/GOAD/issues

### Custom Installer

- **Repository:** (this repository)
- **Documentation:** README.md, QUICKSTART.md
- **Issues:** (this repository issues)

## Conclusion

Both methods are valid and will result in a fully functional GOAD lab. Choose based on your:

- **Experience level** (Official for experts, Custom for beginners)
- **Time available** (Official is faster with templates)
- **Learning goals** (Custom for deep understanding)
- **Environment** (Official for production, Custom for personal use)

**Recommendation for you:** Given that you're using Proxmox 9.1 with NFS storage and this is your first time using GOAD, I recommend starting with the **custom installer** to understand the process, then migrate to the official method for future updates.

Happy hacking! 🎯
