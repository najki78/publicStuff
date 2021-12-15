
# lists ObjectID for the list of Azure AD devices


#Get AzureAD Module
$m = Get-Module -Name AzureAD -ListAvailable

Write-Output $m

if (-not $m)
{
    
    Install-Module -Name AzureAD -AllowClobber -Force 
   
}

Install-Module AzureAD
Connect-AzureAD

$outfile = "C:\temp\Outfile.csv"

# input file "c:\temp\devices.csv" has a single column and a header "DeviceName" on the first line ...
Import-Csv c:\temp\devices.csv | ForEach-Object {

    (Get-AzureADDevice -SearchString $($_.DeviceName)).objectid | add-content -path $outfile
    Write-Host "$($_.DeviceName)"

}



