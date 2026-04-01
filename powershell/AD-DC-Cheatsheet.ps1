###   AD Administration   ###

#Denne finder ALLE properties for en specific bruger
Get-ADUser BRUGERNAVN -Properties *

#Få alt det der typisk er brugbart med Get-ADUser i én command
Get-ADUser rm -Properties Title, TelephoneNumber, SamAccountName, proxyAddresses, PrimaryGroup, PasswordExpired, OfficePhone, MemberOf, Manager, LockedOut, Enabled, DistinguishedName, DisplayName, Department

##Find brugere på en AD server, som er låst
Search-ADAccount -LockedOut

#Showcase af mange brugbare switches til Search-Adaccount
Search-ADAccount -AccountDisabled -AccountExpired -AccountExpiring -PasswordExpired -AccountInactive

#Lås bruger konti op
Unlock-ADAccount BRUGERNAVN

#Ændrer adgangskode på bruger
Set-AdAccountPassword -Identity BRUGERNAVN -reset -NewPassword (ConvertTo-SecureString -AsPlainText "KODEORD" -Force)

#Find alle de brugerkonti, som har noget med "SvcAccount" i deres brugernavn
#og efterfølgende viser den deres brugernavne i en liste, i alfabetisk rækkefølge
Get-ADUser -Filter "Name -like '*SvcAccount'"

#Find ud af om bruger har adgang til en sti på en fil server
(Get-Acl "\\STI\NAME").Access | Where-Object { $_.IdentityReference -like "domain\username" } 

#Få vist Medlemmer af en gruppe
Get-ADGroupMember GRUPPENAVN

#Vis hvilke grupper en bruger er medlem af
Get-ADPrincipalGroupMembership -Identity "username"

#Tilføj bruger til gruppe
Add-ADGroupMember -Identity GRUPPE -Members BRUGERNAVN

#Få vist properties af en OU
Get-ADOrganizationalUnit OUnavn

#Enable og Disable en bruger konti
Enable-ADAccount

#Få alle GPO'er på et domain
Get-GPO *

#Denne finder hvor mange brugere som har et hjemmedrev med H: bogstavet
Get-ADUser -Filter "HomeDrive -eq 'H:'" | Measure-Object

###   REMOTE SERVER ADMINISTRATION   ###

#Denne command genstarter spooleren på print serveren
Invoke-Command -ComputerName Appsrv3 -ScriptBlock { Get-Service -Name 'spooler' | Restart-Service -Force }

#Denne command genstarter SALTO på på salto serveren
Invoke-Command -ComputerName Salto01 -ScriptBlock { Get-Service -Name 'SALTO ProAccess Space Service' | Restart-Service -Force }

#Test forbindelse til server
Test-Connection Appsrv3

#Get service på remote PC
Get-Service -ComputerName Appsrv3

#Remote session til server
Enter-PSSession -ComputerName Appsrv3



#Tjek DC helbred på serveren
dcdiag

#Schedule task på server
schtasks
