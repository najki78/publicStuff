# Check for duplicate Windows PC names in Intune, generate new names for duplicates, and verify the availability of the new names across Intune and Entra ID (when running on hybrid worker, also DNS)

##############################
## Parameters
##############################

#### this must be the first uncommented command in the script
[CmdletBinding()]
Param(
)

##############################
## Variables
##############################

$version = "2024.09.19.01"
$OutputEncoding = [System.Text.Encoding]::UTF8
$VerbosePreference = 'SilentlyContinue'  
$InformationPreference = 'Continue'
$ErrorActionPreference = "Stop" 
$WarningActionPreference = 'Continue'
$DebugPreference = 'SilentlyContinue' 

$stopwatch = [system.diagnostics.stopwatch]::startNew()
$graphApiVersion = "beta"

##############################
## Functions
##############################

Function Get-MSGraphAuthToken {
    [cmdletbinding()]
    Param(
        [ValidateNotNullOrEmpty()][parameter(Mandatory = $true)][pscredential]$Credential,
        [ValidateNotNullOrEmpty()][parameter(Mandatory = $true)][string]$tenantID
    )
    
    #Get token
    $AuthUri = "https://login.microsoftonline.com/$TenantID/oauth2/token"
    $Resource = 'graph.microsoft.com'
    $AuthBody = "grant_type=client_credentials&client_id=$($credential.UserName)&client_secret=$($credential.GetNetworkCredential().Password)&resource=https%3A%2F%2F$Resource%2F"

    $Response = Invoke-RestMethod -Method Post -Uri $AuthUri -Body $AuthBody 
    If ($Response.access_token) {
        return $Response 
    }
    Else {
        Throw "Authentication failed"
    }
}

# very ugly function (uses global variables which is bad practice) to check if access token is about to expire and if it does, renews it
function refreshAccessTokenIfNeeded {

    # Check if the access token is valid for at least 10 minutes
    $ExpirationThreshold = 10 # minutes
    $ExpirationTime =  (Get-Date -Date "1970-01-01 00:00:00Z").addseconds($([int64] $global:Token.expires_on) + $([int64] $global:Token.expires_in) ) 
    $TimeDifference = New-TimeSpan -Start (Get-Date) -End $ExpirationTime

    if ($TimeDifference.TotalMinutes -lt $ExpirationThreshold) {
    
        Write-Progress "[Graph API] Token expires in $($TimeDifference.TotalMinutes) minutes. Renewing access token."

        $global:Token = Get-MSGraphAuthToken -credential $global:Credential -TenantID $global:TenantID
        $global:loginMgGraph = Connect-MgGraph -AccessToken (ConvertTo-SecureString $global:Token.access_token -AsPlainText -Force)
    
    }

}

Function Invoke-MSGraphQuery {
    [CmdletBinding(DefaultParametersetname = "Default")]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Default')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Refresh')]
        [string]$URI,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Refresh')]
        [string]$Body,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Refresh')]
        [string]$token=$global:Token.access_token,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Refresh')]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$method = "GET",
    
        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Refresh')]
        [switch]$recursive,
    
        [Parameter(Mandatory = $true, ParameterSetName = 'Refresh')]
        [switch]$tokenrefresh,
    
        [Parameter(Mandatory = $true, ParameterSetName = 'Refresh')]
        [pscredential]$credential,
    
        [Parameter(Mandatory = $true, ParameterSetName = 'Refresh')]
        [string]$tenantID,

        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Refresh')]
        [switch]$ConsistencyLevelHeader

    )

    refreshAccessTokenIfNeeded
    $token = $global:Token.access_token

    If ($ConsistencyLevelHeader) {
        $authHeader = @{
            'Accept'        = 'application/json'
            'Content-Type'  = 'application/json'
            'Authorization' = "Bearer $Token"
            'ConsistencyLevel' = 'eventual'
        } 
    } else {
        $authHeader = @{
            'Accept'        = 'application/json'
            'Content-Type'  = 'application/json'
            'Authorization' = "Bearer $Token"
        } 
    }
    
    [array]$returnvalue = $()
    Try {

        If ($body) {
            $Response = Invoke-RestMethod -Uri $URI -Headers $authHeader -Body $Body -Method $method -ErrorAction Stop -ContentType "application/json"
        }
        Else {
            $Response = Invoke-RestMethod -Uri $URI -Headers $authHeader -Method $method -ErrorAction Stop
        }
    }
    Catch {

        try {
            $exception = $_.Exception
                Write-Warning "GetType.FullName: $( $exception.GetType().FullName)"
                Write-Warning "Message: $( $exception.Message )" 
                Write-Warning "StackTrace: $( $exception.StackTrace )" 
                Write-Warning "InnerException: $( $exception.InnerException )"
        } catch {}

        Throw $_
        
    }

    $returnvalue += $Response
    If (-not $recursive -and $Response.'@odata.nextLink') {
        Write-Verbose "Query contains more data, use recursive to get all!"
        Start-Sleep 1
    }
    ElseIf ($recursive -and $Response.'@odata.nextLink') {
        If ($PSCmdlet.ParameterSetName -eq 'default') {
            If ($body) {
                $returnvalue += Invoke-MSGraphQuery -URI $Response.'@odata.nextLink' -token $token -body $body -method $method -recursive -ErrorAction SilentlyContinue
            }
            Else {
                $returnvalue += Invoke-MSGraphQuery -URI $Response.'@odata.nextLink' -token $token -method $method -recursive -ErrorAction SilentlyContinue
            }
        }
        Else {
            If ($body) {
                $returnvalue += Invoke-MSGraphQuery -URI $Response.'@odata.nextLink' -token $token -body $body -method $method -recursive -tokenrefresh -credential $credential -tenantID $TenantID -ErrorAction SilentlyContinue
            }
            Else {
                $returnvalue += Invoke-MSGraphQuery -URI $Response.'@odata.nextLink' -token $token -method $method -recursive -tokenrefresh -credential $credential -tenantID $TenantID -ErrorAction SilentlyContinue
            }
        }
    }
    Return $returnvalue
}

function exitRunbook {
    [CmdletBinding()]
    param (
        [Parameter (Mandatory=$false)][int] $errorCode = 0, # 0 =  success
        [Parameter (Mandatory=$false)][string] $errorMessage = $null, # null = success
        [Parameter (Mandatory=$true)] $outputString # we pass an array, not string
    )

    # Create a hashtable (runbook output)
    $runbookOutput = [ordered]@{}
    $runbookOutput["errorCode"] = "$errorCode"
    $runbookOutput["errorMessage"] = "$errorMessage"
    $runbookOutput["outputString"] = $outputString 

    if ($global:stopwatch.elapsed) {
        $runbookOutput["stopWatch"] = $global:stopwatch.elapsed
        $global:stopwatch.stop()
    }

    # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-json?view=powershell-7.4&viewFallbackFrom=powershell-7
    $runbookOutputJSON = $runbookOutput | ConvertTo-Json -ErrorAction Continue -Compress -Depth 100 -EnumsAsStrings 

    Write-Output $runbookOutputJSON # to be further processed 

    if($errorCode -ne 0) {
        Write-Warning $runbookOutputJSON   # non-zero return code = something is wrong
    }

    Write-Progress "Exit: $errorCode"

    exit $errorCode

}

# Function to test if a device name is available
function Test-DeviceNameAvailability {
    param (
        [string]$DeviceName
    )
    
    # Check in Intune
    $intuneDevice = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$DeviceName'"
    if ($intuneDevice) { return $false }

    # Check in Entra ID
    $entraDevice = Get-MgDevice -Filter "displayName eq '$DeviceName'"
    if ($entraDevice) { return $false }

    <#

    # uncomment if using Hybrid Worker to run the runbook

    # Check DNS
    try {
        [System.Net.Dns]::GetHostEntry($DeviceName)
        return $false
    }
    catch [System.Net.Sockets.SocketException] {
        # DNS lookup failed, name might be available
    }

    # Check via PING
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $result = $ping.Send($DeviceName, 1000)
        if ($result.Status -eq 'Success') {
            return $false
        }
    }
    catch {
        # Ping failed, name might be available
    }
    #>

    return $true
}

# Function to generate a new device name - random 6-digit number for the device name
function Get-NewDeviceName {
    param (
        [string]$Prefix = "PC" # enter your default prefix here
    )

    do {
        $newName = "{0}{1:D6}" -f $Prefix, (Get-Random -Minimum 100000 -Maximum 999999)
    } while (-not (Test-DeviceNameAvailability $newName))
    
    return $newName
}

# returns a prefix from a device name (when the PC name is in the form <some characters><some numbers>, e.g. ABC123456
function Get-StringUntilFirstNumber {
    param(
        [string]$InputString
    )
    if ($InputString -match '^([a-zA-Z]+)') {
        return $matches[1]
    } else {
        return $InputString
    }
}

##############################
## Scriptstart
##############################

try {
    
    $tmpOutput = [ordered]@{} # output, JSON 
    $tmpOutput["runbookVersion"] = "$version"
    Write-Progress "[DetectDuplicatePCsAndRenameViaIntune] Runbook version $($version)"

    $TenantID        = Get-AutomationVariable -Name 'TenantID' -ErrorAction Stop
    $ApplicationID   = Get-AutomationVariable -Name 'ReadWriteApplicationID' -ErrorAction Stop 
    $AppSecret       = Get-AutomationVariable -Name 'ReadWriteAppSecret' -ErrorAction Stop

    Write-Progress "[Graph API] Credential"
    $Credential = New-Object System.Management.Automation.PSCredential($ApplicationID, (ConvertTo-SecureString $AppSecret -AsPlainText -Force))

    ############################
    #### Graph API ####
    ############################
    
        Write-Progress "[Graph API] Token"
        $Token = Get-MSGraphAuthToken -credential $Credential -TenantID $TenantID

        Write-Progress "[Graph API] Connect-MgGraph"
        $loginMgGraph = Connect-MgGraph -AccessToken (ConvertTo-SecureString $Token.access_token -AsPlainText -Force)

    #############################################
    # Get all Intune devices -   $intuneDevices + $hashIntuneDevices #
    #############################################

        # https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.devicemanagement/get-mgdevicemanagementmanageddevice?view=graph-powershell-beta

        Write-Progress "Get-MgDeviceManagementManagedDevice"

        $intuneDevices = Get-MgDeviceManagementManagedDevice -filter "operatingSystem eq 'Windows'" -All -Property serialNumber,id,AzureAdDeviceId,LastSyncDateTime,DeviceName | Sort-Object -Property LastSyncDateTime -Descending 

        $tmpOutput["intuneDevices"] = $intuneDevices.count

    #############################################
    # main script logic #
    #############################################

       Write-Progress "Finding duplicate Intune devices" 
  
       # Group devices by name to find duplicates
       $groupedDevices = $intuneDevices | Where-Object { -not [string]::IsNullOrWhiteSpace($_.DeviceName) } | Group-Object -Property DeviceName
        
       $tmpGroupCounter = 0
       $tmpRenameActionCounter = 0

        foreach ($group in $groupedDevices) {
            if ($group.Count -gt 1) {

                Write-Progress "------------------------------------------------------------"
                Write-Progress "Found duplicate name: $($group.Name). Count: $($group.Count)"
                $tmpOutput["$($group.Name)-Progress01"] = "Found duplicate name: $($group.Name). Count: $($group.Count)"

                Write-Progress "Name: $($group.Name) > $(Get-StringUntilFirstNumber -InputString $group.Name)"
                $tmpOutput["$($group.Name)-Progress02"] = "Name: $($group.Name) > $(Get-StringUntilFirstNumber -InputString $group.Name)"

                $tmpGroupCounter += 1
                
                # Keep the first device, rename others
                for ($i = 1; $i -lt $group.Count; $i++) {
                    
                    $device = $group.Group[$i]
                    
                        $tmpDevice = Invoke-MSGraphQuery -method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($device.id)')" 
                        # https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-actionstate?view=graph-rest-1.0
                        $renameAction = $tmpDevice.deviceActionResults | Sort-Object -Property lastUpdatedDateTime -Descending | Where-Object actionName -eq "setDeviceName" | Where-Object { ($_.actionState -eq "pending") -or ($_.actionState -eq "active") }
                        if ($renameAction)  {

                            Write-Warning "There is a $($renameAction.actionState) Rename Device task for device $($device.Id), last sync: $($device.LastSyncDateTime)"
                            $tmpOutput["$($device.Id)-Warning01"] = "There is a $($renameAction.actionState) Rename Device task for device $($device.Id), last sync: $($device.LastSyncDateTime)"

                            Write-Warning "Original device name $($device.DeviceName), target device name: $($renameAction.passcode), errorcode: $($renameAction.errorCode), startDateTime: $($renameAction.startDateTime), lastUpdatedDateTime: $($renameAction.lastUpdatedDateTime)"
                            $tmpOutput["$($device.Id)-Warning02"] = "Original device name $($device.DeviceName), target device name: $($renameAction.passcode), errorcode: $($renameAction.errorCode), startDateTime: $($renameAction.startDateTime), lastUpdatedDateTime: $($renameAction.lastUpdatedDateTime)"

                        } else {
        
                            $newName = Get-NewDeviceName -Prefix (Get-StringUntilFirstNumber -InputString $group.Name)

                            Write-Progress "Renaming device $($device.Id) from $($device.DeviceName) to $newName (last sync: $($device.LastSyncDateTime))"
                            $tmpOutput["$($device.Id)-RenameAction"] = "Renaming device $($device.Id) from $($device.DeviceName) to $newName (last sync: $($device.LastSyncDateTime))"
                            
                            # Note: /setDeviceName WILL NOT initiate restart of the device after rename operation

                            # https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-setdevicename?view=graph-rest-beta
                            $apiUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($device.id)')/setDeviceName"
                            $response = Invoke-MSGraphQuery -method POST -Uri $apiUrl -Body (@{ deviceName = $newName } | ConvertTo-Json -Depth 100 -Compress)
                            
                            # indicate that the Rename Device action has run...
                            $tmpRenameActionCounter+=1
                            
                            if($response) {
                                $tmpOutput["$($device.Id)-RenameActionResponse"] = "$response"
                                Write-Progress $response
                            }

                        } # if ($renameAction)

                } # for ($i = 1; $i -lt $group.Count; $i++)
                
            } # if ($group.Count -gt 1)

            # Before you roll-out for all PCs at once: only rename the first duplicate found (on which Rename Device is not pending or active)
            if($tmpRenameActionCounter -eq 1) { break }

        } # foreach ($group in $groupedDevices) 

        $tmpOutput["tmpGroupCounter"] = $tmpGroupCounter
        Write-Progress "tmpGroupCounter: $tmpGroupCounter"

    exitRunbook -outputString $tmpOutput

} catch {

    try {

        $exception = $_.Exception
        $tmpOutput["exception.DetectDuplicatePCsAndRenameViaIntune"] = $exception

        Write-Warning $exception.GetType().FullName
        $tmpOutput["exception.DetectDuplicatePCsAndRenameViaIntune.GetTypeFullName"] = $exception.GetType().FullName

        Write-Warning $exception.Message 
        $tmpOutput["exception.DetectDuplicatePCsAndRenameViaIntune.Message"] = $exception.Message

        Write-Warning $exception.StackTrace 
        $tmpOutput["exception.DetectDuplicatePCsAndRenameViaIntune.StackTrace"] = $exception.StackTrace

        Write-Warning $exception.InnerException
        $tmpOutput["exception.DetectDuplicatePCsAndRenameViaIntune.InnerException"] = $exception.InnerException

    } catch {}

    $tmpOutput["DetectDuplicatePCsAndRenameViaIntune"] = 'FailedWithException'
    exitRunbook -errorCode 1002 -errorMessage "Exception raised. Exiting." -outputString $tmpOutput

}

exitRunbook -errorCode 1001 -errorMessage "End of script. The script execution should never reach this point." -outputString $tmpOutput