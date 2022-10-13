<# 

 Description: Launch Remote desktop shadowing session
 Author: Lubos Nikolini
 Wiki: https://github.com/najki78/publicStuff/wiki/Remote-desktop-shadowing-is-Microsoft's-free-alternative-to-VNC,-TeamViewer,-DameWare-etc.-(well,-sort-of-and-only-sometimes)
 
 Important:
    Run the script under user account that is a member of local Administrators on the remote machine (or has special permissions - details in Wiki)

 Version history:

    2022-03-10A using IP instead of FQDN to avoid issues (Error 0x00000721 enumerating sessionnames ... Error [1825]:A security package specific error occurred.)
    2022-08-02 consider removing mstsc /span parameter, in case of issues (distorted image)
    2022-09-23 added troubleshooting tips
    2022-10-13 displaying the logged on account info (for troubleshooting purposes)
    
#> 

<#
# Convert to EXE file by running
# https://github.com/MScholtes/PS2EXE
Install-Module ps2exe
Invoke-ps2exe "LaunchShadowSession.ps1"
#>

$domain1 = ".mydomain.com"
$domain2 = ".my2nddomain.com"
$registryPath = "HKCU:\SOFTWARE\RemoteDesktopShadowing"  

$version = "2022-10-13C"
cls

Remove-Variable -Name value -ErrorAction SilentlyContinue
Remove-Variable -Name compName -ErrorAction SilentlyContinue
Remove-Variable -Name ipAddy -ErrorAction SilentlyContinue
Remove-Variable -Name line -ErrorAction SilentlyContinue
Remove-Variable -Name message -ErrorAction SilentlyContinue
Remove-Variable -Name sessionID -ErrorAction SilentlyContinue
Remove-Variable -Name whoami -ErrorAction SilentlyContinue
Remove-Variable -Name timeout -ErrorAction SilentlyContinue
Remove-Variable -Name ping -ErrorAction SilentlyContinue
Remove-Variable -Name response -ErrorAction SilentlyContinue

# https://devblogs.microsoft.com/scripting/automating-quser-through-powershell/

# https://community.spiceworks.com/scripts/show/4408-get-logged-in-users-remote-computers-or-local
function Get-LoggedInUser
{
<#
    .SYNOPSIS
        Shows all the users currently logged in

    .DESCRIPTION
        Shows the users currently logged into the specified computernames

    .PARAMETER ComputerName
        One or more computernames

    .EXAMPLE
        PS C:\> Get-LoggedInUser
        Shows the users logged into the local system

    .EXAMPLE
        PS C:\> Get-LoggedInUser -ComputerName server1,server2,server3
        Shows the users logged into server1, server2, and server3

    .EXAMPLE
        PS C:\> Get-LoggedInUser  | where idletime -gt "1.0:0" | ft
        Get the users who have been idle for more than 1 day.  Format the output
        as a table.

        Note the "1.0:0" string - it must be either a system.timespan datatype or
        a string that can by converted to system.timespan.  Examples:
            days.hours:minutes
            hours:minutes
#>

    [CmdletBinding()]
    param
    (
        [ValidateNotNullOrEmpty()]
        [String[]]$ComputerName = $env:COMPUTERNAME,
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    $out = @()

    ForEach ($computer in $ComputerName)
    {
        try { if (-not (Test-Connection -ComputerName $computer -Quiet -Count 1 -ErrorAction Stop)) { Write-Warning "Can't connect to $computer"; continue } }
        catch { Write-Warning "Can't test connect to $computer"; continue }

        $quserOut = quser.exe /SERVER:$computer 2>&1
        if ($quserOut -match "No user exists")
        { Write-Warning "No users logged in to $computer";  continue }

        $users = $quserOut -replace '\s{2,}', ',' |
        ConvertFrom-CSV -Header 'username', 'sessionname', 'id', 'state', 'idleTime', 'logonTime' |
        Add-Member -MemberType NoteProperty -Name ComputerName -Value $computer -PassThru

        $users = $users[1..$users.count]

        for ($i = 0; $i -lt $users.count; $i++)
        {
            if ($users[$i].sessionname -match '^\d+$')
            {
                $users[$i].logonTime = $users[$i].idleTime
                $users[$i].idleTime = $users[$i].STATE
                $users[$i].STATE = $users[$i].ID
                $users[$i].ID = $users[$i].SESSIONNAME
                $users[$i].SESSIONNAME = $null
            }

            # cast the correct datatypes
            $users[$i].ID = [int]$users[$i].ID

            $idleString = $users[$i].idleTime
            if ($idleString -eq '.') { $users[$i].idleTime = 0 }

            # if it's just a number by itself, insert a '0:' in front of it. Otherwise [timespan] cast will interpret the value as days rather than minutes
            if ($idleString -match '^\d+$')
            { $users[$i].idleTime = "0:$($users[$i].idleTime)" }

            # if it has a '+', change the '+' to a colon and add ':0' to the end
            if ($idleString -match "\+")
            {
                $newIdleString = $idleString -replace "\+", ":"
                $newIdleString = $newIdleString + ':0'
                $users[$i].idleTime = $newIdleString
            }

          ###  $users[$i].idleTime = [timespan]$users[$i].idleTime
            #$users[$i].logonTime = [datetime]$users[$i].logonTime
        }
        $users = $users | Sort-Object -Property idleTime
        $out += $users
    }
    Write-Output $out
}

$whoami = whoami
if(-not $whoami) { $whoami = (Get-LoggedInUser).username }

Function port-scan-tcp {
# https://github.com/InfosecMatter/Minimalistic-offensive-security-tools/blob/master/port-scan-tcp.ps1

# Open - OK
# Filtered - no connection or some other problem

# Examples:
#
# port-scan-tcp 10.10.0.1 137
# port-scan-tcp 10.10.0.1 (135,137,445)
# port-scan-tcp (gc .\ips.txt) 137
# port-scan-tcp (gc .\ips.txt) (135,137,445)
# 0..255 | foreach { port-scan-tcp 10.10.0.$_ 137 }
# 0..255 | foreach { port-scan-tcp 10.10.0.$_ (135,137,445) }

  param($hosts,$ports)
  if (!$ports) {
    Write-Host "usage: port-scan-tcp <host|hosts> <port|ports>"
    Write-Host " e.g.: port-scan-tcp 192.168.1.2 445`n"
    return
  }

    $out = "$env:temp\scanresults.txt"
    try {
        foreach($p in [array]$ports) {
        foreach($h in [array]$hosts) {
        $x = (gc $out -EA SilentlyContinue | select-string "^$h,tcp,$p,")
        if ($x) {
            gc $out | select-string "^$h,tcp,$p,"
            continue
        }
        $msg = "$h,tcp,$p,"
        $t = new-Object system.Net.Sockets.TcpClient
        $c = $t.ConnectAsync($h,$p)
        for($i=0; $i -lt 10; $i++) {
            if ($c.isCompleted) { break; }
            sleep -milliseconds 100
        }
        $t.Close();
        $r = "Filtered"
        if ($c.isFaulted -and $c.Exception -match "actively refused") {
            $r = "Closed"
        } elseif ($c.Status -eq "RanToCompletion") {
            $r = "Open"
        }
        $msg += $r
        Write-Host "$msg"
        echo $msg >>$out
        }
        }
        #return $r

    } catch {
        # $_.Exception.Message 
        Write-Host "`n" $_ -ForegroundColor DarkYellow
        #Write-Host "The error occurs when running the command against the local machine (cannot portscan itself)." $_ -ForegroundColor Yellow

        Write-Host "`nYou cannot shadow your own session. Exiting." -foregroundcolor red
        Read-Host "Press Enter to exit..."
        exit
    }

    Remove-Item -Path $out -Force -ErrorAction SilentlyContinue

}

# retrieve the last target device from registry
New-PSDrive -Name HKCU -PSProvider Registry -Root HKEY_CURRENT_USER -erroraction silentlycontinue | out-null
$Name = "TargetDevices"
$value = ""

# check if key exists, if not, create it
IF(!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }

$value = ((Get-ItemProperty -Path $registryPath -Name $Name -ErrorAction SilentlyContinue).$Name)

# https://petri.com/prompt-answers-powershell

if($value) { # if there are some previous entries in registry

    $value = $value | ?{$_.Trim()} | select $_ -Last 1 # remove blank lines
    
    do {
        $compNameObject = $host.ui.Prompt("Remote desktop shadowing (version: $($version)) using '$($whoami)'","Enter a target computer name, IP address or press Enter to use the most recent value ($($value))","Name")
        [string]$compName = $compNameObject.Name.Trim()
        if($compName -eq "") { $compName = $value }
    } until ($compName)

} else {

    do {
        $compNameObject = $host.ui.Prompt("Remote desktop shadowing (version: $($version)) using '$($whoami)'","Enter a target computer name or IP address","Name")
        [string]$compName = $compNameObject.Name.Trim()
    } until ($compName)

}

try {
    $ipAddy = [System.Net.Dns]::GetHostAddresses($compName)[0].IPAddressToString
} catch {
    
    try { # maybe only NetBIOS name entered, try to add $domain1 
        $compName = $compName.Split(".")[0] + $domain1 
        $ipAddy = [System.Net.Dns]::GetHostAddresses($compName)[0].IPAddressToString
    } catch {

        try { # maybe only NetBIOS name entered, try to add $domain2
            $compName = $compName.Split(".")[0] + $domain2
            $ipAddy = [System.Net.Dns]::GetHostAddresses($compName)[0].IPAddressToString
        } catch {
            Write-Host $_ -ForegroundColor Red
        }

    }
}

if( ($ipAddy -eq "::1") -or ($ipAddy -eq "127.0.0.1") ) {
    Write-Host "You cannot shadow your own session. Exiting." -foregroundcolor red
    Read-Host "Press Enter to exit..."
    exit
}

if(-not $ipAddy) {
    Write-Host "No IP address found in DNS for $($compName). Connection not possible. Exiting." -foregroundcolor red
    Read-Host "Press Enter to exit..."
    exit
}

# add to registry --- keeping last value of target computer
$value = $compName
New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType Multistring -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Connecting to (hostname): " $compName
Write-Host "Connecting to (IP address): " $ipAddy

# PING --- it mimics get-wmiobject -class win32_pingstatus
#Test-Connection -ComputerName $compName -Count 1 | Format-Table -AutoSize -Wrap

try {
    $Timeout = 1000
    $Ping = New-Object System.Net.NetworkInformation.Ping
    $Response = $Ping.Send($ipAddy,$Timeout)
    Write-Host "`nPing response (for troubleshooting purposes): " $Response.Status
    # Status = TimedOut, Success

} catch {
    # $_.Exception.Message 
    Write-Host $_ -ForegroundColor Red # continue despite the exception, although probably it will fail later, maybe ping-ing your own machine 
}

##### check if the device responds or if not "Exception calling "GetHostAddresses" with "1" argument(s): "No such host is known""
#port-scan-tcp $ipAddy (3389,5985,5986,80,443,445)

Write-Host "`nFirewall status on the target machine (for troubleshooting purposes):" #-NoNewline

port-scan-tcp $ipAddy (135)
port-scan-tcp $ipAddy (3389)
port-scan-tcp $ipAddy (445)
#$portScanResult 
# if not "Open", do not even continue...

try {
    
    # Redirection https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-7.2
    $quser_command = [string](quser console /server:$ipAddy 3>&1 2>&1)

} catch {
    # $_.Exception.Message 
    Write-Host $_ -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit 1
}


$sessionID = "" # default value
$message = "Error: Unable to establish shadowing session.`nEither there is no user logged on at the console or the user has not been detected.`nThis occurs mostly due to the blocked connection to the target machine."

foreach ($line in ($quser_command)){
      
    Write-Host "`nOutput (for troubleshooting purposes): `n" $line    -ForegroundColor gray

    if ($line.contains("SESSIONNAME")){ 
        $sessionID = $line.split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[10] # next value after "console"
        Write-Host "`nConsole session ID: " $sessionID -ForegroundColor Yellow
    } 

    if ($line.contains("No User exists for console")){  
        $message = "`nError: Unable to establish shadowing session.`nEither there is no user logged on at the console OR the user '$($whoami)' is not member of neither Administrators, Remote Desktop Users group(s) nor has special permissions granted on the target machine." #### ...and cannot run QUSER command - same error message it both cases "No User exists for console"
    }

    if ($line.contains("Error [1722]")){  # Error [1722]:The RPC server is unavailable.
        $message = "`nError: Unable to establish shadowing session.`nThe console user information not retrieved. Often due to the blocked tcp/445 connection to the target machine OR the machine is shutting down / restarting."
    }
    
} 

if ($sessionID) {

    Write-Host "`nTo remotely logoff remote console session (for troubleshooting purposes only): " -NoNewline -ForegroundColor gray
    Write-Host "logoff $($sessionID) /server:$($ipAddy)" -ForegroundColor DarkGray
    
    Start-Process "$($env:windir)\system32\mstsc.exe" -ArgumentList "/v:$($ipAddy) /control /noconsentprompt /span /shadow:$($sessionID)" 

} else {
    Write-Host $message -ForegroundColor Red
}

    Write-Host "`nVisit " -NoNewline 
    Write-Host "https://github.com/najki78/publicStuff/wiki/Remote-desktop-shadowing-is-Microsoft's-free-alternative-to-VNC,-TeamViewer,-DameWare-etc.-(well,-sort-of-and-only-sometimes)" -NoNewline -ForegroundColor gray
    Write-Host " for more information about Shadowing."
    
    Write-Host "`nIf Shadowing is not working, try to remotely connect using traditional remote desktop connection: " -NoNewline 
    Write-Host "mstsc /console /v:$($ipAddy)" -ForegroundColor gray
    Write-Host "Note: The 'traditional' remote desktop connection is allowed only when your account '$($whoami)' is a member of Remote Desktop Users group on the remote machine."
    Write-Host "Important: Unlike Shadowing, such connection will NOT be visible for the user behind the remote machine."

# Wait for Enter (other keypress methods did not work for me)
Read-Host "`nPress Enter to exit..."