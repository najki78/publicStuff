# Runbook name: User2DeviceMapper

# Required modules:
# Microsoft.Graph.Authentication
# Microsoft.Graph.Groups 
# Microsoft.Graph.Users 
# Microsoft.Graph.Identity.DirectoryManagement 

# Input: 

    # None

# Output: 

    # JSON: errorCode, errorMessage, stopWatch, outputString 

##############################
## Parameters
##############################

#### this must be the first uncommented command in the script
[CmdletBinding()]
Param()

##############################
## Variables
##############################

$version = "2024.09.12.02"

$VerbosePreference = 'SilentlyContinue' 
$InformationPreference = 'Continue'
$ErrorActionPreference = "Stop" 
$WarningActionPreference = 'Continue'
$DebugPreference = 'SilentlyContinue' 

$stopwatch = [system.diagnostics.stopwatch]::startNew()

##############################
## Functions
##############################

Function Get-MSGraphAuthToken {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory = $true)][pscredential]$Credential,
        [parameter(Mandatory = $true)][string]$tenantID
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

# Very ugly function (uses global variables $token, $loginMgGraph, $Credential, $TenantID which is a bad practice) to check if an access token is about to expire and if it does, renews it
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
        [string]$tenantID
    )

    refreshAccessTokenIfNeeded
    $token = $global:Token.access_token

    $authHeader = @{
        'Accept'        = 'application/json'
        'Content-Type'  = 'application/json'
        'Authorization' = "Bearer $Token"
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
                Write-Warning "Message: $( $exception.Message )" # .ToString().Replace("`r`n", " ").Replace("`n", " ")
                Write-Warning "StackTrace: $( $exception.StackTrace )" # .ToString().Replace("`r`n", " ").Replace("`n", " ")
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
    param (
        [Parameter (Mandatory=$false)][int] $errorCode = 0, # 0 =  success
        [Parameter (Mandatory=$false)][string] $errorMessage = $null, # null = success
        [Parameter (Mandatory=$true)] $outputString # we pass an array
    )

    # Create a hashtable (runbook output)
    $runbookOutput = [ordered]@{}
    $runbookOutput["errorCode"] = "$errorCode"
    $runbookOutput["errorMessage"] = "$errorMessage"
    $runbookOutput["outputString"] = $outputString 
    $runbookOutput["stopWatch"] = $global:stopwatch.elapsed
    $global:stopwatch.stop()

    # Convert the hashtable to a JSON object
    $runbookOutputJSON = $runbookOutput | ConvertTo-Json -Compress -Depth 100 -ErrorAction Continue

    Write-Output $runbookOutputJSON 

    if($errorCode -ne 0) {
        Write-Warning $runbookOutputJSON   # non-zero return code = something is wrong
    }

    exit $errorCode

}

function populateDeviceGroup {
    param (
        [ValidateNotNullOrEmpty()][Parameter (Mandatory=$true)][string] $usersGroupID,
        [ValidateNotNullOrEmpty()][Parameter (Mandatory=$true)][string] $deviceGroupID,
        [Parameter (Mandatory=$false)][switch]$leaveCurrentDevicesInTheDeviceGroup
    )

    try {

        refreshAccessTokenIfNeeded

        ######################################################################################################
        # USERS group
        ######################################################################################################

        Remove-Variable -ErrorAction SilentlyContinue groupID
        Remove-Variable -ErrorAction SilentlyContinue groupName
        Remove-Variable -ErrorAction SilentlyContinue groupMembers
        Remove-Variable -ErrorAction SilentlyContinue devices
        Remove-Variable -ErrorAction SilentlyContinue tmpDevices
        Remove-Variable -ErrorAction SilentlyContinue tmpUserDevices

        $groupID = $usersGroupID
        $groupName = (Get-MgGroup -GroupId $groupID -ErrorAction Stop).DisplayName
        Write-Progress $groupName

        # list of Ids of group members - Entra Object Id is returned
        # retrieve only User objects
        $groupMembers = Get-MgGroupTransitiveMember -GroupId $groupID -All  | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' }

        $global:tmpOutput["$groupName-usersGroupMembersCount"] = $groupMembers.Count
        $devices = @() 

        foreach ($user in $groupMembers.id) {
            if($user) {  
                # Get-MgUserRegisteredDevice  --- returned "id" is Entra ID ObjectID
                Remove-Variable -ErrorAction SilentlyContinue tmpUserDevices
                $tmpUserDevices = Get-MgUserRegisteredDevice -UserId $user -All -ErrorAction Continue
                if($tmpUserDevices) { $devices += $tmpUserDevices }
            }
        }

        $global:tmpOutput["$groupName-devicesRawCount"] = $devices.Count
        
        # only Intune managed Windows devices
        $devices = $devices | Where-Object { $_.AdditionalProperties.operatingSystem -eq 'Windows' } | Where-Object { $_.AdditionalProperties.isManaged -eq 'true' } 
        $global:tmpOutput["$groupName-devicesManagedInclInactiveCount"] = $devices.Count

        # now we clean up the inactive devices
        $tmpDevices = $devices
        $devices = @() # re-initialize

        foreach ($device in $tmpDevices) {

            # if the device has been recently active...
            if ( ((Get-MgDevice -DeviceId $device.id -Property "ApproximateLastSignInDateTime" -ErrorAction Stop).ApproximateLastSignInDateTime) -gt $global:DeviceInactivityInDaysThreshold) {
                $devices += $device
            }

        }
        Remove-Variable -ErrorAction SilentlyContinue tmpDevices
        $global:tmpOutput["$groupName-devicesManagedActiveCount"] = $devices.Count

    ######################################################################################################
    # DEVICES group
    ######################################################################################################

        Remove-Variable -ErrorAction SilentlyContinue groupID
        Remove-Variable -ErrorAction SilentlyContinue groupName
        Remove-Variable -ErrorAction SilentlyContinue groupMembers
        
        $groupID = $deviceGroupID
        $groupName = (Get-MgGroup -GroupId $groupID -ErrorAction Stop).DisplayName
        Write-Progress $groupName

        # list of Ids of group members - Entra ID Object Id is returned
        $groupMembers = Get-MgGroupTransitiveMember -GroupId $groupID -All -ErrorAction Stop  | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.device' }

        foreach ($device in $devices) {

                if($device.id -and ($device.id -in $groupMembers.id)) {
                   # generates a lot of output if uncommented, use only while troubleshooting an issue
                   # $tmpOutput["$groupName-deviceSkipped:$($device.id)"] = $device.id # already in the target group
                } else {
                    Remove-Variable -ErrorAction SilentlyContinue tmpResults
                    $tmpResults = New-MgGroupMember -GroupId $groupID -DirectoryObjectId $device.id
                    
                    $global:tmpOutput["$groupName-deviceAdded:$($device.id):Results"] = $tmpResults
                    $global:tmpOutput["$groupName-deviceAdded:$($device.id)"] = $device.id
                }

        } # foreach

        if(-not $leaveCurrentDevicesInTheDeviceGroup) {

            # now remove those device from device group that  no longer belong there (=that are no longer in $devices)
            foreach ($groupMember in $groupMembers) {
            
                if($groupMember.id -in $devices.id) {
                    # use while troubleshooting an issue
                } else {
                    
                    Remove-Variable -ErrorAction SilentlyContinue tmpResults
                    
                    $tmpResults = Remove-MgGroupMemberByRef -GroupId $groupID -DirectoryObjectId $groupMember.id -PassThru -ErrorAction Continue -WarningAction SilentlyContinue 
                    Write-Progress "Remove-MgGroupMemberByRef -GroupId $groupID -DirectoryObjectId $($groupMember.id)"
                    
                    $global:tmpOutput["$groupName-deviceRemoved:$($groupMember.id):Results"] = $tmpResults
                    $global:tmpOutput["$groupName-deviceRemoved:$($groupMember.id)"] = $groupMember.id
                }
            }
        }

    } catch {
        try {

            $exception = $_.Exception
            $global:tmpOutput["exception-$usersGroupID-$deviceGroupID"] = $exception
    
            Write-Warning $exception.GetType().FullName
            $global:tmpOutput["exception-$usersGroupID-$deviceGroupID.GetTypeFullName"] = $exception.GetType().FullName
    
            Write-Warning $exception.Message 
            $global:tmpOutput["exception-$usersGroupID-$deviceGroupID.Message"] = $exception.Message
    
            Write-Warning $exception.StackTrace 
            $global:tmpOutput["exception-$usersGroupID-$deviceGroupID.StackTrace"] = $exception.StackTrace
    
            Write-Warning $exception.InnerException
            $global:tmpOutput["exception-$usersGroupID-$deviceGroupID.InnerException"] = $exception.InnerException

        } catch {}
    }

}

##############################
## Scriptstart
##############################

try {

    Write-Verbose "Script version $($version)"
  
    $TenantID               = Get-AutomationVariable -Name 'TenantID'
    $ApplicationID          = Get-AutomationVariable -Name 'ReadWriteApplicationID'
    $AppSecret              = Get-AutomationVariable -Name 'ReadWriteAppSecret'

    # number of days of device inactivity (the threshold after which we do not include it into a group anymore) 
    $DeviceInactivityInDays = -1 * (Get-AutomationVariable -Name 'DeviceInactivityInDays') 

    # To show devices that signed in anytime in the last X days
    $DeviceInactivityInDaysThreshold = $(Get-Date).AddDays( $DeviceInactivityInDays )

    $tmpOutput = [ordered]@{} # output, JSON 
    $tmpOutput["scriptVersion"] = $version

    $tmpOutput["DeviceInactivityInDays"] = $DeviceInactivityInDays
    $tmpOutput["DeviceInactivityInDaysThreshold"] = $DeviceInactivityInDaysThreshold

    $Credential = New-Object System.Management.Automation.PSCredential($ApplicationID, (ConvertTo-SecureString $AppSecret -AsPlainText -Force))
    $Token = Get-MSGraphAuthToken -credential $Credential -TenantID $TenantID

    $loginMgGraph = Connect-MgGraph -AccessToken (ConvertTo-SecureString $Token.access_token -AsPlainText -Force)

    # <Users Group Entra Object ID> -> <Device Group Entra Object ID>
    populateDeviceGroup -usersGroupID "Users Group Entra Object ID" -deviceGroupID "Device Group Entra Object ID"
    # if you want to keep manually added devices in device group, use the parameter '-leaveCurrentDevicesInTheDeviceGroup'

    exitRunbook -outputString $tmpOutput  

} catch {

    try {
        $exception = $_.Exception
        $tmpOutput["exception"] = $exception

        Write-Warning $exception.GetType().FullName
        $tmpOutput["exception.GetTypeFullName"] = $exception.GetType().FullName

        Write-Warning $exception.Message 
        $tmpOutput["exception.Message"] = $exception.Message

        Write-Warning $exception.StackTrace 
        $tmpOutput["exception.StackTrace"] = $exception.StackTrace

        Write-Warning $exception.InnerException
        $tmpOutput["exception.InnerException"] = $exception.InnerException

    } catch {}

    exitRunbook -errorCode 1002 -errorMessage "Exception raised."-outputString $tmpOutput

}

exitRunbook -errorCode 1001 -errorMessage "End of script. The script execution should never reach this point." -outputString $tmpOutput