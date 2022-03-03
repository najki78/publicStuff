# https://smsagent.blog/2018/10/22/querying-for-devices-in-azure-ad-and-intune-with-powershell-and-microsoft-graph/


# GET DEVICES FROM INTUNE

Install-Module AzureAD

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
 
Function Get-AllIntuneDevices(){
 
[cmdletbinding()]
 
# Defining Variables
$graphApiVersion = "v1.0"
$Resource = "deviceManagement/managedDevices"
 
try {
 
    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
    
    Write-Host "Calling $uri"
    $DevicesResponse = (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get)
    $Devices = $DevicesResponse.value
    $DevicesNextLink = $DevicesResponse."@odata.nextLink"
    while ($DevicesNextLink -ne $null){
        Write-Host "Calling $DevicesNextLink"
        $DevicesResponse = (Invoke-RestMethod -Uri $DevicesNextLink -Headers $authToken -Method Get)
        $DevicesNextLink = $DevicesResponse."@odata.nextLink"
        $Devices += $DevicesResponse.value
    }
    return $Devices
        
}
 
    catch {
 
    $ex = $_.Exception
    $errorResponse = $ex.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    Write-Host "Response content:`n$responseBody" -f Red
    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    write-host
    break
 
    }
 
}

Function Get-AzureADDevices(){
 
[cmdletbinding()]
 
$graphApiVersion = "beta"
$Resource = "devices"
$QueryParams = ""
 
    try {
 
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)$QueryParams"
        Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get
    }
 
    catch {
 
    $ex = $_.Exception
    $errorResponse = $ex.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    Write-Host "Response content:`n$responseBody" -f Red
    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    write-host
    break
 
    }
 
}

#region Authentication

write-host

# Checking if authToken exists before running authentication
if($global:authToken){

    # Setting DateTime to Universal time to work in all timezones
    $DateTime = (Get-Date).ToUniversalTime()

    # If the authToken exists checking when it expires
    $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes

        if($TokenExpires -le 0){

        write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow
        write-host

            # Defining User Principal Name if not present

            if($User -eq $null -or $User -eq ""){

            $User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
            Write-Host

            }

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

#endregion


<#
Write-Host "Running Get-AzureADDevices" -ForegroundColor Yellow

# Return the data
$ADDeviceResponse = Get-AzureADDevices
$ADDevices = $ADDeviceResponse.Value
$NextLink = $ADDeviceResponse.'@odata.nextLink'


# Need to loop the requests because only 100 results are returned each time
While ($NextLink -ne $null)
{
    $ADDeviceResponse = Invoke-RestMethod -Uri $NextLink -Headers $authToken -Method Get
    $NextLink = $ADDeviceResponse.'@odata.nextLink'
    $ADDevices += $ADDeviceResponse.Value
    Write-Host "Already processed: $($ADDevices.Count)" -ForegroundColor Green
}



Write-Host "Found $($ADDevices.Count) devices in Azure AD" -ForegroundColor Yellow

$ADDevices.operatingSystem | group -NoElement
 
$DeviceTypes = $ADDevices.operatingSystem | group -NoElement | Select -ExpandProperty Name
$AzureADDevices = @{}
Foreach ($DeviceType in $DeviceTypes)
{
    $AzureADDevices.$DeviceType = $ADDevices | where {$_.operatingSystem -eq "$DeviceType"} | Sort displayName
}
 
Write-host "Devices have been saved to a variable. Enter '`$AzureADDevices' to view."
#>

    #Connect-MSGraph
    #$MDMDevices = Get-IntuneManagedDevice | Get-MSGraphAllPages
    #$MDMDevices.Value

$MDMDevices = Get-AllIntuneDevices 
# | Select -First 100
Write-Host "Found $($MDMDevices.Count) devices in Intune" -ForegroundColor Yellow
#$MDMDevices 

$MDMDevices.operatingSystem | group -NoElement
 
$IntuneDeviceTypes

$IntuneDeviceTypes = $MDMDevices.operatingSystem | group -NoElement | Select -ExpandProperty Name
$IntuneDevices = @{}
Foreach ($IntuneDeviceType in $IntuneDeviceTypes)
{
    $IntuneDevices.$IntuneDeviceType = $MDMDevices | where {$_.operatingSystem -eq "$IntuneDeviceType"} | Sort displayName
}
 
Write-host "Devices have been saved to a variable. Enter '`$IntuneDevices' to view."

# id = Intune Device ID
$IntuneDevices.Windows | Select id,deviceName | Sort deviceName | ft