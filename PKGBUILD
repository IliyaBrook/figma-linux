# Maintainer: Soroush Alinia <soroush.alinia.dev@gmail.com>
pkgname=figma-desktop-bin
pkgver=126.5.6
pkgrel=1
pkgdesc="Figma Desktop for Linux (patched Windows build, incl. FigJam and local font support)"
arch=('x86_64')
url="https://github.com/soroushalinia/figma-linux"
license=('custom:Figma-EULA')
depends=('fuse2' 'zlib' 'hicolor-icon-theme' 'gtk3' 'nss' 'libxcrypt-compat')
options=('!strip')
provides=('figma-desktop')
conflicts=('figma-desktop')
source=("figma-desktop-126.5.6-amd64.AppImage::https://github.com/IliyaBrook/figma-linux/releases/download/126.5.6/figma-desktop-126.5.6-amd64.AppImage"
        "figma-desktop.desktop")
sha256sums=('48b9f8cbe35509c04366b1aa2299a920441abd8ef19e0b7924c23cc86d60ebfd'
            '5c0a875a0d414fd8c92e596736707e079a24a03de235f197f38f65b491688df3')

prepare() {
  chmod +x "${srcdir}/figma-desktop-126.5.6-amd64.AppImage"
}

package() {
  # Install AppImage
  install -dm755 "${pkgdir}/opt/figma-desktop"
  install -Dm755 "${srcdir}/figma-desktop-126.5.6-amd64.AppImage" "${pkgdir}/opt/figma-desktop/figma-desktop.AppImage"

  # Extract and install icon from the AppImage itself
  cd "${srcdir}"
  "${srcdir}/figma-desktop-126.5.6-amd64.AppImage" --appimage-extract >/dev/null 2>&1 || true
  if [ -f "squashfs-root/figma-desktop.png" ]; then
    install -Dm644 "squashfs-root/figma-desktop.png" "${pkgdir}/usr/share/icons/hicolor/512x512/apps/figma-desktop.png"
  elif [ -f "squashfs-root/.DirIcon" ]; then
    install -Dm644 "squashfs-root/.DirIcon" "${pkgdir}/usr/share/icons/hicolor/512x512/apps/figma-desktop.png"
  elif [ -f "squashfs-root/io.github.nickvdp.figma-desktop-linux.png" ]; then
    install -Dm644 "squashfs-root/io.github.nickvdp.figma-desktop-linux.png" "${pkgdir}/usr/share/icons/hicolor/512x512/apps/figma-desktop.png"
  fi
  rm -rf "squashfs-root"

  # Desktop entry
  install -Dm644 "${srcdir}/figma-desktop.desktop" "${pkgdir}/usr/share/applications/figma-desktop.desktop"

  # Symlink
  install -dm755 "${pkgdir}/usr/bin"
  ln -s "/opt/figma-desktop/figma-desktop.AppImage" "${pkgdir}/usr/bin/figma-desktop"
}
