
# Get all Microsoft 365 Groups (Unified groups)
$Groups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All

$Results = @()

foreach ($Group in $Groups) {
    $Members = Get-MgGroupMember -GroupId $Group.Id -All
    if ($Members) {
        foreach ($Member in $Members) {
            $Results += [PSCustomObject]@{
                GroupName      = $Group.DisplayName
                GroupId        = $Group.Id
                MemberName     = $Member.AdditionalProperties.displayName
                MemberType     = $Member.AdditionalProperties['@odata.type']
                MemberEmail    = $Member.AdditionalProperties.mail
                MemberUPN      = $Member.AdditionalProperties.userPrincipalName
            }
        }
    } else {
        # If no members, still output the group
        $Results += [PSCustomObject]@{
            GroupName      = $Group.DisplayName
            GroupId        = $Group.Id
            MemberName     = "N/A"
            MemberType     = "N/A"
            MemberEmail    = "N/A"
            MemberUPN      = "N/A"
        }
    }
}

# Export to CSV in your Cloud Shell persistent storage
$ExportPath = "$HOME/M365GroupMembers.csv"
$Results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8

Write-Host "Export complete! File saved to $ExportPath"
