#!/usr/bin/env bash
set -euo pipefail

# TrueAsync PHP Installer for Linux/macOS
#
# Install:  curl -fsSL https://raw.githubusercontent.com/true-async/releases/main/installer/install.sh | bash
# Update:   php-trueasync update
# Uninstall: php-trueasync uninstall
#
# Options (via environment variables):
#   INSTALL_DIR   — Installation directory (default: $HOME/.php-trueasync)
#   VERSION       — Specific version to install (default: latest)
#   SKIP_VERIFY   — Skip SHA256 verification (default: false)
#   NO_PATH       — Skip adding to PATH (default: false)

REPO="true-async/releases"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.php-trueasync}"
VERSION="${VERSION:-latest}"
SKIP_VERIFY="${SKIP_VERIFY:-false}"
NO_PATH="${NO_PATH:-false}"
VERSION_FILE=".trueasync-version"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# --- Detect platform ---
detect_platform() {
    local os arch

    case "$(uname -s)" in
        Linux*)  os="linux" ;;
        Darwin*) os="macos" ;;
        *)       error "Unsupported OS: $(uname -s)" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac

    echo "${os}-${arch}"
}

# --- Find download tool ---
get_downloader() {
    if command -v curl &>/dev/null; then
        echo "curl"
    elif command -v wget &>/dev/null; then
        echo "wget"
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
}

# --- Download file ---
download() {
    local url="$1" dest="$2"
    local downloader
    downloader=$(get_downloader)

    if [[ "$downloader" == "curl" ]]; then
        curl -fSL --progress-bar -o "$dest" "$url"
    else
        wget -q --show-progress -O "$dest" "$url"
    fi
}

# --- Get latest version ---
get_latest_version() {
    local downloader
    downloader=$(get_downloader)

    local api_url="https://api.github.com/repos/${REPO}/releases/latest"

    if [[ "$downloader" == "curl" ]]; then
        curl -fsSL "$api_url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//'
    else
        wget -qO- "$api_url" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//'
    fi
}

# --- Get currently installed version ---
get_installed_version() {
    local vfile="${INSTALL_DIR}/${VERSION_FILE}"
    if [[ -f "$vfile" ]]; then
        cat "$vfile"
    else
        echo ""
    fi
}

# --- Verify SHA256 ---
verify_checksum() {
    local file="$1" expected="$2"

    local actual
    if command -v sha256sum &>/dev/null; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        warn "No sha256sum or shasum found, skipping verification"
        return 0
    fi

    if [[ "$actual" != "$expected" ]]; then
        error "Checksum mismatch!\n  Expected: $expected\n  Actual:   $actual"
    fi

    ok "Checksum verified"
}

# --- Install/update ---
do_install() {
    local platform
    platform=$(detect_platform)
    info "Platform: $platform"

    # Resolve version
    if [[ "$VERSION" == "latest" ]]; then
        info "Fetching latest version..."
        VERSION=$(get_latest_version)
        if [[ -z "$VERSION" ]]; then
            error "Could not determine latest version"
        fi
    fi

    local version_num="${VERSION#v}"
    info "Version: $VERSION"

    # Determine archive name
    local ext="tar.gz"
    local archive="php-trueasync-${version_num}-${platform}.${ext}"
    local base_url="https://github.com/${REPO}/releases/download/${VERSION}"
    local archive_url="${base_url}/${archive}"
    local checksums_url="${base_url}/sha256sums.txt"

    # Create temp directory
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    # Download archive
    info "Downloading ${archive}..."
    download "$archive_url" "${tmpdir}/${archive}"
    ok "Downloaded"

    # Verify checksum
    if [[ "$SKIP_VERIFY" != "true" ]]; then
        info "Downloading checksums..."
        download "$checksums_url" "${tmpdir}/sha256sums.txt"

        local expected
        expected=$(grep "$archive" "${tmpdir}/sha256sums.txt" | awk '{print $1}')
        if [[ -n "$expected" ]]; then
            verify_checksum "${tmpdir}/${archive}" "$expected"
        else
            warn "Checksum for $archive not found in sha256sums.txt"
        fi
    fi

    # Install
    info "Installing to ${INSTALL_DIR}..."
    mkdir -p "$INSTALL_DIR"
    tar xzf "${tmpdir}/${archive}" -C "$INSTALL_DIR" --strip-components=1

    # Save version marker
    echo "$VERSION" > "${INSTALL_DIR}/${VERSION_FILE}"

    ok "Installed to ${INSTALL_DIR}"

    # Setup PATH and management script
    local bin_dir="${INSTALL_DIR}/bin"
    if [[ -d "$bin_dir" ]]; then
        # Install the management script
        install_management_script "$bin_dir"

        if [[ "$NO_PATH" != "true" ]]; then
            local shell_rc=""
            if [[ -n "${BASH_VERSION:-}" ]]; then
                shell_rc="$HOME/.bashrc"
            elif [[ -n "${ZSH_VERSION:-}" ]]; then
                shell_rc="$HOME/.zshrc"
            fi

            if [[ -n "$shell_rc" ]] && ! grep -q "php-trueasync" "$shell_rc" 2>/dev/null; then
                echo "" >> "$shell_rc"
                echo "# TrueAsync PHP" >> "$shell_rc"
                echo "export PATH=\"${bin_dir}:\$PATH\"" >> "$shell_rc"
                ok "Added ${bin_dir} to PATH in ${shell_rc}"
                warn "Run 'source ${shell_rc}' or open a new terminal to use php"
            fi
        else
            info "Skipping PATH modification (NO_PATH=true)"
            info "Binary location: ${bin_dir}/php"
        fi
    fi

    # Verify
    echo ""
    info "Verifying installation..."
    "${bin_dir}/php" -v
    echo ""
    ok "TrueAsync PHP ${VERSION} installed successfully!"
    echo ""
}

# --- Install php-trueasync management script ---
install_management_script() {
    local bin_dir="$1"
    local script="${bin_dir}/php-trueasync"

    cat > "$script" << 'MGMT_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE=".trueasync-version"
INSTALLER_URL="https://raw.githubusercontent.com/true-async/releases/main/installer/install.sh"

case "${1:-help}" in
    update)
        echo "Checking for updates..."
        CURRENT=$(cat "${SCRIPT_DIR}/${VERSION_FILE}" 2>/dev/null || echo "unknown")
        echo "Current version: $CURRENT"

        INSTALL_DIR="$SCRIPT_DIR" exec bash <(curl -fsSL "$INSTALLER_URL")
        ;;
    version)
        cat "${SCRIPT_DIR}/${VERSION_FILE}" 2>/dev/null || echo "unknown"
        ;;
    uninstall)
        echo "Uninstalling TrueAsync PHP from ${SCRIPT_DIR}..."

        # Remove PATH from shell rc files
        for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
            if [[ -f "$rc" ]] && grep -q "php-trueasync" "$rc"; then
                sed -i.bak '/php-trueasync/d' "$rc"
                rm -f "${rc}.bak"
                echo "Cleaned PATH from $rc"
            fi
        done

        # Remove installation
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
        echo "  update      Check for updates and install the latest version"
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
}

# --- Update command (called directly) ---
do_update() {
    local current
    current=$(get_installed_version)

    if [[ -z "$current" ]]; then
        info "No existing installation found. Running fresh install..."
        do_install
        return
    fi

    info "Current version: $current"
    info "Checking for updates..."

    local latest
    latest=$(get_latest_version)

    if [[ -z "$latest" ]]; then
        error "Could not determine latest version"
    fi

    if [[ "$current" == "$latest" ]]; then
        ok "Already up to date ($current)"
        return
    fi

    info "New version available: $latest (current: $current)"
    VERSION="$latest"
    do_install
}

# --- Uninstall ---
do_uninstall() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        warn "TrueAsync PHP is not installed at ${INSTALL_DIR}"
        return
    fi

    info "Uninstalling TrueAsync PHP from ${INSTALL_DIR}..."

    # Remove PATH from shell rc files
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$rc" ]] && grep -q "php-trueasync" "$rc"; then
            sed -i.bak '/php-trueasync/d' "$rc"
            rm -f "${rc}.bak"
            ok "Cleaned PATH from $rc"
        fi
    done

    rm -rf "$INSTALL_DIR"
    ok "TrueAsync PHP uninstalled"
    warn "Restart your terminal to apply PATH changes"
}

# === Entry point ===
main() {
    local command="${1:-install}"

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     TrueAsync PHP Installer          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    case "$command" in
        install)   do_install ;;
        update)    do_update ;;
        uninstall) do_uninstall ;;
        *)         do_install ;;
    esac
}

main "$@"
