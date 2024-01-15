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