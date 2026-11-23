#!/usr/bin/env bash
set -euo pipefail

# Read-only backup of critical factory/calibration & boot partitions from garnet.
# Must be run while the device is booted into OrangeFox/TWRP recovery (or rooted adb shell).
# NEVER writes to or erases any partition on the device.

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$PROJ/tools/bin:/opt/homebrew/bin:$PATH"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="$PROJ/backups/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo "Checking ADB connection..."
if ! adb get-state >/dev/null 2>&1; then
    echo "ERROR: No ADB device detected. Boot garnet into OrangeFox/TWRP recovery and connect USB." >&2
    exit 1
fi

UID_CHECK=$(adb shell id -u | tr -d '\r')
if [[ "$UID_CHECK" != "0" ]]; then
    echo "ERROR: ADB shell is not running as root (uid=$UID_CHECK). Boot into custom recovery (OrangeFox/TWRP) first." >&2
    exit 1
fi

PARTITIONS=(
    persist
    modemst1
    modemst2
    fsg
    boot_a
    vendor_boot_a
    dtbo_a
    vbmeta_a
    vbmeta_system_a
)

echo "Backing up critical partitions to $BACKUP_DIR..."
for part in "${PARTITIONS[@]}"; do
    DEV_NODE="/dev/block/bootdevice/by-name/$part"
    if adb shell "test -e $DEV_NODE"; then
        echo "  -> Pulling $part..."
        adb shell "dd if=$DEV_NODE bs=4M status=none" > "$BACKUP_DIR/${part}.img"
    else
        echo "  -> WARNING: $DEV_NODE not found on device, skipping."
    fi
done

echo "Generating SHA256 checksums..."
(cd "$BACKUP_DIR" && shasum -a 256 *.img > SHA256SUMS.txt)
ls -lh "$BACKUP_DIR"
echo "Backup completed safely at: $BACKUP_DIR"
