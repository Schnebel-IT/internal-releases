<#
.SYNOPSIS
    Erstellt einen Bericht aller NTFS-Berechtigungen für Ordner bis zu einer bestimmten Tiefe.

.DESCRIPTION
    Dieses Skript analysiert NTFS-Berechtigungen (ACLs) in einem angegebenen Startpfad.
    Es kann rekursiv Unterordner durchsuchen, jedoch nur bis zu einer definierten maximalen Tiefe.
    Ordner, auf die der Benutzer keinen Zugriff hat, werden automatisch übersprungen.
    Optional kann die Ausgabe auf eine bestimmte Domäne gefiltert werden (z.B. "RIETHO").

.AUTHOR
    Luca Baumann

.LASTEDIT
    21. Oktober 2025

.EXAMPLE
    Get-AclReport -Path "D:\Daten" -MaxDepth 3 -Domain "RIETHO"
#>

function Get-AclReport {
   param (
       [Parameter(Mandatory = $true)]
       [string]$Path,

       [int]$MaxDepth = 3, # maximale Tiefe (inkl. Startordner)

       [string]$Domain # optional: Filter für Domäne
   )

   $results = @()

   Write-Host "Ermittle Ordnerstruktur unter '$Path' (max. Tiefe: $MaxDepth)..." -ForegroundColor Cyan

   try {
       # Rekursives Auflisten aller Unterordner (Zugriffsfehler werden ignoriert)
       $items = Get-ChildItem -LiteralPath $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue
   } catch {
       Write-Error "Fehler beim Auflisten der Unterordner: $($_.Exception.Message)"
       return
   }

   foreach ($item in $items) {

       # Tiefe relativ zum Startpfad berechnen
       $relative = $item.FullName.Substring($Path.Length).TrimStart('\')
       $depth = ($relative -split '\\').Count + 1

       if ($depth -le $MaxDepth) {
           try {
               # Zugriffssteuerung abrufen
               $acl = Get-Acl -LiteralPath $item.FullName -ErrorAction Stop

               foreach ($access in $acl.Access) {

                   # Optionaler Domänenfilter
                   if ($Domain -and (-not ($access.IdentityReference.Value -like "$Domain\*"))) {
                       continue
                   }

                   $obj = [PSCustomObject]@{
                       Path              = $item.FullName
                       Account           = $access.IdentityReference.Value
                       AccessControlType = $access.AccessControlType
                       FileSystemRights  = $access.FileSystemRights.ToString()
                       IsInherited       = $access.IsInherited
                   }

                   $results += $obj
               }

           } catch {
               Write-Warning "Zugriff verweigert: '$($item.FullName)' – wird übersprungen."
               continue
           }
       }
   }

   return $results
}

# ---------------------------------------------------------------------------
#                           SKRIPTAUSFÜHRUNG
# ---------------------------------------------------------------------------

# === KONFIGURATION ===
$StartPath = "D:\Daten"  # Startordner
$MaxDepth  = 3            # Maximale Tiefe (inkl. Startordner)
$Domain    = "RIETHO"     # Nur Konten dieser Domäne werden berücksichtigt (optional)
$OutputFile = "C:\Temp\FileserverPermissions_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

# === STATUSAUSGABE ===
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════"
Write-Host " NTFS-Berechtigungs-Analyse – Start: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
Write-Host " Autor: Luca Baumann"
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host " Startpfad:          $StartPath"
Write-Host " Maximale Tiefe:     $MaxDepth Ebenen"
if ($Domain) {
   Write-Host " Domänenfilter:      $Domain"
} else {
   Write-Host " Domänenfilter:      (keiner)"
}
Write-Host " Export-Datei:       $OutputFile"
Write-Host "═══════════════════════════════════════════════════════════════════"
Write-Host ""

# === HAUPTAUSFÜHRUNG ===
try {
   $permissions = Get-AclReport -Path $StartPath -MaxDepth $MaxDepth -Domain $Domain

   if ($permissions.Count -gt 0) {
       Write-Host "`nBerechtigungen gefunden: $($permissions.Count) Einträge." -ForegroundColor Green

       # Ausgabe in Tabellenform
       $permissions | Format-Table -AutoSize

       # Export nach CSV
       Write-Host "`nExportiere Ergebnisse nach:" -NoNewline
       Write-Host " $OutputFile" -ForegroundColor Yellow
       $permissions | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
       Write-Host "Export abgeschlossen." -ForegroundColor Green

   } else {
       Write-Host "Keine passenden Berechtigungseinträge gefunden." -ForegroundColor Yellow
   }

} catch {
   Write-Error "Ein unerwarteter Fehler ist aufgetreten: $($_.Exception.Message)"
}

Write-Host "`nSkript erfolgreich beendet." -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════"