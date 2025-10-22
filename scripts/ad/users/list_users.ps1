<#
.SYNOPSIS
Erstellt einen AD-Benutzerbericht mit Anzeige von Anzeigename, UPN, Abteilung, Standort,
Status (aktiv/gesperrt), Beschäftigungsende und Service-/Systemaccount-Kennzeichnung.

.DESCRIPTION
Dieses Skript listet Benutzerobjekte aus Active Directory auf.
Optional werden aktivierte und deaktivierte Konten getrennt dargestellt.
Service-/Systemkonten werden automatisch gekennzeichnet.
Die Ausgabe enthält Hauptfelder wie Anzeigename, Benutzername, Abteilung, Standort, Status und 
ggf. Enddatum der Beschäftigung (AccountExpirationDate).

.AUTHOR
Luca Baumann

.LASTEDIT
22. Oktober 2025

.EXAMPLE
Get-AdUserReport -OU "OU=Mitarbeiter,DC=HOME,DC=local" -SeparateEnabledDisabled $true
#>

function Get-AdUserReport {
   param(
       [Parameter(Mandatory = $false)]
       [string]$OU,

       [Parameter(Mandatory = $false)]
       [switch]$SeparateEnabledDisabled
   )

   Write-Host "Ermittle AD-Benutzer..." -ForegroundColor Cyan

   try {
       if ($OU) {
           $users = Get-ADUser -SearchBase $OU -Filter * `
               -Properties DisplayName, UserPrincipalName, Department, Office, Enabled, AccountExpirationDate, Description
       } else {
           $users = Get-ADUser -Filter * `
               -Properties DisplayName, UserPrincipalName, Department, Office, Enabled, AccountExpirationDate, Description
       }

       Write-Host "Gesamtanzahl gefundener Benutzer: $($users.Count)" -ForegroundColor Green

       $results = foreach ($u in $users) {
           # Status: aktiv / gesperrt
           $status = if ($u.Enabled) { "Aktiv" } else { "Gesperrt" }

           # Service-/Systemkonto-Erkennung – heuristisch nach Namen oder Beschreibung
           $isServiceAccount = $false
           if ($u.SamAccountName -match '^(svc_|sys_|service_)' -or
               $u.DisplayName -match '(?i)dienstkonto|service' -or
               $u.Description -match '(?i)system|dienstkonto|service') {
               $isServiceAccount = $true
           }

           [PSCustomObject]@{
               Anzeigename       = $u.DisplayName
               BenutzernameUPN   = $u.UserPrincipalName
               Abteilung         = $u.Department
               Standort          = $u.Office
               Status            = $status
               Beschaeftigungsende = if ($u.AccountExpirationDate) { $u.AccountExpirationDate.ToString("dd.MM.yyyy") } else { "" }
               ServiceKonto      = if ($isServiceAccount) { "Ja" } else { "Nein" }
           }
       }

       if ($SeparateEnabledDisabled) {
           $aktiv = $results | Where-Object { $_.Status -eq "Aktiv" }
           $gesperrt = $results | Where-Object { $_.Status -eq "Gesperrt" }

           Write-Host "`nAktive Benutzer: $($aktiv.Count)" -ForegroundColor Green
           $aktiv | Format-Table -AutoSize

           Write-Host "`nGesperrte Benutzer: $($gesperrt.Count)" -ForegroundColor Yellow
           $gesperrt | Format-Table -AutoSize

           return @{
               Aktiv     = $aktiv
               Gesperrt  = $gesperrt
           }
       }
       else {
           $results | Format-Table -AutoSize
           return $results
       }

   } catch {
       Write-Error "Fehler beim Abrufen der Benutzerinformationen: $($_.Exception.Message)"
   }
}

# ---------------------------------------------------------------------------
# SKRIPTAUSFÜHRUNG
# ---------------------------------------------------------------------------

# === KONFIGURATION ===
$OU = ""                           # z.B. "OU=Mitarbeiter,DC=HOME,DC=local"
$SeparateEnabledDisabled = $true   # Trennung aktiv/deaktiv
$OutputDir = "C:\Temp"
$TimeStamp = Get-Date -Format 'yyyyMMdd_HHmm'
$BaseName = "ADUserReport_$TimeStamp"
$OutputFile_All = Join-Path $OutputDir "$BaseName.csv"
$OutputFile_Enabled = Join-Path $OutputDir "$BaseName`_Enabled.csv"
$OutputFile_Disabled = Join-Path $OutputDir "$BaseName`_Disabled.csv"

# === STATUSAUSGABE ===
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════"
Write-Host " AD-Benutzer-Analyse – Start: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
Write-Host " Autor: Luca Baumann"
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($OU) {
   Write-Host " Organisationseinheit:  $OU"
} else {
   Write-Host " Organisationseinheit:  (gesamtes AD)"
}
Write-Host " Getrennte Darstellung:  $SeparateEnabledDisabled"
Write-Host " Export-Pfad:            $OutputDir"
Write-Host "═══════════════════════════════════════════════════════════════════"
Write-Host ""

# === HAUPTAUSFÜHRUNG ===
try {
   $report = Get-AdUserReport -OU $OU -SeparateEnabledDisabled:$SeparateEnabledDisabled

   if ($SeparateEnabledDisabled) {
       $report.Aktiv | Export-Csv -Path $OutputFile_Enabled -NoTypeInformation -Encoding UTF8
       $report.Gesperrt | Export-Csv -Path $OutputFile_Disabled -NoTypeInformation -Encoding UTF8
       Write-Host "`nExporte abgeschlossen:" -ForegroundColor Green
       Write-Host "  $OutputFile_Enabled"
       Write-Host "  $OutputFile_Disabled"
   } else {
       $report | Export-Csv -Path $OutputFile_All -NoTypeInformation -Encoding UTF8
       Write-Host "`nExport abgeschlossen: $OutputFile_All" -ForegroundColor Green
   }

} catch {
   Write-Error "Ein unerwarteter Fehler ist aufgetreten: $($_.Exception.Message)"
}

Write-Host "`nSkript erfolgreich beendet." -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════"