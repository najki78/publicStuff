# ***************************************************************************************************
# ***************************************************************************************************
#
#  Author       : Ľuboš Nikolíni
#  Credit       : Microsoft (Script functions) and 
#                 Trevor Jones - https://smsagent.blog/2018/10/22/querying-for-devices-in-azure-ad-and-intune-with-powershell-and-microsoft-graph/
#  Contact      : lubos(at)nikolini.eu
#  LinkedIn     : https://sk.linkedin.com/in/nikolini
#  GitHub       : https://github.com/najki78/publicStuff/
#
#
#  Script Name  : Get-AzureADDevicesGroupsMembership.ps1
#  Version      : 1.0
#  Release date : 2021-12-30
#
#                 
#  Purpose      : Get AAD groups membership of AzureAD devices (aka Get-AzureADDeviceMembership)
#                 (Until we have have an equivalent of Get-AzureADUserMembership that would cover Device objects )
#
#  instructions : On a first run, uncomment "Save-AllAzureADGroupsMembership" line (the function records the group membership of all Static - non Dynamic - AAD Security groups into files, which are processed later)
#
#                 If needed, it is simple to extend the scope of the script to save group membership to ALL AAD groups.
#
#                 This Id is used for device identification in the output (ListDevicesWithGroupMembership.txt):
#                 Azure AD Device ID (in Intune console) = Device ID (in Azure console)
#
#  Alternative approach: https://www.michev.info/Blog/Post/3096/reporting-on-group-membership-for-azure-ad-devices


####################################################################################################
#                                       Script functions                                           #
####################################################################################################

function Get-AzureADDeviceMembership{
# Credit: https://stackoverflow.com/questions/57251857/azure-active-directory-how-to-check-device-membership
# https://stackoverflow.com/users/10213635/gerrit-geeraerts
# I am not using this approach because it takes many hours to process EVERY time the function is run

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


function Save-AllIntuneDevices {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)][string]$filename
    )

    $MDMDevices = Get-AllIntuneDevices 
    Write-Host "Found $($MDMDevices.Count) devices in Intune" -ForegroundColor Yellow
    $MDMDevices | Select azureADDeviceId,serialNumber,id,deviceName,operatingSystem,osVersion,azureADRegistered,model,manufacturer,managementAgent,userDisplayName,emailAddress  

}



# using Get-AzureADGroup - older approach, different set of columns than Get-AzureADMSGroup
# I am not using this function anymore as it does not provide enough details in the output (e.g GroupTypes)
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
    
    If($AzureAdMSGroups) {

        Foreach ($group in $AzureAdMSGroups) {

            # if you want to save the group membership of all groups, remove the following IF
            if (($group.SecurityEnabled -eq "TRUE") -and ($group.GroupTypes[0] -ne "Unified") -and ($group.GroupTypes[0] -ne "DynamicMembership")) {
                Write-Host $group.DisplayName 
                Save-AzureADGroupMembership -Id $group.Id -filename ("{0}{1}.txt" -f $folder,$group.Id)
                $groupCounter += 1
            } 
        }
    }
    
    Write-Host "Number of groups processed: $groupCounter" -ForegroundColor Green 

}


# (Lubos) if it expires in less than 15 minutes, renew it...
Function Check-AuthTokenValidity {

# Checking if authToken exists before running authentication
If ($global:authToken)
	{
    # Setting DateTime to Universal time to work in all timezones
    $DateTime = (Get-Date).ToUniversalTime()

    # If the authToken exists checking when it expires
    $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes

    # expiration - value in minutes (change 15 min to anything under 60 min, in case you need the validity to be more, e.g. you have a long running script)
    If ($TokenExpires -le 15)
		{
		write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow
		write-host

		# Defining User Principal Name if not present
		If ($User -eq $null -or $User -eq "")
			{
			$User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
			Write-Host
			}
		$global:authToken = Get-AuthToken -User $User
		}
	}

# Authentication doesn't exist, calling Get-AuthToken function
Else
	{
	If ($User -eq $null -or $User -eq "")
		{
		$User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
		Write-Host
		}
	# Getting the authorization token
	$global:authToken = Get-AuthToken -User $User
	}

}  

####################################################################################################
#                                          Script Functions from Trevor Jones                      #
####################################################################################################

# GET DEVICES FROM INTUNE

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


####################################################################################################
#                                          Script Main                                             #
####################################################################################################

#Install-Module AzureAD
#Check-AuthTokenValidity


$folder = "C:\temp\AADGroups\"
mkdir $folder -ErrorAction SilentlyContinue

# the function below can take up to several hours to run
# the function lists all AAD groups and saves the group membership into the files (filename: group Id)



# IMPORTANT: Uncomment first time you run this script, let it run for couple of hours to collect the data and then comment it back 
# (only uncomment when you need to refresh the files containing device AAD membership)


# Save-AllAzureADGroupsMembership

        # I need to finish this part - extracting device information
        # Save-AllIntuneDevices -filename $folder"ListAllIntuneDevices.txt"



# Processing all files (groups) found in ListOfAADMSGroups.txt and saving information into hashtable (where key = DeviceId and value = array of group names the device is member of)

$hashDeviceIds = @{}
# ObjectType = Device
# DeviceId
# DisplayName

$filesToProcess = Import-Csv $folder"ListOfAADMSGroups.txt"

foreach ($f in $filesToProcess){
    # just checking if Id is provided in a particular line
    if($f.Id) {
        $filenameWithPath = ("{0}{1}.txt" -f $folder,$f.Id)
        # checking if such file even exists
        if(Test-Path $filenameWithPath) {
            Write-Host "Processing" $filenameWithPath
            Import-Csv $filenameWithPath | ForEach-Object {
                # check if DeviceId is even present in the file (it might contain only User objects for instance)
                if($($_.DeviceId)) {
                    # if such DeviceId is not yet listed, create an entry (empty array to store ObjectIds of groups)
                    if(-not $hashDeviceIds["$($_.DeviceId)"]) { $hashDeviceIds["$($_.DeviceId)"] = @() } 
                    # adding a name of a group to the array
                    $hashDeviceIds["$($_.DeviceId)"] += $f.DisplayName
                }
            }
        }
    }
}




# Exporting hashtable into ListDevicesWithGroupMembership.txt
# Add header: "DeviceId,ListOfSecurityNonDynamicAADGroups"

"DeviceId,ListOfSecurityNonDynamicAADGroups" | Out-File ("{0}ListDevicesWithGroupMembership.txt" -f $folder)
#export to file
foreach ($record in $hashDeviceIds.Keys) {
    $record  + "," + ($hashDeviceIds["$record"].SyncRoot -join ";") | Out-File -Append ("{0}ListDevicesWithGroupMembership.txt" -f $folder)
} 