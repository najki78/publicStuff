Install-Module ps2exe
Invoke-ps2exe ".\ShadowingSystrayIndicator.ps1" -title "Remote Desktop Services Systray Indicator" -verbose -noConsole # -requireAdmin -DPIAware -credentialGUI -noConsole 