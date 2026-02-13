#!/usr/bin/env bash

# Arguments passed from the main script
version="$1"
architecture="$2"
work_dir="$3"           # The top-level build directory (e.g., ./build)
app_staging_dir="$4"    # Directory containing the prepared app files
package_name="$5"
# $6 is maintainer (unused in RPM spec)
description="$7"

echo '--- Starting RPM Package Build ---'
echo "Version: $version"

# RPM Version field cannot contain hyphens
if [[ $version == *-* ]]; then
	rpm_version="${version%%-*}"
	rpm_release="${version#*-}"
	echo "RPM Version: $rpm_version"
	echo "RPM Release: $rpm_release"
else
	rpm_version="$version"
	rpm_release="1"
fi
echo "Architecture: $architecture"
echo "Work Directory: $work_dir"
echo "App Staging Directory: $app_staging_dir"
echo "Package Name: $package_name"

# Map architecture to RPM naming
case "$architecture" in
	amd64) rpm_arch='x86_64' ;;
	arm64) rpm_arch='aarch64' ;;
	*)
		echo "Unsupported architecture for RPM: $architecture" >&2
		exit 1
		;;
esac

# RPM build directories
rpmbuild_dir="$work_dir/rpmbuild"
rm -rf "$rpmbuild_dir"
mkdir -p "$rpmbuild_dir"/{BUILD,RPMS,SOURCES,SPECS,SRPMS} || exit 1

# Get script directory
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create staging area
staging_dir="$work_dir/rpm-staging"
rm -rf "$staging_dir"
mkdir -p "$staging_dir" || exit 1

# --- Create Desktop Entry ---
echo 'Creating desktop entry...'
cat > "$staging_dir/figma-desktop.desktop" << EOF
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

# --- Create Launcher Script ---
echo 'Creating launcher script...'
cat > "$staging_dir/figma-desktop" << EOF
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
chmod +x "$staging_dir/figma-desktop"

# --- Build Icon Install Commands ---
icon_install_cmds=""
for size in 16 24 32 48 64 128 256; do
	icon_source_path=$(find "$work_dir" -maxdepth 1 -name "figma_*.png" -exec identify -format '%w %h %i\n' {} \; 2>/dev/null | awk -v s="$size" '$1==s && $2==s {print $3; exit}')
	if [[ -f $icon_source_path ]]; then
		icon_install_cmds+="mkdir -p %{buildroot}/usr/share/icons/hicolor/${size}x${size}/apps
install -Dm 644 $icon_source_path %{buildroot}/usr/share/icons/hicolor/${size}x${size}/apps/figma-desktop.png
"
	fi
done

# --- Create RPM Spec File ---
echo 'Creating RPM spec file...'
cat > "$rpmbuild_dir/SPECS/$package_name.spec" << SPECEOF
Name:           $package_name
Version:        $rpm_version
Release:        $rpm_release%{?dist}
Summary:        $description

License:        Proprietary
URL:            https://www.figma.com

AutoReqProv:    no
%define debug_package %{nil}
%define __strip /bin/true
%define _build_id_links none

%description
Figma is a collaborative design tool.
This package provides the desktop interface for Figma on Linux.

Supported on RPM-based Linux distributions (Fedora, RHEL, CentOS, etc.)

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr/lib/$package_name
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/bin

# Install icons
$icon_install_cmds

# Copy application files
cp -r $app_staging_dir/node_modules %{buildroot}/usr/lib/$package_name/
cp $app_staging_dir/app.asar %{buildroot}/usr/lib/$package_name/node_modules/electron/dist/resources/
if [ -d "$app_staging_dir/app.asar.unpacked" ]; then
    cp -r $app_staging_dir/app.asar.unpacked %{buildroot}/usr/lib/$package_name/node_modules/electron/dist/resources/
fi

# Copy shared launcher library
cp $script_dir/launcher-common.sh %{buildroot}/usr/lib/$package_name/

# Install desktop entry
install -Dm 644 $staging_dir/figma-desktop.desktop %{buildroot}/usr/share/applications/figma-desktop.desktop

# Install launcher script
install -Dm 755 $staging_dir/figma-desktop %{buildroot}/usr/bin/figma-desktop

%post
update-desktop-database /usr/share/applications &> /dev/null || true

SANDBOX_PATH="/usr/lib/$package_name/node_modules/electron/dist/chrome-sandbox"
if [ -f "\$SANDBOX_PATH" ]; then
    chown root:root "\$SANDBOX_PATH" || echo "Warning: Failed to chown chrome-sandbox"
    chmod 4755 "\$SANDBOX_PATH" || echo "Warning: Failed to chmod chrome-sandbox"
fi

%postun
update-desktop-database /usr/share/applications &> /dev/null || true

%files
%attr(755, root, root) /usr/bin/figma-desktop
/usr/lib/$package_name
/usr/share/applications/figma-desktop.desktop
/usr/share/icons/hicolor/*/apps/figma-desktop.png
SPECEOF

echo 'RPM spec file created'

# --- Build RPM Package ---
echo 'Building RPM package...'
if ! rpmbuild --define "_topdir $rpmbuild_dir" \
	--define "_rpmdir $work_dir" \
	--target "$rpm_arch" \
	-bb "$rpmbuild_dir/SPECS/$package_name.spec"; then
	echo 'Failed to build RPM package' >&2
	exit 1
fi

# Find and move the built RPM
rpm_file=$(find "$work_dir" -name "${package_name}-${rpm_version}*.rpm" -type f | head -n 1)
if [[ -z $rpm_file ]]; then
	echo 'Could not find built RPM file' >&2
	exit 1
fi

final_rpm="$work_dir/${package_name}-${version}-1.${rpm_arch}.rpm"
if [[ $rpm_file != "$final_rpm" ]]; then
	mv "$rpm_file" "$final_rpm" || exit 1
fi

echo "RPM package built successfully: $final_rpm"
echo '--- RPM Package Build Finished ---'

exit 0
