<#
.SYNOPSIS
  Get System Reserved/EFI partition information
.DESCRIPTION
  Retrieves System Reserved/EFI partition information (important for Windows 11 upgrades - the upgrade requires at least 15 MB free space on the System partition).
.NOTES
  Requires: Administrator privileges
#>

function Write-Log {
  # Uncomment in case you want to log to a file
  <#
  param([string]$Message, [ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level='INFO')
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$timestamp] [$Level] $Message"
  Add-Content -Path $LogPath -Value $line
  $color = switch ($Level) { 'ERROR'{'Red'} 'WARN'{'Yellow'} 'SUCCESS'{'Green'} default{'White'} }
  Write-Host $line -ForegroundColor $color
  #>
}

function Get-AvailableDriveLetter {
  $used = (Get-Volume | Where-Object DriveLetter).DriveLetter
  $cand = @('Y','Z','X','W')
  return ($cand | Where-Object {$_ -notin $used})[0]
}

function Get-SystemPartition {
  try {
    Write-Log "Identifying System/EFI partition..."
    $p = Get-Partition | Where-Object {
      $_.GptType -eq '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' -or $_.Type -eq 'System'
    } | Select-Object -First 1

    if (-not $p) { Write-Log "No System/EFI partition found." 'ERROR'; return $null }

    $dl = $p.DriveLetter
    if ($dl) {
      Write-Log "System partition already mounted at $dl`:"
      return @{ DriveLetter=$dl; WasAlreadyMounted=$true; Partition=$p }
    }

    $letter = Get-AvailableDriveLetter
    if (-not $letter) { Write-Log "No free drive letter available." 'ERROR'; return $null }

    try {
      $p | Set-Partition -NewDriveLetter $letter -ErrorAction Stop
      Write-Log "Mounted using Set-Partition to $letter`:" 'SUCCESS'
      return @{ DriveLetter=$letter; WasAlreadyMounted=$false; Partition=$p; MountedBy='Set-Partition' }
    } catch {
      Write-Log "Set-Partition failed ($($_.Exception.Message)). Trying mountvol /s..."
      mountvol "$letter`:" /s | Out-Null
      if (Test-Path "$letter`:") {
        Write-Log "Mounted using mountvol to $letter`:" 'SUCCESS'
        return @{ DriveLetter=$letter; WasAlreadyMounted=$false; Partition=$p; MountedBy='mountvol' }
      } else {
        Write-Log "Failed to mount System partition." 'ERROR'
        return $null
      }
    }
  } catch {
    Write-Log "Error accessing System partition: $_" 'ERROR'
    return $null
  }
}

function Get-PartitionSpaceInfo {
  param([Parameter(Mandatory)] [string]$DriveLetter)
  $v = Get-Volume -DriveLetter $DriveLetter
  @{
    TotalSize   = [math]::Round($v.Size/1MB,2)
    FreeSpace   = [math]::Round($v.SizeRemaining/1MB,2)
    UsedSpace   = [math]::Round(($v.Size-$v.SizeRemaining)/1MB,2)
    PercentFree = [math]::Round(($v.SizeRemaining/$v.Size)*100,2)
  }
}

try {

    Remove-Variable -ErrorAction SilentlyContinue -Name version
    $version = "2025.11.13.01"

    $ErrorActionPreference = "Continue" # default value
    $VerbosePreference = 'SilentlyContinue' # default value
    $ConfirmPreference = 'None'
    $InformationPreference = "Continue"

    ######################################
    ########### MAIN CODE ################
    ######################################

    $outputJSON = @{}

    $exitCode = 0 # default exit code (unless exception in the main program)

    $outputJSON.lastRun = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    if($version) { $outputJSON.version = "$version" } 

    if($env:computername) { $outputJSON.Name = "$env:computername" } 

    try {
        $serialNumber = (Get-CimInstance win32_bios -ErrorAction Stop).SerialNumber
        if ($serialNumber) { $outputJSON.SerialNumber = "$serialNumber" }
    } catch {
        try { 
            $exception = $_.Exception 

            if ($exception -and $exception.GetType() -and $exception.Message) {
                $outputJSON.SerialNumber="Exception-$($exception.GetType().FullName)-$($exception.Message)"
            } else {
                $outputJSON.SerialNumber="Exception"
            }

        } catch {}
    }

    # ACTUAL CODE

    $mountInfo = Get-SystemPartition
    if (-not $mountInfo) { 
        throw "Cannot mount/access System partition."
    }

    $dl = $mountInfo.DriveLetter
    if (-not $dl) { 
        throw "Drive letter for System partition not found."
    } else {
        $outputJSON.SystemPartitionLetter = "$dl`:"
    }

    $initial = Get-PartitionSpaceInfo -DriveLetter $dl
    if (-not $initial) { 
        throw "Cannot retrieve System partition information."
    } else {

        # all sizes in MB
        $outputJSON.InitialTotal=$($initial.TotalSize)
        $outputJSON.InitialUsed=$($initial.UsedSpace)
        $outputJSON.InitialFree=$($initial.FreeSpace)

        $outputJSON.InitialPercentFree=$($initial.PercentFree)

    }

    # Unmount only if we mounted it
    if (-not $mountInfo.WasAlreadyMounted) {
        #Write-Log "Unmounting System partition..."
        if ($mountInfo.MountedBy -eq 'mountvol') {
            mountvol "$dl`:" /d | Out-Null
            $outputJSON.Unmount = "Unmounted with mountvol"
        } else {
            try {
                Get-Partition -DiskNumber $mountInfo.Partition.DiskNumber -PartitionNumber $mountInfo.Partition.PartitionNumber | Remove-PartitionAccessPath -AccessPath "$dl`:\" -ErrorAction Stop
                 $outputJSON.Unmount = "Drive letter removed"
            } catch {
                $outputJSON.Unmount = "Warning: failed to unmount ($($_.Exception.Message))."
            }
        }
    } else {
        $outputJSON.Unmount = "System partition was already mounted; not unmounting."
    }

    # determine if remediation is needed (if there is less than 15 MB free space)
    if ($outputJSON.InitialFree -lt 15) {
      $exitCode = 1
    }

} catch {

    # main program

    try { 
        $exception = $_.Exception 
        
        if ($exception -and $exception.GetType() -and $exception.Message) {
            $outputJSON.Exception="$($exception.GetType().FullName)-$($exception.Message)"
        } else {
            $outputJSON.Exception="Exception or its properties are null."
        }

    } catch {}

    $exitCode = 1
    #Write-Error "Exception in the main program."

} finally {
    #Do this after the try block regardless of whether an exception occurred or not

    try {
    
        # now we convert it to JSON
        $outputString = $outputJSON | ConvertTo-Json -Compress -ErrorAction SilentlyContinue -Depth 100
        
        # https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations#script-requirements
    
        if($outputString -and $outputString.Length) {
    
            if($outputString.Length -ge 2048) { 
                $outputString = "The output string is too long: $($outputString.Length)"
            }      
    
        } else {
            $outputString = "The output string seems to be 'null'."
        }
    
        Write-Output -InputObject $outputString 
    
    } catch {
    
        try { 
            Write-Output "Exception to display 'outputString'."
        } catch {}
    
        #Write-Error "Exception to display 'outputString'."
    
    }
    
    exit $exitCode

} # finally