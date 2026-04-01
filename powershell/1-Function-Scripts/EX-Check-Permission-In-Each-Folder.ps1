# Replace with the mailbox you want to check
$mailbox = "user@contoso.com"

# Get all folder paths
$folders = Get-MailboxFolderStatistics $mailbox | Select-Object -ExpandProperty FolderPath

foreach ($folder in $folders) {
    # Build the folder identity string
    $identity = "${mailbox}:$($folder -replace '/', '\')"
    # Get permissions for each folder
    Get-MailboxFolderPermission -Identity $identity
}
