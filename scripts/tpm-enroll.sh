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

# PCR 7 alone measures Secure Boot state, not the kernel or initrd that get
# booted. Anything Secure Boot already trusts can therefore ask the TPM to
# release the key — including a different signed kernel with your disk attached.
# Adding PCR 11 covers the booted kernel, but then every kernel update
# invalidates the token and you re-run this script, so it stays opt-in.
TPM2_PCRS="${TPM2_PCRS:-7}"
TPM2_PIN="${TPM2_PIN:-no}"

echo "Detected LUKS device: $LUKS_DEV"
echo "Enrolling TPM 2.0 bound to PCR(s): $TPM2_PCRS"
if [[ "$TPM2_PCRS" == "7" && "$TPM2_PIN" != "yes" ]]; then
    echo ""
    echo "  NOTE: PCR 7 measures Secure Boot state only. Unlocking needs no"
    echo "  secret from you, so someone with the machine and a signed kernel of"
    echo "  their choosing can have the TPM hand over the key. To harden:"
    echo "    TPM2_PIN=yes  $0     # require a PIN at boot (recommended)"
    echo "    TPM2_PCRS=7+11 $0    # also bind the booted kernel"
    echo "                         # (re-run after every kernel update)"
fi
echo ""
echo "You will be prompted for your current LUKS disk decryption password."
echo "----------------------------------------------------------------------"

# Replace any existing TPM2 token rather than stacking a second one.
ENROLL_ARGS=(--wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs="$TPM2_PCRS")
if [[ "$TPM2_PIN" == "yes" ]]; then
    ENROLL_ARGS+=(--tpm2-with-pin=yes)
fi

systemd-cryptenroll "${ENROLL_ARGS[@]}" "$LUKS_DEV"

echo "----------------------------------------------------------------------"
echo "Success! TPM 2.0 token added (PCRs: $TPM2_PCRS, PIN: $TPM2_PIN)."
echo "On your next boot, systemd will attempt to automatically unlock the drive using the TPM chip."
if [[ "$TPM2_PCRS" == *11* ]]; then
    echo "Re-run this script after each kernel update to refresh the PCR 11 policy."
fi
