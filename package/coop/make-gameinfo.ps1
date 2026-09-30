# Writes <ModDir>\gameinfo.txt for the ez2coop sourcemod.
# It reads the user's own Entropy : Zero 2 gameinfo.txt and rewrites every search path to an absolute path,
# so the mod mounts whatever content the installed EZ2 version has (tracks future EZ2 updates).
param(
    [Parameter(Mandatory=$true)][string]$Ez2Root,   # ...\steamapps\common\EntropyZero2
    [Parameter(Mandatory=$true)][string]$ModDir     # folder that will hold gameinfo.txt
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $Ez2Root).Path.TrimEnd('\').Replace('\', '/')
$src  = Join-Path $Ez2Root 'entropyzero2\gameinfo.txt'
if (-not (Test-Path $src)) { throw "Not an Entropy : Zero 2 install (missing $src)" }
$text = Get-Content $src -Raw

$verMatch = [regex]::Match($text, '"ez2_version"\s+"([^"]*)"')
$ez2ver = if ($verMatch.Success) { $verMatch.Groups[1].Value } else { 'unknown' }

# Pull the SearchPaths block out of the original.
$m = [regex]::Match($text, '"?SearchPaths"?\s*\{(.*?)\}', 'Singleline')
if (-not $m.Success) { throw "Could not parse SearchPaths in $src" }
$lines = New-Object System.Collections.Generic.List[string]
# Our own folder comes first so our client.dll/server.dll and content win.
$lines.Add("`t`t`t`"game+mod+mod_write+default_write_path`"`t`"|gameinfo_path|.`"")
$lines.Add("`t`t`t`"gamebin`"`t`"|gameinfo_path|bin`"")
foreach ($pm in [regex]::Matches($m.Groups[1].Value, '"([^"]+)"\s+"([^"]+)"')) {
    $key = $pm.Groups[1].Value; $val = $pm.Groups[2].Value
    if ($val -eq '|gameinfo_path|bin') { continue }  # EZ2's own client/server DLLs: replaced by ours
    if ($val -eq '|gameinfo_path|.') { $lines.Add("`t`t`t`"game+mod`"`t`"$root/entropyzero2`""); continue }  # EZ2 content, same priority as before
    if ($key -match 'mod_write|default_write_path') { $key = ($key -replace '\+?mod_write', '' -replace '\+?default_write_path', '') }
    if ($val.StartsWith('|gameinfo_path|'))            { $val = "$root/entropyzero2/" + $val.Substring(15) }
    elseif ($val.StartsWith('|all_source_engine_paths|')) { $val = "$root/" + $val.Substring(25) }
    elseif ($val -notmatch '^[A-Za-z]:') { $val = "$root/$val" }
    # Normalise ".." segments (e.g. the workshop mount) so the engine gets a clean absolute path.
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($p in $val.Split('/')) { if ($p -eq '..') { $parts.RemoveAt($parts.Count - 1) } elseif ($p -ne '') { $parts.Add($p) } }
    $val = [string]::Join('/', $parts)
    $lines.Add("`t`t`t`"$key`"`t`"$val`"")
}

$out = @"
"GameInfo"
{
	"game"	"Entropy : Zero 2 Co-op"
	"title"	"ENTROPY : ZERO 2 CO-OP"
	"gamepadui_title"	"E N T R O P Y : Z E R O  2"
	"gamepadui_title2"	"C O - O P"
	"ez2_version"	"$ez2ver"
	"supportsvr"	"0"
	"GameData"	"bin/EntropyZero2.fgd"
	"type"	"singleplayer_only"
	"icon"	"resource/ez2coop_icon"
	"FileSystem"
	{
		"SteamAppId"	"1583720"
		"SearchPaths"
		{
$([string]::Join("`r`n", $lines))
		}
	}
}
"@
New-Item -ItemType Directory -Force $ModDir | Out-Null
[IO.File]::WriteAllText((Join-Path $ModDir 'gameinfo.txt'), $out, (New-Object Text.UTF8Encoding($false)))
Write-Output "gameinfo.txt written for EZ2 $ez2ver -> $ModDir"
