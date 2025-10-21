<#
.SYNOPSIS
    Erstellt einen Bericht über AD-Gruppenmitglieder innerhalb eines OU-Pfads.

.DESCRIPTION
    Dieses Skript durchsucht Active Directory nach Gruppen unterhalb einer angegebenen OU.
    Es listet für jede gefundene Gruppe deren Mitglieder auf und kann optional verschachtelte Gruppen mit auflösen.

.AUTHOR
    Luca Baumann

.LASTEDIT
    21. Oktober 2025

.EXAMPLE
    Get-ADGroupMembershipReport -DomainName "HOME.local" -OUPath "OU=Gruppen,DC=HOME,DC=local" -Recursive
#>

function Get-ADGroupMembershipReport {
   [CmdletBinding()]
   param (
       [Parameter(Mandatory = $true)]
       [string]$DomainName,

       [Parameter(Mandatory = $true)]
       [string]$OUPath,

       [switch]$Recursive
   )

   Import-Module ActiveDirectory -ErrorAction Stop

   $results = @()

   try {
       $groups = Get-ADGroup -SearchBase $OUPath -Server $DomainName -Filter * -ErrorAction Stop
   } catch {
       Write-Error "Fehler beim Abrufen der Gruppen: $($_.Exception.Message)"
       return
   }

   foreach ($group in $groups) {
       Write-Host "Analysiere Gruppe: $($group.Name)" -ForegroundColor Cyan

       try {
           $members = Get-ADGroupMember -Identity $group.DistinguishedName -Server $DomainName -ErrorAction Stop

           foreach ($member in $members) {
               if ($Recursive -and $member.ObjectClass -eq 'group') {
                   $nestedMembers = Get-ADGroupMember -Identity $member.DistinguishedName -Server $DomainName -ErrorAction SilentlyContinue
                   foreach ($nm in $nestedMembers) {
                       $results += [PSCustomObject]@{
                           GroupName  = $group.Name
                           MemberName = $nm.SamAccountName
                           MemberType = $nm.ObjectClass
                           Domain     = $DomainName
                       }
                   }
               } else {
                   $results += [PSCustomObject]@{
                       GroupName  = $group.Name
                       MemberName = $member.SamAccountName
                       MemberType = $member.ObjectClass
                       Domain     = $DomainName
                   }
               }
           }

       } catch {
           Write-Warning "Zugriff auf Gruppe '$($group.Name)' nicht möglich – übersprungen."
       }
   }

   return $results
}

# ---------------------------------------------------------------------------
#                           SKRIPTAUSFÜHRUNG
# ---------------------------------------------------------------------------

# === KONFIGURATION ===
$DomainName = "HOME.local"
$OUPath     = "OU=Gruppen,DC=HOME,DC=local"
$Recursive  = $true
$OutputFile = "C:\Temp\ADGroups_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

# === STATUSAUSGABE ===
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════"
Write-Host " AD-Gruppenanalyse – Start: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
Write-Host " Autor: Luca Baumann"
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host " Domäne:             $DomainName"
Write-Host " OU-Pfad:            $OUPath"
Write-Host " Rekursive Auflösung:" ($(if ($Recursive) { "Aktiv" } else { "Inaktiv" }))
Write-Host " Export-Datei:       $OutputFile"
Write-Host "═══════════════════════════════════════════════════════════════════"
Write-Host ""

# === HAUPTAUSFÜHRUNG ===
try {
   $report = Get-ADGroupMembershipReport -DomainName $DomainName -OUPath $OUPath -Recursive:$Recursive
   if ($report.Count -gt 0) {
       Write-Host "`nMitgliedschaften gefunden: $($report.Count) Einträge." -ForegroundColor Green

       $report | Format-Table -AutoSize
       Write-Host "`nExportiere Ergebnisse nach:" -NoNewline
       Write-Host " $OutputFile" -ForegroundColor Yellow

       $report | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
       Write-Host "Export abgeschlossen." -ForegroundColor Green
   } else {
       Write-Host "Keine Gruppenmitglieder gefunden oder keine Gruppen im OU." -ForegroundColor Yellow
   }
} catch {
   Write-Error "Ein unerwarteter Fehler ist aufgetreten: $($_.Exception.Message)"
}

Write-Host "`nSkript erfolgreich beendet." -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════"