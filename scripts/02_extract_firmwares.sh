#!/usr/bin/env bash
set -euo pipefail

# Extracts stock HyperOS (garnet) and donor ColorOS 17 (PKJ110) firmware archives
# into the Case-Sensitive APFS workspace, then unpacks EROFS images.

PROJ="/Users/tahaermis/Desktop/ColorOS17-Garnet"
# shellcheck source=/dev/null
source "$PROJ/scripts/00_mount_workspace.sh"

DL_DIR="$PROJ/downloads"
GARNET_WORK="$MNT_POINT/base_garnet"
DONOR_WORK="$MNT_POINT/donor_fx8u"

extract_ota_zip() {
    local zip_glob="$1"
    local work_dir="$2"
    local label="$3"

    local zip_file
    zip_file=$(compgen -G "$zip_glob" | head -n 1 || true)
    if [[ -z "$zip_file" || ! -f "$zip_file" ]]; then
        echo "ERROR: Missing firmware archive matching $zip_glob ($label)." >&2
        exit 1
    fi

    echo "=== [$label] Extracting payload.bin from $(basename "$zip_file") ==="
    mkdir -p "$work_dir/images" "$work_dir/extracted"
    rm -f "$work_dir/payload.bin"
    unzip -o -j "$zip_file" "payload.bin" -d "$work_dir"

    echo "=== [$label] Dumping partitions with payload-dumper-go ==="
    payload-dumper-go -o "$work_dir/images" "$work_dir/payload.bin"
    rm -f "$work_dir/payload.bin"
}

unpack_erofs_images() {
    local img_dir="$1"
    local out_dir="$2"
    shift 2
    local parts=("$@")

    for part in "${parts[@]}"; do
        local img="$img_dir/${part}.img"
        local target="$out_dir/$part"
        if [[ -f "$img" ]]; then
            echo "  -> Unpacking ${part}.img into $target ..."
            rm -rf "$target"
            mkdir -p "$target"
            fsck.erofs --extract="$target" --xattrs --preserve-perms "$img"
        else
            echo "  -> Skipping ${part}.img (not present)"
        fi
    done
}

extract_fastboot_tgz() {
    local tgz_glob="$1"
    local work_dir="$2"
    local label="$3"

    local tgz_file
    tgz_file=$(compgen -G "$tgz_glob" | head -n 1 || true)
    if [[ -z "$tgz_file" || ! -f "$tgz_file" ]]; then
        return 1
    fi

    echo "=== [$label] Extracting fastboot images from $(basename "$tgz_file") ==="
    mkdir -p "$work_dir/images" "$work_dir/extracted"
    tar -xzf "$tgz_file" --strip-components=2 -C "$work_dir/images" \
        "*/images/boot.img" \
        "*/images/vendor_boot.img" \
        "*/images/dtbo.img" \
        "*/images/vbmeta.img" \
        "*/images/vbmeta_system.img" \
        "*/images/super.img"

    if [[ -f "$work_dir/images/super.img" ]]; then
        local super_src="$work_dir/images/super.img"
        if file "$super_src" | grep -qi "Android sparse image"; then
            echo "=== [$label] Converting sparse super.img to raw image ==="
            simg2img "$super_src" "$work_dir/images/super.raw.img"
            rm -f "$super_src"
            super_src="$work_dir/images/super.raw.img"
        fi
        echo "=== [$label] Unpacking logical partitions from super image via lpunpack ==="
        lpunpack "$super_src" "$work_dir/images"
        rm -f "$super_src"

        for p in system system_ext product vendor vendor_dlkm odm; do
            if [[ -f "$work_dir/images/${p}_a.img" ]]; then
                mv -f "$work_dir/images/${p}_a.img" "$work_dir/images/${p}.img"
            fi
            rm -f "$work_dir/images/${p}_b.img"
        done
    fi
    return 0
}

if ! extract_fastboot_tgz "$DL_DIR/garnet_*.tgz" "$GARNET_WORK" "Target: garnet HyperOS"; then
    extract_ota_zip "$DL_DIR/garnet_*.zip" "$GARNET_WORK" "Target: garnet HyperOS"
fi
extract_ota_zip "$DL_DIR/PKJ110_*.zip" "$DONOR_WORK" "Donor: PKJ110 ColorOS 17"

echo "=== Unpacking garnet base EROFS partitions ==="
unpack_erofs_images "$GARNET_WORK/images" "$GARNET_WORK/extracted" \
    system system_ext product vendor vendor_dlkm odm

echo "=== Unpacking PKJ110 donor EROFS partitions ==="
unpack_erofs_images "$DONOR_WORK/images" "$DONOR_WORK/extracted" \
    system system_ext product \
    my_product my_stock my_heytap my_bigball my_region my_manifest \
    my_carrier my_company my_preload

echo "Firmware extraction and EROFS unpacking complete."
