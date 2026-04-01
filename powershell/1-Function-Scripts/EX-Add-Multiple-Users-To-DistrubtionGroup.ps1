# Define the distribution group email as a variable
$DistributionGroupEmail = "DISTRIBUTION-GROUP@fabrikam.com"

# Import the list of users from CSV
$Users = Import-Csv ".\AALBORG - PSYKOLOGER ALLE.csv"






# Loop through each user and add to the distribution group
foreach ($User in $Users) {
    try {
        Add-DistributionGroupMember -Identity $DistributionGroupEmail -Member $User.Email -BypassSecurityGroupManagerCheck -ErrorAction Stop
        Write-Host "$($User.Email) successfully added." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to add $($User.Email): $($_.Exception.Message)" -ForegroundColor Red
    }
}
