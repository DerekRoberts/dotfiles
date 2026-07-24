#!/usr/bin/env bash
# Dev Tooling Bootstrap Script (~/.local/bin)
# Installs/updates CLI tools required for BC Gov GHA & OpenShift development.

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    export PATH="${BIN_DIR}:${PATH}"
fi

# Force update toggle (e.g. UPDATE=1 ./setup.sh or ./bootstrap-tools.sh --update)
UPDATE="${UPDATE:-0}"
if [[ "${1:-}" == "--update" ]] || [[ "${1:-}" == "-u" ]]; then
    UPDATE="1"
fi

# Tool version targets (Default to "latest" for dynamic API lookup; overridable via ENV)
ACTIONLINT_VERSION="${ACTIONLINT_VERSION:-latest}"
YQ_VERSION="${YQ_VERSION:-latest}"
HADOLINT_VERSION="${HADOLINT_VERSION:-latest}"

# Detect OS
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "${OS}" in
    linux)
        OS_NAME="linux"
        HADO_OS="linux"
        ;;
    darwin)
        OS_NAME="darwin"
        HADO_OS="macos"
        ;;
    *) echo "❌ Unsupported OS: ${OS}" >&2; exit 1 ;;
esac

# Detect Architecture
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64|amd64)
        ARCH_YQ="amd64"
        ARCH_ACTIONLINT="amd64"
        ARCH_HADOLINT="x86_64"
        ;;
    aarch64|arm64)
        ARCH_YQ="arm64"
        ARCH_ACTIONLINT="arm64"
        ARCH_HADOLINT="arm64"
        ;;
    *) echo "❌ Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

# Helper: Resolve latest tag dynamically from GitHub API / redirect
resolve_latest_tag() {
    local repo="$1"
    local tag=""

    tag="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)"

    if [[ -z "${tag}" ]]; then
        tag="$(curl -fsSI "https://github.com/${repo}/releases/latest" 2>/dev/null | grep -i "^location:" | head -n 1 | sed -E 's/.*\/tag\/([^ \r\n]+).*/\1/' | tr -d '\r' || true)"
    fi

    if [[ -z "${tag}" ]]; then
        echo "❌ Unable to resolve latest release tag for ${repo}" >&2
        return 1
    fi

    echo "${tag}"
}

# Helper: Atomic binary download via mktemp
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

# Helper: Download and extract tarball binary atomically
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

    chmod +x "${tmp_dir}/${binary_name}"
    mv "${tmp_dir}/${binary_name}" "${dest}"
    trap - RETURN EXIT
}

# Helper: Safely query version string from managed binary
get_tool_version() {
    local cmd="$1"
    local bin_path="${BIN_DIR}/${cmd}"

    if [[ ! -x "${bin_path}" ]]; then
        echo "none"
        return
    fi

    case "${cmd}" in
        actionlint)
            "${bin_path}" -version 2>&1 | head -n 1
            ;;
        yq|hadolint)
            "${bin_path}" --version 2>&1
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Helper: Check if tool needs installation or update under ~/.local/bin
should_install_tool() {
    local cmd="$1"
    local target_ver="$2"

    if [[ "${UPDATE}" == "1" ]]; then
        return 0 # Force update requested
    fi

    local bin_path="${BIN_DIR}/${cmd}"
    if [[ ! -x "${bin_path}" ]]; then
        return 0 # Binary missing in ~/.local/bin
    fi

    local current_ver
    current_ver="$(get_tool_version "${cmd}")"
    
    local target_clean="${target_ver#v}"
    local current_clean="${current_ver#v}"

    if [[ "${current_clean}" != *"${target_clean}"* ]]; then
        echo " -> Version mismatch for ${cmd}: installed (${current_ver:-unknown}) != target (${target_ver})"
        return 0
    fi

    return 1 # Tool installed in ~/.local/bin and matches target version
}

echo "Checking & installing dev tools in ${BIN_DIR}..."

# 1. actionlint
TARGET_ACTIONLINT_VER="${ACTIONLINT_VERSION}"
if [[ "${TARGET_ACTIONLINT_VER}" == "latest" ]]; then
    TARGET_ACTIONLINT_VER="$(resolve_latest_tag "rhysd/actionlint")"
fi

if should_install_tool "actionlint" "${TARGET_ACTIONLINT_VER}"; then
    echo " -> Installing/Updating actionlint (${TARGET_ACTIONLINT_VER})..."
    ACTIONLINT_VER_CLEAN="${TARGET_ACTIONLINT_VER#v}"
    ACTIONLINT_TAR="actionlint_${ACTIONLINT_VER_CLEAN}_${OS_NAME}_${ARCH_ACTIONLINT}.tar.gz"
    ACTIONLINT_URL="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VER_CLEAN}/${ACTIONLINT_TAR}"
    download_tarball_binary "${ACTIONLINT_URL}" "actionlint" "${BIN_DIR}/actionlint"
else
    echo " -> actionlint: $(get_tool_version "actionlint") (up to date)"
fi

# 2. yq
TARGET_YQ_VER="${YQ_VERSION}"
if [[ "${TARGET_YQ_VER}" == "latest" ]]; then
    TARGET_YQ_VER="$(resolve_latest_tag "mikefarah/yq")"
fi
if [[ "${TARGET_YQ_VER}" != v* ]]; then
    TARGET_YQ_TAG="v${TARGET_YQ_VER}"
else
    TARGET_YQ_TAG="${TARGET_YQ_VER}"
fi

if should_install_tool "yq" "${TARGET_YQ_VER}"; then
    echo " -> Installing/Updating yq (${TARGET_YQ_TAG})..."
    YQ_URL="https://github.com/mikefarah/yq/releases/download/${TARGET_YQ_TAG}/yq_${OS_NAME}_${ARCH_YQ}"
    download_binary "${YQ_URL}" "${BIN_DIR}/yq"
else
    echo " -> yq: $(get_tool_version "yq") (up to date)"
fi

# 3. hadolint
TARGET_HADOLINT_VER="${HADOLINT_VERSION}"
if [[ "${TARGET_HADOLINT_VER}" == "latest" ]]; then
    TARGET_HADOLINT_VER="$(resolve_latest_tag "hadolint/hadolint")"
fi
if [[ "${TARGET_HADOLINT_VER}" != v* ]]; then
    TARGET_HADOLINT_TAG="v${TARGET_HADOLINT_VER}"
else
    TARGET_HADOLINT_TAG="${TARGET_HADOLINT_VER}"
fi

if should_install_tool "hadolint" "${TARGET_HADOLINT_VER}"; then
    echo " -> Installing/Updating hadolint (${TARGET_HADOLINT_TAG})..."
    HADOLINT_URL="https://github.com/hadolint/hadolint/releases/download/${TARGET_HADOLINT_TAG}/hadolint-${HADO_OS}-${ARCH_HADOLINT}"
    download_binary "${HADOLINT_URL}" "${BIN_DIR}/hadolint"
else
    echo " -> hadolint: $(get_tool_version "hadolint") (up to date)"
fi

echo "✅ All dev tools verified and ready in ${BIN_DIR}."
