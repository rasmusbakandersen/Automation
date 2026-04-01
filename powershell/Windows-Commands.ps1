###   Windows commands  ###

#Restart af PC nu
Restart-Computer -Force

#Kør program som anden bruger, typisk som admin
runas /user:administrator cmd.exe

#Tjek om bruger er med i local admin
Get-LocalGroupMember Administrators

#Få alt brugbart info på printere
Get-Printer | Select-Object Name, Type, PortName, DriverName, Location, PrintProcessor, PrinterStatus, JobCount

#Tjek om enhed er enrolled
dsregcmd /status


### COMPUTER INFO ###

#Få alt brugbar info på en Windows maskine
Get-Computerinfo  BiosSeralNumber, OsArchitecture, OsLanguage, OsInstallDate, OsLocalDateTime, OsVersion, OsName, CsUserName, CsPhyicallyInstalledMemory, CsSystemType, CsSystemSKUNumber, CsProcessors, CsModel, CsName , BiosVersion, OSDisplayVersion, WindowsCurrentVersion

#Find ud af hvem du er logget på som, samt gruppe og mere
whoami /all

#Få oplysninger om TPM på maskinen
Get-Tpm

#Få locale brugere, brugbart ved LAPS
Get-LocalUser      #Alternativ: net user

#Sæt tidszone på maskine til dansk tid
Set-TimeZone -Id "Romance Standard Time"

#Få hvilken licens windows har
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" | Select-Object -Property ProductName, DisplayVersion

#Find Drev på maskine og deres info
net use



### DISKS   ###

#Tjek Disk helbred
Get-PhysicalDisk

#Reperare Windows for korrupte filer
sfc /scannow

#Fuld Scan og repair af disken
chkdsk /x /f /r

#Denne reperare også Windows som den ovenstående, men tager længere tid.
dism.exe /online /cleanup-image /restorehealth


#Få en liste af alle tasks
tasklist
#Dræb en tjeneste hvis task manager er slået fra
taskkill /IM cmd.exe

#Opdater gruppe politiker
gpupdate




###   NETVÆRK   ###

#Tjek DNS
Resolve-DNSName dr.dk

#Liste over netværk interface og adresser
Get-NetIpAddress * | Select-Object IpAddress, InterfaceAlias, PrefixLength


###   MISCELLANEOUS   ###


#Fixer App Store Apps, som for eksempel Calculator, Snipping tool, osv.
Get-AppXPackage | For-each {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}

#Enable en optional Windows feature, som for eksempel HyperV
Enable-WindowsOptionalFeature

#Få alle windows update logs 
Get-WindowsUpdateLog

#Installer certifikat på maskine
Get-Certificate

#Lav Zip archive af en folder
Compress-Archive






###  CMD IKKE POWERSHELL COMMANDS   ###
#Viser stien CMD i er inde i som et tree
tree
#Disse 4 commands finder info på maskine, men ovenstående command er bedere
wmic bios get serialnumber | systeminfo  | set   |  ver
