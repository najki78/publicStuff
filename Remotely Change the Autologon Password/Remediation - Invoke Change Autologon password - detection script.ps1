# Change the Autologon Password
$version = "2024.01.25.01"

    # based on Name: Autologon.ps1 - Version: 1.0 - Author: Johan Schrewelius - Date: 2020-06-15
    # Thank you!
    # https://ccmexec.com/2020/08/windows-10-secure-autologon-powershell/
    # Johan's script elegantly uses -EncodedCommand to store the embedded script (I was unable to make it work and had to temporarily store the $Code in a file on the disk)

    # and 

    # Get-TSLsaSecret - Thanks to Niklas Goude @ http://www.truesec.com
    # https://github.com/dwj7738/My-Powershell-Repository/blob/master/Scripts/Get-TSLSASecret.ps1
    # https://devblogs.microsoft.com/scripting/use-powershell-to-decrypt-lsa-secrets-from-the-registry/

[string]$Username = "<UPN>"
[string]$Password = "<password>"

[string]$DomainName = "<Entra ID Name>" # 
[string]$RebootAllowed = "yes" 
    # if 'yes', the script will reboot the PC if needed (=if the password has been updated) and only if needed (it will not reboot when the password in the registry matches the newly provided password)
    # if no, do not reboot in any circumstances

# More on DefaultPassword value saved in registry for AutoLogon: https://www.thewindowsclub.com/decrypt-the-defaultpassword-value-saved-in-registry-for-autologon

cls

$Code = @'
$VerbosePreference = 'SilentlyContinue' 
$InformationPreference = 'SilentlyContinue'
$ErrorActionPreference = "Stop" 
$WarningActionPreference = 'Continue'
$DebugPreference = 'SilentlyContinue' 

# the end results to be reported both 
# locally, stored in "C:\ProgramData\YourCompany\Intune\<timestamp>-ChangeAutologonPassword.txt" 
# and remotely, using a webhook to add an entry to Sharepoint list
$Results = $null

# without timezone information (time in UTC), suitable for file names etc (colon character removed)
function timestampUTC2 {
    try {
        return "$((get-date -ErrorAction Stop).ToUniversalTime().ToString("yyyy-MM-ddTHHmmssZ"))" # the actual time (on the clock) + current timezone shift
    } catch {
        return "yyyy-MM-ddTHHmmssZ"
    }
}

try {

    try{ stop-transcript|out-null } catch {}
    $path = "C:\ProgramData\YourCompany\Intune\" # the folder to store the report
    $logFile = $path + (timestampUTC2) + "-ChangeAutologonPassword.txt" # log file
       
    # the file should not exist (it includes a timestamp), but if it does, delete it (the only possibility is if 'timestamp2' function fails to provide a current timestamp, this should never happen)
    $null = Remove-Item $logFile -Force -ErrorAction SilentlyContinue | out-null	

    Start-Transcript -Path $logFile -Append -ErrorAction Continue

    Write-Output "Starting."
    Write-Output "Script version: %SCRIPTVERSION%"

} catch {}

function Get-TSLsaSecret {
 <#
    .SYNOPSIS
    Displays LSA Secrets from local computer.

    .DESCRIPTION
    Extracts LSA secrets from HKLM:\\SECURITY\Policy\Secrets\ on a local computer.
    The CmdLet must be run with elevated permissions, in 32-bit mode and requires permissions to the security key in HKLM.

    .PARAMETER Key
    Name of Key to Extract. if the parameter is not used, all secrets will be displayed.

    .EXAMPLE
    Enable-TSDuplicateToken
    Get-TSLsaSecret

    .EXAMPLE
    Enable-TSDuplicateToken
    Get-TSLsaSecret -Key KeyName

    .LINK
    http://www.truesec.com

    .NOTES
    Goude 2012, TreuSec
  #>
  param(
    [Parameter(Position = 0,
      ValueFromPipeLine= $true
    )]
    [Alias("RegKey")]
    [string[]]$RegistryKey
  )

Begin {
# Check if User is Elevated
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal( [Security.Principal.WindowsIdentity]::GetCurrent())
if($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -ne $true) {
  Write-Warning "Run the Command as an Administrator"
  Break
}

# Check if Script is run in a 32-bit Environment by checking a Pointer Size
if([System.IntPtr]::Size -eq 8) {
  Write-Warning "Run PowerShell in 32-bit mode"
  Break
}



# Check if RegKey is specified
if([string]::IsNullOrEmpty($registryKey)) {
  [string[]]$registryKey = (Split-Path (Get-ChildItem HKLM:\SECURITY\Policy\Secrets | Select -ExpandProperty Name) -Leaf)
}

# Create Temporary Registry Key
if( -not(Test-Path "HKLM:\\SECURITY\Policy\Secrets\MySecret")) {
  mkdir "HKLM:\\SECURITY\Policy\Secrets\MySecret" | Out-Null
}

Add-Type -Name LSAUtil -Namespace LSAUtil -MemberDefinition @"
[StructLayout(LayoutKind.Sequential)]
public struct LSA_UNICODE_STRING
{
  public UInt16 Length;
  public UInt16 MaximumLength;
  public IntPtr Buffer;
}

[StructLayout(LayoutKind.Sequential)]
public struct LSA_OBJECT_ATTRIBUTES
{
  public int Length;
  public IntPtr RootDirectory;
  public LSA_UNICODE_STRING ObjectName;
  public uint Attributes;
  public IntPtr SecurityDescriptor;
  public IntPtr SecurityQualityOfService;
}

public enum LSA_AccessPolicy : long
{
  POLICY_VIEW_LOCAL_INFORMATION = 0x00000001L,
  POLICY_VIEW_AUDIT_INFORMATION = 0x00000002L,
  POLICY_GET_PRIVATE_INFORMATION = 0x00000004L,
  POLICY_TRUST_ADMIN = 0x00000008L,
  POLICY_CREATE_ACCOUNT = 0x00000010L,
  POLICY_CREATE_SECRET = 0x00000020L,
  POLICY_CREATE_PRIVILEGE = 0x00000040L,
  POLICY_SET_DEFAULT_QUOTA_LIMITS = 0x00000080L,
  POLICY_SET_AUDIT_REQUIREMENTS = 0x00000100L,
  POLICY_AUDIT_LOG_ADMIN = 0x00000200L,
  POLICY_SERVER_ADMIN = 0x00000400L,
  POLICY_LOOKUP_NAMES = 0x00000800L,
  POLICY_NOTIFICATION = 0x00001000L
}

[DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
public static extern uint LsaRetrievePrivateData(
  IntPtr PolicyHandle,
  ref LSA_UNICODE_STRING KeyName,
  out IntPtr PrivateData
);

[DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
public static extern uint LsaStorePrivateData(
  IntPtr policyHandle,
  ref LSA_UNICODE_STRING KeyName,
  ref LSA_UNICODE_STRING PrivateData
);

[DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
public static extern uint LsaOpenPolicy(
  ref LSA_UNICODE_STRING SystemName,
  ref LSA_OBJECT_ATTRIBUTES ObjectAttributes,
  uint DesiredAccess,
  out IntPtr PolicyHandle
);

[DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
public static extern uint LsaNtStatusToWinError(
  uint status
);

[DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
public static extern uint LsaClose(
  IntPtr policyHandle
);

[DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
public static extern uint LsaFreeMemory(
  IntPtr buffer
);
"@

}

  Process{
    foreach($key in $RegistryKey) {
      $regPath = "HKLM:\\SECURITY\Policy\Secrets\" + $key
      $tempRegPath = "HKLM:\\SECURITY\Policy\Secrets\MySecret"
      $myKey = "MySecret"
      if(Test-Path $regPath) {
        Try {
          Get-ChildItem $regPath -ErrorAction Stop | Out-Null
        }
        Catch {
          Write-Error -Message "Access to registry Denied, run as NT AUTHORITY\SYSTEM" -Category PermissionDenied
          Break
        }      

        if(Test-Path $regPath) {
          # Copy Key
          "CurrVal","OldVal","OupdTime","CupdTime","SecDesc" | ForEach-Object {
            $copyFrom = "HKLM:\SECURITY\Policy\Secrets\" + $key + "\" + $_
            $copyTo = "HKLM:\SECURITY\Policy\Secrets\MySecret\" + $_

            if( -not(Test-Path $copyTo) ) {
              mkdir $copyTo | Out-Null
            }
            $item = Get-ItemProperty $copyFrom
            Set-ItemProperty -Path $copyTo -Name '(default)' -Value $item.'(default)'
          }
        }
        # Attributes
        $objectAttributes = New-Object LSAUtil.LSAUtil+LSA_OBJECT_ATTRIBUTES
        $objectAttributes.Length = 0
        $objectAttributes.RootDirectory = [IntPtr]::Zero
        $objectAttributes.Attributes = 0
        $objectAttributes.SecurityDescriptor = [IntPtr]::Zero
        $objectAttributes.SecurityQualityOfService = [IntPtr]::Zero

        # localSystem
        $localsystem = New-Object LSAUtil.LSAUtil+LSA_UNICODE_STRING
        $localsystem.Buffer = [IntPtr]::Zero
        $localsystem.Length = 0
        $localsystem.MaximumLength = 0

        # Secret Name
        $secretName = New-Object LSAUtil.LSAUtil+LSA_UNICODE_STRING
        $secretName.Buffer = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($myKey)
        $secretName.Length = [Uint16]($myKey.Length * [System.Text.UnicodeEncoding]::CharSize)
        $secretName.MaximumLength = [Uint16](($myKey.Length + 1) * [System.Text.UnicodeEncoding]::CharSize)

        # Get LSA PolicyHandle
        $lsaPolicyHandle = [IntPtr]::Zero
        [LSAUtil.LSAUtil+LSA_AccessPolicy]$access = [LSAUtil.LSAUtil+LSA_AccessPolicy]::POLICY_GET_PRIVATE_INFORMATION
        $lsaOpenPolicyHandle = [LSAUtil.LSAUtil]::LSAOpenPolicy([ref]$localSystem, [ref]$objectAttributes, $access, [ref]$lsaPolicyHandle)

        if($lsaOpenPolicyHandle -ne 0) {
          Write-Warning "lsaOpenPolicyHandle Windows Error Code: $lsaOpenPolicyHandle"
          Continue
        }

        # Retrieve Private Data
        $privateData = [IntPtr]::Zero
        $ntsResult = [LSAUtil.LSAUtil]::LsaRetrievePrivateData($lsaPolicyHandle, [ref]$secretName, [ref]$privateData)

        $lsaClose = [LSAUtil.LSAUtil]::LsaClose($lsaPolicyHandle)

        $lsaNtStatusToWinError = [LSAUtil.LSAUtil]::LsaNtStatusToWinError($ntsResult)

        if($lsaNtStatusToWinError -ne 0) {
          Write-Warning "lsaNtsStatusToWinError: $lsaNtStatusToWinError"
        }

        [LSAUtil.LSAUtil+LSA_UNICODE_STRING]$lusSecretData =
        [LSAUtil.LSAUtil+LSA_UNICODE_STRING][System.Runtime.InteropServices.marshal]::PtrToStructure($privateData, [System.Type][LSAUtil.LSAUtil+LSA_UNICODE_STRING])

        Try {
          [string]$value = [System.Runtime.InteropServices.marshal]::PtrToStringAuto($lusSecretData.Buffer)
          $value = $value.SubString(0, ($lusSecretData.Length / 2))
        }
        Catch {
          $value = ""
        }

        if($key -match "^_SC_") {
          # Get Service Account
          $serviceName = $key -Replace "^_SC_"
          Try {
            # Get Service Account
            $service = Get-WmiObject -Query "SELECT StartName FROM Win32_Service WHERE Name = '$serviceName'" -ErrorAction Stop
            $account = $service.StartName
          }
          Catch {
            $account = ""
          }
        } else {
          $account = ""
        }

        # Return Object
        New-Object PSObject -Property @{
          Name = $key;
          Secret = $value;
          Account = $Account
        } | Select-Object Name, Account, Secret, @{Name="ComputerName";Expression={$env:COMPUTERNAME}}
      } else {
        Write-Error -Message "Path not found: $regPath" -Category ObjectNotFound
      }
    }
  }
  end {
    if(Test-Path $tempRegPath) {
      Remove-Item -Path "HKLM:\\SECURITY\Policy\Secrets\MySecret" -Recurse -Force
    }
  }
}

try {

    Write-Output "Get-TSLsaSecret"
    try { $secret01 = Get-TSLsaSecret -regkey "DefaultPassword" } catch { Write-Output "Exception: Get-TSLsaSecret" }
    Write-Output "Get-TSLsaSecret - Done?"

    if(-not $secret01) {

        Write-Output "Oppps: Cannot Get-TSLsaSecret"
        $Results += "Oppps: Cannot Get-TSLsaSecret. | "

    } else {

        Write-Output "Get-TSLsaSecret. Value of DefaultPassword decrypted."
        $Results += "Get-TSLsaSecret. Value of DefaultPassword decrypted. | "
    
    }

    $RebootAllowed = "%RebootAllowed%" # if 'no', do not reboot in any circumstances

    $reboot_flag = $false # initial value

} catch {
     Write-Output "Exception in Get-TSLsaSecret code."
     $Results += "Exception in Get-TSLsaSecret code. | "
}

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
 
namespace PInvoke.LSAUtil {
    public class LSAutil {
        [StructLayout (LayoutKind.Sequential)]
        private struct LSA_UNICODE_STRING {
            public UInt16 Length;
            public UInt16 MaximumLength;
            public IntPtr Buffer;
        }
 
        [StructLayout (LayoutKind.Sequential)]
        private struct LSA_OBJECT_ATTRIBUTES {
            public int Length;
            public IntPtr RootDirectory;
            public LSA_UNICODE_STRING ObjectName;
            public uint Attributes;
            public IntPtr SecurityDescriptor;
            public IntPtr SecurityQualityOfService;
        }
 
        private enum LSA_AccessPolicy : long {
            POLICY_VIEW_LOCAL_INFORMATION = 0x00000001L,
            POLICY_VIEW_AUDIT_INFORMATION = 0x00000002L,
            POLICY_GET_PRIVATE_INFORMATION = 0x00000004L,
            POLICY_TRUST_ADMIN = 0x00000008L,
            POLICY_CREATE_ACCOUNT = 0x00000010L,
            POLICY_CREATE_SECRET = 0x00000020L,
            POLICY_CREATE_PRIVILEGE = 0x00000040L,
            POLICY_SET_DEFAULT_QUOTA_LIMITS = 0x00000080L,
            POLICY_SET_AUDIT_REQUIREMENTS = 0x00000100L,
            POLICY_AUDIT_LOG_ADMIN = 0x00000200L,
            POLICY_SERVER_ADMIN = 0x00000400L,
            POLICY_LOOKUP_NAMES = 0x00000800L,
            POLICY_NOTIFICATION = 0x00001000L
        }
 
        [DllImport ("advapi32.dll", SetLastError = true, PreserveSig = true)]
        private static extern uint LsaStorePrivateData (
            IntPtr policyHandle,
            ref LSA_UNICODE_STRING KeyName,
            ref LSA_UNICODE_STRING PrivateData
        );
 
        [DllImport ("advapi32.dll", SetLastError = true, PreserveSig = true)]
        private static extern uint LsaOpenPolicy (
            ref LSA_UNICODE_STRING SystemName,
            ref LSA_OBJECT_ATTRIBUTES ObjectAttributes,
            uint DesiredAccess,
            out IntPtr PolicyHandle
        );
 
        [DllImport ("advapi32.dll", SetLastError = true, PreserveSig = true)]
        private static extern uint LsaNtStatusToWinError (
            uint status
        );
 
        [DllImport ("advapi32.dll", SetLastError = true, PreserveSig = true)]
        private static extern uint LsaClose (
            IntPtr policyHandle
        );
 
        [DllImport ("advapi32.dll", SetLastError = true, PreserveSig = true)]
        private static extern uint LsaFreeMemory (
            IntPtr buffer
        );
 
        private LSA_OBJECT_ATTRIBUTES objectAttributes;
        private LSA_UNICODE_STRING localsystem;
        private LSA_UNICODE_STRING secretName;
 
        public LSAutil (string key) {
            if (key.Length == 0) {
                throw new Exception ("Key lenght zero");
            }
 
            objectAttributes = new LSA_OBJECT_ATTRIBUTES ();
            objectAttributes.Length = 0;
            objectAttributes.RootDirectory = IntPtr.Zero;
            objectAttributes.Attributes = 0;
            objectAttributes.SecurityDescriptor = IntPtr.Zero;
            objectAttributes.SecurityQualityOfService = IntPtr.Zero;
 
            localsystem = new LSA_UNICODE_STRING ();
            localsystem.Buffer = IntPtr.Zero;
            localsystem.Length = 0;
            localsystem.MaximumLength = 0;
 
            secretName = new LSA_UNICODE_STRING ();
            secretName.Buffer = Marshal.StringToHGlobalUni (key);
            secretName.Length = (UInt16) (key.Length * UnicodeEncoding.CharSize);
            secretName.MaximumLength = (UInt16) ((key.Length + 1) * UnicodeEncoding.CharSize);
        }
 
        private IntPtr GetLsaPolicy (LSA_AccessPolicy access) {
            IntPtr LsaPolicyHandle;
            uint ntsResult = LsaOpenPolicy (ref this.localsystem, ref this.objectAttributes, (uint) access, out LsaPolicyHandle);
            uint winErrorCode = LsaNtStatusToWinError (ntsResult);
            if (winErrorCode != 0) {
                throw new Exception ("LsaOpenPolicy failed: " + winErrorCode);
            }
            return LsaPolicyHandle;
        }
 
        private static void ReleaseLsaPolicy (IntPtr LsaPolicyHandle) {
            uint ntsResult = LsaClose (LsaPolicyHandle);
            uint winErrorCode = LsaNtStatusToWinError (ntsResult);
            if (winErrorCode != 0) {
                throw new Exception ("LsaClose failed: " + winErrorCode);
            }
        }
 
        private static void FreeMemory (IntPtr Buffer) {
            uint ntsResult = LsaFreeMemory (Buffer);
            uint winErrorCode = LsaNtStatusToWinError (ntsResult);
            if (winErrorCode != 0) {
                throw new Exception ("LsaFreeMemory failed: " + winErrorCode);
            }
        }
 
        public void SetSecret (string value) {
            LSA_UNICODE_STRING lusSecretData = new LSA_UNICODE_STRING ();
 
            if (value.Length > 0) {
                //Create data and key
                lusSecretData.Buffer = Marshal.StringToHGlobalUni (value);
                lusSecretData.Length = (UInt16) (value.Length * UnicodeEncoding.CharSize);
                lusSecretData.MaximumLength = (UInt16) ((value.Length + 1) * UnicodeEncoding.CharSize);
            } else {
                //Delete data and key
                lusSecretData.Buffer = IntPtr.Zero;
                lusSecretData.Length = 0;
                lusSecretData.MaximumLength = 0;
            }
 
            IntPtr LsaPolicyHandle = GetLsaPolicy (LSA_AccessPolicy.POLICY_CREATE_SECRET);
            uint result = LsaStorePrivateData (LsaPolicyHandle, ref secretName, ref lusSecretData);
            ReleaseLsaPolicy (LsaPolicyHandle);
 
            uint winErrorCode = LsaNtStatusToWinError (result);
            if (winErrorCode != 0) {
                throw new Exception ("StorePrivateData failed: " + winErrorCode);
            }
        }
    }
}
"@

try {

    if(-not $secret01) {

        Write-Output "Previous password unknown. Setting the password." 
        [PInvoke.LSAUtil.LSAutil]::new("DefaultPassword").SetSecret("%PASSWORD%")
        $reboot_flag = $true # we are not sure about the previous value

        $Results += "Previous password unknown. Setting the password. | " 

    } else {    

        Write-Output "Comparing stored and new password."
        if($secret01.Secret -like "%PASSWORD%") {
            Write-Output "Done. Same password. No need to change the password."
            $Results += "Same password. No need to change the password. | "
        } else {     
            Write-Output "Passwords are different. Setting the password." 
            [PInvoke.LSAUtil.LSAutil]::new("DefaultPassword").SetSecret("%PASSWORD%")
            Write-Output "Done. New DefaultPassword configured." 
            $Results += "New DefaultPassword configured. | " 
            $reboot_flag = $true
        }

    }

} catch {
    Write-Output "Exception when setting the password." 
    $Results += "Exception when setting the password. | " 
}


$username = "%USERNAME%"
Write-Output "User name: $username"

# Testing if the new password works - modify tests below to fit your scenario
# Modify the reporting part to include the results of these tests ($Results += "...")

# TEST #1 

    # run CALC.EXE with the new account (one of these methods should be sufficient)
    # chose arp.exe or similar, if we want the window to close itself
    $PWord = ConvertTo-SecureString -String "%PASSWORD%" -AsPlainText -Force
    try {
        $User = "<Entra ID Domain>\$($username.Split("@")[0])"
        $usercredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
        Start-process -FilePath "${env:SystemRoot}\system32\calc.exe" -Credential ($usercredentials)
    } catch { Write-Host "Exception #1 - $User" }
    try {
        $User = "azuread\$username"
        $usercredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
        Start-process -FilePath "${env:SystemRoot}\system32\calc.exe" -Credential ($usercredentials)
    } catch { Write-Host "Exception #2 - $User" }
    try {
        $User = "<Entra ID Domain>\$username"
        $usercredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
        Start-process -FilePath "${env:SystemRoot}\system32\calc.exe" -Credential ($usercredentials)
    } catch { Write-Host "Exception #3 - $User" }
    
    # report the status using a webhook that adds an entry to the Sharepoint List https://YourCompany.sharepoint.com/sites/YourSharepointSite/Lists/YourSharepointList
    try {

        # Name: Webhook-ReportingChangeAutologonPassword
        $webhookurl = "https://<webhookURL>"
        $WebhookPassword = 'NONE'

        $SerialNumber = (Get-WmiObject -Class "Win32_BIOS" -Verbose:$false).SerialNumber

          $body = @{ "SerialNumber" = "$SerialNumber"; "ComputerName"="$env:COMPUTERNAME"; "Results" = "$Results"; "Account" = "%USERNAME%"; LOCALSCRIPTVERSION = "%SCRIPTVERSION%" } 

          $params = @{
            ContentType  = 'application/json'
            Headers	      = @{ 'from' = 'Webhook-ReportingChangeAutologonPassword'; 'Date' = "$(Get-Date)"; 'message' = $WebhookPassword }
            Body		 = ($body | convertto-json -ErrorAction Continue)
            Method	     = 'Post'
            URI		     = $webhookurl
          }

          $callingWebhook = Invoke-RestMethod @params -Verbose
          if ($callingWebhook.JobIds) { Write-Output "Successfully started: $($callingWebhook.JobIds)" }
    
    } catch {}

# end

# cleanup and reboot
try {

    Write-Output "RebootAllowed : $RebootAllowed"
    Write-Output "reboot_flag : $reboot_flag"

    # cleanup
        # delete itself (the script)
        Remove-Item -Path "$($path)ChangeAutologonPassword.ps1" -Force -ErrorAction Continue -Verbose
        Write-Output "PS1 removed"

        # delete the scheduled task
        Unregister-ScheduledTask -TaskPath "\YourCompany\" -TaskName "YourCompanyChangeAutologonPassword" -Confirm:$false -ErrorAction Continue -Verbose
        Write-Output "Scheduled task removed"

    if ( ($RebootAllowed -like "yes") -and ($reboot_flag -eq $true) ) { 
        
            Write-Output "Restart to be initiated."
            shutdown.exe /t 150 /r /c "Planned system restart in 2 minutes." 

    }
    
} catch {
    Write-Output "Exception - cleanup and reboot"
}

try{ stop-transcript|out-null } catch {}

# TEST #2 - another test by mapping a network drive using the new password
# We do not want to include it in the transcript, because it shows the password in a clear text

    try {
        $usedDriveLetters = Get-PSDrive | Select-Object -Expand Name | Where-Object { $_.Length -eq 1 }
        $availableDriveLetter = 90..65 | ForEach-Object { [string][char]$_ } | Where-Object { $usedDriveLetters -notcontains $_ } | Select-Object -First 1
        net use "$($availableDriveLetter):" \\<serverName>\<shareName> %PASSWORD% /user:%USERNAME% /persistent:yes
        net use "$($availableDriveLetter):" /delete /y 
        net use "$($availableDriveLetter):" /delete /global /y 
    } catch {
       Write-Output "Exception - test by mapping a network drive using the new password"
    }
'@

function Create-Task ($Argument){    $taskName = "YourCompanyChangeAutologonPassword"

    #if there is such scheduled task, delete it
    Unregister-ScheduledTask -TaskPath "\YourCompany\" -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue  -Verbose

    # Create a new action that will run the script
    
    # IMPORTANT:
    
        # Run PowerShell in 32-bit mode - C:\Windows\SysWOW64\WindowsPowerShell\v1.0 [Get-TSLsaSecret requires 32bit Powershell]
        # Run PowerShell in 64-bit mode - C:\Windows\System32\WindowsPowerShell\v1.0 [Default]

    $action = New-ScheduledTaskAction -Execute "$($env:windir)\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass $($Argument)"

    # Define the trigger to be only once at a specific time
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15) # executed right after this script finishes, usually 10 seconds is enough 
    
    # https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset?view=windowsserver2022-ps
    $Settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 3 -DisallowHardTerminate -StartWhenAvailable -DontStopOnIdleEnd -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 0 -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1) 

    # Register the scheduled task
    $TargetTask = Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -TaskPath "\YourCompany\" -Description "Temporary - set Autologon password" -User "SYSTEM" -RunLevel Highest -Verbose -Force -Settings $Settings
          
        # In order to use DeleteExpiredTaskAfter, you need to set an StartBoundary & EndBoundary date/time to the trigger
        $TargetTask.Triggers[0].EndBoundary = [DateTime]::Now.AddMinutes(5).ToString("yyyy-MM-dd'T'HH:mm:ss") 

        # If the task is not scheduled to run again, delete it after: immediately
        $TargetTask.Settings.DeleteExpiredTaskAfter = "PT0S"
        $TargetTask | Set-ScheduledTask
                 
    return $TargetTask}
 
$Code = $Code.Replace("%USERNAME%", $Username)
$Code = $Code.Replace("%PASSWORD%", $Password)
$Code = $Code.Replace("%DOMAINNAME%", $DomainName)
$Code = $Code.Replace("%RebootAllowed%", $RebootAllowed)
$Code = $Code.Replace("%SCRIPTVERSION%", $version)

$path = "C:\ProgramData\YourCompany\Intune\" 

    # create the YourCompany folder to store the transcript

    ##################################################################################################################
    ####### Create folder $path ####################################################################################
    ##################################################################################################################

    try {
        # Create folder if not exists
        if (-not (Test-Path "$Path")) {
            $null = New-Item -Path "$Path" -ItemType Directory -ErrorAction Stop
        }

    } catch {

        try {
            $exception = $_.Exception
            Write-Warning $exception.GetType().FullName
            Write-Warning $exception.Message 
            Write-Warning $exception.StackTrace 
            Write-Warning $exception.InnerException
        } catch {}

        Write-Output "# $(timestamp): Exception while creating folder $path - $($exception.GetType().FullName) - $($exception.Message). Exiting."
        exit 1

    }

    try {
        Stop-Transcript -ErrorAction SilentlyContinue     # Stop-Transcript, in case some lingering transcript is running
    } catch {}

    ##################################################################################################################
    ##### Grant permissions to SYSTEM:Full control to "C:\ProgramData\YourCompany\" ###################################
    ##################################################################################################################

        try {
            # Get current access permissions from folder and store in object
            $Access = Get-Acl -Path "C:\ProgramData\YourCompany\" -ErrorAction Stop

            # Create new object with required new permissions
            $NewRule = New-Object System.Security.AccessControl.FileSystemAccessRule ("SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow") -ErrorAction Stop

            # Add new rule to our copy of the current rules
            $Access.AddAccessRule($NewRule)

            # Apply our new rule object to destination folder
            Set-Acl -Path "C:\ProgramData\YourCompany\" -AclObject $Access -ErrorAction Stop

        } catch {
    
            try {
                $exception = $_.Exception
                Write-Warning $exception.GetType().FullName
                Write-Warning $exception.Message # .ToString().Replace("`r`n", " ").Replace("`n", " ")
                Write-Warning $exception.StackTrace # .ToString().Replace("`r`n", " ").Replace("`n", " ")
                Write-Warning $exception.InnerException
            } catch {}

            Write-Output "# $(timestamp): Exception while granting permissions SYSTEM:Full control to $path - $($exception.GetType().FullName) - $($exception.Message)"
    
        }

    ##################################################################################################################
    ####### start Task Scheduler service, if not running ########################################################
    ##################################################################################################################
    
        try {

            # Get the status of the Task Scheduler service
            $service = Get-Service -Name Schedule -ErrorAction Stop

            # If the service is not running, start it
            if ($service.Status -ne "Running") { Start-Service -Name Schedule -ErrorAction Continue }

            # If the service is not set to automatic, change it
            if ($service.StartType -ne "Automatic") { Set-Service -Name Schedule -StartupType Automatic -ErrorAction SilentlyContinue } ### Set-Service : Service 'Task Scheduler (Schedule)' cannot be configured due to the following error: Access is denied

            # enable scheduled tasks history
            # wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true

            # enable task history (SLOWS DOWN TASK SCHEDULER CONSOLE)
        
                # Get the name of the task scheduler event log
                # Create an object to access the event log configuration
                $log = New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration 'Microsoft-Windows-TaskScheduler/Operational' -Verbose

                # Set the IsEnabled property to true, if disabled
                if(-not $log.IsEnabled) {
                    $log.IsEnabled=$true
                    $log.SaveChanges()         # Save the changes
                }

        } catch {
    
            try {
                $exception = $_.Exception
                Write-Warning $exception.GetType().FullName
                Write-Warning $exception.Message 
                Write-Warning $exception.StackTrace 
                Write-Warning $exception.InnerException
            } catch {}

            Write-Output "# $(timestamp): Exception while starting Task Scheduler service (if not running) - $($exception.GetType().FullName) - $($exception.Message)"
       
        }

$Code | Out-File "$($path)ChangeAutologonPassword.ps1" -force

    # We need to change these registry entries here (and not in $Code), because SYSTEM does not have an access to "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

    # user name and domain name
    try{

        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultUserName" -Value "$Username" -PropertyType string -ErrorAction Continue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultUserName" -Value "$Username" -Force -PassThru -ErrorAction Continue
            
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultDomainName" -Value "$DomainName" -PropertyType string -ErrorAction Continue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultDomainName" -Value "$DomainName" -Force -PassThru -ErrorAction Continue

    } catch {
        Write-OUtput "Exception - user name and domain name" # I know, when using '-ErrorAction Continue' above, this exception will never be raised
    }

    try{

        # if the "Name" does not exist, create it ... if it exists, New-ItemProperty it WILL NOT update it, that is why use Set-ItemProperty 
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value "1" -PropertyType string -ErrorAction Continue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value "1" -Force -PassThru -ErrorAction Continue
   
        # remove the default password if stored in the clear text
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -Force -ErrorAction Continue

    } catch {
        Write-OUtput "Exception - AutoAdminLogon and removing clear text DefaultPassword"
    }
    
Create-Task -Argument "-file ""$($path)ChangeAutologonPassword.ps1"""

# cleanup

    try {

        # Since Intune keeps the local copies of the detection and remediation scripts (requires local admin to access the folder), delete the local copy of this script...
        $tmpScript = $MyInvocation.MyCommand.Path
        # remove the script if it runs as a Remediation
        if ($tmpScript.StartsWith("$([System.Environment]::GetEnvironmentVariable("ProgramFiles(x86)"))\Microsoft Intune Management Extension\")) {
            Remove-Item $tmpScript -Force
        } 
    
    } catch {}

exit 0