# Requires -Module Microsoft.Graph, ExchangeOnlineManagement

# Sicherstellen, dass die benötigten Sub-Module geladen sind
Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Groups -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Applications -ErrorAction SilentlyContinue
Import-Module ExchangeOnlineManagement -ErrorAction SilentlyContinue

<#
.SYNOPSIS
    Exportiert eine CSV-Datei mit Microsoft 365 Benutzern, deren zugewiesenen Gruppen,
    Lizenzen und Zugriffe auf freigegebene Postfächer.

.DESCRIPTION
    Dieses Skript verbindet sich mit Microsoft Graph und Exchange Online,
    liest alle Microsoft 365 Benutzer, ermittelt deren direkte Gruppenzuweisungen,
    die zugewiesenen Lizenzen (mit lesbaren Namen) und eine Liste der freigegebenen
    Postfächer, auf die der Benutzer direkten Zugriff hat.
    Die gesammelten Informationen werden dann in eine CSV-Datei exportiert.

.NOTES
    Autor: T3 Chat (Angepasst für Schnebel-IT)
    Datum: 27. Mai 2025
    Version: 3.0
    Voraussetzung: 
    - Microsoft.Graph PowerShell Modul
    - ExchangeOnlineManagement Modul (für freigegebene Postfächer)
    Der ausführende Benutzer benötigt entsprechende Berechtigungen in Microsoft 365.
#>

$OutputCSVPath = Join-Path -Path $PSScriptRoot -ChildPath "M365_User_Report_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

# --- Prüfen, ob die benötigten Module installiert sind ---
$modulesNeeded = @("Microsoft.Graph", "ExchangeOnlineManagement")
$missingModules = @()

foreach ($module in $modulesNeeded) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        $missingModules += $module
    }
}

if ($missingModules.Count -gt 0) {
    Write-Host "FEHLER: Die folgenden Module werden benötigt, sind aber nicht installiert:" -ForegroundColor Red
    foreach ($module in $missingModules) {
        Write-Host "  - $module" -ForegroundColor Red
    }
    Write-Host "Bitte installiere die fehlenden Module mit:" -ForegroundColor Yellow
    Write-Host "Install-Module -Name <ModulName> -Scope CurrentUser -Force" -ForegroundColor Yellow
    Exit
}

# --- Verbindung zu Microsoft Graph herstellen ---
Write-Host "Verbinde mich mit Microsoft Graph..." -ForegroundColor Cyan

try {
    Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Directory.Read.All"
    Write-Host "Erfolgreich mit Microsoft Graph verbunden." -ForegroundColor Green
}
catch {
    Write-Host "Fehler beim Verbinden mit Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
    Exit
}

# --- Verbindung zu Exchange Online herstellen ---
Write-Host "Verbinde mich mit Exchange Online..." -ForegroundColor Cyan

try {
    Connect-ExchangeOnline -ShowBanner:$false
    Write-Host "Erfolgreich mit Exchange Online verbunden." -ForegroundColor Green
}
catch {
    Write-Host "Fehler beim Verbinden mit Exchange Online: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Die Informationen zu freigegebenen Postfächern werden nicht verfügbar sein." -ForegroundColor Yellow
    # Wir brechen nicht ab, sondern machen ohne Exchange Online weiter
}

# --- Alle Benutzer abrufen ---
Write-Host "Lese alle Microsoft 365 Benutzer..." -ForegroundColor Cyan

$allUsers = @()
try {
    $allUsers = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, AssignedLicenses | 
                Select-Object Id, DisplayName, UserPrincipalName, AssignedLicenses
    Write-Host "Anzahl der gefundenen Benutzer: $($allUsers.Count)" -ForegroundColor Green
}
catch {
    Write-Host "Fehler beim Abrufen der Benutzer: $($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph
    if (Get-Command -Name Disconnect-ExchangeOnline -ErrorAction SilentlyContinue) {
        Disconnect-ExchangeOnline -Confirm:$false
    }
    Exit
}

# --- Alle freigegebenen Postfächer abrufen (über Exchange Online) ---
$sharedMailboxes = @()
try {
    if (Get-Command -Name Get-Mailbox -ErrorAction SilentlyContinue) {
        Write-Host "Lese alle freigegebenen Postfächer..." -ForegroundColor Cyan
        $sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited | 
                           Select-Object DisplayName, PrimarySmtpAddress, Identity
        Write-Host "Anzahl der gefundenen freigegebenen Postfächer: $($sharedMailboxes.Count)" -ForegroundColor Green
    }
    else {
        Write-Host "Exchange Online Verbindung nicht verfügbar. Freigegebene Postfächer können nicht abgerufen werden." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Fehler beim Abrufen der freigegebenen Postfächer: $($_.Exception.Message)" -ForegroundColor Yellow
    # Wir brechen nicht ab, sondern machen ohne freigegebene Postfächer weiter
}

# --- Lizenz-Mapping-Tabelle ---
# Diese Tabelle ordnet die SKU-IDs den lesbaren Lizenznamen zu
$licenseTable = @{
    # Microsoft 365 / Office 365 Lizenzen
    "c7df2760-2c81-4ef7-b578-5b5392b571df" = "Microsoft 365 A5 für Lehrkräfte"
    "05e9a617-0261-4cee-bb44-138d3ef5d965" = "Microsoft 365 E3"
    "06ebc4ee-1bb5-47dd-8120-11324bc54e06" = "Microsoft 365 E5"
    "d61d61cc-f992-433f-a577-5bd016037eeb" = "Microsoft 365 E3 Developer"
    "4b590615-0888-425a-a965-b3bf7789848d" = "Microsoft 365 F3"
    "3b555118-da6a-4418-894f-7df1e2096870" = "Microsoft 365 Business Basic"
    "dab7782a-93b1-4074-8bb1-0e61318bea0b" = "Microsoft 365 Business Standard"
    "cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46" = "Microsoft 365 Business Premium"
    "18181a46-0d4e-45cd-891e-60aabd171b4e" = "Office 365 E1"
    "6fd2c87f-b296-42f0-b197-1e91e994b900" = "Office 365 E3"
    "4b585984-651b-448a-9e53-3b10f069cf7f" = "Office 365 F3"
    
    # Exchange Online Lizenzen
    "4a9b13d0-2a11-4514-9181-28e71f4a6fc4" = "Exchange Online (Plan 1)"
    "19ec0d23-8335-4cbd-94ac-6050e30712fa" = "Exchange Online (Plan 2)"
    "ee02fd1b-340e-4a4b-b355-4a514e4c8943" = "Exchange Online Archiving"
    
    # SharePoint & OneDrive Lizenzen
    "5dbe027f-2339-4123-9542-606e4d348a72" = "SharePoint Online (Plan 1)"
    "a9732ec9-17d9-494c-a51c-d6b45b384dcb" = "SharePoint Online (Plan 2)"
    "e95bec33-7c88-4a70-8e19-b10bd9d0c014" = "OneDrive for Business (Plan 1)"
    
    # Teams Lizenzen
    "57ff2da0-773e-42df-b2af-ffb7a2317929" = "Teams (Kostenlos)"
    "b05e124f-c7cc-45a0-a68e-57b12759e62e" = "Teams Essentials"
    
    # Visio & Project Lizenzen
    "4a03357b-4608-4a1a-95e4-3e6b3c3f3bbb" = "Visio Plan 1"
    "c5928f49-12ba-48f7-ada3-0d743a3601d5" = "Visio Plan 2"
    "53818b1b-4a27-454b-8896-0dba576410e6" = "Project Plan 1"
    "f82a60b8-1ee3-4cfb-a4fe-1c6a53c2656c" = "Project Plan 3"
    "09015f9f-377f-4538-bbb5-f75ceb09358a" = "Project Plan 5"
    
    # Azure AD Lizenzen
    "078d2b04-f1bd-4111-bbd4-b4b1b354cef4" = "Azure AD Premium P1"
    "84a661c4-e949-4bd2-a560-ed7766fcaf2b" = "Azure AD Premium P2"
    
    # Sicherheitslizenzen
    "80b2d799-d2ba-4d2a-8842-fb0d0f3a4b82" = "Microsoft Defender for Office 365 (Plan 1)"
    "111046dd-295b-4d6d-9724-d52ac90bd1f2" = "Microsoft Defender for Office 365 (Plan 2)"
    
    # Weitere häufige Lizenzen
    "4828c8ec-dc2e-4779-b502-87ac9ce28ab7" = "Power BI Free"
    "a403ebcc-fae0-4ca2-8c8c-7a907fd6c235" = "Power BI Pro"
    "45bc2c81-6072-436a-9b0b-3b12eefbc402" = "Power BI Premium"
    "dcb1a3ae-b33f-4487-846a-a640262fadf4" = "Power Apps Plan 1"
    "6a1a5366-f698-4841-b6e1-6a864c4e13e6" = "Power Apps Plan 2"
    "f30db892-07e9-47e9-837c-80727f46fd3d" = "Power Automate Free"
    "41781fb2-bc02-4b7c-bd55-b576c07bb09d" = "Power Automate Plan 1"
    "50e68c76-46c6-4674-81f9-75456511b170" = "Power Automate Plan 2"
}

$userReport = @()

foreach ($user in $allUsers) {
    Write-Host "Verarbeite Benutzer: $($user.UserPrincipalName)" -ForegroundColor DarkGray

    # --- Gruppen lesen ---
    $groupNames = "Keine Gruppen"
    try {
        $groups = Get-MgUserMemberOf -UserId $user.Id -All | 
                  Where-Object { $_.AdditionalProperties.ContainsKey('displayName') } | 
                  Select-Object -ExpandProperty AdditionalProperties | 
                  Select-Object displayName
        
        if ($groups -and $groups.Count -gt 0) {
            $groupNames = ($groups.displayName -join "; ")
        }
    }
    catch {
        Write-Host "Warnung: Konnte Gruppen für Benutzer $($user.UserPrincipalName) nicht lesen. Fehler: $($_.Exception.Message)" -ForegroundColor Yellow
        $groupNames = "Fehler beim Lesen der Gruppen"
    }

    # --- Lizenzen lesen ---
    $licensesString = "Keine Lizenzen"
    try {
        if ($user.AssignedLicenses -and $user.AssignedLicenses.Count -gt 0) {
            $licenseNames = @()
            
            foreach ($license in $user.AssignedLicenses) {
                $skuId = $license.SkuId
                
                if ($licenseTable.ContainsKey($skuId)) {
                    $licenseNames += $licenseTable[$skuId]
                } else {
                    # Wenn die SKU-ID nicht in unserer Tabelle ist, zeigen wir die ID an
                    $licenseNames += "Unbekannte Lizenz (SKU: $skuId)"
                }
            }
            
            if ($licenseNames.Count -gt 0) {
                $licensesString = ($licenseNames -join "; ")
            }
        }
    }
    catch {
        Write-Host "Warnung: Konnte Lizenzen für Benutzer $($user.UserPrincipalName) nicht lesen. Fehler: $($_.Exception.Message)" -ForegroundColor Yellow
        $licensesString = "Fehler beim Lesen der Lizenzen"
    }

    # --- Freigegebene Postfächer lesen (über Exchange Online) ---
    $sharedMailboxAccessString = "Keine freigegebenen Postfächer"
    
    try {
        if (Get-Command -Name Get-MailboxPermission -ErrorAction SilentlyContinue) {
            $mailboxPermissions = @()
            
            # Für jeden Benutzer prüfen wir alle freigegebenen Postfächer
            foreach ($sharedMailbox in $sharedMailboxes) {
                # Prüfen, ob der Benutzer Berechtigungen auf dieses Postfach hat
                $permissions = Get-MailboxPermission -Identity $sharedMailbox.Identity | 
                               Where-Object { 
                                   $_.User -like "*$($user.UserPrincipalName)*" -or 
                                   $_.User -like "*$($user.DisplayName)*" 
                               }
                
                if ($permissions) {
                    # Wenn Berechtigungen gefunden wurden, fügen wir das Postfach zur Liste hinzu
                    $mailboxPermissions += "$($sharedMailbox.DisplayName) ($($permissions.AccessRights -join ', '))"
                }
            }
            
            if ($mailboxPermissions.Count -gt 0) {
                $sharedMailboxAccessString = ($mailboxPermissions -join "; ")
            }
        }
    }
    catch {
        Write-Host "Warnung: Konnte freigegebene Postfächer für Benutzer $($user.UserPrincipalName) nicht lesen. Fehler: $($_.Exception.Message)" -ForegroundColor Yellow
        $sharedMailboxAccessString = "Fehler beim Lesen der freigegebenen Postfächer"
    }

    # --- Report Objekt erstellen ---
    $userObject = [PSCustomObject]@{
        DisplayName           = $user.DisplayName
        UserPrincipalName     = $user.UserPrincipalName
        Groups                = $groupNames
        Licenses              = $licensesString
        SharedMailboxAccesses = $sharedMailboxAccessString
    }
    
    $userReport += $userObject
}

# --- Daten exportieren ---
Write-Host "Exportiere Daten nach '$OutputCSVPath'..." -ForegroundColor Cyan

if ($userReport.Count -gt 0) {
    $userReport | Export-Csv -Path $OutputCSVPath -NoTypeInformation -Encoding UTF8
    Write-Host "Bericht erfolgreich exportiert nach: $OutputCSVPath" -ForegroundColor Green
} else {
    Write-Host "Keine Benutzerdaten zum Exportieren gefunden." -ForegroundColor Yellow
}

# --- Verbindungen trennen ---
Write-Host "Trenne die Verbindungen..." -ForegroundColor Cyan

Disconnect-MgGraph
if (Get-Command -Name Disconnect-ExchangeOnline -ErrorAction SilentlyContinue) {
    Disconnect-ExchangeOnline -Confirm:$false
}

Write-Host "Skript abgeschlossen." -ForegroundColor Green