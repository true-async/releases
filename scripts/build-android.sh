#!/usr/bin/env bash
set -euo pipefail

# TrueAsync PHP — Android cross-compilation script
# Produces libphp.a + PHP headers for embedding in Android APK
#
# Usage:
#   ./build-android.sh [options]
#
# Options:
#   --ndk-dir DIR      Path to Android NDK (default: auto-download)
#   --api-level N      Android API level (default: from build-config.json)
#   --abi ABI          Target ABI: arm64-v8a or x86_64 (default: arm64-v8a)
#   --output-dir DIR   Output directory for libphp.a + headers zip
#   --config PATH      Path to build-config.json
#   --src-dir DIR      Use existing php-src checkout (skip clone)
#   --jobs N           Parallel make jobs (default: nproc)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../build-config.json"
NDK_DIR=""
ABI="arm64-v8a"
OUTPUT_DIR="${SCRIPT_DIR}/../out/android"
BUILD_DIR=""
JOBS="$(nproc)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --ndk-dir)    NDK_DIR="$2";    shift 2 ;;
        --api-level)  API_LEVEL="$2";  shift 2 ;;
        --abi)        ABI="$2";        shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --config)     CONFIG_FILE="$2"; shift 2 ;;
        --src-dir)    BUILD_DIR="$2";  shift 2 ;;
        --jobs)       JOBS="$2";       shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

API_LEVEL="${API_LEVEL:-$(jq -r '.android.api_level' "$CONFIG_FILE")}"
NDK_VERSION=$(jq -r '.android.ndk_version' "$CONFIG_FILE")
PHP_SRC_REPO=$(jq -r '.php_src.repo' "$CONFIG_FILE")
PHP_SRC_BRANCH=$(jq -r '.php_src.branch' "$CONFIG_FILE")
COMMON_FLAGS=$(jq -r '.configure.common | join(" ")' "$CONFIG_FILE")
ANDROID_FLAGS=$(jq -r '.configure.android | join(" ")' "$CONFIG_FILE")

mkdir -p "$OUTPUT_DIR"

echo "=== TrueAsync PHP Android Build ==="
echo "ABI:       $ABI"
echo "API Level: $API_LEVEL"
echo "NDK:       $NDK_VERSION"
echo "Output:    $OUTPUT_DIR"

# ------------------------------------------------------------------ #
# NDK setup                                                           #
# ------------------------------------------------------------------ #

if [[ -z "$NDK_DIR" ]]; then
    NDK_CACHE="/tmp/android-ndk-r${NDK_VERSION%%.*}"

    if [[ ! -d "$NDK_CACHE" ]]; then
        echo "=== Downloading NDK $NDK_VERSION ==="
        NDK_ZIP="/tmp/android-ndk.zip"
        NDK_URL="https://dl.google.com/android/repository/android-ndk-r${NDK_VERSION%%.*}-linux.zip"
        wget -q "$NDK_URL" -O "$NDK_ZIP"
        unzip -q "$NDK_ZIP" -d /tmp
        mv "/tmp/android-ndk-r${NDK_VERSION%%.*}" "$NDK_CACHE"
        rm -f "$NDK_ZIP"
    fi

    NDK_DIR="$NDK_CACHE"
fi

echo "NDK dir: $NDK_DIR"

# Toolchain variables
case "$ABI" in
    arm64-v8a) TRIPLE="aarch64-linux-android" ;;
    x86_64)    TRIPLE="x86_64-linux-android"  ;;
    *) echo "Unsupported ABI: $ABI"; exit 1 ;;
esac

TOOLCHAIN="${NDK_DIR}/toolchains/llvm/prebuilt/linux-x86_64"
SYSROOT="${TOOLCHAIN}/sysroot"
API_TRIPLE="${TRIPLE}${API_LEVEL}"

export CC="${TOOLCHAIN}/bin/${API_TRIPLE}-clang"
export CXX="${TOOLCHAIN}/bin/${API_TRIPLE}-clang++"
export AR="${TOOLCHAIN}/bin/llvm-ar"
export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
export STRIP="${TOOLCHAIN}/bin/llvm-strip"
export NM="${TOOLCHAIN}/bin/llvm-nm"
export LD="${TOOLCHAIN}/bin/ld"

export CFLAGS="-fPIC --sysroot=${SYSROOT} -D__ANDROID_API__=${API_LEVEL}"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="--sysroot=${SYSROOT}"

DEPS_PREFIX="/tmp/trueasync-android-deps-${ABI}"
mkdir -p "$DEPS_PREFIX"

export PKG_CONFIG_LIBDIR="${DEPS_PREFIX}/lib/pkgconfig"
export PKG_CONFIG_PATH="${DEPS_PREFIX}/lib/pkgconfig"

# ------------------------------------------------------------------ #
# Dependencies                                                        #
# ------------------------------------------------------------------ #

echo "=== Installing build tools ==="
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    autoconf automake libtool bison re2c pkg-config \
    wget unzip cmake ninja-build jq

build_zlib() {
    local VERSION="1.3.1"
    [[ -f "${DEPS_PREFIX}/lib/libz.a" ]] && return
    echo "--- zlib ${VERSION} ---"
    wget -q "https://zlib.net/zlib-${VERSION}.tar.gz" -O /tmp/zlib.tar.gz
    tar -xf /tmp/zlib.tar.gz -C /tmp
    cd "/tmp/zlib-${VERSION}"
    ./configure --prefix="$DEPS_PREFIX" --static
    make -j"$JOBS" && make install
    cd -
}

build_openssl() {
    local VERSION="3.5.0"
    [[ -f "${DEPS_PREFIX}/lib/libssl.a" ]] && return
    echo "--- OpenSSL ${VERSION} ---"
    wget -q "https://github.com/openssl/openssl/releases/download/openssl-${VERSION}/openssl-${VERSION}.tar.gz" -O /tmp/openssl.tar.gz
    tar -xf /tmp/openssl.tar.gz -C /tmp
    cd "/tmp/openssl-${VERSION}"
    case "$ABI" in
        arm64-v8a) OPENSSL_TARGET="android-arm64" ;;
        x86_64)    OPENSSL_TARGET="android-x86_64" ;;
    esac
    ANDROID_NDK_ROOT="$NDK_DIR" ./Configure \
        "$OPENSSL_TARGET" \
        -D__ANDROID_API__="${API_LEVEL}" \
        --prefix="$DEPS_PREFIX" \
        no-shared no-tests
    make -j"$JOBS" && make install_sw
    cd -
}

build_libxml2() {
    local VERSION="2.13.5"
    [[ -f "${DEPS_PREFIX}/lib/libxml2.a" ]] && return
    echo "--- libxml2 ${VERSION} ---"
    wget -q "https://download.gnome.org/sources/libxml2/2.13/libxml2-${VERSION}.tar.xz" -O /tmp/libxml2.tar.xz
    tar -xf /tmp/libxml2.tar.xz -C /tmp
    cd "/tmp/libxml2-${VERSION}"
    ./configure \
        --host="$TRIPLE" \
        --prefix="$DEPS_PREFIX" \
        --enable-static --disable-shared \
        --without-python --without-lzma \
        --with-zlib="${DEPS_PREFIX}"
    make -j"$JOBS" && make install
    cd -
}

build_sqlite3() {
    local VERSION="3470100"
    [[ -f "${DEPS_PREFIX}/lib/libsqlite3.a" ]] && return
    echo "--- sqlite3 ---"
    wget -q "https://www.sqlite.org/2024/sqlite-autoconf-${VERSION}.tar.gz" -O /tmp/sqlite3.tar.gz
    tar -xf /tmp/sqlite3.tar.gz -C /tmp
    cd "/tmp/sqlite-autoconf-${VERSION}"
    ./configure \
        --host="$TRIPLE" \
        --prefix="$DEPS_PREFIX" \
        --enable-static --disable-shared
    make -j"$JOBS" && make install
    cd -
}

build_libuv() {
    local VERSION=$(jq -r '.requirements.libuv' "$CONFIG_FILE")
    [[ -f "${DEPS_PREFIX}/lib/libuv.a" ]] && return
    echo "--- libuv ${VERSION} ---"
    wget -q "https://github.com/libuv/libuv/archive/refs/tags/v${VERSION}.tar.gz" -O /tmp/libuv.tar.gz
    tar -xf /tmp/libuv.tar.gz -C /tmp
    cd "/tmp/libuv-${VERSION}"
    mkdir -p build && cd build
    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE="${NDK_DIR}/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-${API_LEVEL}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
        -G Ninja
    ninja -j"$JOBS" && ninja install
    cd -
}

build_curl() {
    local VERSION=$(jq -r '.requirements.curl' "$CONFIG_FILE")
    [[ -f "${DEPS_PREFIX}/lib/libcurl.a" ]] && return
    echo "--- curl ${VERSION} ---"
    wget -q "https://github.com/curl/curl/releases/download/curl-$(echo $VERSION | tr '.' '_')/curl-${VERSION}.tar.gz" -O /tmp/curl.tar.gz
    tar -xf /tmp/curl.tar.gz -C /tmp
    cd "/tmp/curl-${VERSION}"
    ./configure \
        --host="$TRIPLE" \
        --prefix="$DEPS_PREFIX" \
        --enable-static --disable-shared \
        --with-openssl="${DEPS_PREFIX}" \
        --without-libpsl \
        --disable-ldap --disable-ldaps \
        --disable-manual
    make -j"$JOBS" && make install
    cd -
}

build_zlib
build_openssl
build_libxml2
build_sqlite3
build_libuv
build_curl

# ------------------------------------------------------------------ #
# PHP sources                                                         #
# ------------------------------------------------------------------ #

if [[ -z "$BUILD_DIR" ]]; then
    BUILD_DIR="$(mktemp -d)"
    echo "=== Cloning php-src ($PHP_SRC_BRANCH) ==="
    git clone --depth=1 --branch "$PHP_SRC_BRANCH" \
        "https://github.com/${PHP_SRC_REPO}.git" "$BUILD_DIR"

    echo "=== Cloning async extension ==="
    ASYNC_REPO=$(jq -r '.extensions.async.repo' "$CONFIG_FILE")
    ASYNC_BRANCH=$(jq -r '.extensions.async.branch' "$CONFIG_FILE")
    ASYNC_PATH=$(jq -r '.extensions.async.path' "$CONFIG_FILE")
    git clone --depth=1 --branch "$ASYNC_BRANCH" \
        "https://github.com/${ASYNC_REPO}.git" "${BUILD_DIR}/${ASYNC_PATH}"
fi

# ------------------------------------------------------------------ #
# Build PHP                                                           #
# ------------------------------------------------------------------ #

echo "=== Building PHP for Android ${ABI} ==="
cd "$BUILD_DIR"
./buildconf --force

INSTALL_PREFIX="${OUTPUT_DIR}/php-${ABI}"

./configure \
    --host="$TRIPLE" \
    --prefix="$INSTALL_PREFIX" \
    --with-libxml="${DEPS_PREFIX}" \
    --with-openssl="${DEPS_PREFIX}" \
    --with-sqlite3="${DEPS_PREFIX}" \
    --with-pdo-sqlite="${DEPS_PREFIX}" \
    --with-curl="${DEPS_PREFIX}" \
    --with-zlib \
    --with-libuv="${DEPS_PREFIX}" \
    $COMMON_FLAGS \
    $ANDROID_FLAGS

make -j"$JOBS"
make install INSTALL_ROOT="${OUTPUT_DIR}/staging-${ABI}"

# ------------------------------------------------------------------ #
# Package output                                                      #
# ------------------------------------------------------------------ #

echo "=== Packaging ==="
STAGING="${OUTPUT_DIR}/staging-${ABI}"
PKG_DIR="${OUTPUT_DIR}/package-${ABI}"
mkdir -p "${PKG_DIR}/staticLibs/${ABI}"
mkdir -p "${PKG_DIR}/include/php"

# Static library
find "$STAGING" -name "libphp.a" -exec cp {} "${PKG_DIR}/staticLibs/${ABI}/" \;

# PHP headers
INCLUDE_SRC="${STAGING}${INSTALL_PREFIX}/include/php"
cp -r "${INCLUDE_SRC}/." "${PKG_DIR}/include/php/"

# Dependency static libs (needed for linking)
for lib in libuv.a libssl.a libcrypto.a libxml2.a libsqlite3.a libcurl.a libz.a; do
    [[ -f "${DEPS_PREFIX}/lib/${lib}" ]] && \
        cp "${DEPS_PREFIX}/lib/${lib}" "${PKG_DIR}/staticLibs/${ABI}/"
done

# Zip
ZIP_NAME="trueasync-php-android-${ABI}.zip"
cd "$PKG_DIR"
zip -r "${OUTPUT_DIR}/${ZIP_NAME}" .
echo "=== Done: ${OUTPUT_DIR}/${ZIP_NAME} ==="
