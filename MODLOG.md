# EZ2 Co-op — MODLOG

Goal: online co-op for Entropy : Zero 2 (Steam 1583720) on the **current** game build (1.10.10, Mapbase v8.0).
Done = 2 players load a campaign map together, see each other, fight, and a level transition works.

## Facts
- Game: `D:\!stem\steamapps\common\EntropyZero2` — Source 2013 SP engine, **x86** `hl2.exe`, no anti-cheat.
  Mod content in `entropyzero2/`, game DLLs in `entropyzero2/bin` (client/server/gamepadui/discord-rpc).
  appmanifest buildid 23281311, `ez2_version "1.10.10"` in gameinfo.
- Sourcemods: `C:\Program Files (x86)\Steam\steamapps\sourcemods` (HKCU\SOFTWARE\Valve\Steam SourceModInstallPath).
- Existing co-op work (don't reinvent):
  - Workshop 2856851374 "E:Z2 CO-OP" (met-nikita), already downloaded at
    `D:\!stem\steamapps\workshop\content\1583720\2856851374` — built for EZ2 **1.6.3** (coop-0.1.1).
    `install_sourcemod.bat` symlinks `ez2coop` into sourcemods and writes a gameinfo with absolute paths.
  - Source: github.com/met-nikita/source-sdk-2013 (branch ez2/mapbase, last push 2025-05-11, ~EZ2 1.8).
    47 co-op commits over upstream, 97 files / +4.9k lines.
  - Map edits (Mapbase MapEdit `maps/<map>_auto.txt`: spawn points, coop_manager, game_player_equip):
    github.com/met-nikita/ez2_coop_mapfixes (2024-05).
  - github.com/blackletum/EZ2-COOP — repackage; README says it only works on beta release-1.8 (Jan 2025).
- Upstream EZ2 source: github.com/entropy-zero/source-sdk-2013 branch `ez2/mapbase` (Mapbase v8.0, 2026-05).

## Route
Source-code route (official SDK, legal): merge current upstream EZ2 into the co-op fork, rebuild
server.dll/client.dll, ship as sourcemod `ez2coop` that mounts the user's own EZ2 content. No game files shipped.

## Repo
`~/ez2-coop` = clone of met-nikita fork, remote `upstream` = entropy-zero. Branch `coop/ez2-1.10`.
- Merge of upstream (159 commits) had 4 conflicts; resolved:
  - c_basehlplayer.cpp/.h, hl2_player.cpp DT: union (keep coop m_hRagdoll + upstream m_nProtagonistIndex).
  - hl2_player.cpp squad-command/kick anims: keep coop `SetAnimation(PLAYER_SIGNAL_*/PLAYER_KICK)` (MP anim
    state is client-side in coop) instead of upstream's server-side `AddAnimStateLayer`.
  - basehlcombatweapon_shared.cpp: union (coop UTIL_ClipPunchAngleOffset + upstream protagonist VM funcs).
- Build: `sh tools/build.sh` (VPC can't write the .sln without an HKLM VS2010 regkey, so msbuild each vcxproj,
  toolset overridden to v145 / VS 2026). Output copied to `game/mod_ez2/bin`.
  Regenerate projects: `cd sp/src && devtools/bin/vpc.exe /ez2 +game /mksln entropyzero2.sln` (sln error is harmless).

## Bridge (relay on dexx server)
- `bridge/relay.py` runs as container `ez2-coop-relay` in `/opt/ez2-coop-relay` on dexx (python:3.12-alpine),
  UDP 27600 = host tunnels, 27601-27616 = public game ports (one per hosting player).
- `bridge/ez2coop-bridge.ps1` (host side, PowerShell + C# 5): tunnel to relay, one local UDP socket per remote player.
- **GOTCHA:** Source's engine silently drops datagrams whose source is 127.0.0.1 (treated as internal loopback).
  The bridge must talk to the listen server from a real LAN IP (it picks the private IPv4 used to reach the relay).
  A2S queries to 127.0.0.1:27015 get no reply; to 192.168.x.x:27015 they do.
- Test on one PC: second instance with `-multirun -clientport 27006 +con_logfile client.log +connect coop.dexx.moe:27601`.

## Distribution
- `irm https://tool.dexx.moe/install-ez2-coop.ps1 | iex` -> sourcemods\ez2coop (+ Host/Join desktop shortcuts).
  Files in `/opt/tool/public/` on dexx: `install-ez2-coop.ps1`, `ez2-coop.zip` (built from content/ + bins + package/coop).
- gamepadui.dll / discord-rpc.dll are copied from the user's own EZ2 install; gameinfo generated from their EZ2 gameinfo.
- Rebuild zip: see stage steps (content/* + sp/game/mod_ez2/bin/{client,server}.dll + package/coop -> stage -> zip).

## Known
- Saving is disabled in MP (met-nikita removed the engine hacks in 2025-05; "Can't save multiplayer games").
- Level transitions not yet tested on 1.10. Maps new since 1.6 (ez2_c1_4*, etc.) have no MapEdit spawn fixes.

## Log
- 2026-09-30: recon, clone, merge, build OK first try (VS 2026 v145). Host on ez2_c1_1 OK. Relay + bridge deployed;
  2nd and 3rd instances joined via coop.dexx.moe:27601 and see each other. Installer published + tested.
