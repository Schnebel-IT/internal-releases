# Requires -Module Microsoft.Graph

<#
.SYNOPSIS
    Exportiert eine CSV-Datei mit Microsoft 365 Benutzern, deren zugewiesenen Gruppen und Lizenzen.

.DESCRIPTION
    Dieses Skript verbindet sich mit Microsoft Graph, liest alle Microsoft 365 Benutzer,
    ermittelt deren direkte Gruppenzuweisungen und die zugewiesenen Lizenzen.
    Die gesammelten Informationen werden dann in eine CSV-Datei exportiert.

.NOTES
    Autor: T3 Chat (Angepasst für Schnebel-IT)
    Datum: 26. Mai 2025
    Version: 1.0
    Voraussetzung: Microsoft.Graph PowerShell Modul.
                   Der ausführende Benutzer benötigt entsprechende Microsoft Graph API Berechtigungen
                   (z.B. User.Read.All, Group.Read.All, Directory.Read.All).
#>

$OutputCSVPath = Join-Path -Path $PSScriptRoot -ChildPath "M365_User_Report_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

Write-Host "Verbinde mich mit Microsoft Graph..." -ForegroundColor Cyan

try {
    # Verbinde dich mit Microsoft Graph. Es öffnet sich ein Authentifizierungsfenster.
    # Die benötigten Scopes für Benutzer, Gruppen und Lizenzen.
    Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Directory.Read.All"
    Write-Host "Erfolgreich mit Microsoft Graph verbunden." -ForegroundColor Green
}
catch {
    Write-Host "Fehler beim Verbinden mit Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Bitte stelle sicher, dass das 'Microsoft.Graph' Modul installiert ist und du die nötigen Berechtigungen hast." -ForegroundColor Yellow
    Exit
}

Write-Host "Lese alle Microsoft 365 Benutzer..." -ForegroundColor Cyan

$allUsers = @()
try {
    # Holen aller Benutzer. -All bringt alle Benutzer, nicht nur die ersten 100.
    $allUsers = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, AssignedLicenses, AssignedPlans | Select-Object Id, DisplayName, UserPrincipalName, AssignedLicenses, AssignedPlans
    Write-Host "Anzahl der gefundenen Benutzer: $($allUsers.Count)" -ForegroundColor Green
}
catch {
    Write-Host "Fehler beim Abrufen der Benutzer: $($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph
    Exit
}

$userReport = @()

foreach ($user in $allUsers) {
    Write-Host "Verarbeite Benutzer: $($user.UserPrincipalName)" -ForegroundColor DarkGray

    # --- Gruppen lesen ---
    $groups = @()
    try {
        # Get-MgUserMemberOf liefert die direkten Gruppenmitgliedschaften
        # Wir wählen nur den DisplayName der Gruppe aus
        $groups = (Get-MgUserMemberOf -UserId $user.Id -All | Select-Object DisplayName)
        $groupNames = if ($groups) { $groups.DisplayName -join "; " } else { "Keine Gruppen" }
    }
    catch {
        Write-Host "Warnung: Konnte Gruppen für Benutzer $($user.UserPrincipalName) nicht lesen. Fehler: $($_.Exception.Message)" -ForegroundColor Yellow
        $groupNames = "Fehler beim Lesen der Gruppen"
    }

    # --- Lizenzen lesen ---
    $assignedLicenses = @()
    if ($user.AssignedLicenses) {
        # AssignedLicenses enthält ProductId (GUIDs) und SkuId (GUIDs)
        # AssignedPlans enthält die ServicePlans (z.B. EXCHANGE_ONLINE, TEAMS_EXPLORATORY)
        # Wir müssen die GUIDs zu lesbaren Namen mappen.

        # Hier wirds etwas komplexer, da M365 keine direkten Namen liefert.
        # Eine vollständige Liste der SKUs findest du hier:
        # https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference

        # Für eine vereinfachte Anzeige nutzen wir die ServicePlans oder ProductIds
        # Wenn ihr eine exakte Map braucht, müsstet ihr eine Liste von GUIDs zu Namen pflegen.

        $licenseNames = @()
        foreach ($license in $user.AssignedLicenses) {
            # Hier versuchen wir, die Lizenzen über die AssignedPlans zu identifizieren
            # Dies gibt die zugewiesenen Dienste innerhalb einer Lizenz wieder.
            # Für den tatsächlichen Lizenznamen (z.B. "Microsoft 365 E3")
            # müsste man die ProductId gegen eine bekannte Liste mappen.
            # Da das Skript einfach gehalten sein soll, liste ich die Services auf.

            # Alternativ: Könnten wir die ProductId oder SkuId anzeigen lassen.
            # $licenseNames += "ProductID: $($license.ProductId)"
            # $licenseNames += "SkuId: $($license.SkuId)"

            # Bessere Annäherung: Wenn ServicePlans vorhanden sind, nutze sie.
            $planDetails = $user.AssignedPlans | Where-Object { $_.AssignedDateTime -and $_.ServicePlanId -and $_.CapabilityStatus -eq 'Enabled' }
            if ($planDetails.Count -gt 0) {
                 # Beispiel: Ein Benutzer hat mehrere Pläne (Exchange, Teams, SharePoint).
                 # Wenn man den genauen Lizenznamen (E3, Business Standard) möchte,
                 # muss man die SKUs über die Graph API abfragen oder eine statische Liste nutzen.
                 # Für dieses Skript, das einfach halten will, listen wir die aktivierten Dienste auf.
                 $licenseNames += ($planDetails.ServicePlanId | ForEach-Object {
                    # Hier könnte man eine Map für ServicePlan IDs zu lesbaren Namen einbauen
                    # Bsp: 'a909407f-023a-4422-88f5-195f190c6a52' ist 'TEAMS_EXPLORATORY'
                    # Ohne eine solche Map zeigen wir die ID
                    "ServicePlan ID: $_" # Oder eine statische Zuordnungstabelle verwenden
                 })
                 $licenseNames = $licenseNames | Select-Object -Unique # Duplikate entfernen
            } else {
                 $licenseNames += "Unbekannte Lizenz (Keine Pläne gefunden)"
            }
        }
        $assignedLicensesString = if ($licenseNames.Count -gt 0) { $licenseNames -join "; " } else { "Keine Lizenzen" }
    } else {
        $assignedLicensesString = "Keine Lizenzen"
    }

    # --- Report Objekt erstellen ---
    $userObject = [PSCustomObject]@{
        DisplayName     = $user.DisplayName
        UserPrincipalName = $user.UserPrincipalName
        Groups          = $groupNames
        Licenses        = $assignedLicensesString
    }
    $userReport += $userObject
}

Write-Host "Exportiere Daten nach '$OutputCSVPath'..." -ForegroundColor Cyan

if ($userReport.Count -gt 0) {
    $userReport | Export-Csv -Path $OutputCSVPath -NoTypeInformation -Encoding UTF8
    Write-Host "Bericht erfolgreich exportiert nach: $OutputCSVPath" -ForegroundColor Green
} else {
    Write-Host "Keine Benutzerdaten zum Exportieren gefunden." -ForegroundColor Yellow
}

# Trenne die Verbindung zu Microsoft Graph
Write-Host "Trenne die Verbindung zu Microsoft Graph..." -ForegroundColor Cyan
Disconnect-MgGraph
Write-Host "Skript abgeschlossen." -ForegroundColor Green