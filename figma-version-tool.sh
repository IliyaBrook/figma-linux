#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/figma-version-common.sh
source "$script_dir/scripts/figma-version-common.sh"

releases_url='https://desktop.figma.com/win/RELEASES'
exe_url='https://desktop.figma.com/win/FigmaSetup.exe'
installer_path=''
output_json=false
temp_dir=''
trap '[[ -z $temp_dir ]] || rm -rf -- "$temp_dir"' EXIT

while (( $# )); do
	case "$1" in
		--json) output_json=true; shift ;;
		--exe)
			if [[ $# -lt 2 || -z $2 || $2 == -* ]]; then
				echo 'Usage: figma-version-tool.sh [--json] [--exe /path/to/FigmaSetup.exe]' >&2
				exit 1
			fi
			installer_path=$2
			shift 2
			;;
		-h|--help)
			echo 'Usage: figma-version-tool.sh [--json] [--exe /path/to/FigmaSetup.exe]'
			echo 'Without --exe, downloads and inspects the complete current Windows installer.'
			echo '--exe inspects a local installer without network access.'
			exit 0
			;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
done

manifest_version=''
if [[ -z $installer_path ]]; then
	if ! manifest_version=$(figma_fetch_manifest_version "$releases_url"); then
		echo 'Warning: RELEASES unavailable or invalid; inspecting the installer instead.' >&2
	fi
	temp_dir=$(mktemp -d)
	installer_path="$temp_dir/FigmaSetup.exe"
	echo 'Downloading current Windows installer for version inspection...' >&2
	figma_download_installer "$exe_url" "$installer_path"
fi

nupkg_name=$(figma_installer_nupkg "$installer_path")
installer_version=$(figma_version_from_nupkg "$nupkg_name")
selected_version=$installer_version
if [[ -n $manifest_version && $manifest_version != "$installer_version" ]]; then
	echo "Warning: RELEASES ($manifest_version) and installer ($installer_version) differ; selecting installer version." >&2
fi

if [[ $output_json == true ]]; then
	# Values are either empty or validated numeric versions.
	printf '{"manifest_version":"%s","installer_version":"%s","selected_version":"%s"}\n' \
		"$manifest_version" "$installer_version" "$selected_version"
else
	printf 'manifest_version:  %s\ninstaller_version: %s\nselected_version:  %s\n' \
		"${manifest_version:-unavailable (or local installer)}" "$installer_version" "$selected_version"
	printf '\nnupkg: https://desktop.figma.com/win/build/%s\nexe:   %s\n' "$nupkg_name" "$exe_url"
fi
