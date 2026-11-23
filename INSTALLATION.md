# Installation

> **Unofficial and experimental. You can lose data or bootloop your device. Nothing here is
> supported by OPPO, OnePlus, Xiaomi or Qualcomm. You are responsible for your device.**

This guide documents the procedure used by the author to flash updated `system` images to a
Garnet that already runs this port. It was exercised on one device only.

## Requirements

- Xiaomi Redmi Note 13 Pro 5G (`garnet`) with an **unlocked bootloader** (verified boot state `orange`).
- Slot **A** active, A/B with dynamic partitions (`super`).
- `adb` and `fastboot` (platform-tools) on the host, USB cable, battery well above 50%.
- Stock Xiaomi firmware for your region, kept available as a fallback.
- The system image you want to flash (built locally; not distributed here).

## 1. Back up first

Boot a custom recovery with root adb (OrangeFox/TWRP) and run:

```sh
export ANDROID_SERIAL=<your device serial>   # the script calls plain `adb`
scripts/01_backup_device_partitions.sh
```

It reads (never writes) `persist`, `modemst1`, `modemst2`, `fsg`, `boot_a`, `vendor_boot_a`,
`dtbo_a`, `vbmeta_a`, `vbmeta_system_a` into `backups/<timestamp>/` with SHA-256 sums.
`persist`/modem partitions contain device calibration data: keep them safe and **private**
(they can contain identifiers). Also back up your user data; a failed flash may require a wipe.

## 2. Verify the image

```sh
shasum -a 256 output/<image>.img
```

Images produced by this project (hashes are of the files on the author's machine):

| Image | SHA-256 | Notes |
|---|---|---|
| `system-lhbm-type-test.img` | `ecc60e57da933c515e9d64c653ee9612904d8dfd9fcc216d81984a1ac04c13a3` | Wake flicker fix |
| `system-applock-vibrator-test.img` | `d46100fbfd32fe0fc893ded09432444f4b2f6cf6feedf5200093989acac189cf` | Vibration + app lock + earlier 165 px island (too large); rollback image |
| `system-padding-fix-test.img` | `3160913cd4a77477dc5c900818924e2f70d3cbd107e904e320a4ae45d2ea4a14` | Same as above with modest island overlays (120 px capsule / 135 px status bar) |

`system-padding-fix-test.img` differs from `system-applock-vibrator-test.img` only in the two
island overlay APKs (verified by extracting both images and diffing).

## 3. Flash `system_a` through fastbootd

```sh
adb -s <serial> reboot fastboot
fastboot -s <serial> getvar is-userspace            # must print: is-userspace: yes
fastboot -s <serial> -S 128M flash system_a output/<image>.img
fastboot -s <serial> reboot
```

- An `Invalid sparse file format` line before chunking is normal for a raw EROFS image.
- fastbootd may resize the logical partition by a few KiB; this is expected.
- Flash only `system_a`. Do not touch other partitions for an image update.
- Wait for `sys.boot_completed=1`.

## 4. Verify

```sh
adb -s <serial> shell getprop sys.boot_completed
adb -s <serial> shell sha256sum /my_product/overlay/garnet-island_padding.apk \
                                /my_product/overlay/garnet-island_statusbar.apk
adb -s <serial> shell cmd overlay list | grep -i garnet
```

For the padding image the overlay hashes should be
`b31580fbac6efcdeaed71e52f45abe957ea421614f97fb9c707a9b23170d3f82` (padding) and
`af0ba3532f4c59f60d10a48119deeb44ac803e30cb6d842e88b61ce214d49b7c` (statusbar).

## Rollback

Repeat step 3 with the previous image (for the padding image, `system-applock-vibrator-test.img`).
Keep every earlier image until the new one is verified.

## Initial installation (not covered)

`output/flash_fastbootd.sh` is the original bring-up helper. It is **destructive**: it flashes
`vbmeta`, `boot`, `vendor_boot` and `dtbo`, deletes every logical partition inside `super` and
recreates them. It is not needed for image updates and should not be run casually. Treat a first
install as an advanced, at-your-own-risk operation; see
[documentation/porting-notes.md](documentation/porting-notes.md).

## Risks

- Logical-partition resize/recreation can fail; a wrong image can **bootloop**.
- **Data loss** is possible (a wipe may be required when switching from another ROM).
- SELinux is **permissive** in this build, which weakens device security.
- Unlocked bootloader / `orange` verified boot state: banking and other apps may refuse to run;
  Play Integrity will likely fail.
- Overlays are signed with a local debug/private keystore, not a release key; signing keystores (`*.jks`, `*.keystore`) are kept private and are not distributed in this repository.
- Cellular/SIM is untested; do not rely on this build as your only phone.
- Warranty and carrier terms may be affected.
