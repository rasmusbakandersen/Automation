$Printer = Get-Printer | Out-GridView -Passthru; $PortName = $Printer.PortName; Test-Connection -ComputerName $PortName -Count 4
