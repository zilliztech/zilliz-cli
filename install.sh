#!/usr/bin/env bash
# ----------------------------------------------------------------------
#  Zilliz CLI Installer (macOS / Linux)
#
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/zilliztech/zilliz-cli/master/install.sh | bash
#
#  Options (via environment variables):
#    ZILLIZ_VERSION=v2.0.0       Install a specific version (default: latest)
#    ZILLIZ_INSTALL_DIR          Directory for zilliz/zz executables (default: ~/.local/bin)
#    ZILLIZ_HOME                 Directory for onedir runtime bundle (default: ~/.local/share/zilliz)
#    ZILLIZ_NO_MODIFY_PATH=1     Set to 1 to skip shell profile PATH modification
#    ZILLIZ_RELEASE_BASE_URL     Override release asset base URL (for mirrors/testing)
# ----------------------------------------------------------------------
set -euo pipefail

PACKAGE_NAME="zilliz-cli"
BIN_NAME="zilliz"
REPO="zilliztech/zilliz-cli"
INSTALL_DIR="${ZILLIZ_INSTALL_DIR:-${INSTALL_DIR:-${HOME}/.local/bin}}"
SHARE_DIR="${ZILLIZ_HOME:-${HOME}/.local/share/zilliz}"
REQUESTED_VERSION="${ZILLIZ_VERSION:-${VERSION:-latest}}"

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

has() { command -v "$1" >/dev/null 2>&1; }

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "${OS}" in
        Linux*)   OS="linux"  ;;
        Darwin*)  OS="darwin" ;;
        *)        error "Unsupported operating system: ${OS}. Use install.ps1 on Windows." ;;
    esac

    case "${ARCH}" in
        x86_64|amd64)   ARCH="x86_64"  ;;
        aarch64|arm64)  ARCH="aarch64" ;;
        *)              error "Unsupported architecture: ${ARCH}" ;;
    esac
}

get_target_triple() {
    case "${OS}-${ARCH}" in
        darwin-x86_64)   echo "x86_64-apple-darwin"       ;;
        darwin-aarch64)  echo "aarch64-apple-darwin"      ;;
        linux-x86_64)    echo "x86_64-unknown-linux-gnu"  ;;
        linux-aarch64)   echo "aarch64-unknown-linux-gnu" ;;
        *)               error "No prebuilt archive for ${OS}/${ARCH}" ;;
    esac
}

cleanup_conflicting_installs() {
    if has pipx && pipx list 2>/dev/null | grep -q "${PACKAGE_NAME}"; then
        info "Found global pipx installation of ${PACKAGE_NAME}. Removing shim..."
        pipx uninstall "${PACKAGE_NAME}" || true
    fi

    if has uv && uv tool list 2>/dev/null | grep -q "${PACKAGE_NAME}"; then
        info "Found global uv tool installation of ${PACKAGE_NAME}. Removing shim..."
        uv tool uninstall "${PACKAGE_NAME}" || true
    fi

    # Never touch active virtualenvs or conda environments
    if [ -z "${VIRTUAL_ENV:-}" ] && [ -z "${CONDA_PREFIX:-}" ]; then
        for pip_cmd in pip3 pip; do
            if has "${pip_cmd}" && "${pip_cmd}" show "${PACKAGE_NAME}" >/dev/null 2>&1; then
                info "Found global ${pip_cmd} installation of ${PACKAGE_NAME}. Removing..."
                "${pip_cmd}" uninstall -y "${PACKAGE_NAME}" 2>/dev/null || true
                break
            fi
        done
    fi

    # Clean up legacy ~/.zilliz/bin single-file binary if installing elsewhere
    local legacy_bin_dir="${HOME}/.zilliz/bin"
    if [ "${INSTALL_DIR}" != "${legacy_bin_dir}" ]; then
        for name in "${BIN_NAME}" "zz"; do
            if [ -f "${legacy_bin_dir}/${name}" ] || [ -L "${legacy_bin_dir}/${name}" ]; then
                rm -f "${legacy_bin_dir}/${name}"
                info "Removed legacy binary at ${legacy_bin_dir}/${name}"
            fi
        done
    fi
}

validate_share_dir() {
    if [ -z "${SHARE_DIR}" ] || [ "${SHARE_DIR}" = "/" ] || [ "${SHARE_DIR}" = "${HOME}" ]; then
        error "Unsafe ZILLIZ_HOME path: '${SHARE_DIR}'. Set ZILLIZ_HOME to a dedicated directory (e.g. ~/.local/share/zilliz)."
    fi
}

verify_checksum() {
    local dir="$1"
    local archive="$2"
    local sums_file="$3"

    local expected=""
    expected=$(awk -v f="${archive}" '$2 == f || $2 == ("*" f) { print tolower($1); exit }' "${sums_file}")
    if [ -z "${expected}" ]; then
        error "Archive ${archive} is missing from sha256sums.txt; refusing unverified installation."
    fi
    if ! printf '%s' "${expected}" | grep -Eq '^[0-9a-f]{64}$'; then
        error "Malformed SHA-256 entry '${expected}' in sha256sums.txt for ${archive}."
    fi

    local actual=""
    if has shasum; then
        actual=$(shasum -a 256 "${dir}/${archive}" | awk '{print tolower($1)}')
    elif has sha256sum; then
        actual=$(sha256sum "${dir}/${archive}" | awk '{print tolower($1)}')
    else
        error "Neither 'shasum' nor 'sha256sum' is available to verify archive integrity."
    fi

    if [ "${actual}" != "${expected}" ]; then
        error "Checksum verification failed for ${archive} (expected ${expected}, got ${actual})"
    fi
    info "Checksum verified (${actual})"
}

install_via_archive() {
    validate_share_dir
    local tag="${REQUESTED_VERSION}"
    if [ "${tag}" = "latest" ]; then
        if [ -n "${ZILLIZ_RELEASE_BASE_URL:-}" ]; then
            error "ZILLIZ_VERSION must be set explicitly when ZILLIZ_RELEASE_BASE_URL is used."
        fi
        info "Fetching latest release..."
        tag=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
              | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        [ -n "${tag}" ] || error "Failed to determine latest version from GitHub Releases"
    fi

    local version="${tag}"
    version="${version#zilliz-v}"
    version="${version#v}"
    case "${version}" in
        *[!0-9A-Za-z._-]*|"")
            error "Invalid version string: '${version}'"
            ;;
    esac
    case "${tag}" in
        zilliz-v*) ;;
        v*) tag="zilliz-${tag}" ;;
        *)  tag="zilliz-v${version}" ;;
    esac
    info "Version: ${version}"

    local target
    target=$(get_target_triple)
    local archive="${BIN_NAME}-${version}-${target}.tar.gz"
    local base_url="${ZILLIZ_RELEASE_BASE_URL:-https://github.com/${REPO}/releases/download/${tag}}"
    base_url="${base_url%/}"
    case "${base_url}" in
        https://*|file://*) ;;
        *) error "ZILLIZ_RELEASE_BASE_URL must use https:// (or file:// for local testing)." ;;
    esac
    local url="${base_url}/${archive}"

    TMPDIR_CLEANUP=$(mktemp -d)
    local tmpdir="${TMPDIR_CLEANUP}"
    trap 'rm -rf "${TMPDIR_CLEANUP}"' EXIT

    info "Downloading ${url}..."
    curl -fsSL "${url}" -o "${tmpdir}/${archive}"

    if [ "${ZILLIZ_SKIP_CHECKSUM:-0}" = "1" ]; then
        warn "Skipping checksum verification because ZILLIZ_SKIP_CHECKSUM=1."
    else
        local checksums_url="${base_url}/sha256sums.txt"
        info "Verifying checksum..."
        if ! curl -fsSL "${checksums_url}" -o "${tmpdir}/sha256sums.txt" 2>/dev/null; then
            error "Failed to download ${checksums_url}; refusing unverified installation (set ZILLIZ_SKIP_CHECKSUM=1 only for legacy pre-2.0 releases without sha256sums.txt)."
        fi
        verify_checksum "${tmpdir}" "${archive}" "${tmpdir}/sha256sums.txt"
    fi

    mkdir -p "${tmpdir}/extracted"
    tar -xzf "${tmpdir}/${archive}" -C "${tmpdir}/extracted"
    mkdir -p "${INSTALL_DIR}"

    if [ -d "${tmpdir}/extracted/_internal" ]; then
        # v2.0.0+ PyInstaller onedir bundle: replace only owned entries inside SHARE_DIR
        info "Installing runtime bundle to ${SHARE_DIR}..."
        mkdir -p "${SHARE_DIR}"
        local staging_internal="${SHARE_DIR}/.internal-staging-$$"
        rm -rf "${staging_internal}"
        mv "${tmpdir}/extracted/_internal" "${staging_internal}"
        install -m 755 "${tmpdir}/extracted/${BIN_NAME}" "${SHARE_DIR}/${BIN_NAME}"
        rm -f "${SHARE_DIR}/zz"
        ln -s "${BIN_NAME}" "${SHARE_DIR}/zz"
        rm -rf "${SHARE_DIR}/_internal"
        mv "${staging_internal}" "${SHARE_DIR}/_internal"

        rm -f "${INSTALL_DIR}/${BIN_NAME}" "${INSTALL_DIR}/zz"
        ln -s "${SHARE_DIR}/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"
        ln -s "${SHARE_DIR}/${BIN_NAME}" "${INSTALL_DIR}/zz"
    else
        # Legacy v1.x single-file binary archive
        info "Installing binary to ${INSTALL_DIR}..."
        rm -rf "${SHARE_DIR}/_internal" "${SHARE_DIR}/${BIN_NAME}" "${SHARE_DIR}/zz"
        rmdir "${SHARE_DIR}" 2>/dev/null || true
        rm -f "${INSTALL_DIR}/${BIN_NAME}" "${INSTALL_DIR}/zz"
        install -m 755 "${tmpdir}/extracted/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"
        ln -s "${INSTALL_DIR}/${BIN_NAME}" "${INSTALL_DIR}/zz"
    fi

    success "Installed ${BIN_NAME} ${version} (${INSTALL_DIR}/${BIN_NAME})"
}

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

        mkdir -p "$(dirname "${profile}")"
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

print_next_steps() {
    printf "\n"
    printf "${BOLD}Next steps:${RESET}\n"
    printf "  1. %-30s %s\n" "${BIN_NAME} login"             "Authenticate with Zilliz Cloud"
    printf "  2. %-30s %s\n" "${BIN_NAME} cluster list"      "See your clusters"
    printf "  3. %-30s %s\n" "${BIN_NAME} collection --help" "Manage collections"
    printf "\n"
    printf "${BOLD}Highlights:${RESET}\n"
    printf "  * %-14s - \`%s cluster create\` / \`modify\` / \`suspend\`\n"      "Clusters"     "${BIN_NAME}"
    printf "  * %-14s - bulk stage & load data with \`%s volume\` / \`import\`\n" "Data ingest"  "${BIN_NAME}"
    printf "  * %-14s - \`%s backup create\` / \`restore-cluster\`\n"            "Backup"       "${BIN_NAME}"
    printf "  * %-14s - \`%s vector search\` / \`query\` / \`insert\`\n"         "Vector ops"   "${BIN_NAME}"
    printf "  * %-14s - \`%s acl\` / \`%s user\` / \`%s role\`\n"                "Access ctrl"  "${BIN_NAME}" "${BIN_NAME}" "${BIN_NAME}"
    printf "\n"
    printf "${BOLD}Docs:${RESET} https://docs.zilliz.com/reference/cli/overview\n"
    printf "\n"
    printf "${BOLD}Plugins:${RESET}\n"
    printf "  * %-22s %s\n" "Zilliz Agent Plugin"   "https://github.com/zilliztech/zilliz-plugin"
    printf "  * %-22s %s\n" "Gemini CLI Extension"  "https://github.com/zilliztech/gemini-cli-extension"
    printf "  * %-22s %s\n" "Zilliz Skill"          "https://github.com/zilliztech/zilliz-skill"
    printf "  * %-22s %s\n" "Milvus Skill"          "https://github.com/zilliztech/milvus-skill"
}

uninstall() {
    validate_share_dir
    info "Uninstalling ${PACKAGE_NAME}..."
    cleanup_conflicting_installs

    for name in "${BIN_NAME}" "zz"; do
        if [ -f "${INSTALL_DIR}/${name}" ] || [ -L "${INSTALL_DIR}/${name}" ]; then
            rm -f "${INSTALL_DIR}/${name}"
            info "Removed ${INSTALL_DIR}/${name}"
        fi
    done

    if [ -d "${SHARE_DIR}" ]; then
        rm -rf "${SHARE_DIR}/_internal" "${SHARE_DIR}/${BIN_NAME}" "${SHARE_DIR}/zz"
        rmdir "${SHARE_DIR}" 2>/dev/null || true
        info "Removed runtime bundle from ${SHARE_DIR}"
    fi

    success "Uninstalled ${PACKAGE_NAME}"
    exit 0
}

main() {
    if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "uninstall" ]; then
        uninstall
    fi

    check_deps=0
    has curl || { error "'curl' is required to install Zilliz CLI."; check_deps=1; }
    has tar  || { error "'tar' is required to install Zilliz CLI."; check_deps=1; }
    [ "${check_deps}" -eq 0 ]

    printf "\n"
    printf "${BOLD}  Zilliz CLI Installer${RESET}\n"
    printf "  Manage Zilliz Cloud from your terminal\n"
    printf "\n"

    detect_platform
    info "Detected platform: ${OS}/${ARCH}"

    cleanup_conflicting_installs
    install_via_archive
    ensure_path

    printf "\n"
    if has "${BIN_NAME}"; then
        success "Installation complete!"
        print_next_steps
    else
        success "Installation complete!"
        warn "Open a new terminal or update PATH, then run '${BIN_NAME} --help' to get started."
        print_next_steps
    fi
    printf "\n"
}

main "$@"
