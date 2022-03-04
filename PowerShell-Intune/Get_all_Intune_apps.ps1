
# Get all assigned Intune policies and apps per Azure AD group
# thanks to Timmy Andersson at https://timmyit.com/2019/12/04/get-all-assigned-intune-policies-and-apps-per-azure-ad-group/

cls

# https://newbedev.com/how-do-i-check-if-a-powershell-module-is-installed
function Load-Module ($m) {

    # If module is imported say that and do nothing
    if (Get-Module | Where-Object {$_.Name -eq $m}) {
        write-host "Module $m is already imported."
    }
    else {

        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) {
            Import-Module $m -Verbose
        }
        else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $m | Where-Object {$_.Name -eq $m}) {
                Install-Module -Name $m -Force -Verbose -Scope CurrentUser
                Import-Module $m -Verbose
            }
            else {

                # If the module is not imported, not available and not in the online gallery then abort
                write-host "Module $m not imported, not available and not in an online gallery, exiting."
                EXIT 1
            }
        }
    }
}

Load-Module "Microsoft.Graph.Intune" 

# Connect and change schema 
if(!(Connect-MSGraph)){ 
    Connect-MSGraph -ForceInteractive
    Update-MSGraphEnvironment -SchemaVersion beta
    Connect-MSGraph
}
 
 
#### Config 
    
    # Apps
    $Resource = "/deviceAppManagement/mobileApps"
    $graphApiVersion = "Beta"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$expand=Assignments"
    $App = Invoke-MSGraphRequest -HttpMethod GET -Url $uri
    $AllApps = $App.value # | Where-Object {$_.assignments -match $Group.id}
    Write-host "Number of apps found: $($AllApps.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllApps) { 
        #Write-host $Config.displayName -ForegroundColor Yellow 

        if($Config.displayName -like "Adobe Cloud Desktop") { ### just an example
            Write-host "$($Config)" -ForegroundColor Yellow 
            Write-host "=========================================================================" -ForegroundColor Green
        }

    }

    <#

    # Apps
    $AllAssignedApps = Get-IntuneMobileApp # -Filter "isAssigned eq true" -Select id, displayName, lastModifiedDateTime, assignments -Expand assignments | Where-Object {$_.assignments -match $Group.id}
    Write-host "Number of Apps found: $($AllAssignedApps.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllAssignedApps) { 
        Write-host "$($Config)" -ForegroundColor Yellow 
        Write-host "=========================================================================" -ForegroundColor Green
        #Write-host "$($Config.displayName) --- $($Config.largeIcon)" -ForegroundColor Yellow 
    } # $Config.displayName 
 
    #>
 