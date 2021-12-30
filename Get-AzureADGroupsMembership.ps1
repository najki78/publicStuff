
# Credit: based on https://stackoverflow.com/questions/57251857/azure-active-directory-how-to-check-device-membership
# https://stackoverflow.com/users/10213635/gerrit-geeraerts
function Get-AzureADDeviceMembership{
    [CmdletBinding()]
    Param(
        [string]$ComputerDisplayname,
        [switch]$UseCache
    )
    if(-not $Global:AzureAdGroupsWithMembers -or -not $UseCache){
        write-host "refreshing cache"

        $Global:AzureAdGroupsWithMembers = Get-AzureADGroup -All 1 | % {
            $members = Get-AzureADGroupMember -ObjectId $_.ObjectId
            $_ | Add-Member -MemberType NoteProperty -Name Members -Value $members
            $_
        }
        
    }
    $Global:AzureAdGroupsWithMembers | % {
        if($ComputerDisplayname -in ($_.Members | select -ExpandProperty DisplayName)){
            $_
        }
    } | select -Unique
}


# using Get-AzureADGroup - older approach, different set of columns than Get-AzureADMSGroup
function Save-AllAADGroups {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)][string]$filename
    )
    
    # change to "-All $true" to see all groups
    $Global:AzureAdGroups = Get-AzureADGroup -All $true 
    $Global:AzureAdGroups | Export-CSV $filename -NoTypeInformation
    
}


# using Get-AzureADMSGroup - newer approach, different set of columns than Get-AzureADGroup
function Save-AllAADMSGroups {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)][string]$filename,
        [switch]$UseCache
    )
    
    if(-not $Global:AzureAdMSGroups -or -not $UseCache){

        # change to "-All $true" to see all groups
        $Global:AzureAdMSGroups = Get-AzureADMSGroup -All $true
        $Global:AzureAdMSGroups | Export-CSV $filename -NoTypeInformation
    
        # "GroupTypes[0]" - check for "Unified" = O365
        # "GroupTypes[0]" - check for "DynamicMembership" = dynamic group

        # "SecurityEnabled"
        # TRUE - Security
        # FALSE - Distribution
    }
}

# using Get-AzureADGroupMember
function Save-AzureADGroupMembership {
    [CmdletBinding()]
        Param(
            [Parameter(Mandatory=$true)][string]$Id,
            [Parameter(Mandatory=$true)][string]$filename
        )

    Get-AzureADGroupMember -ObjectId $Id -All $true | Export-CSV $filename -NoTypeInformation

}

# go through all AAD groups 
# we are only interested in Security groups with Assigned membership (not Dynamic) for device management purposes
function Save-AllAzureADGroupsMembership {

    Save-AllAADMSGroups -filename $folder"ListOfAADMSGroups.txt"
    
    $groupCounter = 0
    
    <#
    If($AzureAdMSGroups) {

        Foreach ($group in $AzureAdMSGroups) {
                    
            if (($group.SecurityEnabled -eq "TRUE") -and ($group.GroupTypes[0] -ne "Unified") -and ($group.GroupTypes[0] -ne "DynamicMembership")) {
                Write-Host $group.DisplayName 
                Save-AzureADGroupMembership -Id $group.Id -filename ("{0}{1}.txt" -f $folder,$group.Id)
                $groupCounter += 1
            } 
        }
    }
    #>
    Write-Host "Number of groups processed: $groupCounter" -ForegroundColor Green 

}

#Connect-AzureAD    

# Setting DateTime to Universal time to work in all timezones
$DateTime = (Get-Date).ToUniversalTime()


$folder = "C:\temp\AADGroups\"
mkdir $folder -ErrorAction SilentlyContinue

# the function below can take up to several hours to run
# the function lists all AAD groups and saves the group membership into the files (filename: group Id)
# Save-AllAzureADGroupsMembership


$hashDeviceIds = @{}
# ObjectType = Device
# DeviceId
# DisplayName

Import-Csv $folder"0754e177-b20d-4919-b03b-aa814c3f8437.txt" | ForEach-Object {
    #Write-Host "$($_.ObjectType) ...  $($_.DeviceId) ... $($_.DisplayName)"
 
    # if such DeviceId is not yet listed, create an entry (empty array to store ObjectIds of groups)
    if(-not $hashDeviceIds["$($_.DeviceId)"]) { $hashDeviceIds["$($_.DeviceId)"] = @() } 
    
    ($hashDeviceIds["$($_.DeviceId)"].count) -1

    #$hashDeviceIds["$($_.DeviceId)"][($hashDeviceIds["$($_.DeviceId)"].count) -1] = $($_.DisplayName)
    $hashDeviceIds["$($_.DeviceId)"] = ,$($_.DisplayName)
    
    ($hashDeviceIds["$($_.DeviceId)"].count) -1

}

$hashDeviceIds