# save_dcs_log.ps1 | v1.0.0
# Archives Saved Games\DCS\Logs\dcs.log before DCS overwrites it at the next start.
#
# The archive file is named after the session START time (first line of dcs.log),
# so running the script again during or after the same session updates the same
# file instead of creating duplicates. A second file *_trt.log holds only the
# mission-script lines ([TL], [AAR], [CD], [JC], [MD], [Core_Scoring], ...).
#
# Usage (PowerShell 5.1 or 7):
#   powershell -ExecutionPolicy Bypass -File tools\save_dcs_log.ps1            # archive once
#   powershell -ExecutionPolicy Bypass -File tools\save_dcs_log.ps1 -Watch     # archive every time DCS exits
# Options:
#   -SavedGames <path>   DCS Saved Games folder (default: %USERPROFILE%\Saved Games\DCS)
#   -Dest <path>         archive folder (default: <SavedGames>\Logs\Archive)
#   -PollSeconds <n>     watch interval (default 15)

[CmdletBinding()]
param(
    [string]$SavedGames = (Join-Path $env:USERPROFILE 'Saved Games\DCS'),
    [string]$Dest = '',
    [switch]$Watch,
    [int]$PollSeconds = 15
)

$ErrorActionPreference = 'Stop'
$Version = '1.0.0'
$LogDir  = Join-Path $SavedGames 'Logs'
$LogFile = Join-Path $LogDir 'dcs.log'
if (-not $Dest) { $Dest = Join-Path $LogDir 'Archive' }
$TrtPattern = '\[(TL|AAR|CD|JC|JL|MD|PB|CVC|FIREGATE|IADS|Core_Scoring|Score_Display|Radio_Log|PlaneCaptain|AIRBOSS_TRT)\]|SCRIPTING.*(ERROR|error)'

function Write-Info([string]$msg) {
    Write-Host ("[save_dcs_log {0}] {1:HH:mm:ss} {2}" -f $Version, (Get-Date), $msg)
}

function Get-SessionStamp([string]$path) {
    # First line of dcs.log: "2026-10-29 19:26:43.123 INFO ..."
    $first = Get-Content -LiteralPath $path -TotalCount 1 -ErrorAction SilentlyContinue
    if ($first -match '^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})') {
        return '{0}{1}{2}-{3}{4}{5}' -f $Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5], $Matches[6]
    }
    return (Get-Item -LiteralPath $path).LastWriteTime.ToString('yyyyMMdd-HHmmss')
}

function Save-DcsLog {
    if (-not (Test-Path -LiteralPath $LogFile)) { Write-Info "no dcs.log in $LogDir"; return }
    if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }

    $stamp  = Get-SessionStamp $LogFile
    $target = Join-Path $Dest ("dcs_{0}.log" -f $stamp)
    $trt    = Join-Path $Dest ("dcs_{0}_trt.log" -f $stamp)

    $srcLen = (Get-Item -LiteralPath $LogFile).Length
    if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).Length -eq $srcLen)) {
        Write-Info "up to date: $target"
        return
    }

    # DCS keeps dcs.log open while running: copy through a shared read stream.
    $in  = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
    try {
        $out = [System.IO.File]::Create($target)
        try { $in.CopyTo($out) } finally { $out.Close() }
    } finally { $in.Close() }

    $lines = Select-String -LiteralPath $target -Pattern $TrtPattern | ForEach-Object { $_.Line }
    Set-Content -LiteralPath $trt -Value $lines -Encoding UTF8
    Write-Info ("saved {0} ({1:N0} KB), {2} script lines -> {3}" -f $target, ($srcLen / 1KB), @($lines).Count, (Split-Path $trt -Leaf))
}

function Test-DcsRunning {
    return [bool](Get-Process -Name 'DCS' -ErrorAction SilentlyContinue)
}

Save-DcsLog
if (-not $Watch) { return }

Write-Info "watching for DCS exit (poll $PollSeconds s, Ctrl+C to stop)"
$wasRunning = Test-DcsRunning
while ($true) {
    Start-Sleep -Seconds $PollSeconds
    $running = Test-DcsRunning
    if ($wasRunning -and -not $running) {
        Start-Sleep -Seconds 5   # let DCS finish writing "=== Log closed."
        Save-DcsLog
    }
    $wasRunning = $running
}
