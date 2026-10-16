#!/usr/bin/env bash
# Pinned AppImage tooling shared by packaging and CI smoke tests.

select_appimage_architecture() {
	case "$1" in
		amd64)
			tool_arch='x86_64'
			appimagetool_sha256='ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0'
			runtime_sha256='2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d'
			;;
		arm64)
			tool_arch='aarch64'
			appimagetool_sha256='f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158'
			runtime_sha256='00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444'
			;;
		*)
			echo "Unsupported architecture for appimagetool: $1" >&2
			exit 1
			;;
	esac
}

download_verified() {
	local url="$1"
	local output="$2"
	local expected_sha256="$3"

	if [[ -f $output ]] && printf '%s  %s\n' "$expected_sha256" "$output" | sha256sum --check --status; then
		echo "Using verified cached artifact: $output"
		return
	fi

	echo "Downloading $url"
	rm -f "$output"
	if ! wget -q --tries=2 --timeout=30 -O "$output" "$url"; then
		echo "Failed to download $url" >&2
		rm -f "$output"
		exit 1
	fi
	if ! printf '%s  %s\n' "$expected_sha256" "$output" | sha256sum --check --status; then
		echo "Checksum verification failed for $output" >&2
		rm -f "$output"
		exit 1
	fi
}

prepare_appimage_tools() {
	local architecture="$1" work_dir="$2"
	local appimagetool_version='1.9.1' runtime_version='20251108'
	select_appimage_architecture "$architecture" || return 1
	appimagetool_path="$work_dir/appimagetool-${appimagetool_version}-${tool_arch}.AppImage"
	runtime_path="$work_dir/runtime-${runtime_version}-${tool_arch}"
	download_verified \
		"https://github.com/AppImage/appimagetool/releases/download/${appimagetool_version}/appimagetool-${tool_arch}.AppImage" \
		"$appimagetool_path" "$appimagetool_sha256"
	download_verified \
		"https://github.com/AppImage/type2-runtime/releases/download/${runtime_version}/runtime-${tool_arch}" \
		"$runtime_path" "$runtime_sha256"
	chmod +x "$appimagetool_path" || exit 1
}
