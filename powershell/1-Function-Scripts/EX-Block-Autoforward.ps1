New-TransportRule -Name "Block Auto-forward from Vipre to External" `
    -SentToScope NotInOrganization `
    -SubjectOrBodyContainsWords "Quarantine Summary Report" `
    -MessageType AutoForward `
    -RejectMessageReasonText "Auto-forward from Vipre is not allowed."
