
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
 
# Which AAD group do we want to check against
$groupName = "Intune-Devices-EMEA-All"
 
# All AAD groups ... $Groups = Get-AADGroup | Get-MSGraphAllPages
# All Intune groups in AAD ... e.g. $Groups = Get-AADGroup | Get-MSGraphAllPages | Where {($_.displayName -like “NL-*” -or $_.displayName -like “*Intune*”)}
$Groups = Get-AADGroup -Filter "displayname eq '$GroupName'"

 
#### Config 
Foreach ($Group in $Groups) {
    Write-host "AAD Group Name: $($Group.displayName)" -ForegroundColor Green
 
    <#
    # Members
    $AllAssignedUsers = (Get-AADGroupMember -groupId $Group.id) | Select-Object -Property displayName
    Write-host ” Number of Users found: $($AllAssignedUsers.DisplayName.Count)” -ForegroundColor cyan
    Foreach ($User in $AllAssignedUsers) { Write-host ” “, $User.DisplayName -ForegroundColor Gray }
    #>

    # Proactive remediations - thanks to https://www.systanddeploy.com/2020/12/manage-intune-proactive-remediation.html
    $Resource = "deviceManagement/deviceHealthScripts"
    $graphApiVersion = "Beta"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$expand=Assignments"
    $ProRem = Invoke-MSGraphRequest -HttpMethod GET -Url $uri
    $AllProRem = $ProRem.value | Where-Object {$_.assignments -match $Group.id}
    Write-host "Number of Proactive Remediations found: $($AllProRem.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllProRem) { Write-host $Config.displayName -ForegroundColor Yellow }


    # Settings Catalogs
    $Resource = “deviceManagement/configurationPolicies”
    $graphApiVersion = “Beta”
    $uri = “https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$expand=Assignments”
    $SC = Invoke-MSGraphRequest -HttpMethod GET -Url $uri
    $AllSC = $SC.value | Where-Object {$_.assignments -match $Group.id}
    Write-host “Number of Device Settings Catalogs found: $($AllSC.Name.Count)” -ForegroundColor cyan
    Foreach ($Config in $AllSC) { Write-host $Config.Name -ForegroundColor Yellow }


    # Administrative templates
    $Resource = "deviceManagement/groupPolicyConfigurations"
    $graphApiVersion = "Beta"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$expand=Assignments"
    $ADMT = Invoke-MSGraphRequest -HttpMethod GET -Url $uri
    $AllADMT = $ADMT.value | Where-Object {$_.assignments -match $Group.id}
    Write-host "Number of Device Administrative Templates found: $($AllADMT.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllADMT) { Write-host $Config.displayName -ForegroundColor Yellow }


    # Apps
    $AllAssignedApps = Get-IntuneMobileApp -Filter "isAssigned eq true" -Select id, displayName, lastModifiedDateTime, assignments -Expand assignments | Where-Object {$_.assignments -match $Group.id}
    Write-host "Number of Apps found: $($AllAssignedApps.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllAssignedApps) { Write-host $Config.displayName -ForegroundColor Yellow }
 
 
    # Device Compliance
    $AllDeviceCompliance = Get-IntuneDeviceCompliancePolicy -Select id, displayName, lastModifiedDateTime, assignments -Expand assignments | Where-Object {$_.assignments -match $Group.id}
    Write-host "Number of Device Compliance policies found: $($AllDeviceCompliance.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllDeviceCompliance) { Write-host $Config.displayName -ForegroundColor Yellow }
 
 
    # Device Configuration
    $AllDeviceConfig = Get-IntuneDeviceConfigurationPolicy -Select id, displayName, lastModifiedDateTime, assignments -Expand assignments | Where-Object {$_.assignments -match $Group.id}
    Write-host "Number of Device Configurations found: $($AllDeviceConfig.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllDeviceConfig) { Write-host $Config.displayName -ForegroundColor Yellow }
 
    # Device Configuration Powershell Scripts 
    $Resource = "deviceManagement/deviceManagementScripts"
    $graphApiVersion = "Beta"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$expand=groupAssignments"
    $DMS = Invoke-MSGraphRequest -HttpMethod GET -Url $uri
    $AllDeviceConfigScripts = $DMS.value | Where-Object {$_.assignments -match $Group.id}
    Write-host "Number of Device Configurations Powershell Scripts found: $($AllDeviceConfigScripts.DisplayName.Count)" -ForegroundColor cyan
 
    Foreach ($Config in $AllDeviceConfigScripts) { Write-host $Config.displayName -ForegroundColor Yellow }
 
}