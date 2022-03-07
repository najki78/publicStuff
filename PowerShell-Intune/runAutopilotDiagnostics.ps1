

# https://www.powershellgallery.com/packages/Get-AutopilotDiagnostics
# https://oofhours.com/2020/07/12/windows-autopilot-diagnostics-digging-deeper/

# mdmdiagnosticstool.exe -area Autopilot -cab c:\autopilot.cab

<#
SYNTAX
    C:\Program Files\WindowsPowerShell\Scripts\Get-AutopilotDiagnostics.ps1 [[-CABFile] <String>] [[-ZIPFile] <String>] [-Online] [-AllSessions] [-ShowPolicies] [<CommonParameters>]
    
    
DESCRIPTION
    This script displays diagnostics information from the current PC or a captured set of logs.  This includes details about the Autopilot profile settings; policies, apps, certifica
    te profiles, etc. being tracked via the Enrollment Status Page; and additional information.
    
    This should work with Windows 10 1903 and later (earlier versions have not been validated).  This script will not work on ARM64 systems due to registry redirection from the use o
    f x86 PowerShell.exe.
    

RELATED LINKS

REMARKS
    To see the examples, type: "get-help C:\Program Files\WindowsPowerShell\Scripts\Get-AutopilotDiagnostics.ps1 -examples".
    For more information, type: "get-help C:\Program Files\WindowsPowerShell\Scripts\Get-AutopilotDiagnostics.ps1 -detailed".
    For technical information, type: "get-help C:\Program Files\WindowsPowerShell\Scripts\Get-AutopilotDiagnostics.ps1 -full".

PARAMETERS
    -CABFile <String>
        Processes the information in the specified CAB file (captured by MDMDiagnosticsTool.exe -area Autopilot -cab filename.cab) instead of from the registry.
        
    -ZIPFile <String>
        Processes the information in the specified ZIP file (captured by MDMDiagnosticsTool.exe -area Autopilot -zip filename.zip) instead of from the registry.
        
    -Online [<SwitchParameter>]
        Look up the actual policy and app names via the Intune Graph API
        
    -AllSessions [<SwitchParameter>]
        Show all ESP progress instead of just the final details.
        
    -ShowPolicies [<SwitchParameter>]
        Shows the policy details as recorded in the NodeCache registry keys, in the order that the policies were received by the client.
        
    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer, PipelineVariable, and OutVariable. For more information, see 
        about_CommonParameters (https:/go.microsoft.com/fwlink/?LinkID=113216). 

#>

Set-ExecutionPolicy bypass -force
Install-Script -Name Get-AutopilotDiagnostics -Scope "AllUsers" -force

Get-AutopilotDiagnostics -CABFile "Autopilot.cab" -Online -AllSessions 
# try switch: -ShowPolicies 