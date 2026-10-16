#!/usr/bin/env bash
# Build Arch Linux pacman package (.pkg.tar.zst) and AUR metadata
# Mirrors build-deb-package.sh / build-rpm-package.sh for Arch
# Usage: build-pacman-package.sh <version> <architecture> <work_dir> <app_staging_dir> <package_name> <maintainer> <description>
# Produces:
#   - $work_dir/PKGBUILD  (+ .SRCINFO) for AUR (figma-desktop-bin, AppImage wrapper)
#   - $work_dir/*.pkg.tar.zst if makepkg is available
#   - ./PKGBUILD + ./.SRCINFO updated in repo root for PR/AUR submission

set -e

version="$1"
architecture="$2"
work_dir="$3"
app_staging_dir="$4"
package_name="$5"   # figma-desktop (native) but AUR package is figma-desktop-bin
maintainer="$6"
description="$7"

echo '--- Starting Pacman Package Build ---'
echo "Version: $version"
echo "Architecture: $architecture"
echo "Work Directory: $work_dir"
echo "App Staging Directory: $app_staging_dir"
echo "Package Name: $package_name"
echo "Maintainer: $maintainer"

# Arch mapping (build.sh uses amd64)
case "$architecture" in
  amd64) pacman_arch='x86_64' ;;
  arm64) pacman_arch='aarch64' ;;
  x86_64) pacman_arch='x86_64'; architecture='amd64' ;;
  aarch64) pacman_arch='aarch64'; architecture='arm64' ;;
  *) echo "Unsupported architecture for pacman: $architecture" >&2; exit 1 ;;
esac

# We build figma-desktop-bin (AppImage wrapper) for AUR — consistent with user's draft
aur_pkgname='figma-desktop-bin'
aur_pkgver="$version"
aur_pkgrel=1

# Resolve repo URL from git remote if possible, else fallback to soroushalinia/figma-linux
repo_url="https://github.com/soroushalinia/figma-linux"
if git remote get-url origin &>/dev/null; then
  remote=$(git remote get-url origin)
  # git@github.com:user/repo.git -> https://github.com/user/repo
  if [[ $remote == git@github.com:* ]]; then
    remote=${remote#git@github.com:}
    remote=${remote%.git}
    repo_url="https://github.com/$remote"
  elif [[ $remote == https://github.com/* ]]; then
    remote=${remote%.git}
    repo_url="$remote"
  fi
fi
echo "Repo URL: $repo_url"

# AppImage file produced by build-appimage.sh — hosted on upstream (IliyaBrook) releases
# AppImage is published without `v` prefix: .../releases/download/<version>/<name>
appimage_name="${package_name}-${version}-${architecture}.AppImage"
appimage_path="$work_dir/$appimage_name"
upstream_url="https://github.com/IliyaBrook/figma-linux/releases/download/${version}/${appimage_name}"
# For your fork, replace with ${repo_url}/releases/download/${version}/${appimage_name} once you publish
appimage_url="$upstream_url"

# Try to compute sha256 of existing AppImage (for PKGBUILD), else placeholder that makepkg will refresh
appimage_sha="SKIP"
if [[ -f $appimage_path ]]; then
  echo "Found AppImage at $appimage_path — computing sha256..."
  appimage_sha=$(sha256sum "$appimage_path" | awk '{print $1}')
  echo "AppImage sha256: $appimage_sha"
else
  echo "Warning: AppImage not found at $appimage_path — PKGBUILD will use SKIP (run makepkg -g after release upload)"
  # Try to find any AppImage in work_dir as fallback
  fallback=$(find "$work_dir" -maxdepth 1 -name "*.AppImage" | head -n 1)
  if [[ -n $fallback ]]; then
    appimage_sha=$(sha256sum "$fallback" | awk '{print $1}')
    appimage_name=$(basename "$fallback")
    appimage_url="https://github.com/IliyaBrook/figma-linux/releases/download/${version}/${appimage_name}"
    echo "Using fallback $fallback sha $appimage_sha"
  fi
fi

# Desktop file content — shared with deb/rpm, kept in repo root for AUR
desktop_file_src="$work_dir/figma-desktop.desktop"
cat > "$desktop_file_src" << 'DESKTOP'
[Desktop Entry]
Name=Figma
Exec=/usr/bin/figma-desktop %u
Icon=figma-desktop
Type=Application
Terminal=false
Categories=Graphics;Development;
MimeType=x-scheme-handler/figma;
StartupWMClass=Figma
Comment=Figma Desktop for Linux
DESKTOP
desktop_sha=$(sha256sum "$desktop_file_src" | awk '{print $1}')

# --- Generate PKGBUILD for AUR (figma-desktop-bin) ---
# Use script dir to resolve launcher is not needed for AppImage wrapper, but keep PKGBUILD self-contained
pkgbuild_path="$work_dir/PKGBUILD"
cat > "$pkgbuild_path" << PKGEOF
# Maintainer: $maintainer
pkgname=$aur_pkgname
pkgver=$aur_pkgver
pkgrel=$aur_pkgrel
pkgdesc="$description (patched Windows build, incl. FigJam and local font support)"
arch=('$pacman_arch')
url="$repo_url"
license=('custom:Figma-EULA')
depends=('fuse2' 'zlib' 'hicolor-icon-theme' 'gtk3' 'nss' 'libxcrypt-compat')
options=('!strip')
provides=('figma-desktop')
conflicts=('figma-desktop')
source=("$appimage_name::${appimage_url}"
        "figma-desktop.desktop")
sha256sums=('$appimage_sha'
            '$desktop_sha')

prepare() {
  chmod +x "\${srcdir}/$appimage_name"
}

package() {
  # Install AppImage
  install -dm755 "\${pkgdir}/opt/figma-desktop"
  install -Dm755 "\${srcdir}/$appimage_name" "\${pkgdir}/opt/figma-desktop/figma-desktop.AppImage"

  # Extract and install icon from the AppImage itself
  cd "\${srcdir}"
  "\${srcdir}/$appimage_name" --appimage-extract >/dev/null 2>&1 || true
  if [ -f "squashfs-root/figma-desktop.png" ]; then
    install -Dm644 "squashfs-root/figma-desktop.png" "\${pkgdir}/usr/share/icons/hicolor/512x512/apps/figma-desktop.png"
  elif [ -f "squashfs-root/.DirIcon" ]; then
    install -Dm644 "squashfs-root/.DirIcon" "\${pkgdir}/usr/share/icons/hicolor/512x512/apps/figma-desktop.png"
  elif [ -f "squashfs-root/io.github.nickvdp.figma-desktop-linux.png" ]; then
    install -Dm644 "squashfs-root/io.github.nickvdp.figma-desktop-linux.png" "\${pkgdir}/usr/share/icons/hicolor/512x512/apps/figma-desktop.png"
  fi
  rm -rf "squashfs-root"

  # Desktop entry
  install -Dm644 "\${srcdir}/figma-desktop.desktop" "\${pkgdir}/usr/share/applications/figma-desktop.desktop"

  # Symlink
  install -dm755 "\${pkgdir}/usr/bin"
  ln -s "/opt/figma-desktop/figma-desktop.AppImage" "\${pkgdir}/usr/bin/figma-desktop"
}
PKGEOF

echo "PKGBUILD generated at $pkgbuild_path"
cat "$pkgbuild_path"

# Desktop file already at $desktop_file_src == $work_dir/figma-desktop.desktop, no copy needed

# --- Generate .SRCINFO ---
srcinfo_path="$work_dir/.SRCINFO"
if command -v makepkg &>/dev/null; then
  echo "Generating .SRCINFO via makepkg --printsrcinfo..."
  (cd "$work_dir" && makepkg --printsrcinfo > "$srcinfo_path")
else
  echo "makepkg not found — generating .SRCINFO manually..."
  cat > "$srcinfo_path" << SRCEOF
pkgbase = $aur_pkgname
	pkgdesc = $description (patched Windows build, incl. FigJam and local font support)
	pkgver = $aur_pkgver
	pkgrel = $aur_pkgrel
	url = $repo_url
	arch = $pacman_arch
	license = custom:Figma-EULA
	depends = fuse2
	depends = zlib
	depends = hicolor-icon-theme
	depends = gtk3
	depends = nss
	depends = libxcrypt-compat
	provides = figma-desktop
	conflicts = figma-desktop
	options = !strip
	source = $appimage_name::${appimage_url}
	source = figma-desktop.desktop
	sha256sums = $appimage_sha
	sha256sums = $desktop_sha

pkgname = $aur_pkgname
SRCEOF
fi
echo ".SRCINFO generated at $srcinfo_path"
cat "$srcinfo_path"

# --- Update repo-root PKGBUILD/.SRCINFO for PR ---
# Only overwrite root if we have a real checksum (not SKIP) — preserve last good PKGBUILD for AUR
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $appimage_sha != "SKIP" ]]; then
  echo "Updating repo-root PKGBUILD/.SRCINFO at $project_root ..."
  cp "$pkgbuild_path" "$project_root/PKGBUILD"
  cp "$desktop_file_src" "$project_root/figma-desktop.desktop"
  cp "$srcinfo_path" "$project_root/.SRCINFO"
  echo "Repo-root files updated."
else
  echo "Skipping repo-root update (appimage SHA is SKIP — no release artifact yet, keeping existing PKGBUILD)"
  echo "Generated files remain in $work_dir/PKGBUILD + .SRCINFO for inspection"
fi

# --- Optionally build binary pacman package via makepkg ---
if command -v makepkg &>/dev/null; then
  echo "Building .pkg.tar.zst via makepkg..."
  # makepkg refuses to run as root without --asdeps; handle it
  makepkg_args=(-f --noconfirm)
  if (( EUID == 0 )); then
    makepkg_args+=(--asdeps --allow-dependency-resolution)
    # On some systems makepkg still refuses as root — try with --asroot if available or warn
    if ! (cd "$work_dir" && makepkg "${makepkg_args[@]}"); then
      echo "makepkg as root failed — trying with su to nobody or skipping binary build"
      # Don't fail the whole build; PKGBUILD/.SRCINFO are already generated
      echo "PKGBUILD/.SRCINFO are ready. Build binary manually with: cd $work_dir && makepkg"
      exit 0
    fi
  else
    (cd "$work_dir" && makepkg "${makepkg_args[@]}")
  fi
  pkg_file=$(find "$work_dir" -maxdepth 1 -name "*.pkg.tar.zst" | head -n 1)
  if [[ -n $pkg_file ]]; then
    echo "Pacman package built: $pkg_file"
  else
    echo "Warning: makepkg finished but no .pkg.tar.zst found in $work_dir"
  fi
else
  echo "makepkg not found — skipping binary .pkg.tar.zst build."
  echo "Install pacman/makepkg on Arch, or run: cd $work_dir && makepkg"
fi

echo '--- Pacman Package Build Finished ---'
