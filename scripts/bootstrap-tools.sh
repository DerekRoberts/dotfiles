#!/usr/bin/env bash
# Dev Tooling Bootstrap Script (~/.local/bin)
# Installs/updates CLI tools required for BC Gov GHA & OpenShift development.

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    export PATH="${BIN_DIR}:${PATH}"
fi

# Tool versions (Explicit defaults, overridable via ENV)
ACTIONLINT_VERSION="${ACTIONLINT_VERSION:-1.7.7}"
YQ_VERSION="${YQ_VERSION:-v4.44.1}"
HADOLINT_VERSION="${HADOLINT_VERSION:-v2.12.0}"

# Detect OS
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "${OS}" in
    linux)  OS_NAME="linux" ;;
    darwin) OS_NAME="darwin" ;;
    *) echo "❌ Unsupported OS: ${OS}" >&2; exit 1 ;;
esac

# Detect Architecture
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64|amd64)
        ARCH_YQ="amd64"
        ARCH_HADOLINT="x86_64"
        ARCH_ACTIONLINT="amd64"
        ;;
    aarch64|arm64)
        ARCH_YQ="arm64"
        ARCH_HADOLINT="x86_64"
        ARCH_ACTIONLINT="arm64"
        ;;
    *) echo "❌ Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

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

echo "Checking & installing dev tools in ${BIN_DIR}..."

# 1. actionlint
if ! command -v actionlint &>/dev/null; then
    echo " -> Installing actionlint (${ACTIONLINT_VERSION})..."
    ACTIONLINT_TAR="actionlint_${ACTIONLINT_VERSION}_${OS_NAME}_${ARCH_ACTIONLINT}.tar.gz"
    ACTIONLINT_URL="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${ACTIONLINT_TAR}"
    download_tarball_binary "${ACTIONLINT_URL}" "actionlint" "${BIN_DIR}/actionlint"
else
    echo " -> actionlint: $(actionlint -version 2>&1 | head -n 1)"
fi

# 2. yq
if ! command -v yq &>/dev/null; then
    echo " -> Installing yq (${YQ_VERSION})..."
    YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${OS_NAME}_${ARCH_YQ}"
    download_binary "${YQ_URL}" "${BIN_DIR}/yq"
else
    echo " -> yq: $(yq --version 2>&1)"
fi

# 3. hadolint
if ! command -v hadolint &>/dev/null; then
    echo " -> Installing hadolint (${HADOLINT_VERSION})..."
    HADO_OS="$(tr '[:lower:]' '[:upper:]' <<< "${OS_NAME:0:1}")${OS_NAME:1}"
    HADOLINT_URL="https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-${HADO_OS}-${ARCH_HADOLINT}"
    download_binary "${HADOLINT_URL}" "${BIN_DIR}/hadolint"
else
    echo " -> hadolint: $(hadolint --version 2>&1)"
fi

echo "✅ All dev tools verified and ready in ${BIN_DIR}."
