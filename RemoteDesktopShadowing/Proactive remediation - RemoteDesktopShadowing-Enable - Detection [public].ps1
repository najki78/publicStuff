
<# 

 Description: Enable Remote desktop shadowing and disable Lock screen (proactive remediation - detection script)
 Author: Lubos Nikolini
 Version: 2022-04-06 

 Settings:
    Run this script using the logged-on credentials: No
    Enforce script signature check: No
    Run script in 64-bit PowerShell: Yes

#> 

function Check-Registry {
    param ($registryPath, $RegName, $value)

    $registry = ((Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue).$RegName)

    if ($registry -eq $value)
        {
           return 0
        }
    else
        {
            return 1 # value in registry <> $value 
        }

}

try {

    $result = 0

    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
    $RegName = "AllowRemoteRPC"
    $value = 1
    $valueType = "DWORD"
    $result += Check-Registry $registryPath $RegName $value


    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    $RegName = "Shadow"
    $value = 2
    $valueType = "DWORD"
    $result += Check-Registry $registryPath $RegName $value

    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\SessionData"
    $RegName = "AllowLockScreen"
    $value = 0
    $valueType = "DWORD"
    $result += Check-Registry $registryPath $RegName $value


    # check scheduled task that runs on logon and return from lock screen and disables lock screen in registry
    # https://www.winhelponline.com/blog/disable-lock-screen-anniversary-update-windows-10/#google_vignette

    $taskName = "Disable Lock Screen"
    if ( (Get-ScheduledTask -TaskName $taskName -TaskPath \* -ErrorAction SilentlyContinue).State -ne "Ready") { $result += 1 }

    Write-Host $result

    if ($result -eq 0) {
        exit 0
    } else {
        exit 1 # if we want to remediate, this needs to be 1
    }

} catch {

    $errMsg = $_.Exception.Message
    Write-Host $errMsg 
    exit 1

}