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

# ── Uninstall previous Python-based installation ────────────────────
uninstall_python_version() {
    local found=0

    if has pipx && pipx list 2>/dev/null | grep -q "${PACKAGE_NAME}"; then
        info "Found previous Python-based installation (pipx). Removing..."
        pipx uninstall "${PACKAGE_NAME}" || true
        found=1
    fi

    if has uv && uv tool list 2>/dev/null | grep -q "${PACKAGE_NAME}"; then
        info "Found previous Python-based installation (uv). Removing..."
        uv tool uninstall "${PACKAGE_NAME}" || true
        found=1
    fi

    # Check pip-installed version (look for the Python package metadata)
    for pip_cmd in pip3 pip; do
        if has "${pip_cmd}" && "${pip_cmd}" show "${PACKAGE_NAME}" &>/dev/null; then
            info "Found previous Python-based installation (${pip_cmd}). Removing..."
            "${pip_cmd}" uninstall -y "${PACKAGE_NAME}" 2>/dev/null || true
            found=1
            break
        fi
    done

    if [ "${found}" -eq 1 ]; then
        success "Previous Python-based installation removed."
    fi
}

# ── Build Rust target triple from OS/ARCH ───────────────────────────
get_target_triple() {
    case "${OS}-${ARCH}" in
        darwin-x86_64)   echo "x86_64-apple-darwin"         ;;
        darwin-aarch64)  echo "aarch64-apple-darwin"        ;;
        linux-x86_64)    echo "x86_64-unknown-linux-gnu"    ;;
        linux-aarch64)   echo "aarch64-unknown-linux-gnu"   ;;
        *)               error "No prebuilt binary for ${OS}/${ARCH}" ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════
#  Install Strategy: Binary (download from GitHub Releases)
# ══════════════════════════════════════════════════════════════════════
install_via_binary() {
    # Resolve version tag
    local tag="${REQUESTED_VERSION}"
    if [ "${tag}" = "latest" ]; then
        info "Fetching latest release..."
        tag=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
              | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        [ -n "${tag}" ] || error "Failed to determine latest version"
    fi

    # Extract version number from tag (e.g. "zilliz-v1.0.1" -> "1.0.1")
    local version="${tag}"
    version="${version#zilliz-v}"
    version="${version#v}"
    info "Version: ${version}"

    # Build download URL
    local target
    target=$(get_target_triple)
    local archive="${BIN_NAME}-${version}-${target}.tar.gz"
    local url="https://github.com/${REPO}/releases/download/${tag}/${archive}"

    # Download & verify
    TMPDIR_CLEANUP=$(mktemp -d)
    local tmpdir="${TMPDIR_CLEANUP}"
    trap 'rm -rf "${TMPDIR_CLEANUP}"' EXIT

    info "Downloading ${url}..."
    curl -fsSL "${url}" -o "${tmpdir}/${archive}"

    # Checksum (optional, if sha256sums.txt is published)
    local checksums_url="https://github.com/${REPO}/releases/download/${tag}/sha256sums.txt"
    if curl -fsSL "${checksums_url}" -o "${tmpdir}/sha256sums.txt" 2>/dev/null; then
        info "Verifying checksum..."
        if has shasum; then
            (cd "${tmpdir}" && shasum -a 256 -c --ignore-missing sha256sums.txt) \
                || error "Checksum verification failed!"
        elif has sha256sum; then
            (cd "${tmpdir}" && sha256sum -c --ignore-missing sha256sums.txt) \
                || error "Checksum verification failed!"
        fi
    fi

    # Extract & install
    info "Extracting to ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"
    tar -xzf "${tmpdir}/${archive}" -C "${tmpdir}"

    # Install binary
    install -m 755 "${tmpdir}/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"

    # Create zz symlink (short alias for zilliz)
    ln -sf "${INSTALL_DIR}/${BIN_NAME}" "${INSTALL_DIR}/zz"

    success "Installed ${BIN_NAME} ${version} to ${INSTALL_DIR}/${BIN_NAME}"
}

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

# ── Post-install Next steps panel ────────────────────────────────────
# NOTE: the Plugins list below is mirrored in install.ps1 and README.md
# "Related Tools". When adding/removing an entry, update all three.
print_next_steps() {
    printf "\n"
    printf "${BOLD}Next steps:${RESET}\n"
    printf "  1. %-30s %s\n" "${BIN_NAME} login"             "Authenticate with Zilliz Cloud"
    printf "  2. %-30s %s\n" "${BIN_NAME} cluster list"      "See your clusters"
    printf "  3. %-30s %s\n" "${BIN_NAME} collection --help" "Manage collections"
    printf "\n"
    printf "${BOLD}Highlights:${RESET}\n"
    printf "  Cloud:\n"
    printf "    • %-14s — \`%s cluster create\` / \`scale\` / \`suspend\`\n"        "Clusters"     "${BIN_NAME}"
    printf "    • %-14s — bulk load data with \`%s import\`\n"                      "Import jobs"  "${BIN_NAME}"
    printf "    • %-14s — \`%s backup create\` / \`restore\`\n"                     "Backup"       "${BIN_NAME}"
    printf "  Data:\n"
    printf "    • %-14s — \`%s vector search\` / \`query\` / \`insert\`\n"          "Vector ops"   "${BIN_NAME}"
    printf "    • %-14s — \`%s index create\` / \`list\` / \`describe\`\n"          "Indexes"      "${BIN_NAME}"
    printf "    • %-14s — \`%s user\` / \`%s role\` (Dedicated only)\n"             "Access ctrl"  "${BIN_NAME}" "${BIN_NAME}"
    printf "\n"
    printf "${BOLD}Docs:${RESET} https://docs.zilliz.com/reference/cli/overview\n"
    printf "\n"
    printf "${BOLD}Plugins:${RESET}\n"
    printf "  • %-22s %s\n" "Zilliz Claude Plugin"  "https://github.com/zilliztech/zilliz-plugin"
    printf "  • %-22s %s\n" "Gemini-cli Extension"  "https://github.com/zilliztech/gemini-cli-extension"
    printf "  • %-22s %s\n" "Zilliz Skill"          "https://github.com/zilliztech/zilliz-skill"
    printf "  • %-22s %s\n" "Milvus Skill"          "https://github.com/zilliztech/milvus-skill"
    printf "  • %-22s %s\n" "Zilliz Launchpad"      "https://github.com/zilliztech/zilliz-launchpad"
}

# ── Uninstall ────────────────────────────────────────────────────────
uninstall() {
    info "Uninstalling ${PACKAGE_NAME}..."

    # Remove Python-based installations
    uninstall_python_version

    # Remove binary install and zz symlink
    if [ -f "${INSTALL_DIR}/${BIN_NAME}" ]; then
        rm -f "${INSTALL_DIR}/${BIN_NAME}"
        info "Removed ${INSTALL_DIR}/${BIN_NAME}"
    fi
    if [ -L "${INSTALL_DIR}/zz" ]; then
        rm -f "${INSTALL_DIR}/zz"
        info "Removed ${INSTALL_DIR}/zz symlink"
    fi

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

    # Remove previous Python-based installation if present
    uninstall_python_version

    # Install binary from GitHub Releases
    install_via_binary

    ensure_path

    # Verify installation
    printf "\n"
    if has "${BIN_NAME}"; then
        success "Installation complete!"
        print_next_steps
    else
        success "Installation complete!"
        warn "Open a new terminal or run 'source ~/.bashrc' (or ~/.zshrc)"
        warn "Then run '${BIN_NAME} --help' to get started."
        print_next_steps
    fi

    printf "\n"
}

main "$@"
