#!/bin/bash
set -euo pipefail

echo "=== TPM 2.0 LUKS Enrollment ==="
echo "This script configures your system to automatically unlock your encrypted drive at boot."

if [[ $EUID -ne 0 ]]; then
   echo "This requires root privileges. Promping for sudo..."
   exec sudo "$0" "$@"
fi

if ! command -v systemd-cryptenroll &>/dev/null; then
    echo "Error: systemd-cryptenroll not found."
    exit 1
fi

if ! systemd-cryptenroll --tpm2-device=list | grep -q "tpm"; then
    echo "Error: No TPM 2.0 device found on this system."
    exit 1
fi

LUKS_DEV=$(lsblk -o NAME,TYPE,FSTYPE -p -l | awk '$3=="crypto_LUKS" {print $1}' | head -n1)

if [[ -z "$LUKS_DEV" ]]; then
    echo "Error: Could not automatically detect a LUKS encrypted partition."
    exit 1
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
