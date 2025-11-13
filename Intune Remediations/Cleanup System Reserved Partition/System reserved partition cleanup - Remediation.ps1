<#
.SYNOPSIS
  Cleans up System Reserved/EFI partition on Windows 11 (focus: remove non-English boot locales & junk), and moves HP BIOS and DEVFW firmware files to C:\Windows\Temp\HPfiles\.
.DESCRIPTION
  Mounts EFI/System partition, optionally moves HP BIOS/firmware content out to C:\Windows\Temp\HPfiles,
  removes unnecessary language folders and temp/backup files,
  keeps en-US and essential fonts, logs all actions, then unmounts the EFI partition if it was mounted.
.NOTES
  Requires: Administrator privileges
#>

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level='INFO')

    # Uncomment in case you want to log to a file

    #$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    #$line = "[$timestamp] [$Level] $Message"
    # Add-Content -Path $LogPath -Value $line
    #$color = switch ($Level) { 'ERROR'{'Red'} 'WARN'{'Yellow'} 'SUCCESS'{'Green'} default{'White'} }
    #Write-Host $line -ForegroundColor $color
    #Write-Host $Message
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

# Move HP BIOS & Firmware content
function Move-HPFirmwareContent {
  param([string]$EfiDriveLetter, [switch]$WhatIf)

  $hpRootEfi = "$EfiDriveLetter`:\EFI\HP"
  $hpRootDst = "C:\Windows\Temp\HPfiles"

  if (-not (Test-Path $hpRootEfi)) {
    Write-Log "HP folder not found in EFI ($hpRootEfi), skipping move." 'WARN'
    return 0
  }

  New-Item -ItemType Directory -Path $hpRootDst -Force | Out-Null

  $movedBytes = 0
  $targets = @('DEVFW','BIOS\New','BIOS\Previous','FWUPDLOG', 'BIOSUpdate')

    # SystemDiags – Contains HP’s UEFI hardware diagnostics tools ... 
        # Removing it frees up tens of MB. It does not affect Windows boot, but you’ll lose built-in pre-boot diagnostics (you can run diagnostics from a USB or HP support media if needed).

    # BIOS – Stores BIOS firmware images for the system’s UEFI firmware. Under this, there are typically subfolders: Current, Previous, and sometimes New.
        # You can delete Previous to free space (removing the older backup firmware) – this is usually safe if you don’t need to rollback.
        # Deleting Current is not recommended unless absolutely necessary – the PC will still boot with the BIOS it has, but you’d lose the on-disk copy of the current firmware used for certain recovery scenarios [garytown.com]. (HP’s hardware Sure Start typically keeps a separate BIOS copy in flash memory, so the EFI copy is mainly a convenience backup.)
        # New – Sometimes present during BIOS updates, contains the new firmware before it’s applied. Safe to delete after the update is complete.  

    # BIOSUpdate – Contains HP’s UEFI BIOS update utility and related scripts
        # Generally safe to delete. If a BIOS update is initiated later, HP’s software will recreate this folder as needed. Deleting it does not harm normal operation; it only removes the UEFI-flash tool until it’s restored by an update package.

    # DEVFW – Stands for “Device Firmware”.
        # Safe to delete after the update is completed. These are essentially temporary payload files. HP’s own update tools often do remove older files here. If they remain, you can delete them to reclaim space

  foreach ($sub in $targets) {
    $src = Join-Path $hpRootEfi $sub
    $dst = Join-Path $hpRootDst $sub

    if (-not (Test-Path $src)) {
      Write-Log "Source $src not found, skipping..." 'WARN'
      continue
    }

    if (-not (Test-Path $dst)) {
      if ($WhatIf) { Write-Log "WHATIF: Would create $dst" 'WARN' }
      else {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Write-Log "Created destination folder: $dst"
      }
    }

    $before = (Get-ChildItem -File -Recurse $src -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $before = if ($null -eq $before) { $before } else { 0 }

    if ($WhatIf) {
      Write-Log "WHATIF: Would move content from $src → $dst (~$([math]::Round($before/1MB,2)) MB)" 'WARN'
    } else {
      Move-Item -Path "$src\*" -Destination $dst -Force -ErrorAction SilentlyContinue
      Write-Log "Moved content from $src → $dst ($([math]::Round($before/1MB,2)) MB)" 'SUCCESS'
      $movedBytes += $before
    }
  }

  return $movedBytes
}

function Remove-NonEnglishFonts {
  param([string]$DriveLetter, [switch]$WhatIf)
  Write-Log "Processing Fonts..."
  $path = "$DriveLetter`:\EFI\Microsoft\Boot\Fonts"
  if (-not (Test-Path $path)) { Write-Log "Fonts folder not found, skipping" 'WARN'; return 0 }
  $keep = @('wgl4_boot.ttf','segmono_boot.ttf','segoe_slboot.ttf','segui_boot.ttf','seguisb_boot.ttf','seguisl_boot.ttf')
  $freed = 0
  Get-ChildItem $path -File -Filter *.ttf | ForEach-Object {
    if ($keep -notcontains $_.Name) {
      $sz=$_.Length
      if ($WhatIf) { Write-Log "WHATIF: Delete font $($_.Name) ($([math]::Round($sz/1MB,2)) MB)" 'WARN' }
      else {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Log "Deleted font $($_.Name) ($([math]::Round($sz/1MB,2)) MB)"
        $freed += $sz
      }
    }
  }
  return $freed
}

function Remove-NonEnglishLocales {
  param([string]$DriveLetter,[switch]$WhatIf)

  Write-Log "Processing locale folders/files..."
  $boot = "$DriveLetter`:\EFI\Microsoft\Boot"
  if (-not (Test-Path $boot)) { Write-Log "Boot folder not found, skipping" 'WARN'; return 0 }

  $freed = 0
  $langRoots = @(
    $boot
    (Join-Path $boot 'Resources')
    (Join-Path $boot 'Fonts')
  )

  foreach ($root in $langRoots) {
    if (Test-Path $root) {
      Get-ChildItem $root -Directory |
        Where-Object { $_.Name -match '^[a-z]{2}-[A-Z]{2}$' -and $_.Name -ne 'en-US' } |
        ForEach-Object {
          $size = (Get-ChildItem $_.FullName -Recurse -Force | Measure-Object Length -Sum).Sum
          if ($WhatIf) { Write-Log "WHATIF: Delete $($_.FullName) ($([math]::Round($size/1MB,2)) MB)" 'WARN' }
          else {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Deleted $($_.FullName) ($([math]::Round($size/1MB,2)) MB)"
            $freed += $size
          }
        }
    }
  }

  # delete stray *.nls not tied to en-US
  Get-ChildItem $boot -Recurse -File -Filter *.nls -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch 'en-US' } |
    ForEach-Object {
      $sz=$_.Length
      if ($WhatIf) { Write-Log "WHATIF: Delete NLS $($_.FullName) ($([math]::Round($sz/1MB,2)) MB)" 'WARN' }
      else {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Log "Deleted NLS $($_.FullName) ($([math]::Round($sz/1MB,2)) MB)"
        $freed += $sz
      }
    }

  return $freed
}

function Remove-OldBootBackups {
  param([string]$DriveLetter,[switch]$WhatIf)
  Write-Log "Cleaning old backups (.bak/.old) under EFI\Microsoft..."
  $root = "$DriveLetter`:\EFI\Microsoft"
  if (-not (Test-Path $root)) { Write-Log "EFI\Microsoft not found, skipping" 'WARN'; return 0 }
  $freed=0
  foreach ($pat in @('*.bak','*.old','*.backup')) {
    Get-ChildItem $root -Recurse -File -Filter $pat -ErrorAction SilentlyContinue | ForEach-Object {
      $sz=$_.Length
      if ($WhatIf) { Write-Log "WHATIF: Delete $($_.FullName) ($([math]::Round($sz/1MB,2)) MB)" 'WARN' }
      else {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Log "Deleted $($_.FullName) ($([math]::Round($sz/1MB,2)) MB)"
        $freed += $sz
      }
    }
  }
  return $freed
}

function Remove-TemporaryUpdateFiles {
  param([string]$DriveLetter,[switch]$WhatIf)
  Write-Log "Checking for temporary update folders on EFI (rare)..."
  $freed=0
  foreach ($p in @("$DriveLetter`:\`$WINDOWS.~BT", "$DriveLetter`:\`$Windows.~WS")) {
    if (Test-Path $p) {
      $sz=(Get-ChildItem $p -Recurse -Force | Measure-Object Length -Sum).Sum
      if ($WhatIf) { Write-Log "WHATIF: Delete $p ($([math]::Round($sz/1MB,2)) MB)" 'WARN' }
      else {
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Deleted $p ($([math]::Round($sz/1MB,2)) MB)"
        $freed += $sz
      }
    }
  }
  return $freed
}

try {

    Remove-Variable -ErrorAction SilentlyContinue -Name version
    $version = "2025.11.13.01"

    $ErrorActionPreference = "Continue" # default value
    $VerbosePreference = 'SilentlyContinue' # default value
    $ConfirmPreference = 'None' # No confirmation prompts are displayed, and actions are performed without asking for user confirmation. # Default is 'High'
    $InformationPreference = "Continue"

    ######################################
    ########### MAIN CODE ################
    ######################################

    $outputJSON = @{
    }

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
        throw "[Initial] Cannot retrieve System partition information."
    } else {

        # all sizes in MB
        $outputJSON.InitialTotal=$($initial.TotalSize)
        $outputJSON.InitialUsed=$($initial.UsedSpace)
        $outputJSON.InitialFree=$($initial.FreeSpace)

        $outputJSON.InitialPercentFree=$($initial.PercentFree)

    }

    # $WhatIf = $true # simulation
    $WhatIf = $false # real action

    # Move HP firmware/BIOS content out of EFI to C:\EFI\HP\
    $totalMoved = Move-HPFirmwareContent -EfiDriveLetter $dl -WhatIf:$WhatIf
    if ($totalMoved -gt 0) { Write-Log "HP content moved (~$([math]::Round($totalMoved/1MB,2)) MB)." 'SUCCESS' }

    $totalFreed = 0
    $totalFreed += Remove-NonEnglishFonts    -DriveLetter $dl -WhatIf:$WhatIf
    $totalFreed += Remove-NonEnglishLocales  -DriveLetter $dl -WhatIf:$WhatIf
    $totalFreed += Remove-OldBootBackups     -DriveLetter $dl -WhatIf:$WhatIf
    $totalFreed += Remove-TemporaryUpdateFiles -DriveLetter $dl -WhatIf:$WhatIf

    $final = Get-PartitionSpaceInfo -DriveLetter $dl

    Write-Log "========================================" 'SUCCESS'
    Write-Log "Cleanup Complete" 'SUCCESS'
    Write-Log "========================================" 'SUCCESS'
    Write-Log "Final:   Total=$($final.TotalSize)MB, Used=$($final.UsedSpace)MB, Free=$($final.FreeSpace)MB ($($final.PercentFree)%)"
    Write-Log "Freed:   $([math]::Round($totalFreed/1MB,2)) MB" 'SUCCESS'
    Write-Log "Delta:   $([math]::Round($final.FreeSpace - $initial.FreeSpace,2)) MB"

    if (-not $final) { 
        throw "[Final] Cannot retrieve System partition information."
    } else {

        # all sizes in MB
        $outputJSON.FinalUsed=$($final.UsedSpace)
        $outputJSON.FinalFree=$($final.FreeSpace)

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
            # Write-Output "The output string size: $($outputString.Length)"
    
            if($outputString.Length -ge 2048) { # 2048
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