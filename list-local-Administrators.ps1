
# 2022-02-11 list local Administrators (in a reliable way)

# https://github.com/PowerShell/PowerShell/issues/2996



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


<#
Get-LocalGroupMember -Group "Administrators"

$PSVersionTable

$Error[0] | fl * -Force

$localAdminGroupWmi = Get-WMIObject Win32_Group -Filter "Name='Administrators'" 
$localAdminGroupWmi.GetRelated("Win32_UserAccount")


foreach ($group in Get-LocalGroup ) { 
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/$group" $group_members = @($group.Invoke('Members') | % {([adsi]$_).path}) $group_members 
    }

#>


<#

#requires -version 3.0

#use CIM to list members of the local admin group

# https://jdhitsolutions.com/blog/scripting/2342/query-local-administrators-with-cim/

[cmdletbinding()]
Param([string]$computer=$env:computername)

$query="Associators of {Win32_Group.Domain='$computer',Name='Administrators'} where Role=GroupComponent"

write-verbose "Querying $computer"
write-verbose $query

Get-CIMInstance -query $query -computer $computer |
Select @{Name="Member";Expression={$_.Caption}},Disabled,LocalAccount,
@{Name="Type";Expression={([regex]"User|Group").matches($_.Class)[0].Value}},
@{Name="Computername";Expression={$_.ComputerName.ToUpper()}}

#>


$administrators = @(
([ADSI]"WinNT://./Administrators").psbase.Invoke('Members') |
% { 
 $_.GetType().InvokeMember('AdsPath','GetProperty',$null,$($_),$null) 
 }
) -match '^WinNT';

$administrators = $administrators -replace "WinNT://",""

#$administrators 

Connect-AzureAD

foreach ($adminSID in $administrators) {

    if ($adminSID -like "S-1-*") {
        $objectId = Convert-AzureAdSidToObjectId -Sid $adminSID
        #$adminSID
        #$objectId 
        (Get-AzureADObjectByObjectId -ObjectIds $objectId -ErrorAction SilentlyContinue).DisplayName
     } else {
        #Write-Host "XXX"
        $adminSID 
     }
}




<#
$objectId = "a18b5f0b-375d-48ac-ab7f-9a952042df35"
$sid = Convert-AzureAdObjectIdToSid -ObjectId $objectId
Write-Output $sid
#>

<# 

$sid = "S-1-12-1-3355307493-1154222592-1435707025-2509201134"
$objectId = Convert-AzureAdSidToObjectId -Sid $sid
Write-Output $objectId

# Output:

# Guid
# ----
# 73d664e4-0886-4a73-b745-c694da45ddb4

#>
