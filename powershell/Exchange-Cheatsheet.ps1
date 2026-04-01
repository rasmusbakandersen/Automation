

### EXCHANGE ONLINE ###

#Connect til Exchange
Connect-ExchangeOnline -UserPrincipalName admin@company.onmicrosoft.com -ShowProgress $true

#Find alle mail kontoer der tilhører en "Morten" og hvis deres navn og SMTP adresse
Get-mailbox -Filter {Displayname -like "morten*"} | Select-Object DisplayName, PrimarySmtpAddress, Alias

#Vis alle foldere en postkasse harG
Get-MailboxFolderStatistics BRUGER@EMAIL | Select-Object Name, FolderPath

#Få info på brugerens mailbox
Get-MailboxStatistics -Identity user@contoso.com

#Få størrelse på alle brugeres mailboxer og hvor mange mails de har
Get-Mailbox -ResultSize Unlimited | Get-MailboxStatistics | Select-Object DisplayName, TotalItemSize, ItemCount

#Lav rettigheder til en hel postkasse for en bruger
Set-MailboxPermission -Identity "John.Doe" -User "Jane.Smith" -AccessRights FullAccess

#Lav rettigheder til en folder i en postkasse
Set-Mailboxfolderpermisson

#Opret Distribution gruppe
New-DistributionGroup -Name "Marketing Team" -DisplayName "Marketing Team" -PrimarySmtpAddress marketing@contoso.com

#Få alle transportregler
Get-TransportRule | Select-Object Name, Priority, Enabled, Mode, From, SentTo, SubjectContainsWords, ApplyHtmlDisclaimer, SetHeaderName, SetHeaderValue

#Opret ny mailbox (rediger parameter delen af kommandoen)
$Name = 'UPN';$DisplayName = 'NAVN';$FirstName = 'Fornavn';$LastName = 'Efternavn';$MicrosoftOnlineServicesID = 'NAVN@contoso.com';$Password = (ConvertTo-SecureString -String 'P@s$w0rd' -AsPlainText -Force)
New-Mailbox -Name "$Name" -DisplayName "$DisplayName" -FirstName "$FirstName" -LastName "$LastName" -MicrosoftOnlineServicesID $MicrosoftOnlineServicesID -Password $Password -ResetPasswordOnNextLogon $true

#Opret autosvar på brugers mailbox (rediger parameter delen af kommandoen)
$Bruger; $InternalMessage = "INTERN BESKED"; $ExternalMessage = "EKSTERN BESKED";
Set-MailboxAutoReplyConfiguration -Identity "$Bruger" -AutoReplyState Enabled -InternalMessage "$InternalMessage" -ExternalMessage "$ExternalMessage" -ExternalAudience All -StartTime (Get-Date) -EndTime (Get-Date).AddDays(7)

#Få alle retention policies
Get-RetentionPolicy | Format-Table Name, RetentionPolicyTagLinks -AutoSize

#Få alle Retention Tags
Get-RetentionPolicyTag | Format-Table Name, Type, AgeLimit, RetentionAction -AutoSize

#Restore alt til de originale mapper i Exchange
Restore-RecoverableItems -Identity "user@contoso.com" -ResultSize Unlimited



###   MØDELOKALE    ###

#Sæt indstillinger på et mødelokale
Set-CalendarProcessing -Identity MØDELOKALENAVN

#Her er nogle mulighederne man kan vælge
Set-CalendarProcessing -Identity MØDELOKALENAVN -AllBookInPolicy -AllowConflicts -AllRequestInPolicy -AllRequestOutOfPolicy -AutomateProcessing





###   MESSEGE TRACE   ###


#Messege Trace som en specifik bruger har sendt
Get-MessageTrace -SenderAddress user@domain.com -StartDate (Get-Date).AddDays(-10) -EndDate (Get-Date)

#Messege Trace som en specifik bruger har modtaget
Get-MessageTrace -RecipientAddress user@domain.com -StartDate (Get-Date).AddDays(-10) -EndDate (Get-Date)

#Få detaljer på en besked fra Messege trace
Get-MessageTrackingLog -MessageId "<message-id>" -Recipients "recipient@domain.com"

#Pipe det ovenstående ind i en ny command, så man kan filtrere på sender adresse
Get-MessageTrace -RecipientAddress user@domain.com -StartDate (Get-Date).AddDays(-10) -EndDate (Get-Date) | Where-Object SenderAddress -like "*udemy*"

#Brug grid view for interaktiv GUI
Get-MessageTrace -SenderAddress user@domain.com -StartDate (Get-Date).AddDays(-10) -EndDate (Get-Date) | Out-GridView -PassThru | Get-MessegeTraceDetail

#For at få over 10 dage siden skal man bruge historical search, dette gøres således
Start-HistoricalSearch -ReportTitle "TestSearch" -StartDate "6/1/2022" -EndDate "8/1/2022" -ReportType MessageTrace -SenderAddress user@domain.com -NotifyAddress user@domain.com

#Tjek status af Historical Search
Get-HistoricalSearch

