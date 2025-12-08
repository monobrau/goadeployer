#!/usr/bin/env pwsh
# WinRM Setup Script for GOAD Lab
# This script configures WinRM on Windows VMs for Ansible connectivity

param(
    [string]$Password = "Password123!",
    [switch]$SkipFirewall = $false
)

Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           GOAD Lab - WinRM Configuration Script              ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "[INFO] Configuring WinRM..." -ForegroundColor Green
Write-Host ""

# Step 1: Enable WinRM service
Write-Host "[STEP 1/6] Enabling WinRM service..." -ForegroundColor Yellow
try {
    winrm quickconfig -force -q
    Write-Host "[SUCCESS] WinRM service enabled" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to enable WinRM service: $_" -ForegroundColor Red
    exit 1
}

# Step 2: Configure WinRM to allow unencrypted traffic (required for Ansible)
Write-Host "[STEP 2/6] Configuring WinRM to allow unencrypted traffic..." -ForegroundColor Yellow
try {
    winrm set winrm/config/service '@{AllowUnencrypted="true"}' | Out-Null
    Write-Host "[SUCCESS] Unencrypted traffic enabled" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to configure unencrypted traffic: $_" -ForegroundColor Red
    exit 1
}

# Step 3: Enable Basic authentication
Write-Host "[STEP 3/6] Enabling Basic authentication..." -ForegroundColor Yellow
try {
    winrm set winrm/config/service/auth '@{Basic="true"}' | Out-Null
    Write-Host "[SUCCESS] Basic authentication enabled" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to enable Basic authentication: $_" -ForegroundColor Red
    exit 1
}

# Step 4: Increase memory limit for WinRM sessions
Write-Host "[STEP 4/6] Configuring WinRM memory limits..." -ForegroundColor Yellow
try {
    winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}' | Out-Null
    Write-Host "[SUCCESS] Memory limits configured" -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Failed to configure memory limits: $_" -ForegroundColor Yellow
}

# Step 5: Configure Windows Firewall
if (-not $SkipFirewall) {
    Write-Host "[STEP 5/6] Configuring Windows Firewall rules..." -ForegroundColor Yellow
    try {
        # Check if rules already exist
        $httpRule = Get-NetFirewallRule -Name "WinRM HTTP" -ErrorAction SilentlyContinue
        $httpsRule = Get-NetFirewallRule -Name "WinRM HTTPS" -ErrorAction SilentlyContinue
        
        if (-not $httpRule) {
            netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow | Out-Null
            Write-Host "[SUCCESS] WinRM HTTP firewall rule added" -ForegroundColor Green
        } else {
            Write-Host "[INFO] WinRM HTTP firewall rule already exists" -ForegroundColor Cyan
        }
        
        if (-not $httpsRule) {
            netsh advfirewall firewall add rule name="WinRM HTTPS" protocol=TCP dir=in localport=5986 action=allow | Out-Null
            Write-Host "[SUCCESS] WinRM HTTPS firewall rule added" -ForegroundColor Green
        } else {
            Write-Host "[INFO] WinRM HTTPS firewall rule already exists" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "[WARNING] Failed to configure firewall rules: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host '[STEP 5/6] Skipping firewall configuration (--SkipFirewall specified)' -ForegroundColor Yellow
}

# Step 6: Verify WinRM configuration
Write-Host "[STEP 6/6] Verifying WinRM configuration..." -ForegroundColor Yellow
Write-Host ""

$serviceConfig = winrm get winrm/config/service
$authConfig = winrm get winrm/config/service/auth

Write-Host "WinRM Service Configuration:" -ForegroundColor Cyan
$serviceConfig | Select-String -Pattern "AllowUnencrypted|RootSDDL" | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

Write-Host ""
Write-Host "WinRM Authentication Configuration:" -ForegroundColor Cyan
$authConfig | Select-String -Pattern "Basic|Kerberos|Certificate" | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              WinRM Configuration Complete!                      ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Test WinRM connectivity:" -ForegroundColor Yellow
$testCmd = "winrs -r:http://localhost:5985 -u:Administrator -p:" + $Password + " hostname"
Write-Host "  From Windows: $testCmd" -ForegroundColor White
Write-Host "  From Linux: winrs -r:http://<VM_IP>:5985 -u:Administrator -p:$Password hostname" -ForegroundColor White
Write-Host ""
Write-Host "Test with Ansible:" -ForegroundColor Yellow
Write-Host "  ansible all -i inventory -m win_ping" -ForegroundColor White
Write-Host ""

