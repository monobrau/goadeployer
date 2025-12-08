# Simple WinRM Setup Script for GOAD Lab
# Run as Administrator

Write-Host "Enabling WinRM..." -ForegroundColor Green

winrm quickconfig -force -q
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}'

# Enable WinRM HTTPS listener
$computerName = $env:COMPUTERNAME
$cert = New-SelfSignedCertificate -DnsName $computerName -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddYears(10)
$thumbprint = $cert.Thumbprint
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$computerName`";CertificateThumbprint=`"$thumbprint`"}"

netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow
netsh advfirewall firewall add rule name="WinRM HTTPS" protocol=TCP dir=in localport=5986 action=allow

Write-Host "WinRM configured successfully!" -ForegroundColor Green
Write-Host "HTTP listener: port 5985" -ForegroundColor Cyan
Write-Host "HTTPS listener: port 5986" -ForegroundColor Cyan

