# Close any running instance of Outlook
if ($process = Get-Process 'outlook' -ErrorAction SilentlyContinue) {
    Write-Host "Closing running instance of Outlook..." -ForegroundColor Green
    Stop-Process -Name 'outlook' -Force
}

# Get the current date in "yyyy-MM-dd" format
$currentDate = (Get-Date).ToString('yyyy-MM-dd')

# Define registry path for Outlook profiles
$regPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles"

# Create a new profile named after the current date
$newProfileName = $currentDate
New-Item -Path $regPath -Name $newProfileName -Force

# Set the new profile as default
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\16.0\Outlook" -Name "DefaultProfile" -Value $newProfileName -Force

Write-Host "New Outlook profile '$newProfileName' created and set as default." -ForegroundColor Green
