<#
.SYNOPSIS
    Bericht ueber AD-Gruppenmitgliedschaften: Gruppe -> Mitglieder oder Benutzer -> Gruppen.

.DESCRIPTION
    Zwei Analyserichtungen:
      Group  Fuer jede Gruppe unterhalb der Suchbasis werden alle Mitglieder aufgelistet.
      User   Fuer jeden Benutzer unterhalb der Suchbasis werden alle Gruppen aufgelistet.

    Mit -Recursive werden verschachtelte Mitgliedschaften vollstaendig (beliebige Tiefe)
    aufgeloest. Die Spalte "Membership" zeigt, ob eine Mitgliedschaft direkt (Direct),
    ueber eine verschachtelte Gruppe (Nested) oder ueber die primaere Gruppe (Primary)
    besteht.

    Ohne Parameter gestartet, fragt ein kurzer Assistent alle Optionen ab.
    Ein unterbrochener Lauf (Strg+C, Verbindungsabbruch, Neustart) wird beim naechsten
    Aufruf mit denselben Parametern automatisch fortgesetzt.

.PARAMETER Mode
    Group (Standard) oder User.

.PARAMETER OUPath
    Suchbasis als Distinguished Name, z. B. "OU=Gruppen,DC=firma,DC=local".
    Standard: die gesamte Domaene.

.PARAMETER DomainName
    DNS-Name der Domaene. Standard: Domaene des angemeldeten Benutzers.

.PARAMETER Server
    Fester Domain Controller. Standard: wird automatisch ermittelt und fuer den
    gesamten Lauf beibehalten.

.PARAMETER Recursive
    Verschachtelte Gruppen vollstaendig aufloesen.

.PARAMETER OutputDir
    Zielordner fuer CSV und Logs. Standard: C:\Temp\ADReports

.PARAMETER OutputFile
    Fester Pfad der CSV-Datei (ueberschreibt OutputDir).

.PARAMETER Delimiter
    CSV-Trennzeichen. Standard: ";" (passt zu Excel mit deutschen Einstellungen).

.PARAMETER Fresh
    Einen unterbrochenen Lauf verwerfen und neu beginnen.

.EXAMPLE
    .\list_ad_groups.ps1

    Startet den Assistenten.

.EXAMPLE
    .\list_ad_groups.ps1 -Mode Group -OUPath "OU=Gruppen,DC=firma,DC=local" -Recursive

.EXAMPLE
    .\list_ad_groups.ps1 -Mode User -OUPath "OU=Benutzer,DC=firma,DC=local"

.NOTES
    Autor:     Luca Baumann
    Version:   2.0
    Geaendert: 06.10.2026
#>
[CmdletBinding()]
param(
    [ValidateSet('Group', 'User')]
    [string]$Mode = 'Group',

    [Alias('SearchBase', 'OU')]
    [string]$OUPath,

    [Alias('Domain')]
    [string]$DomainName,

    [string]$Server,

    [switch]$Recursive,

    [string]$OutputDir = 'C:\Temp\ADReports',

    [string]$OutputFile,

    [char]$Delimiter = ';',

    [switch]$Fresh
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '2.0'
$ScriptFile = 'list_ad_groups.ps1'

#region ADReportKit 2.0
# ----------------------------------------------------------------------------
#  Shared UI, retry and resume helpers.
#  This region is identical in every script under scripts/ad, so that each
#  file stays standalone and can be run directly from GitHub (irm one-liner).
#  When changing it, copy the whole region into the other scripts as well.
# ----------------------------------------------------------------------------

$ReportKit = @{
    Width         = 72
    Utf8Bom       = New-Object System.Text.UTF8Encoding($true)
    Utf8NoBom     = New-Object System.Text.UTF8Encoding($false)
    RunWatch      = [System.Diagnostics.Stopwatch]::StartNew()
    ProgressWatch = [System.Diagnostics.Stopwatch]::StartNew()
    BeatWatch     = [System.Diagnostics.Stopwatch]::StartNew()
    LoopWatch     = [System.Diagnostics.Stopwatch]::StartNew()
    Activity      = ''
    LoopBase      = 0
    IssuesShown   = 0
    MaxIssuesShown = 25
    SidNames      = @{}
    Job           = $null
}

# --- Console output ---------------------------------------------------------

function Write-UiRule {
    param([string]$Char = '-', [ConsoleColor]$Color = 'DarkGray')
    Write-Host ($Char * $ReportKit.Width) -ForegroundColor $Color
}

function Write-UiHeader {
    param([string]$Title, [string]$Version, [string]$Subtitle)
    Write-Host ''
    Write-UiRule '=' 'DarkCyan'
    Write-Host '  ' -NoNewline
    Write-Host $Title -ForegroundColor Cyan -NoNewline
    Write-Host "  v$Version" -ForegroundColor DarkGray
    if ($Subtitle) { Write-Host "  $Subtitle" -ForegroundColor Gray }
    Write-Host '  Schnebel IT - internal-releases' -ForegroundColor DarkGray
    Write-UiRule '=' 'DarkCyan'
}

function Write-UiSection {
    param([string]$Title)
    Write-Host ''
    Write-Host ('  ' + $Title.ToUpperInvariant()) -ForegroundColor White
    Write-UiRule '-'
}

function Write-UiField {
    param([string]$Name, [string]$Value, [ConsoleColor]$Color = 'White')
    Write-Host ('  {0,-22}' -f $Name) -ForegroundColor Gray -NoNewline
    if ([string]::IsNullOrEmpty($Value)) { Write-Host '-' -ForegroundColor DarkGray }
    else { Write-Host $Value -ForegroundColor $Color }
}

function Write-UiStatus {
    param(
        [ValidateSet('Ok', 'Info', 'Warn', 'Fail', 'Step')][string]$Level,
        [string]$Message
    )
    $tag, $color = switch ($Level) {
        'Ok'   { ' OK ', 'Green' }
        'Info' { 'INFO', 'Cyan' }
        'Warn' { 'WARN', 'Yellow' }
        'Fail' { 'FAIL', 'Red' }
        'Step' { ' .. ', 'DarkGray' }
    }
    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host $tag -NoNewline -ForegroundColor $color
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Message
}

function Write-UiCommandHint {
    param([string]$ScriptFile, [System.Collections.IDictionary]$Parameters)
    $parts = foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]
        if ($value -is [bool] -or $value -is [System.Management.Automation.SwitchParameter]) {
            if ($value) { "-$key" }
        }
        elseif ($null -ne $value -and "$value" -ne '') {
            "-$key '{0}'" -f ("$value" -replace "'", "''")
        }
    }
    Write-Host ''
    Write-Host '  Gleicher Lauf ohne Assistent:' -ForegroundColor Gray
    Write-Host "  .\$ScriptFile $($parts -join ' ')" -ForegroundColor DarkCyan
}

function Format-UiNumber {
    param([double]$Value)
    '{0:N0}' -f $Value
}

function Format-UiDuration {
    param([TimeSpan]$Span)
    if ($Span.TotalHours -ge 24) { return '{0}d {1:hh\:mm\:ss}' -f [int][Math]::Floor($Span.TotalDays), $Span }
    '{0:hh\:mm\:ss}' -f $Span
}

# --- Progress ---------------------------------------------------------------

function Start-UiProgress {
    param([string]$Activity, [int]$AlreadyDone = 0)
    $ReportKit.Activity = $Activity
    $ReportKit.LoopBase = $AlreadyDone
    $ReportKit.LoopWatch.Restart()
    $ReportKit.BeatWatch.Restart()
}

# Throttled: Write-Progress on every item slows Windows PowerShell 5.1 down a lot.
# A plain status line every 30 seconds keeps transcripts and scheduled tasks informative.
function Write-UiProgress {
    param([int]$Current, [int]$Total = 0, [string]$Item)
    if ($ReportKit.ProgressWatch.ElapsedMilliseconds -lt 300) { return }
    $ReportKit.ProgressWatch.Restart()

    $processed = $Current - $ReportKit.LoopBase
    $seconds = $ReportKit.LoopWatch.Elapsed.TotalSeconds
    $status = if ($Total -gt 0) { '{0} / {1}' -f (Format-UiNumber $Current), (Format-UiNumber $Total) } else { Format-UiNumber $Current }
    $percent = -1
    if ($Total -gt 0) {
        $percent = [Math]::Min(100, [int](100 * $Current / $Total))
        $status += " ($percent %)"
        if ($processed -gt 0 -and $seconds -gt 5) {
            $remaining = [TimeSpan]::FromSeconds(($Total - $Current) * $seconds / $processed)
            $status += ' - Rest ca. ' + (Format-UiDuration $remaining)
        }
    }
    $operation = if ($Item -and $Item.Length -gt 90) { '...' + $Item.Substring($Item.Length - 87) } else { $Item }
    $progressArgs = @{ Activity = $ReportKit.Activity; Status = $status; PercentComplete = $percent }
    if ($operation) { $progressArgs.CurrentOperation = $operation }
    Write-Progress @progressArgs

    if ($ReportKit.BeatWatch.Elapsed.TotalSeconds -ge 30) {
        $ReportKit.BeatWatch.Restart()
        Write-UiStatus Step $status
    }
}

function Stop-UiProgress {
    Write-Progress -Activity ($(if ($ReportKit.Activity) { $ReportKit.Activity } else { 'Bericht' })) -Completed
}

# --- Input ------------------------------------------------------------------

function Test-UiInteractive {
    if (-not [Environment]::UserInteractive) { return $false }
    if ($Host.Name -eq 'Default Host') { return $false }
    foreach ($arg in [Environment]::GetCommandLineArgs()) {
        if ($arg -match '^-noni') { return $false }
    }
    $true
}

function Read-UiValue {
    param([string]$Prompt, [string]$Default)
    Write-Host '  ? ' -ForegroundColor Cyan -NoNewline
    Write-Host $Prompt -NoNewline
    if ($Default) { Write-Host " [$Default]" -ForegroundColor DarkGray -NoNewline }
    Write-Host ': ' -NoNewline
    $answer = Read-Host
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    $answer.Trim().Trim('"')
}

function Read-UiChoice {
    param([string]$Prompt, [string[]]$Options, [int]$Default = 1)
    Write-Host '  ? ' -ForegroundColor Cyan -NoNewline
    Write-Host $Prompt
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ('      {0}) ' -f ($i + 1)) -ForegroundColor Cyan -NoNewline
        Write-Host $Options[$i]
    }
    while ($true) {
        $answer = Read-UiValue -Prompt 'Auswahl' -Default "$Default"
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Options.Count) { return $number }
        Write-UiStatus Warn "Bitte eine Zahl von 1 bis $($Options.Count) eingeben."
    }
}

function Read-UiYesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $hint = if ($Default) { 'J/n' } else { 'j/N' }
    while ($true) {
        $answer = Read-UiValue -Prompt "$Prompt ($hint)" -Default ''
        if (-not $answer) { return $Default }
        if ($answer -match '^(j|ja|y|yes)$') { return $true }
        if ($answer -match '^(n|nein|no)$') { return $false }
    }
}

# --- Helpers ----------------------------------------------------------------

function Resolve-UiPath {
    param([string]$Path)
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Resolve-SidName {
    param([string]$Sid)
    if ($ReportKit.SidNames.ContainsKey($Sid)) { return $ReportKit.SidNames[$Sid] }
    $name = $Sid
    try {
        $identifier = New-Object System.Security.Principal.SecurityIdentifier($Sid)
        $name = $identifier.Translate([System.Security.Principal.NTAccount]).Value
    }
    catch { }
    $ReportKit.SidNames[$Sid] = $name
    $name
}

function Test-TransientError {
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($exception) {
        $type = $exception.GetType().Name
        if ($type -match 'ServerDown|Timeout|Communication|EndpointNotFound|ServerBusy|ServiceUnavailable') { return $true }
        if ($exception.Message -match 'not operational|nicht funktionsf|timed out|Zeitlimit|Timeout|Web Services|Webdienste|unable to contact|busy|ausgelastet') { return $true }
        $exception = $exception.InnerException
    }
    $false
}

# Runs a script block and retries it with back-off when the error looks transient
# (DC unreachable, ADWS timeout). Permanent errors are rethrown immediately.
function Invoke-WithRetry {
    param([scriptblock]$RetryAction, [int]$RetryAttempts = 3)
    for ($retryIndex = 1; ; $retryIndex++) {
        try {
            return (& $RetryAction)
        }
        catch {
            if ($retryIndex -ge $RetryAttempts -or -not (Test-TransientError $_)) { throw }
            Start-Sleep -Seconds ([int][Math]::Pow(2, $retryIndex))
        }
    }
}

# --- Resumable job ----------------------------------------------------------
#
#  Rows are appended to the CSV in batches. After every batch one line is
#  appended to "<csv>.progress":   C <tab> csvBytes <tab> rowCount <tab> key...
#  On resume, the CSV is cut back to the byte length of the last complete
#  progress line, so an interruption at any point never duplicates or loses
#  rows. The progress file is deleted when the run completes.

function Get-ReportJobId {
    param([string]$ScriptName, [System.Collections.IDictionary]$Settings)
    $pairs = foreach ($key in ($Settings.Keys | Sort-Object)) { '{0}={1}' -f $key, $Settings[$key] }
    $text = ($ScriptName + '|' + ($pairs -join '|')).ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($ReportKit.Utf8NoBom.GetBytes($text)) } finally { $sha.Dispose() }
    -join ($hash[0..7] | ForEach-Object { $_.ToString('x2') })
}

function Read-ReportJobHeader {
    param([string]$ProgressPath)
    $line = $null
    try {
        $reader = New-Object System.IO.StreamReader($ProgressPath, $ReportKit.Utf8NoBom)
        try { $line = $reader.ReadLine() } finally { $reader.Dispose() }
    }
    catch { return $null }
    if (-not $line) { return $null }
    $fields = $line.Split("`t")
    if ($fields.Count -lt 4 -or $fields[0] -ne '#ADREPORT') { return $null }
    @{ JobId = $fields[2]; Started = $fields[3] }
}

# Returns the CSV path of the newest unfinished run with the same settings, if any.
function Find-ReportJob {
    param([string]$Directory, [string]$JobId)
    if (-not [System.IO.Directory]::Exists($Directory)) { return $null }
    $candidates = Get-ChildItem -LiteralPath $Directory -Filter '*.csv.progress' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    foreach ($file in $candidates) {
        $header = Read-ReportJobHeader $file.FullName
        if ($header -and $header.JobId -eq $JobId) {
            return $file.FullName.Substring(0, $file.FullName.Length - '.progress'.Length)
        }
    }
    $null
}

function Remove-ReportJobs {
    param([string]$Directory, [string]$JobId)
    if (-not [System.IO.Directory]::Exists($Directory)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter '*.csv.progress' -File -ErrorAction SilentlyContinue) {
        $header = Read-ReportJobHeader $file.FullName
        if ($header -and $header.JobId -eq $JobId) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
    }
}

function Set-ReportFileLength {
    param([string]$Path, [int64]$Length)
    if (-not [System.IO.File]::Exists($Path)) { return }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
    try { if ($stream.Length -ne $Length) { $stream.SetLength($Length) } } finally { $stream.Dispose() }
}

function Get-ReportFileLength {
    param([string]$Path)
    if ([System.IO.File]::Exists($Path)) { return (New-Object System.IO.FileInfo($Path)).Length }
    [int64]0
}

function Restore-ReportJob {
    param([hashtable]$Job)
    $bytes = [System.IO.File]::ReadAllBytes($Job.ProgressPath)
    $end = [Array]::LastIndexOf($bytes, [byte]10)
    if ($end -lt 0) { return $false }
    $lines = $ReportKit.Utf8NoBom.GetString($bytes, 0, $end + 1).Split("`n")
    $header = $lines[0].Split("`t")
    if ($header.Count -lt 4 -or $header[0] -ne '#ADREPORT' -or $header[2] -ne $Job.JobId) { return $false }

    $length = [int64]0
    $rows = [int64]0
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $fields = $lines[$i].Split("`t")
        if ($fields.Count -lt 3 -or $fields[0] -ne 'C') { continue }
        $length = [int64]$fields[1]
        $rows = [int64]$fields[2]
        for ($k = 3; $k -lt $fields.Count; $k++) { [void]$Job.Done.Add($fields[$k]) }
    }

    if ((Get-ReportFileLength $Job.CsvPath) -lt $length) {
        Write-UiStatus Warn 'CSV-Datei ist kuerzer als der gespeicherte Fortschritt - der Lauf beginnt neu.'
        $Job.Done.Clear()
        return $false
    }
    Set-ReportFileLength $Job.CsvPath $length
    Set-ReportFileLength $Job.ProgressPath ($end + 1)
    $Job.Started = $header[3]
    $Job.CommittedLength = $length
    $Job.CommittedRows = $rows
    $Job.ResumedItems = $Job.Done.Count
    $true
}

function Open-ReportJob {
    param([string]$CsvPath, [string]$JobId, [char]$Delimiter = ';', [switch]$Resume)
    $job = @{
        CsvPath         = $CsvPath
        ProgressPath    = "$CsvPath.progress"
        ErrorPath       = ($CsvPath -replace '\.csv$', '') + '_Fehler.log'
        JobId           = $JobId
        Delimiter       = $Delimiter
        Done            = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        PendingRows     = New-Object 'System.Collections.Generic.List[object]'
        PendingKeys     = New-Object 'System.Collections.Generic.List[string]'
        FlushWatch      = [System.Diagnostics.Stopwatch]::StartNew()
        CommittedLength = [int64]0
        CommittedRows   = [int64]0
        Started         = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        Resumed         = $false
        ResumedItems    = 0
        Warnings        = 0
        Failures        = 0
        Retryable       = 0
        Completed       = $false
    }
    $directory = [System.IO.Path]::GetDirectoryName($CsvPath)
    if (-not [System.IO.Directory]::Exists($directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }

    if ($Resume -and [System.IO.File]::Exists($job.ProgressPath)) { $job.Resumed = Restore-ReportJob $job }
    if (-not $job.Resumed) {
        foreach ($path in @($job.CsvPath, $job.ProgressPath, $job.ErrorPath)) {
            if ([System.IO.File]::Exists($path)) { [System.IO.File]::Delete($path) }
        }
        $header = "#ADREPORT`t2`t{0}`t{1}`n" -f $JobId, $job.Started
        [System.IO.File]::WriteAllText($job.ProgressPath, $header, $ReportKit.Utf8NoBom)
    }
    $ReportKit.Job = $job
    $job
}

function Test-ReportItemDone {
    param([string]$Key)
    $ReportKit.Job.Done.Contains($Key)
}

# Registers a finished work item and its CSV rows. Writes to disk in batches.
function Add-ReportItem {
    param([string]$Key, $Rows)
    $job = $ReportKit.Job
    foreach ($row in $Rows) { if ($null -ne $row) { $job.PendingRows.Add($row) } }
    $job.PendingKeys.Add($Key)
    [void]$job.Done.Add($Key)
    Save-ReportJob
}

function Save-ReportJob {
    param([switch]$Force)
    $job = $ReportKit.Job
    if (-not $job -or $job.PendingKeys.Count -eq 0) { return }
    if (-not $Force -and $job.PendingKeys.Count -lt 250 -and $job.FlushWatch.ElapsedMilliseconds -lt 5000) { return }

    # Cut off anything an interrupted earlier write may have left behind.
    Set-ReportFileLength $job.CsvPath $job.CommittedLength
    if ($job.PendingRows.Count -gt 0) {
        $lines = @($job.PendingRows | ConvertTo-Csv -NoTypeInformation -Delimiter $job.Delimiter)
        $first = if ($job.CommittedLength -gt 0) { 1 } else { 0 }
        $writer = New-Object System.IO.StreamWriter($job.CsvPath, $true, $ReportKit.Utf8Bom)
        try { for ($i = $first; $i -lt $lines.Count; $i++) { $writer.WriteLine($lines[$i]) } }
        finally { $writer.Dispose() }
    }
    $length = Get-ReportFileLength $job.CsvPath
    $rows = $job.CommittedRows + $job.PendingRows.Count
    $line = "C`t$length`t$rows`t" + [string]::Join("`t", $job.PendingKeys.ToArray()) + "`n"
    [System.IO.File]::AppendAllText($job.ProgressPath, $line, $ReportKit.Utf8NoBom)

    $job.CommittedLength = $length
    $job.CommittedRows = $rows
    $job.PendingRows.Clear()
    $job.PendingKeys.Clear()
    $job.FlushWatch.Restart()
}

# Logs a problem with one item to "<csv>_Fehler.log" and (limited) to the console.
#   Warn      - item was processed, but something is incomplete
#   Fail      - item is skipped for good (e.g. access denied)
#   Retryable - item stays open; running the same command again retries it
function Write-ReportIssue {
    param(
        [string]$Item,
        [string]$Message,
        [ValidateSet('Warn', 'Fail', 'Retryable')][string]$Kind = 'Warn'
    )
    $job = $ReportKit.Job
    switch ($Kind) {
        'Warn'      { $job.Warnings++ }
        'Fail'      { $job.Failures++ }
        'Retryable' { $job.Retryable++ }
    }
    $line = '{0}  {1,-9}  {2}  ->  {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Kind.ToUpperInvariant(), $Item, $Message
    try { [System.IO.File]::AppendAllText($job.ErrorPath, $line + [Environment]::NewLine, $ReportKit.Utf8Bom) } catch { }

    $ReportKit.IssuesShown++
    if ($ReportKit.IssuesShown -le $ReportKit.MaxIssuesShown) {
        $level = if ($Kind -eq 'Warn') { 'Warn' } else { 'Fail' }
        Write-UiStatus $level "$Item - $Message"
    }
    elseif ($ReportKit.IssuesShown -eq $ReportKit.MaxIssuesShown + 1) {
        Write-UiStatus Info 'Weitere Meldungen werden nur noch in die Fehler-Logdatei geschrieben.'
    }
}

# Flushes everything. Deletes the progress file unless items are still open.
function Complete-ReportJob {
    $job = $ReportKit.Job
    Save-ReportJob -Force
    $job.Completed = $true
    if ($job.Retryable -eq 0 -and [System.IO.File]::Exists($job.ProgressPath)) {
        [System.IO.File]::Delete($job.ProgressPath)
    }
}

# Called from the scripts' finally block: keeps progress after Ctrl+C or a crash.
function Stop-ReportJob {
    Stop-UiProgress
    $job = $ReportKit.Job
    if (-not $job -or $job.Completed) { return }
    try { Save-ReportJob -Force } catch { }
    Write-Host ''
    Write-UiStatus Warn 'Lauf wurde nicht abgeschlossen. Der Fortschritt ist gespeichert.'
    Write-UiStatus Info 'Zum Fortsetzen denselben Befehl erneut ausfuehren (oder mit -Fresh neu beginnen).'
}

function Write-ReportSummary {
    param([System.Collections.IDictionary]$Fields)
    $job = $ReportKit.Job
    Write-UiSection 'Ergebnis'
    foreach ($key in $Fields.Keys) { Write-UiField $key $Fields[$key] }
    Write-UiField 'CSV-Zeilen' (Format-UiNumber $job.CommittedRows)
    if ($job.Resumed) { Write-UiField 'Fortgesetzt' ("ja, {0} Elemente aus frueherem Lauf" -f (Format-UiNumber $job.ResumedItems)) }
    $issueColor = if ($job.Failures + $job.Retryable -gt 0) { 'Yellow' } else { 'White' }
    Write-UiField 'Warnungen / Fehler' ('{0} / {1}' -f $job.Warnings, ($job.Failures + $job.Retryable)) $issueColor
    Write-UiField 'Dauer' (Format-UiDuration $ReportKit.RunWatch.Elapsed)
    if ([System.IO.File]::Exists($job.CsvPath)) { Write-UiField 'Datei' $job.CsvPath 'Green' }
    else { Write-UiField 'Datei' 'keine Eintraege gefunden - es wurde keine CSV-Datei erstellt' 'Yellow' }
    if ([System.IO.File]::Exists($job.ErrorPath)) { Write-UiField 'Fehler-Log' $job.ErrorPath 'Yellow' }
    Write-Host ''
    if ($job.Retryable -gt 0) {
        Write-UiStatus Warn ('{0} Elemente konnten wegen Verbindungsproblemen nicht gelesen werden.' -f $job.Retryable)
        Write-UiStatus Info 'Denselben Befehl erneut ausfuehren, um nur diese Elemente nachzuholen.'
    }
    elseif ($job.Failures -gt 0) {
        Write-UiStatus Ok 'Bericht erstellt. Uebersprungene Elemente stehen im Fehler-Log.'
    }
    else {
        Write-UiStatus Ok 'Bericht erfolgreich erstellt.'
    }
    Write-UiRule '=' 'DarkCyan'
}

#endregion ADReportKit

# ----------------------------------------------------------------------------
#  Active Directory helpers
# ----------------------------------------------------------------------------

# RIDs of the well-known groups that are used as primary group. Members of a
# primary group are not listed in its "member" attribute, so they are queried
# separately via primaryGroupID.
$PrimaryGroupRids = @(513, 514, 515, 516, 521)

function Connect-Directory {
    param([string]$DomainName, [string]$Server)
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'Das PowerShell-Modul "ActiveDirectory" fehlt. Server: Install-WindowsFeature RSAT-AD-PowerShell | Client: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
    }
    Import-Module ActiveDirectory -ErrorAction Stop -Verbose:$false

    if (-not $Server) {
        $dcArgs = @{ Discover = $true; Service = 'ADWS'; ErrorAction = 'Stop' }
        if ($DomainName) { $dcArgs.DomainName = $DomainName }
        $dc = Invoke-WithRetry { Get-ADDomainController @dcArgs }
        $Server = [string]($dc.HostName | Select-Object -First 1)
    }
    $domain = Invoke-WithRetry { Get-ADDomain -Server $Server -ErrorAction Stop }
    [pscustomobject]@{
        Server  = $Server
        DnsRoot = $domain.DNSRoot
        NetBios = $domain.NetBIOSName
        DN      = $domain.DistinguishedName
    }
}

function ConvertTo-LdapFilterValue {
    param([string]$Value)
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $Value.ToCharArray()) {
        switch ([int]$char) {
            0x5C { [void]$builder.Append('\5c') }
            0x2A { [void]$builder.Append('\2a') }
            0x28 { [void]$builder.Append('\28') }
            0x29 { [void]$builder.Append('\29') }
            0x00 { [void]$builder.Append('\00') }
            default { [void]$builder.Append($char) }
        }
    }
    $builder.ToString()
}

# "CN=Name\, Vorname,OU=..." -> "Name, Vorname"
function Get-NameFromDn {
    param([string]$DistinguishedName)
    if ($DistinguishedName -match '^[A-Za-z]+=((?:\\.|[^,])+)') { return ($Matches[1] -replace '\\(.)', '$1') }
    $DistinguishedName
}

function Get-MemberName {
    param($Object)
    if ($Object.sAMAccountName) { return [string]$Object.sAMAccountName }
    if ($Object.ObjectClass -eq 'foreignSecurityPrincipal') { return Resolve-SidName ([string]$Object.Name) }
    [string]$Object.Name
}

function Get-MemberEnabled {
    param($Object)
    if ($null -eq $Object.userAccountControl) { return '' }
    if (([int]$Object.userAccountControl -band 2) -eq 2) { 'False' } else { 'True' }
}

$MemberProperties = @('sAMAccountName', 'displayName', 'userAccountControl')

function Get-GroupRows {
    param($Group, $Context, [bool]$Recursive)
    $dnValue = ConvertTo-LdapFilterValue $Group.DistinguishedName
    $filter = if ($Recursive) { "(memberOf:1.2.840.113556.1.4.1941:=$dnValue)" } else { "(memberOf=$dnValue)" }
    $members = @(Invoke-WithRetry {
            Get-ADObject -LDAPFilter $filter -SearchBase $Context.DN -SearchScope Subtree -Server $Context.Server `
                -Properties $MemberProperties -ResultPageSize 1000 -ErrorAction Stop
        })

    $primaryMembers = @()
    $rid = [int]($Group.SID.Value.Split('-')[-1])
    if ($PrimaryGroupRids -contains $rid) {
        $primaryMembers = @(Invoke-WithRetry {
                Get-ADObject -LDAPFilter "(primaryGroupID=$rid)" -SearchBase $Context.DN -SearchScope Subtree -Server $Context.Server `
                    -Properties $MemberProperties -ResultPageSize 1000 -ErrorAction Stop
            })
    }

    $direct = $null
    if ($Recursive) {
        $direct = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($dn in $Group.member) { [void]$direct.Add($dn) }
    }

    $rows = New-Object 'System.Collections.Generic.List[object]'
    $entries = @($members | ForEach-Object { @{ Object = $_; Kind = $null } }) + @($primaryMembers | ForEach-Object { @{ Object = $_; Kind = 'Primary' } })
    foreach ($entry in $entries) {
        $object = $entry.Object
        # Nesting cycles (A in B in A) would list the group as its own member.
        if ($object.DistinguishedName -eq $Group.DistinguishedName) { continue }
        $membership = $entry.Kind
        if (-not $membership) {
            $membership = if (-not $Recursive -or $direct.Contains($object.DistinguishedName)) { 'Direct' } else { 'Nested' }
        }
        $rows.Add([pscustomobject][ordered]@{
                GroupName         = $Group.Name
                Description       = $Group.Description
                MemberName        = Get-MemberName $object
                MemberDisplayName = $object.displayName
                MemberType        = $object.ObjectClass
                MemberEnabled     = Get-MemberEnabled $object
                Membership        = $membership
                Domain            = $Context.DnsRoot
            })
    }
    , [object[]]@($rows | Sort-Object Membership, MemberName)
}

# Group ancestry is resolved in memory from one bulk query, which is much faster
# than asking the DC once per user.
function New-GroupIndex {
    param($Context)
    $index = @{
        ByDn      = New-Object 'System.Collections.Generic.Dictionary[string,object]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        ByRid     = @{}
        Ancestors = New-Object 'System.Collections.Generic.Dictionary[string,object]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    }
    $groups = Invoke-WithRetry {
        Get-ADGroup -Filter * -SearchBase $Context.DN -Server $Context.Server -Properties Description, memberOf -ResultPageSize 1000 -ErrorAction Stop
    }
    foreach ($group in $groups) {
        $index.ByDn[$group.DistinguishedName] = $group
        $index.ByRid[[int]($group.SID.Value.Split('-')[-1])] = $group
    }
    $index
}

function Get-GroupAncestors {
    param($Index, [string]$GroupDn)
    if ($Index.Ancestors.ContainsKey($GroupDn)) { return $Index.Ancestors[$GroupDn] }
    $result = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($GroupDn)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        $group = $null
        if (-not $Index.ByDn.TryGetValue($current, [ref]$group)) { continue }
        foreach ($parent in $group.memberOf) {
            if ($result.Add($parent)) { $stack.Push($parent) }
        }
    }
    [void]$result.Remove($GroupDn)
    $Index.Ancestors[$GroupDn] = $result
    , $result
}

function Get-UserRows {
    param($User, $Index, $Context, [bool]$Recursive)
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)

    $primary = $null
    if ($User.primaryGroupID -and $Index.ByRid.ContainsKey([int]$User.primaryGroupID)) {
        $primary = $Index.ByRid[[int]$User.primaryGroupID].DistinguishedName
        [void]$seen.Add($primary)
        $entries.Add(@{ Dn = $primary; Membership = 'Primary' })
    }
    foreach ($dn in ($User.memberOf | Sort-Object)) {
        if ($seen.Add($dn)) { $entries.Add(@{ Dn = $dn; Membership = 'Direct' }) }
    }
    if ($Recursive) {
        $nested = New-Object 'System.Collections.Generic.List[string]'
        foreach ($entry in $entries.ToArray()) {
            foreach ($ancestor in (Get-GroupAncestors $Index $entry.Dn)) {
                if ($seen.Add($ancestor)) { $nested.Add($ancestor) }
            }
        }
        foreach ($dn in ($nested | Sort-Object)) { $entries.Add(@{ Dn = $dn; Membership = 'Nested' }) }
    }

    $enabled = if ($User.Enabled) { 'True' } else { 'False' }
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $entries) {
        $group = $null
        [void]$Index.ByDn.TryGetValue($entry.Dn, [ref]$group)
        $rows.Add([pscustomobject][ordered]@{
                UserName         = $User.SamAccountName
                DisplayName      = $User.DisplayName
                UserEnabled      = $enabled
                GroupName        = $(if ($group) { $group.Name } else { Get-NameFromDn $entry.Dn })
                GroupDescription = $(if ($group) { $group.Description } else { '' })
                Membership       = $entry.Membership
                Domain           = $Context.DnsRoot
            })
    }
    , $rows
}

# ----------------------------------------------------------------------------
#  Main
# ----------------------------------------------------------------------------

Write-UiHeader 'AD-Gruppenbericht' $ScriptVersion 'Gruppenmitglieder und Gruppenmitgliedschaften'

try {
    $wizard = ($PSBoundParameters.Count -eq 0) -and (Test-UiInteractive)

    Write-UiSection 'Verbindung'
    Write-UiStatus Step 'Suche Domain Controller ...'
    $context = Connect-Directory -DomainName $DomainName -Server $Server
    Write-UiStatus Ok ("Verbunden mit {0} ({1})" -f $context.Server, $context.DnsRoot)

    if ($wizard) {
        Write-UiSection 'Assistent'
        $choice = Read-UiChoice 'Was soll ausgewertet werden?' @('Gruppen -> Mitglieder', 'Benutzer -> Gruppen')
        $Mode = @('Group', 'User')[$choice - 1]
        $OUPath = Read-UiValue 'Suchbasis (OU)' $context.DN
        $Recursive = [System.Management.Automation.SwitchParameter](Read-UiYesNo 'Verschachtelte Gruppen aufloesen?' $true)
        $OutputDir = Read-UiValue 'Zielordner' $OutputDir
    }
    if (-not $OUPath) { $OUPath = $context.DN }

    try { $null = Invoke-WithRetry { Get-ADObject -Identity $OUPath -Server $context.Server -ErrorAction Stop } }
    catch { throw "Suchbasis nicht gefunden: $OUPath" }

    $settings = [ordered]@{ Mode = $Mode; OUPath = $OUPath; Domain = $context.DnsRoot; Recursive = [bool]$Recursive }
    $jobId = Get-ReportJobId $ScriptFile $settings
    $prefix = if ($Mode -eq 'Group') { 'ADGruppen' } else { 'ADBenutzerGruppen' }
    if ($OutputFile) { $csvPath = Resolve-UiPath $OutputFile; $resumePath = $csvPath }
    else {
        $directory = Resolve-UiPath $OutputDir
        $resumePath = if ($Fresh) { Remove-ReportJobs $directory $jobId; $null } else { Find-ReportJob $directory $jobId }
        $csvPath = if ($resumePath) { $resumePath } else { Join-Path $directory ('{0}_{1}.csv' -f $prefix, (Get-Date -Format 'yyyyMMdd_HHmmss')) }
    }

    Write-UiSection 'Einstellungen'
    Write-UiField 'Modus' $(if ($Mode -eq 'Group') { 'Gruppen -> Mitglieder' } else { 'Benutzer -> Gruppen' })
    Write-UiField 'Suchbasis' $OUPath
    Write-UiField 'Domain Controller' $context.Server
    Write-UiField 'Verschachtelung' $(if ($Recursive) { 'vollstaendig aufloesen' } else { 'nur direkte Mitgliedschaften' })
    Write-UiField 'Ausgabe' $csvPath

    if ($wizard) {
        Write-UiCommandHint $ScriptFile ([ordered]@{ Mode = $Mode; OUPath = $OUPath; Recursive = [bool]$Recursive; OutputDir = $OutputDir })
        Write-Host ''
        if (-not (Read-UiYesNo 'Jetzt starten?' $true)) { Write-UiStatus Info 'Abgebrochen.'; return }
    }

    $job = Open-ReportJob -CsvPath $csvPath -JobId $jobId -Delimiter $Delimiter -Resume:([bool]$resumePath -and -not $Fresh)

    Write-UiSection 'Analyse'
    if ($job.Resumed) {
        Write-UiStatus Info ('Unterbrochener Lauf vom {0} wird fortgesetzt ({1} bereits erledigt).' -f $job.Started.Replace('T', ' '), (Format-UiNumber $job.ResumedItems))
    }

    if ($Mode -eq 'Group') {
        Write-UiStatus Step 'Lese Gruppen ...'
        $groupProperties = @('Description')
        if ($Recursive) { $groupProperties += 'member' }
        $groups = @(Invoke-WithRetry {
                Get-ADGroup -Filter * -SearchBase $OUPath -Server $context.Server -Properties $groupProperties -ResultPageSize 1000 -ErrorAction Stop
            } | Sort-Object Name)
        Write-UiStatus Ok ('{0} Gruppen gefunden' -f (Format-UiNumber $groups.Count))

        $emptyGroups = 0
        Start-UiProgress 'Gruppen werden analysiert' $job.Done.Count
        $position = 0
        foreach ($group in $groups) {
            $position++
            $key = $group.ObjectGUID.ToString()
            if (Test-ReportItemDone $key) { continue }
            Write-UiProgress $position $groups.Count $group.Name
            try {
                $rows = Get-GroupRows -Group $group -Context $context -Recursive ([bool]$Recursive)
                if ($rows.Count -eq 0) { $emptyGroups++ }
                Add-ReportItem $key $rows
            }
            catch {
                if (Test-TransientError $_) { Write-ReportIssue $group.Name $_.Exception.Message -Kind Retryable }
                else { Write-ReportIssue $group.Name $_.Exception.Message -Kind Fail; Add-ReportItem $key $null }
            }
        }
        Stop-UiProgress
        Complete-ReportJob
        Write-ReportSummary ([ordered]@{
                'Gruppen'            = Format-UiNumber $groups.Count
                'davon ohne Mitglied' = Format-UiNumber $emptyGroups
            })
    }
    else {
        Write-UiStatus Step 'Lese Gruppen der Domaene ...'
        $index = New-GroupIndex $context
        Write-UiStatus Ok ('{0} Gruppen geladen' -f (Format-UiNumber $index.ByDn.Count))
        Write-UiStatus Step 'Lese Benutzer ...'
        $users = @(Invoke-WithRetry {
                Get-ADUser -Filter * -SearchBase $OUPath -Server $context.Server -Properties DisplayName, memberOf, primaryGroupID -ResultPageSize 1000 -ErrorAction Stop
            } | Sort-Object SamAccountName)
        Write-UiStatus Ok ('{0} Benutzer gefunden' -f (Format-UiNumber $users.Count))

        Start-UiProgress 'Benutzer werden analysiert' $job.Done.Count
        $position = 0
        foreach ($user in $users) {
            $position++
            $key = $user.ObjectGUID.ToString()
            if (Test-ReportItemDone $key) { continue }
            Write-UiProgress $position $users.Count $user.SamAccountName
            try {
                Add-ReportItem $key (Get-UserRows -User $user -Index $index -Context $context -Recursive ([bool]$Recursive))
            }
            catch {
                Write-ReportIssue $user.SamAccountName $_.Exception.Message -Kind Fail
                Add-ReportItem $key $null
            }
        }
        Stop-UiProgress
        Complete-ReportJob
        Write-ReportSummary ([ordered]@{ 'Benutzer' = Format-UiNumber $users.Count })
    }
}
catch {
    Write-Host ''
    Write-UiStatus Fail $_.Exception.Message
}
finally {
    Stop-ReportJob
}
