<#
.SYNOPSIS
    Bericht ueber NTFS-Berechtigungen von Ordnern bis zu einer festgelegten Tiefe.

.DESCRIPTION
    Liest die Zugriffsrechte (ACL) des Startordners und aller Unterordner bis zur
    angegebenen Tiefe und schreibt sie in eine CSV-Datei. Generische Rechte werden in
    lesbare Rechte uebersetzt, verwaiste SIDs werden als SID ausgegeben, Junctions und
    symbolische Links werden nicht verfolgt. Pfade ueber 260 Zeichen werden unterstuetzt.

    Ordner ohne Leserechte werden uebersprungen und im Fehler-Log festgehalten.
    Ohne Parameter gestartet, fragt ein kurzer Assistent alle Optionen ab.
    Ein unterbrochener Lauf wird beim naechsten Aufruf mit denselben Parametern
    automatisch fortgesetzt.

.PARAMETER Path
    Startordner, lokal oder UNC, z. B. "D:\Daten" oder "\\fs01\Daten".

.PARAMETER MaxDepth
    Maximale Tiefe inklusive Startordner. 1 = nur der Startordner,
    3 (Standard) = Startordner plus zwei Ebenen darunter, 0 = unbegrenzt.

.PARAMETER Domain
    Nur Konten dieser Domaene ausgeben (NetBIOS-Name, z. B. "FIRMA").

.PARAMETER ExcludeInherited
    Nur explizit gesetzte (nicht vererbte) Berechtigungen ausgeben.

.PARAMETER OutputDir
    Zielordner fuer CSV und Logs. Standard: C:\Temp\ADReports

.PARAMETER OutputFile
    Fester Pfad der CSV-Datei (ueberschreibt OutputDir).

.PARAMETER Delimiter
    CSV-Trennzeichen. Standard: ";" (passt zu Excel mit deutschen Einstellungen).

.PARAMETER Fresh
    Einen unterbrochenen Lauf verwerfen und neu beginnen.

.EXAMPLE
    .\list_permissions.ps1

    Startet den Assistenten.

.EXAMPLE
    .\list_permissions.ps1 -Path "D:\Daten" -MaxDepth 3 -Domain "FIRMA"

.EXAMPLE
    .\list_permissions.ps1 -Path "\\fs01\Daten" -MaxDepth 0 -ExcludeInherited

.NOTES
    Autor:     Luca Baumann
    Version:   2.0
    Geaendert: 06.10.2026
#>
[CmdletBinding()]
param(
    [Alias('StartPath')]
    [string]$Path,

    [ValidateRange(0, 1000)]
    [int]$MaxDepth = 3,

    [string]$Domain,

    [switch]$ExcludeInherited,

    [string]$OutputDir = 'C:\Temp\ADReports',

    [string]$OutputFile,

    [char]$Delimiter = ';',

    [switch]$Fresh
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '2.0'
$ScriptFile = 'list_permissions.ps1'

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
#  File system helpers
# ----------------------------------------------------------------------------

# Paths near the 260 character limit get the \\?\ prefix, which Windows
# PowerShell 5.1 (.NET 4.6.2+) needs for long paths. Reported paths never carry it.
function ConvertTo-IoPath {
    param([string]$Path)
    if ($Path.Length -lt 240 -or $Path.StartsWith('\\?\')) { return $Path }
    if ($Path.StartsWith('\\')) { return '\\?\UNC\' + $Path.Substring(2) }
    '\\?\' + $Path
}

function ConvertFrom-IoPath {
    param([string]$Path)
    if ($Path.StartsWith('\\?\UNC\')) { return '\\' + $Path.Substring(8) }
    if ($Path.StartsWith('\\?\')) { return $Path.Substring(4) }
    $Path
}

# Reading the ACL through .NET is much faster than Get-Acl. Windows PowerShell 5.1
# has DirectoryInfo.GetAccessControl(), PowerShell 7 the FileSystemAclExtensions
# class; Get-Acl is the fallback if neither is available.
$AclSections = [System.Security.AccessControl.AccessControlSections]'Access, Owner'
try { Add-Type -AssemblyName System.IO.FileSystem.AccessControl -ErrorAction Stop } catch { }
$AclMode = 'Cmdlet'
if ('System.IO.FileSystemAclExtensions' -as [type]) { $AclMode = 'Extension' }
elseif ([System.IO.DirectoryInfo].GetMethod('GetAccessControl', [type[]]@([System.Security.AccessControl.AccessControlSections]))) { $AclMode = 'Instance' }

function Get-FolderAcl {
    param([string]$IoPath)
    switch ($AclMode) {
        'Extension' { return [System.IO.FileSystemAclExtensions]::GetAccessControl((New-Object System.IO.DirectoryInfo($IoPath)), $AclSections) }
        'Instance'  { return (New-Object System.IO.DirectoryInfo($IoPath)).GetAccessControl($AclSections) }
        default     { return Get-Acl -LiteralPath $IoPath -ErrorAction Stop }
    }
}

# Generic rights (GENERIC_ALL etc.) show up as large numbers. Map them to the
# file system rights they stand for, e.g. 268435456 -> FullControl.
function Format-Rights {
    param($Rights)
    [int64]$value = [int]$Rights
    if ($value -lt 0) { $value += 4294967296 }
    if (($value -band 0xF0000000) -eq 0) { return $Rights.ToString() }
    [int64]$mapped = $value -band 0x0FFFFFFF
    if ($value -band 0x10000000) { $mapped = $mapped -bor 2032127 }  # GENERIC_ALL     -> FullControl
    if ($value -band 0x80000000) { $mapped = $mapped -bor 131209 }   # GENERIC_READ    -> Read
    if ($value -band 0x40000000) { $mapped = $mapped -bor 278 }      # GENERIC_WRITE   -> Write
    if ($value -band 0x20000000) { $mapped = $mapped -bor 32 }       # GENERIC_EXECUTE -> ExecuteFile
    # Enum::ToObject also accepts bits without a name; a plain cast would throw.
    [Enum]::ToObject([System.Security.AccessControl.FileSystemRights], [int]$mapped).ToString()
}

function Format-AppliesTo {
    param($Rule)
    $inherit = [int]$Rule.InheritanceFlags          # 1 = ContainerInherit, 2 = ObjectInherit
    $propagate = [int]$Rule.PropagationFlags        # 1 = NoPropagateInherit, 2 = InheritOnly
    $inheritOnly = ($propagate -band 2) -eq 2
    $text = switch ($inherit) {
        0 { 'Nur dieser Ordner' }
        1 { if ($inheritOnly) { 'Nur Unterordner' } else { 'Dieser Ordner und Unterordner' } }
        2 { if ($inheritOnly) { 'Nur Dateien' } else { 'Dieser Ordner und Dateien' } }
        3 { if ($inheritOnly) { 'Nur Unterordner und Dateien' } else { 'Dieser Ordner, Unterordner und Dateien' } }
    }
    if (($propagate -band 1) -eq 1) { $text += ' (nur eine Ebene)' }
    $text
}

# Plain I/O errors (network share gone, server busy) are worth a retry on the
# next run. Everything else - access denied, path vanished, path too long - is not.
function Test-RetryableIoError {
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($exception.InnerException -and $exception -is [System.Management.Automation.MethodInvocationException]) {
        $exception = $exception.InnerException
    }
    ($exception -is [System.IO.IOException]) -and
    -not ($exception -is [System.IO.DirectoryNotFoundException]) -and
    -not ($exception -is [System.IO.FileNotFoundException]) -and
    -not ($exception -is [System.IO.PathTooLongException])
}

function Get-InnerMessage {
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($exception.InnerException) { $exception = $exception.InnerException }
    $exception.Message
}

function Get-FolderRows {
    param([string]$DisplayPath, [string]$IoPath, [int]$Depth)
    $acl = Get-FolderAcl $IoPath
    $owner = ''
    try { $owner = Resolve-SidName ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value) } catch { }

    $rows = New-Object 'System.Collections.Generic.List[object]'
    $rules = $acl.GetAccessRules($true, -not $ExcludeInherited, [System.Security.Principal.SecurityIdentifier])
    foreach ($rule in $rules) {
        $account = Resolve-SidName $rule.IdentityReference.Value
        if ($Domain -and -not $account.StartsWith("$Domain\", [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $rows.Add([pscustomobject][ordered]@{
                Path              = $DisplayPath
                Depth             = $Depth
                Account           = $account
                AccessControlType = $rule.AccessControlType.ToString()
                FileSystemRights  = Format-Rights $rule.FileSystemRights
                AppliesTo         = Format-AppliesTo $rule
                IsInherited       = $rule.IsInherited
                Owner             = $owner
            })
    }
    , $rows
}

# ----------------------------------------------------------------------------
#  Main
# ----------------------------------------------------------------------------

Write-UiHeader 'NTFS-Berechtigungsbericht' $ScriptVersion 'Ordnerberechtigungen bis zur gewaehlten Tiefe'

try {
    $wizard = ($PSBoundParameters.Count -eq 0) -and (Test-UiInteractive)
    if ($wizard) {
        Write-UiSection 'Assistent'
        $Path = Read-UiValue 'Startordner (z. B. D:\Daten oder \\server\freigabe)' ''
        $MaxDepth = [int](Read-UiValue 'Maximale Tiefe inkl. Startordner (0 = unbegrenzt)' '3')
        $Domain = Read-UiValue ('Nur Konten dieser Domaene, z. B. {0} (leer = alle)' -f $env:USERDOMAIN) ''
        $ExcludeInherited = [System.Management.Automation.SwitchParameter](-not (Read-UiYesNo 'Vererbte Berechtigungen ausgeben?' $true))
        $OutputDir = Read-UiValue 'Zielordner' $OutputDir
    }
    if (-not $Path) { throw 'Kein Startordner angegeben. Beispiel: -Path "D:\Daten"' }

    $rootPath = Resolve-UiPath $Path
    if ($rootPath.Length -gt 3) { $rootPath = $rootPath.TrimEnd('\') }
    if (-not [System.IO.Directory]::Exists((ConvertTo-IoPath $rootPath))) { throw "Startordner nicht gefunden oder kein Zugriff: $rootPath" }

    $settings = [ordered]@{ Path = $rootPath; MaxDepth = $MaxDepth; Domain = $Domain; ExcludeInherited = [bool]$ExcludeInherited }
    $jobId = Get-ReportJobId $ScriptFile $settings
    if ($OutputFile) { $csvPath = Resolve-UiPath $OutputFile; $resumePath = $csvPath }
    else {
        $directory = Resolve-UiPath $OutputDir
        $resumePath = if ($Fresh) { Remove-ReportJobs $directory $jobId; $null } else { Find-ReportJob $directory $jobId }
        $csvPath = if ($resumePath) { $resumePath } else { Join-Path $directory ('NTFSBerechtigungen_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss')) }
    }

    Write-UiSection 'Einstellungen'
    Write-UiField 'Startordner' $rootPath
    Write-UiField 'Maximale Tiefe' $(if ($MaxDepth -eq 0) { 'unbegrenzt' } else { "$MaxDepth Ebenen (inkl. Startordner)" })
    Write-UiField 'Domaenenfilter' $(if ($Domain) { "$Domain\*" } else { 'alle Konten' })
    Write-UiField 'Vererbte Rechte' $(if ($ExcludeInherited) { 'ausgeblendet' } else { 'enthalten' })
    Write-UiField 'Ausgabe' $csvPath

    if ($wizard) {
        Write-UiCommandHint $ScriptFile ([ordered]@{ Path = $rootPath; MaxDepth = $MaxDepth; Domain = $Domain; ExcludeInherited = [bool]$ExcludeInherited; OutputDir = $OutputDir })
        Write-Host ''
        if (-not (Read-UiYesNo 'Jetzt starten?' $true)) { Write-UiStatus Info 'Abgebrochen.'; return }
    }

    $job = Open-ReportJob -CsvPath $csvPath -JobId $jobId -Delimiter $Delimiter -Resume:([bool]$resumePath -and -not $Fresh)

    Write-UiSection 'Analyse'
    if ($job.Resumed) {
        Write-UiStatus Info ('Unterbrochener Lauf vom {0} wird fortgesetzt ({1} Ordner bereits erledigt).' -f $job.Started.Replace('T', ' '), (Format-UiNumber $job.ResumedItems))
    }

    # Breadth-first walk with the depth limit built in: folders below MaxDepth are
    # never enumerated. On resume, finished folders are only walked, not re-read.
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue(@($rootPath, 1))
    $folders = 0
    $skippedLinks = 0
    Start-UiProgress 'Ordner werden analysiert'
    while ($queue.Count -gt 0) {
        $entry = $queue.Dequeue()
        $displayPath = [string]$entry[0]
        $depth = [int]$entry[1]
        $ioPath = ConvertTo-IoPath $displayPath
        $folders++
        Write-UiProgress $folders 0 $displayPath

        $aclReadable = $true
        if (-not (Test-ReportItemDone $displayPath)) {
            try {
                Add-ReportItem $displayPath (Get-FolderRows -DisplayPath $displayPath -IoPath $ioPath -Depth $depth)
            }
            catch {
                $aclReadable = $false
                if (Test-RetryableIoError $_) {
                    Write-ReportIssue $displayPath (Get-InnerMessage $_) -Kind Retryable
                }
                else {
                    Write-ReportIssue $displayPath (Get-InnerMessage $_) -Kind Fail
                    Add-ReportItem $displayPath $null
                }
            }
        }

        if ($MaxDepth -ne 0 -and $depth -ge $MaxDepth) { continue }
        try {
            $children = (New-Object System.IO.DirectoryInfo($ioPath)).GetDirectories()
        }
        catch {
            # Only report it when the ACL itself was readable; otherwise it is already logged.
            if ($aclReadable) { Write-ReportIssue $displayPath ('Unterordner nicht lesbar: ' + (Get-InnerMessage $_)) -Kind Warn }
            continue
        }
        foreach ($child in $children) {
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $skippedLinks++; continue }
            $queue.Enqueue(@((ConvertFrom-IoPath $child.FullName), ($depth + 1)))
        }
    }
    Stop-UiProgress
    Complete-ReportJob
    Write-ReportSummary ([ordered]@{
            'Ordner'              = Format-UiNumber $folders
            'Links uebersprungen' = Format-UiNumber $skippedLinks
        })
}
catch {
    Write-Host ''
    Write-UiStatus Fail $_.Exception.Message
}
finally {
    Stop-ReportJob
}
