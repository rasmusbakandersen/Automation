# Get all distribution groups
$Groups = Get-DistributionGroup -ResultSize Unlimited

# Initialize an array to store results
$Results = @()

# Loop through each group and get its members
foreach ($Group in $Groups) {
    $Members = Get-DistributionGroupMember -Identity $Group.Identity
    foreach ($Member in $Members) {
        $Results += [PSCustomObject]@{
            GroupName         = $Group.DisplayName
            GroupSMTP         = $Group.PrimarySmtpAddress
            MemberName        = $Member.Name
            MemberType        = $Member.RecipientType
            MemberSMTP        = $Member.PrimarySmtpAddress
        }
    }
}

# Export the results to CSV in your Cloud Shell drive
$ExportPath = "$HOME/AllDistributionGroupMembers.csv"
$Results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8

Write-Host "Export complete! File saved to $ExportPath"
