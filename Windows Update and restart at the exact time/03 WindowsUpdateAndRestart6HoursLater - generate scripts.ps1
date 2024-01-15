# Generate scripts for different timeslots and upload them to Intune

$version = "2024.01.15.01"

# location of these scripts
$path = "C:\Temp\Windows Update and restart at the exact time\" 

cls

# Intune support - https://smsagent.blog/2020/03/19/managing-intune-powershell-scripts-with-microsoft-graph/

# Define a function with two string parameters
Function Update-deviceManagementScript {
    Param (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$scriptID, # script ID in Intune
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$scriptPath,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$scriptName
    )

    # Write the function logic here

    $Params = @{
        ScriptName = $ScriptName
        ScriptContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path "$ScriptPath\$ScriptName" -Raw -Encoding UTF8)))
        DisplayName = "(DisplayNamePlaceholder)"
        Description = "(DescriptionPlaceholder)"
        RunAsAccount = "system"
        EnforceSignatureCheck = "false"
        RunAs32Bit = "false"
    }

$Json = @"
{
    "@odata.type": "#microsoft.graph.deviceManagementScript",
    "scriptContent": "$($Params.ScriptContent)",
    "runAsAccount": "$($Params.RunAsAccount)",
    "enforceSignatureCheck": $($Params.EnforceSignatureCheck),
    "fileName": "$($Params.ScriptName)",
    "runAs32Bit": $($Params.RunAs32Bit)
}
"@

    $URI = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$($scriptID)"
    $Response = Invoke-MSGraphRequest -HttpMethod PATCH -Url $URI -Content $Json

}

function Load-Module {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory = $true)][string] $m,
        [parameter(Mandatory = $false)][string] $version
    )

    $returnValue = $false # module not loaded

    Write-Verbose "[Powershell module] Loading module $($m)"
    
    try {

        if ($version) {
            
            $module = Get-InstalledModule -Name $m -RequiredVersion $version -ErrorAction SilentlyContinue
            
            if(-not $module) {
                Write-Verbose "[Powershell module] Installing module $($m) - required version: $version"
                Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Installing module $($m) - required version: $($version): $( Install-Module -Name $m -AllowClobber -Force -confirm:$false -RequiredVersion $version )"
            }

            Get-Module -ListAvailable -Name $m -ErrorAction Continue | Where-Object { $_.Version -ne $version } -ErrorAction Continue | ForEach-Object { Uninstall-Module -Name $_.Name -RequiredVersion $_.Version -Force -ErrorAction Continue }

            # import
            Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Importing module $($m) - importing version $($version): $( Import-Module $m -Scope Global -ErrorAction Stop -RequiredVersion $version -PassThru )"

        } else { # if $version not present
        
            $module = Get-InstalledModule -Name $m -ErrorAction SilentlyContinue # -Verbose 
            if (-not $module) {
                Write-Verbose "[Powershell module] Installing module $($m)"
                # https://learn.microsoft.com/en-us/powershell/module/powershellget/install-module?view=powershellget-2.x
                Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Installing module $($m): $( Install-Module $m -AllowClobber -Force -confirm:$false )"

            } else {
                Write-Verbose "[Powershell module] Updating module $($m)"
                Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Updating module $($m): $( Update-Module -Name $m -confirm:$false -ErrorAction Continue )"
                # -Force 
            }

            # import
            Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Importing module $($m): $( Import-Module $m -Scope Global -ErrorAction Stop -PassThru )"

        }

        # displaying the current version
        $module = Get-Module -Name $m -ListAvailable -ErrorAction Stop
        if ($module.Version) {
            Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Module $($m) - current version: $($module.Version.ToString())"
        }

        $returnValue = $true

    } catch {}

    return $returnValue

}

# without timezone information, suitable for file names etc (colon character removed)
function timestamp2 {
    (get-date -ErrorAction SilentlyContinue).ToString("yyyy-MM-ddTHHmmss")  # the actual time (on the clock) + current timezone shift
}

# Stop-Transcript, in case some lingering transcript is running
try {
    Stop-Transcript -ErrorAction SilentlyContinue 
} catch {}

$logFile = $path + (timestamp2) + "-Log-GenerateScriptsUploadToIntune.txt" # log file
Start-Transcript -Path $logFile -Append -ErrorAction SilentlyContinue

Write-Output "[Installing package provider] NuGet"
Find-PackageProvider -Name 'Nuget' -ForceBootstrap -IncludeDependencies

Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

Load-Module Microsoft.Graph.Intune # -Verbose

#The connection to Azure Graph
Connect-MSGraph 

#Get Graph scripts
$ScriptsData = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts" -HttpMethod GET
$ScriptsInfos = $ScriptsData.value 

$ScriptsInfoHash = @{} # hashtable with Intune scripts

foreach($record in $ScriptsInfos) {

    $ScriptsInfoHash["$($record.displayName)"] = @($record.id, $record.fileName, $record.lastModifiedDateTime)

}

$hashTable = @{}

    <#

    When adding a new timeslot, create a new $hashTable["DayX...."] record with the following structure:

    Line 1: [string] The name of the Script in Intune [to be replaced by a new version]
    Line 2: [string] Used by previous version with Register-ScheduledTask (now obsolete when using 'SCHTASKS'), leave empty string
    Line 3: [string] Used by previous version with Register-ScheduledTask (now obsolete when using 'SCHTASKS'), leave empty string
    Line 4: [string] Schedule of "WindowsUpdateNoRestart" task using SCHTASKS (configured to run e.g. 6 hours before the restart to give the updates enough time to download and install)
    Line 5: [string] Schedule of "RestartAfterWindowsUpdate" task using SCHTASKS
    Line 6: [int] Restart delay in seconds (my default is 90 seconds; to leave enough time for the user to close the applications)
    
            # Examples for line 4 and 5: 
            "/sc monthly /m * /mo FOURTH /d SUN /st 18:00"
            "/sc WEEKLY /d FRI /st 17:32"
    
    #>

# Auto-restart on the 2nd Sunday each month at 14:00 (2PM) - restart delay of 20 minutes (actual restart therefore at 14:20)
$hashTable["Day7-2nd-Sun2PM-Delay20min"] = @( `
'Update Ring SF AutoRestart – Day7 2nd Sun2PM Delay20min', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo SECOND /d sun /st 08:11"', `
'"/sc monthly /m * /mo second /d sun /st 14:00"', `
'1200'
)

$hashTable["Day1-EVRMon6AM"] = @( `
'Update Ring SF AutoRestart - Day1 EVR Mon6AM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Mon /st 00:01"', `
'"/sc weekly /d Mon /st 06:00"', `
'90'
)

$hashTable["Day1-EVRMon2_30PM"] = @( `
'Update Ring SF AutoRestart - Day1 EVR Mon2_30PM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Mon /st 08:31"', `
'"/sc weekly /d Mon /st 14:30"', `
'90'
)

$hashTable["Day2-EVRTue6AM"] = @( `
'Update Ring SF AutoRestart - Day2 EVR Tue6AM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Tue /st 00:02"', `
'"/sc weekly /d Tue /st 06:00"', `
'90'
)

$hashTable["Day2-EVRTue7AM"] = @( `
'Update Ring SF AutoRestart - Day2 EVR Tue7AM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Tue /st 01:04"', `
'"/sc weekly /d Tue /st 07:00"', `
'90'
)

$hashTable["Day2-EVRTue2_30PM"] = @( `
'Update Ring SF AutoRestart - Day2 EVR Tue2_30PM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Tue /st 08:33"', `
'"/sc weekly /d Tue /st 14:30"', `
'90'
)

$hashTable["Day2-EVRTue6PM"] = @( `
'Update Ring SF AutoRestart – Day2 EVR Tue6PM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Tue /st 12:01"', `
'"/sc weekly /d Tue /st 18:00"', `
'90'
)

$hashTable["Day3-EVRWed6AM"] = @( `
'Update Ring SF AutoRestart - Day3 EVR Wed6AM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Wed /st 00:05"', `
'"/sc weekly /d Wed /st 06:00"', `
'90'
)

$hashTable["Day3-EVRWed2_15PM"] = @( `
'Update Ring SF AutoRestart - Day3 EVR Wed2_15PM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Wed /st 08:17"', `
'"/sc weekly /d Wed /st 14:15"', `
'90'
)

$hashTable["Day3-EVRWed2_30PM"] = @( `
'Update Ring SF AutoRestart - Day3 EVR Wed2_30PM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Wed /st 08:31"', `
'"/sc weekly /d Wed /st 14:30"', `
'90'
)

$hashTable["Day4-EVRThu6AM"] = @( `
'Update Ring SF AutoRestart - Day4 EVR Thu6AM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Thu /st 00:03"', `
'"/sc weekly /d Thu /st 06:00"', `
'90'
)

$hashTable["Day4-EVRThu2_30PM"] = @( `
'Update Ring SF AutoRestart - Day4 EVR Thu2_30PM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Thu /st 08:32"', `
'"/sc weekly /d Thu /st 14:30"', `
'90'
)

$hashTable["Day5-EVRFri6_50AM"] = @( `
'Update Ring SF AutoRestart - Day5 EVR Fri6_50AM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Fri /st 00:51"', `
'"/sc weekly /d Fri /st 06:50"', `
'90'
)

$hashTable["Day7-EVRSun6AM"] = @( `
'Update Ring SF AutoRestart - Day7 EVR Sun6AM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Sun /st 00:04"', `
'"/sc weekly /d Sun /st 06:00"', `
'90'
)

$hashTable["Day7-EVRSun2_30PM"] = @( `
'Update Ring SF AutoRestart - Day7 EVR Sun2_30PM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d Sun /st 08:36"', `
'"/sc weekly /d Sun /st 14:30"', `
'90'
)

$hashTable["Day7-4thSun21_00"] = @( `
'Update Ring SF AutoRestart - Day7 4th Sun21_00', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc monthly /m * /mo FOURTH /d SUN /st 15:00"', `
'"/sc monthly /m * /mo FOURTH /d SUN /st 21:00"', `
'1200'
)

$hashTable["Day7-3rdSun6AM"] = @( `
'Update Ring SF AutoRestart - Day7 3rd Sun06_00', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc monthly /m * /mo THIRD /d SUN /st 00:10"', `
'"/sc monthly /m * /mo THIRD /d SUN /st 06:00"', `
'1200'
)

$hashTable["Day3-EVRWedNoon"] = @( `
'Update Ring SF AutoRestart - Day3 Wed12_00', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc weekly /d WED /st 06:00"', `
'"/sc weekly /d WED /st 12:00"', `
'90'
)

$hashTable["Day3-2ndWed7_45AM"] = @( `
'Update Ring SF AutoRestart - Day3 2nd Wed 7_45AM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc monthly /m * /mo SECOND /d WED /st 01:05"', `
'"/sc monthly /m * /mo SECOND /d WED /st 07:45"', `
'90'
)

$hashTable["Day7-3rdSun3AM"] = @( `
'Update Ring SF AutoRestart – Day7 3rd Sun 3AM', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc monthly /m * /mo THIRD /d SUN /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d SUN /st 03:00"', `
'1200'
)

$hashTable["Day3-3rdWedNoon"] = @( `
'Update Ring SF AutoRestart – Day3 3rd Wed Noon', `
'"(not needed)"', `
'"(not needed)"', `
'"/sc monthly /m * /mo THIRD /d WED /st 06:05"', `
'"/sc monthly /m * /mo THIRD /d WED /st 12:00"', `
'90'
)

$hashTable["Day3-EVRWed11AM"] = @( `
'Update Ring SF AutoRestart - Day3 EVR Wed11AM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc weekly /d Wed /st 05:02"', `
'"/sc weekly /d Wed /st 11:00"', `
'90'
)

$hashTable["Day3-EVRWed7AM"] = @( `
'Update Ring SF AutoRestart - Day3 EVR Wed 7AM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc weekly /d Wed /st 01:03"', `
'"/sc weekly /d Wed /st 07:00"', `
'90'
)

$hashTable["Day6-EVRSat15_00"] = @( `
'Update Ring SF AutoRestart - Day6 EVR Sat 15_00', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc weekly /d Sat /st 10:04"', `
'"/sc weekly /d Sat /st 15:00"', `
'90'
)

$hashTable["Day7-3rdSun10_00-Delay20"] = @( `
'Update Ring SF AutoRestart - Day7 3rd Sun 10_00 - Delay 20 min', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d SUN /st 04:04"', `
'"/sc monthly /m * /mo THIRD /d SUN /st 10:00"', `
'1200'
)

$hashTable["Day7-4thSun07_00-Delay20"] = @( `
'Update Ring SF AutoRestart - Day7 4th Sun 07_00 - Delay 20 min', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo FOURTH /d SUN /st 01:01"', `
'"/sc monthly /m * /mo FOURTH /d SUN /st 07:00"', `
'1200'
)

$hashTable["Day5-1stFri06_30-Delay20"] = @( `
'Update Ring SF AutoRestart - Day5 1st Fri 06_30 - Delay 20 min', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo FIRST /d FRI /st 00:31"', `
'"/sc monthly /m * /mo FIRST /d FRI /st 06:30"', `
'1200'
)

$hashTable["Day1-3rd-Mon-6AM"] = @( `
'Update Ring SF AutoRestart - Day1 3rd Mon 6AM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d MON /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d MON /st 06:00"', `
'90'
)

$hashTable["Day1-3rd-Mon-11AM"] = @( `
'Update Ring SF AutoRestart - Day1 3rd Mon 11AM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d MON /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d MON /st 11:00"', `
'90'
)

$hashTable["Day1-3rd-Mon-2_30PM"] = @( `
'Update Ring SF AutoRestart - Day1 3rd Mon 2_30PM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d MON /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d MON /st 14:30"', `
'90'
)
$hashTable["Day2-3rd-Tue-6AM"] = @( `
'Update Ring SF AutoRestart - Day2 3rd Tue 6AM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d TUE /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d TUE /st 06:00"', `
'90'
)
$hashTable["Day2-3rd-Tue-7AM"] = @( `
'Update Ring SF AutoRestart - Day2 3rd Tue 7AM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d TUE /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d TUE /st 07:00"', `
'90'
)
$hashTable["Day2-3rd-Tue-2_30PM"] = @( `
'Update Ring SF AutoRestart - Day2 3rd Tue 2_30PM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d TUE /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d TUE /st 14:30"', `
'90'
)
$hashTable["Day3-3rd-Wed-6AM"] = @( `
'Update Ring SF AutoRestart - Day3 3rd Wed 6AM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d WED /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d WED /st 06:00"', `
'90'
)
$hashTable["Day3-3rd-Wed-2_15PM"] = @( `
'Update Ring SF AutoRestart - Day3 3rd Wed 2_15PM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d WED /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d WED /st 14:15"', `
'90'
)
$hashTable["Day3-3rd-Wed-2_30PM"] = @( `
'Update Ring SF AutoRestart - Day3 3rd Wed 2_30PM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d WED /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d WED /st 14:30"', `
'90'
)
$hashTable["Day4-3rd-Thu-6AM"] = @( `
'Update Ring SF AutoRestart - Day4 3rd Thu 6AM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d THU /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d THU /st 06:00"', `
'90'
)
$hashTable["Day4-3rd-Thu-2_30PM"] = @( `
'Update Ring SF AutoRestart - Day4 3rd Thu 2_30PM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d THU /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d THU /st 14:30"', `
'90'
)
$hashTable["Day5-3rd-Fri-6AM"] = @( `
'Update Ring SF AutoRestart - Day5 3rd Fri 6AM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d FRI /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d FRI /st 06:00"', `
'90'
)
$hashTable["Day5-3rd-Fri-2_30PM"] = @( `
'Update Ring SF AutoRestart - Day5 3rd Fri 2_30PM', `
'"(do not leave empty)"', `
'"(do not leave empty)"', `
'"/sc monthly /m * /mo THIRD /d FRI /st 00:01"', `
'"/sc monthly /m * /mo THIRD /d FRI /st 14:30"', `
'90'
)
    
# Define the template for the main scripts
$firstLines = @'
    
    $triggerWU = {0} 
    $triggerRestart = {1}
    $schtasksWU = {2} 
    $schtasksRestart = {3}
    $restartDelay = {4}

'@

    try {
        # Create folder if not exists
        if (-not (Test-Path "$($path + "generatedScripts\")")) {
            $null = New-Item -Path "$($path + "generatedScripts\")" -ItemType Directory -ErrorAction Stop
        }

    } catch {

        try {
            $exception = $_.Exception
            Write-Warning $exception.GetType().FullName
            Write-Warning $exception.Message # .ToString().Replace("`r`n", " ").Replace("`n", " ")
            Write-Warning $exception.StackTrace # .ToString().Replace("`r`n", " ").Replace("`n", " ")
            Write-Warning $exception.InnerException
        } catch {}

        Write-Output "# $(timestamp): Exception while creating folder $path - $($exception.GetType().FullName) - $($exception.Message). Exiting."
        exit 1

    }

# we use the -Raw parameter when calling Get-Content to read the entire content of each file as a single string, including newline characters.
$scriptContent2 = Get-Content -Path $($path + "02 WindowsUpdateAndRestart6HoursLater - template.ps1") -Encoding UTF8 -Raw -ErrorAction Stop

foreach ($key in $hashTable.Keys) {
    
    $value = $hashTable[$key]

    # Generate the main scripts using the template and the variable values

    $scriptContent1 = $firstLines -f $value[1],$value[2],$value[3],$value[4],$value[5]
    # Write a text to a file using UTF-8 without BOM
    
    $scriptContent = $scriptContent1 + "`r`n" + $scriptContent2

    $scriptFileName = "WindowsUpdateAndRestart6HoursLater - $($key).ps1"

    $scriptFilePath = $path + "generatedScripts\" + $scriptFileName 

    Write-Host $scriptFileName -ForegroundColor Magenta
    Write-Host $scriptFilePath 

    # we use [System.IO.File]::WriteAllText instead of [System.IO.File]::WriteAllLines to write the merged content to the output file as a single string.
    [System.IO.File]::WriteAllText( $scriptFilePath, $scriptContent)
    
    if ( $ScriptsInfoHash[$value[0]] ) { #if we get script ID ...

        Write-Host $ScriptsInfoHash[$value[0]][0] -ForegroundColor Yellow # id
        Write-Host $ScriptsInfoHash[$value[0]][1] # scriptName
        Write-Host $ScriptsInfoHash[$value[0]][2] # lastUpdate timestamp

        Update-deviceManagementScript -scriptID $ScriptsInfoHash[$value[0]][0] -scriptPath ($path + "generatedScripts")  -scriptName $scriptFileName
        Write-Host "### Update-deviceManagementScript ID: $($ScriptsInfoHash[$value[0]][0]), path: $($path + "generatedScripts"), name:  $($scriptFileName)"
    }
        
    Write-Host " "

}

Stop-Transcript -Verbose -ErrorAction SilentlyContinue

<#

SCHTASKS /CREATE


C:\Windows\System32>schtasks /create /?

SCHTASKS /Create [/S system [/U username [/P [password]]]]
    [/RU username [/RP password]] /SC schedule [/MO modifier] [/D day]
    [/M months] [/I idletime] /TN taskname /TR taskrun [/ST starttime]
    [/RI interval] [ {/ET endtime | /DU duration} [/K] [/XML xmlfile] [/V1]]
    [/SD startdate] [/ED enddate] [/IT | /NP] [/Z] [/F] [/HRESULT] [/?]

Description:
    Enables an administrator to create scheduled tasks on a local or
    remote system.

Parameter List:
    /S   system        Specifies the remote system to connect to. If omitted
                       the system parameter defaults to the local system.

    /U   username      Specifies the user context under which SchTasks.exe
                       should execute.

    /P   [password]    Specifies the password for the given user context.
                       Prompts for input if omitted.

    /RU  username      Specifies the "run as" user account (user context)
                       under which the task runs. For the system account,
                       valid values are "", "NT AUTHORITY\SYSTEM"
                       or "SYSTEM".
                       For v2 tasks, "NT AUTHORITY\LOCALSERVICE" and
                       "NT AUTHORITY\NETWORKSERVICE" are also available as well
                       as the well known SIDs for all three.

    /RP  [password]    Specifies the password for the "run as" user.
                       To prompt for the password, the value must be either
                       "*" or none. This password is ignored for the
                       system account. Must be combined with either /RU or
                       /XML switch.

    /SC   schedule     Specifies the schedule frequency.
                       Valid schedule types: MINUTE, HOURLY, DAILY, WEEKLY,
                       MONTHLY, ONCE, ONSTART, ONLOGON, ONIDLE, ONEVENT.

    /MO   modifier     Refines the schedule type to allow finer control over
                       schedule recurrence. Valid values are listed in the
                       "Modifiers" section below.

    /D    days         Specifies the day of the week to run the task. Valid
                       values: MON, TUE, WED, THU, FRI, SAT, SUN and for
                       MONTHLY schedules 1 - 31 (days of the month).
                       Wildcard "*" specifies all days.

    /M    months       Specifies month(s) of the year. Defaults to the first
                       day of the month. Valid values: JAN, FEB, MAR, APR,
                       MAY, JUN, JUL, AUG, SEP, OCT, NOV, DEC. Wildcard "*"
                       specifies all months.

    /I    idletime     Specifies the amount of idle time to wait before
                       running a scheduled ONIDLE task.
                       Valid range: 1 - 999 minutes.

    /TN   taskname     Specifies the string in the form of path\name
                       which uniquely identifies this scheduled task.

    /TR   taskrun      Specifies the path and file name of the program to be
                       run at the scheduled time.
                       Example: C:\windows\system32\calc.exe

    /ST   starttime    Specifies the start time to run the task. The time
                       format is HH:mm (24 hour time) for example, 14:30 for
                       2:30 PM. Defaults to current time if /ST is not
                       specified.  This option is required with /SC ONCE.

    /RI   interval     Specifies the repetition interval in minutes. This is
                       not applicable for schedule types: MINUTE, HOURLY,
                       ONSTART, ONLOGON, ONIDLE, ONEVENT.
                       Valid range: 1 - 599940 minutes.
                       If either /ET or /DU is specified, then it defaults to
                       10 minutes.

    /ET   endtime      Specifies the end time to run the task. The time format
                       is HH:mm (24 hour time) for example, 14:50 for 2:50 PM.
                       This is not applicable for schedule types: ONSTART,
                       ONLOGON, ONIDLE, ONEVENT.

    /DU   duration     Specifies the duration to run the task. The time
                       format is HH:mm. This is not applicable with /ET and
                       for schedule types: ONSTART, ONLOGON, ONIDLE, ONEVENT.
                       For /V1 tasks, if /RI is specified, duration defaults
                       to 1 hour.

    /K                 Terminates the task at the endtime or duration time.
                       This is not applicable for schedule types: ONSTART,
                       ONLOGON, ONIDLE, ONEVENT. Either /ET or /DU must be
                       specified.

    /SD   startdate    Specifies the first date on which the task runs. The
                       format is dd/mm/yyyy. Defaults to the current
                       date. This is not applicable for schedule types: ONCE,
                       ONSTART, ONLOGON, ONIDLE, ONEVENT.

    /ED   enddate      Specifies the last date when the task should run. The
                       format is dd/mm/yyyy. This is not applicable for
                       schedule types: ONCE, ONSTART, ONLOGON, ONIDLE, ONEVENT.

    /EC   ChannelName  Specifies the event channel for OnEvent triggers.

    /IT                Enables the task to run interactively only if the /RU
                       user is currently logged on at the time the job runs.
                       This task runs only if the user is logged in.

    /NP                No password is stored.  The task runs non-interactively
                       as the given user.  Only local resources are available.

    /Z                 Marks the task for deletion after its final run.

    /XML  xmlfile      Creates a task from the task XML specified in a file.
                       Can be combined with /RU and /RP switches, or with /RP
                       alone, when task XML already contains the principal.

    /V1                Creates a task visible to pre-Vista platforms.
                       Not compatible with /XML.

    /F                 Forcefully creates the task and suppresses warnings if
                       the specified task already exists.

    /RL   level        Sets the Run Level for the job. Valid values are
                       LIMITED and HIGHEST. The default is LIMITED.

    /DELAY delaytime   Specifies the wait time to delay the running of the
                       task after the trigger is fired.  The time format is
                       mmmm:ss.  This option is only valid for schedule types
                       ONSTART, ONLOGON, ONEVENT.

    /HRESULT           For better diagnosability, the process exit code
                       will be in the HRESULT format.

    /?                 Displays this help message.

Modifiers: Valid values for the /MO switch per schedule type:
    MINUTE:  1 - 1439 minutes.
    HOURLY:  1 - 23 hours.
    DAILY:   1 - 365 days.
    WEEKLY:  weeks 1 - 52.
    ONCE:    No modifiers.
    ONSTART: No modifiers.
    ONLOGON: No modifiers.
    ONIDLE:  No modifiers.
    MONTHLY: 1 - 12, or
             FIRST, SECOND, THIRD, FOURTH, LAST, LASTDAY.

    ONEVENT:  XPath event query string.
Examples:
    ==> Creates a scheduled task "doc" on the remote machine "ABC"
        which runs notepad.exe every hour under user "runasuser".

        SCHTASKS /Create /S ABC /U user /P password /RU runasuser
                 /RP runaspassword /SC HOURLY /TN doc /TR notepad

    ==> Creates a scheduled task "accountant" on the remote machine
        "ABC" to run calc.exe every five minutes from the specified
        start time to end time between the start date and end date.

        SCHTASKS /Create /S ABC /U domain\user /P password /SC MINUTE
                 /MO 5 /TN accountant /TR calc.exe /ST 12:00 /ET 14:00
                 /SD 06/06/2006 /ED 06/06/2006 /RU runasuser /RP userpassword

    ==> Creates a scheduled task "gametime" to run freecell on the
        first Sunday of every month.

        SCHTASKS /Create /SC MONTHLY /MO first /D SUN /TN gametime
                 /TR c:\windows\system32\freecell

    ==> Creates a scheduled task "report" on remote machine "ABC"
        to run notepad.exe every week.

        SCHTASKS /Create /S ABC /U user /P password /RU runasuser
                 /RP runaspassword /SC WEEKLY /TN report /TR notepad.exe

    ==> Creates a scheduled task "logtracker" on remote machine "ABC"
        to run notepad.exe every five minutes starting from the
        specified start time with no end time. The /RP password will be
        prompted for.

        SCHTASKS /Create /S ABC /U domain\user /P password /SC MINUTE
                 /MO 5 /TN logtracker
                 /TR c:\windows\system32\notepad.exe /ST 18:30
                 /RU runasuser /RP

    ==> Creates a scheduled task "gaming" to run freecell.exe starting
        at 12:00 and automatically terminating at 14:00 hours every day

        SCHTASKS /Create /SC DAILY /TN gaming /TR c:\freecell /ST 12:00
                 /ET 14:00 /K
    ==> Creates a scheduled task "EventLog" to run wevtvwr.msc starting
        whenever event 101 is published in the System channel

        SCHTASKS /Create /TN EventLog /TR wevtvwr.msc /SC ONEVENT
                 /EC System /MO *[System/EventID=101]
    ==> Spaces in file paths can be used by using two sets of quotes, one
        set for CMD.EXE and one for SchTasks.exe.  The outer quotes for CMD
        need to be double quotes; the inner quotes can be single quotes or
        escaped double quotes:
        SCHTASKS /Create
           /tr "'c:\program files\internet explorer\iexplorer.exe'
           \"c:\log data\today.xml\"" ...

C:\Windows\System32>


#>