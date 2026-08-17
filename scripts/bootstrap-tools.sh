#!/usr/bin/env bash
# bootstrap-tools.sh — CLI tool installer for tools not in nixpkgs at target cadence.
#
# Currently manages:
#   - oc (OpenShift CLI) — tracks Red Hat's official release, not nixpkgs lag
#
# hadolint, actionlint, and yq-go are declared in config/home-manager/home.nix
# and installed via: home-manager switch --flake .#dev
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
    linux)  OS_NAME="linux"  ;;
    darwin) OS_NAME="darwin" ;;
    *) echo "❌ Unsupported OS: ${OS}" >&2; exit 1 ;;
esac

# Detect Architecture
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64|amd64)  ARCH_OC="amd64" ;;
    aarch64|arm64) ARCH_OC="arm64" ;;
    *) echo "❌ Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

# ── Helpers ──────────────────────────────────────────────────────────────────

# Resolve latest GitHub release tag via API (with redirect fallback)
resolve_latest_tag() {
    local repo="$1"
    local tag=""

    tag="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)"

    if [[ -z "${tag}" ]]; then
        tag="$(curl -fsSI "https://github.com/${repo}/releases/latest" 2>/dev/null \
            | grep -i "^location:" | head -n 1 \
            | sed -E 's/.*\/tag\/([^ \r\n]+).*/\1/' | tr -d '\r' || true)"
    fi

    if [[ -z "${tag}" ]]; then
        echo "❌ Unable to resolve latest release tag for ${repo}" >&2
        return 1
    fi

    echo "${tag}"
}

# Atomic binary download via mktemp staging
download_binary() {
    local url="$1"
    local dest="$2"
    local tmp_file
    tmp_file="$(mktemp "${BIN_DIR}/.tmp.XXXXXX")"
    trap 'rm -f "${tmp_file}"' RETURN EXIT

    if ! curl -fsSL "${url}" -o "${tmp_file}"; then
        echo "❌ Download failed for ${url}" >&2
        return 1
    fi

    chmod +x "${tmp_file}"
    mv "${tmp_file}" "${dest}"
    trap - RETURN EXIT
}

# Download and extract tarball, atomically placing a single binary
download_tarball_binary() {
    local url="$1"
    local binary_name="$2"
    local dest="$3"
    local tmp_dir
    tmp_dir="$(mktemp -d "${BIN_DIR}/.tmpdir.XXXXXX")"
    trap 'rm -rf "${tmp_dir}"' RETURN EXIT

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

# Safely query version string from a managed binary
get_tool_version() {
    local cmd="$1"
    local bin_path="${BIN_DIR}/${cmd}"

    if [[ ! -x "${bin_path}" ]]; then
        echo "none"
        return
    fi

    case "${cmd}" in
        oc) "${bin_path}" version --client 2>&1 | head -n 1 ;;
        *)  echo "unknown" ;;
    esac
}

# Check if tool needs install or update
should_install_tool() {
    local cmd="$1"
    local target_ver="$2"

    if [[ "${UPDATE}" == "1" ]]; then
        return 0  # force update
    fi

    local bin_path="${BIN_DIR}/${cmd}"
    if [[ ! -x "${bin_path}" ]]; then
        return 0  # binary missing
    fi

    local current_ver target_clean current_clean
    current_ver="$(get_tool_version "${cmd}")"
    target_clean="${target_ver#v}"
    current_clean="${current_ver#v}"

    if [[ "${current_clean}" != *"${target_clean}"* ]]; then
        echo " -> Version mismatch for ${cmd}: installed (${current_ver:-unknown}) != target (${target_ver})"
        return 0
    fi

    return 1  # up to date
}

# ── oc (OpenShift CLI) ───────────────────────────────────────────────────────
# oc is not in nixpkgs at Red Hat's release cadence; managed here as a binary.

install_oc() {
    local TARGET_OC_VER="${OC_VERSION}"

    if [[ "${TARGET_OC_VER}" == "latest" ]]; then
        # oc releases are in openshift/oc on GitHub
        TARGET_OC_VER="$(resolve_latest_tag "openshift/oc")"
    fi

    if should_install_tool "oc" "${TARGET_OC_VER}"; then
        echo " -> Installing/Updating oc (${TARGET_OC_VER})..."
        local VER_CLEAN="${TARGET_OC_VER#v}"
        local OC_TAR="openshift-client-${OS_NAME}-${ARCH_OC}-${VER_CLEAN}.tar.gz"
        local OC_URL="https://github.com/openshift/oc/releases/download/v${VER_CLEAN}/${OC_TAR}"
        download_tarball_binary "${OC_URL}" "oc" "${BIN_DIR}/oc"

        # Fix SELinux label on Kinoite
        if command -v restorecon &>/dev/null; then
            restorecon -v "${BIN_DIR}/oc" 2>/dev/null || true
        fi
    else
        echo " -> oc: $(get_tool_version "oc") (up to date)"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

echo "Checking & installing CLI tools in ${BIN_DIR}..."

install_oc

echo "✅ All CLI tools verified and ready in ${BIN_DIR}."
