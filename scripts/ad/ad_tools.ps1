<#
.SYNOPSIS
    Startmenue fuer die AD-Berichte (Gruppen, Benutzer, NTFS-Berechtigungen).

.DESCRIPTION
    Zeigt ein Menue und startet das gewaehlte Skript im Assistenten-Modus. Liegt das
    Skript neben dieser Datei (Repository-Checkout), wird die lokale Kopie verwendet,
    sonst die aktuelle Version von GitHub.

.PARAMETER Report
    Bericht direkt waehlen, ohne Menue: Groups, Users oder Permissions.

.EXAMPLE
    .\ad_tools.ps1

.NOTES
    Autor:     Luca Baumann
    Version:   2.0
    Geaendert: 06.10.2026
#>
[CmdletBinding()]
param(
    [ValidateSet('Groups', 'Users', 'Permissions')]
    [string]$Report
)

$ErrorActionPreference = 'Stop'
$RepositoryUrl = 'https://raw.githubusercontent.com/Schnebel-IT/internal-releases/refs/heads/main/scripts/ad'
$Reports = [ordered]@{
    Groups      = @{ File = 'groups/list_ad_groups.ps1';        Title = 'AD-Gruppenbericht         Gruppen -> Mitglieder / Benutzer -> Gruppen' }
    Users       = @{ File = 'users/list_users.ps1';             Title = 'AD-Benutzerbericht        Status, letzte Anmeldung, Service-Konten' }
    Permissions = @{ File = 'permissions/list_permissions.ps1'; Title = 'NTFS-Berechtigungsbericht Ordnerrechte bis zur gewaehlten Tiefe' }
}

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor DarkCyan
Write-Host '  AD-Berichte' -ForegroundColor Cyan -NoNewline
Write-Host '  v2.0' -ForegroundColor DarkGray
Write-Host '  Schnebel IT - internal-releases' -ForegroundColor DarkGray
Write-Host ('=' * 72) -ForegroundColor DarkCyan

if (-not $Report) {
    Write-Host ''
    $keys = @($Reports.Keys)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        Write-Host ('    {0}) ' -f ($i + 1)) -ForegroundColor Cyan -NoNewline
        Write-Host $Reports[$keys[$i]].Title
    }
    Write-Host '    q) ' -ForegroundColor Cyan -NoNewline
    Write-Host 'Beenden'
    while (-not $Report) {
        Write-Host ''
        Write-Host '  ? ' -ForegroundColor Cyan -NoNewline
        Write-Host 'Auswahl: ' -NoNewline
        $answer = (Read-Host).Trim()
        if ($answer -match '^(q|x|exit)$') { return }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $keys.Count) { $Report = $keys[$number - 1] }
        else { Write-Host "  Bitte 1 bis $($keys.Count) oder q eingeben." -ForegroundColor Yellow }
    }
}

$entry = $Reports[$Report]
$localPath = $null
if ($PSScriptRoot) { $localPath = Join-Path $PSScriptRoot $entry.File }

if ($localPath -and (Test-Path -LiteralPath $localPath)) {
    & $localPath
}
else {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $code = Invoke-RestMethod -UseBasicParsing -Uri "$RepositoryUrl/$($entry.File)"
    }
    catch {
        Write-Host "  [FAIL] Download fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    & ([scriptblock]::Create($code))
}
