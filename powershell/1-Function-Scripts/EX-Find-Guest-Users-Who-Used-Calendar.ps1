$StartDate = (Get-Date).AddDays(-30)  # Adjust time range as needed
$EndDate = Get-Date

# Search for calendar bookings with external user pattern
Search-UnifiedAuditLog -StartDate $StartDate -EndDate $EndDate -Operations "MeetingResponseAccepted","Create" -RecordType ExchangeItem -FreeText "#EXT#" -ResultSize 5000 -SessionCommand ReturnLargeSet | Where-Object {$_.AuditData -like "*RoomMailbox*"} 
