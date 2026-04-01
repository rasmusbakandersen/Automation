# Import the CSV
#CSV Syntax:
#Email,Birthday
#ashr,1928-01-01
$users = Import-Csv -Path C:\Users\Public\csv.csv

# Process each user
foreach ($user in $users) {
    try {
        Set-ADUser -Identity $user.Email -Replace @{
            'msDS-cloudExtensionAttribute1' = $user.Birthday
        }
        Write-Host "Updated $($user.Email) with birthday $($user.Birthday)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to update $($user.Email): $_"
    }
}
