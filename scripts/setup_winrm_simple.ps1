# Simple WinRM Setup Script for GOAD Lab
# Run as Administrator

Write-Host "Enabling WinRM..." -ForegroundColor Green

winrm quickconfig -force -q
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}'

netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow
netsh advfirewall firewall add rule name="WinRM HTTPS" protocol=TCP dir=in localport=5986 action=allow

Write-Host "WinRM configured successfully!" -ForegroundColor Green

