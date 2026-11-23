# Device specifications

Collected from `getprop`/`dumpsys` on the running port. Serial number, IMEI, MAC addresses and
account data are intentionally omitted.

| Item | Value |
|---|---|
| Target device | Xiaomi Garnet (`ro.product.board=garnet`) |
| SoC | Qualcomm SM7435 (Snapdragon 7s Gen 2), platform `parrot`, `ro.hardware=qcom` |
| CPU ABI | arm64-v8a |
| RAM | about 11.5 GB (`MemTotal`) |
| Display | 1220 x 2712, density 480 dpi, modes 120 / 90 / 60 / 30 Hz |
| Stock cutout (Xiaomi) | `M 0,0 H -32 V 122 H 32 V 0 H 0 Z`; stock status bar 122 px; rounded corners 110 px |
| Kernel | 5.10.236-android12-9-00003-gfb24cf99ad97-ab14313284 (aarch64) |
| Vendor interface | Android 12 (`ro.vendor.build.version.release=12`, SDK 32) |
| Partitioning | A/B, active slot `_a`, dynamic partitions in `super`, `system` as EROFS |
| Bootloader | Unlocked (`ro.boot.flash.locked=0`), verified boot state `orange` |
| SELinux | Permissive (current build) |

## ROM identity (donor build)

| Item | Value |
|---|---|
| ColorOS version | 17.0.1 (oplusrom V17.0.0) |
| Display ID | `PKJ110_17.0.1.201(CN01)` |
| Android | 17, API level 37 |
| Security patch | 2026-11-01 |
| Product | model `PKJ110`, device `OP5DD3L1`, name `PKJ110`, brand/manufacturer `OPPO` |
| About-phone name | "Find X8 Ultra by YetUnseen" (branding via `ro.vendor.oplus.market.name`) |

The ROM base is the OPPO Find X8 Ultra (PKJ110) ColorOS build; hardware below the framework is
the Xiaomi Garnet's own vendor stack.

## Display cutout / island geometry

- Hole property: `ro.oplus.display.screenhole.positon=568,18:652,128` (110 px tall, centre y = 73).
  The donor value was `679,39:761,121`.
- Final island overlay values: see [../fixes/05-island-cutout-overlays.md](../fixes/05-island-cutout-overlays.md).
