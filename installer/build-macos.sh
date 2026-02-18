#!/usr/bin/env bash
set -euo pipefail

# TrueAsync PHP — Build from Source for macOS
#
# Interactive:  curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-macos.sh | bash
# Non-interactive: curl -fsSL ... | EXTENSIONS=all NO_INTERACTIVE=true bash
#
# Options (CLI args or environment variables):
#   --prefix DIR         Installation directory       (INSTALL_DIR, default: $HOME/.php-trueasync)
#   --set-default        Add to PATH as default php   (SET_DEFAULT=true, default: false)
#   --debug              Build with debug symbols      (DEBUG_BUILD=true, default: false)
#   --extensions PRESET  Extension preset              (EXTENSIONS: standard|xdebug|all, default: standard)
#   --no-xdebug          Exclude Xdebug               (NO_XDEBUG=true)
#   --jobs N             Parallel make jobs            (BUILD_JOBS, default: sysctl hw.ncpu)
#   --branch NAME        Override php-src branch       (PHP_BRANCH)
#   --no-interactive     Skip interactive wizard       (NO_INTERACTIVE=true or CI=true)
#   --help               Show this help

# ═══════════════════════════════════════════════════════════════════════════════
# Self-relaunch: when piped via curl, save to temp file and re-exec with tty
# ═══════════════════════════════════════════════════════════════════════════════

if [[ -z "${__TRUEASYNC_RELAUNCHED:-}" ]] && ! [[ -t 0 ]]; then
    _tmpscript=$(mktemp)
    cat > "$_tmpscript"
    __TRUEASYNC_RELAUNCHED=1 exec bash "$_tmpscript" "$@" < /dev/tty
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration defaults
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]+${BASH_SOURCE[0]}}")" 2>/dev/null && pwd || echo /tmp)"
CONFIG_FILE="${SCRIPT_DIR}/../build-config.json"

INSTALL_DIR="${INSTALL_DIR:-$HOME/.php-trueasync}"
SET_DEFAULT="${SET_DEFAULT:-false}"
DEBUG_BUILD="${DEBUG_BUILD:-false}"
EXTENSIONS="${EXTENSIONS:-standard}"
NO_XDEBUG="${NO_XDEBUG:-false}"
BUILD_JOBS="${BUILD_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
PHP_BRANCH="${PHP_BRANCH:-}"
NO_INTERACTIVE="${NO_INTERACTIVE:-${CI:-false}}"

CURL_VERSION="8.10.1"

# Detect Homebrew prefix (ARM: /opt/homebrew, Intel: /usr/local)
BREW_PREFIX="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null || echo "/opt/homebrew")}"

# ═══════════════════════════════════════════════════════════════════════════════
# Colors and UI
# ═══════════════════════════════════════════════════════════════════════════════

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' DIM='' NC=''
fi

STEP_CURRENT=0
STEP_TOTAL=0

info()    { echo -e "  ${CYAN}→${NC} $*"; }
success() { echo -e "  ${GREEN}✓${NC} $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $*"; }
error()   { echo -e "  ${RED}✗${NC} $*" >&2; exit 1; }
dimtext() { echo -e "  ${DIM}$*${NC}"; }

step() {
    STEP_CURRENT=$((STEP_CURRENT + 1))
    echo ""
    echo -e "${BOLD}${BLUE}[$STEP_CURRENT/$STEP_TOTAL]${NC} ${BOLD}$*${NC}"
}

spinner() {
    local pid=$1
    local msg="${2:-}"
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${NC} %s" "${chars:i++%${#chars}:1}" "$msg"
        sleep 0.1
    done
    printf "\r"
}

run_with_spinner() {
    local msg="$1"
    shift
    local logfile
    logfile=$(mktemp)

    "$@" > "$logfile" 2>&1 &
    local pid=$!
    spinner "$pid" "$msg"
    if wait "$pid"; then
        success "$msg"
        rm -f "$logfile"
        return 0
    else
        echo ""
        error "$msg — failed! Log:\n$(tail -20 "$logfile")"
    fi
}

show_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║                                                      ║"
    echo "  ║     ⚡ TrueAsync PHP — Build from Source             ║"
    echo "  ║        macOS (Homebrew)                               ║"
    echo "  ║                                                      ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_summary_box() {
    local prefix="$1" debug="$2" extensions="$3" xdebug="$4" set_default="$5" jobs="$6"

    echo ""
    echo -e "  ${BOLD}┌──────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}│${NC}  ${BOLD}Build Configuration Summary${NC}               ${BOLD}│${NC}"
    echo -e "  ${BOLD}├──────────────────────────────────────────────┤${NC}"
    echo -e "  ${BOLD}│${NC}  Install prefix:  ${CYAN}${prefix}${NC}"
    echo -e "  ${BOLD}│${NC}  Debug build:     ${debug}"
    echo -e "  ${BOLD}│${NC}  Extensions:      ${extensions}"
    echo -e "  ${BOLD}│${NC}  Xdebug:          ${xdebug}"
    echo -e "  ${BOLD}│${NC}  Set as default:  ${set_default}"
    echo -e "  ${BOLD}│${NC}  Parallel jobs:   ${jobs}"
    echo -e "  ${BOLD}│${NC}  Homebrew prefix: ${CYAN}${BREW_PREFIX}${NC}"
    echo -e "  ${BOLD}└──────────────────────────────────────────────┘${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# Argument parsing
# ═══════════════════════════════════════════════════════════════════════════════

show_help() {
    echo "TrueAsync PHP — Build from Source (macOS)"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --prefix DIR         Installation directory (default: \$HOME/.php-trueasync)"
    echo "  --set-default        Add to PATH as default php"
    echo "  --debug              Build with debug symbols"
    echo "  --extensions PRESET  Extension preset: standard, xdebug, all (default: standard)"
    echo "  --no-xdebug          Exclude Xdebug from build"
    echo "  --jobs N             Parallel make jobs (default: $(sysctl -n hw.ncpu 2>/dev/null || echo 4))"
    echo "  --branch NAME        Override php-src branch"
    echo "  --no-interactive     Skip interactive wizard"
    echo "  --help               Show this help"
    echo ""
    echo "Environment variables:"
    echo "  INSTALL_DIR, SET_DEFAULT, DEBUG_BUILD, EXTENSIONS,"
    echo "  NO_XDEBUG, BUILD_JOBS, PHP_BRANCH, NO_INTERACTIVE, CI"
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)         INSTALL_DIR="$2"; shift 2 ;;
            --set-default)    SET_DEFAULT="true"; shift ;;
            --debug)          DEBUG_BUILD="true"; shift ;;
            --extensions)     EXTENSIONS="$2"; shift 2 ;;
            --no-xdebug)      NO_XDEBUG="true"; shift ;;
            --jobs)           BUILD_JOBS="$2"; shift 2 ;;
            --branch)         PHP_BRANCH="$2"; shift 2 ;;
            --no-interactive) NO_INTERACTIVE="true"; shift ;;
            --help|-h)        show_help ;;
            *) error "Unknown option: $1. Use --help for usage." ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Interactive wizard
# ═══════════════════════════════════════════════════════════════════════════════

ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local count=${#options[@]}

    echo ""
    echo -e "  ${BOLD}${prompt}${NC}"
    for i in "${!options[@]}"; do
        echo -e "    ${CYAN}$((i + 1))${NC}) ${options[$i]}"
    done

    local default="${ASK_CHOICE_DEFAULT:-}"

    while true; do
        if [[ -n "$default" ]]; then
            printf "  ${BOLD}▸${NC} Your choice [1-%d] (default: %d): " "$count" "$default"
        else
            printf "  ${BOLD}▸${NC} Your choice [1-%d]: " "$count"
        fi
        read -r choice
        [[ -z "$choice" && -n "$default" ]] && choice="$default"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            return $((choice - 1))
        fi
        echo -e "  ${RED}Invalid choice. Please enter 1-${count}${NC}"
    done
}

ask_yesno() {
    local prompt="$1"
    local default="${2:-n}"

    local hint="y/N"
    [[ "$default" == "y" ]] && hint="Y/n"

    printf "  ${BOLD}%s${NC} [%s]: " "$prompt" "$hint"
    read -r answer
    answer="${answer:-$default}"

    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

ask_input() {
    local prompt="$1"
    local default="$2"

    printf "  ${BOLD}%s${NC} [${DIM}%s${NC}]: " "$prompt" "$default"
    read -r answer
    echo "${answer:-$default}"
}

run_wizard() {
    echo -e "  ${MAGENTA}${BOLD}Build Configuration Wizard${NC}"
    echo -e "  ${DIM}Configure your TrueAsync PHP build${NC}"

    # 1. Extensions
    ASK_CHOICE_DEFAULT=2 ask_choice "Which extensions to build?" \
        "Standard — async + core extensions" \
        "Standard + Xdebug — adds debugging support" \
        "All — everything including Xdebug" \
        "Custom — choose manually"
    local ext_choice=$?

    case $ext_choice in
        0) EXTENSIONS="standard"; NO_XDEBUG="true" ;;
        1) EXTENSIONS="standard"; NO_XDEBUG="false" ;;
        2) EXTENSIONS="all"; NO_XDEBUG="false" ;;
        3) EXTENSIONS="all"
           echo ""
           if ask_yesno "Include Xdebug?" "y"; then
               NO_XDEBUG="false"
           else
               NO_XDEBUG="true"
           fi
           ;;
    esac

    # 2. Debug build
    echo ""
    if ask_yesno "Enable debug build? (slower, useful for development)" "n"; then
        DEBUG_BUILD="true"
    else
        DEBUG_BUILD="false"
    fi

    # 3. Install prefix
    echo ""
    INSTALL_DIR=$(ask_input "Installation directory" "$INSTALL_DIR")

    # 4. PATH
    echo ""
    if ask_yesno "Add to PATH as default php?" "n"; then
        SET_DEFAULT="true"
    else
        SET_DEFAULT="false"
    fi

    # Summary
    local debug_label="${RED}No${NC}"
    [[ "$DEBUG_BUILD" == "true" ]] && debug_label="${YELLOW}Yes${NC}"

    local xdebug_label="${DIM}No${NC}"
    [[ "$NO_XDEBUG" != "true" ]] && xdebug_label="${GREEN}Yes${NC}"

    local default_label="${DIM}No${NC}"
    [[ "$SET_DEFAULT" == "true" ]] && default_label="${GREEN}Yes${NC}"

    show_summary_box "$INSTALL_DIR" "$debug_label" "$EXTENSIONS" "$xdebug_label" "$default_label" "$BUILD_JOBS"

    if ! ask_yesno "Proceed with build?" "y"; then
        echo ""
        info "Build cancelled."
        exit 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Config reader
# ═══════════════════════════════════════════════════════════════════════════════

read_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        CONFIG_FILE=$(mktemp)
        local config_url="https://raw.githubusercontent.com/true-async/releases/master/build-config.json"
        curl -fsSL "$config_url" -o "$CONFIG_FILE"
    fi

    if ! command -v jq &>/dev/null; then
        # Minimal JSON parsing without jq (jq might not be installed before brew)
        PHP_SRC_REPO=$(grep -o '"repo"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | head -1 | sed 's/.*"repo"[[:space:]]*:[[:space:]]*"//;s/"//')
        PHP_SRC_BRANCH=$(grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | head -1 | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//;s/"//')
        ASYNC_REPO=$(sed -n '/"async"/,/}/p' "$CONFIG_FILE" | grep '"repo"' | sed 's/.*"repo"[[:space:]]*:[[:space:]]*"//;s/".*//')
        ASYNC_BRANCH=$(sed -n '/"async"/,/}/p' "$CONFIG_FILE" | grep '"branch"' | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//;s/".*//')
        XDEBUG_REPO=$(sed -n '/"xdebug"/,/}/p' "$CONFIG_FILE" | grep '"repo"' | sed 's/.*"repo"[[:space:]]*:[[:space:]]*"//;s/".*//')
        XDEBUG_BRANCH=$(sed -n '/"xdebug"/,/}/p' "$CONFIG_FILE" | grep '"branch"' | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//;s/".*//')
    else
        PHP_SRC_REPO=$(jq -r '.php_src.repo' "$CONFIG_FILE")
        PHP_SRC_BRANCH=$(jq -r '.php_src.branch' "$CONFIG_FILE")
        ASYNC_REPO=$(jq -r '.extensions.async.repo' "$CONFIG_FILE")
        ASYNC_BRANCH=$(jq -r '.extensions.async.branch' "$CONFIG_FILE")
        XDEBUG_REPO=$(jq -r '.extensions.xdebug.repo' "$CONFIG_FILE")
        XDEBUG_BRANCH=$(jq -r '.extensions.xdebug.branch' "$CONFIG_FILE")
    fi

    [[ -n "$PHP_BRANCH" ]] && PHP_SRC_BRANCH="$PHP_BRANCH"
}

# ═══════════════════════════════════════════════════════════════════════════════
# System checks
# ═══════════════════════════════════════════════════════════════════════════════

check_system() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        error "This script is for macOS. Use build-linux.sh for Linux."
    fi

    if ! command -v brew &>/dev/null; then
        error "Homebrew is required. Install from https://brew.sh"
    fi

    # Ensure Xcode command line tools
    if ! xcode-select -p &>/dev/null; then
        info "Installing Xcode Command Line Tools..."
        xcode-select --install
        error "Please re-run this script after Xcode CLT installation completes."
    fi

    info "Homebrew prefix: ${BREW_PREFIX}"
    info "Architecture: $(uname -m)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Build steps
# ═══════════════════════════════════════════════════════════════════════════════

install_dependencies() {
    step "Installing build dependencies via Homebrew"

    local pkgs=(
        autoconf
        automake
        bison
        re2c
        pkg-config
        cmake
        ninja
        git
        jq
        # Libraries
        libuv
        openssl@3
        icu4c
        libxml2
        sqlite
        libzip
        zlib
        oniguruma
        libsodium
        readline
        bzip2
        gmp
        libxslt
        libjpeg-turbo
        libwebp
        freetype
        libpng
        tidy-html5
        openldap
        libffi
        net-snmp
        enchant
        gdbm
        lmdb
        curl
        argon2
        libpq
    )

    info "Installing ${#pkgs[@]} Homebrew packages..."
    run_with_spinner "Installing Homebrew packages" \
        brew install --quiet "${pkgs[@]}"

    # Update BREW_PREFIX after potential Homebrew changes
    BREW_PREFIX="$(brew --prefix)"

    success "All dependencies installed"
}

build_libcurl() {
    step "Checking libcurl version"

    # Check brew curl version
    local brew_curl_ver
    brew_curl_ver=$(brew info --json=v2 curl 2>/dev/null | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"//;s/"//' || echo "0")

    local major
    major=$(echo "$brew_curl_ver" | cut -d. -f1)
    if (( major >= 8 )); then
        success "Homebrew curl ${brew_curl_ver} is sufficient"
        return 0
    fi

    info "Building libcurl ${CURL_VERSION} from source..."

    local build_dir="$1"
    local curl_tag
    curl_tag="curl-$(echo "$CURL_VERSION" | tr '.' '_')"

    curl -fsSL "https://github.com/curl/curl/releases/download/${curl_tag}/curl-${CURL_VERSION}.tar.gz" -o "${build_dir}/curl.tar.gz"
    tar -xf "${build_dir}/curl.tar.gz" -C "$build_dir"

    local curl_dir="${build_dir}/curl-${CURL_VERSION}"

    run_with_spinner "Configuring libcurl" \
        bash -c "cd '${curl_dir}' && ./configure --prefix=/usr/local --with-openssl=$(brew --prefix openssl@3) --enable-shared --disable-static --quiet"
    run_with_spinner "Compiling libcurl" \
        make -C "${curl_dir}" -j"$BUILD_JOBS" --quiet
    run_with_spinner "Installing libcurl" \
        sudo make -C "${curl_dir}" install --quiet

    success "libcurl ${CURL_VERSION} installed"
}

clone_sources() {
    step "Cloning source code"

    local src_dir="$1"

    info "Cloning php-src (${PHP_SRC_BRANCH})..."
    run_with_spinner "Cloning php-src" \
        git clone --depth=1 --branch "$PHP_SRC_BRANCH" "https://github.com/${PHP_SRC_REPO}.git" "$src_dir"

    info "Cloning async extension (${ASYNC_BRANCH})..."
    run_with_spinner "Cloning ext/async" \
        git clone --depth=1 --branch "$ASYNC_BRANCH" "https://github.com/${ASYNC_REPO}.git" "${src_dir}/ext/async"

    if [[ "$NO_XDEBUG" != "true" ]]; then
        info "Cloning Xdebug (${XDEBUG_BRANCH})..."
        run_with_spinner "Cloning Xdebug" \
            git clone --depth=1 --branch "$XDEBUG_BRANCH" "https://github.com/${XDEBUG_REPO}.git" "${src_dir}/../xdebug"
    fi

    success "Sources cloned"
}

configure_php() {
    step "Configuring PHP build"

    local src_dir="$1"

    # Homebrew paths for macOS
    local openssl_prefix
    openssl_prefix="$(brew --prefix openssl@3)"
    local icu_prefix
    icu_prefix="$(brew --prefix icu4c)"
    local bison_prefix
    bison_prefix="$(brew --prefix bison)"
    local libxml2_prefix
    libxml2_prefix="$(brew --prefix libxml2)"
    local zlib_prefix
    zlib_prefix="$(brew --prefix zlib)"
    local bzip2_prefix
    bzip2_prefix="$(brew --prefix bzip2)"
    local readline_prefix
    readline_prefix="$(brew --prefix readline)"
    local curl_prefix
    curl_prefix="$(brew --prefix curl)"
    local libuv_prefix
    libuv_prefix="$(brew --prefix libuv)"
    local libzip_prefix
    libzip_prefix="$(brew --prefix libzip)"
    local sodium_prefix
    sodium_prefix="$(brew --prefix libsodium)"
    local gmp_prefix
    gmp_prefix="$(brew --prefix gmp)"
    local libpng_prefix
    libpng_prefix="$(brew --prefix libpng)"
    local jpeg_prefix
    jpeg_prefix="$(brew --prefix libjpeg-turbo)"
    local webp_prefix
    webp_prefix="$(brew --prefix libwebp)"
    local freetype_prefix
    freetype_prefix="$(brew --prefix freetype)"
    local tidy_prefix
    tidy_prefix="$(brew --prefix tidy-html5)"
    local oniguruma_prefix
    oniguruma_prefix="$(brew --prefix oniguruma)"
    local libffi_prefix
    libffi_prefix="$(brew --prefix libffi)"
    local xslt_prefix
    xslt_prefix="$(brew --prefix libxslt)"
    local ldap_prefix
    ldap_prefix="$(brew --prefix openldap)"
    local pgsql_prefix
    pgsql_prefix="$(brew --prefix libpq)"
    local sqlite_prefix
    sqlite_prefix="$(brew --prefix sqlite)"
    local argon2_prefix
    argon2_prefix="$(brew --prefix argon2)"
    local enchant_prefix
    enchant_prefix="$(brew --prefix enchant)"
    local gdbm_prefix
    gdbm_prefix="$(brew --prefix gdbm)"
    local lmdb_prefix
    lmdb_prefix="$(brew --prefix lmdb)"
    local snmp_prefix
    snmp_prefix="$(brew --prefix net-snmp)"

    # Ensure bison from Homebrew is first in PATH (macOS ships an old one)
    export PATH="${bison_prefix}/bin:${PATH}"

    info "Running buildconf..."
    run_with_spinner "Running buildconf" \
        bash -c "cd '${src_dir}' && ./buildconf --force"

    local flags=(
        "--prefix=${INSTALL_DIR}"
        "--with-config-file-path=${INSTALL_DIR}/etc"
        "--with-config-file-scan-dir=${INSTALL_DIR}/etc/php.d"
        "--enable-zts"
        "--enable-async"
        "--enable-phpdbg"
        "--enable-bcmath"
        "--enable-calendar"
        "--enable-exif"
        "--enable-ftp"
        "--enable-intl"
        "--enable-mbstring"
        "--enable-pdo"
        "--enable-shmop"
        "--enable-soap"
        "--enable-sockets"
        "--enable-pcntl"
        "--enable-sysvmsg"
        "--enable-sysvsem"
        "--enable-sysvshm"
        "--enable-gd"
        "--enable-dba"
        "--enable-xmlreader"
        "--with-bz2=${bzip2_prefix}"
        "--with-curl=${curl_prefix}"
        "--with-gettext"
        "--with-gmp=${gmp_prefix}"
        "--with-mysqli=mysqlnd"
        "--with-openssl=${openssl_prefix}"
        "--with-pdo-mysql=mysqlnd"
        "--with-pdo-pgsql=${pgsql_prefix}"
        "--with-pdo-sqlite=${sqlite_prefix}"
        "--with-pgsql=${pgsql_prefix}"
        "--with-sqlite3=${sqlite_prefix}"
        "--with-xsl"
        "--with-zlib=${zlib_prefix}"
        "--with-jpeg=${jpeg_prefix}"
        "--with-webp=${webp_prefix}"
        "--with-freetype=${freetype_prefix}"
        "--with-zip=${libzip_prefix}"
        "--with-sodium=${sodium_prefix}"
        "--with-readline=${readline_prefix}"
        "--with-tidy=${tidy_prefix}"
        "--with-ldap=${ldap_prefix}"
        "--with-enchant=${enchant_prefix}"
        "--with-ffi"
        "--with-snmp=${snmp_prefix}"
        "--with-gdbm=${gdbm_prefix}"
        "--with-lmdb=${lmdb_prefix}"
        "--with-libxml"
        "--with-password-argon2=${argon2_prefix}"
        "--without-pear"
    )

    if [[ "$DEBUG_BUILD" == "true" ]]; then
        flags+=("--enable-debug")
    else
        flags+=("--disable-debug")
    fi

    # Export PKG_CONFIG_PATH for Homebrew libraries
    export PKG_CONFIG_PATH="${openssl_prefix}/lib/pkgconfig:${icu_prefix}/lib/pkgconfig:${libxml2_prefix}/lib/pkgconfig:${zlib_prefix}/lib/pkgconfig:${oniguruma_prefix}/lib/pkgconfig:${libffi_prefix}/lib/pkgconfig:${xslt_prefix}/lib/pkgconfig:${sqlite_prefix}/lib/pkgconfig:${libuv_prefix}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

    # Export LDFLAGS and CPPFLAGS for libraries that Homebrew keg-only installs
    export LDFLAGS="-L${openssl_prefix}/lib -L${icu_prefix}/lib -L${zlib_prefix}/lib -L${bzip2_prefix}/lib -L${readline_prefix}/lib -L${libxml2_prefix}/lib -L${sqlite_prefix}/lib -L${libffi_prefix}/lib"
    export CPPFLAGS="-I${openssl_prefix}/include -I${icu_prefix}/include -I${zlib_prefix}/include -I${bzip2_prefix}/include -I${readline_prefix}/include -I${libxml2_prefix}/include -I${sqlite_prefix}/include -I${libffi_prefix}/include"

    info "Configure flags: ${#flags[@]} options"

    run_with_spinner "Running configure" \
        bash -c "cd '${src_dir}' && ./configure ${flags[*]}"

    success "Configuration complete"
}

build_php() {
    step "Compiling PHP"

    local src_dir="$1"

    info "Building with ${BUILD_JOBS} parallel jobs..."
    info "This may take 5-15 minutes depending on your hardware"

    run_with_spinner "Compiling PHP (${BUILD_JOBS} jobs)" \
        make -C "$src_dir" -j"$BUILD_JOBS"

    success "PHP compiled successfully"
}

install_php() {
    step "Installing PHP"

    local src_dir="$1"

    mkdir -p "$INSTALL_DIR"

    run_with_spinner "Installing to ${INSTALL_DIR}" \
        make -C "$src_dir" install

    success "PHP installed to ${INSTALL_DIR}"
}

build_xdebug() {
    step "Building Xdebug"

    local xdebug_dir="$1"
    local php_bin="${INSTALL_DIR}/bin"

    if [[ ! -d "$xdebug_dir" ]]; then
        warn "Xdebug source not found, skipping"
        return 0
    fi

    run_with_spinner "Running phpize" \
        bash -c "cd '${xdebug_dir}' && '${php_bin}/phpize'"

    run_with_spinner "Configuring Xdebug" \
        bash -c "cd '${xdebug_dir}' && ./configure --with-php-config='${php_bin}/php-config'"

    run_with_spinner "Compiling Xdebug" \
        make -C "${xdebug_dir}" -j"$BUILD_JOBS"

    run_with_spinner "Installing Xdebug" \
        make -C "${xdebug_dir}" install

    success "Xdebug installed"
}

setup_config() {
    step "Setting up PHP configuration"

    local conf_dir="${INSTALL_DIR}/etc/php.d"
    mkdir -p "$conf_dir"

    cat > "${conf_dir}/opcache.ini" << 'EOF'
opcache.enable_cli=1
EOF
    success "Created opcache.ini"

    if [[ "$NO_XDEBUG" != "true" ]]; then
        cat > "${conf_dir}/xdebug.ini" << 'EOF'
zend_extension=xdebug.so
xdebug.mode=off
EOF
        success "Created xdebug.ini"
    fi
}

setup_path() {
    step "Setting up environment"

    local bin_dir="${INSTALL_DIR}/bin"

    install_management_script "$bin_dir"

    if [[ "$SET_DEFAULT" == "true" ]]; then
        local shell_rc=""
        local current_shell
        current_shell=$(basename "${SHELL:-/bin/zsh}")

        case "$current_shell" in
            bash) shell_rc="$HOME/.bash_profile" ;;
            zsh)  shell_rc="$HOME/.zshrc" ;;
            *)    shell_rc="$HOME/.profile" ;;
        esac

        if [[ -n "$shell_rc" ]] && ! grep -q "php-trueasync" "$shell_rc" 2>/dev/null; then
            {
                echo ""
                echo "# TrueAsync PHP"
                echo "export PATH=\"${bin_dir}:\$PATH\""
            } >> "$shell_rc"
            success "Added ${bin_dir} to PATH in ${shell_rc}"
            warn "Run 'source ${shell_rc}' or open a new terminal to use php"
        elif grep -q "php-trueasync" "$shell_rc" 2>/dev/null; then
            info "PATH already configured in ${shell_rc}"
        fi
    else
        info "PATH not modified (use --set-default to add to PATH)"
        info "You can run PHP directly: ${CYAN}${bin_dir}/php${NC}"
    fi
}

install_management_script() {
    local bin_dir="$1"
    local script="${bin_dir}/php-trueasync"

    cat > "$script" << 'MGMT_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE=".trueasync-version"
INSTALLER_URL="https://raw.githubusercontent.com/true-async/releases/master/installer/build-macos.sh"

case "${1:-help}" in
    update|rebuild)
        echo "Rebuilding TrueAsync PHP..."
        INSTALL_DIR="$SCRIPT_DIR" exec bash <(curl -fsSL "$INSTALLER_URL")
        ;;
    version)
        if [[ -f "${SCRIPT_DIR}/${VERSION_FILE}" ]]; then
            cat "${SCRIPT_DIR}/${VERSION_FILE}"
        else
            "${SCRIPT_DIR}/bin/php" -v | head -1
        fi
        ;;
    uninstall)
        echo "Uninstalling TrueAsync PHP from ${SCRIPT_DIR}..."
        for rc in "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            if [[ -f "$rc" ]] && grep -q "php-trueasync" "$rc"; then
                sed -i '' '/php-trueasync/d' "$rc"
                echo "Cleaned PATH from $rc"
            fi
        done
        rm -rf "$SCRIPT_DIR"
        echo "TrueAsync PHP uninstalled."
        echo "Restart your terminal to apply PATH changes."
        ;;
    help|--help|-h)
        echo "TrueAsync PHP Manager"
        echo ""
        echo "Usage: php-trueasync <command>"
        echo ""
        echo "Commands:"
        echo "  rebuild     Rebuild PHP from source (fetches latest code)"
        echo "  version     Show the installed version"
        echo "  uninstall   Remove TrueAsync PHP and clean up PATH"
        echo "  help        Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'php-trueasync help' for usage."
        exit 1
        ;;
esac
MGMT_SCRIPT

    chmod +x "$script"
    success "Management script installed: ${bin_dir}/php-trueasync"
}

verify_installation() {
    step "Verifying installation"

    local php_bin="${INSTALL_DIR}/bin/php"

    if [[ ! -x "$php_bin" ]]; then
        error "php binary not found at ${php_bin}"
    fi

    echo ""
    "$php_bin" -v
    echo ""

    info "Loaded modules:"
    local modules
    modules=$("$php_bin" -m | grep -E "^(async|xdebug|Core|date|pcre)" | tr '\n' ', ' | sed 's/,$//')
    dimtext "$modules ..."

    local version
    version=$("$php_bin" -r 'echo PHP_VERSION;')
    echo "$version" > "${INSTALL_DIR}/.trueasync-version"

    success "PHP ${version} with TrueAsync is ready!"
}

show_final_message() {
    local bin_dir="${INSTALL_DIR}/bin"

    echo ""
    echo -e "  ${GREEN}${BOLD}┌──────────────────────────────────────────────┐${NC}"
    echo -e "  ${GREEN}${BOLD}│${NC}                                              ${GREEN}${BOLD}│${NC}"
    echo -e "  ${GREEN}${BOLD}│${NC}  ${GREEN}${BOLD}⚡ Build complete!${NC}                           ${GREEN}${BOLD}│${NC}"
    echo -e "  ${GREEN}${BOLD}│${NC}                                              ${GREEN}${BOLD}│${NC}"
    echo -e "  ${GREEN}${BOLD}│${NC}  PHP binary: ${CYAN}${bin_dir}/php${NC}"
    echo -e "  ${GREEN}${BOLD}│${NC}  Manager:    ${CYAN}${bin_dir}/php-trueasync${NC}"
    echo -e "  ${GREEN}${BOLD}│${NC}                                              ${GREEN}${BOLD}│${NC}"

    if [[ "$SET_DEFAULT" != "true" ]]; then
        echo -e "  ${GREEN}${BOLD}│${NC}  ${DIM}Tip: Run with --set-default to add to PATH${NC}  ${GREEN}${BOLD}│${NC}"
        echo -e "  ${GREEN}${BOLD}│${NC}                                              ${GREEN}${BOLD}│${NC}"
    fi

    echo -e "  ${GREEN}${BOLD}└──────────────────────────────────────────────┘${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    parse_args "$@"
    show_banner
    check_system

    # Interactive wizard
    if [[ "$NO_INTERACTIVE" != "true" ]] && [[ -t 0 ]]; then
        run_wizard
    fi

    # Determine total steps
    STEP_TOTAL=7
    [[ "$NO_XDEBUG" != "true" ]] && STEP_TOTAL=8

    read_config

    local build_dir
    build_dir=$(mktemp -d)
    local src_dir="${build_dir}/php-src"
    trap 'rm -rf "$build_dir"' EXIT

    install_dependencies
    build_libcurl "$build_dir"
    clone_sources "$src_dir"
    configure_php "$src_dir"
    build_php "$src_dir"
    install_php "$src_dir"

    if [[ "$NO_XDEBUG" != "true" ]]; then
        build_xdebug "${build_dir}/xdebug"
    fi

    setup_config
    setup_path
    verify_installation
    show_final_message
}

main "$@"
