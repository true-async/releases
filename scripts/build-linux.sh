#!/usr/bin/env bash
set -euo pipefail

# TrueAsync PHP — Linux build script
# Usage: ./build-linux.sh [--config path/to/build-config.json] [--prefix /opt/php-trueasync]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../build-config.json"
PREFIX="/opt/php-trueasync"
BUILD_DIR=""
JOBS="$(nproc)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --config)  CONFIG_FILE="$2"; shift 2 ;;
        --prefix)  PREFIX="$2"; shift 2 ;;
        --jobs)    JOBS="$2"; shift 2 ;;
        --src-dir) BUILD_DIR="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

echo "=== TrueAsync PHP Linux Build ==="
echo "Config:  $CONFIG_FILE"
echo "Prefix:  $PREFIX"
echo "Jobs:    $JOBS"

# Read config
PHP_SRC_REPO=$(jq -r '.php_src.repo' "$CONFIG_FILE")
PHP_SRC_BRANCH=$(jq -r '.php_src.branch' "$CONFIG_FILE")

COMMON_FLAGS=$(jq -r '.configure.common | join(" ")' "$CONFIG_FILE")
LINUX_FLAGS=$(jq -r '.configure.linux | join(" ")' "$CONFIG_FILE")

# Clone sources if no build dir specified
if [[ -z "$BUILD_DIR" ]]; then
    BUILD_DIR="$(mktemp -d)"
    echo "=== Cloning php-src ==="
    git clone --depth=1 --branch "$PHP_SRC_BRANCH" "https://github.com/${PHP_SRC_REPO}.git" "$BUILD_DIR"

    # Clone extensions
    jq -r '.extensions | to_entries[] | "\(.value.repo) \(.value.branch) \(.value.path)"' "$CONFIG_FILE" | \
    while read -r repo branch path; do
        echo "=== Cloning $repo ($branch) ==="
        git clone --depth=1 --branch "$branch" "https://github.com/${repo}.git" "${BUILD_DIR}/${path}"
    done
fi

echo "=== Installing dependencies ==="
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    autoconf automake bison re2c pkg-config \
    gcc g++ make wget \
    libxml2-dev libsqlite3-dev \
    libssl-dev libzip-dev zlib1g-dev \
    libpq-dev libonig-dev libsodium-dev \
    libreadline-dev libbz2-dev \
    libuv1-dev libpsl-dev

# Verify libuv
LIBUV_VER=$(pkg-config --modversion libuv 2>/dev/null || echo "unknown")
MIN_VER=$(jq -r '.requirements.libuv_min_version' "$CONFIG_FILE")
echo "libuv: $LIBUV_VER (required >= $MIN_VER)"

# Build libcurl 8.12.0 from source (need >= 8.11.1 for fully async file uploads)
CURL_VERSION="8.12.0"
echo "=== Building libcurl ${CURL_VERSION} ==="
CURL_TAG="curl-$(echo "$CURL_VERSION" | tr '.' '_')"
wget -q "https://github.com/curl/curl/releases/download/${CURL_TAG}/curl-${CURL_VERSION}.tar.gz" -O "/tmp/curl-${CURL_VERSION}.tar.gz"
tar -xf "/tmp/curl-${CURL_VERSION}.tar.gz" -C /tmp
cd "/tmp/curl-${CURL_VERSION}"
./configure --prefix=/usr/local --with-openssl --enable-shared --disable-static
make -j"$JOBS"
sudo make install
sudo ldconfig
cd "$BUILD_DIR"

echo "=== Building PHP ==="
cd "$BUILD_DIR"
./buildconf --force
./configure \
    --prefix="$PREFIX" \
    $COMMON_FLAGS \
    $LINUX_FLAGS

make -j"$JOBS"

echo "=== Installing ==="
STAGING="$(mktemp -d)"
make install INSTALL_ROOT="$STAGING"

echo "=== Verifying ==="
"${STAGING}${PREFIX}/bin/php" -v
"${STAGING}${PREFIX}/bin/php" -m

echo "=== Build complete ==="
echo "Installed to: ${STAGING}${PREFIX}"
echo "Staging dir:  ${STAGING}"
