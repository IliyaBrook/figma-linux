#!/usr/bin/env bash

# Arguments passed from the main script
version="$1"
architecture="$2"
work_dir="$3"           # The top-level build directory (e.g., ./build)
app_staging_dir="$4"    # Directory containing the prepared app files
package_name="$5"
maintainer="$6"
description="$7"

echo '--- Starting Debian Package Build ---'
echo "Version: $version"
echo "Architecture: $architecture"
echo "Work Directory: $work_dir"
echo "App Staging Directory: $app_staging_dir"
echo "Package Name: $package_name"

package_root="$work_dir/package"
install_dir="$package_root/usr"

# Clean previous package structure if it exists
rm -rf "$package_root"

# Create Debian package structure
echo "Creating package structure in $package_root..."
mkdir -p "$package_root/DEBIAN" || exit 1
mkdir -p "$install_dir/lib/$package_name" || exit 1
mkdir -p "$install_dir/share/applications" || exit 1
mkdir -p "$install_dir/share/icons" || exit 1
mkdir -p "$install_dir/bin" || exit 1

# --- Icon Installation ---
echo 'Installing icons...'
# Find all extracted icon PNG files and install appropriate sizes
for size in 16 24 32 48 64 128 256; do
	icon_dir="$install_dir/share/icons/hicolor/${size}x${size}/apps"
	mkdir -p "$icon_dir" || exit 1
	# Try to find an icon of this size from the extracted files
	# Icons may be from ImageMagick (figma_icon-N.png) or icotool (figma_N_SIZExSIZExDEPTH.png)
	icon_source_path=$(find "$work_dir" -maxdepth 1 -name "figma_*.png" -exec identify -format '%w %h %i\n' {} \; 2>/dev/null | awk -v s="$size" '$1==s && $2==s {print $3; exit}')
	if [[ -f $icon_source_path ]]; then
		echo "Installing ${size}x${size} icon..."
		install -Dm 644 "$icon_source_path" "$icon_dir/figma-desktop.png" || exit 1
	fi
done
echo 'Icons installed'

# --- Copy Application Files ---
echo "Copying application files from $app_staging_dir..."

# Copy local electron first if it was packaged (check if node_modules exists in staging)
if [[ -d $app_staging_dir/node_modules ]]; then
	echo 'Copying packaged electron...'
	cp -r "$app_staging_dir/node_modules" "$install_dir/lib/$package_name/" || exit 1
fi

# Install app.asar in Electron's resources directory where process.resourcesPath points
resources_dir="$install_dir/lib/$package_name/node_modules/electron/dist/resources"
mkdir -p "$resources_dir" || exit 1
cp "$app_staging_dir/app.asar" "$resources_dir/" || exit 1
if [[ -d $app_staging_dir/app.asar.unpacked ]]; then
	cp -r "$app_staging_dir/app.asar.unpacked" "$resources_dir/" || exit 1
fi
echo 'Application files copied to Electron resources directory'

# Copy shared launcher library
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$script_dir/launcher-common.sh" "$install_dir/lib/$package_name/" || exit 1
echo 'Shared launcher library copied'

# --- Create Desktop Entry ---
echo 'Creating desktop entry...'
cat > "$install_dir/share/applications/figma-desktop.desktop" << EOF
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
EOF
echo 'Desktop entry created'

# --- Create Launcher Script ---
echo 'Creating launcher script...'
cat > "$install_dir/bin/figma-desktop" << EOF
#!/usr/bin/env bash

# Source shared launcher library
source "/usr/lib/$package_name/launcher-common.sh"

# Setup logging and environment
setup_logging || exit 1
setup_electron_env

# Log startup info
log_message '--- Figma Desktop Launcher Start ---'
log_message "Timestamp: \$(date)"
log_message "Arguments: \$@"

# Check for display
if ! check_display; then
	log_message 'No display detected (TTY session)'
	echo 'Error: Figma Desktop requires a graphical desktop environment.' >&2
	echo 'Please run from within an X11 or Wayland session, not from a TTY.' >&2
	exit 1
fi

# Detect display backend
detect_display_backend
if [[ \$is_wayland == true ]]; then
	log_message 'Wayland detected'
fi

# Determine Electron executable path
electron_exec='electron'
local_electron_path="/usr/lib/$package_name/node_modules/electron/dist/electron"
if [[ -f \$local_electron_path ]]; then
	electron_exec="\$local_electron_path"
	log_message "Using local Electron: \$electron_exec"
else
	if command -v electron &> /dev/null; then
		log_message "Using global Electron: \$electron_exec"
	else
		log_message 'Error: Electron executable not found'
		if command -v zenity &> /dev/null; then
			zenity --error \
				--text='Figma Desktop cannot start because the Electron framework is missing.'
		elif command -v kdialog &> /dev/null; then
			kdialog --error \
				'Figma Desktop cannot start because the Electron framework is missing.'
		fi
		exit 1
	fi
fi

# App path
app_path="/usr/lib/$package_name/node_modules/electron/dist/resources/app.asar"

# Build electron args
build_electron_args 'deb'

# Add app path LAST
electron_args+=("\$app_path")

# Change to application directory
app_dir="/usr/lib/$package_name"
log_message "Changing directory to \$app_dir"
cd "\$app_dir" || { log_message "Failed to cd to \$app_dir"; exit 1; }

# Execute Electron
log_message "Executing: \$electron_exec \${electron_args[*]} \$*"
"\$electron_exec" "\${electron_args[@]}" "\$@" >> "\$log_file" 2>&1
exit_code=\$?
log_message "Electron exited with code: \$exit_code"
log_message '--- Figma Desktop Launcher End ---'
exit \$exit_code
EOF
chmod +x "$install_dir/bin/figma-desktop" || exit 1
echo 'Launcher script created'

# --- Create Control File ---
echo 'Creating control file...'
cat > "$package_root/DEBIAN/control" << EOF
Package: $package_name
Version: $version
Section: utils
Priority: optional
Architecture: $architecture
Maintainer: $maintainer
Description: $description
 Figma is a collaborative design tool.
 This package provides the desktop interface for Figma on Linux.
 .
 Supported on Debian-based Linux distributions (Debian, Ubuntu, Linux Mint, etc.)
EOF
echo 'Control file created'

# --- Create Postinst Script ---
echo 'Creating postinst script...'
cat > "$package_root/DEBIAN/postinst" << EOF
#!/bin/sh
set -e

# Update desktop database for MIME types
echo "Updating desktop database..."
update-desktop-database /usr/share/applications &> /dev/null || true

# Set correct permissions for chrome-sandbox
echo "Setting chrome-sandbox permissions..."
LOCAL_SANDBOX_PATH="/usr/lib/$package_name/node_modules/electron/dist/chrome-sandbox"
if [ -f "\$LOCAL_SANDBOX_PATH" ]; then
    echo "Found chrome-sandbox at: \$LOCAL_SANDBOX_PATH"
    chown root:root "\$LOCAL_SANDBOX_PATH" || echo "Warning: Failed to chown chrome-sandbox"
    chmod 4755 "\$LOCAL_SANDBOX_PATH" || echo "Warning: Failed to chmod chrome-sandbox"
    echo "Permissions set for \$LOCAL_SANDBOX_PATH"
else
    echo "Warning: chrome-sandbox binary not found at \$LOCAL_SANDBOX_PATH."
fi

exit 0
EOF
chmod +x "$package_root/DEBIAN/postinst" || exit 1
echo 'Postinst script created'

# --- Build .deb Package ---
echo 'Building .deb package...'
deb_file="$work_dir/${package_name}_${version}_${architecture}.deb"

# Fix DEBIAN directory permissions (must be 755 for dpkg-deb)
echo 'Setting DEBIAN directory permissions...'
chmod 755 "$package_root/DEBIAN" || exit 1
chmod 755 "$package_root/DEBIAN/postinst" || exit 1

if ! dpkg-deb --build "$package_root" "$deb_file"; then
	echo 'Failed to build .deb package' >&2
	exit 1
fi

echo "Deb package built successfully: $deb_file"
echo '--- Debian Package Build Finished ---'

exit 0
