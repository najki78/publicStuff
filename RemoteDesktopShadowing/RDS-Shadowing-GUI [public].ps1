#Requires -RunAsAdministrator

Clear-Host 

# cleanup variables - https://stackoverflow.com/questions/17678381/powershell-remove-all-variables
Get-Variable -Exclude PWD,*Preference,psEditor | Remove-Variable -ErrorAction SilentlyContinue

# cleanup error messages
$error.Clear();
#removing jobs, if any
Get-Job | Remove-Job -Force

$version = "2023.01.09.1"
$companyName = "YourCompany"

<#

# Convert to EXE
Install-Module ps2exe -force
# https://github.com/MScholtes/PS2EXE
Invoke-ps2exe "RDS-Shadowing-GUI [public].ps1" -requireAdmin -DPIAware -credentialGUI -title "Remote Desktop Services Shadowing GUI" -company $companyName -version $version 
# these parameters require .config file: -longPaths -winFormsDPIAware 
# and -noConsole causes some issues when running the file

#>

# the core GUI created by https://chat.openai.com/chat - wow!

if ($(whoami -user) -match "S-1-5-18"){ # that means, running as SYSTEM
    # Wait for Enter (other keypress methods did not work for me)
    Read-Host "`r`nThe program cannot run in the SYSTEM context. Press Enter to exit" # it does not make sense, SYSTEM does not have remote machine permissions
    Exit 1
}

Write-Output "Note: Keep the console window open."

# DNS suffixes for device search 
$domain1 = ".mydomain.com" 
$domain2 = ".myotherdomain.com" 

if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript")
 { $ScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition }
 else
 { $ScriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0]) 
     if (!$ScriptPath){ $ScriptPath = "." } }

New-PSDrive -Name HKU  -PSProvider Registry -Root HKEY_USERS -erroraction silentlycontinue | out-null
New-PSDrive -Name HKCU -PSProvider Registry -Root HKEY_CURRENT_USER -erroraction silentlycontinue | out-null

# https://community.spiceworks.com/scripts/show/4408-get-logged-in-users-remote-computers-or-local
function Get-LoggedInUser
{
<#
    .SYNOPSIS
        Shows all the users currently logged in

    .DESCRIPTION
        Shows the users currently logged into the specified computernames

    .PARAMETER ComputerName
        One or more computernames

    .EXAMPLE
        PS C:\> Get-LoggedInUser
        Shows the users logged into the local system

    .EXAMPLE
        PS C:\> Get-LoggedInUser -ComputerName server1,server2,server3
        Shows the users logged into server1, server2, and server3

    .EXAMPLE
        PS C:\> Get-LoggedInUser  | where idletime -gt "1.0:0" | ft
        Get the users who have been idle for more than 1 day.  Format the output
        as a table.

        Note the "1.0:0" string - it must be either a system.timespan datatype or
        a string that can by converted to system.timespan.  Examples:
            days.hours:minutes
            hours:minutes
#>

    [CmdletBinding()]
    param
    (
        [ValidateNotNullOrEmpty()]
        [String[]]$ComputerName = $env:COMPUTERNAME,
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    $out = @()

    ForEach ($computer in $ComputerName)
    {
        try { if (-not (Test-Connection -ComputerName $computer -Quiet -Count 1 -ErrorAction Stop)) { Write-Warning "Can't connect to $computer"; continue } }
        catch { Write-Warning "Can't test connect to $computer"; continue }

        $quserOut = quser.exe /SERVER:$computer 2>&1
        if ($quserOut -match "No user exists")
        { Write-Warning "No users logged in to $computer";  continue }

        $users = $quserOut -replace '\s{2,}', ',' |
        ConvertFrom-CSV -Header 'username', 'sessionname', 'id', 'state', 'idleTime', 'logonTime' |
        Add-Member -MemberType NoteProperty -Name ComputerName -Value $computer -PassThru

        $users = $users[1..$users.count]

        for ($i = 0; $i -lt $users.count; $i++)
        {
            if ($users[$i].sessionname -match '^\d+$')
            {
                $users[$i].logonTime = $users[$i].idleTime
                $users[$i].idleTime = $users[$i].STATE
                $users[$i].STATE = $users[$i].ID
                $users[$i].ID = $users[$i].SESSIONNAME
                $users[$i].SESSIONNAME = $null
            }

            # cast the correct datatypes
            $users[$i].ID = [int]$users[$i].ID

            $idleString = $users[$i].idleTime
            if ($idleString -eq '.') { $users[$i].idleTime = 0 }

            # if it's just a number by itself, insert a '0:' in front of it. Otherwise [timespan] cast will interpret the value as days rather than minutes
            if ($idleString -match '^\d+$')
            { $users[$i].idleTime = "0:$($users[$i].idleTime)" }

            # if it has a '+', change the '+' to a colon and add ':0' to the end
            if ($idleString -match "\+")
            {
                $newIdleString = $idleString -replace "\+", ":"
                $newIdleString = $newIdleString + ':0'
                $users[$i].idleTime = $newIdleString
            }

          ###  $users[$i].idleTime = [timespan]$users[$i].idleTime
            #$users[$i].logonTime = [datetime]$users[$i].logonTime
        }
        $users = $users | Sort-Object -Property idleTime
        $out += $users
    }
    Write-Output $out
}

#check if running under SYSTEM, if yes, quit ...

$whoami = $env:username
if(-not $whoami) { 
    
    $whoami = whoami
            
    if(-not $whoami) { $whoami = (Get-LoggedInUser).username } 

}


# https://call4cloud.nl/2020/03/how-to-deploy-hkcu-changes-while-blocking-powershell/
try {

    $sid = (New-Object System.Security.Principal.NTAccount($whoami)).Translate([System.Security.Principal.SecurityIdentifier]).value
    $registryPath = "HKU:\$sid\SOFTWARE\$companyName\RemoteDesktopShadowing"

} catch { 
    $registryPath = "HKCU:\SOFTWARE\$companyName\RemoteDesktopShadowing" # change for public version> $registryPath = "HKCU:\SOFTWARE\RemoteDesktopShadowing" 
}

$registryName = "TargetDevices"


Function port-scan-tcp {

    [CmdletBinding()]
    param
    (
        [ValidateNotNullOrEmpty()][string]$target,
        [ValidateNotNullOrEmpty()][int[]]$ports
    )

    Remove-Variable -Name result -ErrorAction SilentlyContinue
    Remove-Variable -Name port -ErrorAction SilentlyContinue
        
    try {
    
        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-connection?view=powershell-5.1#example-5-run-a-test-as-a-background-job

        # Loop through each port in the list and test if it is open
        foreach ($port in $ports) {
            $result = Test-NetConnection -ComputerName $target -Port $port -InformationLevel Quiet -ErrorAction SilentlyContinue # -InformationLevel Quiet ... it speeds things up a bit
            if ($result.TcpTestSucceeded) {
                Write-Output "`r`nPort $port is open on $target."
            } else {
                Write-Output "`r`nPort $port is blocked on $target."
            }
        }

    } catch {
        Write-Warning $_.Exception.Message
    }
    
}



Function retrieveMultistringValueFromRegistry {

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$registryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$registryName
    )

    Remove-Variable -Name registryValue -ErrorAction SilentlyContinue
    Remove-Variable -Name output -ErrorAction SilentlyContinue

    $output = @()

    try {

        $registryValue = ((Get-ItemProperty -Path $registryPath -Name $registryName -ErrorAction Stop).$registryName)

        if ($registryValue.Count -gt 0) { 
            $output += $registryValue | Where-Object {$_}   #### always use += when adding to arrays ... https://docs.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-arrays
        }

    } catch {
       # Write-Warning $_.Exception.Message
    }

    return ($output | Select-Object $_ -Unique)

}


Function addMultistringValueToRegistry {

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$registryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$registryName,
        [Parameter(Mandatory = $false)][string[]]$registryValue = @(), # must be [], otherwise it will not save it as REG_MULTI_SZ
        [Parameter(Mandatory = $false)][switch]$saveAsSorted = $false
    )

    Remove-Variable -Name registryValueToReplace -ErrorAction SilentlyContinue
    Remove-Variable -Name item -ErrorAction SilentlyContinue

    $registryValueToReplace = @()
    
    $registryValueToReplace = $registryValue

    $registryValueToReplace = $registryValueToReplace | Where-Object { $_ -and $_.Trim() } | select $_ -Unique # removing empty strings entirely and using only unique values

    if($saveAsSorted) { $registryValueToReplace = $registryValueToReplace | Sort-Object $_ }
    
    # check if key exists, if not, create it
    try {
        IF(!(Test-Path $registryPath -ErrorAction Stop)) { New-Item -Path $registryPath -Force | Out-Null }
    } catch {
        New-Item -Path $registryPath -Force -ErrorAction SilentlyContinue | Out-Null 
       # Write-Warning $_.Exception.Message
    }

    try {
        # always use New-ItemProperty to ensure REG_MULTI_SZ value is created, if REG_SZ is created, it causes a mess (all functionality stops working)
        New-ItemProperty -Path $registryPath -Name $registryName -Value $registryValueToReplace -PropertyType Multistring -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null 
        #Set-ItemProperty -Path $registryPath -Name $registryName -Value $registryValueToReplace -Force -Confirm:$false -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning $_.Exception.Message
    }

    # return ($output | )
}


Function resolveToIP {

    [CmdletBinding()]
    param
    (
        [ValidateNotNullOrEmpty()][string]$compName
    )

    Remove-Variable -Name ipAddy -ErrorAction SilentlyContinue

    nbtstat /R | Out-Null 
    Clear-DnsClientCache # ipconfig -flushdns | Out-Null

    try {
        $ipAddy = [System.Net.Dns]::GetHostAddresses($compName)[0].IPAddressToString
    } catch {
    
        try { # maybe only NetBIOS name entered, try to add $domain1 
            $compName = $compName.Split(".")[0] + $domain1 
            $ipAddy = [System.Net.Dns]::GetHostAddresses($compName)[0].IPAddressToString
        } catch {

            try { # maybe only NetBIOS name entered, try to add $domain2
                $compName = $compName.Split(".")[0] + $domain2
                $ipAddy = [System.Net.Dns]::GetHostAddresses($compName)[0].IPAddressToString
            } catch {
                #Write-Host $_ -ForegroundColor Red
                 # Write-Warning $_.Exception.Message
            }

        }
    }

    if( ($ipAddy -eq "::1") -or ($ipAddy -eq "127.0.0.1") ) {
        #Write-Host "You cannot shadow your own session. Exiting." -foregroundcolor red
        return "localhost"
    }

    if(-not $ipAddy) {
        #Write-Host "No IP address found in DNS for $($compName). Connection not possible. Exiting." -foregroundcolor red
        return $null
    }

    return $ipAddy

}

##### GUI ######


# Load assembly
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

# https://learn.microsoft.com/en-us/powershell/scripting/samples/creating-a-custom-input-box?view=powershell-5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing


function InputBox {

    [CmdletBinding()]
    param
    (
        [ValidateNotNullOrEmpty()][String[]]$displayText = "Please enter the information in the space below:",
        [ValidateNotNullOrEmpty()][String[]]$headerText = "Data Entry Form",
        [Parameter(Mandatory = $false)][string]$defaultText = $null # the value that will be pre-filled in a text box
    )
    
    Remove-Variable -Name x -ErrorAction SilentlyContinue
    Remove-Variable -Name objForm -ErrorAction SilentlyContinue
    Remove-Variable -Name objTextBox -ErrorAction SilentlyContinue
    Remove-Variable -Name OKButton -ErrorAction SilentlyContinue
    Remove-Variable -Name CancelButton -ErrorAction SilentlyContinue
    Remove-Variable -Name objLabel -ErrorAction SilentlyContinue
    Remove-Variable -Name result -ErrorAction SilentlyContinue
    
    $objForm = New-Object System.Windows.Forms.Form
    $objForm.Text = $headerText 
    $objForm.Size = New-Object System.Drawing.Size(300,200)
    $objForm.StartPosition = "CenterScreen"

    $objForm.KeyPreview = $True
    $objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") { $objForm.Close()}})
    $objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") { if($defaultText) { $objTextBox.Text = $null }; $objForm.Close()}})

    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Location = New-Object System.Drawing.Size(75,120)
    $OKButton.Size = New-Object System.Drawing.Size(75,23)
    $OKButton.Text = "OK"
    $OKButton.Add_Click({$objForm.Close()})
    $objForm.Controls.Add($OKButton)

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Location = New-Object System.Drawing.Size(150,120)
    $CancelButton.Size = New-Object System.Drawing.Size(75,23)
    $CancelButton.Text = "Cancel"
    $CancelButton.Add_Click({ if($defaultText) { $objTextBox.Text = $null }; $objForm.Close() })
    $objForm.Controls.Add($CancelButton)

    $objLabel = New-Object System.Windows.Forms.Label
    $objLabel.Location = New-Object System.Drawing.Size(10,20)
    $objLabel.Size = New-Object System.Drawing.Size(280,20)
    $objLabel.Text = $displayText 
    $objForm.Controls.Add($objLabel)

    $objTextBox = New-Object System.Windows.Forms.TextBox
    $objTextBox.Location = New-Object System.Drawing.Size(10,40)
    $objTextBox.Size = New-Object System.Drawing.Size(260,20)

    if($defaultText) { $objTextBox.Text = $defaultText }

    $objForm.Controls.Add($objTextBox)

    $objForm.Topmost = $True

    $objForm.Add_Shown({$objForm.Activate()})
    [void] $objForm.ShowDialog()

    $objTextBox.Text # this is what the function returns
    
} 


function InputBoxListView {

    [OutputType([String[]])]  # function returns an array of strings
    [CmdletBinding()]
    param   # [ValidateNotNullOrEmpty()]
    (
        [Parameter(Mandatory = $false)][String[]]$displayDevice = "Please enter the device name in the space below:",
        [Parameter(Mandatory = $false)][String[]]$displayDescription = "Please enter the device description in the space below:",
        [Parameter(Mandatory = $false)][String[]]$headerText = "Data Entry Form",
        [Parameter(Mandatory = $false)][string]$defaultDevice = $null, # the value that will be pre-filled in a text box
        [Parameter(Mandatory = $false)][string]$defaultDescription = $null # the value that will be pre-filled in a text box
    )
    
    Remove-Variable -Name x -ErrorAction SilentlyContinue
    Remove-Variable -Name objForm -ErrorAction SilentlyContinue
    Remove-Variable -Name objTextBox -ErrorAction SilentlyContinue
    Remove-Variable -Name OKButton -ErrorAction SilentlyContinue
    Remove-Variable -Name CancelButton -ErrorAction SilentlyContinue
    Remove-Variable -Name objLabel -ErrorAction SilentlyContinue
    Remove-Variable -Name result -ErrorAction SilentlyContinue
    
    $objForm = New-Object System.Windows.Forms.Form
    $objForm.Text = $headerText 
    $objForm.Size = New-Object System.Drawing.Size(300,220)
    $objForm.StartPosition = "CenterScreen"

    $objForm.KeyPreview = $True

    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Location = New-Object System.Drawing.Size(75,130)
    $OKButton.Size = New-Object System.Drawing.Size(75,23)
    $OKButton.Text = "OK"
    $OKButton.Add_Click({ $objForm.Close()})
    $objForm.Controls.Add($OKButton)

    $objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") { $objForm.Close()}})


    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Location = New-Object System.Drawing.Size(150,130)
    $CancelButton.Size = New-Object System.Drawing.Size(75,23)
    $CancelButton.Text = "Cancel"
    $CancelButton.Add_Click({ $objTextDevice.Text = $null; $objTextDescription.Text = $null; $objForm.Close() })   # { if($defaultDevice) { $objTextDevice.Text = $null }; $objForm.Close() }
    $objForm.Controls.Add($CancelButton)

    $objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") {  $objTextDevice.Text = $null; $objTextDescription.Text = $null; $objForm.Close()   }})

    $objLabel1 = New-Object System.Windows.Forms.Label
    $objLabel1.Location = New-Object System.Drawing.Size(10,20)
    $objLabel1.Size = New-Object System.Drawing.Size(280,20)
    $objLabel1.Text = $displayDevice 
    $objForm.Controls.Add($objLabel1)

    $objTextDevice = New-Object System.Windows.Forms.TextBox
    $objTextDevice.Location = New-Object System.Drawing.Size(10,40)
    $objTextDevice.Size = New-Object System.Drawing.Size(260,20)
    if($defaultDevice) { $objTextDevice.Text =  $defaultDevice }
    $objForm.Controls.Add($objTextDevice)
  
    $objLabel2 = New-Object System.Windows.Forms.Label
    $objLabel2.Location = New-Object System.Drawing.Size(10,(20+50))
    $objLabel2.Size = New-Object System.Drawing.Size(280,20)
    $objLabel2.Text = $displayDescription
    $objForm.Controls.Add($objLabel2)

    $objTextDescription = New-Object System.Windows.Forms.TextBox
    $objTextDescription.Location = New-Object System.Drawing.Size(10,(40+30+20))
    $objTextDescription.Size = New-Object System.Drawing.Size(260,20)
    if($defaultDescription) { $objTextDescription.Text =  $defaultDescription }
    $objForm.Controls.Add($objTextDescription)

    $objForm.Topmost = $True

    $objForm.Add_Shown({$objForm.Activate()})
    [void] $objForm.ShowDialog()

    return @($objTextDevice.Text,$objTextDescription.Text) # this is what the function returns
    
} 


function AppendToTextBox1 {

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)][String]$displayText = "",
        [Parameter(Mandatory = $false)][switch]$addEmptyLine
    )

    $textbox1.AppendText($displayText); 
    $textbox1.AppendText("`r`n")
    if($addEmptyLine) { $textbox1.AppendText("`r`n") } 
    
}


# Message Box: https://michlstechblog.info/blog/powershell-show-a-messagebox/

$sizeMargin = 10 # pixels between elements, both X and Y

$sizeSmallButtonX = 115 # size of small button X - was 85

$sizeLBX = (3*$sizeSmallButtonX) + (2*$sizeMargin) # X - listView with devices, width
$sizeTBX = 2 * $sizeLBX  # X - textBox with output, width ... was 3*$sizeLBX
$sizeFormX = ($sizeMargin + $sizeLBX + $sizeMargin + $sizeTBX + (2*$sizeMargin))

$sizeSmallButtonY = 30 # size of small button Y

$sizeLBY = 350 # was 350

$sizeTBY = $sizeLBY + (2*$sizeMargin) + (2*$sizeSmallButtonY)
$sizeFormY = (5*$sizeMargin) + $sizeTBY 


# Create a new form
$form = New-Object System.Windows.Forms.Form

# Set the form properties
$form.Text = "Remote Desktop Services Shadowing - version: $($version) - logged on as '$($whoami)'"
$form.Size = New-Object System.Drawing.Size($sizeFormX,$sizeFormY)
$form.FormBorderStyle = 'FixedDialog' # or 'FixedDialog' - non resizeable
$form.StartPosition = "CenterScreen"
#$form.backcolor = "lightgray"

# Create a timer to check the status of the jobs
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
#$timer.Enabled = $false

# Create a variable to store the background jobs
$global:jobs = @()

# Create the ListView (multi-column)
# https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.listview?view=windowsdesktop-7.0
$listView = New-Object System.Windows.Forms.ListView 
$listView.Location = New-Object System.Drawing.Point($sizeMargin,$sizeMargin)
$listView.Size = New-Object System.Drawing.Size($sizeLBX,$sizeLBY)
$listView.View = [System.Windows.Forms.View]::Details
$listView.LabelEdit = $false # ???
$listView.HideSelection = $false # ???
$listView.FullRowSelect = $true
$listView.Scrollable = $true
$listView.Columns.Add('Device')
$listView.Columns.Add('Description')
$listView.GridLines = $true
$listView.MultiSelect = $false
$listView.AllowColumnReorder = $true
$listView.Sorting = 1 # Ascending - https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.listview.sorting?view=windowsdesktop-7.0

$form.Controls.Add($listView) | Out-Null

#######################################################################################################################
# https://social.technet.microsoft.com/forums/scriptcenter/en-US/553f06bc-522c-4854-9e28-d0e219a789a6/powershell-and-systemwindowsformslistview?prof=required
# double click on the column name sorts list view by the given column (only ascending, not descending sort)

# This is the custom comparer class string
# copied from the MSDN article

$comparerClassString = @"

  using System;
  using System.Windows.Forms;
  using System.Drawing;
  using System.Collections;

  public class ListViewItemComparer : IComparer
  {
    private int col;
    public ListViewItemComparer()
    {
      col = 0;
    }
    public ListViewItemComparer(int column)
    {
      col = column;
    }
    public int Compare(object x, object y)
    {
      return String.Compare(
        ((ListViewItem)x).SubItems[col].Text, 
        ((ListViewItem)y).SubItems[col].Text);
    }
  }

"@

# Add the comparer class
Add-Type -TypeDefinition $comparerClassString -ReferencedAssemblies ('System.Windows.Forms', 'System.Drawing')


# Add the event to the ListView ColumnClick event
$columnClick = {  $listView.ListViewItemSorter = New-Object ListViewItemComparer($_.Column) }
$listView.Add_ColumnClick($columnClick)



#######################################################################################################################

# add as initial values to the ListView
retrieveMultistringValueFromRegistry -registryPath $registryPath -registryName $registryName | ForEach-Object { 

    $tmpRegistryValue = $_
    $tmpIndexOfDelimiter = if ( $tmpRegistryValue.IndexOf(";") -lt 0) { $tmpRegistryValue.Length } else { $tmpRegistryValue.IndexOf(";") }
    $tmpStartOfDescription = if (($tmpIndexOfDelimiter + 1) -gt $tmpRegistryValue.Length) { $tmpRegistryValue.Length  }  else { $tmpIndexOfDelimiter + 1 }
    $tmpLengthOfDescription = if(($tmpRegistryValue.Length - $tmpStartOfDescription) -gt 0) { $tmpRegistryValue.Length - $tmpStartOfDescription } else { 0 }

    # delimiter ;
    $tmpDevice      = ($tmpRegistryValue.substring(0,$tmpIndexOfDelimiter)) -replace("\s+",'')
    $tmpDescription = $tmpRegistryValue.substring($tmpStartOfDescription, $tmpLengthOfDescription)

    $tmpListViewItem = New-Object System.Windows.Forms.ListViewItem("$tmpDevice") -ErrorAction SilentlyContinue
    $tmpListViewItem.SubItems.Add("$tmpDescription") | Out-Null
    $listView.Items.AddRange($tmpListViewItem)

    $listView.AutoResizeColumns(2)  # base width on content length - https://stackoverflow.com/questions/53629916/how-to-automatically-resize-columns-in-a-listview

}

# Create the first text box
$textBox1 = New-Object System.Windows.Forms.TextBox
$textBox1.Location = New-Object System.Drawing.Point(($sizeMargin + $sizeLBX + $sizeMargin),$sizeMargin)
$textBox1.Size = New-Object System.Drawing.Size($sizeTBX,$sizeTBY)
$textBox1.Multiline = $true
$textBox1.ScrollBars = 'Vertical'
$textBox1.ReadOnly = $true
$textBox1.Visible = $true

# Add the text box to the form
$form.Controls.Add($textBox1)

# Create a button to add a new device
$addButton = New-Object System.Windows.Forms.Button
$addButton.Location = New-Object System.Drawing.Point($sizeMargin,((2*$sizeMargin)+$sizeLBY)) #(2*$sizeMargin+$sizeLBY)
$addButton.Size = New-Object System.Drawing.Size($sizeSmallButtonX,$sizeSmallButtonY)
$addButton.Text = "Add"

# Add an event handler for the add button
$addButton.Add_Click({
    # Show a dialog to get the name of the new device
    
    Remove-Variable -Name tmpOutput -ErrorAction SilentlyContinue
    Remove-Variable -Name tmpDevice -ErrorAction SilentlyContinue
    Remove-Variable -Name tmpDescription -ErrorAction SilentlyContinue

    $tmpOutput = InputBoxListView -headerText "Add remote device" -displayDevice "Remote device name" -displayDescription "Remote device description" # -defaultDevice "device" -defaultDescription "description" 

    # delimiter ;
    $tmpDevice      = ($tmpOutput[0]) -replace("\s+",'')
    $tmpDescription = ($tmpOutput[1])

    if($tmpDevice) { # if not returned empty string
        # Add the device to the list

        $tmpListViewItem = New-Object System.Windows.Forms.ListViewItem("$tmpDevice")
        $tmpListViewItem.SubItems.Add("$tmpDescription")
        $listView.Items.AddRange($tmpListViewItem) | Out-Null

    }

    $listView.AutoResizeColumns(2)  # base width on content length - https://stackoverflow.com/questions/53629916/how-to-automatically-resize-columns-in-a-listview

})

# Add the add button to the form
$form.Controls.Add($addButton)

# Create a button to remove the selected device
$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Location = New-Object System.Drawing.Point((2*$sizeMargin + $sizeSmallButtonX),((2*$sizeMargin)+$sizeLBY))
$removeButton.Size = New-Object System.Drawing.Size($sizeSmallButtonX,$sizeSmallButtonY)
$removeButton.Text = "Remove"

# Add an event handler for the remove button
$removeButton.Add_Click({
    # Get the selected index
    Remove-Variable -Name index -ErrorAction SilentlyContinue

    $index =  $listView.SelectedIndices[0] # equivalent of $listView.SelectedIndex

    if ($index -ge 0) { # if there is some item selected...

        $listView.Items.RemoveAt($index)
    
    } # if ($listView.Focused) 

    $listView.AutoResizeColumns(2)  # base width on content length - https://stackoverflow.com/questions/53629916/how-to-automatically-resize-columns-in-a-listview

})

# Add the remove button to the form
$form.Controls.Add($removeButton)

# Create a button to modify the selected device
$modifyButton = New-Object System.Windows.Forms.Button
$modifyButton.Location = New-Object System.Drawing.Point((3*$sizeMargin + 2*$sizeSmallButtonX),((2*$sizeMargin)+$sizeLBY))
$modifyButton.Size = New-Object System.Drawing.Size($sizeSmallButtonX,$sizeSmallButtonY)
$modifyButton.Text = "Modify"

# Add an event handler for the modify button
$modifyButton.Add_Click({
    
    Remove-Variable -Name index -ErrorAction SilentlyContinue
    Remove-Variable -Name tmpOutput -ErrorAction SilentlyContinue
    Remove-Variable -Name tmpDevice -ErrorAction SilentlyContinue
    Remove-Variable -Name tmpDescription -ErrorAction SilentlyContinue

    # Get the selected index
    $index =  $listView.SelectedIndices[0] # equivalent of $listView.SelectedIndex

    if ($index -ge 0) { # if there is some item selected...

        $tmpOutput = InputBoxListView -headerText "Modify remote device" -displayDevice "New remote device name" -displayDescription "New remote device description" -defaultDevice "$($listView.Items[$index].Text)" -defaultDescription "$($listView.Items[$index].Subitems[1].Text)" 

        # delimiter ;
        $tmpDevice      = ($tmpOutput[0]) -replace("\s+",'')
        $tmpDescription = ($tmpOutput[1])
    
        if($tmpDevice) { # if not returned empty string
            
            # Modify the device in the list
            $listView.Items[$index].Text = $tmpDevice
            $listView.Items[$index].Subitems[1].Text = $tmpDescription
    
        }
    
    } # if ($listView.SelectedIndices)

    $listView.AutoResizeColumns(2)  # base width on content length - https://stackoverflow.com/questions/53629916/how-to-automatically-resize-columns-in-a-listview

})

# Add the modify button to the form
$form.Controls.Add($modifyButton)

# Create a button to add a new device
$troubleshootButton = New-Object System.Windows.Forms.Button
$troubleshootButton.Location = New-Object System.Drawing.Point($sizeMargin,((3*$sizeMargin)+$sizeLBY+$sizeSmallButtonY))
$troubleshootButton.Size = New-Object System.Drawing.Size($sizeLBX,$sizeSmallButtonY)
$troubleshootButton.Text = "Troubleshoot"

# Add an event handler for the troubleshoot button
$troubleshootButton.Add_Click({
  # Get the name of the selected device for troubleshoot action
        
    Remove-Variable -Name name -ErrorAction SilentlyContinue
    Remove-Variable -Name index -ErrorAction SilentlyContinue
    Remove-Variable -Name tempIPAddress -ErrorAction SilentlyContinue
    Remove-Variable -Name continue -ErrorAction SilentlyContinue

    AppendToTextBox1 -displayText "The list of devices is stored in the '$($whoami)' account's registry:`r`n$registryPath\$registryName" -addEmptyLine
    AppendToTextBox1 -displayText "Visit https://bit.ly/rds-shadowing for general information about Shadowing." -addEmptyLine
    AppendToTextBox1 -displayText "Script path: $ScriptPath" -addEmptyLine

    $index =  $listView.SelectedIndices[0] # equivalent of $listView.SelectedIndex

    if ($index -ge 0) { # if there is some item selected...

        # Get the selected index
        $name = $listView.Items[($index)].Text 

        if ($name) { # if some item from the list is selected
        
            AppendToTextBox1 -displayText "Troubleshooting connection to $name"
        
            $tempIPAddress = resolveToIP -compName $name
            $continue = $false
    
            Switch ($tempIPAddress) {
                $null { AppendToTextBox1 -displayText "No IP address found in DNS for $name.  Connection not possible."; break } # $null = no address found
                "" { AppendToTextBox1 -displayText "No IP address found in DNS for $name. Connection not possible."; break } # ""= no address 
                "localhost" { AppendToTextBox1 -displayText "You cannot shadow the session on your own device. Connection not possible."; break } # cannot shadow itself
                Default { $continue = $true; AppendToTextBox1 -displayText "Resolved IP: $tempIPAddress" ; break } # OK, some address found
            } # Switch ($tempIPAddress) ...
        
            if($continue) { # seems we have a valid IP address...
                    
                #AppendToTextBox1 -displayText "To remotely logoff remote console session (for troubleshooting purposes only): "
                #AppendToTextBox1 -displayText "logoff $($sessionID) /server:$($tempIPAddress)" -addEmptyLine
            
                AppendToTextBox1 -displayText "If Shadowing is not working, try to remotely connect using 'traditional' remote desktop connection: " 
                AppendToTextBox1 -displayText "mstsc /console /v:$($tempIPAddress)"
                AppendToTextBox1 -displayText "Note: The 'traditional' remote desktop connection is allowed only when your account '$($whoami)' is a member of Remote Desktop Users group on the remote machine."
                AppendToTextBox1 -displayText "Important: Unlike Shadowing, 'traditional' remote desktop connection will NOT be visible for the user behind the remote machine." -addEmptyLine
                
                # PING --- it mimics get-wmiobject -class win32_pingstatus
                #Test-Connection -ComputerName $compName -Count 1 | Format-Table -AutoSize -Wrap
    
                try {
                    AppendToTextBox1 -displayText "PING result: $(((New-Object System.Net.NetworkInformation.Ping).Send($tempIPAddress,1000)).Status)" -addEmptyLine
                } catch {
                    AppendToTextBox1 -displayText $_.Exception.Message -addEmptyLine
                }
                
                ##### check if the device responds or if not "Exception calling "GetHostAddresses" with "1" argument(s): "No such host is known""
                AppendToTextBox1 -displayText "Wait while collecting troubleshooting information."
    
                AppendToTextBox1 -displayText "Querying the firewall status on the target machine:" -addEmptyLine
    
                # redo to ADD the new job to the list of $jobs ... because currently we replace
                $global:jobs = Start-Job -ScriptBlock { 
    
                    Remove-Variable -Name port -ErrorAction SilentlyContinue
                    foreach ($port in @(135,445,3389) ) {
    
                        if(Test-NetConnection -ComputerName $args[0] -Port $port -InformationLevel Quiet -ErrorAction SilentlyContinue) { 
                            Write-Output "`r`nPort $($port) is Open on $($args[0])" # `r`n
                        } else {
                            Write-Output "`r`nPort $($port) is Closed on $($args[0])" # `r`n
                        }
                    } # foreach ($port in $ports)
                
                } -ArgumentList $tempIPAddress
    
                #$timer.Enabled = $true
                $timer.Start()
    
            } # if($continue)
    
        } # if ($name)
    


    } # if ($listView.SelectedIndices)

})

# Add the troubleshoot button to the form
$form.Controls.Add($troubleshootButton)

# Add an event handler for when an item in the list is clicked
$listView.Add_MouseDoubleClick({
    # Get the name of the selected device
        
    Remove-Variable -Name name -ErrorAction SilentlyContinue
    Remove-Variable -Name tempIPAddress -ErrorAction SilentlyContinue
    Remove-Variable -Name continue -ErrorAction SilentlyContinue
    Remove-Variable -Name sessionID -ErrorAction SilentlyContinue
    Remove-Variable -Name line -ErrorAction SilentlyContinue
    Remove-Variable -Name message -ErrorAction SilentlyContinue
    Remove-Variable -Name quser_command -ErrorAction SilentlyContinue
    Remove-Variable -Name index -ErrorAction SilentlyContinue

    $name = $null
    $index = $null

    # Get the selected index
    $index =  $listView.SelectedIndices[0] # equivalent of $listView.SelectedIndex

    if ($index -ge 0) { # if there is some item selected... originally $listView.Focused

        $name = $listView.Items[($index)].Text 

    } # if ($listView.SelectedIndices)

    if ($name) { # if some item from the list is selected
        
        AppendToTextBox1 -displayText "Selected device: $name"
    
        $sessionID = "" # default value

        $tempIPAddress = resolveToIP -compName $name

        $continue = $false

        Switch ($tempIPAddress) {
            $null { AppendToTextBox1 -displayText "No IP address found in DNS for $name. Connection not possible. Select different device."; break } # $null = no address found
            "" { AppendToTextBox1 -displayText "No IP address found in DNS for $name. Connection not possible. Select different device."; break } # ""= no address 
            "localhost" { AppendToTextBox1 -displayText "You cannot shadow session on your own device. Connection not possible. Select different device."; break } # cannot shadow itself
            Default { $continue = $true; AppendToTextBox1 -displayText "Resolved IP: $tempIPAddress" ; break } # OK, some address found
        } # Switch ($tempIPAddress) ...
    
        if($continue) { # seems we have a valid IP address...

            $continue = $false # we will need this later
            
            AppendToTextBox1 -displayText "Wait while establishing connection. The program will become unresponsive for a while."
            
            try {
    
                # Redirection https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-7.2
                
                $quser_command = [string](quser console /server:$tempIPAddress 3>&1 2>&1)
                
                AppendToTextBox1 -displayText $quser_command -addEmptyLine

                $continue = $true # continue with the next step

            } catch {
                # $_.Exception.Message 
                AppendToTextBox1 -displayText $_
            }


        } # if($continue) ...


        if($continue) { # seems we have QUERY STRING

            $continue = $false # we will need this later

            foreach ($line in ($quser_command)){
      
                if ($line.contains("console")){ 

                    # remove all before "console" string and get the next string, that should be sessionID
                    $sessionID = ($line.substring( $line.IndexOf("console"), $line.length - $line.IndexOf("console"))).split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)[1] # next value after "console"
                    
                    # check if the string is number - if yes, it is sessionID
                    if($sessionID -match "^\d+$") {  # if integer...
                        $continue = $true # continue with the next step
                        $message = "Console session ID: $sessionID"
                    }
                } 

                if ($line.contains("No User exists for console")){  
                    $message = "`r`nError: Unable to establish shadowing session.`r`nEither `r`n- there is no user logged on at the console OR`r`n- the user '$($whoami)' is not member of neither Administrators, Remote Desktop Users group(s) nor has special permissions granted on the target machine." #### ...and cannot run QUSER command - same error message it both cases "No User exists for console"
                }

                if ($line.contains("Error [1722]")){  # Error 0x000006BA enumerating sessionnames Error [1722]:The RPC server is unavailable. System.Management.Automation.RemoteException
                    $message = "`r`nError: Unable to establish shadowing session.`r`nThe console user information not retrieved.`r`nOften due to the blocked tcp/445 connection to the target machine OR the machine is shutting down / restarting.`r`nClick on 'Troubleshoot' button to perform additional checks."
                }
                
                if ($line.contains("Error [5]")) {  # Error 0x00000005 enumerating sessionnames Error [5]:Access is denied. System.Management.Automation.RemoteException
                    $message = "`r`nError: Unable to establish shadowing session.`r`nThe console user information not retrieved.`r`n`r`nThis happens often due to:`r`n- the blocked tcp/445 connection to the target machine OR`r`n- the machine is shutting down / restarting OR`r`n- the user you are logged in does not have required permission to the target machine OR `r`n- Remote Desktop Shadowing is not configured properly on the target machine."
                }
    
            } 

            AppendToTextBox1 -displayText $message -addEmptyLine
            
        } # if($continue) ...

        if($continue) { # seems we have SESSIO ID

            $continue = $false # we will need this later

            $message = "`r`nError: Unable to establish shadowing session.`r`nEither`r`n- there is no user logged on at the console OR`r`n- the user has not been detected.`r`nThis occurs mostly due to the blocked connection to the target machine."
            
            if ($sessionID) {
                                
                Start-Process "$($env:windir)\system32\mstsc.exe" -ArgumentList "/v:$($tempIPAddress) /control /noconsentprompt /span /shadow:$($sessionID)" -WindowStyle Hidden # Hidden - allows to have GUI still responsive after opening Shadoing session

            } else {
                AppendToTextBox1 -displayText $message
            }

        } # if($continue) ...

    }

})

# Set up an event handler for the timer tick event
$timer.Add_Tick({
    # Check the status of the jobs
    Remove-Variable -Name completedJobs -ErrorAction SilentlyContinue
    $completedJobs = Get-Job | Where-Object { $_.State -eq 'Completed' }
    
    # Display the results of the completed jobs
    Remove-Variable -Name job -ErrorAction SilentlyContinue
    foreach ($job in $completedJobs) {
        
     #   Write-Host "TIMER - ForEach Job:" $Job.Name

        $form.Invoke(([System.Action]$(
            {

                if( ($job | Receive-Job -Keep) ) { AppendToTextBox1 -displayText "$($job | Receive-Job -Wait -AutoRemoveJob)" } 
                                
            }
        )))
    } # foreach ($job in $completedJobs)

    # Remove the completed jobs from the list
    
    $global:jobs = $global:jobs | Where-Object { $completedJobs -notcontains $_ }

    # Stop the timer if all jobs have completed
    if ($global:jobs.Count -eq 0) {
        $timer.Stop()
        # Display a message indicating that the pings have finished
        # $form.Invoke(([System.Action]$( { $textBox.AppendText("All pings have completed.") } )))
    }


})


#### https://akaplan.com/2016/05/move-selected-item-up-or-down-in-powershell-listbox/

AppendToTextBox1 -displayText "Note: Keep the console window, that started the application, open." -addEmptyLine

# Show the form
[void] $form.ShowDialog()

# update list of devices in the registry
$tempArray = @()

if($listView.Items.Count -gt 0) { 
    ForEach ($item in $listView.Items) { 
        $tempArray += ($item.SubItems[0].Text + ";" + $item.SubItems[1].Text)
    }
}
addMultistringValueToRegistry -registryPath $registryPath -registryName $registryName -registryValue $tempArray # -saveAsSorted

# just in case...
$timer.Stop()
$timer.Dispose()