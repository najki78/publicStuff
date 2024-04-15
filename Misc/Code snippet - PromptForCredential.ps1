# Code snippet - PromptForCredential

# Recently, we had issues obtaining user credentials in PowerShell scripts on Windows 11. While we do not know yet the exact cause, we prepared a workaround to prevent our scripts from failing. 

# The issue arises when trying to use the Get-Credential cmdlet or the $host.ui.PromptForCredential method in a PowerShell script. 
# These are standard ways to prompt for user credentials in a secure manner. 
# However, for some users, these methods are failing without any clear error message.

# The following script provides a workaround for this issue. 
# It first tries to use Get-Credential or $host.ui.PromptForCredential. 
# If these fail, it attempts an alternative method using System.Windows.Forms (function PromptForCredentialWindowsForms). 
# If even that fails, it prompts for the password in text form. 

# 2024.04.15.01 Ľuboš Nikolíni

# Known issues:
# 1. The script does not differentiate between clicking on Cancel in the PromptForCredential form and entering an empty password (raise a pull request please, if you fix it)

function PromptForCredentialWindowsForms {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $false)][String[]]$displayText = "Supply values for the following parameters:",
        [Parameter(Mandatory = $false)][String[]]$headerText = "Form host.ui.PromptForCredential"
    )

    Add-Type -AssemblyName System.Windows.Forms

    $form = New-Object System.Windows.Forms.Form 
    $form.Text = $headerText
    $form.Size = New-Object System.Drawing.Size(400,200) 
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(10,20) 
    $label.Size = New-Object System.Drawing.Size(370,40) 
    $label.Text = $displayText
    $form.Controls.Add($label) 

    $userLabel = New-Object System.Windows.Forms.Label
    $userLabel.Location = New-Object System.Drawing.Point(10,70) 
    $userLabel.Size = New-Object System.Drawing.Size(80,20) 
    $userLabel.Text = "User name:"
    $form.Controls.Add($userLabel) 

    $userBox = New-Object System.Windows.Forms.TextBox 
    $userBox.Location = New-Object System.Drawing.Point(100,70) 
    $userBox.Size = New-Object System.Drawing.Size(260,20) 
    $form.Controls.Add($userBox) 

    $passLabel = New-Object System.Windows.Forms.Label
    $passLabel.Location = New-Object System.Drawing.Point(10,100) 
    $passLabel.Size = New-Object System.Drawing.Size(80,20) 
    $passLabel.Text = "Password:"
    $form.Controls.Add($passLabel) 

    $passBox = New-Object System.Windows.Forms.TextBox 
    $passBox.Location = New-Object System.Drawing.Point(100,100) 
    $passBox.Size = New-Object System.Drawing.Size(260,20) 
    $passBox.UseSystemPasswordChar = $true
    $form.Controls.Add($passBox) 

    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Location = New-Object System.Drawing.Point(100,130)
    $OKButton.Size = New-Object System.Drawing.Size(75,23)
    $OKButton.Text = "OK"
    $OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $OKButton
    $form.Controls.Add($OKButton)

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Location = New-Object System.Drawing.Point(185,130)
    $CancelButton.Size = New-Object System.Drawing.Size(75,23)
    $CancelButton.Text = "Cancel"
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $CancelButton
    $form.Controls.Add($CancelButton)

    $form.Topmost = $true

    $form.Add_Shown({ $userBox.Select() })
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK)
    {
        $username = $userBox.Text
        $password = $passBox.Text
        $password = $password | ConvertTo-SecureString -AsPlainText -Force -ErrorAction Continue

        $usercredentials = (New-Object System.Management.Automation.PSCredential -ArgumentList $username,$password)
        return $usercredentials 
    }

}

try {

    $displayText = "Please enter your username and password."
    $headerText = "This is a placeholder for a header text."

    # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-credential?view=powershell-5.1
    # $usercredentials = (Get-Credential -Message "$headerText. $displayText" -ErrorAction Stop)
    $usercredentials = $host.ui.PromptForCredential($headerText, $displayText, "", "")

    # alternative graphical pop-up, if $host.ui.PromptForCredential fails to show up the form
    if (-not ($usercredentials.Password)) { # Cancel button clicked OR pop-up did not show up OR empty password entered
        $usercredentials = PromptForCredentialWindowsForms -displayText $displayText -headerText $headerText
    }

    # backup - text form prompt
    if (-not ($usercredentials.Password)) { # Cancel button clicked OR pop-up did not show up OR empty password entered
        $user = Read-Host "Please enter your username" 
        $pwd = Read-Host "Please enter the password for '$($user)' account" -AsSecureString
        $usercredentials = (New-Object System.Management.Automation.PSCredential -ArgumentList $user,$pwd)
    }
    
} catch {
    
    Write-Warning -Message "Exception: $($Error[0])"
    Read-Host "`nPress Enter to exit..."
    exit
}

if (-not ($usercredentials.Password)) { # Cancel button clicked OR empty password entered
    Write-Warning -Message 'Cancelled by the user. Exiting now.'
    Read-Host "`nPress Enter to exit..."
    exit
}