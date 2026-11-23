#!/usr/bin/env bash
# Mounts the Case-Sensitive APFS workspace volume and configures PATH & garnet specs.
# Usage: source scripts/00_mount_workspace.sh

PROJ="/Users/tahaermis/Desktop/ColorOS17-Garnet"
SPARSE_IMG="$PROJ/workspace_cs.sparseimage"
MNT_POINT="$PROJ/mnt_workspace"

if ! mount | grep -q "on $MNT_POINT "; then
    mkdir -p "$MNT_POINT"
    echo "Mounting Case-Sensitive APFS workspace at $MNT_POINT..."
    hdiutil attach "$SPARSE_IMG" -mountpoint "$MNT_POINT" -nobrowse >/dev/null
fi

FS_TYPE=$(diskutil info "$MNT_POINT" 2>/dev/null | awk -F: '/File System Personality/ {gsub(/^[ \t]+/, "", $2); print $2}')
if [[ "$FS_TYPE" != "Case-sensitive APFS" ]]; then
    echo "ERROR: $MNT_POINT is '$FS_TYPE', expected 'Case-sensitive APFS'!" >&2
    return 1 2>/dev/null || exit 1
fi

export PROJ
export MNT_POINT
export PATH="$PROJ/tools/bin:/opt/homebrew/bin:$PATH"

if [[ -f "$PROJ/configs/garnet_specs.env" ]]; then
    # shellcheck source=/dev/null
    source "$PROJ/configs/garnet_specs.env"
fi

echo "Workspace ready ($FS_TYPE): $MNT_POINT"
