

# https://www.powershellgallery.com/packages/Get-AutopilotDiagnostics
# https://oofhours.com/2020/07/12/windows-autopilot-diagnostics-digging-deeper/

# mdmdiagnosticstool.exe -area Autopilot -cab c:\autopilot.cab

#mdmdiagnosticstool.exe -area Autopilot;DeviceEnrollment;DeviceProvisioning;TPM -cab c:\temp\autopilot.cab

<#

Usage1: MDMDiagnosticsTool.exe -out <output folder path>
      * Output MDM diagnostics info only to given folder path specified in -out parameter.
      eg: MDMDiagnosticsTool.exe -out c:\temp\outputfolder

  Usage2: MDMDiagnosticsTool.exe -area <area name(s)> -cab <output cab file path>
      * Collect predefined area logs and create a log cab to given cab file.
      * Supported area name example:
          Autopilot
          DeviceProvisioning
          Tpm
      * It also supports multiple areas, separated by ';', example:
          Autopilot;DeviceEnrollment;Tpm
      * Please find all possible areas in registry under:
          HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\MdmDiagnostics\Area
      eg: MDMDiagnosticsTool.exe -area Autopilot;Tpm -cab c:\temp\AutopilotDiag.cab
  Usage3: MDMDiagnosticsTool.exe -area <area name(s)> -zip <output zip file path>
      * Collect predefined area logs and create a log zip to given zip file. Areas supported are the same as Usage2 for creating cab
  Usage4: MDMDiagnosticsTool.exe -xml <xml file of information to gather> -zip <output zip file path> -server <MDM Server to alert>
      * Collect information specified in the xml and create a log zip to given zip file.

#>

<#

Example of the CAB file content:

    AgentExecutor-20220722-141658.log
    AgentExecutor-20220728-172654.log
    AgentExecutor.log
    AutopilotConciergeFile.json
    AutopilotDDSZTDFile.json
    CertReq_enrollaik_Output.txt
    CertUtil_tpminfo_Output.txt
    ClientHealth.log
    DeviceHash_MB401346.csv
    DiagnosticLogCSP_Collector_Autopilot_2021_12_22_4_16_20.etl
    DiagnosticLogCSP_Collector_Autopilot_2021_12_22_4_19_19.etl
    DiagnosticLogCSP_Collector_Autopilot_2021_12_22_4_39_26.etl
    DiagnosticLogCSP_Collector_Autopilot_2021_12_22_4_42_18.etl
    DiagnosticLogCSP_Collector_DeviceEnrollment_2021_12_22_4_31_55.etl
    DiagnosticLogCSP_Collector_DeviceEnrollment_2021_12_22_4_57_5.etl
    DiagnosticLogCSP_Collector_DeviceProvisioning_2022_2_24_16_42_27.etl.merged
    DiagnosticLogCSP_Collector_DeviceProvisioning_2022_7_26_21_6_26.etl
    DiagnosticLogCSP_Collector_DeviceProvisioning_2022_7_29_10_46_56.etl
    DiagnosticLogCSP_Collector_DeviceProvisioning_2022_8_1_12_32_21.etl
    DiagnosticLogCSP_Collector_DeviceProvisioning_2022_8_3_11_9_27.etl
    IntuneManagementExtension-20220803-110145.log
    IntuneManagementExtension-20220803-134049.log
    IntuneManagementExtension.log
    LicensingDiag.cab
    LicensingDiag_Output.txt
    MDMDiagHtmlReport.html
    MdmDiagLogMetadata.json
    MDMDiagReport.xml
    MdmDiagReport_RegistryDump.reg
    MdmLogCollectorFootPrint.txt
    microsoft-windows-aad-operational.evtx
    microsoft-windows-appxdeploymentserver-operational.evtx
    microsoft-windows-assignedaccess-admin.evtx
    microsoft-windows-assignedaccess-operational.evtx
    microsoft-windows-assignedaccessbroker-admin.evtx
    microsoft-windows-assignedaccessbroker-operational.evtx
    microsoft-windows-crypto-ncrypt-operational.evtx
    microsoft-windows-devicemanagement-enterprise-diagnostics-provider-admin.evtx
    microsoft-windows-devicemanagement-enterprise-diagnostics-provider-debug.evtx
    microsoft-windows-devicemanagement-enterprise-diagnostics-provider-operational.evtx
    microsoft-windows-moderndeployment-diagnostics-provider-autopilot.evtx
    microsoft-windows-moderndeployment-diagnostics-provider-managementservice.evtx
    microsoft-windows-provisioning-diagnostics-provider-admin.evtx
    microsoft-windows-shell-core-operational.evtx
    microsoft-windows-user device registration-admin.evtx
    Sensor-20220624-152543.log
    Sensor-20220720-002439.log
    Sensor.log
    setupact.log
    TpmHliInfo_Output.txt

#>



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