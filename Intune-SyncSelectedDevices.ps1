

# Sync selected Devices
# thanks to 


Connect-MSGraph


#$DevicesToSync = Get-IntuneManagedDevice | Get-MSGraphAllPages | where-object {$_.managementAgent -eq 'mdm'}


#$IPs = (Get-Content IP.csv)[0].split(",")
#foreach ( $IP in $IPs){    echo $IP}


$DevicesToSync = Get-IntuneManagedDevice -Filter "contains(deviceName,'MC256694')" 
#| select serialnumber, devicename, userDisplayName, userPrincipalName, id, userId, azureADDeviceId, managedDeviceOwnerType, model, manufacturer


Foreach ($Device in $DevicesToSync)
{
 
Invoke-IntuneManagedDeviceSyncDevice -managedDeviceId $Device.managedDeviceId
Write-Host "Sending Sync request to Device with Name $($Device.deviceName)" -ForegroundColor Green
 
}

