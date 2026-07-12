<h1 align="center">
  <img src="assets/figma-icon.svg" alt="Figma" width="38" valign="middle" />
  Figma Desktop for Linux
</h1>

<p align="center">
  Run the <b>real</b> Figma Desktop app on Linux — not a browser wrapper, not a web app,<br/>
  but the actual Electron-based desktop client with full functionality.
</p>

<p align="center">
  <a href="https://github.com/IliyaBrook/figma-linux/releases/latest"><img src="https://img.shields.io/github/v/release/IliyaBrook/figma-linux?style=for-the-badge&label=Release&color=blue" alt="Release" /></a>
  &nbsp;
  <img src="https://img.shields.io/badge/Platform-Linux%20x86__64-orange?style=for-the-badge&logo=linux&logoColor=white" alt="Platform" />
  &nbsp;
  <img src="https://img.shields.io/badge/Display-X11%20%7C%20Wayland-green?style=for-the-badge" alt="Display Server" />
  &nbsp;
  <img src="https://img.shields.io/badge/Package-AppImage%20%7C%20deb%20%7C%20rpm-purple?style=for-the-badge" alt="Packages" />
</p>

This project extracts the official Figma Desktop Windows installer, patches it for Linux compatibility, and packages it as an **AppImage**, **.deb**, or **.rpm**. You get the real desktop client experience: system tray icon, `figma://` protocol handling, MCP server support, native window frames, local font support, and offline file opening.

## Why This Exists

Every other "Figma for Linux" project is just a browser window pretending to be a desktop app. This one is different:

| Feature                                           | This project                  | Browser wrappers |
| ------------------------------------------------- | ----------------------------- | ---------------- |
| Full desktop Electron client                      | Yes                           | No               |
| System tray icon                                  | Yes                           | No               |
| `figma://` URL protocol handler                   | Yes                           | No               |
| MCP server (`127.0.0.1:3845/mcp`)                 | Yes                           | No               |
| Native `.fig` file opening                        | Yes                           | No               |
| Dark mode detection                               | Yes                           | Varies           |
| Figma i18n locales (7 languages)                  | Yes                           | No               |
| Desktop notifications                             | Yes                           | Browser-level    |
| Auto desktop integration                          | Yes                           | Manual           |
| Allow duplicate tabs (same file in multiple tabs) | Yes                           | No               |
| Built-in local font helper                        | Yes, no separate agent needed | No               |

## How It Works

The build script performs a multi-stage pipeline:

1. **Extract** — Downloads (or uses a local copy of) `FigmaSetup.exe`, unpacks the Squirrel/NuGet package to reach `app.asar`
2. **Patch** — Applies Linux-specific fixes:
   - Enables native window frames (Figma ships with `frame:false` for custom titlebar)
   - Stubs Windows/macOS native modules (`bindings.node`, `desktop_rust.node`) with JS equivalents
   - Spoofs the renderer User-Agent as Windows so Figma enables the desktop/local font flows
   - Starts a built-in Linux font helper and scans system/user font directories
   - Fixes `handleCommandLineArgs` to find `figma://` URLs in Linux's argv layout
   - Fixes Linux tray behavior, native frame sizing, menu visibility, and duplicate-tab handling
3. **Package** — Bundles a matching Electron binary + patched `app.asar` into your chosen format
4. **Integrate** — On first launch, the AppImage automatically registers a `.desktop` file and `figma://` URI handler

## Installation

### Option 1: Download Pre-built AppImage (Recommended)

Grab the latest AppImage from the [Releases](https://github.com/IliyaBrook/figma-linux/releases) page — no build step required. New project builds are published there as AppImage, deb, and rpm artifacts.

```bash
chmod +x figma-desktop-*.AppImage
./figma-desktop-*.AppImage
```

On first launch the AppImage automatically:

- Creates a `.desktop` entry in `~/.local/share/applications/`
- Registers itself as the `figma://` URL handler
- Copies the Figma icon to your icon theme

After that, Figma appears in your application menu like any other app.

### Local Fonts

The app includes a built-in font helper, so AppImage, deb, and rpm builds expose installed system/user fonts without a separate `figma-agent-linux` install. On launch, the patched native stub starts a localhost helper compatible with [neetly/figma-agent-linux](https://github.com/neetly/figma-agent-linux) at `127.0.0.1:44950` and serves the same data through Figma's desktop font APIs.

This covers the normal font picker and the **Installed by you** flow. If you already run an external helper on that port, this app leaves it alone. You can point the desktop stub at another endpoint with `FIGMA_FONT_AGENT_URL`, disable external agent lookup with `FIGMA_FONT_AGENT_DISABLED=1`, or disable the built-in localhost helper with `FIGMA_BUILTIN_FONT_AGENT_DISABLED=1`.

### Option 2: Build from Source

#### Prerequisites

- **Node.js 22.12+** (or the script installs it locally)
- **p7zip** — for extracting the Windows installer
- **ImageMagick** — for icon conversion
- **wget** — for downloading the installer

> The build script auto-detects missing dependencies and installs them via `apt` (Debian/Ubuntu) or `dnf` (Fedora/RHEL).

#### Build & Run

```bash
git clone https://github.com/IliyaBrook/figma-linux.git
cd figma-linux

# Build an AppImage (default)
./build.sh

# Run it
chmod +x figma-desktop-*.AppImage
./figma-desktop-*.AppImage
```

#### Build Options

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

#### Install Packages

```bash
# Debian/Ubuntu
sudo apt install ./figma-desktop_*.deb

# Fedora/RHEL
sudo dnf install ./figma-desktop-*.rpm
```

#### Makefile Shortcuts

```bash
make build          # Build AppImage (default)
make build-deb      # Build .deb
make build-rpm      # Build .rpm
make run            # Run the built AppImage
make run-debug      # Run with FIGMA_DEBUG=1 (logs to stdout)
make clean          # Remove all build artifacts
make url            # Check Figma RELEASES and installer URLs
```

## MCP Server

When Figma Desktop is running, it exposes an MCP (Model Context Protocol) server at:

```
http://127.0.0.1:3845/mcp
```

This is the same MCP endpoint available in the Windows/macOS clients. You can connect any MCP-compatible tool (Claude Code, Cursor, VS Code extensions, etc.) to interact with the running Figma instance — inspect documents, export assets, run code generation, and more.

## Display Server Support

The launcher handles both X11 and Wayland:

| Environment           | Behavior                                     |
| --------------------- | -------------------------------------------- |
| **X11**               | Works out of the box                         |
| **Wayland** (default) | Uses XWayland for compatibility              |
| **Wayland** (native)  | Set `FIGMA_USE_WAYLAND=1` for native Wayland |

```bash
# Force native Wayland mode
FIGMA_USE_WAYLAND=1 ./figma-desktop-*.AppImage
```

## Extra Features

This build includes enhancements not available in the official Figma Desktop client:

### Allow Duplicate Tabs

In the official Figma client, clicking a file that's already open simply switches to the existing tab — there's no way to open the same file in two tabs side by side. This build adds a **"Allow Duplicate Tabs"** toggle in the system tray menu.

**How to use:** Right-click the Figma icon in the system tray and check **"Allow Duplicate Tabs"**. Now clicking any file (from Home, Starred, Recents, or anywhere) will always open it in a new tab, even if it's already open. Uncheck to restore the default behavior.

This is useful when you need to view different pages or sections of the same file simultaneously.

## Debugging

Logs are written to `~/.cache/figma-desktop-linux/launcher.log`.

```bash
# Run with debug output to terminal
FIGMA_DEBUG=1 ./figma-desktop-*.AppImage

# Or via Make
make run-debug
```

Setting `FIGMA_DEBUG=1` enables verbose logging to stdout and automatically opens DevTools for the tray notification window (Feed).

### Developer Tools Shortcuts

Figma Desktop includes built-in DevTools accessible via keyboard shortcuts (menu bar: **Help → Troubleshooting**):

| Shortcut           | What it opens                                                        |
| ------------------ | -------------------------------------------------------------------- |
| `Ctrl+Alt+I`       | DevTools for the **active tab** (editor, files — main Figma content) |
| `Shift+Ctrl+Alt+I` | DevTools for the **shell** (window frame, tab bar, sidebar)          |

> **Tip:** The menu bar is hidden by default. Press `Alt` to toggle it and access **Help → Troubleshooting** for additional debug options including saving debug info, network logs, and performance logs.

## Architecture

```
figma-desktop-linux/
  build.sh                          # Main orchestrator
  Makefile                          # Build/run shortcuts
  figma-version-tool.sh             # Compare RELEASES vs FigmaSetup.exe versions
  scripts/
    frame-fix-wrapper.js            # BrowserWindow monkey-patch for native frames
    figma-native-stub.js            # JS stubs for Windows/macOS native modules
    font-enum/                      # Pure JS local/system font scanner + parser
    launcher-common.sh              # Shared X11/Wayland detection logic
    build-appimage.sh               # AppImage packaging
    build-deb-package.sh            # Debian packaging
    build-rpm-package.sh            # RPM packaging
  .github/workflows/
    font-enum-tests.yml             # Unit tests for the local font implementation
    global-workflows.yml            # Telegram, stale issue, and issue triage workflows
```

### What Gets Patched

- **Window shell** — forces native frames, hides the Windows caption buttons, keeps the menu bar hidden by default, and fixes stale content bounds after Linux tiling/maximize events.
- **Native modules** — redirects `bindings.node` and `desktop_rust.node` imports to `figma-native-stub.js`, including the `bindings_worker.js` utility process used for font enumeration.
- **Local fonts** — starts a built-in localhost helper at `127.0.0.1:44950` with `/figma/version`, `/figma/font-files`, and `/figma/font-file`, backed by the pure JS scanner in `scripts/font-enum/`.
- **Linux argument handling** — rewrites `handleCommandLineArgs` so `figma://` URLs and file paths are found even when Electron inserts Linux launcher flags before the app path.
- **Tray integration** — fixes right-click context menus on Linux, adds the persistent **Allow Duplicate Tabs** toggle, and keeps tray notifications debuggable with `FIGMA_DEBUG=1`.
- **Package entrypoint** — updates the packaged `package.json` to load `frame-fix-wrapper.js` before Figma's original entry point.

## Known Limitations

- **No auto-updates** — The Squirrel updater is Windows-only. Rebuild to update to a new version.
- **No eyedropper tool** — Requires native screen capture (`bindings.node`), which is stubbed.
- **x86_64 only** — Figma's Windows installer is x86_64-only.
- **Font preview endpoint is not implemented** — Fonts load through the built-in helper, but `/figma/font-preview` currently returns 404.

## License

This project provides build tooling only. Figma Desktop is proprietary software owned by Figma, Inc. By using this project you agree to [Figma's Terms of Service](https://www.figma.com/tos/).
