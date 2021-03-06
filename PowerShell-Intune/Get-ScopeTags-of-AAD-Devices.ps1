
# ***************************************************************************************************
# ***************************************************************************************************
#
#  Author       : Ľuboš Nikolíni
#  Credit       : Microsoft and Cary GARVIN (Script functions)
#  Contact      : lubos(at)nikolini.eu
#  LinkedIn     : https://sk.linkedin.com/in/nikolini
#  GitHub       : https://github.com/najki78/publicStuff/
#
#
#  Script Name  : Get-ScopeTags-of-AAD-Devices.ps1
#  Version      : 1.0
#  Release date : 2021-12-28
#
#                 
#  Purpose      : Get scope tags for all Intune managed Windows devices 
#
#                 This Id is used for device identification in the output (ListOfDevicesWithScopeTags.txt):
#                 Azure AD Device ID (in Intune console) = Device ID (in Azure console)
#
#  History      : The script is based on https://github.com/carygarvin/Assign-DeviceScopeTags.ps1/blob/master/Assign-DeviceScopeTags.ps1 ---> THANK YOU!
#


####################################################################################################
#                                       Script functions                                           #
####################################################################################################



Function Get-AuthToken
	{
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

    If ($AadModule -eq $null)
		{
		Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
		$AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
		}

	If ($AadModule -eq $null)
		{
		write-host
		write-host "AzureAD Powershell module not installed..." -f Red
		write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
		write-host "Script can't continue..." -f Red
		write-host
		exit
		}

	# Getting path to ActiveDirectory Assemblies
	# If the module count is greater than 1 find the latest version

    If ($AadModule.count -gt 1)
		{
		$Latest_Version = ($AadModule | select version | Sort-Object)[-1]
		$aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }

		# Checking if there are multiple versions of the same module found
		If ($AadModule.count -gt 1)	{$aadModule = $AadModule | select -Unique}

		$adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
		$adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
		}
	Else
		{
		$adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
		$adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
		}

	[System.Reflection.Assembly]::LoadFrom($adal) | Out-Null

	[System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null

	$clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"

	$redirectUri = "urn:ietf:wg:oauth:2.0:oob"

	$resourceAppIdURI = "https://graph.microsoft.com"

	$authority = "https://login.microsoftonline.com/$Tenant"

    try
		{
		$authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority

		# https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
		# Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession
		$platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"

		$userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")

		$authResult = $authContext.AcquireTokenAsync($resourceAppIdURI,$clientId,$redirectUri,$platformParameters,$userId).Result

		# If the accesstoken is valid then create the authentication header
		If ($authResult.AccessToken)
			{
			# Creating header for Authorization token
			$authHeader = @{
				'Content-Type'='application/json'
				'Authorization'="Bearer " + $authResult.AccessToken
				'ExpiresOn'=$authResult.ExpiresOn
				}
			return $authHeader
			}
        Else
			{
			Write-Host
			Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
			Write-Host
			break
			}
		}
	catch
		{
		write-host $_.Exception.Message -f Red
		write-host $_.Exception.ItemName -f Red
		write-host
		break
		}
	}


# Lubos - currently filters only "Windows" devices
Function Get-ManagedDevices()
	{
	<#
	.SYNOPSIS
	This function is used to get Intune Managed Devices from the Graph API REST interface
	.DESCRIPTION
	The function connects to the Graph API Interface and gets any Intune Managed Device
	.EXAMPLE
	Get-ManagedDevices
	Returns all managed devices but excludes EAS devices registered within the Intune Service
	.EXAMPLE
	Get-ManagedDevices -IncludeEAS
	Returns all managed devices including EAS devices registered within the Intune Service
	.NOTES
	NAME: Get-ManagedDevices
	#>

	[cmdletbinding()]

	param
		(
		[switch]$IncludeEAS,
		[switch]$ExcludeMDM,
		$DeviceName,
		$id
		)

	# Defining Variables
	$graphApiVersion = "beta"
	$Resource = "deviceManagement/managedDevices"

	try
		{
		$Count_Params = 0
		If ($IncludeEAS.IsPresent) {$Count_Params++}
		If ($ExcludeMDM.IsPresent) {$Count_Params++}
		If ($DeviceName.IsPresent) {$Count_Params++}
		If ($id.IsPresent) {$Count_Params++}
        
        If ($Count_Params -gt 1)
			{
			write-warning "Multiple parameters set, specify a single parameter -IncludeEAS, -ExcludeMDM, -deviceName, -id or no parameter against the function"
			Write-Host
			break
			}
		ElseIf ($IncludeEAS)
			{
			$uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
			(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
			}
		ElseIf ($ExcludeMDM)
			{
			$uri = "https://graph.microsoft.com/$graphApiVersion/$Resource`?`$filter=managementAgent eq 'eas'"
			(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
			}
		ElseIf ($id)
			{
			$uri = "https://graph.microsoft.com/$graphApiVersion/$Resource('$id')"
			(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get)
			}
		ElseIf ($DeviceName)
			{
			$uri = "https://graph.microsoft.com/$graphApiVersion/$Resource`?`$filter=deviceName eq '$DeviceName'"
			(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
			}
		Else
			{

            # https://docs.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list?view=graph-rest-1.0

			#$uri = "https://graph.microsoft.com/$graphApiVersion/$Resource`?`$filter=managementAgent eq 'mdm' and managementAgent eq 'easmdm'"
            $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource`?`$filter=operatingSystem eq 'Windows'"

			#Write-Warning "EAS Devices are excluded by default, please use -IncludeEAS if you want to include those devices"
			Write-Host
			#(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
			# (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value | out-file mobiledevices.txt -append
   
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
		}
    catch
		{
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



Function Get-RBACScopeTag()
	{
	<#
	.SYNOPSIS
	This function is used to get scope tags using the Graph API REST interface
	.DESCRIPTION
	The function connects to the Graph API Interface and gets scope tags
	.EXAMPLE
	Get-RBACScopeTag -DisplayName "Test"
	Gets a scope tag with display Name 'Test'
	.NOTES
	NAME: Get-RBACScopeTag
	#>

	[cmdletbinding()]
	
	param
		(
		[Parameter(Mandatory=$false)]
		$DisplayName
		)

	# Defining Variables
	$graphApiVersion = "beta"
	$Resource = "deviceManagement/roleScopeTags"

    try
		{
		If ($DisplayName)
			{
            $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource`?`$filter=displayName eq '$DisplayName'"
            $Result = (Invoke-RestMethod -Uri $uri -Method Get -Headers $authToken).Value
			}
		Else
			{
            $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
            $Result = (Invoke-RestMethod -Uri $uri -Method Get -Headers $authToken).Value
			}
		return $Result
		}
    catch
		{
		$ex = $_.Exception
		$errorResponse = $ex.Response.GetResponseStream()
		$reader = New-Object System.IO.StreamReader($errorResponse)
		$reader.BaseStream.Position = 0
		$reader.DiscardBufferedData()
		$responseBody = $reader.ReadToEnd();
		Write-Host "Response content:`n$responseBody" -f Red
		Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
		write-host
		throw
		}
	}



Function Get-ManagedDeviceUser()
	{
	<#
	.SYNOPSIS
	This function is used to get a Managed Device username from the Graph API REST interface
	.DESCRIPTION
	The function connects to the Graph API Interface and gets a managed device users registered with Intune MDM
	.EXAMPLE
	Get-ManagedDeviceUser -DeviceID $DeviceID
	Returns a managed device user registered in Intune
	.NOTES
	NAME: Get-ManagedDeviceUser
	#>

	[cmdletbinding()]

	param
		(
		[Parameter(Mandatory=$true,HelpMessage="DeviceID (guid) for the device on must be specified:")]
		$DeviceID
		)

	# Defining Variables
	$graphApiVersion = "beta"
	$Resource = "deviceManagement/manageddevices('$DeviceID')?`$select=userId"

    try
		{
		$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
		Write-Verbose $uri
		(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).userId
		}
	catch
		{
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



Function Get-AADUser()
	{
	<#
	.SYNOPSIS
	This function is used to get AAD Users from the Graph API REST interface
	.DESCRIPTION
	The function connects to the Graph API Interface and gets any users registered with AAD
	.EXAMPLE
	Get-AADUser
	Returns all users registered with Azure AD
	.EXAMPLE
	Get-AADUser -userPrincipleName user@domain.com
	Returns specific user by UserPrincipalName registered with Azure AD
	.NOTES
	NAME: Get-AADUser
	#>

	[cmdletbinding()]

	param
		(
		$userPrincipalName,
		$Property
		)

	# Defining Variables
	$graphApiVersion = "v1.0"
	$User_resource = "users"

	try
		{
        If ($userPrincipalName -eq "" -or $userPrincipalName -eq $null)
			{
			$uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)"
			(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
			}
		Else
			{
            If ($Property -eq "" -or $Property -eq $null)
				{
				$uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)/$userPrincipalName"
				Write-Verbose $uri
				Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get
				}
			Else
				{
				$uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)/$userPrincipalName/$Property"
				Write-Verbose $uri
				(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
				}
			}
		}
    catch
		{
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



Function Update-ManagedDevices()
	{
	<#
	.SYNOPSIS
	This function is used to add a device compliance policy using the Graph API REST interface
	.DESCRIPTION
	The function connects to the Graph API Interface and adds a device compliance policy
	.EXAMPLE
	Update-ManagedDevices -JSON $JSON
	Adds an Android device compliance policy in Intune
	.NOTES
	NAME: Update-ManagedDevices
	#>

	[cmdletbinding()]

	param
		(
		$id,
		$ScopeTags
		)

	$graphApiVersion = "beta"
	$Resource = "deviceManagement/managedDevices('$id')"

    try
    	{
		If ($ScopeTags -eq "" -or $ScopeTags -eq $null)
			{
$JSON = @"

{
  "roleScopeTagIds": []
}

"@
			}
        Else
			{
			$object = New-Object -TypeName PSObject
			$object | Add-Member -MemberType NoteProperty -Name 'roleScopeTagIds' -Value @($ScopeTags)
			$JSON = $object | ConvertTo-Json
			}

		$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
		Invoke-RestMethod -Uri $uri -Headers $authToken -Method Patch -Body $JSON -ContentType "application/json"
		Start-Sleep -Milliseconds 100
		}
    catch
		{
		Write-Host
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




# (Lubos) if it expires in less than 15 minutes, renew it...
Function Check-AuthTokenValidity {

# Checking if authToken exists before running authentication
If ($global:authToken)
	{
    # Setting DateTime to Universal time to work in all timezones
    $DateTime = (Get-Date).ToUniversalTime()

    # If the authToken exists checking when it expires
    $TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes

    # expiration - value in minutes
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
#                                          Script Main                                             #
####################################################################################################

Install-Module AzureAD

Check-AuthTokenValidity

# Getting list of Intune Scope Tages and their associated IDs
Write-Host
$ScopeTags = (Get-RBACScopeTag).displayName | sort
$ScopeTags2IDHT = @{}
$ScopeTags | ForEach {$ScopeTag = $_ ; $ScopeTags2IDHT.Add($_,(Get-RBACScopeTag | ? { $_.displayName -eq $ScopeTag }).id)}
write-host "Intune Scope Tags and corresponding IDs" -foregroundcolor "yellow"
$ScopeTags2IDHT
write-host


$outfile = "C:\temp\ListOfDevicesWithScopeTags.txt"
$newcsv = {} | Select "id","azureADDeviceId","azureActiveDirectoryDeviceId","deviceName","scopeTags" | Export-Csv $outfile -NoTypeInformation
$csvfile = Import-Csv $outfile


# Enumerate a single device based on a deviceName
#$ManagedDevices = Get-ManagedDevices -deviceName "...."

# Enumerate through all InTune Windows devices 
$ManagedDevices = Get-ManagedDevices

# https://stackoverflow.com/questions/17927525/accessing-values-of-object-properties-in-powershell
#$ManagedDevices.hardwareInformation.psobject.properties["batteryHealthPercentage"].Value
#$ManagedDevices.hardwareInformation.psobject.properties["batteryHealthPercentage"] | % {$_.Value}

If($ManagedDevices) {
	$NumberOfManagedDevices = $ManagedDevices.count
	$NumberOfNewManagedDevices = 0
    Foreach ($Device in $ManagedDevices)
		{

        Check-AuthTokenValidity

        $DeviceID = $Device.id # Intune Device ID (not visible in Azure, only Intune)
        
		$DeviceName = $Device.deviceName
		$Enroller = $Device.userPrincipalName

		write-host "Managed Device '$DeviceName/$DeviceID' found..." -ForegroundColor Yellow

        $csvfile.id = $DeviceID
        $csvfile.azureADDeviceId = $Device.azureADDeviceId # Azure AD Device ID (in Intune console) = Device ID (in Azure console)
        $csvfile.azureActiveDirectoryDeviceId = $Device.azureActiveDirectoryDeviceId 
        $csvfile.deviceName = $DeviceName

		$DeviceScopeTags = (Get-ManagedDevices -id $DeviceID).roleScopeTagIds
		If (($Device.deviceRegistrationState -eq "registered") -and ($DeviceScopeTags.count -eq 0))
			{
			$NumberOfNewManagedDevices++
			#write-host "Device $DeviceName/$DeviceID enrolled by '$Enroller' has no Scope Tag." -foregroundcolor "green"

            $csvfile.scopeTags = "(empty)"

			$UserId = Get-ManagedDeviceUser -DeviceID $DeviceID
			$User = Get-AADUser $userId

			#Write-Host "`tDevice Registered User:" $User.displayName
			#Write-Host "`tUser Principle Name   :" $User.userPrincipalName
			
			#$UserSMTPDomain = $User.userPrincipalName.SubString($User.userPrincipalName.IndexOf("@"))
		
            }
                        
		Else {
			$STList = $DeviceScopeTags | % {$CurrentSCID = $_; $ScopeTags2IDHT.Keys | ? {$ScopeTags2IDHT[$_] -eq $CurrentSCID}}
			
            If ($STList -is [array]) {
                #write-host "`tDevice '$DeviceName/$DeviceID' enrolled by '$Enroller' already has Scope Tags '$($STList -join "', '")'."

                $csvfile.scopeTags = $($STList -join ",")

            }
			Else {
                #write-host "`tDevice '$DeviceName/$DeviceID' enrolled by '$Enroller' already has Scope Tag '$STList'."

                $csvfile.scopeTags = $STList

            }
		}
		#Write-Host

        $csvfile | Export-CSV $outfile –Append
        
		}
#	If ($NumberOfNewManagedDevices -eq 0) {Write-Host "`r`nNo newly enrolled Managed Devices found amongst the $NumberOfManagedDevices present mobile devices in tenant...`r`n" -ForegroundColor "cyan"}
#	Else {Write-Host "`r`n$NumberOfNewManagedDevices newly enrolled Managed Devices have been assigned corresponding Scope Tags...`r`n" -ForegroundColor "cyan"}
	}
Else {Write-Host "`r`nNo Managed Devices found in tenant...`r`n" -ForegroundColor cyan}
