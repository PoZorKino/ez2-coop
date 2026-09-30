# Host an Entropy : Zero 2 co-op game: pick a chapter, start the bridge, launch the listen server.
$ErrorActionPreference = 'Stop'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$modDir = Split-Path -Parent $here
$ez2    = (Get-Content (Join-Path $here 'ez2root.txt') -Raw).Trim()
$exe    = Join-Path $ez2 'hl2.exe'
if (-not (Test-Path $exe)) { Write-Host "Entropy : Zero 2 not found at $ez2 - rerun the installer."; Read-Host 'Enter to exit'; exit 1 }

$chapters = [ordered]@{
    '0' = @('Prologue',               'ez2_c0_1')
    '1' = @('Chapter 1 - Intro',      'ez2_intro')
    '2' = @('Chapter 2',              'ez2_c2_1')
    '3' = @('Chapter 3',              'ez2_c3_1')
    '4' = @('Chapter 4',              'ez2_c4_1')
    '5' = @('Chapter 4a',             'ez2_c4_3')
    '6' = @('Chapter 5',              'ez2_c5_1')
    '7' = @('Chapter 6',              'ez2_c6_1')
}
Write-Host ''
Write-Host '  ENTROPY : ZERO 2 CO-OP - host a game' -ForegroundColor Cyan
Write-Host ''
foreach ($k in $chapters.Keys) { Write-Host ("   {0}) {1}  ({2})" -f $k, $chapters[$k][0], $chapters[$k][1]) }
Write-Host '   or type any map name (e.g. ez2_c1_2)'
$pick = Read-Host "`nChapter [0]"
if ([string]::IsNullOrWhiteSpace($pick)) { $pick = '0' }
$map = if ($chapters.Contains($pick)) { $chapters[$pick][1] } else { $pick.Trim() }
$max = Read-Host 'Max players [4]'
if (-not ($max -match '^\d+$')) { $max = '4' }

# Bridge in its own window: it prints the "connect coop.dexx.moe:PORT" line for your friends.
Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$here\ez2coop-bridge.ps1`"")

Start-Process $exe -WorkingDirectory $ez2 -ArgumentList @(
    '-game', "`"$modDir`"", '-steam', '-novid', '-console', '-nogamepadui', '-port', '27015',
    '+maxplayers', $max, '+sv_lan', '1', '+map', $map)
Write-Host "`nStarting $map for up to $max players. Give your friends the connect line from the bridge window."
Start-Sleep 4
