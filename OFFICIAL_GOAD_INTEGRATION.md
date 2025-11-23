# Official GOAD Integration Notes

This document summarizes the integration of official GOAD specifications into our custom Proxmox installer.

## Official GOAD Analysis

After reviewing the official GOAD repository (https://github.com/Orange-Cyberdefense/GOAD), I've identified the following:

### Official Proxmox Support

GOAD **officially supports Proxmox** through:
- **Provider:** `ad/GOAD/providers/proxmox/`
- **Method:** Terraform + Ansible
- **Files:**
  - `windows.tf` - Terraform VM definitions
  - `inventory` - Ansible inventory template

### Official VM Specifications

From `ad/GOAD/providers/proxmox/windows.tf`:

```hcl
DC01:  2 cores, 3096 MB RAM, Windows Server 2019
DC02:  2 cores, 3096 MB RAM, Windows Server 2019
DC03:  2 cores, 3096 MB RAM, Windows Server 2016
SRV02: 2 cores, 6240 MB RAM, Windows Server 2019
SRV03: 2 cores, 5120 MB RAM, Windows Server 2016
```

**Total:** 20,648 MB (≈20.2 GB) RAM

### Key Differences from Initial Implementation

| Component | Initial Spec | Official Spec | Change |
|-----------|-------------|---------------|--------|
| DC01 RAM | 4096 MB | 3096 MB | -1 GB ✅ |
| DC02 RAM | 4096 MB | 3096 MB | -1 GB ✅ |
| DC03 RAM | 4096 MB | 3096 MB | -1 GB ✅ |
| DC03 OS | Win 2019 | Win 2016 | Changed ✅ |
| SRV02 RAM | 4096 MB | 6240 MB | +2.1 GB ✅ |
| SRV03 RAM | 4096 MB | 5120 MB | +1 GB ✅ |
| SRV03 OS | Win 2019 | Win 2016 | Changed ✅ |
| **Total RAM** | **20 GB** | **20.2 GB** | +0.2 GB |

### Why the Different Allocations?

**Domain Controllers (3 GB each):**
- Run only AD DS services
- Minimal memory footprint
- 3 GB is sufficient for DC operations

**SRV02 (6 GB):**
- Runs **MSSQL Server** (memory-intensive)
- Hosts **IIS** web services
- Runs **ADCS** (Certificate Services)
- Hosts various web applications
- Needs significantly more RAM

**SRV03 (5 GB):**
- Runs multiple application services
- Hosts file shares
- Various background services
- Moderate RAM requirements

## Changes Made to Custom Installer

### 1. Configuration File Updates

**File:** `goad_config.conf.example`

```bash
# Updated specs (lines 59-109)
DC01_MEMORY="3096"    # Was: 4096
DC02_MEMORY="3096"    # Was: 4096
DC03_MEMORY="3096"    # Was: 4096
DC03_OS_TYPE="win2016"  # Was: win2019
SRV02_MEMORY="6240"   # Was: 4096 - CRITICAL for MSSQL
SRV03_MEMORY="5120"   # Was: 4096
SRV03_OS_TYPE="win2016" # Was: win2019
```

### 2. Documentation Updates

**README.md:**
- Added official GOAD repository link
- Updated hardware requirements (96GB → 20GB minimum)
- Added VM specifications table with OS versions
- Added notes about service requirements
- Clarified why SRV02/SRV03 need more RAM

### 3. New Documentation

**INSTALLATION_METHODS.md:**
Comprehensive guide comparing:
- Official GOAD method (Terraform + Ansible)
- Custom installer method (Bash scripts)
- Hybrid approach options
- When to use each method
- Template building instructions

## Official GOAD Deployment Method

### Prerequisites for Official Method

1. **Windows Templates on Proxmox:**
   - `WinServer2019_x64` template (VMID 9000 or similar)
   - `WinServer2016_x64` template (VMID 9001 or similar)

2. **Software:**
   - Terraform installed
   - Ansible installed
   - Python 3.8+

### Official Deployment Steps

```bash
# 1. Clone GOAD
git clone https://github.com/Orange-Cyberdefense/GOAD.git
cd GOAD

# 2. Install dependencies
./goad.sh -t install

# 3. Configure Proxmox provider
# Edit ad/GOAD/providers/proxmox/terraform.tfvars

# 4. Deploy
./goad.sh -t install -p proxmox -l GOAD
```

## Integration Strategy

Our custom installer now:

1. ✅ **Uses official VM specifications**
2. ✅ **Documents official method** in INSTALLATION_METHODS.md
3. ✅ **Provides alternative approach** with better automation
4. ✅ **Maintains compatibility** with official Ansible playbooks
5. ✅ **Offers flexibility** for users without templates

## Recommendation Matrix

| Scenario | Recommended Method |
|----------|-------------------|
| Have Windows templates | Official GOAD |
| First time user | Custom Installer |
| Quick deployment | Official GOAD |
| Learning focused | Custom Installer |
| Need customization | Custom Installer |
| Production/team use | Official GOAD |
| No Terraform experience | Custom Installer |
| Want official support | Official GOAD |

## Benefits of Our Approach

While GOAD officially supports Proxmox, our custom installer adds:

1. **Network Automation**
   - Automatic VLAN creation
   - NAT configuration
   - Bridge setup
   - iptables rules

2. **No Template Dependency**
   - Can build from ISO
   - Packer templates included
   - Step-by-step instructions

3. **Progress Tracking**
   - Real-time logs
   - Status checker
   - Progress indicators

4. **Rollback Support**
   - Complete cleanup
   - Selective removal
   - Safe deletion

5. **Better for Beginners**
   - Simpler configuration
   - Guided installation
   - Comprehensive docs

## Compatibility with Official GOAD

Our installer is **fully compatible** with official GOAD:

- ✅ Same VM specifications
- ✅ Same IP addressing scheme
- ✅ Same network configuration
- ✅ Compatible with GOAD Ansible playbooks
- ✅ Can use official updates

### Using Official GOAD Ansible

After our installer creates VMs:

```bash
# Skip to official GOAD Ansible deployment
cd GOAD/ansible
ansible-playbook -i ../ad/GOAD/data/inventory main.yml
```

## Network Configuration Compatibility

Both methods use identical network setup:

```
Network: 192.168.50.0/24
Gateway: 192.168.50.1
DNS:     192.168.50.10 (DC01)

DC01:  192.168.50.10
DC02:  192.168.50.11
DC03:  192.168.50.12
SRV02: 192.168.50.22
SRV03: 192.168.50.23
```

## Future Updates

To stay aligned with official GOAD:

1. **Monitor Official Repository**
   ```bash
   cd GOAD
   git pull
   ```

2. **Update Specs if Changed**
   - Check `ad/GOAD/providers/proxmox/windows.tf`
   - Update our `goad_config.conf.example`

3. **Test Compatibility**
   - Run status checker
   - Verify Ansible playbooks work
   - Test all VMs

## Migration Path

### From Custom Installer to Official GOAD

```bash
# 1. Use our network setup
./scripts/setup_network.sh

# 2. Create templates from our VMs
qm template <vmid>

# 3. Switch to official GOAD
cd GOAD
./goad.sh -t install -p proxmox -l GOAD
```

### From Official GOAD to Custom Installer

```bash
# 1. Keep existing VMs
# 2. Run our network setup only
./scripts/setup_network.sh

# 3. Use our status checker
./scripts/check_status.sh
```

## Acknowledgments

- **Orange Cyberdefense** for creating and maintaining GOAD
- Official GOAD contributors
- Proxmox community

## References

- **GOAD Repository:** https://github.com/Orange-Cyberdefense/GOAD
- **Proxmox Provider:** https://github.com/Orange-Cyberdefense/GOAD/tree/main/ad/GOAD/providers/proxmox
- **GOAD Documentation:** https://github.com/Orange-Cyberdefense/GOAD/tree/main/docs

---

**Updated:** November 2025
**Version:** 1.1.0
**Status:** Aligned with Official GOAD Specs ✅
