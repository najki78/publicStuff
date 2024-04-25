# Recovery Partition size required for KB5028997
$version = "2024.04.23.02"

if($PSDefaultParameterValues) { $PSDefaultParameterValues = @{} } # this should never be needed, $PSDefaultParameterValues should always be initialized as hash table
$PSDefaultParameterValues["*:Confirm"] = $False

$ConfirmPreference = 'None'
$InformationPreference = 'Continue'
$VerbosePreference = 'SilentlyContinue' # if Continue, it will ensure that -Verbose is written in a transcript for all commands
$global:DebugPreference = 'SilentlyContinue' 

$ErrorActionPreference = "Stop" # set default ErrorAction for all commands
$WarningActionPreference = "Continue" # set default action for all commands

$partitionSize = 1500000000 - 10000000 #bytes 1,5GB  ... minus some insignificant value, if the partition is not the exact size

Try {
    $computerDisks = Get-PhysicalDisk
    foreach ($computerDisk in $computerDisks) {
        $diskPartitions = Get-Partition -DiskNumber $computerDisk.DeviceId -ErrorAction Ignore
        if ($diskPartitions.DriveLetter -contains 'C' -and $null -ne $diskPartitions) {
            $systemDrive = $computerDisk
        }
    }

    $recoveryPartition = Get-Partition -DiskNumber $systemDrive.DeviceId | Where-Object { $_.Type -eq 'Recovery' }

    if ($recoveryPartition.Size -le $partitionSize) {
        Write-Output "Recovery Partition size $($($recoveryPartition.Size) / 1000000) MB is smaller than $($partitionSize / 1000000) MB"
        Exit 1
    }
    else {
        Write-Output "Recovery Partition size $($($recoveryPartition.Size) / 1000000) MB is already larger than $($partitionSize / 1000000) MB"
        Exit 0
    }
}
Catch {
    Write-Output 'Recovery Partition not found.'
    Exit 1
}