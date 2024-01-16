    
    $schtasksWU = "/sc weekly /d Fri /st 00:51" 
    $schtasksRestart = "/sc weekly /d Fri /st 06:50"
    $restartDelay = 90

<#
# These three variables need to be present in the target script:
# They will be inserted using "03 WindowsUpdateAndRestart6HoursLater - generate scripts.ps1"

    # schedule (using SCHTASKS syntax) for "WindowsUpdateNoRestart" task
    $schtasksWU = "/sc monthly /m * /mo THIRD /d SUN /st 04:04"
    
        # Other examples: 
        # $schtasksWU = "/sc monthly /m * /mo FOURTH /d SUN /st 18:00"
        # $schtasksWU = "/sc WEEKLY /d FRI /st 17:32"

    # schedule (using SCHTASKS syntax) for "RestartAfterWindowsUpdate" task
    $schtasksRestart = "/sc monthly /m * /mo THIRD /d SUN /st 10:00"
    
        # Other example: 
        # $schtasksRestart = "/sc monthly /m * /mo SECOND /d TUE /st 10:00"
    
    # restart delay in seconds
    $restartDelay = 90 

        # Example: 
        # $restartDelay = 1200 # 20 minutes, numeric value, no quotes

#>

# TEMPLATE - Schedule the task that runs Windows Update, to run 6 hours before we run another task that restarts the device

$version = "2024.01.15.01"
$path = "C:\ProgramData\YourFolderName\Intune\" 

# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-5.1
$ConfirmPreference = 'None'
$InformationPreference = 'Continue'
$VerbosePreference = 'Continue' # this will ensure that -Verbose is written in a transcript for all commands
$global:DebugPreference = 'SilentlyContinue' 

$ErrorActionPreference = "Stop" # set default ErrorAction for all commands
$WarningActionPreference = "Continue" # set default action for all commands

# including timezone information
function timestamp {

    try {

        return "$((get-date -ErrorAction Stop).ToString("yyyy-MM-ddTHH:mm:sszzz"))"  
        # the actual time (on the clock) + current timezone shift

    } catch {

        return "yyyy-MM-ddTHH:mm:sszzz"

    }

}

# 2023.11.24.01
# without timezone information, suitable for file names etc (colon character removed)
function timestamp2 {

    try {

        return "$((get-date -ErrorAction Stop).ToString("yyyy-MM-ddTHHmmss"))" 
        # the actual time (on the clock) + current timezone shift

    } catch {

        return "yyyy-MM-ddTHHmmss"

    }

}

### SUPER IMPORTANT - USE SINGLE QUOTES, TO AVOID ENUMERATION -> saving a string to a file as is, without expanding any variables by values etc.
$scriptFile = @'
cls

$version = "2024.01.15.01"
$path = "C:\ProgramData\YourFolderName\Intune\" 

$InformationPreference = 'Continue'
$VerbosePreference = 'Continue' # this will ensure that -Verbose is written in a transcript for all commands
$DebugPreference = 'SilentlyContinue' 

$ErrorActionPreference = "Stop" # set default ErrorAction for all commands
$WarningActionPreference = "Continue" # set default action for all commands

# including timezone information
function timestamp {

    try {

        return "$((get-date -ErrorAction Stop).ToString("yyyy-MM-ddTHH:mm:sszzz"))"  
        # the actual time (on the clock) + current timezone shift

    } catch {

        return "yyyy-MM-ddTHH:mm:sszzz"

    }

}

# without timezone information, suitable for file names etc (colon character removed)
function timestamp2 {

    try {

        return "$((get-date -ErrorAction Stop).ToString("yyyy-MM-ddTHHmmss"))" 
        # the actual time (on the clock) + current timezone shift

    } catch {

        return "yyyy-MM-ddTHHmmss"

    }

}

    ##################################################################################################################
    ####### Create folder $path 
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

try { # main program

    ##################################################################################################################
    ############## Start the transcript 
    ##################################################################################################################

        try {
            Stop-Transcript -ErrorAction SilentlyContinue # in case some lingering transcript is running
        } catch {}

        $logFile = $path + (timestamp2) + "-WindowsUpdateAndRestart.txt" # log file

        # the file should not exist (it includes a timestamp), but if it does, delete it (the only possibility is if 'timestamp2' function fails to provide a current timestamp, this should never happen)
        $null = Remove-Item $logFile -Force -ErrorAction SilentlyContinue | out-null	

        Start-Transcript -Path $logFile -Append -ErrorAction Continue

    ##################################################################################################################
    ############## Header in transcript 
    ##################################################################################################################

        Write-Output "### Scheduled task - WindowsUpdate - Download and Install"
        $serialNumber = "$( (Get-CimInstance win32_bios -ErrorAction Continue).SerialNumber )"
        Write-Output  ("{0};{1};{2};{3};{4};{5};{6}" -f  $(timestamp), $($env:computername), $($env:USERDOMAIN),$($env:USERDNSDOMAIN),$($env:username), $($serialNumber), $($version))


    ##################################################################################################################
    ###### load the module/package provider  
    ##################################################################################################################

        # enabling TLS1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        # 2023-11-24 including before Get-PSRepository / Set-PSRepository calls which until finding out why the scripts hangs on Get-PSRepository / Set-PSRepository 
        Write-Output "# $(timestamp): Find-PackageProvider -Name 'Nuget' -ForceBootstrap -IncludeDependencies"
        Find-PackageProvider -Name 'Nuget' -ForceBootstrap -IncludeDependencies -ErrorAction Continue

        try {
            $url = "https://www.powershellgallery.com/api/v2"

            Write-Output "# $(timestamp): Verifying access to $url"

            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
            
                Write-Output "# $(timestamp): Access to $url was successful."
                
                if( (Get-PSRepository -Name "PSGallery").InstallationPolicy -ne "Trusted") { 
                    
                    Write-Output "# $(timestamp): Set-PSRepository PSGallery"
                    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -Verbose 
                    Write-Output "# $(timestamp): Set-PSRepository PSGallery: DONE"

                } else {
                    Write-Output "# $(timestamp): PSGallery is already Trusted repository. No action necessary."
                }

            } else {
                Write-Output "# $(timestamp): Access to $url was not successful. Status code: $($response.StatusCode)"
            }
        } catch {
    
            try {
                $exception = $_.Exception
                Write-Warning $exception.GetType().FullName
                Write-Warning $exception.Message 
                Write-Warning $exception.StackTrace 
                Write-Warning $exception.InnerException
            } catch {}

            Write-Output "# $(timestamp): Exception while accessing $url - $($exception.GetType().FullName) - $($exception.Message)"

        }

    # NuGet
    Write-Output "# $(timestamp): Get-PackageProvider -Name nuget -ListAvailable"
    $packageprovider = Get-PackageProvider -Name nuget -ListAvailable -ErrorAction Continue # -Verbose 

    # If not installed, download and install it from PSGallery repository
    if (-not $packageprovider) {
        Write-Output "# $(timestamp): Install NuGet provider"
        Install-PackageProvider -Name NuGet -Scope AllUsers -Force -confirm:$false -ErrorAction Continue #  -Verbose  -MinimumVersion 2.8.5.201 -Verbose 
    }

    try {

        Write-Output "# $(timestamp): Import-PackageProvider nuget"

        Import-PackageProvider nuget -Force -ErrorAction Stop # -Verbose 

        Write-Output "# $(timestamp): Import-PackageProvider nuget : DONE"

    } catch {

        try {
            $exception = $_.Exception
            Write-Warning $exception.GetType().FullName
            Write-Warning $exception.Message 
            Write-Warning $exception.StackTrace 
            Write-Warning $exception.InnerException
        } catch {}

        Write-Output "# $(timestamp): Import-PackageProvider nuget: Exception - $($exception.GetType().FullName) - $($exception.Message)." #  Exiting.

    }
    
    # Check if PSWindowsUpdate module is already installed
    Write-Output "# $(timestamp): Get-Module -Name PSWindowsUpdate"
    $module = Get-Module -Name PSWindowsUpdate -ListAvailable -ErrorAction Continue # -Verbose 

    # If not installed, download and install it from PSGallery repository
    if (-not $module) {
        # Install PSWindowsUpdate module for all users
        Write-Output "# $(timestamp): Install-Module -Name PSWindowsUpdate"
        Install-Module -Name PSWindowsUpdate -Scope AllUsers -AllowClobber -Force -confirm:$false -ErrorAction Continue # -Verbose 
        Write-Output "# $(timestamp): Install-Module -Name PSWindowsUpdate : DONE"
    }

    # Import PSWindowsUpdate module
    try {
        Write-Output "# $(timestamp): Import-Module PSWindowsUpdate"

        Import-Module -Name PSWindowsUpdate -Scope Global -PassThru -ErrorAction Stop # -Verbose 
    
        Write-Output "# $(timestamp): Import-Module PSWindowsUpdate : DONE"

    } catch {

        try {
            $exception = $_.Exception
            Write-Warning $exception.GetType().FullName
            Write-Warning $exception.Message 
            Write-Warning $exception.StackTrace 
            Write-Warning $exception.InnerException
        } catch {}

        Write-Output "# $(timestamp): Import-Module PSWindowsUpdate : Exception - $($exception.GetType().FullName) - $($exception.Message). Exiting."

        exit 1

    }

    ##################################################################################################################
    ####### Checking if required Windows services are running
    ##################################################################################################################

    Write-Output "# $(timestamp): WindowsUpdate service"

        $WindowsUpdateService = Get-Service -Name wuauserv -Verbose -ErrorAction Continue
        $WindowsUpdateService | Select-Object -Property *  -ErrorAction Continue

        if( $WindowsUpdateService.StartType -eq "Disabled"){
            Write-Output "# $(timestamp): Set-Service -Name wuauserv -StartupType Manual"
            Set-Service -Name wuauserv -StartupType Manual -Verbose  -ErrorAction Continue
        }

        if( $WindowsUpdateService.Status -ne "Running"){
            Write-Output "# $(timestamp): Start-Service -Name wuauserv"
            Start-Service -Name wuauserv -Verbose  -ErrorAction Continue
        }

    Write-Output "# $(timestamp): Windows Update Medic Service or WaaSMedicSVC"

        $WindowsUpdateMedicService = Get-Service -Name WaaSMedicSVC  -ErrorAction Continue -Verbose
        $WindowsUpdateMedicService | Select-Object -Property *  -ErrorAction Continue

        if( $WindowsUpdateMedicService.StartType -eq "Disabled") {
            Write-Output "# $(timestamp): Set-Service -Name WaaSMedicSVC -StartupType Manual "
            Set-Service -Name WaaSMedicSVC -StartupType Manual  -ErrorAction Continue -Verbose
        }
        if( $WindowsUpdateMedicService.Status -ne "Running") { 
            Write-Output "# $(timestamp): Start-Service -Name WaaSMedicSVC"
            Start-Service -Name WaaSMedicSVC  -ErrorAction Continue -Verbose
        }
            
    ##################################################################################################################
    ####### key part of the script - download and the installation
    ##################################################################################################################
        
    Write-Output "# $(timestamp): Get-WindowsUpdate -Download -AcceptAll -Verbose"
    Get-WindowsUpdate -Download -AcceptAll -Verbose -ErrorAction Continue # -NotCategory "Drivers" -Silent 

        Write-Output "# $(timestamp): List all the Windows Updates downloaded but not yet installed:"
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search("IsInstalled=0")
        $updates = $result.Updates | Where-Object {$_.IsDownloaded -eq $true} 
        $updates
        
        Write-Output "# $(timestamp): List all categories (downloaded but not yet installed updates):"
        $updates.Categories | Select-Object Name,CategoryID,Description,Type | fl

        Write-Output "# $(timestamp): Number of downloaded Windows Updates (but not yet installed): $( $updates.Count )"

    Write-Output "# $(timestamp): Install-WindowsUpdate -AcceptAll -IgnoreReboot -Verbose (including Drivers)."
    
    $tmpInstall = Install-WindowsUpdate -AcceptAll -IgnoreReboot -Verbose -ErrorAction Continue
    # -Category 'Drivers','Security Updates','Critical Updates','Service Packs','Microsoft Defender Antivirus','Definition Updates','Windows Security platform','Updates','Feature Packs'
    # to exclude drivers, use parameter -NotCategory "Drivers"

    ##################################################################################################################
    ####### after-installation reporting
    ##################################################################################################################
    
    foreach($tmpUpdate in $tmpInstall) {

        Write-Output "# $(timestamp): Installed update '$( $tmpUpdate.KB )' - '$( $tmpUpdate.Title )':"
        $tmpUpdate | Format-list
        $tmpUpdate.categories | Select-Object Name,CategoryID,Description,Type | Format-list

    }
    
    Write-Output "# $(timestamp): Last 10 updates (install/uninstall):"
    Get-WUHistory -Last 10 -ErrorAction Continue | Sort-Object Date -Descending | Format-List 

    Write-Output "# $(timestamp): Last events with Source as User32 and Event ID as 1074. These events indicate that an application or user has initiated a restart or shutdown."

    # Get the newest 3 log entries from System log where Source=User32 and EventID=1074
    # https://learn.microsoft.com/en-us/powershell/scripting/samples/creating-get-winevent-queries-with-filterhashtable?view=powershell-5.1
    Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='User32'; Id=1074 } -MaxEvents 3 | fl 

    Write-Output "# $(timestamp): Check Windows Update Installer status: Get-WUInstallerStatus"
    Get-WUInstallerStatus  -Verbose   | Format-List # -Silent 

    Write-Output "# $(timestamp): Check Windows Update reboot status. Is reboot required? Get-WURebootStatus"
    # it is mandatory to use -silent parameter, otherwise the command might get stuck on "Reboot is required. Do it now? [Y / N] (default is 'N')"
    Get-WURebootStatus -Verbose -silent | Format-List 

} catch { # main program

        try {
            $exception = $_.Exception
            Write-Warning $exception.GetType().FullName
            Write-Warning $exception.Message 
            Write-Warning $exception.StackTrace 
            Write-Warning $exception.InnerException
        } catch {}

        Write-Output "# $(timestamp): Exception in a main program - $($exception.GetType().FullName) - $($exception.Message). Exiting."

}

try {
    Stop-Transcript -ErrorAction Continue -Verbose
} catch {}

exit
'@

try { # main program

    ##################################################################################################################
    ####### Create folder $path ####################################################################################
    ##################################################################################################################

        Write-Output "# $(timestamp): Creating $path"

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

    ##################################################################################################################
    ############## Transcript ############## ############## ############## ############## ############## ############## 
    ##################################################################################################################

        try {
            Stop-Transcript -ErrorAction SilentlyContinue     # Stop-Transcript, in case some lingering transcript is running
        } catch {}

        $logFile = $path + (timestamp2) + "-WindowsUpdateAndRestart.txt" # log file

        # the file should not exist (it includes a timestamp), but if it does, delete it (the only possibility is if 'timestamp2' function fails to provide a current timestamp, this should never happen)
        $null = Remove-Item $logFile -Force -ErrorAction SilentlyContinue | out-null	

        Start-Transcript -Path $logFile -Append -ErrorAction Continue

    ##################################################################################################################
    ############## Header in transcript ############## ############## ############## ############## ############## ############## 
    ##################################################################################################################

        Write-Output "### SETUP script - Schedule the task that runs Windows Update, to run 6 hours before we run another task that restarts the device"
        $serialNumber = "$( (Get-CimInstance win32_bios -ErrorAction Continue).SerialNumber )"
        Write-Output ("{0};{1};{2};{3};{4};{5};{6}" -f  $(timestamp), $($env:computername), $($env:USERDOMAIN),$($env:USERDNSDOMAIN),$($env:username), $($serialNumber), $($version)) 

    ##################################################################################################################
    ##### grant permissions to SYSTEM:Full control to "C:\ProgramData\YourFolderName\" ###################################
    ##################################################################################################################

        try {
            # Get current access permissions from folder and store in object
            $Access = Get-Acl -Path "C:\ProgramData\YourFolderName\" -ErrorAction Stop

            # Create new object with required new permissions
            $NewRule = New-Object System.Security.AccessControl.FileSystemAccessRule ("SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow") -ErrorAction Stop

            # Add new rule to our copy of the current rules
            $Access.AddAccessRule($NewRule)

            # Apply our new rule object to destination folder
            Set-Acl -Path "C:\ProgramData\YourFolderName\" -AclObject $Access -ErrorAction Stop

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
                # $log.IsEnabled=$false

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

    ##################################################################################################################
    ###### create a script file with embedded script     #############################################################
    ##################################################################################################################
  
        $fileName = $path + "WindowsUpdate.ps1"

        # cleanup of $fileName 
        $null = Remove-Item $fileName -Force -ErrorAction SilentlyContinue | out-null	

        ### $scriptFile | Out-file $fileName -Encoding utf8  ### do not use, cannot save in utf8NoBOM (only in Powershell 6.0+)

        # Write some text to a file using UTF-8 without BOM
        [System.IO.File]::WriteAllLines($fileName, $scriptFile)

    ##################################################################################################################
    # Task - Windows Update     ######################################################################################
    ##################################################################################################################
    
        $taskName = "WindowsUpdateNoRestart"

        #if there is such scheduled task, delete it
        Unregister-ScheduledTask -TaskPath "\YourFolderName\" -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue  -Verbose # -TaskPath \* 

        Write-Output "### Creating scheduled task $($taskName)"

        # c:\apps\myapp.exe is a placeholder, it will be corrected in the next step, using Powershell
        # schtasks.exe arguments
        $schtasks_args = "/create /tn ""\YourFolderName\$($taskName)"" /tr c:\apps\myapp.exe /ru System /RL Highest /F " + $schtasksWU

        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-5.1
        $schtasks_process = Start-Process "$($env:windir)\system32\schtasks.exe" -ArgumentList "$($schtasks_args)" -Wait -verb RunAs -PassThru -WindowStyle Hidden
        # -NoNewWindow ... generates error Start-Process : Parameter set cannot be resolved using the specified named parameters.
    
        if ($schtasks_process.exitcode -eq 0) { # SUCCESS of SCHTASKS

            # Create a new action that will run the script
            $action = New-ScheduledTaskAction -Execute "C:\Windows\system32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File $($fileName)" 

            $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 0 -MultipleInstances Queue
            # https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset?view=windowsserver2022-ps
            # -ExecutionTimeLimit (New-TimeSpan -Hours 6) -WakeToRun -RunOnlyIfNetworkAvailable 

            # when using 'schtasks', I just update the parameters of the task created by 'SCHTASKS'
            # unable to set Description, neither via SCHTASKS, not Set-ScheduledTask
            # combination of "-Principal $System" + "-RunLevel Highest" did not work for me: Register-ScheduledTask : Parameter set cannot be resolved using the specified named parameters.
     
            Set-ScheduledTask -Action $action -TaskName $taskName -TaskPath "\YourFolderName\" -User "SYSTEM" -Settings $Settings -Verbose -ErrorAction Continue


            Write-Output "### Scheduled task $($taskName) created successfully."

        } else { # if ($schtasks_process.exitcode -eq 0) 

            Write-Output "### Error creating $($taskName): $($schtasks_process.exitcode)"

        }

    ##################################################################################################################
    # Task - Restart device     ######################################################################################
    ##################################################################################################################

        $taskName = "RestartAfterWindowsUpdate"

        #if there is such scheduled task, delete it
        Unregister-ScheduledTask -TaskPath "\YourFolderName\" -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue  -Verbose

        Write-Output "### Creating scheduled task $($taskName)"

        # c:\apps\myapp.exe is a placeholder, it will be corrected in the next step, using Powershell
        # schtasks.exe arguments
        $schtasks_args = "/create /tn ""\YourFolderName\$($taskName)"" /tr c:\apps\myapp.exe /ru System /RL Highest /F " + $schtasksRestart

        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-5.1
        $schtasks_process = Start-Process "$($env:windir)\system32\schtasks.exe" -ArgumentList "$($schtasks_args)" -Wait -verb RunAs -PassThru -WindowStyle Hidden
        # -NoNewWindow ... generates error Start-Process : Parameter set cannot be resolved using the specified named parameters.

        if ($schtasks_process.exitcode -eq 0) { # SUCCESS of SCHTASKS

            # Create a new action that will run the script

            if (-not $restartDelay) { $restartDelay = 90 } # default of 90 seconds
        
            [string]$tmpArgument = '/t {0} /r /c "Planned system restart in {1} minutes." /d p:2:17' -f $restartDelay,$($restartDelay / 60)

            $action = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument $tmpArgument

            $Settings = New-ScheduledTaskSettingsSet -DontStopOnIdleEnd -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 0 -MultipleInstances Queue -ExecutionTimeLimit (New-TimeSpan -Hours 1) # -WakeToRun 
            # https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset?view=windowsserver2022-ps
            # -RunOnlyIfNetworkAvailable 

            # when using 'schtasks', I just update the parameters of the task created by 'SCHTASKS'
            Set-ScheduledTask -Action $action -TaskName $taskName -TaskPath "\YourFolderName\" -User "SYSTEM" -Settings $Settings -Verbose -ErrorAction Continue

            Write-Output "### Scheduled task $($taskName) created successfully."
                
        } else { # if ($schtasks_process.exitcode -eq 0) 

            Write-Output "### Error creating $($taskName): $($schtasks_process.exitcode)"

        }

    ##################################################################################################################
    ###### load the same module/package provider as the actual script will need (to have it ready in advance) ########
    ##################################################################################################################

        # enabling TLS1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        # 2023-11-24 including before Get-PSRepository / Set-PSRepository calls which until finding out why the scripts hangs on Get-PSRepository / Set-PSRepository 
        Write-Output "# $(timestamp): Find-PackageProvider -Name 'Nuget' -ForceBootstrap -IncludeDependencies"
        Find-PackageProvider -Name 'Nuget' -ForceBootstrap -IncludeDependencies -ErrorAction Continue
      
        try {
            $url = "https://www.powershellgallery.com/api/v2"

            Write-Output "# $(timestamp): Verifying access to $url"

            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
            
                Write-Output "# $(timestamp): Access to $url was successful."
                
                # 2023-11-24 DEBUG used temporarily until finding out why  the scripts hangs on Get-PSRepository / Set-PSRepository 
                # to supress the prompt 'Continue with this operation? [Y] Yes [A] Yes to All [H] Halt Command [S] Suspend [?] Help (default is "Y"):' when using the -Debug parameter --- instead of using -Debug parameter, use the following workaround:

                    $tmpDebugPreference = $DebugPreference 
                    $DebugPreference = 'Continue'

                    if( (Get-PSRepository -Name "PSGallery" -Verbose).InstallationPolicy -ne "Trusted") { 
                    
                        Write-Output "# $(timestamp): Set-PSRepository PSGallery"
                        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -Verbose
                        Write-Output "# $(timestamp): Set-PSRepository PSGallery: DONE"

                    } else {
                        Write-Output "# $(timestamp): PSGallery is already Trusted repository. No action necessary."
                    }
                
                    $DebugPreference = $tmpDebugPreference
                
            } else {
                Write-Output "# $(timestamp): Access to $url was not successful. Status code: $($response.StatusCode)"
            }
        } catch {
    
            try {
                $exception = $_.Exception
                Write-Warning $exception.GetType().FullName
                Write-Warning $exception.Message 
                Write-Warning $exception.StackTrace 
                Write-Warning $exception.InnerException
            } catch {}

            Write-Output "# $(timestamp): Exception while accessing $url - $($exception.GetType().FullName) - $($exception.Message)"

        }


        # NuGet --- if using 'Find-PackageProvider -Name 'Nuget' -ForceBootstrap -IncludeDependencies', this should not be necessary
        Write-Output "# $(timestamp): Get-PackageProvider -Name nuget -ListAvailable"
        $packageprovider = Get-PackageProvider -Name nuget -ListAvailable -Verbose -ErrorAction Continue

        # If not installed, download and install it from PSGallery repository
        if (-not $packageprovider) {
            Write-Output "# $(timestamp): Install NuGet provider"
            Install-PackageProvider -Name NuGet -Scope AllUsers -Verbose -Force -confirm:$false -ErrorAction Continue #  -MinimumVersion 2.8.5.201
        }

        try {

            Write-Output "# $(timestamp): Import-PackageProvider nuget"

            Import-PackageProvider nuget -Force -Verbose -ErrorAction Stop

            Write-Output "# $(timestamp): Import-PackageProvider nuget : DONE"

        } catch {

            try {
                $exception = $_.Exception
                Write-Warning $exception.GetType().FullName
                Write-Warning $exception.Message 
                Write-Warning $exception.StackTrace 
                Write-Warning $exception.InnerException
            } catch {}

            Write-Output "# $(timestamp): Import-PackageProvider nuget: Exception - $($exception.GetType().FullName) - $($exception.Message)."

        }

        # Check if PSWindowsUpdate module is already installed
        Write-Output "# $(timestamp): Get-Module -Name PSWindowsUpdate"
        $module = Get-Module -Name PSWindowsUpdate -ListAvailable -ErrorAction Continue # -Verbose 

        # If not installed, download and install it from PSGallery repository
        if (-not $module) {
            # Install PSWindowsUpdate module for all users
            Write-Output "# $(timestamp): Install-Module -Name PSWindowsUpdate"
            Install-Module -Name PSWindowsUpdate -Scope AllUsers -AllowClobber -Force -confirm:$false -ErrorAction Continue # -Verbose 
            Write-Output "# $(timestamp): Install-Module -Name PSWindowsUpdate : DONE"
        }

        # Import PSWindowsUpdate module
        try {

            Write-Output "# $(timestamp): Import-Module PSWindowsUpdate"

            Import-Module -Name PSWindowsUpdate -Scope Global -Verbose  -PassThru -ErrorAction Stop 
    
            Write-Output "# $(timestamp): Import-Module PSWindowsUpdate : DONE"

        } catch {

            try {
                $exception = $_.Exception
                Write-Warning $exception.GetType().FullName
                Write-Warning $exception.Message 
                Write-Warning $exception.StackTrace 
                Write-Warning $exception.InnerException
            } catch {}

            Write-Output "# $(timestamp): Import-Module PSWindowsUpdate : Exception - $($exception.GetType().FullName) - $($exception.Message)."

        }

        Write-Output "# $(timestamp): WindowsUpdate service"

        $WindowsUpdateService = Get-Service -Name wuauserv -Verbose -ErrorAction Continue
        $WindowsUpdateService | Select-Object -Property *  -ErrorAction Continue

        if( $WindowsUpdateService.StartType -eq "Disabled"){
            Write-Output "# $(timestamp): Set-Service -Name wuauserv -StartupType Manual"
            Set-Service -Name wuauserv -StartupType Manual -Verbose  -ErrorAction Continue
        }

        if( $WindowsUpdateService.Status -ne "Running"){
            Write-Output "# $(timestamp): Start-Service -Name wuauserv"
            Start-Service -Name wuauserv -Verbose  -ErrorAction Continue
        }

    Write-Output "# $(timestamp): Windows Update Medic Service or WaaSMedicSVC"

        $WindowsUpdateMedicService = Get-Service -Name WaaSMedicSVC  -ErrorAction Continue -Verbose
        $WindowsUpdateMedicService | Select-Object -Property *  -ErrorAction Continue

        if( $WindowsUpdateMedicService.StartType -eq "Disabled") {
            Write-Output "# $(timestamp): Set-Service -Name WaaSMedicSVC -StartupType Manual "
            Set-Service -Name WaaSMedicSVC -StartupType Manual  -ErrorAction Continue -Verbose
        }
        if( $WindowsUpdateMedicService.Status -ne "Running") { 
            Write-Output "# $(timestamp): Start-Service -Name WaaSMedicSVC"
            Start-Service -Name WaaSMedicSVC  -ErrorAction Continue -Verbose
        }

} catch { # main program

        try {
            $exception = $_.Exception
            Write-Warning $exception.GetType().FullName
            Write-Warning $exception.Message 
            Write-Warning $exception.StackTrace 
            Write-Warning $exception.InnerException
        } catch {}

        Write-Output "# $(timestamp): Exception in a main program - $($exception.GetType().FullName) - $($exception.Message). Exiting."

}

try {
    Stop-Transcript -ErrorAction Continue -Verbose
} catch {}

exit