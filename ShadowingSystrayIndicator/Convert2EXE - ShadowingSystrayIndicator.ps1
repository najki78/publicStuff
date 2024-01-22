Install-Module ps2exe
Invoke-ps2exe "ShadowingSystrayIndicator.ps1" -DPIAware -credentialGUI -title "Remote Desktop Services Systray Indicator" -verbose # -requireAdmin 