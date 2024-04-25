
# Kudos to  Nick Benton!

    # Script to fix the recovery partition for KB5028997 by /u/InternetStranger4You, updated by Nick Benton
    # Mostly Powershell version of Microsoft's support article: https://support.microsoft.com/en-us/topic/kb5028997-instructions-to-manually-resize-your-partition-to-install-the-winre-update-400faa27-9343-461c-ada9-24c8229763bf
    # Test in your own environment before running. Not responsible for any damages.

    # Resize the WinRE Partition for Windows Update KB5034441 (after update failing with the 0x80070643 error)
    # https://memv.ennbee.uk/posts/winre-parition-resize-kb5034441/

# Other WinRE related articles:

    # https://answers.microsoft.com/en-us/windows/forum/all/reagentc-does-not-let-me-enable-windows-re/dfa13429-0cd1-4bf9-83ae-92f1c8006132
    # https://answers.microsoft.com/en-us/windows/forum/all/the-window-re-image-was-not-found/93fd0930-6a27-43ea-8415-1ca0ddb645b5
    # https://woshub.com/restoring-windows-recovery-environment-winre-in-windows-10/
    # https://learn.microsoft.com/en-us/archive/blogs/askcore/customizing-the-recovery-partition-after-upgrading-the-os-from-windows-8-1-to-windows-10
    # https://www.tenforums.com/general-support/172567-how-recreate-windows-recovery-partition.html
    # https://windowsloop.com/create-recovery-partition-windows-10/
    # https://superuser.com/questions/1667319/how-to-restore-the-recovery-partition-in-windows-10
    # https://www.elevenforum.com/t/deleted-windows-recovery-partition-how-to-make-a-new-one.11534/
    # https://superuser.com/questions/1108243/setting-winre-windows-recovery-environment-flag-on-partitions/1109582#1109582

$version = "2024.04.23.01"

if($PSDefaultParameterValues) { $PSDefaultParameterValues = @{} } # this should never be needed, $PSDefaultParameterValues should always be initialized as hash table
$PSDefaultParameterValues["*:Confirm"] = $False

$ConfirmPreference = 'None'
$InformationPreference = 'Continue'
$VerbosePreference = 'Continue' # if Continue, it will ensure that -Verbose is written in a transcript for all commands # SilentlyContinue
$global:DebugPreference = 'SilentlyContinue' 

$ErrorActionPreference = "Stop" # set default ErrorAction for all commands
$WarningActionPreference = "Continue" # set default action for all commands

# Recovery Partition size required for KB5028997 - '750000000'
$partitionSize = '1500000000' #bytes

$exitCode = 0

# 2024.01.08.01
# without timezone information (time in UTC), suitable for file names etc (colon character removed)
function timestampUTC2 {

    try {

        return "$((get-date -ErrorAction Stop).ToUniversalTime().ToString("yyyy-MM-ddTHHmmssZ"))" 
        # the actual time (on the clock) + current timezone shift

    } catch {

        return "yyyy-MM-ddTHHmmssZ"

    }

}

$path = "C:\ProgramData\PLACEHOLDER1\Intune"

try {
    Stop-Transcript -ErrorAction SilentlyContinue     # Stop-Transcript, in case some lingering transcript is running
} catch {}

try {
    # Create folder if not exists
    if (-not (Test-Path "$Path")) {
        $null = New-Item -Path "$Path" -ItemType Directory -ErrorAction Stop
    }

} catch {

    try {
        $exception = $_.Exception
    } catch {}

    Write-Output "# $(timestamp): Exception while creating folder $path - $($exception.GetType().FullName) - $($exception.Message). Exiting."

}

$logFile = $path + "\" + (timestampUTC2) + "-WinREResize.txt" # log file

# the file should not exist (it includes a timestamp), but if it does, delete it (the only possibility is if 'timestampUTC2' function fails to provide a current timestamp, this should never happen)
$null = Remove-Item $logFile -Force -ErrorAction SilentlyContinue | out-null	

Start-Transcript -Path $logFile -Append -ErrorAction Continue

Write-Output "Version: $version"
Write-Output "Log file: $logFile"

Import-Module Storage -Global -PassThru -ErrorAction Continue

# check if winre.wim etc is available and later /enable command will not fail
$pathRecovery = "$env:SystemRoot\system32\Recovery"

try {
    # Create folder if not exists
    if (-not (Test-Path "$pathRecovery")) {
        $null = New-Item -Path "$pathRecovery" -ItemType Directory -ErrorAction Stop
    }

} catch {

    try { $exception = $_.Exception } catch {}
    Write-Output "Exception while creating folder $pathRecovery - $($exception.GetType().FullName) - $($exception.Message). Exiting."

}

if(Test-Path -Path "$pathRecovery\winre.wim") {
    
    Write-Output "OK. winre.wim found in $($pathRecovery)"

} else {

    Write-Output "winre.wim not found in $($pathRecovery)"

    # in case, the winre.wim is stored together with the script, there is no need to download from Azure storage
    if(Test-Path -Path "$($PSScriptRoot)\winre.wim") {

        # copy winre.wim from the folder where the script is located
        Write-Output "Copying winre.wim from script folder $PSScriptRoot to $pathRecovery"
        Copy-Item "$($PSScriptRoot)\winre.wim" -Destination "$pathRecovery\winre.wim" -PassThru

    } else {

        # where to place azcopy.exe
        $pathAzCopy = "$path\azcopy"

        if(-not (Test-Path -Path "$pathAzCopy\azcopy.exe")) {

            Write-Output "Copying azcopy.exe from Microsoft."
            
            try {
                # Create folder if not exists
                if (-not (Test-Path "$pathAzCopy")) {
                    $null = New-Item -Path "$pathAzCopy" -ItemType Directory -ErrorAction Stop
                }
            } catch {
        
                try { $exception = $_.Exception } catch {}
                Write-Output "# Exception while creating folder $pathAzCopy - $($exception.GetType().FullName) - $($exception.Message). Exiting."
            }
        
            Set-Location $path 
        
            Invoke-WebRequest -Uri "https://aka.ms/downloadazcopy-v10-windows" -OutFile "$path\AzCopy.zip"
            
            # Load the assembly required for zip file manipulation
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            
            # Open the zip archive
            $zipArchive = [System.IO.Compression.ZipFile]::OpenRead("$path\azcopy.zip")
            
            # Iterate through each entry in the zip file
            foreach ($entry in $zipArchive.Entries) {
                # Define the destination path for the current entry
                # This example extracts all files directly into the destination directory without preserving the folder structure
                #$destinationPath = Join-Path -Path $destinationDirectory -ChildPath $entry.Name
                #$entry
            
                # Check if the entry is a directory (we skip directories)
                if (-not $entry.FullName.EndsWith("/")) {
                    # Extract the file to the destination path
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, "$pathAzCopy\$($entry.Name)", $true)
                }
            }
            # Close the zip archive
            $zipArchive.Dispose()
            Remove-Item "AzCopy.zip" -Force
        
        }

        Write-Output "Copying winre.wim from Azure storage to $pathAzCopy"
        set-location $pathAzCopy 
        .\azcopy.exe copy "https://PLACEHOLDER2.blob.core.windows.net/PLACEHOLDER3/winre.wim" "$pathRecovery\winre.wim" # file name is case sensitive

    }

}

# resize

Try {
    Write-Output "Run reagentc.exe /info"
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = 'reagentc.exe'
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = '/info'
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stdout
    $stderr = $p.StandardError.ReadToEnd()
    $stderr

    #Disable Windows recovery environment
    Start-Process 'reagentc.exe' -ArgumentList '/disable' -Wait -NoNewWindow -PassThru

    #Verify that disk and partition are listed in reagentc.exe /info. If blank, then something is wrong with WinRE
    if (($stdout.IndexOf('harddisk') -ne -1) -and ($stdout.IndexOf('partition') -ne -1)) {

        #Get recovery disk number and partition number
        $diskNum = $stdout.substring($stdout.IndexOf('harddisk') + 8, 1)
        $recPartNum = $stdout.substring($stdout.IndexOf('partition') + 9, 1)

        Write-Output "Recovery partition found. Disk: $diskNum Recovery partition: $recPartNum"
    }
    else {
        Write-Output "Recovery partition not found in 'reagentc /info' output."

    }

    Write-Output "Identifying system disk:"
    $sysDisk = Get-Disk | Where-Object { ($_.IsBoot -eq $true) -and ($_.IsSystem -eq $true) }
    $diskNum = $sysDisk.Number

        $sysDisk | fl

    # check all partitions marked as Recovery (there shoould be maximum of 1) and delete 
    Write-Output "Deleting recovery partition, if any, on disk $diskNum."
    $recoveryPartition = Get-Partition -DiskNumber $diskNum | Where-Object {  $_.Type -eq "Recovery" }
    if($recoveryPartition) {
        $recoveryPartition | ForEach-Object { Remove-Partition -DiskNumber $diskNum -PartitionNumber $_.PartitionNumber -PassThru }   # -Confirm:$false
    }
    
    $allPartitions = Get-Partition -DiskNumber $diskNum

    # ensure Type <> Recovery for any of the partitions
    if( ($allPartitions | Where-Object {  $_.Type -eq "Recovery" } | Measure-Object).Count -ne 0 ) { Write-Output "Recovery partition still exists. Delete it before proceeding. Aborting script."; Exit 1  }

    Write-Output "allPartitions"
    $allPartitions | fl

    # retrieve the highest PartitionNumber
    $lastPartitionNum = ($allPartitions | Sort-Object -Property PartitionNumber -Descending | Select-Object -First 1).PartitionNumber
    Write-Output "lastPartitionNum: $lastPartitionNum"

    # Get the size of the disk
    $diskSize = (Get-Disk $diskNum).Size
    Write-Output "diskSize: $diskSize"

    # Calculate the total size of the partitions
    $totalPartitionSize = ($allPartitions | Measure-Object -Property Size -Sum).Sum
    Write-Output "totalPartitionSize: $totalPartitionSize"

    # Calculate the free space
    $freeSpace = $diskSize - $totalPartitionSize
    Write-Output "freeSpace: $freeSpace"

    # Check if there is a need to resize partition
    if ($freeSpace -gt $partitionSize) {

        Write-Output "OK. Resizing is not needed. There is enough free space after the last partition on the disk."

    } else {

        Write-Output "There is not enough free space after the last partition on the disk. Need to resize."

        #Resize partition at the end of the disk
        $lastPartitionSize = Get-Partition -DiskNumber $diskNum -PartitionNumber $lastPartitionNum | Select-Object -ExpandProperty Size
        Write-Output "Size of the last partition $lastPartitionNum [before Recovery partition]: $lastPartitionSize"

        $lastPartitionTargetSize = $lastPartitionSize + $freeSpace - $partitionSize
        Write-Output "Target size of the partition $lastPartitionNum (to be resized): $lastPartitionTargetSize"

        $lastPartitionSupportedSize = Get-PartitionSupportedSize -DiskNumber $diskNum -PartitionNumber $lastPartitionNum
        Write-Output "Supported sizes of the partition $($lastPartitionNum):"      
        $lastPartitionSupportedSize | fl

        # do not try to resize to more than max possible size for that partition
        if($lastPartitionSupportedSize.SizeMin -and $lastPartitionSupportedSize.SizeMax -and ($lastPartitionTargetSize -ge $lastPartitionSupportedSize.SizeMin) -and ($lastPartitionTargetSize -le $lastPartitionSupportedSize.SizeMax)) {
            Write-Output "No change in the size of the target partition $($lastPartitionNum): $lastPartitionTargetSize"
        } else {
            Write-Output "Adjusting the target size of the partition $lastPartitionNum. `nOriginal value: $lastPartitionTargetSize `nAdjusted size : $($lastPartitionSupportedSize.SizeMax)"
            $lastPartitionTargetSize = $lastPartitionSupportedSize.SizeMax
        }

        # it seems we need to explicitly convert...
        $lastPartitionTargetSize = [UInt64]$lastPartitionTargetSize
        
        Write-Output "The difference between lastPartitionSize and lastPartitionTargetSize in MB: $(($lastPartitionSize - $lastPartitionTargetSize) / 1MB)"
        
        # this seems to fail if the difference between lastPartitionSize and lastPartitionTargetSize is less than 1MB - TO BE CONFIRMED
        if(  (($lastPartitionSize - $lastPartitionTargetSize) / 1MB) -gt 1 ) {
            Write-Output "Resizing to the target size: $lastPartitionTargetSize"
            Get-Partition -DiskNumber $diskNum -PartitionNumber $lastPartitionNum | Resize-Partition -Size $lastPartitionTargetSize -PassThru -ErrorAction Continue # -Confirm:$false
        } else {
            Write-Output "The difference between lastPartitionSize and lastPartitionTargetSize is less than 1 MB. Skipping resize to prevent an error message."
        }

    }

    Write-Output "Create new partition with diskpart script."
    
    $diskpartScriptPath = $env:TEMP
    $diskpartScriptName = 'ResizeREScript.txt'
    $diskpartScript = $diskpartScriptPath + '\' + $diskpartScriptName
    
    Write-Output "diskpartScript: $diskpartScript"
    "sel disk $($diskNum)" | Out-File -FilePath $diskpartScript -Encoding utf8 -Force
    $PartStyle = Get-Disk $diskNum | Select-Object -ExpandProperty PartitionStyle
    if ($partStyle -eq 'GPT') {
        #GPT partition commands
        'create partition primary id=de94bba4-06d1-4d40-a16a-bfd50179d6ac' | Out-File -FilePath $diskpartScript -Encoding utf8 -Append -Force
        'gpt attributes=0x8000000000000001' | Out-File -FilePath $diskpartScript -Encoding utf8 -Append -Force
    }
    else {
        #MBR partition command
        'create partition primary id=27' | Out-File -FilePath $diskpartScript -Encoding utf8 -Append -Force
    }
    "format quick fs=ntfs label=`"Windows RE tools`"" | Out-File -FilePath $diskpartScript -Encoding utf8 -Append -Force

        Write-Output "Starting DISKPART."
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = 'diskpart.exe'
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false # if we want to redirect the output and error streams of the process, UseShellExecute must be set to false. If it were true, the redirection of the streams would not work
        $pinfo.Arguments = "/s $($diskpartScript)"
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()
        $stdout = $p.StandardOutput.ReadToEnd()
        $stdout
        $stderr = $p.StandardError.ReadToEnd()
        $stderr

    #Enable the recovery environment

        # to ensure winre.wim is located
        Write-Output "Starting /setreimage /path $pathRecovery"
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = 'reagentc.exe'
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false # if we want to redirect the output and error streams of the process, UseShellExecute must be set to false. If it were true, the redirection of the streams would not work
        $pinfo.Arguments = "/setreimage /path $pathRecovery"
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()
        $stdout = $p.StandardOutput.ReadToEnd()
        $stdout
        $stderr = $p.StandardError.ReadToEnd()
        $stderr

        Write-Output "Starting reagentc.exe /enable."
        #Run reagentc.exe /enable and save the output
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = 'reagentc.exe'
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false # if we want to redirect the output and error streams of the process, UseShellExecute must be set to false. If it were true, the redirection of the streams would not work
        $pinfo.Arguments = '/enable'
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()
        $stdout = $p.StandardOutput.ReadToEnd()
        $stdout
        $stderr = $p.StandardError.ReadToEnd()
        $stderr

        if($stderr) {
            "Recovery Partition configuration failed: $stderr"
        } else {
            Write-Output 'Recovery Partition Configured Successfully.'
        }

        Write-Output "Run reagentc.exe /info"
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = 'reagentc.exe'
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = '/info'
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()
        $stdout = $p.StandardOutput.ReadToEnd()
        $stdout
        $stderr = $p.StandardError.ReadToEnd()
        $stderr

        #Verify that disk and partition are listed in reagentc.exe /info. If blank, then something is wrong with WinRE
        if (($stdout.IndexOf('harddisk') -ne -1) -and ($stdout.IndexOf('partition') -ne -1)) {
            Write-Output "Done: Windows RE configured successfully. Restart PC and re-run Windows Updates to verify KB5034441 installs successfully.`nExiting."
            $exitCode = 0
        } else {
            Write-Output "ERROR: Windows RE configuration failed. Re-run the script and if the issue persists, send the script output to Lubos.`nExiting."
            $exitCode++
        }

}
Catch {

    try { $exception = $_.Exception } catch {}
    Write-Output "# Exception. Unable to update Recovery Partition on the device - $($exception.GetType().FullName) - $($exception.Message).`nRe-run the script and if the issue persists, send the script output to Lubos.`nExiting."
    $exitCode++

}

try {
    $null = Stop-Transcript -ErrorAction SilentlyContinue # -Verbose
} catch {}

exit $exitCode