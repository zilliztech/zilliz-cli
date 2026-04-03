#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
#  Zilliz CLI Installer
#
#  A unified CLI and TUI for managing Zilliz Cloud clusters
#  vector database operations.
#
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/zilliztech/zilliz-cli/master/install.sh | bash
#
#  Options (via environment variables):
#    ZILLIZ_VERSION=v0.1.0  Install a specific version (default: latest)
#    ZILLIZ_INSTALL_DIR     Override install directory (default: ~/.local/bin)
#    ZILLIZ_NO_MODIFY_PATH  Set to 1 to skip PATH modification
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────
PACKAGE_NAME="zilliz-cli"                     # PyPI package name
BIN_NAME="zilliz"                             # primary binary name
REPO="zilliztech/zilliz-cli"                  # GitHub repo
INSTALL_DIR="${ZILLIZ_INSTALL_DIR:-${HOME}/.local/bin}"
REQUESTED_VERSION="${ZILLIZ_VERSION:-latest}"
MIN_PYTHON_VERSION="3.8"

# ── Logging helpers ──────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

info()    { printf "${BLUE}==>${RESET} ${BOLD}%s${RESET}\n" "$*"; }
success() { printf "${GREEN}==>${RESET} ${BOLD}%s${RESET}\n" "$*"; }
warn()    { printf "${YELLOW}Warning:${RESET} %s\n" "$*" >&2; }
error()   { printf "${RED}Error:${RESET} %s\n" "$*" >&2; exit 1; }

# ── Detect OS / Arch ─────────────────────────────────────────────────
detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "${OS}" in
        Linux*)   OS="linux"  ;;
        Darwin*)  OS="darwin" ;;
        MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
        *)        error "Unsupported operating system: ${OS}" ;;
    esac

    case "${ARCH}" in
        x86_64|amd64)       ARCH="x86_64"  ;;
        aarch64|arm64)      ARCH="aarch64" ;;
        armv7l)             ARCH="armv7"   ;;
        *)                  error "Unsupported architecture: ${ARCH}" ;;
    esac
}

# ── Check if a command exists ────────────────────────────────────────
has() { command -v "$1" &>/dev/null; }

# ── Compare Python versions ─────────────────────────────────────────
python_version_ok() {
    local python_cmd="$1"
    local version
    version=$("${python_cmd}" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null) || return 1
    local major minor
    major=$(echo "${version}" | cut -d. -f1)
    minor=$(echo "${version}" | cut -d. -f2)
    local req_major req_minor
    req_major=$(echo "${MIN_PYTHON_VERSION}" | cut -d. -f1)
    req_minor=$(echo "${MIN_PYTHON_VERSION}" | cut -d. -f2)
    [ "${major}" -gt "${req_major}" ] || { [ "${major}" -eq "${req_major}" ] && [ "${minor}" -ge "${req_minor}" ]; }
}

# ── Find a usable Python ────────────────────────────────────────────
find_python() {
    for cmd in python3 python; do
        if has "${cmd}" && python_version_ok "${cmd}"; then
            echo "${cmd}"
            return 0
        fi
    done
    return 1
}

# ══════════════════════════════════════════════════════════════════════
#  Install Strategy: Python (current)
#
#  In the future, this section will be replaced by a binary download
#  from GitHub Releases. The user-facing install command stays the same.
# ══════════════════════════════════════════════════════════════════════
install_via_python() {
    local python_cmd
    python_cmd=$(find_python) || error "Python ${MIN_PYTHON_VERSION}+ is required but not found.
Please install Python first:
  macOS:  brew install python3
  Ubuntu: sudo apt install python3 python3-pip
  Fedora: sudo dnf install python3 python3-pip"

    local python_version
    python_version=$("${python_cmd}" --version 2>&1)
    info "Found ${python_version}"

    local pkg="${PACKAGE_NAME}"
    if [ "${REQUESTED_VERSION}" != "latest" ]; then
        pkg="${PACKAGE_NAME}==${REQUESTED_VERSION}"
    fi

    # Prefer pipx > uv > pip for isolated installs
    if has pipx; then
        info "Installing ${PACKAGE_NAME} via pipx..."
        pipx install "${pkg}" --force
    elif has uv; then
        info "Installing ${PACKAGE_NAME} via uv..."
        uv tool install "${pkg}" --force
    else
        info "Installing ${PACKAGE_NAME} via pip..."
        "${python_cmd}" -m pip install --user --upgrade "${pkg}"
    fi
}

# ══════════════════════════════════════════════════════════════════════
#  Install Strategy: Binary (future — uncomment when Rust builds are
#  published to GitHub Releases)
# ══════════════════════════════════════════════════════════════════════
# install_via_binary() {
#     detect_platform
#
#     # Resolve version
#     local version="${REQUESTED_VERSION}"
#     if [ "${version}" = "latest" ]; then
#         info "Fetching latest release..."
#         version=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
#                   | grep '"tag_name"' | head -1 | cut -d'"' -f4)
#         [ -n "${version}" ] || error "Failed to determine latest version"
#     fi
#     info "Version: ${version}"
#
#     # Build download URL
#     local archive="${BIN_NAME}-${version}-${OS}-${ARCH}.tar.gz"
#     local url="https://github.com/${REPO}/releases/download/${version}/${archive}"
#
#     # Download & verify
#     local tmpdir
#     tmpdir=$(mktemp -d)
#     trap 'rm -rf "${tmpdir}"' EXIT
#
#     info "Downloading ${url}..."
#     curl -fsSL "${url}" -o "${tmpdir}/${archive}"
#
#     # Checksum (optional, if sha256sums.txt is published)
#     local checksums_url="https://github.com/${REPO}/releases/download/${version}/sha256sums.txt"
#     if curl -fsSL "${checksums_url}" -o "${tmpdir}/sha256sums.txt" 2>/dev/null; then
#         info "Verifying checksum..."
#         (cd "${tmpdir}" && sha256sum -c --ignore-missing sha256sums.txt) \
#             || error "Checksum verification failed!"
#     fi
#
#     # Extract & install
#     info "Extracting to ${INSTALL_DIR}..."
#     mkdir -p "${INSTALL_DIR}"
#     tar -xzf "${tmpdir}/${archive}" -C "${tmpdir}"
#
#     # Install binaries
#     install -m 755 "${tmpdir}/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"
#     # Create shorthand alias
#     ln -sf "${INSTALL_DIR}/${BIN_NAME}" "${INSTALL_DIR}/${BIN_ALIAS}"
#
#     success "Installed ${BIN_NAME} ${version} to ${INSTALL_DIR}/${BIN_NAME}"
# }

# ── Ensure INSTALL_DIR is on PATH ────────────────────────────────────
ensure_path() {
    if echo "${PATH}" | tr ':' '\n' | grep -qx "${INSTALL_DIR}"; then
        return 0
    fi

    if [ "${ZILLIZ_NO_MODIFY_PATH:-0}" = "1" ]; then
        warn "${INSTALL_DIR} is not in your PATH."
        warn "Add it manually: export PATH=\"${INSTALL_DIR}:\$PATH\""
        return 0
    fi

    local shell_name
    shell_name=$(basename "${SHELL:-bash}")
    local profile=""

    case "${shell_name}" in
        bash)
            if [ -f "${HOME}/.bashrc" ]; then
                profile="${HOME}/.bashrc"
            elif [ -f "${HOME}/.bash_profile" ]; then
                profile="${HOME}/.bash_profile"
            fi
            ;;
        zsh)  profile="${HOME}/.zshrc" ;;
        fish) profile="${HOME}/.config/fish/config.fish" ;;
    esac

    if [ -n "${profile}" ]; then
        local path_line
        if [ "${shell_name}" = "fish" ]; then
            path_line="fish_add_path ${INSTALL_DIR}"
        else
            path_line="export PATH=\"${INSTALL_DIR}:\$PATH\""
        fi

        # Avoid duplicate entries
        if ! grep -qF "${INSTALL_DIR}" "${profile}" 2>/dev/null; then
            printf '\n# Added by Zilliz CLI installer\n%s\n' "${path_line}" >> "${profile}"
            info "Added ${INSTALL_DIR} to PATH in ${profile}"
            info "Run 'source ${profile}' or open a new terminal to use it."
        fi
    else
        warn "Could not detect shell profile. Add this to your shell config:"
        warn "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi
}

# ── Uninstall ────────────────────────────────────────────────────────
uninstall() {
    info "Uninstalling ${PACKAGE_NAME}..."

    # Try pipx first, then uv, then pip
    if has pipx && pipx list 2>/dev/null | grep -q "${PACKAGE_NAME}"; then
        pipx uninstall "${PACKAGE_NAME}"
    elif has uv && uv tool list 2>/dev/null | grep -q "${PACKAGE_NAME}"; then
        uv tool uninstall "${PACKAGE_NAME}"
    elif has pip3; then
        pip3 uninstall -y "${PACKAGE_NAME}" 2>/dev/null || true
    elif has pip; then
        pip uninstall -y "${PACKAGE_NAME}" 2>/dev/null || true
    fi

    # Also remove binary install (future-proof)
    for bin in "${BIN_NAME}" "${BIN_ALIAS}"; do
        if [ -f "${INSTALL_DIR}/${bin}" ]; then
            rm -f "${INSTALL_DIR}/${bin}"
            info "Removed ${INSTALL_DIR}/${bin}"
        fi
    done

    success "Uninstalled ${PACKAGE_NAME}"
    exit 0
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    # Handle --uninstall flag
    if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "uninstall" ]; then
        uninstall
    fi

    printf "\n"
    printf "${BOLD}  Zilliz CLI Installer${RESET}\n"
    printf "  Manage Zilliz Cloud from your terminal\n"
    printf "\n"

    detect_platform
    info "Detected platform: ${OS}/${ARCH}"

    # ── Current: Python install ──────────────────────────────────────
    install_via_python

    # ── Future: switch to binary install ─────────────────────────────
    # install_via_binary

    ensure_path

    # Verify installation
    printf "\n"
    if has "${BIN_NAME}"; then
        success "Installation complete!"
        info "Run '${BIN_NAME} --help' to get started."
        info "Use '${BIN_NAME} login' to authenticate with Zilliz Cloud."
    else
        success "Installation complete!"
        warn "Open a new terminal or run 'source ~/.bashrc' (or ~/.zshrc)"
        warn "Then run '${BIN_NAME} --help' to get started."
    fi

    printf "\n"
}

main "$@"
