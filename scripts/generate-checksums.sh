#!/usr/bin/env bash
set -euo pipefail

# Generate SHA256 checksums for release artifacts
# Usage: ./generate-checksums.sh <directory>

DIR="${1:-.}"

if [[ ! -d "$DIR" ]]; then
    echo "Error: Directory not found: $DIR"
    exit 1
fi

cd "$DIR"

ARTIFACTS=$(find . -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.zip" \) | sort)

if [[ -z "$ARTIFACTS" ]]; then
    echo "No artifacts found in $DIR"
    exit 1
fi

echo "Generating SHA256 checksums..."
sha256sum $ARTIFACTS | tee sha256sums.txt

echo ""
echo "Checksums written to: ${DIR}/sha256sums.txt"
