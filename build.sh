#!/usr/bin/env bash

#===============================================================================
# Figma Desktop Linux Build Script
# Repackages Figma Desktop (Electron app) for Linux
# Based on claude-desktop-debian architecture
#===============================================================================

# Global variables (set by functions, used throughout)
architecture=''
distro_family=''  # debian, rpm, or unknown
figma_download_url=''
figma_exe_filename='FigmaSetup.exe'
version=''
build_format=''  # Will be set based on distro if not specified
cleanup_action='yes'
perform_cleanup=false
local_exe_path=''
original_user=''
original_home=''
project_root=''
work_dir=''
app_staging_dir=''
chosen_electron_module_path=''
asar_exec=''
figma_extract_dir=''
electron_resources_dest=''
final_output_path=''

# Package metadata (constants)
readonly PACKAGE_NAME='figma-desktop'
readonly MAINTAINER='Figma Desktop Linux Maintainers'
readonly DESCRIPTION='Figma Desktop for Linux'

# Figma download URLs
readonly FIGMA_RELEASES_URL='https://desktop.figma.com/win/RELEASES'
readonly FIGMA_EXE_URL='https://desktop.figma.com/win/FigmaSetup.exe'

#===============================================================================
# Utility Functions
#===============================================================================

check_command() {
	if ! command -v "$1" &> /dev/null; then
		echo "$1 not found"
		return 1
	else
		echo "$1 found"
		return 0
	fi
}

section_header() {
	echo -e "\033[1;36m--- $1 ---\033[0m"
}

section_footer() {
	echo -e "\033[1;36m--- End $1 ---\033[0m"
}

#===============================================================================
# Setup Functions
#===============================================================================

detect_architecture() {
	section_header 'Architecture Detection'
	echo 'Detecting system architecture...'

	local raw_arch
	raw_arch=$(uname -m) || {
		echo 'Failed to detect architecture' >&2
		exit 1
	}
	echo "Detected machine architecture: $raw_arch"

	case "$raw_arch" in
		x86_64)
			architecture='amd64'
			echo 'Configured for amd64 (x86_64) build.'
			;;
		*)
			echo "Unsupported architecture: $raw_arch. Figma Desktop Windows installer is only available for x86_64." >&2
			exit 1
			;;
	esac

	echo "Target Architecture: $architecture"
	section_footer 'Architecture Detection'
}

detect_distro() {
	section_header 'Distribution Detection'
	echo 'Detecting Linux distribution family...'

	if [[ -f /etc/debian_version ]]; then
		distro_family='debian'
		echo "Detected Debian-based distribution"
	elif [[ -f /etc/fedora-release ]]; then
		distro_family='rpm'
		echo "Detected Fedora"
	elif [[ -f /etc/redhat-release ]]; then
		distro_family='rpm'
		echo "Detected Red Hat-based distribution"
	else
		distro_family='unknown'
		echo "Warning: Could not detect distribution family"
		echo "  AppImage build will still work, but native packages (deb/rpm) may not"
	fi

	echo "Distribution: $(grep 'PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo 'Unknown')"
	echo "Distribution family: $distro_family"
	section_footer 'Distribution Detection'
}

check_system_requirements() {
	# Allow running as root in CI/container environments
	if (( EUID == 0 )); then
		if [[ -n ${CI:-} || -n ${GITHUB_ACTIONS:-} || -f /.dockerenv ]]; then
			echo 'Running as root in CI/container environment (allowed)'
		else
			echo 'This script should not be run using sudo or as the root user.' >&2
			echo 'It will prompt for sudo password when needed for specific actions.' >&2
			echo 'Please run as a normal user.' >&2
			exit 1
		fi
	fi

	original_user=$(whoami)
	original_home=$(getent passwd "$original_user" | cut -d: -f6)
	if [[ -z $original_home ]]; then
		echo "Could not determine home directory for user $original_user." >&2
		exit 1
	fi
	echo "Running as user: $original_user (Home: $original_home)"

	# Check for NVM and source it if found
	if [[ -d $original_home/.nvm ]]; then
		echo "Found NVM installation for user $original_user, checking for Node.js 20+..."
		export NVM_DIR="$original_home/.nvm"
		if [[ -s $NVM_DIR/nvm.sh ]]; then
			# shellcheck disable=SC1091
			\. "$NVM_DIR/nvm.sh"
			local node_bin_path=''
			node_bin_path=$(nvm which current | xargs dirname 2>/dev/null || \
				find "$NVM_DIR/versions/node" -maxdepth 2 -type d -name 'bin' | sort -V | tail -n 1)

			if [[ -n $node_bin_path && -d $node_bin_path ]]; then
				echo "Adding NVM Node bin path to PATH: $node_bin_path"
				export PATH="$node_bin_path:$PATH"
			else
				echo 'Warning: Could not determine NVM Node bin path.'
			fi
		else
			echo 'Warning: nvm.sh script not found or not sourceable.'
		fi
	fi

	echo 'System Information:'
	echo "Distribution: $(grep 'PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo 'Unknown')"
	echo "Distribution family: $distro_family"
	echo "Target Architecture: $architecture"
}

parse_arguments() {
	section_header 'Argument Parsing'

	project_root="$(pwd)"
	work_dir="$project_root/build"
	app_staging_dir="$work_dir/electron-app"

	# Set default build format based on detected distro
	case "$distro_family" in
		debian) build_format='deb' ;;
		rpm) build_format='rpm' ;;
		*) build_format='appimage' ;;
	esac

	while (( $# > 0 )); do
		case "$1" in
			-b|--build|-c|--clean|-e|--exe)
				if [[ -z ${2:-} || $2 == -* ]]; then
					echo "Error: Argument for $1 is missing" >&2
					exit 1
				fi
				case "$1" in
					-b|--build) build_format="$2" ;;
					-c|--clean) cleanup_action="$2" ;;
					-e|--exe) local_exe_path="$2" ;;
				esac
				shift 2
				;;
			-h|--help)
				echo "Usage: $0 [--build deb|rpm|appimage] [--clean yes|no] [--exe /path/to/FigmaSetup.exe]"
				echo '  --build: Specify the build format (deb, rpm, or appimage).'
				echo "           Default: auto-detected based on distro (current: $build_format)"
				echo '  --clean: Specify whether to clean intermediate build files (yes or no). Default: yes'
				echo '  --exe:   Use a local Figma installer exe instead of downloading'
				exit 0
				;;
			*)
				echo "Unknown option: $1" >&2
				echo 'Use -h or --help for usage information.' >&2
				exit 1
				;;
		esac
	done

	# Validate arguments
	build_format="${build_format,,}"
	cleanup_action="${cleanup_action,,}"

	if [[ $build_format != 'deb' && $build_format != 'rpm' && $build_format != 'appimage' ]]; then
		echo "Invalid build format specified: '$build_format'. Must be 'deb', 'rpm', or 'appimage'." >&2
		exit 1
	fi

	# Warn if building native package for wrong distro
	if [[ $build_format == 'deb' && $distro_family != 'debian' ]]; then
		echo "Warning: Building .deb package on non-Debian system ($distro_family). This may fail." >&2
	elif [[ $build_format == 'rpm' && $distro_family != 'rpm' ]]; then
		echo "Warning: Building .rpm package on non-RPM system ($distro_family). This may fail." >&2
	fi
	if [[ $cleanup_action != 'yes' && $cleanup_action != 'no' ]]; then
		echo "Invalid cleanup option specified: '$cleanup_action'. Must be 'yes' or 'no'." >&2
		exit 1
	fi

	echo "Selected build format: $build_format"
	echo "Cleanup intermediate files: $cleanup_action"

	[[ $cleanup_action == 'yes' ]] && perform_cleanup=true

	section_footer 'Argument Parsing'
}

check_dependencies() {
	echo 'Checking dependencies...'
	local deps_to_install=''
	local common_deps='p7zip wget convert'
	local all_deps="$common_deps"

	# Add format-specific dependencies
	case "$build_format" in
		deb) all_deps="$all_deps dpkg-deb" ;;
		rpm) all_deps="$all_deps rpmbuild" ;;
	esac

	# Command-to-package mappings per distro family
	declare -A debian_pkgs=(
		[p7zip]='p7zip-full' [wget]='wget'
		[convert]='imagemagick'
		[dpkg-deb]='dpkg-dev' [rpmbuild]='rpm'
	)
	declare -A rpm_pkgs=(
		[p7zip]='p7zip p7zip-plugins' [wget]='wget'
		[convert]='ImageMagick'
		[dpkg-deb]='dpkg' [rpmbuild]='rpm-build'
	)

	local cmd
	for cmd in $all_deps; do
		if ! check_command "$cmd"; then
			case "$distro_family" in
				debian)
					deps_to_install="$deps_to_install ${debian_pkgs[$cmd]}"
					;;
				rpm)
					deps_to_install="$deps_to_install ${rpm_pkgs[$cmd]}"
					;;
				*)
					echo "Warning: Cannot auto-install '$cmd' on unknown distro. Please install manually." >&2
					;;
			esac
		fi
	done

	if [[ -n $deps_to_install ]]; then
		echo "System dependencies needed:$deps_to_install"

		# Determine if we need sudo (skip if already root)
		local sudo_cmd='sudo'
		if (( EUID == 0 )); then
			sudo_cmd=''
			echo 'Installing as root (no sudo needed)...'
		else
			echo 'Attempting to install using sudo...'
			if ! sudo -v; then
				echo 'Failed to validate sudo credentials. Please ensure you can run sudo.' >&2
				exit 1
			fi
		fi

		case "$distro_family" in
			debian)
				if ! $sudo_cmd apt update; then
					echo "Failed to run 'apt update'." >&2
					exit 1
				fi
				# shellcheck disable=SC2086
				if ! $sudo_cmd apt install -y $deps_to_install; then
					echo "Failed to install dependencies using 'apt install'." >&2
					exit 1
				fi
				;;
			rpm)
				# shellcheck disable=SC2086
				if ! $sudo_cmd dnf install -y $deps_to_install; then
					echo "Failed to install dependencies using 'dnf install'." >&2
					exit 1
				fi
				;;
			*)
				echo "Cannot auto-install dependencies on unknown distro." >&2
				echo "Please install these packages manually: $deps_to_install" >&2
				exit 1
				;;
		esac
		echo 'System dependencies installed successfully.'
	fi
}

setup_work_directory() {
	rm -rf "$work_dir"
	mkdir -p "$work_dir" || exit 1
	mkdir -p "$app_staging_dir" || exit 1
}

setup_nodejs() {
	section_header 'Node.js Setup'
	echo 'Checking Node.js version...'

	local node_version_ok=false
	if command -v node &> /dev/null; then
		local node_version node_major
		node_version=$(node --version | cut -d'v' -f2)
		node_major="${node_version%%.*}"
		echo "System Node.js version: v$node_version"

		if (( node_major >= 20 )); then
			echo "System Node.js version is adequate (v$node_version)"
			node_version_ok=true
		else
			echo "System Node.js version is too old (v$node_version). Need v20+"
		fi
	else
		echo 'Node.js not found in system'
	fi

	if [[ $node_version_ok == true ]]; then
		section_footer 'Node.js Setup'
		return 0
	fi

	# Node.js version inadequate - install locally
	echo 'Installing Node.js v20 locally in build directory...'

	local node_arch='x64'
	local node_version_to_install='20.18.1'
	local node_tarball="node-v${node_version_to_install}-linux-${node_arch}.tar.xz"
	local node_url="https://nodejs.org/dist/v${node_version_to_install}/${node_tarball}"
	local node_install_dir="$work_dir/node"

	echo "Downloading Node.js v${node_version_to_install} for ${node_arch}..."
	cd "$work_dir" || exit 1
	if ! wget -O "$node_tarball" "$node_url"; then
		echo "Failed to download Node.js from $node_url" >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	echo 'Extracting Node.js...'
	if ! tar -xf "$node_tarball"; then
		echo 'Failed to extract Node.js tarball' >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	mv "node-v${node_version_to_install}-linux-${node_arch}" "$node_install_dir" || exit 1
	export PATH="$node_install_dir/bin:$PATH"

	if command -v node &> /dev/null; then
		echo "Local Node.js installed successfully: $(node --version)"
	else
		echo 'Failed to install local Node.js' >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	rm -f "$node_tarball"
	cd "$project_root" || exit 1
	section_footer 'Node.js Setup'
}

setup_electron_asar() {
	section_header 'Electron & Asar Setup'

	echo "Ensuring local Electron and Asar installation in $work_dir..."
	cd "$work_dir" || exit 1

	if [[ ! -f package.json ]]; then
		echo "Creating temporary package.json in $work_dir for local install..."
		echo '{"name":"figma-desktop-build","version":"0.0.1","private":true}' > package.json
	fi

	local electron_dist_path="$work_dir/node_modules/electron/dist"
	local asar_bin_path="$work_dir/node_modules/.bin/asar"
	local install_needed=false

	[[ ! -d $electron_dist_path ]] && echo 'Electron distribution not found.' && install_needed=true
	[[ ! -f $asar_bin_path ]] && echo 'Asar binary not found.' && install_needed=true

	if [[ $install_needed == true ]]; then
		echo "Installing Electron and Asar locally into $work_dir..."
		if ! npm install --no-save electron @electron/asar; then
			echo 'Failed to install Electron and/or Asar locally.' >&2
			cd "$project_root" || exit 1
			exit 1
		fi
		echo 'Electron and Asar installation command finished.'
	else
		echo 'Local Electron distribution and Asar binary already present.'
	fi

	if [[ -d $electron_dist_path ]]; then
		echo "Found Electron distribution directory at $electron_dist_path."
		chosen_electron_module_path="$(realpath "$work_dir/node_modules/electron")"
		echo "Setting Electron module path for copying to $chosen_electron_module_path."
	else
		echo "Failed to find Electron distribution directory at '$electron_dist_path' after installation attempt." >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	if [[ -f $asar_bin_path ]]; then
		asar_exec="$(realpath "$asar_bin_path")"
		echo "Found local Asar binary at $asar_exec."
	else
		echo "Failed to find Asar binary at '$asar_bin_path' after installation attempt." >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	cd "$project_root" || exit 1

	if [[ -z $chosen_electron_module_path || ! -d $chosen_electron_module_path ]]; then
		echo 'Critical error: Could not resolve a valid Electron module path to copy.' >&2
		exit 1
	fi

	echo "Using Electron module path: $chosen_electron_module_path"
	echo "Using asar executable: $asar_exec"
	section_footer 'Electron & Asar Setup'
}

#===============================================================================
# Download and Extract Functions
#===============================================================================

resolve_figma_version() {
	section_header 'Resolving Figma Version'

	echo 'Fetching latest Figma Desktop version from RELEASES API...'
	local releases_data
	releases_data=$(curl -s -L -H 'User-Agent: Figma/1 (Windows; x64)' "$FIGMA_RELEASES_URL")

	if [[ -z $releases_data ]]; then
		echo 'Failed to fetch Figma RELEASES data' >&2
		exit 1
	fi

	local nupkg_name
	nupkg_name=$(echo "$releases_data" | awk '{print $2}')
	version=$(echo "$nupkg_name" | sed 's/Figma-\(.*\)-full\.nupkg/\1/')

	if [[ -z $version ]]; then
		echo 'Failed to extract version from RELEASES data' >&2
		exit 1
	fi

	figma_download_url="$FIGMA_EXE_URL"
	echo "Latest Figma version: $version"
	echo "Download URL: $figma_download_url"

	section_footer 'Resolving Figma Version'
}

download_figma_installer() {
	section_header 'Download Figma Installer'

	local figma_exe_path="$work_dir/$figma_exe_filename"

	if [[ -n $local_exe_path ]]; then
		echo "Using local Figma installer: $local_exe_path"
		if [[ ! -f $local_exe_path ]]; then
			echo "Local installer file not found: $local_exe_path" >&2
			exit 1
		fi
		cp "$local_exe_path" "$figma_exe_path" || exit 1
		echo 'Local installer copied to build directory'
	else
		echo "Downloading Figma Desktop installer..."
		if ! wget -O "$figma_exe_path" "$figma_download_url"; then
			echo "Failed to download Figma Desktop installer from $figma_download_url" >&2
			exit 1
		fi
		echo "Download complete: $figma_exe_filename"
	fi

	echo "Extracting resources from $figma_exe_filename..."
	figma_extract_dir="$work_dir/figma-extract"
	mkdir -p "$figma_extract_dir" || exit 1

	if ! 7z x -y "$figma_exe_path" -o"$figma_extract_dir"; then
		echo 'Failed to extract installer' >&2
		exit 1
	fi

	cd "$figma_extract_dir" || exit 1
	local nupkg_path_relative
	nupkg_path_relative=$(find . -maxdepth 1 -name 'Figma-*.nupkg' | head -1)

	if [[ -z $nupkg_path_relative ]]; then
		echo "Could not find Figma nupkg file in $figma_extract_dir" >&2
		cd "$project_root" || exit 1
		exit 1
	fi
	echo "Found nupkg: $nupkg_path_relative (in $figma_extract_dir)"

	# Extract version from nupkg filename (e.g., Figma-126.1.2-full.nupkg)
	local nupkg_version
	nupkg_version=$(echo "$nupkg_path_relative" | LC_ALL=C grep -oP 'Figma-\K[0-9]+\.[0-9]+\.[0-9]+(?=-full)')
	if [[ -n $nupkg_version ]]; then
		version="$nupkg_version"
		echo "Version from nupkg: $version"
	fi

	if ! 7z x -y "$nupkg_path_relative"; then
		echo 'Failed to extract nupkg' >&2
		cd "$project_root" || exit 1
		exit 1
	fi
	echo 'Resources extracted from nupkg'

	cd "$project_root" || exit 1
	section_footer 'Download Figma Installer'
}

#===============================================================================
# Patching Functions
#===============================================================================

extract_app_asar() {
	section_header 'Extracting app.asar'

	echo 'Processing app.asar...'
	local asar_source="$figma_extract_dir/lib/net45/resources/app.asar"
	local unpacked_source="$figma_extract_dir/lib/net45/resources/app.asar.unpacked"

	if [[ ! -f $asar_source ]]; then
		echo "app.asar not found at $asar_source" >&2
		exit 1
	fi

	cp "$asar_source" "$app_staging_dir/" || exit 1
	if [[ -d $unpacked_source ]]; then
		cp -a "$unpacked_source" "$app_staging_dir/" || exit 1
	fi

	cd "$app_staging_dir" || exit 1

	# Extract app.asar - use Node.js script to handle Figma's special asar format
	# (Figma's asar has entries with size=-1000 that crash standard extraction)
	echo 'Extracting app.asar contents (handling Figma-specific format)...'
	node -e "
const asar = require('@electron/asar');
const fs = require('fs');
const path = require('path');
const asarPath = 'app.asar';
const outDir = 'app.asar.contents';
const header = JSON.parse(asar.getRawHeader(asarPath).headerString);

function walk(obj, prefix) {
  const results = [];
  if (obj.files) {
    for (const [name, data] of Object.entries(obj.files)) {
      const fullPath = prefix + '/' + name;
      if (data.files) {
        results.push(...walk(data, fullPath));
      } else {
        results.push({ path: fullPath, size: data.size, offset: data.offset, unpacked: !!data.unpacked });
      }
    }
  }
  return results;
}

const files = walk(header, '');
fs.mkdirSync(outDir, { recursive: true });

const asarBuf = fs.readFileSync(asarPath);
const headerBufSize = asarBuf.readUInt32LE(4);
const dataStart = 8 + headerBufSize;

let extracted = 0, skipped = 0;
for (const f of files) {
  const outPath = path.join(outDir, f.path);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });

  if (f.unpacked || f.size < 0 || f.offset === undefined) {
    skipped++;
    continue;
  }

  try {
    const buf = Buffer.alloc(f.size);
    const fileOffset = parseInt(f.offset);
    asarBuf.copy(buf, 0, dataStart + fileOffset, dataStart + fileOffset + f.size);
    fs.writeFileSync(outPath, buf);
    extracted++;
  } catch(e) {
    console.error('Failed to extract:', f.path, e.message);
  }
}
console.log('Extracted: ' + extracted + ' files, Skipped: ' + skipped + ' (unpacked/special)');
" || exit 1

	echo 'app.asar extraction complete'
	cd "$project_root" || exit 1
	section_footer 'Extracting app.asar'
}

patch_app_asar() {
	section_header 'Patching app.asar'

	cd "$app_staging_dir" || exit 1

	# ---- Frame fix wrapper ----
	echo 'Creating BrowserWindow frame fix wrapper...'
	local original_main
	original_main=$(node -e "const pkg = require('./app.asar.contents/package.json'); console.log(pkg.main);")
	echo "Original main entry: $original_main"

	cp "$project_root/scripts/frame-fix-wrapper.js" app.asar.contents/frame-fix-wrapper.js || exit 1

	cat > app.asar.contents/frame-fix-entry.js << EOFENTRY
// Load frame fix first
require('./frame-fix-wrapper.js');
// Then load original main
require('./${original_main}');
EOFENTRY

	# ---- Patch BrowserWindow creation in main.js ----
	echo 'Patching BrowserWindow creation for native frames...'
	local main_js='app.asar.contents/main.js'
	if [[ -f $main_js ]]; then
		# frame:!1 -> frame:true (minified false)
		sed -i 's/frame:!1/frame:true/g' "$main_js"
		# frame:!0 -> frame:true (minified true with NOT, i.e. false)
		sed -i 's/frame:!0/frame:true/g' "$main_js"
		# frame:false -> frame:true
		sed -i 's/frame[[:space:]]*:[[:space:]]*false/frame:true/g' "$main_js"
		# Remove titleBarStyle:"hidden"
		sed -i 's/titleBarStyle:"hidden"/titleBarStyle:"default"/g' "$main_js"
		echo "Patched $main_js for native frames"
	fi

	# Also patch desktop_shell.js if it has BrowserWindow references
	local shell_js='app.asar.contents/desktop_shell.js'
	if [[ -f $shell_js ]]; then
		sed -i 's/frame:!1/frame:true/g' "$shell_js"
		sed -i 's/frame:!0/frame:true/g' "$shell_js"
		echo "Patched $shell_js"
	fi

	# ---- Update package.json ----
	echo 'Modifying package.json to load frame fix...'
	node -e "
const fs = require('fs');
const pkg = require('./app.asar.contents/package.json');
pkg.originalMain = pkg.main;
pkg.main = 'frame-fix-entry.js';
fs.writeFileSync('./app.asar.contents/package.json', JSON.stringify(pkg, null, 2));
console.log('Updated package.json: main entry set to frame-fix-entry.js');
"

	# ---- Create stub native modules ----
	echo 'Creating stub native modules...'

	# Stub bindings.node - replace the require with our JS stub
	cp "$project_root/scripts/figma-native-stub.js" \
		app.asar.contents/figma-native-stub.js || exit 1

	# Patch main.js to load our stub instead of the native .node files
	echo 'Patching native module loading in main.js...'
	if [[ -f $main_js ]]; then
		# Replace require("./bindings.node") with require("./figma-native-stub.js")
		sed -i 's|require("./bindings.node")|require("./figma-native-stub.js")|g' "$main_js"
		# Replace require("../build/Debug/bindings.node") with require("./figma-native-stub.js")
		sed -i 's|require("../build/Debug/bindings.node")|require("./figma-native-stub.js")|g' "$main_js"
		# Replace require("../build/Release/bindings.node") with require("./figma-native-stub.js")
		sed -i 's|require("../build/Release/bindings.node")|require("./figma-native-stub.js")|g' "$main_js"
		# Replace require("./desktop_rust.node") with require("./figma-native-stub.js").desktop_rust
		sed -i 's|require("./desktop_rust.node")|require("./figma-native-stub.js").desktop_rust|g' "$main_js"
		# Replace require("../rust/desktop_rust.node") with require("./figma-native-stub.js").desktop_rust
		sed -i 's|require("../rust/desktop_rust.node")|require("./figma-native-stub.js").desktop_rust|g' "$main_js"
		echo 'Native module loading patched in main.js'
	fi

	# Also patch bindings_worker.js - runs as a utility process for font enumeration
	local worker_js="$app_staging_dir/app.asar.contents/bindings_worker.js"
	if [[ -f $worker_js ]]; then
		echo 'Patching native module loading in bindings_worker.js...'
		sed -i 's|require("./desktop_rust.node")|require("./figma-native-stub.js").desktop_rust|g' "$worker_js"
		sed -i 's|require("../rust/desktop_rust.node")|require("./figma-native-stub.js").desktop_rust|g' "$worker_js"
		echo 'Native module loading patched in bindings_worker.js'
	else
		echo 'Warning: bindings_worker.js not found - font utility process may crash'
	fi

	# ---- Patch handleCommandLineArgs for Linux argv ----
	# On Linux, Electron is invoked with CLI flags (--no-sandbox, --disable-features=...)
	# before the app.asar path, so process.argv looks like:
	#   [electron, --no-sandbox, --disable-features=..., app.asar, figma://auth?...]
	# But handleCommandLineArgs expects the URL at argv[1] (isPackaged) or argv[2] (dev).
	# We patch it to scan all argv entries for a URL or file path instead.
	echo 'Patching handleCommandLineArgs for Linux argv layout...'
	if [[ -f $main_js ]]; then
		node -e "
const fs = require('fs');
let code = fs.readFileSync('$main_js', 'utf8');
const oldCode = 'async handleCommandLineArgs(r){let s=St.app.isPackaged?1:2;if(r.length>s){let a=r[s];if(ti(a,{isExternalOpen:!0}))return!0;if(aFe.default.statSync(a,{throwIfNoEntry:!1}))return await YP(a)}return!1}';
const newCode = 'async handleCommandLineArgs(r){for(let s=1;s<r.length;s++){let a=r[s];if(a.startsWith(\"-\")||a.endsWith(\".asar\")||a.endsWith(\".js\"))continue;if(ti(a,{isExternalOpen:!0}))return!0;if(aFe.default.statSync(a,{throwIfNoEntry:!1}))return await YP(a)}return!1}';
if (code.includes(oldCode)) {
  code = code.replace(oldCode, newCode);
  fs.writeFileSync('$main_js', code);
  console.log('handleCommandLineArgs patched for Linux argv');
} else {
  console.error('Warning: handleCommandLineArgs pattern not found - Figma may have updated');
  console.error('Auth redirect from browser may not work');
  process.exit(1);
}
"
	fi

	# ---- Patch platform detection ----
	# Figma checks process.platform==="win32" for many features.
	# We do NOT want to pretend to be Windows. Instead, we let it see "linux"
	# and handle the cases where it explicitly blocks Linux.
	echo 'Patching auto-updater to not block Linux...'
	if [[ -f $main_js ]]; then
		# The updater has: process.platform==="linux"&&(n="linux")
		# which sets n to a string, disabling the updater. We want to keep this behavior
		# (no auto-update on Linux is fine) - so we don't need to patch it.
		echo 'Auto-updater Linux check preserved (updates disabled on Linux - expected)'
	fi

	# ---- Patch tray context menu for Linux ----
	# On Linux with libappindicator (GNOME, KDE), Electron's 'right-click' event
	# on Tray does NOT fire. Figma uses popUpContextMenu() inside a right-click
	# handler, which never triggers. Fix: add setContextMenu() right after tray
	# creation so appindicator can show the menu natively.
	echo 'Patching tray context menu for Linux...'
	if [[ -f $main_js ]]; then
		node -e "
const fs = require('fs');
let code = fs.readFileSync('$main_js', 'utf8');

// Find the tray init pattern and add setContextMenu after setToolTip
const oldTray = 'this.electronTray.setToolTip(ne.name),this.electronTray.on(\"right-click\",()=>{var r;(r=this.electronTray)==null||r.popUpContextMenu(qSt())})';
const newTray = 'this.electronTray.setToolTip(ne.name),this.electronTray.setContextMenu(qSt()),this.electronTray.on(\"right-click\",()=>{var r;(r=this.electronTray)==null||r.popUpContextMenu(qSt())})';

if (code.includes(oldTray)) {
  code = code.replace(oldTray, newTray);
  fs.writeFileSync('$main_js', code);
  console.log('Tray context menu patched: added setContextMenu(qSt()) for Linux');
} else {
  console.error('Warning: Tray context menu pattern not found - Figma may have updated');
  console.error('Right-click on tray icon may not show context menu on Linux');
}
"
	fi

	# ---- Patch tray window: DevTools debug support ----
	# When FIGMA_DEBUG=1 is set, open DevTools for the tray notification window.
	# We inject this directly into main.js because the BrowserWindow monkey-patch
	# in frame-fix-wrapper.js may not intercept utility/tray window creation.
	echo 'Patching tray window for debug DevTools support...'
	if [[ -f $main_js ]]; then
		node -e "
const fs = require('fs');
let code = fs.readFileSync('$main_js', 'utf8');

const oldPattern = 't.setAlwaysOnTop(!0,\"pop-up-menu\"),t.webContents.on(\"will-navigate\"';
const newPattern = 't.setAlwaysOnTop(!0,\"pop-up-menu\"),process.env.FIGMA_DEBUG===\"1\"&&t.webContents.on(\"dom-ready\",()=>{t.webContents.openDevTools({mode:\"detach\"})}),t.webContents.on(\"will-navigate\"';

if (code.includes(oldPattern)) {
  code = code.replace(oldPattern, newPattern);
  fs.writeFileSync('$main_js', code);
  console.log('Tray DevTools debug patch applied');
} else {
  console.error('Warning: Tray DevTools pattern not found');
}
"
	fi

	cd "$project_root" || exit 1
	echo 'Patching complete'
	section_footer 'Patching app.asar'
}

finalize_app_asar() {
	section_header 'Finalizing app.asar'

	cd "$app_staging_dir" || exit 1

	echo 'Repacking app.asar...'
	"$asar_exec" pack app.asar.contents app.asar || exit 1
	echo 'app.asar repacked'

	# Ensure unpacked directory has our stubs
	mkdir -p "$app_staging_dir/app.asar.unpacked" || exit 1

	# Copy the cursor dropper assets if they exist in unpacked
	if [[ -d "$figma_extract_dir/lib/net45/resources/app.asar.unpacked/assets" ]]; then
		mkdir -p "$app_staging_dir/app.asar.unpacked/assets" || exit 1
		cp -r "$figma_extract_dir/lib/net45/resources/app.asar.unpacked/assets/"* \
			"$app_staging_dir/app.asar.unpacked/assets/" 2>/dev/null || true
	fi

	cd "$project_root" || exit 1
	section_footer 'Finalizing app.asar'
}

#===============================================================================
# Staging Functions
#===============================================================================

stage_electron() {
	section_header 'Staging Electron'

	echo 'Copying chosen Electron installation to staging area...'
	mkdir -p "$app_staging_dir/node_modules/" || exit 1
	local electron_dir_name
	electron_dir_name=$(basename "$chosen_electron_module_path")
	echo "Copying from $chosen_electron_module_path to $app_staging_dir/node_modules/"
	cp -a "$chosen_electron_module_path" "$app_staging_dir/node_modules/" || exit 1

	local staged_electron_bin="$app_staging_dir/node_modules/$electron_dir_name/dist/electron"
	if [[ -f $staged_electron_bin ]]; then
		echo "Setting executable permission on staged Electron binary: $staged_electron_bin"
		chmod +x "$staged_electron_bin" || exit 1
	else
		echo "Warning: Staged Electron binary not found at expected path: $staged_electron_bin"
	fi

	# Copy Electron resources (locale files etc.)
	local electron_resources_src="$chosen_electron_module_path/dist/resources"
	electron_resources_dest="$app_staging_dir/node_modules/$electron_dir_name/dist/resources"
	if [[ -d $electron_resources_src ]]; then
		echo 'Copying Electron locale resources...'
		mkdir -p "$electron_resources_dest" || exit 1
		cp -a "$electron_resources_src"/* "$electron_resources_dest/" || exit 1
		echo 'Electron locale resources copied'
	else
		echo "Warning: Electron resources directory not found at $electron_resources_src"
	fi

	section_footer 'Staging Electron'
}

process_icons() {
	section_header 'Icon Processing'

	cd "$work_dir" || exit 1

	# Find ImageMagick command
	local magick_cmd=''
	command -v magick &> /dev/null && magick_cmd='magick'
	[[ -z $magick_cmd ]] && command -v convert &> /dev/null && magick_cmd='convert'

	# Extract icon from the .ico file included in the installer
	# Use ImageMagick because icotool fails on Figma's non-standard .ico format
	local ico_path="$figma_extract_dir/setupIcon.ico"
	if [[ -f $ico_path && -n $magick_cmd ]]; then
		echo "Extracting icons from setupIcon.ico using $magick_cmd..."
		if $magick_cmd "$ico_path" figma_icon.png 2>/dev/null; then
			echo "Icons extracted to $work_dir"
		else
			echo 'Warning: Failed to convert setupIcon.ico'
		fi
	elif [[ -f $ico_path ]]; then
		echo 'Trying icotool for icon extraction...'
		cp "$ico_path" figma.ico || true
		icotool -x figma.ico 2>/dev/null || echo 'Warning: icotool also failed on this .ico'
	else
		echo 'setupIcon.ico not found, trying to extract from Figma.exe...'
		local exe_path="$figma_extract_dir/lib/net45/Figma.exe"
		if [[ -f $exe_path ]]; then
			if command -v wrestool &> /dev/null; then
				if wrestool -x -t 14 "$exe_path" -o figma.ico 2>/dev/null; then
					if [[ -n $magick_cmd ]]; then
						$magick_cmd figma.ico figma_icon.png 2>/dev/null || true
					else
						icotool -x figma.ico 2>/dev/null || true
					fi
				else
					echo 'Warning: could not extract icons from Figma.exe'
				fi
			fi
		fi
	fi

	# Process tray icons from the app.asar
	echo 'Processing tray icon files for Linux...'
	local tray_src="$app_staging_dir/app.asar.contents/assets/tray"
	if [[ -d $tray_src ]]; then
		echo 'Copying tray icons to Electron resources...'
		cp "$tray_src/"*.png "$electron_resources_dest/" 2>/dev/null || \
			echo 'Warning: No tray icon files found'

		# Find ImageMagick command
		local magick_cmd=''
		command -v magick &> /dev/null && magick_cmd='magick'
		[[ -z $magick_cmd ]] && command -v convert &> /dev/null && magick_cmd='convert'

		if [[ -n $magick_cmd ]]; then
			echo "Processing tray icons for Linux visibility (using $magick_cmd)..."
			local icon_file icon_name
			for icon_file in "$electron_resources_dest"/icon*.png; do
				[[ ! -f $icon_file ]] && continue
				icon_name=$(basename "$icon_file")
				if "$magick_cmd" "$icon_file" -channel A -fx 'a>0?1:0' +channel \
					"PNG32:$icon_file" 2>/dev/null; then
					echo "  Processed $icon_name (100% opaque)"
				else
					echo "  Failed to process $icon_name"
				fi
			done
			echo 'Tray icon files copied and processed'
		else
			echo 'Warning: ImageMagick not found - tray icons may appear invisible'
		fi
	fi

	cd "$project_root" || exit 1
	section_footer 'Icon Processing'
}

copy_locale_files() {
	echo 'Copying Figma locale JSON files to Electron resources directory...'
	local i18n_src="$app_staging_dir/app.asar.contents/i18n"
	if [[ -d $i18n_src ]]; then
		mkdir -p "$electron_resources_dest/i18n" || exit 1
		cp "$i18n_src/"*.json "$electron_resources_dest/i18n/" || exit 1
		echo 'Figma locale JSON files copied'
	else
		echo "Warning: Figma i18n directory not found"
	fi

	echo "app.asar processed and staged in $app_staging_dir"
}

#===============================================================================
# Packaging Functions
#===============================================================================

run_packaging() {
	section_header 'Call Packaging Script'

	local output_path=''
	local script_name file_pattern pkg_file

	case "$build_format" in
		deb)
			script_name='build-deb-package.sh'
			file_pattern="${PACKAGE_NAME}_${version}_${architecture}.deb"
			;;
		rpm)
			script_name='build-rpm-package.sh'
			file_pattern="${PACKAGE_NAME}-${version}*.rpm"
			;;
		appimage)
			script_name='build-appimage.sh'
			file_pattern="${PACKAGE_NAME}-${version}-${architecture}.AppImage"
			;;
	esac

	if [[ $build_format == 'deb' || $build_format == 'rpm' ]]; then
		echo "Calling ${build_format^^} packaging script for $architecture..."
		chmod +x "scripts/$script_name" || exit 1
		if ! "scripts/$script_name" \
			"$version" "$architecture" "$work_dir" "$app_staging_dir" \
			"$PACKAGE_NAME" "$MAINTAINER" "$DESCRIPTION"; then
			echo "${build_format^^} packaging script failed." >&2
			exit 1
		fi

		pkg_file=$(find "$work_dir" -maxdepth 1 -name "$file_pattern" | head -n 1)
		echo "${build_format^^} Build complete!"
		if [[ -n $pkg_file && -f $pkg_file ]]; then
			output_path="./$(basename "$pkg_file")"
			mv "$pkg_file" "$output_path" || exit 1
			echo "Package created at: $output_path"
		else
			echo "Warning: Could not determine final .${build_format} file path."
			output_path='Not Found'
		fi

	elif [[ $build_format == 'appimage' ]]; then
		echo "Calling AppImage packaging script for $architecture..."
		chmod +x scripts/build-appimage.sh || exit 1
		if ! scripts/build-appimage.sh \
			"$version" "$architecture" "$work_dir" "$app_staging_dir" "$PACKAGE_NAME"; then
			echo 'AppImage packaging script failed.' >&2
			exit 1
		fi

		local appimage_file
		appimage_file=$(find "$work_dir" -maxdepth 1 -name "${PACKAGE_NAME}-${version}-${architecture}.AppImage" | head -n 1)
		echo 'AppImage Build complete!'
		if [[ -n $appimage_file && -f $appimage_file ]]; then
			output_path="./$(basename "$appimage_file")"
			mv "$appimage_file" "$output_path" || exit 1
			echo "Package created at: $output_path"
		else
			echo 'Warning: Could not determine final .AppImage file path.'
			output_path='Not Found'
		fi
	fi

	# Store for print_next_steps
	final_output_path="$output_path"
}

cleanup_build() {
	section_header 'Cleanup'
	if [[ $perform_cleanup != true ]]; then
		echo "Skipping cleanup of intermediate build files in $work_dir."
		return
	fi

	echo "Cleaning up intermediate build files in $work_dir..."
	if rm -rf "$work_dir"; then
		echo "Cleanup complete ($work_dir removed)."
	else
		echo 'Cleanup command failed.'
	fi
}

print_next_steps() {
	echo -e '\n\033[1;34m====== Next Steps ======\033[0m'

	case "$build_format" in
		deb|rpm)
			if [[ $final_output_path != 'Not Found' && -e $final_output_path ]]; then
				local pkg_type install_cmd alt_cmd
				if [[ $build_format == 'deb' ]]; then
					pkg_type='Debian'
					install_cmd="sudo apt install $final_output_path"
					alt_cmd="sudo dpkg -i $final_output_path"
				else
					pkg_type='RPM'
					install_cmd="sudo dnf install $final_output_path"
					alt_cmd="sudo rpm -i $final_output_path"
				fi
				echo -e "To install the $pkg_type package, run:"
				echo -e "   \033[1;32m$install_cmd\033[0m"
				echo -e "   (or \`$alt_cmd\`)"
			else
				echo -e "${build_format^^} package file not found. Cannot provide installation instructions."
			fi
			;;
		appimage)
			if [[ $final_output_path != 'Not Found' && -e $final_output_path ]]; then
				echo -e "AppImage created at: \033[1;36m$final_output_path\033[0m"
				echo -e "\nTo run:"
				echo -e "   \033[1;32mchmod +x $final_output_path && $final_output_path\033[0m"
			else
				echo -e 'AppImage file not found. Cannot provide usage instructions.'
			fi
			;;
	esac

	echo -e '\033[1;34m======================\033[0m'
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
	# Phase 1: Setup
	detect_architecture
	detect_distro
	check_system_requirements
	parse_arguments "$@"

	check_dependencies
	setup_work_directory
	setup_nodejs
	setup_electron_asar

	# Phase 2: Download and extract
	resolve_figma_version
	download_figma_installer

	# Phase 3: Patch and prepare
	extract_app_asar
	patch_app_asar
	finalize_app_asar
	stage_electron
	process_icons
	copy_locale_files

	cd "$project_root" || exit 1

	# Phase 4: Package
	run_packaging

	# Phase 5: Cleanup and finish
	cleanup_build

	echo 'Build process finished.'
	print_next_steps
}

# Run main with all script arguments
main "$@"

exit 0
