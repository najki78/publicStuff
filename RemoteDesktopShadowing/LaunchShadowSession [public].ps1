
$version = "2022-08-15B"

cls

<# 

 Description: Launch Remote desktop shadowing session
 Author: Lubos Nikolini

 Important:
    Run the script under user account that is a member of local Administrators on the remote machine 

 Version history:

    2022-03-10A using IP instead of FQDN to avoid issues (Error 0x00000721 enumerating sessionnames ... Error [1825]:A security package specific error occurred.)
    2022-08-02 consider removing mstsc /span parameter, in case of issues (distorted image)
    
#> 


<#
# Convert to EXE file by running
# https://github.com/MScholtes/PS2EXE
Install-Module ps2exe
Invoke-ps2exe "LaunchShadowSession [public].ps1"
#>


Remove-Variable -Name value -ErrorAction SilentlyContinue
Remove-Variable -Name compName -ErrorAction SilentlyContinue
Remove-Variable -Name ipAddy -ErrorAction SilentlyContinue
Remove-Variable -Name line -ErrorAction SilentlyContinue
Remove-Variable -Name message -ErrorAction SilentlyContinue
Remove-Variable -Name sessionID -ErrorAction SilentlyContinue

# https://devblogs.microsoft.com/scripting/automating-quser-through-powershell/

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
        Write-Host "The error occurs when running the command against the local machine (cannot portscan itself)." $_ -ForegroundColor Yellow
    }

    Remove-Item -Path $out -Force -ErrorAction SilentlyContinue

}


#### retrieve the last target device from registry

New-PSDrive -Name HKCU -PSProvider Registry -Root HKEY_CURRENT_USER -erroraction silentlycontinue | out-null

$registryPath = "HKCU:\SOFTWARE\RemoteDesktopShadowing"
$Name = "TargetDevices"
$value = ""

# check if key exists, if not, create it
IF(!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }

$value = ((Get-ItemProperty -Path $registryPath -Name $Name -ErrorAction SilentlyContinue).$Name)

if ($value) {
    $value = $value | ?{$_.Trim()} | select $_ -Last 5 # remove blank lines
    $value = $value | Select-Object -Unique
} else  { 
    # if Name property does not exist, create it
    New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType Multistring -Force -ErrorAction SilentlyContinue | Out-Null 
}


# https://petri.com/prompt-answers-powershell
#Write-Host "Previous values: " $value

if($value) { # if there are some previous entries in registry

    do {
        $compNameObject = $host.ui.Prompt("Remote desktop shadowing (version: $($version))","Enter a target computer name, IP address or press Enter to use the most recent value ($($value[$value.Length - 1]))","Name")
        [string]$compName = $compNameObject.Name.Trim()
        if($compName -eq "") { $compName = $value[$value.Length - 1] }
    } until ($compName)

} else {

    do {
        $compNameObject = $host.ui.Prompt("Remote desktop shadowing","Enter a target computer name","Name")
        [string]$compName = $compNameObject.Name.Trim()
    } until ($compName)

}

try {
    $ipAddy = [System.Net.Dns]::GetHostAddresses($compName)[0].IPAddressToString
} catch {
    
    try { # maybe only NetBIOS name entered, try to add ".yourdomain.com"
        $compName = $compName.Split(".")[0] + ".yourdomain.com"  
        $ipAddy = [System.Net.Dns]::GetHostAddresses($compName)[0].IPAddressToString
    } catch {

        try { # maybe only NetBIOS name entered, try to add ".yourseconddomain.com"
            $compName = $compName.Split(".")[0] + ".yourseconddomain.com"
            $ipAddy = [System.Net.Dns]::GetHostAddresses($compName)[0].IPAddressToString
        } catch {
            Write-Host $_ -ForegroundColor Red
        }

    }
}

### add to registry --- keeping last 5 unique values of target computers
$value += $compName
$value = $value | ?{$_.Trim()} | select $_ -Last 5 # remove blank lines
$value = $value | Select-Object -Unique

New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType Multistring -Force -ErrorAction SilentlyContinue | Out-Null


if(-not $ipAddy) {
    Write-Host "No IP address found in DNS for $($compName). Connection not possible. Exiting." -foregroundcolor red
    Read-Host "Press Enter to exit..."
    exit
}

Write-Host "Connecting to (hostname): " $compName
Write-Host "Connecting to (IP address): " $ipAddy

$Timeout = 1000
$Ping = New-Object System.Net.NetworkInformation.Ping
$Response = $Ping.Send($ipAddy,$Timeout)
Write-Host "Ping response: " $Response.Status

Write-Host "Firewall status on the target machine:" #-NoNewline

port-scan-tcp $ipAddy (135)
port-scan-tcp $ipAddy (445) # if "Filtered" or "Closed", the connection will fail

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
$message = "Error: Unable to establish shadowing session (either no user logged on at the console or the user not detected - often due to the blocked connection to the target machine)."

foreach ($line in ($quser_command)){
      
    Write-Host "Output (for troubleshooting purposes): `n" $line    -ForegroundColor gray

    if ($line.contains("SESSIONNAME")){ 
        $sessionID = $line.split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[10] # next value after "console"
        Write-Host "Console session ID: " $sessionID -ForegroundColor Yellow
    } 

    if ($line.contains("No User exists for console")){  
        $message = "Error: Unable to establish shadowing session - no user logged on at the console."
    }

    if ($line.contains("Error [1722]")){  # Error [1722]:The RPC server is unavailable.
        $message = "Error: Unable to establish shadowing session (the console user information not retrieved - often due to the blocked tcp/445 connection to the target machine)."
    }
    
} 

if ($sessionID) {
    
    Start-Process "$($env:windir)\system32\mstsc.exe" -ArgumentList "/v:$($ipAddy) /control /noconsentprompt /span /shadow:$($sessionID)" 

} else {
    Write-Host $message -ForegroundColor Red
}

# Wait for Enter (other keypress methods did not work for me)
Read-Host "Press Enter to exit..."