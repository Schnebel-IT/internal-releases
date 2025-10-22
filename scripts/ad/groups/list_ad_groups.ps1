<#
.SYNOPSIS
    Erstellt Berichte über AD-Gruppen und Benutzer-Mitgliedschaften.

.DESCRIPTION
    Das Skript ermöglicht zwei wählbare Analysemethoden:
    - Mode "Group": Listet zu jeder Gruppe die Mitglieder auf.
    - Mode "User":   Listet zu jedem Benutzer alle Gruppenmitgliedschaften auf.

    Unterstützt rekursive Auflösungen verschachtelter Gruppen
    und exportiert alle Ergebnisse als CSV-Datei.

.PARAMETER DomainName
    FQDN der Domäne (z. B. "RIETHO.local").

.PARAMETER OUPath
    LDAP-Suchpfad, z. B. "OU=Gruppen,DC=RIETHO,DC=local".

.PARAMETER Mode
    "Group" oder "User" – bestimmt die Analyserichtung.

.PARAMETER Recursive
    Optionaler Schalter, um verschachtelte Gruppen komplett aufzulösen.

.PARAMETER OutputFile
    Pfad zur CSV-Datei (Standard: C:\Temp\ADGroups_<Datum>.csv)

.EXAMPLE
    .\list_ad_groups.ps1 -DomainName "RIETHO.local" -OUPath "OU=Gruppen,DC=RIETHO,DC=local" -Mode "Group"

.EXAMPLE
    .\list_ad_groups.ps1 -DomainName "RIETHO.local" -OUPath "OU=Benutzer,DC=RIETHO,DC=local" -Mode "User" -Recursive

.AUTHOR
    Luca Baumann
.VERSION
    1.1
.LASTEDIT
    22. Oktober 2025
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName,

    [Parameter(Mandatory = $true)]
    [string]$OUPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Group", "User")]
    [string]$Mode,

    [switch]$Recursive,

    [string]$OutputFile = "C:\Temp\ADGroups_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmm')
)

# ----------------------------------------------------------------------------
#                             INITIALISIERUNG
# ----------------------------------------------------------------------------

Import-Module ActiveDirectory -ErrorAction Stop

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════"
Write-Host " AD-$($Mode)-Analyse – Start: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
Write-Host " Autor: Luca Baumann"
Write-Host "───────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host " Domäne:             $DomainName"
Write-Host " OU-Pfad:            $OUPath"
Write-Host " Modus:              $Mode"
Write-Host " Rekursive Auflösung:" ($(if ($Recursive) { "Aktiv" } else { "Inaktiv" }))
Write-Host " Export-Datei:       $OutputFile"
Write-Host "═══════════════════════════════════════════════════════════════════"
Write-Host ""

$results = @()

# ----------------------------------------------------------------------------
#                             FUNKTIONEN
# ----------------------------------------------------------------------------

function Get-GroupMembers {
    param (
        [string]$GroupDN,
        [string]$GroupName,
        [string]$GroupDescription
    )

    try {
        $members = Get-ADGroupMember -Identity $GroupDN -Server $DomainName -ErrorAction Stop
        foreach ($member in $members) {
            if ($Recursive -and $member.ObjectClass -eq 'group') {
                # verschachtelte Gruppen auflösen
                $nested = Get-ADGroupMember -Identity $member.DistinguishedName -Server $DomainName -ErrorAction SilentlyContinue
                foreach ($n in $nested) {
                    $results += [PSCustomObject]@{
                        GroupName      = $GroupName
                        Description    = $GroupDescription
                        MemberName     = $n.SamAccountName
                        MemberType     = $n.ObjectClass
                        Domain         = $DomainName
                    }
                }
            }
            $results += [PSCustomObject]@{
                GroupName      = $GroupName
                Description    = $GroupDescription
                MemberName     = $member.SamAccountName
                MemberType     = $member.ObjectClass
                Domain         = $DomainName
            }
        }
    } catch {
        Write-Warning "→ Zugriff auf Gruppe '$GroupName' nicht möglich: $($_.Exception.Message)"
    }
}

function Get-UserGroups {
    param (
        [string]$UserSam
    )

    try {
        # Holt ALLE Gruppen des Benutzers (inkl. verschachtelte)
        $groups = @( Get-ADPrincipalGroupMembership -Identity $UserSam -Server $DomainName -ErrorAction Stop )

        if (-not $groups -or $groups.Count -eq 0) {
            Write-Verbose "Benutzer '$UserSam' ist in keiner Gruppe."
            return
        }

        foreach ($group in $groups) {
            $groupDesc = (Get-ADGroup -Identity $group.DistinguishedName -Properties Description -ErrorAction SilentlyContinue).Description
            $results += [PSCustomObject]@{
                UserName         = $UserSam
                GroupName        = $group.Name
                GroupDescription = $groupDesc
                Domain           = $DomainName
            }

            # Rekursive Auflösung von verschachtelten Gruppen
            if ($Recursive) {
                $nestedGroups = Get-ADGroupMember -Identity $group.DistinguishedName -Server $DomainName -ErrorAction SilentlyContinue |
                                Where-Object { $_.ObjectClass -eq 'group' }
                foreach ($n in $nestedGroups) {
                    $nestedDesc = (Get-ADGroup -Identity $n.DistinguishedName -Properties Description -ErrorAction SilentlyContinue).Description
                    $results += [PSCustomObject]@{
                        UserName         = $UserSam
                        GroupName        = $n.Name
                        GroupDescription = $nestedDesc
                        Domain           = $DomainName
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "→ Konnte Gruppen für Benutzer '$UserSam' nicht ermitteln: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------------------
#                             ANALYSE
# ----------------------------------------------------------------------------

try {
    if ($Mode -eq "Group") {
        $groups = Get-ADGroup -SearchBase $OUPath -Server $DomainName -Filter * -Properties Description
        foreach ($g in $groups) {
            Write-Host "Analysiere Gruppe: $($g.Name)" -ForegroundColor Cyan
            Get-GroupMembers -GroupDN $g.DistinguishedName -GroupName $g.Name -GroupDescription $g.Description
        }
    }
    elseif ($Mode -eq "User") {
        $users = Get-ADUser -SearchBase $OUPath -Server $DomainName -Filter * -Properties SamAccountName
        foreach ($u in $users) {
            Write-Host "Analysiere Benutzer: $($u.SamAccountName)" -ForegroundColor Cyan
            Get-UserGroups -UserSam $u.SamAccountName
        }
    }
}
catch {
    Write-Error "Ein unerwarteter Fehler ist aufgetreten: $($_.Exception.Message)"
    exit 1
}

# ----------------------------------------------------------------------------
#                             EXPORT
# ----------------------------------------------------------------------------

if ($results.Count -gt 0) {
    Write-Host "`nEinträge gefunden: $($results.Count)" -ForegroundColor Green
    Write-Host "Exportiere nach: $OutputFile" -ForegroundColor Yellow
    $results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
    Write-Host "Export abgeschlossen." -ForegroundColor Green
} else {
    Write-Host "Keine Ergebnisse gefunden." -ForegroundColor Yellow
}

Write-Host "`nSkript erfolgreich beendet." -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════"