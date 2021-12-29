
Install-Module -Name Microsoft.Graph.Intune

Connect-MSGraph

Get-IntuneDeviceConfigurationPolicy | select displayName,id,description 