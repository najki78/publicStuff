
# 2022-02-11 list local Administrators (in a reliable way)

# https://github.com/PowerShell/PowerShell/issues/2996

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

$administrators