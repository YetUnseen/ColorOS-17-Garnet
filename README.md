# ColorOS 17 for Xiaomi Redmi Note 13 Pro 5G (`garnet`) — Unofficial Port

An experimental, unofficial port of **ColorOS 17** (Android 17, API 37 base) to the **Xiaomi Redmi Note 13 Pro 5G** (codename `garnet`, Snapdragon 7s Gen 2 / SM7435, 1220x2712 panel). It boots and runs smoothly in daily use as reported by the developer, but it is an experimental hobby project: it is **not** bug-free, there is no official support from OPPO, OnePlus, Xiaomi, or Qualcomm, and several areas remain untested or subject to further regression testing (see [COMPATIBILITY.md](COMPATIBILITY.md)).

> **Warning:** Flashing custom system images can bootloop your device or cause data loss. Read [INSTALLATION.md](INSTALLATION.md) and back up critical partitions and user data first. You proceed at your own risk.

## What this repository contains

Only the project's own scripts, small source patches, resource-overlay sources, toolchain notes, screenshots, and documentation. **No proprietary firmware, system images, vendor binaries, compiled APKs/ELF binaries, third-party tool binaries, or signing keystores are redistributed here.**

Excluded from this repository (local-only on the developer's machine):
- Firmware packages, extracted trees, and built images (`downloads/`, `mnt_workspace/`, `workspace_cs.sparseimage`, `output/`, `logs/`, `backups/`)
- Bundled third-party host binaries (`tools/bin/`) — see [tools/TOOLCHAIN_STATUS.md](tools/TOOLCHAIN_STATUS.md) for required tools and where to obtain them
- Private overlay signing material (`tools/garnet_overlay.jks`, `*.jks`, `*.keystore`)
- Compiled overlay APKs (`*.apk`, `*.apk.idsig`) and compiled native helper (`src/garnet_fod/garnet_lhbm_helper`)
- Unverified third-party reference device tree files (`reference/android_device_xiaomi_garnet/`, `configs/reference_garnet/`), kept out of the initial publication until upstream origin and licensing are independently verified

## Port overview

| Item | Value |
|---|---|
| Base ROM | ColorOS 17.0.1 (`PKJ110_17.0.1.201(CN01)` build, Android 17 / API 37) |
| Target device | Xiaomi Redmi Note 13 Pro 5G (`ro.product.board=garnet`, platform `parrot`) |
| Vendor side | Stock Xiaomi vendor / kernel (Linux 5.10.236, vendor Android 12 interface) |
| Partition layout | A/B, logical partitions in `super`, `system` built as EROFS |
| Flashing method | `fastboot` in fastbootd (userspace), only `system_a` |
| Display | 1220x2712, 60/90/120 Hz, density 480 |
| Bootloader | Unlocked (required) |
| SELinux | **Permissive** in the current build |

## Features / status summary

- **Verified working (developer-confirmed on device):** ColorOS 17 boots on `garnet`, smooth daily use, fingerprint unlock and awake lock screen press animation, double-tap to wake, Always-On Display (AOD), wake/AOD flicker fix, Bluetooth pairing and audio, speaker, microphone, NFC, auto-brightness, 60/90/120 Hz refresh rate, proximity sensor and auto-rotation, torch, USB-C audio, OTG, GPS, Wi-Fi 5 GHz, wired charging, and camera in tested apps.
- **Known limitation:** **Face unlock** is unavailable because a compatible face HAL implementation was not found.
- **Pending verification / untested:** Cellular/SIM/calls/mobile data/VoLTE and other features not explicitly verified remain untested and subject to further regression testing. Wireless charging is not applicable (no hardware).

See [COMPATIBILITY.md](COMPATIBILITY.md) for the full breakdown.

## Notable fixes in this port

See [fixes/](fixes/) for the cause, change, files and status of each:

1. [Wake/AOD flicker](fixes/01-wake-aod-flicker.md)
2. [FOD press animation / keyguard patch](fixes/02-fod-press-animation.md)
3. [Vibration (VINTF instance)](fixes/03-vibration.md)
4. [App lock / privacy password (software cryptoeng)](fixes/04-app-lock-cryptoeng.md)
5. [Dynamic Island / cutout overlays](fixes/05-island-cutout-overlays.md)
6. [Smoothness properties](fixes/06-smoothness-props.md)

## Documentation

- [INSTALLATION.md](INSTALLATION.md): flashing, verification, rollback and risks
- [CHANGELOG.md](CHANGELOG.md): development history
- [COMPATIBILITY.md](COMPATIBILITY.md): verified working, known limitations, and untested functionality
- [tools/TOOLCHAIN_STATUS.md](tools/TOOLCHAIN_STATUS.md): host toolchain requirements and acquisition sources
- [device-info/](device-info/): device specs and build fingerprints
- [documentation/porting-notes.md](documentation/porting-notes.md) and [documentation/troubleshooting.md](documentation/troubleshooting.md)
- [screenshots/](screenshots/): screenshots from the running ROM

## License

The project's own scripts, source, overlay sources, and documentation are under the [MIT License](LICENSE).
OPPO / OnePlus / ColorOS, Xiaomi / HyperOS / MIUI, and Qualcomm firmware, binaries, and images are
proprietary to their owners, are **not** covered by that license, and are **not** distributed here.
You must obtain stock firmware yourself.

### Third-party dependencies & attribution

This repository does not redistribute third-party binaries or unverified device trees. Building or
patching images locally relies on external upstream tools (installed separately — see
[tools/TOOLCHAIN_STATUS.md](tools/TOOLCHAIN_STATUS.md)), including:

- Android SDK Platform-Tools & Build-Tools (`adb`, `fastboot`, `aapt2`, `zipalign`, `apksigner`, `d8`) — Android Open Source Project (Apache-2.0 / Android SDK License)
- `avbtool` (AOSP / LineageOS `android_external_avb`, Apache-2.0)
- `magiskboot` (`topjohnwu/Magisk` / `PinNaCode/magiskboot_build`, GPLv3)
- `lpunpack` (`soe1hom-arch/lpunpack-go` / AOSP `partition_tools`)
- `erofs-utils`, `apktool`, `jadx`, `payload-dumper-go`, `simg2img`, `lz4`, `zstd`, `aarch64-elf-gcc`, and Python packages (`protobuf`, `pycryptodome`, `requests`) — each governed by its respective upstream license.
