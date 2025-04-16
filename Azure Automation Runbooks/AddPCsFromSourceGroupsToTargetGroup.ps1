# Gradually add PCs from <source groups> to <target group> (excluding <excluded groups>)

##############################
## Parameters
##############################

#### this must be the first uncommented command in the script
[CmdletBinding()]
Param()

##############################
## Variables
##############################

    $version = "2025.04.16.01"

    $threshold = 200 # number of PCs to be added to the target group (batch size)
    $sourceGroupsList = '<source groups #1>','<source groups #2>','<source groups #3>'
    $excludedGroupsList =  '<excluded groups #1>','<excluded groups #2>'
    $targetGroupName = '<target Entra ID group name>'

    $OutputEncoding = [System.Text.Encoding]::UTF8
    $VerbosePreference = 'SilentlyContinue'  # to supress Write-Verbose - it slows down the script execution (too much logging)
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
        [Parameter (Mandatory=$true)] $outputString # we pass an array, not a string
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

    # Convert the hashtable to a JSON object
    $runbookOutputJSON = $runbookOutput | ConvertTo-Json -ErrorAction Continue -Compress -Depth 100 -EnumsAsStrings 

    Write-Output $runbookOutputJSON 

    if($errorCode -ne 0) {
        Write-Warning $runbookOutputJSON   # non-zero return code = something is wrong
    }

    Write-Progress "Exit: $errorCode"

    exit $errorCode

}

function Get-MgBetaEntraGroupObjectId { 
    [CmdletBinding()]
    param( 
    [Parameter (Mandatory = $true)] [String]$groupName
    )
        # https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.groups/get-mggroup?view=graph-powershell-1.0
       
        Remove-Variable -Name result -ErrorAction SilentlyContinue
        Remove-Variable -Name query -ErrorAction SilentlyContinue
    
        $result = $null
        $query = $null
        $global:counter = $null
    
        try {
            
            $query = Get-MgBetaGroup -Filter "displayName eq '$($groupName)'" -ConsistencyLevel eventual -Count counter
    
            # if exactly 1 ObjectId has been returned
            if ( $query.Id -and ($global:counter -eq 1) ) { $result = $query.Id } 
                
        } catch {         
            # Exception
        }
    
        return $result
        
}

##############################
## Scriptstart
##############################

try {
    
    $tmpOutput = [ordered]@{} # output, JSON 
    $tmpOutput["runbookVersion"] = "$version"
    Write-Progress "[AddPCsToTargetGroup] Runbook version $($version)"

    # https://learn.microsoft.com/en-us/azure/automation/automation-runbook-output-and-messages#retrieve-runbook-output-and-messages-in-windows-powershell
    $TenantID        = Get-AutomationVariable -Name 'TenantID' -ErrorAction Stop
    $ApplicationID   = Get-AutomationVariable -Name 'ReadWriteApplicationID' -ErrorAction Stop # Azure App with read-write access to Entra ID groups
    $AppSecret       = Get-AutomationVariable -Name 'ReadWriteAppSecret' -ErrorAction Stop

    Write-Progress "[Graph API] Credential"
    $Credential = New-Object System.Management.Automation.PSCredential($ApplicationID, (ConvertTo-SecureString $AppSecret -AsPlainText -Force))

    ############################
    #### Graph API ####
    ############################
    
        Write-Progress "[Graph API] Token"
        $Token = Get-MSGraphAuthToken -credential $Credential -TenantID $TenantID

        Write-Progress "[Graph API] Connect-MgGraph"
        $loginMgGraph = Connect-MgGraph -AccessToken (ConvertTo-SecureString $Token.access_token -AsPlainText -Force) -NoWelcome
        $tmpOutput["loginMgGraph"] = "$loginMgGraph"

    ############################
    #### Retrieve source group(s) membership 
    ############################

        $sourceGroupsMembership = $null

        foreach ($groupName in $sourceGroupsList) {

            Remove-Variable -Name groupID -ErrorAction SilentlyContinue
            Remove-Variable -Name groupMembers -ErrorAction SilentlyContinue

            try {
                
                $groupID =  Get-MgBetaEntraGroupObjectId -groupName $groupName
                Write-Progress "Processing group: $($groupName) - $($groupID)"

                if ($groupID) { # $null means either multiple groups with the same displayName or none found

                    # https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.groups/get-mggroupmember?view=graph-powershell-beta
                    $groupMembers = Get-MgGroupTransitiveMember -GroupId $groupID -All # list of Ids of group members

                    $sourceGroupsMembership += $groupMembers

                    Write-Progress "[Included] Count of $($groupName) members: $($groupMembers.Count)"
                    $tmpOutput["Included - count of $($groupName)"] = "$($groupMembers.Count)"

                } else {
                    exitRunbook -errorCode 7621 -errorMessage "GroupID for $($groupName) not found. Exiting." -outputString $tmpOutput
                } 

            } catch { 
                exitRunbook -errorCode 6475 -errorMessage "[hashSourceGroupsMembership] Error processing group ID: $groupID. Exiting." -outputString $tmpOutput
            }

        } # foreach...

        $sourceGroupsMembership = $sourceGroupsMembership | Select-Object -Property Id,AdditionalProperties -Unique
    
        Write-Progress "Count of 'sourceGroupsMembership' members: $($sourceGroupsMembership.Count)"
        $tmpOutput["Count of sourceGroupsMembership"] = "$($sourceGroupsMembership.Count)"

    ############################
    #### Retrieve excluded group(s) membership 
    ############################

        # Create an empty hash table to store group membership of devices ... we will use "GroupName:Entra Object Id" as a key in a hashtable
        $excludedGroupsMembership = $null

        $excludedGroupsList += $targetGroupName

        foreach ($groupName in $excludedGroupsList) {

            Remove-Variable -Name groupID -ErrorAction SilentlyContinue
            Remove-Variable -Name groupMembers -ErrorAction SilentlyContinue

            try {
                
                $groupID =  Get-MgBetaEntraGroupObjectId -groupName $groupName
                Write-Progress "Processing group: $($groupName) - $($groupID)"

                if ($groupID) { 

                    # https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.groups/get-mggroupmember?view=graph-powershell-beta
                    $groupMembers = Get-MgGroupTransitiveMember -GroupId $groupID -All # list of Ids of group members
                    Write-Progress "[Excluded] Count of $($groupName) members: $($groupMembers.Count)"
                    $tmpOutput["Excluded - count of $($groupName)"] = "$($groupMembers.Count)"

                    $excludedGroupsMembership += $groupMembers # |  Select-Object -Unique

                } else {
                    exitRunbook -errorCode 7621 -errorMessage "GroupID for $($groupName) not found. Exiting." -outputString $tmpOutput
                } 

            } catch { 
                exitRunbook -errorCode 6475 -errorMessage "[hashExcludedGroupsMembership] Error processing group ID: $groupID. Exiting." -outputString $tmpOutput
            }

        } # foreach...

        $excludedGroupsMembership = $excludedGroupsMembership | Select-Object -Property Id,AdditionalProperties -Unique

        Write-Progress "Count of 'excludedGroupsMembership' members: $($excludedGroupsMembership.Count)"
        $tmpOutput["Count of excludedGroupsMembership"] = "$($excludedGroupsMembership.Count)"
        
    #################################################################################
    #### source groups minus excluded groups (and not already in the target group)
    #################################################################################
      
        $targetDevices = $null

        $targetDevices = $sourceGroupsMembership | Where-Object { `
                        ($_.AdditionalProperties.operatingSystem -eq "Windows") `
                        -and ($_.Id -notin $excludedGroupsMembership.Id) `
                        -and ($_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.device") `
                    } | Select-Object -Property Id,AdditionalProperties -Unique

        Write-Progress "Count of 'targetDevices' members: $($targetDevices.Count)"
        $tmpOutput["Count of targetDevices"] = "$($targetDevices.Count)"

    ########################################################
    #### now add up to $threshold PCs into the target group
    ########################################################

        $tmpCounter = 0

        $groupName = $targetGroupName
        $groupID =  Get-MgBetaEntraGroupObjectId -groupName $groupName
        Write-Progress "Processing target group: $($groupName) - $($groupID)"

        if (-not $groupID) {
            exitRunbook -errorCode 7621 -errorMessage "GroupID for $($groupName) not found. Exiting." -outputString $tmpOutput
        } 

        $targetDevices | ForEach-Object -Begin $null -End $null -Process {    

            try {
                $tmpOutput["Now adding"] = "$($_.AdditionalProperties.displayName),$($_.Id)"
                Write-Progress $($tmpOutput["Now adding"])
                
                $null = New-MgBetaGroupMember -GroupId $groupID -DirectoryObjectId $_.Id
                                
                $tmpOutput["Added:$($_.Id)"] = "$($_.AdditionalProperties.displayName)"
                $tmpCounter++
              
            } catch {
                $tmpOutput["Exception:$($_.Id)"] = "$($_.AdditionalProperties.displayName)"
                Write-Progress "Exception:$($tmpOutput["Exception:$($_.Id)"])"
            }

            if($tmpCounter -gt $threshold) { 
                Write-Progress "OK. Counter reached the maximum. Exiting."
                exitRunbook -outputString $tmpOutput
            }

            Start-Sleep -Milliseconds 100 # 0.1 sec delay between each call to the Graph API (to avoid throttling)

        }

        Write-Progress "DONE"

    # output 
    exitRunbook -outputString $tmpOutput

} catch {

    try {

        $exception = $_.Exception
        $tmpOutput["exception.AddPCsToTargetGroup"] = $exception

        Write-Warning $exception.GetType().FullName
        $tmpOutput["exception.AddPCsToTargetGroup.GetTypeFullName"] = $exception.GetType().FullName

        Write-Warning $exception.Message 
        $tmpOutput["exception.AddPCsToTargetGroup.Message"] = $exception.Message

        Write-Warning $exception.StackTrace 
        $tmpOutput["exception.AddPCsToTargetGroup.StackTrace"] = $exception.StackTrace

        Write-Warning $exception.InnerException
        $tmpOutput["exception.AddPCsToTargetGroup.InnerException"] = $exception.InnerException

    } catch {}

    $tmpOutput["AddPCsToTargetGroup"] = 'FailedWithException'
    exitRunbook -errorCode 1002 -errorMessage "Exception raised. Exiting." -outputString $tmpOutput

}

exitRunbook -errorCode 1001 -errorMessage "End of script. The script execution should never reach this point." -outputString $tmpOutput