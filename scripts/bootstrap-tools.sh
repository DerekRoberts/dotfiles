#!/usr/bin/env bash
# bootstrap-tools.sh — CLI tool installer
#
# Currently manages:
#   - oc (OpenShift CLI) — tracks Red Hat's official release mirror
#
# Usage:
#   scripts/bootstrap-tools.sh           # install/verify all managed tools
#   scripts/bootstrap-tools.sh --update  # force re-download latest releases
#   UPDATE=1 scripts/bootstrap-tools.sh  # same via env var

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    export PATH="${BIN_DIR}:${PATH}"
fi

# Force update toggle
UPDATE="${UPDATE:-0}"
if [[ "${1:-}" == "--update" ]] || [[ "${1:-}" == "-u" ]]; then
    UPDATE="1"
fi

# Tool version targets (default "latest" = dynamic GitHub API lookup)
OC_VERSION="${OC_VERSION:-latest}"

# Detect OS
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "${OS}" in
    linux) ;;
    *) echo "❌ Unsupported OS: ${OS}" >&2; exit 1 ;;
esac

# Detect Architecture
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64|amd64) ;;
    *) echo "❌ Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

# ── Helpers ──────────────────────────────────────────────────────────────────

# Download and extract tarball, atomically placing a single binary
download_tarball_binary() {
    local url="$1"
    local binary_name="$2"
    local dest="$3"
    local tmp_dir
    tmp_dir="$(mktemp -d "${BIN_DIR}/.tmpdir.XXXXXX")"
    trap 'rm -rf "${tmp_dir:-}"' RETURN EXIT

    if ! curl -fsSL "${url}" | tar -xz -C "${tmp_dir}"; then
        echo "❌ Failed to download/extract ${url}" >&2
        return 1
    fi

    local bin_path
    bin_path="$(find "${tmp_dir}" -type f -name "${binary_name}" | head -n 1)"
    if [[ -z "${bin_path}" ]]; then
        echo "❌ Binary '${binary_name}' not found in archive" >&2
        return 1
    fi

    chmod +x "${bin_path}"
    mv "${bin_path}" "${dest}"
    trap - RETURN EXIT
}

# ── Tool installers ──────────────────────────────────────────────────────────

# oc (OpenShift CLI)
install_oc() {
    local TARGET_OC_VER="${OC_VERSION}"

    if [[ "${TARGET_OC_VER}" == "latest" ]]; then
        TARGET_OC_VER=$(curl -fsSL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/release.txt" | grep "Version:" | awk '{print $2}')
    fi

    # oc version --client returns e.g. "Client Version: 4.14.0"
    local CURRENT_VER
    CURRENT_VER="$(oc version --client 2>/dev/null | grep "Client Version:" | awk '{print $3}' || echo "none")"

    if [[ "${CURRENT_VER}" != "${TARGET_OC_VER}" ]]; then
        echo " -> Installing/Updating oc (${TARGET_OC_VER})..."
        local OC_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${TARGET_OC_VER}/openshift-client-linux.tar.gz"
        download_tarball_binary "${OC_URL}" "oc" "${BIN_DIR}/oc"
        
        if command -v restorecon &>/dev/null; then
            restorecon "${BIN_DIR}/oc" 2>/dev/null || true
        fi
    else
        echo " -> oc: ${CURRENT_VER} (up to date)"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

echo "Checking & installing CLI tools in ${BIN_DIR}..."

install_oc

echo "✅ All CLI tools verified and ready in ${BIN_DIR}."
