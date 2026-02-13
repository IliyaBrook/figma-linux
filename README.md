# Figma Desktop for Linux

Run the **real** Figma Desktop app on Linux — not a browser wrapper, not a web app, but the actual Electron-based desktop client with full functionality.

This project extracts the official Figma Desktop Windows installer, patches it for Linux compatibility, and packages it as an **AppImage**, **.deb**, or **.rpm**. You get everything the Windows/macOS client has: system tray icon, `figma://` protocol handling, MCP server support, native window frames, and offline file opening.

## Why This Exists

Every other "Figma for Linux" project is just a browser window pretending to be a desktop app. This one is different:

| Feature | This project | Browser wrappers |
|---|---|---|
| Full desktop Electron client | Yes | No |
| System tray icon | Yes | No |
| `figma://` URL protocol handler | Yes | No |
| MCP server (`127.0.0.1:3845/mcp`) | Yes | No |
| Native `.fig` file opening | Yes | No |
| Dark mode detection | Yes | Varies |
| Figma i18n locales (7 languages) | Yes | No |
| Desktop notifications | Yes | Browser-level |
| Auto desktop integration | Yes | Manual |

## How It Works

The build script performs a multi-stage pipeline:

1. **Extract** — Downloads (or uses a local copy of) `FigmaSetup.exe`, unpacks the Squirrel/NuGet package to reach `app.asar`
2. **Patch** — Applies Linux-specific fixes:
   - Enables native window frames (Figma ships with `frame:false` for custom titlebar)
   - Stubs Windows/macOS native modules (`bindings.node`, `desktop_rust.node`) with JS equivalents
   - Fixes `handleCommandLineArgs` to find `figma://` URLs in Linux's argv layout
   - Hides the Electron menu bar while keeping the native frame
3. **Package** — Bundles a matching Electron binary + patched `app.asar` into your chosen format
4. **Integrate** — On first launch, the AppImage automatically registers a `.desktop` file and `figma://` URI handler

## Quick Start

### Prerequisites

- **Node.js 20+** (or the script installs it locally)
- **p7zip** — for extracting the Windows installer
- **ImageMagick** — for icon conversion
- **wget** — for downloading the installer

> The build script auto-detects missing dependencies and installs them via `apt` (Debian/Ubuntu) or `dnf` (Fedora/RHEL).

### Build & Run

```bash
git clone https://github.com/nickvdp/figma-desktop-linux.git
cd figma-desktop-linux

# Build an AppImage (default)
./build.sh

# Run it
chmod +x figma-desktop-*.AppImage
./figma-desktop-*.AppImage
```

That's it. The AppImage is portable — move it anywhere you like. On first launch it automatically:
- Creates a `.desktop` entry in `~/.local/share/applications/`
- Registers itself as the `figma://` URL handler
- Copies the Figma icon to your icon theme

### Build Options

```bash
# Build a .deb package (Debian/Ubuntu)
./build.sh --build deb

# Build an .rpm package (Fedora/RHEL)
./build.sh --build rpm

# Build an AppImage (explicit)
./build.sh --build appimage

# Use a previously downloaded installer (skip download)
./build.sh --exe /path/to/FigmaSetup.exe

# Keep intermediate build files for debugging
./build.sh --clean no
```

### Install Packages

```bash
# Debian/Ubuntu
sudo apt install ./figma-desktop_*.deb

# Fedora/RHEL
sudo dnf install ./figma-desktop-*.rpm
```

### Makefile Shortcuts

```bash
make build          # Build AppImage (default)
make build-deb      # Build .deb
make build-rpm      # Build .rpm
make run            # Run the built AppImage
make run-debug      # Run with FIGMA_DEBUG=1 (logs to stdout)
make clean          # Remove all build artifacts
make url            # Print the latest Figma download URLs
```

## MCP Server

When Figma Desktop is running, it exposes an MCP (Model Context Protocol) server at:

```
http://127.0.0.1:3845/mcp
```

This is the same MCP endpoint available in the Windows/macOS clients. You can connect any MCP-compatible tool (Claude Code, Cursor, VS Code extensions, etc.) to interact with the running Figma instance — inspect documents, export assets, run code generation, and more.

## Display Server Support

The launcher handles both X11 and Wayland:

| Environment | Behavior |
|---|---|
| **X11** | Works out of the box |
| **Wayland** (default) | Uses XWayland for compatibility |
| **Wayland** (native) | Set `FIGMA_USE_WAYLAND=1` for native Wayland |

```bash
# Force native Wayland mode
FIGMA_USE_WAYLAND=1 ./figma-desktop-*.AppImage
```

## Debugging

Logs are written to `~/.cache/figma-desktop-linux/launcher.log`.

```bash
# Run with debug output to terminal
FIGMA_DEBUG=1 ./figma-desktop-*.AppImage

# Or via Make
make run-debug
```

## Architecture

```
figma-desktop-linux/
  build.sh                          # Main orchestrator
  Makefile                          # Build/run shortcuts
  get-url-x64.sh                   # Print latest Figma download URLs
  scripts/
    frame-fix-wrapper.js            # BrowserWindow monkey-patch for native frames
    figma-native-stub.js            # JS stubs for Windows/macOS native modules
    launcher-common.sh              # Shared X11/Wayland detection logic
    build-appimage.sh               # AppImage packaging
    build-deb-package.sh            # Debian packaging
    build-rpm-package.sh            # RPM packaging
```

### What Gets Patched

- **`frame:!1` / `frame:false`** in BrowserWindow options replaced with `frame:true`
- **`titleBarStyle:"hidden"`** replaced with `"default"`
- **`require("./bindings.node")`** redirected to `figma-native-stub.js` (40+ stubbed methods)
- **`require("./desktop_rust.node")`** redirected to stub
- **`handleCommandLineArgs`** rewritten to scan all argv entries (Linux passes CLI flags before the app path)
- **`package.json` main entry** updated to load `frame-fix-wrapper.js` before the original entry point

## Known Limitations

- **No auto-updates** — The Squirrel updater is Windows-only. Rebuild to update to a new version.
- **No eyedropper tool** — Requires native screen capture (`bindings.node`), which is stubbed.
- **x86_64 only** — Figma's Windows installer is x86_64-only.

## License

This project provides build tooling only. Figma Desktop is proprietary software owned by Figma, Inc. By using this project you agree to [Figma's Terms of Service](https://www.figma.com/tos/).
