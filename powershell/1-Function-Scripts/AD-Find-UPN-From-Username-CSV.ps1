
##Denne command finder den UserPrincipalName (UPN) for en liste af brugere i en CSV fil.
>> $users | ForEach-Object {
>>     Get-ADUser -Filter "DisplayName -eq '$($_.DisplayName)'" -Properties DisplayName
>> } | select DisplayName, UserPrincipalName



Denne tjekker om der var nogle den ikke kunnne finde i AD og viser dem
 foreach ($user in $users) {
>>     $adUser = Get-ADUser -Filter "DisplayName -eq '$($user.DisplayName)'" -Properties DisplayName
>>     if (-not $adUser) {
>>         # Not found in AD, display the name
>>         Write-Host "Not found in AD: $($user.DisplayName)"
>>     }
>> }
