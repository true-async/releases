#!/usr/bin/env bash
set -euo pipefail

# TrueAsync PHP — Build from Source for Linux (Ubuntu/Debian)
#
# Interactive:  curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-linux.sh | bash
# Non-interactive: curl -fsSL ... | EXTENSIONS=all NO_INTERACTIVE=true bash
#
# Options (CLI args or environment variables):
#   --prefix DIR         Installation directory       (INSTALL_DIR, default: $HOME/.php-trueasync)
#   --set-default        Add to PATH as default php   (SET_DEFAULT=true, default: false)
#   --debug              Build with debug symbols      (DEBUG_BUILD=true, default: false)
#   --extensions PRESET  Extension preset              (EXTENSIONS: standard|xdebug|all, default: standard)
#   --no-xdebug          Exclude Xdebug               (NO_XDEBUG=true)
#   --jobs N             Parallel make jobs            (BUILD_JOBS, default: nproc)
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
BUILD_JOBS="${BUILD_JOBS:-$(nproc 2>/dev/null || echo 4)}"
PHP_BRANCH="${PHP_BRANCH:-}"
NO_INTERACTIVE="${NO_INTERACTIVE:-${CI:-false}}"

LIBUV_VERSION="1.49.2"
CURL_VERSION="8.10.1"

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
    echo "  ║        Linux (Ubuntu/Debian)                         ║"
    echo "  ║                                                      ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_summary_box() {
    local prefix="$1" debug="$2" extensions="$3" xdebug="$4" set_default="$5" jobs="$6"

    echo ""
    echo -e "  ${BOLD}Build Configuration Summary${NC}"
    echo -e "  ─────────────────────────────────────"
    echo -e "  Install prefix:  ${CYAN}${prefix}${NC}"
    echo -e "  Debug build:     ${debug}"
    echo -e "  Extensions:      ${extensions}"
    echo -e "  Xdebug:          ${xdebug}"
    echo -e "  Set as default:  ${set_default}"
    echo -e "  Parallel jobs:   ${jobs}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# Argument parsing
# ═══════════════════════════════════════════════════════════════════════════════

show_help() {
    echo "TrueAsync PHP — Build from Source (Linux)"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --prefix DIR         Installation directory (default: \$HOME/.php-trueasync)"
    echo "  --set-default        Add to PATH as default php"
    echo "  --debug              Build with debug symbols"
    echo "  --extensions PRESET  Extension preset: standard, xdebug, all (default: standard)"
    echo "  --no-xdebug          Exclude Xdebug from build"
    echo "  --jobs N             Parallel make jobs (default: $(nproc 2>/dev/null || echo 4))"
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

    local hint="y/N" default_hint="N"
    if [[ "$default" == "y" ]]; then
        hint="Y/n"
        default_hint="Y"
    fi

    while true; do
        printf "  ${BOLD}%s${NC} [%s] (default: %s): " "$prompt" "$hint" "$default_hint"
        read -r answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo -e "  ${RED}Please answer y or n${NC}" ;;
        esac
    done
}

ask_input() {
    local prompt="$1"
    local default="$2"

    printf "  ${BOLD}%s${NC} [${DIM}%s${NC}]: " "$prompt" "$default" >&2
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
        # Download config if running from curl pipe
        CONFIG_FILE=$(mktemp)
        local config_url="https://raw.githubusercontent.com/true-async/releases/master/build-config.json"
        if command -v curl &>/dev/null; then
            curl -fsSL "$config_url" -o "$CONFIG_FILE"
        elif command -v wget &>/dev/null; then
            wget -qO "$CONFIG_FILE" "$config_url"
        else
            error "Cannot download build-config.json. Install curl or wget."
        fi
    fi

    if ! command -v jq &>/dev/null; then
        # Minimal JSON parsing without jq
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

    # Override branch if specified
    [[ -n "$PHP_BRANCH" ]] && PHP_SRC_BRANCH="$PHP_BRANCH"
}

# ═══════════════════════════════════════════════════════════════════════════════
# System checks
# ═══════════════════════════════════════════════════════════════════════════════

check_system() {
    # Check we're on Linux
    if [[ "$(uname -s)" != "Linux" ]]; then
        error "This script is for Linux. Use build-macos.sh for macOS."
    fi

    # Check for apt
    if ! command -v apt-get &>/dev/null; then
        error "This script requires apt (Ubuntu/Debian). Your distro is not supported yet."
    fi

    # Check for sudo and pre-authenticate
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo &>/dev/null; then
            error "sudo is required to install build dependencies."
        fi
        info "Sudo access is required to install build dependencies."
        sudo -v || error "Failed to obtain sudo credentials."
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Build steps
# ═══════════════════════════════════════════════════════════════════════════════

install_dependencies() {
    step "Installing build dependencies"

    local pkgs=(
        autoconf automake bison re2c pkg-config dos2unix
        gcc g++ make cmake ninja-build
        git curl wget
        # Core
        libxml2-dev libssl-dev libsqlite3-dev libargon2-dev
        # Extensions
        libedit-dev libreadline-dev libonig-dev
        libsodium-dev libzip-dev zlib1g-dev
        libbz2-dev libgmp-dev libicu-dev
        libxslt1-dev libpsl-dev
        # Image
        libpng-dev libjpeg-dev libwebp-dev libfreetype6-dev
        # Database
        libpq-dev libmysqlclient-dev
        # Extra
        libcurl4-openssl-dev libldap2-dev libsasl2-dev
        libtidy-dev libenchant-2-dev libffi-dev
        libsnmp-dev libgdbm-dev liblmdb-dev
    )

    local sudo_cmd=""
    [[ $EUID -ne 0 ]] && sudo_cmd="sudo"

    run_with_spinner "Updating package lists" $sudo_cmd apt-get update -qq
    run_with_spinner "Installing ${#pkgs[@]} packages" $sudo_cmd apt-get install -y -qq --no-install-recommends "${pkgs[@]}"
}

build_libuv() {
    step "Building libuv ${LIBUV_VERSION}"

    local build_dir="$1"
    local libuv_dir="${build_dir}/libuv-${LIBUV_VERSION}"

    if pkg-config --exists libuv 2>/dev/null; then
        local sys_ver
        sys_ver=$(pkg-config --modversion libuv 2>/dev/null)
        info "System libuv found: ${sys_ver}"

        # Check if system version is recent enough (>= 1.44)
        local major minor
        major=$(echo "$sys_ver" | cut -d. -f1)
        minor=$(echo "$sys_ver" | cut -d. -f2)
        if (( major >= 1 && minor >= 44 )); then
            success "System libuv ${sys_ver} is sufficient, skipping build"
            return 0
        fi
        warn "System libuv ${sys_ver} is too old, building ${LIBUV_VERSION}"
    fi

    info "Downloading libuv ${LIBUV_VERSION}..."
    wget -q "https://github.com/libuv/libuv/archive/v${LIBUV_VERSION}.tar.gz" -O "${build_dir}/libuv.tar.gz"
    tar -xf "${build_dir}/libuv.tar.gz" -C "$build_dir"

    mkdir -p "${libuv_dir}/build"
    run_with_spinner "Configuring libuv" \
        cmake -S "${libuv_dir}" -B "${libuv_dir}/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
    run_with_spinner "Compiling libuv" \
        ninja -C "${libuv_dir}/build"

    local sudo_cmd=""
    [[ $EUID -ne 0 ]] && sudo_cmd="sudo"
    run_with_spinner "Installing libuv" \
        $sudo_cmd ninja -C "${libuv_dir}/build" install
    $sudo_cmd ldconfig

    success "libuv ${LIBUV_VERSION} installed"
}

build_libcurl() {
    step "Building libcurl ${CURL_VERSION}"

    local build_dir="$1"

    # Check system curl version
    if pkg-config --exists libcurl 2>/dev/null; then
        local sys_ver
        sys_ver=$(pkg-config --modversion libcurl 2>/dev/null)
        local major minor patch
        IFS='.' read -r major minor patch <<< "$sys_ver"
        # Need >= 7.87.0
        if (( major > 7 || (major == 7 && minor >= 87) || major >= 8 )); then
            success "System libcurl ${sys_ver} is sufficient, skipping build"
            return 0
        fi
        warn "System libcurl ${sys_ver} is too old, building ${CURL_VERSION}"
    fi

    info "Downloading libcurl ${CURL_VERSION}..."
    local curl_tag
    curl_tag="curl-$(echo "$CURL_VERSION" | tr '.' '_')"
    wget -q "https://github.com/curl/curl/releases/download/${curl_tag}/curl-${CURL_VERSION}.tar.gz" -O "${build_dir}/curl.tar.gz"
    tar -xf "${build_dir}/curl.tar.gz" -C "$build_dir"

    local curl_dir="${build_dir}/curl-${CURL_VERSION}"

    run_with_spinner "Configuring libcurl" \
        bash -c "cd '${curl_dir}' && ./configure --prefix=/usr/local --with-openssl --enable-shared --disable-static --quiet"
    run_with_spinner "Compiling libcurl" \
        make -C "${curl_dir}" -j"$BUILD_JOBS" --quiet

    local sudo_cmd=""
    [[ $EUID -ne 0 ]] && sudo_cmd="sudo"
    run_with_spinner "Installing libcurl" \
        $sudo_cmd make -C "${curl_dir}" install --quiet
    $sudo_cmd ldconfig

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

    # Fix line endings
    if command -v dos2unix &>/dev/null; then
        dos2unix "${src_dir}/ext/async/config.m4" 2>/dev/null || true
    fi

    success "Sources cloned"
}

configure_php() {
    step "Configuring PHP build"

    local src_dir="$1"

    info "Running buildconf..."
    run_with_spinner "Running buildconf" \
        bash -c "cd '${src_dir}' && ./buildconf --force"

    # Build configure flags
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
        "--with-bz2"
        "--with-curl"
        "--with-gettext"
        "--with-gmp"
        "--with-mysqli=mysqlnd"
        "--with-openssl"
        "--with-pdo-mysql=mysqlnd"
        "--with-pdo-pgsql"
        "--with-pdo-sqlite"
        "--with-pgsql"
        "--with-sqlite3"
        "--with-xsl"
        "--with-zlib"
        "--with-jpeg"
        "--with-webp"
        "--with-freetype"
        "--with-zip"
        "--with-sodium"
        "--with-readline"
        "--with-tidy"
        "--with-ldap"
        "--with-ldap-sasl"
        "--with-enchant"
        "--with-ffi"
        "--with-snmp"
        "--with-gdbm"
        "--with-lmdb"
        "--with-libxml"
        "--without-pear"
    )

    if [[ "$DEBUG_BUILD" == "true" ]]; then
        flags+=("--enable-debug")
    else
        flags+=("--disable-debug")
    fi

    info "Configure flags: ${#flags[@]} options"
    dimtext "${flags[*]}"

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

    # opcache
    cat > "${conf_dir}/opcache.ini" << 'EOF'
opcache.enable_cli=1
EOF
    success "Created opcache.ini"

    # xdebug
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

    # Install management script
    install_management_script "$bin_dir"

    if [[ "$SET_DEFAULT" == "true" ]]; then
        local shell_rc=""
        local current_shell
        current_shell=$(basename "${SHELL:-/bin/bash}")

        case "$current_shell" in
            bash) shell_rc="$HOME/.bashrc" ;;
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
INSTALLER_URL="https://raw.githubusercontent.com/true-async/releases/master/installer/build-linux.sh"

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
        for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            if [[ -f "$rc" ]] && grep -q "php-trueasync" "$rc"; then
                sed -i.bak '/php-trueasync/d' "$rc"
                rm -f "${rc}.bak"
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

    # Save version
    local version
    version=$("$php_bin" -r 'echo PHP_VERSION;')
    echo "$version" > "${INSTALL_DIR}/.trueasync-version"

    success "PHP ${version} with TrueAsync is ready!"
}

show_final_message() {
    local bin_dir="${INSTALL_DIR}/bin"

    echo ""
    echo -e "  ${GREEN}${BOLD}Build complete!${NC}"
    echo -e "  ─────────────────────────────────────"
    echo -e "  PHP binary: ${CYAN}${bin_dir}/php${NC}"
    echo -e "  Manager:    ${CYAN}${bin_dir}/php-trueasync${NC}"

    if [[ "$SET_DEFAULT" != "true" ]]; then
        echo ""
        echo -e "  ${DIM}Tip: Run with --set-default to add to PATH${NC}"
    fi

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
    STEP_TOTAL=8
    [[ "$NO_XDEBUG" != "true" ]] && STEP_TOTAL=9

    # Read config
    read_config

    # Create temp build directory
    local build_dir
    build_dir=$(mktemp -d)
    local src_dir="${build_dir}/php-src"
    trap 'rm -rf "$build_dir"' EXIT

    # Execute build steps
    install_dependencies
    build_libuv "$build_dir"
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
