# Join an Entropy : Zero 2 co-op game through the bridge (or any address).
$ErrorActionPreference = 'Stop'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$modDir = Split-Path -Parent $here
$ez2    = (Get-Content (Join-Path $here 'ez2root.txt') -Raw).Trim()
$exe    = Join-Path $ez2 'hl2.exe'
if (-not (Test-Path $exe)) { Write-Host "Entropy : Zero 2 not found at $ez2 - rerun the installer."; Read-Host 'Enter to exit'; exit 1 }

# Only one copy of the game should run at a time.
$running = @(Get-Process hl2 -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Write-Host "Entropy : Zero 2 is already running (hl2.exe, PID $($running.Id -join ', ')). Close it first." -ForegroundColor Yellow
    $a = Read-Host 'Close it now? [y/N]'
    if ($a -match '^[yY]') { $running | Stop-Process -Force; Start-Sleep 2 } else { exit 1 }
}

Write-Host ''
Write-Host '  ENTROPY : ZERO 2 CO-OP - join a game' -ForegroundColor Cyan
Write-Host '  The host''s bridge window shows the address, e.g. coop.dexx.moe:27601'
$addr = Read-Host "`nAddress [coop.dexx.moe:27601]"
if ([string]::IsNullOrWhiteSpace($addr)) { $addr = 'coop.dexx.moe:27601' }
$addr = ($addr -replace '^\s*connect\s+', '').Trim()
if ($addr -match '^\d+$') { $addr = "coop.dexx.moe:$addr" }   # just the port number

Start-Process $exe -WorkingDirectory $ez2 -ArgumentList @(
    '-game', "`"$modDir`"", '-steam', '-novid', '-console', '-nogamepadui', '+connect', $addr)
Write-Host "Connecting to $addr ..."
Start-Sleep 3
