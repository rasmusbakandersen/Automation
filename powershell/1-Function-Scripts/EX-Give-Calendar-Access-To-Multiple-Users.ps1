# Kør fra Cloud Shell
# Ændrer script ud fra hvilke brugere der skal have adgang og hvilken adgang de skal have

$calendarOwner = "calendarowner@domain.com"
$usersToGrantAccess = @("user1@domain.com", "user2@domain.com", "user3@domain.com")

# Define the permission level (e.g., Reviewer, Editor, etc.)
$permissionLevel = "Reviewer"  # Change this as needed

# Loop through each user and grant access to the calendar
foreach ($user in $usersToGrantAccess) {
    try {
        # Grant the specified permission to the user
        Add-MailboxFolderPermission -Identity "$calendarOwner:\Calendar" -User $user -AccessRights $permissionLevel
        Write-Host "Successfully granted $permissionLevel access to $user on $calendarOwner's calendar." -ForegroundColor Green
    } catch {
        Write-Host "Failed to grant access to $user. Error: $_" -ForegroundColor Red
    }
}
