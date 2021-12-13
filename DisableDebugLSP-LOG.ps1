
<# 

 Description: Disable lsp.log on the client device (after troubleshooting Name/SID lookup APIs)

 C:\Windows\debug\lsp.log

 Author: Ľuboš Nikolíni
 Version: 2021-12-13A

 Reference: https://docs.microsoft.com/en-us/windows/client-management/mdm/policy-csp-localusersandgroups#how-can-i-troubleshoot-namesid-lookup-apis
    
#> 


function Set-Registry {
    param ($registryPath, $RegName, $value, $valueType)

    if (!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }

    # check current value
    $CurVal=(Get-ItemProperty -Path $registryPath -Name $RegName -ErrorAction:SilentlyContinue).$RegName
            
    # if key does not exist or if it has different value that $value, create / replace it with a new $value
    if($CurVal -ne $value){ New-ItemProperty -Path $registryPath -Name $RegName -Value $value -PropertyType $valueType -Force -ErrorAction:SilentlyContinue | Out-Null }

}


$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$valueType = "DWORD"

$RegName = "LspDbgInfoLevel"
$value = 0x0
# enable value 0x800
Set-Registry $registryPath $RegName $value

$RegName = "LspDbgTraceOptions"
$value = 0x0
# enable value 0x1
Set-Registry $registryPath $RegName $value

return 0