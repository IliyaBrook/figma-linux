#!/usr/bin/env bash
# Exercise official downloads, explicit runtime selection and extract-and-run.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$script_dir/appimage-toolchain.sh"
smoke_dir=$(mktemp -d)
trap 'rm -rf -- "$smoke_dir"' EXIT
case "$(uname -m)" in
  x86_64) architecture=amd64 ;;
  aarch64) architecture=arm64 ;;
  *) echo 'Unsupported smoke-test host' >&2; exit 1 ;;
esac
prepare_appimage_tools "$architecture" "$smoke_dir"
mkdir -p "$smoke_dir/Smoke.AppDir"
cat > "$smoke_dir/Smoke.AppDir/AppRun" <<'APP'
#!/bin/sh
echo 'AppImage runtime smoke passed'
APP
chmod +x "$smoke_dir/Smoke.AppDir/AppRun"
cat > "$smoke_dir/Smoke.AppDir/smoke.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Runtime smoke
Exec=AppRun
Icon=smoke
Type=Application
Categories=Utility;
DESKTOP
cp "$script_dir/../assets/figma-icon.svg" "$smoke_dir/Smoke.AppDir/smoke.svg"
ARCH="$tool_arch" APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool_path" \
  --runtime-file "$runtime_path" "$smoke_dir/Smoke.AppDir" "$smoke_dir/smoke.AppImage"
APPIMAGE_EXTRACT_AND_RUN=1 "$smoke_dir/smoke.AppImage" | grep -Fx 'AppImage runtime smoke passed'
