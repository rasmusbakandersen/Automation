###   MICROSOFT GRAPH   ###



#Få UseriD ud fra email
$userId = (Get-MgUser -Filter "mail eq 'EMAIl'").Id

#Få licens på specifik bruger
$userId = (Get-MgUser -Filter "mail eq 'EMAIl'").Id
Get-MgUserLicenseDetail -UserId $userID

#Få hvilke apps der er slået til for brugeren i 365
(Get-MgUserLicenseDetail -UserId "$userID" -Property ServicePlans).ServicePlans



#Søg for en person udfra deres FirstName
Get-MgUser -ConsistencyLevel eventual -Filter "startsWith(displayName, 'John')"

#Find gruppe ud fra DisplayName
Get-MgGroup -Filter "startsWith(DisplayName, 'Riffe')" -All | Select-Object DisplayName, UserPrincipalName, Id

#Find ud af hvilken gruppe en bruger er med i
$userId = (Get-MgUser -Filter "mail eq 'EMAIl'").Id
Get-MgUserMemberOf -UserId $user | ForEach-Object {
    [PSCustomObject]@{
        DisplayName = $_.AdditionalProperties.displayName
        Id          = $_.Id
    }
} | Select-Object DisplayName, Id | Format-Table -AutoSize


#Reset kode på en bruger
$userid = "brugers@email.com"; $newPassword = "REDACTED"
Update-MgUser -UserId $userid -PasswordProfile @{
    Password = $newPassword
    ForceChangePasswordNextSignIn = $true
}

#Find Risky User og fjern dens risk
$selected = Get-MgRiskyUser | Out-GridView -PassThru; Invoke-MgDismissRiskyUser -UserIds $selected.Id

#Find låste brugere i Graph
Get-MgUser -Filter "accountEnabled eq false" | Select-Object DisplayName, UserPrincipalName



#Tjek info på applikation
Get-MgApplication | Format-List Id, DisplayName, AppId, SignInAudience, PublisherDomain

#Tjek hvem der er med i en Application gruppe
Get-MgApplicationMemberGroup -ApplicationID "application id" | Select *

#Find alle Service Principals
Get-MgServicePrincipal



#Find ID på kalender
Get-MgUserCalendar -UserId "owner@example.com" 

#Giv en bruger adgang til en anden brugers kalender
New-MgUserCalendarPermission -UserId bruger1 -CalendarId $_ -EmailAddress bruger2 -Role Editor

























### SKAL TJEKKES ###



# Retrieve all users with extended properties  
Get-MgUser -All -Property "id,displayName,userPrincipalName,accountEnabled"  

# Create new user with license assignment  
$PasswordProfile = @{Password = "REDACTED"}  
New-MgUser -DisplayName "Jane Doe" -UserPrincipalName "jane@contoso.com" -PasswordProfile $PasswordProfile -AccountEnabled  

# Update user attributes  
Update-MgUser -UserId "jane@contoso.com" -Department "Finance" -JobTitle "CFO"  


#Find en brugers kalender permissions
$userId = (Get-MgUser -Filter "mail eq 'EMAIl'").Id
Get-MgUserCalendarPermission -UserID $userId
