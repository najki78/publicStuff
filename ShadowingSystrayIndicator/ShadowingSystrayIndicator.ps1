<# 

 Description: Monitor if the current console session is being shadowed (Remote desktop services Shadowing)
 Author: Lubos Nikolini
 Wiki: https://github.com/najki78/publicStuff/wiki/Remote-desktop-shadowing-is-Microsoft's-free-alternative-to-VNC,-TeamViewer,-DameWare-etc.-(well,-sort-of-and-only-sometimes)
 
 Instructions:
    Run the script under user account logged on the device that is being shadowed. 

 Version history:

    2022-10-12B Initial version
    2022-10-13A tidying up a bit
    2022-10-18A
        
#> 

<#
# Convert to EXE file by running
# https://github.com/MScholtes/PS2EXE
Install-Module ps2exe
Invoke-ps2exe "ShadowingSystrayIndicator.ps1"
#>

$version = "2024.01.22.01"

# https://stackoverflow.com/questions/59349635/change-tray-icon-based-on-event?rq=1

cls

# if the EXE is already running, do not start 2nd or more instances
if (Get-Process -Name 'ShadowingSystrayIndicator' -ErrorAction SilentlyContinue) { exit }

### list of icons - https://diymediahome.org/windows-icons-reference-list-with-details-locations-images/

# https://renenyffenegger.ch/notes/Windows/PowerShell/examples/WinAPI/ExtractIconEx
$null = [Reflection.Assembly]::LoadWithPartialName('System.Drawing');
$null = [Reflection.Assembly]::LoadWithPartialName('System.Drawing.Imaging');
[System.IntPtr] $phiconSmall = 0
[System.IntPtr] $phiconLarge = 0
#
#   https://stackoverflow.com/questions/6872957/how-can-i-use-the-images-within-shell32-dll-in-my-c-sharp-project
#
add-type -typeDefinition '

using System;
using System.Runtime.InteropServices;

public class Shell32_Extract {

  [DllImport(
     "Shell32.dll",
      EntryPoint        = "ExtractIconExW",
      CharSet           =  CharSet.Unicode,
      ExactSpelling     =  true,
      CallingConvention =  CallingConvention.StdCall)
  ]

   public static extern int ExtractIconEx(
      string lpszFile          , // Name of the .exe or .dll that contains the icon
      int    iconIndex         , // zero based index of first icon to extract. If iconIndex == 0 and and phiconSmall == null and phiconSmall = null, the number of icons is returnd
      out    IntPtr phiconLarge,
      out    IntPtr phiconSmall,
      int    nIcons
  );

}
';



# Toggle following two lines
Set-StrictMode -Version Latest
# Set-StrictMode -Off

Add-Type -AssemblyName System.Windows.Forms    
Add-Type -AssemblyName System.Drawing

function Test-RdpSa {
    [bool](Get-Process -Name 'RdpSa' -ErrorAction SilentlyContinue)  # RdpSa # requires elevated rights> -IncludeUserName ... but it does not reveal who is performing Shadowing
}


function OnMenuItem1ClickEventFn () {
    # Build Form object
    $Form = New-Object System.Windows.Forms.Form
        $Form.Text = "Remote Desktop Shadowing Indicator (refreshed every 10 seconds)"
        $Form.Size = New-Object System.Drawing.Size(200,200)
        $Form.StartPosition = "CenterScreen"
        $Form.Topmost = $True
        $Form.Controls.Add($Label)               # Add label to form
        $form.ShowDialog()| Out-Null             # Show the Form
}


function OnMenuItem4ClickEventFn () {
    $Main_Tool_Icon.Visible = $false

    [System.Windows.Forms.Application]::Exit()
}


function create_taskbar_menu{
    # Create menu items
    $MenuItem1 = New-Object System.Windows.Forms.MenuItem
    $MenuItem1.Text = "Status"

    $MenuItem4 = New-Object System.Windows.Forms.MenuItem
    $MenuItem4.Text = "Exit"

    # Add menu items to context menu
    $contextmenu = New-Object System.Windows.Forms.ContextMenu
    $Main_Tool_Icon.ContextMenu = $contextmenu
    $Main_Tool_Icon.contextMenu.MenuItems.AddRange($MenuItem1)
    $Main_Tool_Icon.contextMenu.MenuItems.AddRange($MenuItem4)

    $MenuItem4.add_Click({OnMenuItem4ClickEventFn})
    $MenuItem1.add_Click({OnMenuItem1ClickEventFn})
}


$Current_Folder = split-path $MyInvocation.MyCommand.Path

# Add assemblies for WPF and Mahapps
[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')    | out-null
[System.Reflection.Assembly]::LoadWithPartialName('presentationframework')   | out-null
[System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')          | out-null
[System.Reflection.Assembly]::LoadWithPartialName('WindowsFormsIntegration') | out-null

# [System.Reflection.Assembly]::LoadFrom("Current_Folder\assembly\MahApps.Metro.dll")  | out-null

# Choose an icon to display in the systray
#$onlineIcon = [System.Drawing.Icon]::ExtractAssociatedIcon("$Current_Folder/icons/online.ico")
 
    $dllPath = "$env:SystemRoot\System32\shell32.dll"
    $nofImages = [Shell32_Extract]::ExtractIconEx($dllPath, -1, [ref] $phiconLarge, [ref] $phiconSmall, 0)
    
    $nofIconsExtracted = [Shell32_Extract]::ExtractIconEx($dllPath, 160, [ref] $phiconLarge, [ref] $phiconSmall, 1)  # second parameter is (icon index - 1)
    $onlineIcon = [System.Drawing.Icon]::FromHandle($phiconSmall);
    
# use this icon when notepad is not running
#$offlineIcon = [System.Drawing.Icon]::ExtractAssociatedIcon("C:\Windows\System32\calc.exe")     

    #$dllPath = "$env:SystemRoot\System32\shell32.dll"
    #$nofImages = [Shell32_Extract]::ExtractIconEx($dllPath, -1, [ref] $phiconLarge, [ref] $phiconSmall, 0)
    
    $nofIconsExtracted = [Shell32_Extract]::ExtractIconEx($dllPath, 208, [ref] $phiconLarge, [ref] $phiconSmall, 1)  # second parameter is (icon index - 1)
    $offlineIcon = [System.Drawing.Icon]::FromHandle($phiconSmall);

$Main_Tool_Icon = New-Object System.Windows.Forms.NotifyIcon
$Main_Tool_Icon.Text = "Remote Desktop Shadowing Indicator"
$Main_Tool_Icon.Icon = if (Test-RdpSa) { $onlineIcon } else { $offlineIcon }
$Main_Tool_Icon.Visible = $true

# Build Label object
$Label = New-Object System.Windows.Forms.Label
    $Label.Name = "labelName"
    $Label.AutoSize = $True


#http://woshub.com/rdp-session-shadow-to-windows-10-user/

#log: 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'

#Event ID 20508 — Shadow View Permission Granted
#Event ID 20503 — Shadow View Session Started
#Event ID 20504 — Shadow View Session Stopped

#Event ID 20506 Shadow Control Session Started
#Event ID 20507 Shadow Control Session Stopped
#Event ID 20510 Shadow Control Permission Granted

# Initialize the timer
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10000 # refresh every 10 seconds
$timer.Add_Tick({
    if ($Label){

        if (Test-RdpSa) {

            $EventIds = 20506,20503
            $AllEvents = Get-WinEvent -FilterHashTable @{LogName='Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational';ID=$EventIds} -ErrorAction SilentlyContinue -MaxEvents 1
            
            $Label.Text = "The console has been shadowed since:`n`n$($AllEvents.TimeCreated)`n`n$($AllEvents.Message)"
            $Main_Tool_Icon.Icon = $onlineIcon
        } else {

            $EventIds = 20504,20507
            $AllEvents = Get-WinEvent -FilterHashTable @{LogName='Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational';ID=$EventIds} -ErrorAction SilentlyContinue -MaxEvents 1
            
            if($AllEvents) {
                $Label.Text = "The console is currently not being shadowed.`nThe console has been shadowed for the last time:`n`n$($AllEvents.TimeCreated)`n`n$($AllEvents.Message)"
            } else {  # if the Shadowing was never active (or the respective logs has been erased)
                $Label.Text = "The console is currently not being shadowed.`nEither no one on this machine has ever been shadowed or the log 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' has been erased."
            }

            $Main_Tool_Icon.Icon = $offlineIcon
        }
    
    } # if ($Label)
})
$timer.Start()

create_taskbar_menu

# Make PowerShell Disappear - Thanks Chrissy
$windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$asyncwindow = Add-Type -MemberDefinition $windowcode -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
$null = $asyncwindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)

# Use a Garbage colection to reduce Memory RAM
# https://dmitrysotnikov.wordpress.com/2012/02/24/freeing-up-memory-in-powershell-using-garbage-collector/
# https://learn.microsoft.com/fr-fr/dotnet/api/system.gc.collect?view=netframework-4.7.2
[System.GC]::Collect()

# Create an application context for it to all run within - Thanks Chrissy
# This helps with responsiveness, especially when clicking Exit - Thanks Chrissy
$appContext = New-Object System.Windows.Forms.ApplicationContext
try
{
    [System.Windows.Forms.Application]::Run($appContext)    
}
finally
{
    foreach ($component in $timer, $Main_Tool_Icon, $offlineIcon, $onlineIcon, $appContext)
    {
        # The following test returns $false if $component is
        # $null, which is really what we're concerned about
        if ($component -is [System.IDisposable])
        {
            $component.Dispose()
        }
    }

    # Make PowerShell Disappear - Thanks Chrissy
    #Stop-Process -Id $PID
}