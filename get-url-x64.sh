#!/bin/bash
RELEASES=$(curl -s -L -H 'User-Agent: Figma/1 (Windows; x64)' \
  "https://desktop.figma.com/win/RELEASES")

NUPKG=$(echo "$RELEASES" | awk '{print $2}')
VERSION=$(echo "$NUPKG" | sed 's/Figma-\(.*\)-full\.nupkg/\1/')

echo "Version: $VERSION"
echo "nupkg:   https://desktop.figma.com/win/build/$NUPKG"
echo "exe:     https://desktop.figma.com/win/FigmaSetup.exe"
