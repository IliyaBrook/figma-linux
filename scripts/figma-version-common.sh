#!/usr/bin/env bash
# Shared version discovery for the builder and the version diagnostic tool.

figma_version_from_nupkg() {
	if [[ $1 =~ ^Figma-([0-9]+\.[0-9]+\.[0-9]+)-full\.nupkg$ ]]; then
		printf '%s\n' "${BASH_REMATCH[1]}"
	else
		echo "Invalid Figma package name: $1" >&2
		return 1
	fi
}

figma_fetch_manifest_version() {
	local data _digest name _remainder found=''
	data=$(curl --fail --silent --show-error --location --connect-timeout 15 \
		--max-time 60 --retry 2 -H 'User-Agent: Figma/1 (Windows; x64)' "$1") || return 1
	while read -r _digest name _remainder; do
		if [[ $name =~ ^Figma-([0-9]+\.[0-9]+\.[0-9]+)-full\.nupkg$ ]]; then
			if [[ -n $found && $found != "${BASH_REMATCH[1]}" ]]; then
				echo 'Ambiguous Figma RELEASES manifest: multiple full versions' >&2
				return 1
			fi
			found=${BASH_REMATCH[1]}
		fi
	done <<< "$data"
	if [[ -z $found ]]; then
		echo 'No valid full Figma package in RELEASES manifest' >&2
		return 1
	fi
	printf '%s\n' "$found"
}

figma_installer_nupkg() {
	local listing line name found=''
	listing=$(LC_ALL=C 7z l -slt -ba -- "$1") || return 1
	while IFS= read -r line; do
		name=${line#Path = }
		if [[ $line == 'Path = '* && $name =~ ^Figma-([0-9]+\.[0-9]+\.[0-9]+)-full\.nupkg$ ]]; then
			if [[ -n $found ]]; then
				echo 'Ambiguous Figma installer: multiple full packages' >&2
				return 1
			fi
			found=$name
		fi
	done <<< "$listing"
	if [[ -z $found ]]; then
		echo 'No valid full Figma package in installer' >&2
		return 1
	fi
	printf '%s\n' "$found"
}

figma_download_installer() {
	local url=$1 destination=$2
	# A failed transfer must never look like a complete cached installer.
	if ! curl --fail --silent --show-error --location --connect-timeout 15 \
		--max-time 600 --retry 2 --output "$destination.part" "$url"; then
		rm -f -- "$destination.part"
		return 1
	fi
	mv -- "$destination.part" "$destination"
}
