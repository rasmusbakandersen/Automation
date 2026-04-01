$users = @(
    "user1@domain.com",
    "user2@domain.com",
    "user3@domain.com"
)

# Define the access rights (e.g., FullAccess, SendAs, SendOnBehalf)
$accessRights = "FullAccess"

# Loop through each user and grant access to the mailbox
foreach ($user in $users) {
    try {
        Add-MailboxPermission -Identity $mailbox -User $user -AccessRights $accessRights -ErrorAction Stop
        Write-Host "Successfully granted $accessRights access to $mailbox for $user"
    } catch {
        Write-Host "Failed to grant access to $user. Error: $_" -ForegroundColor Red
    }
}
