#!/bin/bash
# Fetch version from RELEASES manifest
RELEASES=$(curl -s -L -H 'User-Agent: Figma/1 (Windows; x64)' \
  "https://desktop.figma.com/win/RELEASES")

NUPKG=$(echo "$RELEASES" | awk '{print $2}')
RELEASES_VERSION=$(echo "$NUPKG" | sed 's/Figma-\(.*\)-full\.nupkg/\1/')

# Fetch actual version from inside FigmaSetup.exe (first 2MB contains nupkg filename)
EXE_NUPKG=$(curl -s -L -H 'User-Agent: Figma/1 (Windows; x64)' \
  -r 0-2097151 "https://desktop.figma.com/win/FigmaSetup.exe" \
  | strings | grep -oP 'Figma-[\d.]+-full\.nupkg' | head -1)
EXE_VERSION=$(echo "$EXE_NUPKG" | sed 's/Figma-\(.*\)-full\.nupkg/\1/')

echo "RELEASES version: $RELEASES_VERSION"
echo "EXE version:      ${EXE_VERSION:-unknown}"
if [[ -n "$EXE_VERSION" && "$RELEASES_VERSION" != "$EXE_VERSION" ]]; then
  echo "  ⚠ Versions differ! EXE is newer."
fi
echo ""
echo "nupkg:   https://desktop.figma.com/win/build/$NUPKG"
echo "exe:     https://desktop.figma.com/win/FigmaSetup.exe"
