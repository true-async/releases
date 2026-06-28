#!/usr/bin/env bash
# Extracts PHP static libs and headers from build artifacts into the Android project.
# Run once before building the APK.
#
# Usage:
#   ./prepare.sh                          # uses ../../out/android/ (local build)
#   ./prepare.sh --arm64 file.zip         # explicit arm64-v8a zip
#   ./prepare.sh --x64   file.zip         # explicit x86_64 zip

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_OUT="${SCRIPT_DIR}/../../out/android"

ARM64_ZIP=""
X64_ZIP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --arm64) ARM64_ZIP="$2"; shift 2 ;;
        --x64)   X64_ZIP="$2";   shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

ARM64_ZIP="${ARM64_ZIP:-${LOCAL_OUT}/trueasync-php-android-arm64-v8a.zip}"
X64_ZIP="${X64_ZIP:-${LOCAL_OUT}/trueasync-php-android-x86_64.zip}"

JNI_DIR="${SCRIPT_DIR}/app/src/main/jniLibs"
INC_DIR="${SCRIPT_DIR}/app/src/main/cpp/include"

mkdir -p "${JNI_DIR}/arm64-v8a" "${JNI_DIR}/x86_64" "${INC_DIR}"

extract_zip() {
    local zip="$1" abi="$2"
    echo "--- Extracting ${abi} from $(basename "$zip") ---"
    local tmp; tmp="$(mktemp -d)"
    unzip -q -o "$zip" -d "$tmp"
    cp "${tmp}/staticLibs/${abi}/"*.a "${JNI_DIR}/${abi}/"
    # Headers only need to be extracted once (same for both ABIs)
    if [[ ! -f "${INC_DIR}/php/main/php.h" ]]; then
        cp -r "${tmp}/include/php" "${INC_DIR}/"
    fi
    rm -rf "$tmp"
    echo "    libs → jniLibs/${abi}/"
}

[[ -f "$ARM64_ZIP" ]] && extract_zip "$ARM64_ZIP" "arm64-v8a" || echo "WARN: arm64-v8a zip not found: $ARM64_ZIP"
[[ -f "$X64_ZIP"   ]] && extract_zip "$X64_ZIP"   "x86_64"    || echo "WARN: x86_64 zip not found: $X64_ZIP"

echo "Done. Now run: gradle assembleDebug"
