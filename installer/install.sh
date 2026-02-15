#!/usr/bin/env bash
set -euo pipefail

# TrueAsync PHP Installer for Linux/macOS
# Usage: curl -fsSL https://raw.githubusercontent.com/true-async/releases/main/installer/install.sh | bash
#
# Options (via environment variables):
#   INSTALL_DIR   — Installation directory (default: $HOME/.php-trueasync)
#   VERSION       — Specific version to install (default: latest)
#   SKIP_VERIFY   — Skip SHA256 verification (default: false)

REPO="true-async/releases"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.php-trueasync}"
VERSION="${VERSION:-latest}"
SKIP_VERIFY="${SKIP_VERIFY:-false}"

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

# === Main ===
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     TrueAsync PHP Installer          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

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

    ok "Installed to ${INSTALL_DIR}"

    # Setup PATH hint
    local bin_dir="${INSTALL_DIR}/bin"
    if [[ -d "$bin_dir" ]]; then
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
    fi

    # Verify
    echo ""
    info "Verifying installation..."
    "${bin_dir}/php" -v
    echo ""
    ok "TrueAsync PHP installed successfully!"
    echo ""
}

main "$@"
