#!/bin/bash
set -euo pipefail

echo "=== TPM 2.0 LUKS Enrollment ==="
echo "This script configures your system to automatically unlock your encrypted drive at boot."

if [[ $EUID -ne 0 ]]; then
   echo "This requires root privileges. Prompting for sudo..."
   exec sudo "$0" "$@"
fi

if ! command -v systemd-cryptenroll &>/dev/null; then
    echo "Error: systemd-cryptenroll not found." >&2
    exit 1
fi

if ! systemd-cryptenroll --tpm2-device=list | grep -q "tpm"; then
    echo "Error: No TPM 2.0 device found on this system." >&2
    exit 1
fi

LUKS_DEV="${1:-}"

if [[ -z "$LUKS_DEV" ]]; then
    mapfile -t luks_devices < <(lsblk -o NAME,TYPE,FSTYPE -p -l | awk '$3=="crypto_LUKS" {print $1}')
    if [[ ${#luks_devices[@]} -eq 0 ]]; then
        echo "Error: Could not detect any LUKS encrypted partitions." >&2
        exit 1
    elif [[ ${#luks_devices[@]} -eq 1 ]]; then
        LUKS_DEV="${luks_devices[0]}"
    else
        echo "Multiple LUKS devices found:"
        for i in "${!luks_devices[@]}"; do
            echo "  $((i+1))) ${luks_devices[$i]}"
        done
        read -r -p "Select device [1-${#luks_devices[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#luks_devices[@]} ]]; then
            LUKS_DEV="${luks_devices[$((choice-1))]}"
        else
            echo "Invalid selection." >&2
            exit 1
        fi
    fi
fi

echo "Detected LUKS device: $LUKS_DEV"
echo "Enrolling TPM 2.0 bound to PCR 7 (Secure Boot State)..."
echo "You will be prompted for your current LUKS disk decryption password."
echo "----------------------------------------------------------------------"

# Append the TPM token. If one exists, this adds another or overwrites depending on systemd version.
# To be safe and clean, we replace any existing TPM2 tokens and add a fresh one.
systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 "$LUKS_DEV"

echo "----------------------------------------------------------------------"
echo "Success! TPM 2.0 token added."
echo "On your next boot, systemd will attempt to automatically unlock the drive using the TPM chip."
