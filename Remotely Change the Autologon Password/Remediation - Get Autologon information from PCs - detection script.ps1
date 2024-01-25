# Get Autologon information from PCs

$version = "2024.01.25.01"

cls

$ConfirmPreference = 'None'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue' 
$VerbosePreference = 'SilentlyContinue' 

$WarningActionPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop" # set default ErrorAction for all commands

# https://gist.github.com/rufflabs/4f3c50c4e9f0218a283e
# https://devblogs.microsoft.com/scripting/use-powershell-to-duplicate-process-tokens-via-pinvoke/
# https://devblogs.microsoft.com/scripting/use-powershell-to-decrypt-lsa-secrets-from-the-registry/

function Enable-TSDuplicateToken {
<#
  .SYNOPSIS
  Duplicates the Access token of lsass and sets it in the current process thread.

  .DESCRIPTION
  The Enable-TSDuplicateToken CmdLet duplicates the Access token of lsass and sets it in the current process thread.
  The CmdLet must be run with elevated permissions.

  .EXAMPLE
  Enable-TSDuplicateToken

  .LINK
  http://www.truesec.com

  .NOTES
  Goude 2012, TreuSec
#>
[CmdletBinding()]
param()

$signature = @"
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
     public struct TokPriv1Luid
     {
         public int Count;
         public long Luid;
         public int Attr;
     }

    public const int SE_PRIVILEGE_ENABLED = 0x00000002;
    public const int TOKEN_QUERY = 0x00000008;
    public const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
    public const UInt32 STANDARD_RIGHTS_REQUIRED = 0x000F0000;

    public const UInt32 STANDARD_RIGHTS_READ = 0x00020000;
    public const UInt32 TOKEN_ASSIGN_PRIMARY = 0x0001;
    public const UInt32 TOKEN_DUPLICATE = 0x0002;
    public const UInt32 TOKEN_IMPERSONATE = 0x0004;
    public const UInt32 TOKEN_QUERY_SOURCE = 0x0010;
    public const UInt32 TOKEN_ADJUST_GROUPS = 0x0040;
    public const UInt32 TOKEN_ADJUST_DEFAULT = 0x0080;
    public const UInt32 TOKEN_ADJUST_SESSIONID = 0x0100;
    public const UInt32 TOKEN_READ = (STANDARD_RIGHTS_READ | TOKEN_QUERY);
    public const UInt32 TOKEN_ALL_ACCESS = (STANDARD_RIGHTS_REQUIRED | TOKEN_ASSIGN_PRIMARY |
      TOKEN_DUPLICATE | TOKEN_IMPERSONATE | TOKEN_QUERY | TOKEN_QUERY_SOURCE |
      TOKEN_ADJUST_PRIVILEGES | TOKEN_ADJUST_GROUPS | TOKEN_ADJUST_DEFAULT |
      TOKEN_ADJUST_SESSIONID);

    public const string SE_TIME_ZONE_NAMETEXT = "SeTimeZonePrivilege";
    public const int ANYSIZE_ARRAY = 1;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID
    {
      public UInt32 LowPart;
      public UInt32 HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID_AND_ATTRIBUTES {
       public LUID Luid;
       public UInt32 Attributes;
    }




    public struct TOKEN_PRIVILEGES {
      public UInt32 PrivilegeCount;
      [MarshalAs(UnmanagedType.ByValArray, SizeConst=ANYSIZE_ARRAY)]
      public LUID_AND_ATTRIBUTES [] Privileges;
    }

    [DllImport("advapi32.dll", SetLastError=true)]
     public extern static bool DuplicateToken(IntPtr ExistingTokenHandle, int
        SECURITY_IMPERSONATION_LEVEL, out IntPtr DuplicateTokenHandle);


    [DllImport("advapi32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetThreadToken(
      IntPtr PHThread,
      IntPtr Token
    );

    [DllImport("advapi32.dll", SetLastError=true)]
     [return: MarshalAs(UnmanagedType.Bool)]
      public static extern bool OpenProcessToken(IntPtr ProcessHandle, 
       UInt32 DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

    [DllImport("kernel32.dll", ExactSpelling = true)]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
     public static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall,
     ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
"@

  $currentPrincipal = New-Object Security.Principal.WindowsPrincipal( [Security.Principal.WindowsIdentity]::GetCurrent())
  if($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -ne $true) {
    Write-Warning "Run the Command as an Administrator"
    Break
  }

  Add-Type -MemberDefinition $signature -Name AdjPriv -Namespace AdjPriv
  $adjPriv = [AdjPriv.AdjPriv]
  [long]$luid = 0

  $tokPriv1Luid = New-Object AdjPriv.AdjPriv+TokPriv1Luid
  $tokPriv1Luid.Count = 1
  $tokPriv1Luid.Luid = $luid
  $tokPriv1Luid.Attr = [AdjPriv.AdjPriv]::SE_PRIVILEGE_ENABLED

  $retVal = $adjPriv::LookupPrivilegeValue($null, "SeDebugPrivilege", [ref]$tokPriv1Luid.Luid)

  [IntPtr]$htoken = [IntPtr]::Zero
  $retVal = $adjPriv::OpenProcessToken($adjPriv::GetCurrentProcess(), [AdjPriv.AdjPriv]::TOKEN_ALL_ACCESS, [ref]$htoken)
  
  
  $tokenPrivileges = New-Object AdjPriv.AdjPriv+TOKEN_PRIVILEGES
  $retVal = $adjPriv::AdjustTokenPrivileges($htoken, $false, [ref]$tokPriv1Luid, 12, [IntPtr]::Zero, [IntPtr]::Zero)

  if(-not($retVal)) {
    [System.Runtime.InteropServices.marshal]::GetLastWin32Error()
    Break
  }

  $process = (Get-Process -Name lsass)
  [IntPtr]$hlsasstoken = [IntPtr]::Zero
  $retVal = $adjPriv::OpenProcessToken($process.Handle, ([AdjPriv.AdjPriv]::TOKEN_IMPERSONATE -BOR [AdjPriv.AdjPriv]::TOKEN_DUPLICATE), [ref]$hlsasstoken)

  [IntPtr]$dulicateTokenHandle = [IntPtr]::Zero
  $retVal = $adjPriv::DuplicateToken($hlsasstoken, 2, [ref]$dulicateTokenHandle)

  $retval = $adjPriv::SetThreadToken([IntPtr]::Zero, $dulicateTokenHandle)
  if(-not($retVal)) {
    [System.Runtime.InteropServices.marshal]::GetLastWin32Error()
  }
}

# without timezone information (time in UTC), only alphanumeric characters
function timestampUTC {

    try {
        return "$((get-date -ErrorAction Stop).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))"  
        # the actual time (on the clock) + current timezone shift
    } catch {
        return "yyyy-MM-ddTHH:mm:ssZ"
    }

}

try {

    # those that will have nested hashtables need to be inserted like arrays first, the other, non-nested, elements do not have to be predefined like this
    $outputJSON = @{}

    # THE MOST IMPORTANT PART OF THE SCRIPT, ACTUAL AUTOLOGON ACCOUNT
    try {
        if(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultDomainName -ErrorAction SilentlyContinue) {
            $outputJSON.AutologonRegistryDefaultDomainName = "$(Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultDomainName -ErrorAction SilentlyContinue)"   
        }
    } catch {}

    # IF THE VALUE = 1, AUTOLOGON IS CONFIGURED
    try {
        if(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name AutoAdminLogon -ErrorAction SilentlyContinue) {
            $outputJSON.AutologonRegistryAutoAdminLogon = "$(Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name AutoAdminLogon -ErrorAction SilentlyContinue)"   
        }
    } catch {}


    # DO NOT RETRIEVE FROM PC IN PRODUCTION, IN CASE CLEAR TEXT PASSWORD IS USED, IT WILL BE PART OF THE INTUNE REMEDIATION REPORT
    # https://learn.microsoft.com/en-us/troubleshoot/windows-server/user-profiles-and-logon/turn-on-automatic-logon
    try {
        if(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultPassword -ErrorAction SilentlyContinue) {
            $outputJSON.AutologonRegistryDefaultPassword = "$(Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultPassword -ErrorAction SilentlyContinue)"   
        }
    } catch {}

    try {
        if(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultUserName -ErrorAction SilentlyContinue) {
            $outputJSON.AutologonRegistryDefaultUserName = "$(Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultUserName -ErrorAction SilentlyContinue)"   
        }
    } catch {}


    #############################################################################
    # Optional part - useful data, but not necessary for Autologon password change
    #############################################################################

    try {
        $outputJSON.serialNumber = "$((Get-CimInstance win32_bios -ErrorAction SilentlyContinue).SerialNumber)"
    } catch {}

    try {
        $outputJSON.Name = "$($env:computername)" 
    } catch {}

    try {
        $outputJSON.LoggedOnUser = "$($env:username)" 
    } catch {}

    try {
        $outputJSON.Version = "$($version)"
    } catch {}

    try {
        $outputJSON.TimeStamp = timestampUTC 
    } catch {}
    
    # https://www.reddit.com/r/Intune/comments/m74luq/obtaining_intune_objectid_from_local_device/
    # Intune Device ID from Autopilot information in registry
    try {
        if(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot\EstablishedCorrelations" -Name EntDMID -ErrorAction SilentlyContinue) {
            $outputJSON.IntuneDeviceIDRegistry = "$(Get-ItemPropertyValue HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot\EstablishedCorrelations -Name EntDMID -ErrorAction SilentlyContinue)"   # Intune Device ID (from registry); 
        }
    } catch {}

    # the actual value is not as important as a fact that there is some value, because it means that the autologon password is configured as LSA secret
    try {

        # this needs to be uncommented to work under other than SYSTEM account
        # Enable-TSDuplicateToken

        # [HKEY_LOCAL_MACHINE\Security\Policy\Secrets\DefaultPassword\CurrVal]
        if(Get-ItemProperty "HKLM:\Security\Policy\Secrets\DefaultPassword\CurrVal" -Name "(default)" -ErrorAction SilentlyContinue) {
            $outputJSON.SecretsDefaultPasswordCurrVal = "$(Get-ItemPropertyValue HKLM:\Security\Policy\Secrets\DefaultPassword\CurrVal -Name "(default)" -ErrorAction SilentlyContinue)"
        }

        # When the password has been last changed
        # [HKEY_LOCAL_MACHINE\Security\Policy\Secrets\DefaultPassword\OupdTime]
        if(Get-ItemProperty "HKLM:\Security\Policy\Secrets\DefaultPassword\OupdTime" -Name "(default)" -ErrorAction SilentlyContinue) {
            $outputJSON.SecretsDefaultPasswordOupdTime = "$(Get-ItemPropertyValue HKLM:\Security\Policy\Secrets\DefaultPassword\OupdTime -Name "(default)" -ErrorAction SilentlyContinue)"
        }

    } catch {}

    try {
        # Intune Device ID (Subject from the Intune certificate); 
        # https://call4cloud.nl/2022/09/intune-the-legend-of-the-certificate/
        # from Intune certificate - sort by Expiration date
        $tmpCert= Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Issuer -like "*Microsoft Intune MDM Device CA*" } | Sort-Object -Property NotAfter -Descending | Select-Object -First 1

        # Get the certificate details
        $certificateSubject = (Get-ChildItem -Path Cert:\LocalMachine\My\$($tmpCert.thumbprint)).Subject

        # Extract the Intune Device ID from the Subject field of the certificate
        $deviceId = ($certificateSubject -split "=")[1]

        $outputJSON.IntuneDeviceIDCertificate = "$($deviceId)"
    
    } catch {}

    # get device primary user via PowerShell script
    # https://learn.microsoft.com/en-us/answers/questions/1288580/how-get-who-is-device-primary-user-on-enrolled-dev
    try {

        $PATH = (Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments\*\FirstSync').Name -replace "\\FirstSync",'' -replace 'HKEY_LOCAL_MACHINE','HKLM:'
        $UPN = Get-ItemPropertyValue -Path $PATH -Name 'UPN'
        $LOGIN = $UPN -replace '@contoso.com'

        $outputJSON.PrimaryUserRegistryUPN = "$($UPN)"

        $null = New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS -ErrorAction SilentlyContinue
        
        FOREACH ($RootHKC in (Get-ChildItem "HKU:\" -ErrorAction SilentlyContinue).Name | Where-Object {$_ -like "HKEY_USERS\S-1-12-1*" -and $_ -notlike "*_Classes"}){

            $HKUPATH = $RootHKC -replace "HKEY_USERS", "HKU:"
            $UserId = Get-ItemPropertyValue -Path "$HKUPATH\Software\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\AADNGC\*" -Name 'UserId' -ErrorAction SilentlyContinue
            #$UserId
        
            IF ($UserId -ne $null -and $UserId -eq $UPN){
                $SID = $RootHKC -replace "HKEY_USERS\\"
            } ELSE {
                $false
            }

        }
        $null = Remove-PSDrive -Name HKU -ErrorAction SilentlyContinue

        $outputJSON.PrimaryUserWorkplaceJoinUserID = "$($UserID)"
        
    } catch {}


    # https://call4cloud.nl/2021/12/married-with-systemboards-976-tpm/
    # on certificate recovery: https://call4cloud.nl/2022/07/the-tenantid-from-toronto/
    # https://call4cloud.nl/2020/05/intune-auto-mdm-enrollment-for-devices-already-azure-ad-joined/
    try {

        # Issued To and Subject = Microsoft Entra Device ID
        $tmpCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Issuer -like "*MS-Organization-Access*" } | Sort-Object -Property NotAfter -Descending | Select-Object -First 1

        # Get the certificate details
        $certificateSubject = (Get-ChildItem -Path Cert:\LocalMachine\My\$($tmpCert.thumbprint)).Subject

        # Extract the Entra Device ID from the Subject field of the certificate
        $deviceId = ($certificateSubject -split "=")[1]

        $outputJSON.EntraDeviceIDCertificate = "$($deviceId)"

    } catch {}

    # https://github.com/okieselbach/Intune/blob/master/Detect-PrimaryUser.ps1
    try {

        <#
        Version: 1.1
        Author:  Oliver Kieselbach
        Script:  Detect-PrimaryUser.ps1
        Date:    10/13/2022

        Description:
        Check if logged on user is enrollment user which is also our primary user (primary user change is not supported)

        Release notes:
        Version 1.0: Original published version.
        Version 1.1: renamed to Detect-PrimaryUser.ps1

        The script is provided "AS IS" with no warranties.
        #>

        # UserEmail from CloudDomainJoin Info = Enrollment User
        $PrimaryUserUPN = $null
        $CloudDomainJoinInfo = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo" -ErrorAction SilentlyContinue
        if ($null -ne $CloudDomainJoinInfo) {
            # Change of Primary User on Intune side is not reflected in registry as the registry key is the enrollment user and is not updated
            # UPN Change is also not reflected in registry -> not supported
            # Consequence: Change of Primary User or UPN change needs reinstall of device!

            $PrimaryUserUPN = ($CloudDomainJoinInfo | Get-ItemProperty).UserEmail
        }

        # Cloud PC has no Enrollment user (dummy entry fooUser@domain.com is written), so we always install (no Primary user support there)
        $SystemProductName = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -Name SystemProductName -ErrorAction SilentlyContinue).SystemProductName
        if ($PrimaryUserUPN.ToLower().StartsWith("foouser@") -and $SystemProductName.ToLower().StartsWith("cloud pc")) {
            #Write-Output "PrimaryUser"
        }

        # No CloudDomainJoinInfo available -> Autopilot Pre-Provisioning (aka White Glove) Phase
        if ([string]::IsNullOrEmpty($PrimaryUserUPN)) {
            #Write-Output "PrimaryUser"
        }

        $outputJSON.PrimaryUserCloudDomainJoin = "$($PrimaryUserUPN)"

        # approach will not work with multisession currently, as there might be more than one explorer.exe
        $explorerProcess = @(Get-WmiObject -Query "Select * FROM Win32_Process WHERE Name='explorer.exe'" -ErrorAction SilentlyContinue)
        if ($explorerProcess.Count -ne 0) {
            $explorerOwner = $explorerProcess[0].GetOwner().User

            # explorer runs as defaultUser* or system -> OOBE phase
            if ($explorerOwner -contains "defaultuser" -or $explorerOwner -contains "system") {
                #Write-Output "PrimaryUser"
            }

            # explorer runs as a normal user process, check if it is the current logged on user
            $userSid = (Get-ChildItem -Recurse "HKLM:\SOFTWARE\Microsoft\IdentityStore\Cache" | Get-ItemProperty | Where-Object { $_.SAMName -match $explorerOwner } | Select-Object -First 1 PSChildName).PSChildName
            $LoggedOnUserUPN = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\IdentityStore\Cache\$userSid\IdentityCache\$userSid" -Name UserName).UserName

            if ($PrimaryUserUPN -eq $LoggedOnUserUPN) {
                #Write-Output "PrimaryUser"
            }
            else {
                #Write-Output "SecondaryUser"
            }
        }
        else {
            # no explorer running -> OOBE phase
            #Write-Output "PrimaryUser"
        }

        $outputJSON.PrimaryUserExplorerProcess = "$($LoggedOnUserUPN)"

    } catch {}

    #############################################################################
    # End of the optional part 
    #############################################################################

    # now we convert it to JSON
    $outputString = $outputJSON | ConvertTo-Json -Depth 100 -Compress # -ErrorAction SilentlyContinue

    # https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations
    # The maximum allowed output size limit is 2048 characters.

    if($outputString.Length > 2046) {

        # The output is too long
        Write-Output "{ ""OutputLength"":""$($outputString.Length)"" }"

    } else {

        Write-Output $outputString 

    }

} catch {

    try {
        $exception = $_.Exception
 
        $outputString = "EXCEPTION."
        
        if ($exception -is [System.Object])    { $outputString += " NAME: " + $exception.GetType().FullName.ToString().Replace("`r", "").Replace("`n", "|") }
        if ($exception.Message)                { $outputString += " MESSAGE: " + $exception.Message.ToString().Replace("`r", "").Replace("`n", "|") }
        if ($exception.StackTrace)             { $outputString += " TRACE: " + $exception.StackTrace.ToString().Replace("`r", "").Replace("`n", "|") }
        if ($exception.ErrorRecord)             { $outputString += " RECORD: " + $exception.ErrorRecord.ToString().Replace("`r", "").Replace("`n", "|") }

    } catch {}

    Write-Output "{ ""Exception"":""$($outputString)"" }"
    
    exit 1 # run remediation (currently none is defined)        

}

exit 0