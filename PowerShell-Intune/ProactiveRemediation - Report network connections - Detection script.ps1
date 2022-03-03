
# many thanks to https://www.powershellgallery.com/packages/WifiTools/
# 2022-03-02 Lubos - Script reports which networks are connected Wireless/Wired/VPN and if applicable, name of active wireless connection profile


try {

    #Get Connection Type
    $WirelessConnected = $null
    $WiredConnected = $null
    $VPNConnected = $null

    # Detecting PowerShell version, and call the best cmdlets
    if ($PSVersionTable.PSVersion.Major -gt 2)
    {
        # Using Get-CimInstance for PowerShell version 3.0 and higher
        $WirelessAdapters =  Get-CimInstance -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
            'NdisPhysicalMediumType = 9'
        $WiredAdapters = Get-CimInstance -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
            "NdisPhysicalMediumType = 0 and `
            (NOT InstanceName like '%pangp%') and `
            (NOT InstanceName like '%cisco%') and `
            (NOT InstanceName like '%juniper%') and `
            (NOT InstanceName like '%vpn%') and `
            (NOT InstanceName like 'Hyper-V%') and `
            (NOT InstanceName like 'VMware%') and `
            (NOT InstanceName like 'VirtualBox Host-Only%')"
        $ConnectedAdapters =  Get-CimInstance -Class win32_NetworkAdapter -Filter `
            'NetConnectionStatus = 2'
        $VPNAdapters =  Get-CimInstance -Class Win32_NetworkAdapterConfiguration -Filter `
            "Description like '%pangp%' `
            or Description like '%cisco%'  `
            or Description like '%juniper%' `
            or Description like '%vpn%'"
    }
    else
    {
        # Needed this script to work on PowerShell 2.0 (don't ask)
        $WirelessAdapters = Get-WmiObject -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
            'NdisPhysicalMediumType = 9'
        $WiredAdapters = Get-WmiObject -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
            "NdisPhysicalMediumType = 0 and `
            (NOT InstanceName like '%pangp%') and `
            (NOT InstanceName like '%cisco%') and `
            (NOT InstanceName like '%juniper%') and `
            (NOT InstanceName like '%vpn%') and `
            (NOT InstanceName like 'Hyper-V%') and `
            (NOT InstanceName like 'VMware%') and `
            (NOT InstanceName like 'VirtualBox Host-Only%')"
        $ConnectedAdapters = Get-WmiObject -Class win32_NetworkAdapter -Filter `
            'NetConnectionStatus = 2'
        $VPNAdapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter `
            "Description like '%pangp%' `
            or Description like '%cisco%'  `
            or Description like '%juniper%' `
            or Description like '%vpn%'"
    }


    Foreach($Adapter in $ConnectedAdapters) {
        If($WirelessAdapters.InstanceName -contains $Adapter.Name)
        {
            $WirelessConnected = $true
        }
    }

    Foreach($Adapter in $ConnectedAdapters) {
        If($WiredAdapters.InstanceName -contains $Adapter.Name)
        {
            $WiredConnected = $true
        }
    }

    Foreach($Adapter in $ConnectedAdapters) {
        If($VPNAdapters.Index -contains $Adapter.DeviceID)
        {
            $VPNConnected = $true
        }
    }

    If(($WirelessConnected -ne $true) -and ($WiredConnected -eq $true)){ $ConnectionType="WIRED"}
    If(($WirelessConnected -eq $true) -and ($WiredConnected -eq $true)){$ConnectionType="WIRED AND WIRELESS"}
    If(($WirelessConnected -eq $true) -and ($WiredConnected -ne $true)){$ConnectionType="WIRELESS"}
    If($VPNConnected -eq $true){$ConnectionType="VPN"}
    

    ### Getting WiFi profile details ###

    class WiFiState
                                                    {
    [string]$IPv4Address
    [string]$IPv6Address
    [string]$SSID
    [string]$BSSID
    [string]$State
    [string]$Authentication
    [string]$Channel
    [string]$Signal
    [string]$RxRate
    [string]$TxRate
    [string]$Profile
    [datetime]$StateTime
    }

    $FullStat=$(netsh wlan show interfaces)
    $FullStat=$FullStat.split("`n")

    [WifiState]$CurrentState=[WiFiState]::new()

    foreach($nextLine in $FullStat) {

           # https://regex101.com/ - best regex tool ever
            if($nextLine -match "^\s*State\s*:\s(.*)"){ $CurrentState.State=$Matches[1] }
            if($nextLine -match "^\s*Profile\s*:\s(.*)"){ $CurrentState.Profile=$Matches[1] }
            
            <#
            # https://regex101.com/ - best regex tool ever
            if($nextLine -match "^\s*SSID\s*:\s(.*)"){ $CurrentState.State=$Matches[1] }
            if($nextLine -match "^ SSID\s{10,35}:\s(.*)"){$CurrentState.SSID=$Matches[1]}
            if($nextLine -match "^ BSSID\s{10,35}:\s(.*)"){$CurrentState.BSSID=$Matches[1]}
            if($nextLine -match "^ Authentication\s{5,35}:\s(.*)"){$CurrentState.Authentication=$Matches[1]}
            if($nextLine -match "^ Channel\s{10,35}:\s(.*)"){$CurrentState.Channel=$Matches[1]}
            if($nextLine -match "^ Signal\s{10,35}:\s(.*)"){$CurrentState.Signal=$Matches[1]}
            if($nextLine -match "^ Receive\srate\s\(Mbps\)\s{2,15}:\s(.*)"){$CurrentState.RxRate=$Matches[1]}
            if($nextLine -match "^ Transmit\srate\s\(Mbps\)\s{2,15}:\s(.*)"){$CurrentState.TxRate=$Matches[1]}
            #>
    }


        If($WirelessConnected -ne $true) {$WirelessConnected = $false}
        If($WiredConnected -ne $true) {$WiredConnected = $false}
        If($VPNConnected -ne $true) {$VPNConnected = $false}
    
        #if ($CurrentState.State -eq "connected") { Write-Host "Wireless profile: $($CurrentState.Profile)" }
        if($CurrentState.Profile -eq $null) { $CurrentState.Profile = "(none)" }

        Write-Host "Wireless: $($WirelessConnected); Wired: $($WiredConnected); VPN: $($VPNConnected); Wireless profile: $($CurrentState.Profile)"

}
catch {
    Write-Host -Message $_
}

exit 0