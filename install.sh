#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="zilliz-cli"
REPO="zilliztech/zilliz-cli"
INSTALL_DIR="${HOME}/.local/bin"

info()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
error() { printf '\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- Currently: Install via Python ----------
install_via_python() {
    if command -v pipx &>/dev/null; then
        info "Installing ${PACKAGE_NAME} via pipx..."
        pipx install "${PACKAGE_NAME}" --force
    elif command -v pip3 &>/dev/null; then
        info "Installing ${PACKAGE_NAME} via pip3..."
        pip3 install --user "${PACKAGE_NAME}"
    elif command -v pip &>/dev/null; then
        info "Installing ${PACKAGE_NAME} via pip..."
        pip install --user "${PACKAGE_NAME}"
    else
        error "Python (pip/pipx) not found. Please install Python 3.8+ first."
    fi
}

# ---------- When switching to Rust binary in the future: Enable this line ----------
# install_via_binary() {
#     OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
#     ARCH="$(uname -m)"
#     case "${ARCH}" in
#         x86_64)  ARCH="x86_64" ;;
#         aarch64|arm64) ARCH="aarch64" ;;
#         *) error "Unsupported architecture: ${ARCH}" ;;
#     esac
#
#     VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
#                | grep '"tag_name"' | cut -d'"' -f4)"
#
#     URL="https://github.com/${REPO}/releases/download/${VERSION}/${PACKAGE_NAME}-${OS}-${ARCH}.tar.gz"
#     info "Downloading ${PACKAGE_NAME} ${VERSION} for ${OS}/${ARCH}..."
#
#     mkdir -p "${INSTALL_DIR}"
#     curl -fsSL "${URL}" | tar -xz -C "${INSTALL_DIR}"
#     chmod +x "${INSTALL_DIR}/${PACKAGE_NAME}"
#
#     info "Installed to ${INSTALL_DIR}/${PACKAGE_NAME}"
# }

# ---------- Main process ----------
info "Installing ${PACKAGE_NAME}..."

install_via_python        # now
# install_via_binary      # When switching in the future: Comment out the above and enable this line

# Check PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "${INSTALL_DIR}"; then
    info "Add this to your shell profile:"
    info "  export PATH=\"${INSTALL_DIR}:\$PATH\""
fi

info "Done! Run '${PACKAGE_NAME} --help' to get started."
