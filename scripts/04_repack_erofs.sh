#!/usr/bin/env bash
set -euo pipefail

# Phase 4 Packaging: Repacks modified ColorOS 17 partitions into EROFS (LZ4HC level 9),
# audits total dynamic partition footprint against garnet's 9.0 GiB super limit,
# and generates a safe fastboot/fastbootd flashing script.

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$PROJ/scripts/00_mount_workspace.sh"

PORT="$MNT_POINT/port_build"
OUT_DIR="$PROJ/output"
mkdir -p "$OUT_DIR"

echo "=== [1/4] Repacking modified partitions with mkfs.erofs (-zlz4hc,9) ==="
for part in system system_ext product; do
    SRC_DIR="$PORT/$part"
    OUT_IMG="$OUT_DIR/${part}.img"
    if [[ ! -d "$SRC_DIR" ]]; then
        echo "ERROR: $SRC_DIR does not exist. Run scripts/03_merge_and_patch_port.sh first." >&2
        exit 1
    fi
    echo "  -> Packing ${part}.img ..."
    rm -f "$OUT_IMG"
    MNT_ARG="/$part"
    if [[ "$part" == "system" ]]; then
        MNT_ARG="/"
    fi
    mkfs.erofs -b4096 -zlz4hc,9 --all-root --mount-point="$MNT_ARG" "$OUT_IMG" "$SRC_DIR"
done

echo "=== [2/4] Copying garnet base and patched boot/vendor images ==="
for img in boot.img vendor_boot.img dtbo.img vbmeta.img vbmeta_system.img vendor.img vendor_dlkm.img odm.img; do
    if [[ -f "$PORT/stock_images/$img" ]]; then
        cp -f "$PORT/stock_images/$img" "$OUT_DIR/$img"
    else
        echo "  -> WARNING: $img not found in $PORT/stock_images"
    fi
done

echo "=== [3/4] Auditing Dynamic Partition sizes against BOARD_QTI_DYNAMIC_PARTITIONS_SIZE ($BOARD_QTI_DYNAMIC_PARTITIONS_SIZE bytes) ==="
TOTAL_BYTES=0
for part in system system_ext product vendor vendor_dlkm odm; do
    IMG_PATH="$OUT_DIR/${part}.img"
    if [[ -f "$IMG_PATH" ]]; then
        SZ=$(stat -f%z "$IMG_PATH")
        TOTAL_BYTES=$((TOTAL_BYTES + SZ))
        printf "  %-14s : %12d bytes (%6.2f MiB)\n" "${part}.img" "$SZ" "$(echo "$SZ / 1048576" | bc -l)"
    fi
done

printf "  %-14s : %12d bytes (%6.2f GiB)\n" "TOTAL DYNAMIC" "$TOTAL_BYTES" "$(echo "$TOTAL_BYTES / 1073741824" | bc -l)"
printf "  %-14s : %12d bytes (%6.2f GiB)\n" "GARNET LIMIT" "$BOARD_QTI_DYNAMIC_PARTITIONS_SIZE" "$(echo "$BOARD_QTI_DYNAMIC_PARTITIONS_SIZE / 1073741824" | bc -l)"

if (( TOTAL_BYTES >= BOARD_QTI_DYNAMIC_PARTITIONS_SIZE )); then
    echo "ERROR: Total dynamic partition size ($TOTAL_BYTES bytes) exceeds garnet limit ($BOARD_QTI_DYNAMIC_PARTITIONS_SIZE bytes)!" >&2
    echo "Strip redundant apps/media from system/my_bigball/my_stock and re-run." >&2
    exit 1
fi
echo "SIZE CHECK PASSED: Fits inside garnet super partition."

echo "=== [4/4] Generating safe fastboot/fastbootd flashing script ==="
cat << 'EOF' > "$OUT_DIR/flash_fastbootd.sh"
#!/usr/bin/env bash
set -euo pipefail

# Safe Flasher for Project Garnet (ColorOS 17)
# NEVER modifies persist, modemst1, modemst2, or fsg.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "1. Setting active slot A and flashing bootloader-level partitions (boot_a, vendor_boot_a, dtbo_a, vbmeta_a)..."
fastboot set_active a
fastboot --disable-verity --disable-verification flash vbmeta_a vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_system_a vbmeta_system.img
fastboot flash boot_a boot.img
fastboot flash vendor_boot_a vendor_boot.img
fastboot flash dtbo_a dtbo.img

echo "2. Rebooting into userspace fastbootd..."
fastboot reboot fastboot

echo "3. Waiting for fastbootd..."
IS_USERSPACE=""
for _ in $(seq 1 15); do
    sleep 2
    IS_USERSPACE=$(fastboot getvar is-userspace 2>&1 || true)
    if echo "$IS_USERSPACE" | grep -qi "yes"; then
        break
    fi
done
if ! echo "$IS_USERSPACE" | grep -qi "yes"; then
    echo "ERROR: Device did not enter fastbootd userspace mode!" >&2
    exit 1
fi

echo "4. Deleting all existing logical partitions inside super..."
EXISTING_LOGICAL=$(fastboot getvar all 2>&1 | tr -d '\r' | sed -nE 's/.*is-logical:([^:]+):yes/\1/p' | sort -u)
for lp in $EXISTING_LOGICAL; do
    echo "  -> Deleting logical partition $lp..."
    fastboot delete-logical-partition "$lp" || true
done

echo "5. Creating and flashing logical dynamic partitions in super (active slot _a)..."
for p in system system_ext product vendor vendor_dlkm odm; do
    if [[ -f "${p}.img" ]]; then
        SZ=$(stat -f%z "${p}.img")
        fastboot create-logical-partition "${p}_a" "$SZ"
        fastboot flash "${p}_a" "${p}.img"
    fi
done

echo "DONE. Run 'fastboot -w' ONLY if switching from HyperOS/AOSP for the first time, then 'fastboot reboot'."
EOF
chmod +x "$OUT_DIR/flash_fastbootd.sh"
echo "Repack complete. Output images and flasher ready in: $OUT_DIR"
