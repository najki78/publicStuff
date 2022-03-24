﻿<#
.COPYRIGHT
Copyright (c) Microsoft Corporation. All rights reserved. Licensed under the MIT license.
See LICENSE in the project root for license information.
#>

####################################################

function Get-AuthToken {

<#
.SYNOPSIS
This function is used to authenticate with the Graph API REST interface
.DESCRIPTION
The function authenticate with the Graph API Interface with the tenant name
.EXAMPLE
Get-AuthToken
Authenticates you with the Graph API interface
.NOTES
NAME: Get-AuthToken
#>

[cmdletbinding()]

param
(
    [Parameter(Mandatory=$true)]
    $User
)

$userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $User

$tenant = $userUpn.Host

Write-Host "Checking for AzureAD module..."

    $AadModule = Get-Module -Name "AzureAD" -ListAvailable

    if ($AadModule -eq $null) {

        Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
        $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable

    }

    if ($AadModule -eq $null) {
        write-host
        write-host "AzureAD Powershell module not installed..." -f Red
        write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
        write-host "Script can't continue..." -f Red
        write-host
        exit
    }

# Getting path to ActiveDirectory Assemblies
# If the module count is greater than 1 find the latest version

    if($AadModule.count -gt 1){

        $Latest_Version = ($AadModule | select version | Sort-Object)[-1]

        $aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }

            # Checking if there are multiple versions of the same module found

            if($AadModule.count -gt 1){

            $aadModule = $AadModule | select -Unique

            }

        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"

    }

    else {

        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"

    }

[System.Reflection.Assembly]::LoadFrom($adal) | Out-Null

[System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null

$clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"

$redirectUri = "urn:ietf:wg:oauth:2.0:oob"

$resourceAppIdURI = "https://graph.microsoft.com"

$authority = "https://login.microsoftonline.com/$Tenant"

    try {

    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority

    # https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
    # Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession

    $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"

    $userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")

    $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI,$clientId,$redirectUri,$platformParameters,$userId).Result

        # If the accesstoken is valid then create the authentication header

        if($authResult.AccessToken){

        # Creating header for Authorization token

        $authHeader = @{
            'Content-Type'='application/json'
            'Authorization'="Bearer " + $authResult.AccessToken
            'ExpiresOn'=$authResult.ExpiresOn
            }

        return $authHeader

        }

        else {

        Write-Host
        Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
        Write-Host
        break

        }

    }

    catch {

    write-host $_.Exception.Message -f Red
    write-host $_.Exception.ItemName -f Red
    write-host
    break

    }

}

####################################################


Function CheckTheToken() {
#region Authentication

    write-host

    # Checking if authToken exists before running authentication
    if($global:authToken){

        # Setting DateTime to Universal time to work in all timezones
        $DateTime = (Get-Date).ToUniversalTime()

        # If the authToken exists checking when it expires
        $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes

            # it was $TokenExpires -le 0
            if($TokenExpires -le 15){

            write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow
            write-host

            $global:authToken = Get-AuthToken -User $User

            }
    }

    # Authentication doesn't exist, calling Get-AuthToken function

    else {

        if($User -eq $null -or $User -eq ""){

        $User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
        Write-Host

        }

    # Getting the authorization token
    $global:authToken = Get-AuthToken -User $User

    }

}

####################################################



cls

if($User -eq $null -or $User -eq ""){

$User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
Write-Host

}

Connect-AzureAD
Connect-MSGraph



<#
$DevicesToSync = Get-IntuneManagedDevice -Filter "contains(deviceName,'XYZ123456')" #| select serialnumber, devicename, userDisplayName, userPrincipalName, id, userId, azureADDeviceId, managedDeviceOwnerType, model, manufacturer
Foreach ($Device in $DevicesToSync) { 
    Invoke-IntuneManagedDeviceSyncDevice -managedDeviceId $Device.managedDeviceId
    Write-Host "Sending Sync request to Device with Name $($Device.deviceName)" -ForegroundColor Green
}
#>

try {

    # Which AAD group do we want to check against
      $groupName = "Intune-ProactiveRemediation-ReportNetworkConnections"
 

        
    #$Groups = Get-AADGroup | Get-MSGraphAllPages
    $Group = Get-AADGroup -Filter "displayname eq '$GroupName'"
        #$Group.id = Azure ObjectId 
        #$Group.securityIdentifier = SID

    Write-host "AAD Group Name: $($Group.displayName)" -ForegroundColor Green

    $listOfDevices = Get-AzureADGroupMember -ObjectId $Group.id -All $true # -Top 5 
    # ObjectId, DeviceId (=azureADDeviceId),DisplayName

    foreach($AzureDeviceObj in $listOfDevices) {

        CheckTheToken

        try {
            $IntuneDeviceObj = Get-IntuneManagedDevice -Filter “azureADDeviceId eq '$($AzureDeviceObj.DeviceId)'”
            #azureADDeviceId, id (Intune DeviceId) 
            if($IntuneDeviceObj -ne $null) { Invoke-IntuneManagedDeviceSyncDevice -managedDeviceId $IntuneDeviceObj.id; Write-Host "Sync sent to $($AzureDeviceObj.DisplayName) - $($IntuneDeviceObj.id)" }
        } # inner 'try' block
        catch { Write-Host -Message $_ }
        
    }
    
} # main 'try' block
catch { Write-Host -Message $_ }
