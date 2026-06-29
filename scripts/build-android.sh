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

# Install system dependencies early — jq is needed to parse config
if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq 2>/dev/null || apt-get update -qq
    sudo apt-get install -y --no-install-recommends \
        autoconf automake libtool make bison re2c pkg-config \
        wget curl unzip zip xz-utils cmake ninja-build \
        jq git ca-certificates python3 2>/dev/null || \
    apt-get install -y --no-install-recommends \
        autoconf automake libtool make bison re2c pkg-config \
        wget curl unzip zip xz-utils cmake ninja-build \
        jq git ca-certificates python3
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

    NDK_MARKER="${NDK_CACHE}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
    if [[ ! -f "$NDK_MARKER" ]]; then
        echo "=== Downloading NDK $NDK_VERSION ==="
        NDK_ZIP="/tmp/android-ndk.zip"
        NDK_URL="https://dl.google.com/android/repository/android-ndk-r${NDK_VERSION%%.*}-linux.zip"
        wget -q --show-progress "$NDK_URL" -O "$NDK_ZIP"
        echo "=== Extracting NDK ==="
        unzip -q "$NDK_ZIP" -d /tmp/ndk-extract
        # NDK extracts as android-ndk-r27/ inside the zip
        cp -a /tmp/ndk-extract/android-ndk-r${NDK_VERSION%%.*}/. "$NDK_CACHE/"
        rm -rf /tmp/ndk-extract "$NDK_ZIP"
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

export PATH="${TOOLCHAIN}/bin:${PATH}"

export CC="${TOOLCHAIN}/bin/${API_TRIPLE}-clang"
export CXX="${TOOLCHAIN}/bin/${API_TRIPLE}-clang++"
export AR="${TOOLCHAIN}/bin/llvm-ar"
export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
export STRIP="${TOOLCHAIN}/bin/llvm-strip"
export NM="${TOOLCHAIN}/bin/llvm-nm"
export LD="${TOOLCHAIN}/bin/ld"

DEPS_PREFIX="/tmp/trueasync-android-deps-${ABI}"
mkdir -p "$DEPS_PREFIX"

# aarch64-linux-android29-clang already defines __ANDROID_API__ — don't redefine it
export CFLAGS="-fPIC -femulated-tls --sysroot=${SYSROOT} -I${DEPS_PREFIX}/include"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="--sysroot=${SYSROOT} -L${DEPS_PREFIX}/lib"

# Replace default pkg-config search paths so only cross-compiled .pc files are found.
# Do NOT set PKG_CONFIG_SYSROOT_DIR — it would prepend sysroot to all .pc paths,
# breaking deps installed outside the sysroot (i.e. in DEPS_PREFIX).
export PKG_CONFIG_LIBDIR="${DEPS_PREFIX}/lib/pkgconfig:${DEPS_PREFIX}/lib64/pkgconfig:${DEPS_PREFIX}/share/pkgconfig"

# ------------------------------------------------------------------ #
# Dependencies                                                        #
# ------------------------------------------------------------------ #

echo "=== Build tools ready ==="

build_libiconv() {
    local VERSION="1.17"
    [[ -f "${DEPS_PREFIX}/lib/libiconv.a" ]] && return
    echo "--- libiconv ${VERSION} ---"
    wget -q "https://ftpmirror.gnu.org/gnu/libiconv/libiconv-${VERSION}.tar.gz" -O /tmp/libiconv.tar.gz \
        || wget -q "https://ftp.gnu.org/gnu/libiconv/libiconv-${VERSION}.tar.gz" -O /tmp/libiconv.tar.gz
    tar -xf /tmp/libiconv.tar.gz -C /tmp
    cd "/tmp/libiconv-${VERSION}"
    ./configure \
        --host="$TRIPLE" \
        --prefix="$DEPS_PREFIX" \
        --enable-static --disable-shared \
        --disable-nls
    make -j"$JOBS" && make install
    cd -
}

build_oniguruma() {
    local VERSION="6.9.9"
    [[ -f "${DEPS_PREFIX}/lib/libonig.a" ]] && return
    echo "--- oniguruma ${VERSION} ---"
    wget -q "https://github.com/kkos/oniguruma/releases/download/v${VERSION}/onig-${VERSION}.tar.gz" -O /tmp/onig.tar.gz
    tar -xf /tmp/onig.tar.gz -C /tmp
    cd "/tmp/onig-${VERSION}"
    ./configure \
        --host="$TRIPLE" \
        --prefix="$DEPS_PREFIX" \
        --enable-static --disable-shared
    make -j"$JOBS" && make install
    cd -
}

build_zlib() {
    local VERSION="1.3.1"
    [[ -f "${DEPS_PREFIX}/lib/libz.a" ]] && return
    echo "--- zlib ${VERSION} ---"
    wget -q "https://github.com/madler/zlib/releases/download/v${VERSION}/zlib-${VERSION}.tar.gz" -O /tmp/zlib.tar.gz
    tar -xf /tmp/zlib.tar.gz -C /tmp
    cd "/tmp/zlib-${VERSION}"
    CHOST="$TRIPLE" ./configure --prefix="$DEPS_PREFIX" --static
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
        -DLIBUV_BUILD_TESTS=OFF \
        -DLIBUV_BUILD_BENCHMARKS=OFF \
        -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
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

build_oniguruma
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

# Patch Android-incompatible POSIX calls before buildconf
# getdtablesize() is not in Android Bionic — use sysconf(_SC_OPEN_MAX) instead
sed -i 's/dtablesize = getdtablesize();/dtablesize = (int)sysconf(_SC_OPEN_MAX);/' \
    ext/standard/php_fopen_wrapper.c

# Android: TSRM uses IE TLS in two places that break dlopen in Bionic:
# 1. TSRM/TSRM.h: __PIC__ branch sets TSRM_TLS_MODEL_ATTR=initial-exec + defines TSRM_TLS_MODEL_INITIAL_EXEC.
#    Fix: inject __ANDROID__ into the first condition so the safe DEFAULT branch is taken.
# 2. TSRM/TSRM.c: x86_64 and i386 inline-asm blocks hardcode @gottpoff/@ntpoff regardless of the macro.
#    Fix: add !defined(__ANDROID__) to their #elif conditions so those blocks are skipped on Android.
# Result: tsrm_get_offset() returns 0 on Android (JIT fast-path disabled, PHP still works),
# and _tsrm_ls_cache is plain __thread, converted to emulated TLS by -femulated-tls.
sed -i \
    's/#if !__has_attribute(tls_model) || defined(__FreeBSD__)/#if !__has_attribute(tls_model) || defined(__ANDROID__) || defined(__FreeBSD__)/' \
    TSRM/TSRM.h
sed -i \
    's/!defined(__HAIKU__) && !defined(__CYGWIN__)$/\!defined(__HAIKU__) \&\& !defined(__CYGWIN__) \&\& !defined(__ANDROID__)/' \
    TSRM/TSRM.c

./buildconf --force

INSTALL_PREFIX="${OUTPUT_DIR}/php-${ABI}"

# Merge our static overrides with any previously cached values
CACHE_TMP="$(mktemp /tmp/android-php-cache.XXXXXX)"
cat "${SCRIPT_DIR}/android-cross.cache" > "$CACHE_TMP"

./configure \
    --host="$TRIPLE" \
    --prefix="$INSTALL_PREFIX" \
    --cache-file="$CACHE_TMP" \
    --with-libxml="${DEPS_PREFIX}" \
    --with-openssl="${DEPS_PREFIX}" \
    --with-sqlite3="${DEPS_PREFIX}" \
    --with-pdo-sqlite="${DEPS_PREFIX}" \
    --with-curl="${DEPS_PREFIX}" \
    --with-zlib \
    $COMMON_FLAGS \
    $ANDROID_FLAGS

# Patch config.h after configure: disable resolver functions that exist as
# private __res_* symbols in Android Bionic but lack the required resolv.h types.
echo "=== Patching config headers for Android DNS ==="
CONFIG_HEADERS=$(find . -maxdepth 3 -name "*.h" | xargs grep -l "HAVE_RES_NSEARCH" 2>/dev/null || true)
echo "Found in: ${CONFIG_HEADERS:-none}"
for cfg in $CONFIG_HEADERS; do
    for sym in HAVE_RES_NSEARCH HAVE___RES_NSEARCH \
               HAVE_RES_NDESTROY HAVE___RES_NDESTROY \
               HAVE_RES_SEARCH HAVE___RES_SEARCH \
               HAVE_RES_INIT HAVE___RES_INIT \
               HAVE_DN_SKIPNAME HAVE___DN_SKIPNAME \
               HAVE_DN_EXPAND HAVE___DN_EXPAND \
               HAVE_GETDTABLESIZE; do
        sed -i "s/^#define ${sym} 1$/\/* Android: ${sym} disabled *\//" "$cfg"
    done
    echo "Patched: $cfg"
done


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
