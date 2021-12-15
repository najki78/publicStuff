#Get Graph API Intune Module
$m = Get-Module -Name Microsoft.Graph.Intune -ListAvailable
if (-not $m)
{
    Install-Module NuGet -Force
    Install-Module Microsoft.Graph.Intune
}

Import-Module Microsoft.Graph.Intune -Global
 
#The path where the scripts will be saved
$Path = "C:\temp\IntuneScripts"

mkdir $Path 

#The connection to Azure Graph
Connect-MSGraph 
 
#Get Graph scripts
$ScriptsData = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts" -HttpMethod GET
 
$ScriptsInfos = $ScriptsData.value | select id,fileName,displayname

$NBScripts = ($ScriptsInfos).count
 
if ($NBScripts -gt 0){
    Write-Host "Found $NBScripts scripts :" -ForegroundColor Yellow
    $ScriptsInfos | FT id,DisplayName,filename
    Write-Host "Downloading Scripts..." -ForegroundColor Yellow
    
    foreach($ScriptInfo in $ScriptsInfos){
        #Get the script
        $script = Invoke-MSGraphRequest -Url "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$($scriptInfo.id)" -HttpMethod GET
        #Save the script
        [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($($script.scriptContent))) | Out-File -FilePath $(Join-Path $Path $($script.fileName))  -Encoding ASCII 
    }
    
    Write-Host "All $NBScripts scripts downloaded!" -ForegroundColor Yellow        
}

