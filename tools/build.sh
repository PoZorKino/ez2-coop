#!/bin/sh
# Build EZ2 co-op DLLs (Release|Win32) with VS 2026 (v145). Usage: tools/build.sh [projects...]
MSB="/c/Program Files/Microsoft Visual Studio/18/Community/MSBuild/Current/Bin/amd64/MSBuild.exe"
cd "$(dirname "$0")/../sp/src" || exit 1
PROJS="${*:-tier1/tier1.vcxproj mathlib/mathlib.vcxproj raytrace/raytrace.vcxproj responserules/runtime/responserules.vcxproj vgui2/vgui_controls/vgui_controls.vcxproj vscript/vscript.vcxproj game/server/server_ez2.vcxproj game/client/client_ez2.vcxproj}"
for p in $PROJS; do
  echo "=== $p"
  "$MSB" "$p" -nologo -m -v:minimal -p:Configuration=Release -p:Platform=Win32 -p:PlatformToolset=v145 \
    -p:WindowsTargetPlatformVersion=10.0.26100.0 -clp:ErrorsOnly -fl -flp:logfile="$(basename "$p" .vcxproj).build.log;verbosity=minimal" || { echo "FAILED: $p"; exit 1; }
done
echo BUILD OK
