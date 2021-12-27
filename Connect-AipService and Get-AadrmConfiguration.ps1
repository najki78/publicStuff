
Set-ExecutionPolicy -ExecutionPolicy Bypass 
Get-ExecutionPolicy -List

Import-Module PowerShellGet
Install-Module -Name AIPService

Connect-AipService

Get-AadrmConfiguration 

# Enterprise Roaming 
# https://docs.microsoft.com/en-us/azure/active-directory/devices/enterprise-state-roaming-faqs