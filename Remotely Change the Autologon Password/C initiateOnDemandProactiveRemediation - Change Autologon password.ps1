# initiateOnDemandProactiveRemediation

# Thank you Damien Van Robaeys! - https://www.systanddeploy.com/2023/07/run-on-demand-remediation-script-on.html
# https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-initiateondemandproactiveremediation?view=graph-rest-beta

$version = "2024.01.25.01"

cls

$VerbosePreference = 'SilentlyContinue' 
$InformationPreference = 'SilentlyContinue'
$ErrorActionPreference = "Stop" 
$WarningActionPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'

##############################
## Functions
##############################

# The actual token is returned as (Get-MSGraphAuthToken).access_token
Function Get-MSGraphAuthToken {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory = $true)]
        [pscredential]$Credential,
        [parameter(Mandatory = $true)]
        [string]$tenantID
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

# Very ugly function (uses global variables $Token and $loginMgGraph which is a bad practice) to check if access token is about to expire and if it does, renews it
function refreshAccessTokenIfNeeded {

    # Check if the access token is valid for at least 10 minutes
    $ExpirationThreshold = 10 # minutes
    $CurrentTime = Get-Date
    $ExpirationTime =  (get-date -year 1970 -month 1 -day 1 -hour 0 -minute 0 -second 0).addseconds([int64] $global:Token.expires_on) # convert to DateTime
    $TimeDifference = New-TimeSpan -Start $CurrentTime -End $ExpirationTime

    if ($TimeDifference.TotalMinutes -lt $ExpirationThreshold) {
    
        Write-Progress "[Graph API] Renewing access token."
        $global:Token = Get-MSGraphAuthToken -credential $global:Credential -TenantID $global:TenantID
        $global:loginMgGraph = Connect-MgGraph -AccessToken (ConvertTo-SecureString $global:Token.access_token -AsPlainText -Force)
        Write-Progress "$( $global:loginMgGraph )"

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

        [Parameter(Mandatory = $true, ParameterSetName = 'Default')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Refresh')]
        [string]$token,

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

        If (($Error[0].ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.Message -eq 'Access token has expired.') { #  -and $tokenrefresh
            refreshAccessTokenIfNeeded
            $token = $global:token.access_token
        }
        Else {
            Throw $_
        }
        
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

function Load-Module {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory = $true)][string] $m,
        [parameter(Mandatory = $false)][string] $version
    )

    $returnValue = $false # module not loaded

    Write-Output "[Powershell module] Loading module $($m)"
    
    try {

        if ($version) {
            
            $module = Get-InstalledModule -Name $m -RequiredVersion $version -ErrorAction SilentlyContinue
            
            if(-not $module) {
                Write-Output "[Powershell module] Installing module $($m) - required version: $version"
                Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Installing module $($m) - required version: $($version): $( Install-Module -Name $m -AllowClobber -Force -confirm:$false -RequiredVersion $version )"
            }

            Get-Module -ListAvailable -Name $m -ErrorAction Continue | Where-Object { $_.Version -ne $version } -ErrorAction Continue | ForEach-Object { Uninstall-Module -Name $_.Name -RequiredVersion $_.Version -Force -ErrorAction Continue }

            # import
            Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Importing module $($m) - importing version $($version): $( Import-Module $m -Scope Global -ErrorAction Stop -RequiredVersion $version -PassThru )"

        } else { # if $version not present
        
            $module = Get-InstalledModule -Name $m -ErrorAction SilentlyContinue # -Verbose 
            if (-not $module) {
                Write-Output "[Powershell module] Installing module $($m)"
                # https://learn.microsoft.com/en-us/powershell/module/powershellget/install-module?view=powershellget-2.x
                Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Installing module $($m): $( Install-Module $m -AllowClobber -Force -confirm:$false )"

            } else {
                Write-Output "[Powershell module] Updating module $($m)"
                Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Updating module $($m): $( Update-Module -Name $m -confirm:$false -ErrorAction Continue )"
                # -Force 
            }

            # import
            Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Importing module $($m): $( Import-Module $m -Scope Global -ErrorAction Stop -PassThru )"

        }

        # displaying the current version
        $module = Get-Module -Name $m -ListAvailable -ErrorAction Stop
        if ($module.Version) {
            Write-Information -ErrorAction SilentlyContinue -MessageData "[Powershell module] Module $($m) - current version: $($module.Version.ToString())"
        }

        $returnValue = $true

    } catch {

        try {
            $exception = $_.Exception
                Write-Warning "GetType.FullName: $( $exception.GetType().FullName)"
                Write-Warning "Message: $( $exception.Message )" # .ToString().Replace("`r`n", " ").Replace("`n", " ")
                Write-Warning "StackTrace: $( $exception.StackTrace )" # .ToString().Replace("`r`n", " ").Replace("`n", " ")
                Write-Warning "InnerException: $( $exception.InnerException )"
        } catch {}

        exit 1 # "[Exception] Unable to import $($m) module. Exiting."

    }

    # return $returnValue

}

##############################
## Variables
##############################

$graphApiVersion = "beta"

$tenantID = "<yourAzureTenantID>"
$ApplicationID   = "<your App ID>"

############################################################
## Login to Graph using Azure App
############################################################
    
# Azure App requires 'DeviceManagementManagedDevices.PrivilegedOperations.All' permission 

    try {

        # in this example, using 'Client secret' to authenticate to Azure App
        $AppSecret = (Get-Credential -Message "Enter your password" -UserName $ApplicationID).Password
       
        $Credential = New-Object System.Management.Automation.PSCredential($ApplicationID, $AppSecret )
        $Token = Get-MSGraphAuthToken -credential $Credential -TenantID $TenantID
        $loginMgGraph = Connect-MgGraph -AccessToken (ConvertTo-SecureString $Token.access_token -AsPlainText -Force)

    } catch {

        Write-Output $_.Exception.Message
        Write-Output "[Connect-MgGraph] Exception while connecting. Exiting."
        exit 1

    }

    if (-not $loginMgGraph) {
        Write-Output "[Connect-MgGraph] Not connected to Graph. Exiting."
        exit 1
    }
  
# Get the Remediation script ID from the Intune portal
# https://doitpsway.com/force-redeploy-of-intune-scripts-even-remediation-ones-using-powershell
$Remediation_Script_ID = "<Remediation_Script_ID>" 
$RemediationScript_Body = @{ "ScriptPolicyId"="$Remediation_Script_ID" }

$listIntuneDevice_IDs = @()

# add Intune Device IDs 
$listIntuneDevice_IDs += "<Intune Device ID #1>" 
...
$listIntuneDevice_IDs += "<Intune Device ID #X>" 

    foreach($IntuneDevice_ID in $listIntuneDevice_IDs) {
      
        $RemediationScript_URL = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$IntuneDevice_ID')/initiateOnDemandProactiveRemediation"                              
        Write-Output "$IntuneDevice_ID - starting..."
        
        $response = Invoke-MSGraphQuery -method POST -URI $RemediationScript_URL -token $token.access_token -Body ($RemediationScript_Body | ConvertTo-Json) -ErrorAction Continue
        Write-Output "$IntuneDevice_ID - response: $($response)"

        Start-Sleep -Seconds 2 # no reason, just in order not to overload Graph and hit some requests limit

    }

DisConnect-MgGraph