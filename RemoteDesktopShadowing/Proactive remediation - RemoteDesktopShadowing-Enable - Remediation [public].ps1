### 2022-04-06 Lubos - remediation script - Enable Remote desktop shadowing

<# 

 Description: Enable Remote desktop shadowing and disable Lock screen
 Author: Lubos Nikolini

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
Set-Registry $registryPath $RegName $value $valueType

$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$RegName = "Shadow"
$value = 2
$valueType = "DWORD"
Set-Registry $registryPath $RegName $value $valueType

$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\SessionData"
$RegName = "AllowLockScreen"
$value = 0
$valueType = "DWORD"
Set-Registry $registryPath $RegName $value $valueType

# creates scheduled task that runs on logon and return from lock screen and disables lock screen in registry
# https://www.winhelponline.com/blog/disable-lock-screen-anniversary-update-windows-10/#google_vignette

$taskName = "Disable Lock Screen"

if (${env:PUBLIC}) {
    $folderName = "${env:PUBLIC}\Documents\RemoteDesktopShadowing\"
} else {
    $folderName = "C:\Users\Public\Documents\RemoteDesktopShadowing\"
}

if (!(Test-Path $folderName)) {
    New-Item -Path $folderName -Force -ErrorAction SilentlyContinue | Out-Null 
}

$fileName = "{0}{1}" -f $folderName,"DisableLockScreen-UTF16LE.xml" 

<#

    # https://www.educba.com/powershell-base64/

    # UTF-16 LE 
    # unicode: Encodes in UTF-16 format using the little-endian byte order.
    # reference> https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-content?view=powershell-7.2#:~:text=Encoding%20is%20a%20dynamic%20parameter%20that%20the%20FileSystem,the%20entire%20file%20in%20a%20single%20read%20operation.

    $inputfile = "DisableLockScreen-UTF16LE.xml"
    # -raw parameter is of utmost importance, otherwise we lose newline characters
    $fc = get-content $inputfile -raw -Encoding unicode

    $By = [System.Text.Encoding]::UTF8.GetBytes($fc)

    $etext = [System.Convert]::ToBase64String($by)
    Write-Host "ENCODED text file content is " $etext -ForegroundColor Green

#>

$etext = "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTE2Ij8+DQo8VGFzayB2ZXJzaW9uPSIxLjIiIHhtbG5zPSJodHRwOi8vc2NoZW1hcy5taWNyb3NvZnQuY29tL3dpbmRvd3MvMjAwNC8wMi9taXQvdGFzayI+DQogIDxSZWdpc3RyYXRpb25JbmZvPg0KICAgIDxEYXRlPjIw
MTYtMDgtMDVUMTA6NTM6MjMuNDI5NjE3MTwvRGF0ZT4NCiAgICA8RGVzY3JpcHRpb24+RGlzYWJsZSB0aGUgTG9jayBTY3JlZW4gd2hlbiBsb2NraW5nIHRoZSBjb21wdXRlci48L0Rlc2NyaXB0aW9uPg0KICAgIDxVUkk+XERpc2FibGUgTG9jayBTY3JlZW48L1VSST4NCiAgPC9SZWdpc3RyYXRpb25JbmZvPg0KICA8VH
JpZ2dlcnM+DQogICAgPExvZ29uVHJpZ2dlcj4NCiAgICAgIDxFbmFibGVkPnRydWU8L0VuYWJsZWQ+DQogICAgPC9Mb2dvblRyaWdnZXI+DQogICAgPFNlc3Npb25TdGF0ZUNoYW5nZVRyaWdnZXI+DQogICAgICA8RW5hYmxlZD50cnVlPC9FbmFibGVkPg0KICAgICAgPFN0YXRlQ2hhbmdlPlNlc3Npb25VbmxvY2s8L1N0
YXRlQ2hhbmdlPg0KICAgIDwvU2Vzc2lvblN0YXRlQ2hhbmdlVHJpZ2dlcj4NCiAgPC9UcmlnZ2Vycz4NCiAgPFByaW5jaXBhbHM+DQogICAgPFByaW5jaXBhbCBpZD0iQXV0aG9yIj4NCiAgICAgIDxVc2VySWQ+Uy0xLTUtMTg8L1VzZXJJZD4NCiAgICAgIDxSdW5MZXZlbD5IaWdoZXN0QXZhaWxhYmxlPC9SdW5MZXZlbD
4NCiAgICA8L1ByaW5jaXBhbD4NCiAgPC9QcmluY2lwYWxzPg0KICA8U2V0dGluZ3M+DQogICAgPE11bHRpcGxlSW5zdGFuY2VzUG9saWN5Pklnbm9yZU5ldzwvTXVsdGlwbGVJbnN0YW5jZXNQb2xpY3k+DQogICAgPERpc2FsbG93U3RhcnRJZk9uQmF0dGVyaWVzPmZhbHNlPC9EaXNhbGxvd1N0YXJ0SWZPbkJhdHRlcmll
cz4NCiAgICA8U3RvcElmR29pbmdPbkJhdHRlcmllcz5mYWxzZTwvU3RvcElmR29pbmdPbkJhdHRlcmllcz4NCiAgICA8QWxsb3dIYXJkVGVybWluYXRlPnRydWU8L0FsbG93SGFyZFRlcm1pbmF0ZT4NCiAgICA8U3RhcnRXaGVuQXZhaWxhYmxlPnRydWU8L1N0YXJ0V2hlbkF2YWlsYWJsZT4NCiAgICA8UnVuT25seUlmTm
V0d29ya0F2YWlsYWJsZT5mYWxzZTwvUnVuT25seUlmTmV0d29ya0F2YWlsYWJsZT4NCiAgICA8SWRsZVNldHRpbmdzPg0KICAgICAgPFN0b3BPbklkbGVFbmQ+dHJ1ZTwvU3RvcE9uSWRsZUVuZD4NCiAgICAgIDxSZXN0YXJ0T25JZGxlPmZhbHNlPC9SZXN0YXJ0T25JZGxlPg0KICAgIDwvSWRsZVNldHRpbmdzPg0KICAg
IDxBbGxvd1N0YXJ0T25EZW1hbmQ+dHJ1ZTwvQWxsb3dTdGFydE9uRGVtYW5kPg0KICAgIDxFbmFibGVkPnRydWU8L0VuYWJsZWQ+DQogICAgPEhpZGRlbj5mYWxzZTwvSGlkZGVuPg0KICAgIDxSdW5Pbmx5SWZJZGxlPmZhbHNlPC9SdW5Pbmx5SWZJZGxlPg0KICAgIDxXYWtlVG9SdW4+ZmFsc2U8L1dha2VUb1J1bj4NCi
AgICA8RXhlY3V0aW9uVGltZUxpbWl0PlBUMUg8L0V4ZWN1dGlvblRpbWVMaW1pdD4NCiAgICA8UHJpb3JpdHk+NzwvUHJpb3JpdHk+DQogIDwvU2V0dGluZ3M+DQogIDxBY3Rpb25zIENvbnRleHQ9IkF1dGhvciI+DQogICAgPEV4ZWM+DQogICAgICA8Q29tbWFuZD5yZWcuZXhlPC9Db21tYW5kPg0KICAgICAgPEFyZ3Vt
ZW50cz5hZGQgSEtMTVxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxBdXRoZW50aWNhdGlvblxMb2dvblVJXFNlc3Npb25EYXRhIC90IFJFR19EV09SRCAvdiBBbGxvd0xvY2tTY3JlZW4gL2QgMCAvZjwvQXJndW1lbnRzPg0KICAgIDwvRXhlYz4NCiAgPC9BY3Rpb25zPg0KPC9UYXNrPg=="

#if there is such scheduled task, but State is Disabled or something else but not Ready, delete it
if ( (Get-ScheduledTask -TaskName $taskName -TaskPath \* -ErrorAction SilentlyContinue).State -ne "Ready") { 
    Unregister-ScheduledTask -TaskPath \* -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

#if there is no such scheduled task, create it
Set-Content -Path $fileName  -Value ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($etext)))
Register-ScheduledTask -Xml (Get-Content $fileName | out-string) -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null 

# delete temp XML file
Remove-Item -Path $fileName -Force -ErrorAction SilentlyContinue

# run the scheduled task
Start-ScheduledTask -TaskName $taskName

return 0