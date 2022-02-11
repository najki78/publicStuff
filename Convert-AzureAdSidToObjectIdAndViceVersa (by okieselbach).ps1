
# source: https://github.com/okieselbach/Intune/blob/master/Convert-AzureAdSidToObjectId.ps1 ... Thank you!

<#

#Get AzureAD Module
$m = Get-Module -Name AzureAD -ListAvailable

Write-Output $m

if (-not $m)
{
    
    Install-Module -Name AzureAD -AllowClobber -Force 

}

#Install-Module AzureAD
#Connect-AzureAD

#>

function Convert-AzureAdSidToObjectId {
<#
.SYNOPSIS
Convert a Azure AD SID to Object ID
 
.DESCRIPTION
Converts an Azure AD SID to Object ID.
Author: Oliver Kieselbach (oliverkieselbach.com)
The script is provided "AS IS" with no warranties.
 
.PARAMETER ObjectID
The SID to convert
#>

    param([String] $Sid)

    $text = $sid.Replace('S-1-12-1-', '')
    $array = [UInt32[]]$text.Split('-')

    $bytes = New-Object 'Byte[]' 16
    [Buffer]::BlockCopy($array, 0, $bytes, 0, 16)
    [Guid]$guid = $bytes

    return $guid
}

<# 

$sid = "S-1-12-1-3355307493-1154222592-1435707025-2509201134"
$objectId = Convert-AzureAdSidToObjectId -Sid $sid
Write-Output $objectId

# Output:

# Guid
# ----
# 73d664e4-0886-4a73-b745-c694da45ddb4

#>

function Convert-AzureAdObjectIdToSid {
<#
.SYNOPSIS
Convert an Azure AD Object ID to SID
 
.DESCRIPTION
Converts an Azure AD Object ID to a SID.
Author: Oliver Kieselbach (oliverkieselbach.com)
The script is provided "AS IS" with no warranties.
 
.PARAMETER ObjectID
The Object ID to convert
#>

    param([String] $ObjectId)

    $bytes = [Guid]::Parse($ObjectId).ToByteArray()
    $array = New-Object 'UInt32[]' 4

    [Buffer]::BlockCopy($bytes, 0, $array, 0, 16)
    $sid = "S-1-12-1-$array".Replace(' ', '-')

    return $sid
}

$objectId = "a18b5f0b-375d-48ac-ab7f-9a952042df35"
$sid = Convert-AzureAdObjectIdToSid -ObjectId $objectId
Write-Output $sid


# Output:

# S-1-12-1-1943430372-1249052806-2496021943-3034400218
# Get-AzureADObjectByObjectId -ObjectIds $objectId