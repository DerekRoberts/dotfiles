#!/usr/bin/env bash
# test-security-hardening.sh — firewall_needs_hardening, harden_security,
# tokenless GitHub MCP config, and permission checks (all external tools stubbed).
# Usage: bash scripts/test-security-hardening.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0

ok()     { echo "ok   $1"; }
fail()   { echo "FAIL $1"; fails=1; }
check()  { local name="$1"; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }
refute() { local name="$1"; shift; if "$@"; then fail "$name"; else ok "$name"; fi; }

export HOME="$TMP/home"
mkdir -p "$HOME/.config/gh" "$TMP/bin"
chmod 751 "$HOME/.config/gh"

ORIG_PATH="$PATH"
export PATH="$TMP/bin:$ORIG_PATH"

# Stub firewall-cmd and systemctl driven by env vars
cat > "$TMP/bin/firewall-cmd" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --state)
        [[ "${FW_RUNNING:-1}" -eq 1 ]] && { echo running; exit 0; } || exit 1 ;;
    --get-default-zone)
        echo "${FW_ZONE:-FedoraWorkstation}" ;;
    --info-service=kdeconnect)
        [[ "${FW_HAS_KDECONNECT:-1}" -eq 1 ]] && exit 0 || exit 1 ;;
    --zone=public)
        case "${2:-}" in
            --query-service=ssh)
                if [[ "${3:-}" == "--permanent" ]]; then
                    [[ "${FW_SSH_PERM:-1}" -eq 1 ]] && { echo yes; exit 0; } || exit 1
                else
                    [[ "${FW_SSH_RUN:-1}" -eq 1 ]] && { echo yes; exit 0; } || exit 1
                fi ;;
            --query-service=kdeconnect)
                if [[ "${3:-}" == "--permanent" ]]; then
                    [[ "${FW_KDE_PERM:-0}" -eq 1 ]] && { echo yes; exit 0; } || exit 1
                else
                    [[ "${FW_KDE_RUN:-0}" -eq 1 ]] && { echo yes; exit 0; } || exit 1
                fi ;;
        esac ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/firewall-cmd"

cat > "$TMP/bin/systemctl" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" ]]; then
    case "${3:-}" in
        sshd)        [[ "${SSHD_ACTIVE:-0}" -eq 1 ]]; exit $? ;;
        sshd.socket) [[ "${SSHD_SOCKET_ACTIVE:-0}" -eq 1 ]]; exit $? ;;
    esac
fi
exit 0
EOF
chmod +x "$TMP/bin/systemctl"

cat > "$TMP/bin/sudo" << 'EOF'
#!/usr/bin/env bash
echo "$*" >> "${SUDO_LOG:?}"
exit 0
EOF
chmod +x "$TMP/bin/sudo"

# shellcheck source=scripts/lib.sh
. "$REPO/scripts/lib.sh"

# ── firewall_needs_hardening ─────────────────────────────────────────────────

FW_RUNNING=0 refute "firewall_needs_hardening false when firewalld stopped" firewall_needs_hardening
FW_RUNNING=1 FW_ZONE=FedoraWorkstation check "firewall_needs_hardening true for FedoraWorkstation" firewall_needs_hardening
FW_RUNNING=1 FW_ZONE=public FW_SSH_RUN=1 FW_SSH_PERM=1 FW_KDE_RUN=1 FW_KDE_PERM=1 SSHD_ACTIVE=0 check "firewall_needs_hardening true for public+ssh when sshd inactive" firewall_needs_hardening
FW_RUNNING=1 FW_ZONE=public FW_SSH_RUN=0 FW_SSH_PERM=0 FW_KDE_RUN=0 FW_KDE_PERM=0 SSHD_ACTIVE=0 check "firewall_needs_hardening true when kdeconnect missing from public" firewall_needs_hardening
FW_RUNNING=1 FW_ZONE=public FW_SSH_RUN=1 FW_SSH_PERM=1 FW_KDE_RUN=1 FW_KDE_PERM=1 SSHD_ACTIVE=1 refute "firewall_needs_hardening false when sshd active and kdeconnect set" firewall_needs_hardening
FW_RUNNING=1 FW_ZONE=public FW_SSH_RUN=1 FW_SSH_PERM=1 FW_KDE_RUN=1 FW_KDE_PERM=1 SSHD_ACTIVE=0 SSHD_SOCKET_ACTIVE=1 refute "firewall_needs_hardening false when sshd.socket active and kdeconnect set" firewall_needs_hardening
FW_RUNNING=1 FW_ZONE=public FW_SSH_RUN=0 FW_SSH_PERM=0 FW_KDE_RUN=1 FW_KDE_PERM=1 SSHD_ACTIVE=0 refute "firewall_needs_hardening false when already hardened" firewall_needs_hardening
FW_RUNNING=1 FW_ZONE=drop refute "firewall_needs_hardening false for custom zone" firewall_needs_hardening

# ── harden_security (core.sh) ────────────────────────────────────────────────

# shellcheck source=scripts/setup/core.sh
. "$REPO/scripts/setup/core.sh"

export SUDO_LOG="$TMP/sudo.log"
: > "$SUDO_LOG"
FW_RUNNING=1 FW_ZONE=FedoraWorkstation FW_SSH_RUN=1 FW_SSH_PERM=1 FW_KDE_RUN=0 FW_KDE_PERM=0 SSHD_ACTIVE=0 SSHD_SOCKET_ACTIVE=0 \
    harden_security >/dev/null

check "harden_security restricts ~/.config/gh to 700" \
    test "$(stat -c '%a' "$HOME/.config/gh")" = "700"
check "harden_security switches default zone to public" \
    grep -qxF "firewall-cmd --set-default-zone=public" "$SUDO_LOG"
check "harden_security removes ssh permanently" \
    grep -qxF "firewall-cmd --zone=public --remove-service=ssh --permanent" "$SUDO_LOG"
check "harden_security removes ssh at runtime without full reload" \
    grep -qxF "firewall-cmd --zone=public --remove-service=ssh" "$SUDO_LOG"
check "harden_security adds kdeconnect permanently" \
    grep -qxF "firewall-cmd --zone=public --add-service=kdeconnect --permanent" "$SUDO_LOG"
check "harden_security adds kdeconnect at runtime" \
    grep -qxF "firewall-cmd --zone=public --add-service=kdeconnect" "$SUDO_LOG"
refute "harden_security avoids full firewall reload" \
    grep -qxF "firewall-cmd --reload" "$SUDO_LOG"

: > "$SUDO_LOG"
FW_RUNNING=1 FW_ZONE=FedoraWorkstation FW_SSH_RUN=1 FW_SSH_PERM=1 FW_KDE_RUN=1 FW_KDE_PERM=1 SSHD_ACTIVE=0 SSHD_SOCKET_ACTIVE=1 \
    harden_security >/dev/null
refute "harden_security preserves ssh when sshd.socket is active" \
    grep -q -- "--remove-service=ssh" "$SUDO_LOG"

: > "$SUDO_LOG"
FW_RUNNING=1 FW_ZONE=public FW_SSH_RUN=0 FW_SSH_PERM=0 FW_KDE_RUN=1 FW_KDE_PERM=1 SSHD_ACTIVE=0 \
    harden_security >/dev/null
check "harden_security skips sudo when already hardened" \
    test ! -s "$SUDO_LOG"

# ── write_github_mcp_config (ai.sh) ──────────────────────────────────────────

# shellcheck source=scripts/setup/ai.sh
. "$REPO/scripts/setup/ai.sh"

mcp_cfg="$HOME/.gemini/config/mcp_config.json"
mkdir -p "$(dirname "$mcp_cfg")"
cat > "$mcp_cfg" << 'EOF'
{"mcpServers":{"other":{"command":"echo"},"github":{"command":"npx","args":["-y","@modelcontextprotocol/server-github@2025.4.8"],"env":{"GITHUB_PERSONAL_ACCESS_TOKEN":"secret-token"}}}}
EOF

write_github_mcp_config "$mcp_cfg" "$HOME/.local/share/dotfiles/bin/mcp-github"
check "mcp_config dir restricted to 700" \
    test "$(stat -c '%a' "$(dirname "$mcp_cfg")")" = "700"
check "mcp_config.json restricted to 600" \
    test "$(stat -c '%a' "$mcp_cfg")" = "600"
refute "mcp_config.json drops plaintext token" \
    grep -qE "GITHUB_PERSONAL_ACCESS_TOKEN|secret-token" "$mcp_cfg"
check "mcp_config.json preserves sibling mcpServers" \
    jq -e '.mcpServers.other.command == "echo"' "$mcp_cfg" >/dev/null
got_cmd="$(jq -r '.mcpServers.github | if keys == ["command"] then .command else "" end' "$mcp_cfg")"
check "mcp_config.json sets wrapper command" \
    test "$got_cmd" = "$HOME/.local/share/dotfiles/bin/mcp-github"

# ── mcp-github.sh ────────────────────────────────────────────────────────────

cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "token" && "${3:-}" == "--hostname" && "${4:-}" == "github.com" ]]; then
    [[ -z "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]] || exit 9
    printf '%s\n' "${MOCK_GH_TOKEN:-}"
    exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/gh"

cat > "$TMP/bin/npx" << 'EOF'
#!/usr/bin/env bash
printf '%s\n%s\n' "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" "$*" > "${NPX_LOG:?}"
EOF
chmod +x "$TMP/bin/npx"

export NPX_LOG="$TMP/npx.log"
GH_HOST="git.corp.example" GITHUB_TOKEN="ambient-bad" GH_TOKEN="ambient-bad-2" MOCK_GH_TOKEN="live-gh-token" \
    bash "$REPO/scripts/mcp-github.sh" --extra-arg
check "mcp-github exports gh auth token in-memory" \
    grep -qxF "live-gh-token" "$NPX_LOG"
check "mcp-github launches pinned github mcp package" \
    grep -qxF -- "-y @modelcontextprotocol/server-github@2025.4.8 --extra-arg" "$NPX_LOG"

refute "mcp-github fails when gh auth token is empty" \
    env MOCK_GH_TOKEN="" bash "$REPO/scripts/mcp-github.sh" 2>/dev/null

[[ "$fails" -eq 0 ]]
