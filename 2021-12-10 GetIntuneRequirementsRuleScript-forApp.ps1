# Kudos to Nicola at https://tech.nicolonsky.ch/intune-win32-app-requirements-deep-dive/  ... just slightly modified

#Get Graph API Intune Module

$m = Get-Module -Name Microsoft.Graph.Intune -ListAvailable
if (-not $m)
{
    Install-Module NuGet -Force
    Install-Module Microsoft.Graph.Intune
}

Import-Module Microsoft.Graph.Intune -Global
 
#Connect-MSGraph -AdminConsent

#The connection to Azure Graph
Connect-MSGraph 
Write-Output "Connected..." 

# to get your application id you can easily use the web browser and navigate to your Intune app and copy the id from the URL.
#   It will look like the following where the guid at the end corresponds to the id:
#  https://devicemanagement.microsoft.com/#blade/Microsoft_Intune_Apps/SettingsMenu/0/appId/0a2b8969-24c9-4305-bbc1-e3cc2562c29b

$mobileApp= Get-IntuneMobileApp -mobileAppId "67b28934-9238-400e-a533-c27a0319d4a0"

Write-Output "Display name: " $mobileApp.rules.displayName

[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($mobileApp.rules.scriptContent))


