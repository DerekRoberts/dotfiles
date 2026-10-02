#!/usr/bin/env bash
# swap.sh — zram cap + btrfs disk swapfile (tier-2 overflow)
#
# Usage: sudo scripts/setup/swap.sh
#
# Idempotent. Safe on Fedora Kinoite (btrfs /var).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

SWAPFILE=/var/lib/swap/swapfile
SWAP_SIZE=16G
DISK_SWAP_PRIO=10
ZRAM_DEST=/etc/systemd/zram-generator.conf
FSTAB_MARK=/var/lib/swap/swapfile

require_root() {
    if [[ "${EUID:-}" -ne 0 ]]; then
        echo "Run as root: sudo $DOTFILES_DIR/scripts/setup/swap.sh" >&2
        exit 1
    fi
}

require_btrfs_var() {
    local fstype
    fstype="$(findmnt -no FSTYPE /var 2>/dev/null || true)"
    if [[ "$fstype" != btrfs ]]; then
        echo "Expected btrfs on /var; got '${fstype:-unknown}'. Aborting." >&2
        exit 1
    fi
}

install_zram_config() {
    section "zram"
    install -m 644 "$DOTFILES_DIR/config/zram-generator.conf" "$ZRAM_DEST"
    success "Installed $ZRAM_DEST (zram-size = min(ram, 12288))"
}

ensure_disk_swapfile() {
    section "disk swapfile"
    mkdir -p "$(dirname "$SWAPFILE")"
    if [[ -f "$SWAPFILE" ]]; then
        success "Swapfile already exists: $SWAPFILE"
        return 0
    fi
    info "Creating $SWAP_SIZE btrfs swapfile at $SWAPFILE ..."
    btrfs filesystem mkswapfile -s "$SWAP_SIZE" "$SWAPFILE"
    success "Created $SWAPFILE"
}

ensure_fstab() {
    if grep -qF "$FSTAB_MARK" /etc/fstab 2>/dev/null; then
        success "fstab already lists $SWAPFILE"
        return 0
    fi
    printf '%s none swap sw,pri=%s,nofail,x-systemd.device-timeout=0 0 0\n' \
        "$SWAPFILE" "$DISK_SWAP_PRIO" >> /etc/fstab
    success "Added $SWAPFILE to /etc/fstab (pri=$DISK_SWAP_PRIO)"
}

activate_disk_swap() {
    if swapon --show | grep -qF "$SWAPFILE"; then
        success "Disk swap already active"
        return 0
    fi
    swapon --priority "$DISK_SWAP_PRIO" "$SWAPFILE"
    success "Activated disk swap"
}

reload_zram() {
    section "reload zram"
    systemctl daemon-reload
    if ! swapoff /dev/zram0 2>/dev/null; then
        warn "Could not swapoff zram0 (memory pressure). Reboot to apply larger zram."
        return 0
    fi
    systemctl restart systemd-zram-setup@zram0.service
    swapon /dev/zram0
    success "zram0 recreated from new config"
}

verify() {
    section "verify"
    swapon --show
    free -h | head -2
    local zram_size
    zram_size="$(swapon --noheading --show=SIZE --bytes /dev/zram0 2>/dev/null || echo 0)"
    if [[ "$zram_size" -lt 10000000000 ]]; then
        warn "zram0 is still under ~10GiB; reboot if you expected 12GiB cap."
    fi
}

main() {
    require_root
    require_btrfs_var
    install_zram_config
    ensure_disk_swapfile
    ensure_fstab
    activate_disk_swap
    reload_zram
    verify
}

main "$@"
