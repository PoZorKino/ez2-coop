# Entropy : Zero 2 Co-op installer.
#   irm https://tool.dexx.moe/install-ez2-coop.ps1 | iex
# Installs the ez2coop sourcemod next to your own Entropy : Zero 2 install (no game files are downloaded),
# plus "EZ2 Co-op - Host" / "EZ2 Co-op - Join" desktop shortcuts.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ZipUrl = 'https://tool.dexx.moe/ez2-coop.zip'

function Find-Ez2 {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    $libs = New-Object System.Collections.Generic.List[string]
    if ($steam) {
        $libs.Add($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs.Add($m.Groups[1].Value.Replace('\\', '\')) }
        }
    }
    foreach ($l in $libs) {
        $p = Join-Path $l 'steamapps\common\EntropyZero2'
        if (Test-Path (Join-Path $p 'entropyzero2\gameinfo.txt')) { return (Resolve-Path $p).Path }
    }
    return $null
}

Write-Host "`n== Entropy : Zero 2 Co-op installer ==`n" -ForegroundColor Cyan
$ez2 = Find-Ez2
if (-not $ez2) {
    $ez2 = Read-Host 'Could not find Entropy : Zero 2. Paste its folder (...\steamapps\common\EntropyZero2)'
    if (-not (Test-Path (Join-Path $ez2 'entropyzero2\gameinfo.txt'))) { throw "Not an Entropy : Zero 2 folder: $ez2" }
}
Write-Host "Entropy : Zero 2: $ez2"

$sm = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SourceModInstallPath
if (-not $sm) { $sm = Join-Path (Split-Path (Split-Path $ez2)) 'sourcemods' }
$mod = Join-Path $sm 'ez2coop'
Write-Host "Installing to:     $mod"

$tmp = Join-Path $env:TEMP ('ez2coop-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    Write-Host 'Downloading...'
    Invoke-WebRequest $ZipUrl -OutFile "$tmp\ez2-coop.zip" -UseBasicParsing
    Expand-Archive "$tmp\ez2-coop.zip" "$tmp\x" -Force

    # A previous install (e.g. the old Workshop symlink) is replaced; your cfg and saves are kept.
    if (Test-Path $mod) {
        $item = Get-Item $mod -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { cmd /c rmdir "$mod" | Out-Null }
        else { foreach ($d in 'bin', 'coop', 'maps', 'resource', 'scripts') { Remove-Item (Join-Path $mod $d) -Recurse -Force -ErrorAction SilentlyContinue } }
    }
    New-Item -ItemType Directory -Force $mod | Out-Null
    Copy-Item "$tmp\x\*" $mod -Recurse -Force

    # These two come from your own game install, not from the download.
    foreach ($dll in 'gamepadui.dll', 'discord-rpc.dll') { Copy-Item (Join-Path $ez2 "entropyzero2\bin\$dll") (Join-Path $mod "bin\$dll") -Force }
    Set-Content (Join-Path $mod 'coop\ez2root.txt') $ez2 -Encoding ASCII
    & (Join-Path $mod 'coop\make-gameinfo.ps1') -Ez2Root $ez2 -ModDir $mod

    $desk = [Environment]::GetFolderPath('Desktop')
    $ws = New-Object -ComObject WScript.Shell
    foreach ($s in @(@('EZ2 Co-op - Host', 'host.ps1'), @('EZ2 Co-op - Join', 'join.ps1'))) {
        $lnk = $ws.CreateShortcut((Join-Path $desk ($s[0] + '.lnk')))
        $lnk.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$mod\coop\$($s[1])`""
        $lnk.WorkingDirectory = "$mod\coop"
        $lnk.IconLocation = "$ez2\hl2.exe,0"
        $lnk.Save()
    }
    $ver = (Get-Content (Join-Path $mod 'coop\VERSION.txt') -Raw).Trim()
    Write-Host "`nInstalled EZ2 Co-op $ver." -ForegroundColor Green
    Write-Host 'Desktop shortcuts: "EZ2 Co-op - Host" (pick a chapter, starts the bridge) and "EZ2 Co-op - Join".'
    Write-Host 'Steam must be running. Restart Steam if you also want it listed in your library.'
}
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
