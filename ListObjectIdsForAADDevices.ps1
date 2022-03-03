
# lists ObjectID for the list of Azure AD devices
# input file "c:\temp\devices.csv" has a single column and a header "DeviceName" on the first line ...
# run this script as Administrator (to install AzureAD module)

# 2022-02-09 Lubos

#Get AzureAD Module
$m = Get-Module -Name AzureAD -ListAvailable

Write-Output $m

if (-not $m)
{
    
    Install-Module -Name AzureAD -AllowClobber -Force 
   
}

Import-Module AzureAD
Connect-AzureAD

$outfile = "C:\temp\"+ (Get-Date).tostring("yyyy-MM-dd_HH-mm-ss") + "_devices-Outfile.csv"
Remove-Item $outfile -Force -ErrorAction SilentlyContinue

add-content -path $outfile -value "DeviceName,ObjectID"

Import-Csv c:\temp\devices.csv | ForEach-Object {
    
    #(Get-AzureADDevice -SearchString $($_.DeviceName)).objectid | add-content -path $outfile
    #Write-Host "$($_.DeviceName)" | add-content -path $outfile
    
    $objectID = (Get-AzureADDevice -SearchString $($_.DeviceName)).objectid

    #$objectID.Count # number of Object IDs returned ... 0 - no match found, 1 - OK, more than 1 - duplicate name

    add-content -path $outfile -NoNewline -value "$($_.DeviceName),"

    if ($objectID.Count -eq 0) {
            add-content -path $outfile -value "$($_.DeviceName) not found in AAD, skipping."
    } else {

            if ($objectID.Count -eq 1) {
                add-content -path $outfile -value $objectID
            } else {
               add-content -path $outfile -value "Duplicate. More than one $($_.DeviceName) found in AAD."
            }
    }
        
    #Write-Host "$($_.DeviceName) ... $objectID ... $($objectID.Count)"
        
}


