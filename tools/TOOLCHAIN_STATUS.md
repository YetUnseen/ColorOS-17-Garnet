# Project Garnet — Toolchain Status

Verified on macOS (`Apple M1`, arm64).

> **Note on redistribution:** No third-party binaries (`tools/bin/`) or private signing keystores (`tools/garnet_overlay.jks`) are redistributed in this repository. Install or acquire the tools below from their upstream sources and keep all signing keys private.

## Installed Tools, Purpose & Sources

| Tool | Purpose | Version / Acquisition Source | Local Path | Status |
| :--- | :--- | :--- | :--- | :--- |
| `adb` / `fastboot` | Device communication, partition backup, and `fastbootd` flashing | Android Debug Bridge 1.0.41 (`brew install --cask android-platform-tools`) | `/opt/homebrew/bin/adb`, `/opt/homebrew/bin/fastboot` | Ready |
| `payload-dumper-go` | Extract partition images from OPPO/Oplus OTA `payload.bin` | 2.1.0 (`brew install payload-dumper-go`) | `/opt/homebrew/bin/payload-dumper-go` | Ready |
| `erofs-utils` (`mkfs.erofs`, `fsck.erofs`, `dump.erofs`) | Extract, inspect, and repack EROFS system images | 1.9.4 (`brew install erofs-utils`, supports `lz4`, `lz4hc`, `lzma`, `deflate`) | `/opt/homebrew/bin/mkfs.erofs` | Ready |
| `apktool` | Decode and rebuild framework JARs/APKs for smali patching | 3.0.3 (`brew install apktool`) | `/opt/homebrew/bin/apktool` | Ready |
| `jadx` | Decompile framework/SystemUI bytecode during reverse engineering | 1.5.7 (`brew install jadx`) | `/opt/homebrew/bin/jadx` | Ready |
| `simg2img` / `img2simg` | Convert between Android sparse and raw partition images | 1.1.5 (`brew install android-simg2img` / `simg2img`) | `/opt/homebrew/bin/simg2img`, `/opt/homebrew/bin/img2simg` | Ready |
| `lz4` / `zstd` | Compress/decompress firmware and ramdisk archives | 1.11.1 / 1.5.7_1 (`brew install lz4 zstd`) | `/opt/homebrew/bin/lz4`, `/opt/homebrew/bin/zstd` | Ready |
| `aarch64-elf-gcc` | Cross-compile `src/garnet_fod/garnet_lhbm_helper.c` into a static AArch64 ELF binary | Homebrew (`brew install aarch64-elf-gcc`) | `/opt/homebrew/bin/aarch64-elf-gcc` | Optional / Build |
| Android SDK build-tools (`aapt2`, `zipalign`, `apksigner`, `d8`) | Compile/sign resource overlays (`configs/garnet_overlays/`) and DEX Java patches | Android Studio / `sdkmanager` (`build-tools;36.0.0`, `platforms;android-37.0`) | `ANDROID_BUILD_TOOLS` env var | Build |
| `avbtool` | Inspect and generate Android Verified Boot (`vbmeta`) metadata/footers | 1.3.0 — acquire from LineageOS `android_external_avb` (`lineage-22.1`) or AOSP `external/avb` (Apache-2.0) | `tools/bin/avbtool` (excluded from git) | Ready |
| `magiskboot` | Unpack/repack Android `boot` / `vendor_boot` images and ramdisks | Standalone macOS arm64 — acquire from `PinNaCode/magiskboot_build` (`e159716`) or build from `topjohnwu/Magisk` (GPLv3) | `tools/bin/magiskboot` (excluded from git) | Ready |
| `lpunpack` | Unpack logical partitions from Xiaomi stock `super.img` | v1.0.7 — acquire from `soe1hom-arch/lpunpack-go` (`darwin-arm64`) or AOSP `system/extras/partition_tools` | `tools/bin/lpunpack` (excluded from git) | Ready |
| Python `.venv` | Run OTA query and binary/smali patching scripts (`protobuf`, `pycryptodome`, `requests`) | Python 3.15 (`python3 -m venv .venv && .venv/bin/pip install protobuf pycryptodome requests`) | `.venv/bin/python` (excluded from git) | Ready |

## Signing Keystore (Private)
- Overlay build scripts (`scripts/build_garnet_cutout_overlay.sh`, `scripts/build_garnet_island_overlays.sh`) require `GARNET_OVERLAY_KEYSTORE`, `GARNET_OVERLAY_KEY_ALIAS`, `GARNET_OVERLAY_STORE_PASSWORD`, and `GARNET_OVERLAY_KEY_PASSWORD` via environment variables.
- Generate your own local keystore with `keytool -genkeypair` (e.g., at `tools/garnet_overlay.jks`). All `*.jks` and `*.keystore` files are excluded via `.gitignore` and must never be committed.

## Notes
- `lpmake` does not ship a prebuilt macOS binary from the inspected GitHub mirrors and is **not required** when flashing individual logical images (`system.img`, `system_ext.img`, `product.img`, `vendor.img`, `vendor_dlkm.img`, `odm.img`) directly in `fastbootd` via `output/flash_fastbootd.sh`.
- All extracted Android partition root filesystems live inside the Case-Sensitive APFS sparse image mounted at `mnt_workspace/`.
