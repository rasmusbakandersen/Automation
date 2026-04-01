Get-GPO -All | Where-Object { (Get-GPOReport -Guid $_.Id -ReportType XML) -match "PowerShell|ExecutionPolicy|Script.*Execution" } | Select-Object DisplayName, Id, Owner, GpoStatus
