APPIMAGE := $(wildcard figma-desktop-*.AppImage)

.PHONY: build build-deb build-rpm build-pacman build-appimage run run-debug clean url

build: build-appimage

build-deb:
	./build.sh --build deb --clean no

build-rpm:
	./build.sh --build rpm --clean no

build-pacman:
	./build.sh --build pacman --clean no

build-appimage:
	./build.sh --build appimage --clean no

run:
ifndef APPIMAGE
	$(error No AppImage found. Run 'make build' first)
endif
	./$(APPIMAGE)

run-debug:
ifndef APPIMAGE
	$(error No AppImage found. Run 'make build' first)
endif
	FIGMA_DEBUG=1 ./$(APPIMAGE)

clean:
	rm -rf build/
	rm -rf src/ pkg/
	rm -f figma-desktop-*.AppImage
	rm -f figma-desktop_*.deb
	rm -f figma-desktop-*.rpm
	rm -f figma-desktop-*.pkg.tar.zst
	rm -f figma-desktop-*.pkg.tar.zst.sig

url:
	./figma-version-tool.sh
