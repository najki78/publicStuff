# publicStuff

Hi, I am Ľuboš Nikolíni and this is my collection of PowerShell scripts, mostly used to manage AzureAD / Intune environments.

What might be of interest for you:

## [Get-ScopeTags-of-AAD-Devices.ps1](PowerShell-Intune/Get-ScopeTags-of-AAD-Devices.ps1)
A script to retrieve scope tags for all Intune managed Windows devices (as there is currently no built-in function to provide the functionality).

## [Get-AzureADDevicesGroupsMembership.ps1](Get-AzureADDevicesGroupsMembership.ps1)
A script to retrieve AAD groups membership of AzureAD devices (aka Get-AzureADDeviceMembership).
Well, until we have have an equivalent of Get-AzureADUserMembership that would cover Device objects.

## [ListObjectIdsForAADDevices.ps1](ListObjectIdsForAADDevices.ps1)
A script to dump (Azure AD) Object ID of given host names (detects incorrect or duplicate names).
