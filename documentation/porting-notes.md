# Porting notes

## Pipeline (`scripts/`)

| Script | Purpose |
|---|---|
| `00_mount_workspace.sh` | Mounts `workspace_cs.sparseimage` (case-sensitive APFS) at `./mnt_workspace` |
| `00b_download_firmwares.sh` | Downloads firmware packages (to `downloads/`) |
| `01_backup_device_partitions.sh` | Read-only backup of persist/modem/boot-related partitions (root adb or recovery) |
| `02_extract_firmwares.sh` | Extracts the donor/stock firmware into the workspace |
| `03_merge_and_patch_port.sh` | Stages the merged system tree and applies patches/props |
| `04_repack_erofs.sh` | Repacks partitions to EROFS images in `output/` |
| `build_garnet_island_overlays.sh`, `build_garnet_cutout_overlay.sh` | Build the resource overlay APKs |

Sources for patches live in `src/garnet_fod/` (FOD, LHBM shim, cryptoeng, auth animation) and
`src/garnet_vibrator/`; overlay sources in `configs/garnet_overlays/`.

External dependencies not redistributed in this repository:
- Stock Xiaomi `garnet` and donor OPPO `PKJ110` firmware packages (placed in `downloads/`).
- Optional/external Xiaomi `garnet` reference device-tree overlays for `scripts/03_merge_and_patch_port.sh` (supply via `GARNET_REF_OVERLAY_DIR` or `GARNET_REF_DEVICE_TREE`, or set `SKIP_REF_OVERLAYS=1`).
- Host tools listed in [../tools/TOOLCHAIN_STATUS.md](../tools/TOOLCHAIN_STATUS.md) and Android SDK (`ANDROID_SDK_ROOT` / `ANDROID_BUILD_TOOLS`).

## Case-sensitive workspace
Android trees need a case-sensitive filesystem. macOS volumes are case-insensitive by default, so
the work happens in a case-sensitive APFS sparse image mounted at `mnt_workspace/`. Remount with
`source scripts/00_mount_workspace.sh` after reboot or if the volume is detached.

## EROFS build
```sh
mkfs.erofs --quiet -b4096 -zlz4hc,9 --all-root --mount-point=/ output/<image>.img <tree>
```

## Isolated-candidate-image method (for small changes)
Never edit the tree of a flashed image. Instead:
1. `cp -c -R mnt_workspace/<known-good-build> mnt_workspace/<new-build>` (APFS clone, cheap).
2. Replace only the files under test.
3. Restore permissions and SELinux labels (see below).
4. Build a new, uniquely named image in `output/`.
5. Verify offline: `fsck.erofs --extract=<dir>` on both the new and the currently flashed image,
   then `diff -rq --no-dereference <old> <new>`; only the intended files may differ.
6. Flash, verify hashes on device, keep the previous image as rollback.

## SELinux labels after file replacement
Files copied on macOS lose `security.selinux`. For each replaced file:
```sh
chmod 0644 <file>
xattr -c <file>
xattr -w security.selinux "u:object_r:system_file:s0" <file>
```
(Use the label appropriate to the file's location; overlays in `/my_product/overlay` use `system_file`
in this build.) The build runs with SELinux permissive.

## Flashing
Only `system_a` via fastbootd with `-S 128M`; see [../INSTALLATION.md](../INSTALLATION.md).

## Large local artifacts
`output/` (~78 GB of images), `mnt_workspace/` (~126 GB), `workspace_cs.sparseimage` (~95 GB) and
`downloads/` (~17 GB) are build products and firmware that are not part of the distributable
documentation and must not be committed or redistributed.

## Overlay signing
Overlays are signed with the local Android debug key and built with `--no-resource-deduping`.
