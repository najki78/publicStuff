cls

if(!(Connect-MSGraph)){ Connect-MSGraph }

### $DevicesToSync = Get-IntuneManagedDevice -Filter "contains(deviceName,'XYZ123456')"  #| select serialnumber, devicename, userDisplayName, userPrincipalName, id, userId, azureADDeviceId, managedDeviceOwnerType, model, manufacturer

try {

    # Which AAD group do we want to check against
    $groupName = "Intune-Devices-EMEA-All"
 
    #$Groups = Get-AADGroup | Get-MSGraphAllPages
    $Group = Get-AADGroup -Filter "displayname eq '$GroupName'"
    #$Group.id = Azure ObjectId 
    #$Group.securityIdentifier = SID

    Write-host "AAD Group Name: $($Group.displayName)" -ForegroundColor Green
 
    $listOfDevices = Get-AzureADGroupMember -ObjectId $Group.id -All $true # -Top 5 
    # ObjectId, DeviceId (=azureADDeviceId),DisplayName

    foreach($AzureDeviceObj in $listOfDevices) {

        try {
            $IntuneDeviceObj = Get-IntuneManagedDevice -Filter “azureADDeviceId eq '$($AzureDeviceObj.DeviceId)'”
            #azureADDeviceId, id (Intune DeviceId) 
            if($IntuneDeviceObj -ne $null) { Invoke-IntuneManagedDeviceSyncDevice -managedDeviceId $IntuneDeviceObj.id; Write-Host "Sync sent to $($AzureDeviceObj.DisplayName) - $($IntuneDeviceObj.id)" }
        } # inner 'try' block
        catch { Write-Host -Message $_ }
        
    }
    
} # main 'try' block
catch { Write-Host -Message $_ }
