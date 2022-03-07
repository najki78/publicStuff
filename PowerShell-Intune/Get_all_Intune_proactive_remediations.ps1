
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

$timestamp = (Get-Date -Format "yyyy-MM-dd___HH_mm_ss")


# Connect and change schema 
if(!(Connect-MSGraph)){ 
    Connect-MSGraph -ForceInteractive
    Update-MSGraphEnvironment -SchemaVersion beta
    Connect-MSGraph
}
 

 

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
    
    $AllProRem = $ProRem.value # | Where-Object {$_.assignments -match "d9fd*"}
    #$AllProRem = $ProRem.value | Where-Object {$_.id -match $Group.id}

    Write-host "Number of Proactive Remediations found: $($AllProRem.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($line in $AllProRem) { 
        Write-host $line -ForegroundColor Yellow 
    
        #
        $myObject = [pscustomobject]@{'displayName' = $line.displayName; 'id' = $line.id; 'publisher' = $line.publisher; 'description' = $line.description.Trim("`t").Trim("`r").Trim("`n") }
        $myObject  | Export-CSV -Path c:\temp\$($timestamp)_proactive-remediation.txt -NoTypeInformation -Append
                
    } # $Config.displayName 


# id; publisher; version; displayName; description; detectionScriptContent=; remediationScriptContent=; createdDateTime=; lastModifiedDateTime=; runAsAccount=; enforceSignatureCheck=; runAs32Bit; roleScopeTagIds=System.Object[]; isGlobalScript=; highestAvailableVersion=; detectionScriptParameters=System.Object[]; remediationScriptParameters=System.Object[]; assignments@odata.context=https://graph.microsoft.com/beta/$metadata#deviceManagement/deviceHealthScripts('f7976d99-3e1f-4bcc-b1d4-2f1f99ae1d5a')/assignments; assignments=System.Object[]}