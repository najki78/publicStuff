
<# 

 Description: Enable Remote desktop shadowing
 Author: Ľuboš Nikolíni
 Version: 2021-12-11A

 Equivalent Group Policy: "Set rules for remote control of Remote Desktop Services user sessions"
 Reference: 
    https://swarm.ptsecurity.com/remote-desktop-services-shadowing/
    https://www.how2shout.com/how-to/windows-firewall-allow-rdp-using-gui-powershell-command.html
#> 


function Set-Registry {
    param ($registryPath, $RegName, $value, $valueType)

    if (!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }

    # check current value
    $CurVal=(Get-ItemProperty -Path $registryPath -Name $RegName -ErrorAction:SilentlyContinue).$RegName
            
    # if key does not exist or if it has different value that $value, create / replace it with a new $value
    if($CurVal -ne $value){ New-ItemProperty -Path $registryPath -Name $RegName -Value $value -PropertyType $valueType -Force -ErrorAction:SilentlyContinue | Out-Null }

}


$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
$RegName = "AllowRemoteRPC"
$value = 1
$valueType = "DWORD"
#Set-Registry $registryPath $RegName $value

$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$RegName = "Shadow"
$value = 2
$valueType = "DWORD"
Set-Registry $registryPath $RegName $value


<#

# Enable firewall - to be tested (if enabling Public profile is not needed - "File and Printer Sharing (SMB-In)" rule is both "Private, Public")

$DisplayNamesList=("File and Printer Sharing (SMB-In)", "Remote Desktop - Shadow (TCP-In)")
foreach ($Rule in $DisplayNamesList){Get-NetFirewallRule -DisplayName $Rule | ?{$_.Profile -notmatch "Public"} | Enable-NetFirewallRule }

#>

return 0