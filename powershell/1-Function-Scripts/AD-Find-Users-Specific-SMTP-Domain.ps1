# Define the domain suffix to search for
$emailSuffix = "@contoso.com"

# Search for all AD users with the specified email suffix
$users = Get-ADUser -Filter {EmailAddress -like "*$emailSuffix"} -Properties EmailAddress

# Check if any users were found
if ($users.Count -gt 0) {
    Write-Host "Found $($users.Count) user(s) with the primary email ending with $emailSuffix:`n"
    
    # Display the results
    $users | ForEach-Object {
        Write-Host "User: $($_.SamAccountName) - Email: $($_.EmailAddress)"
    }
} else {
    Write-Host "No users found with the primary email ending with $emailSuffix."
}
