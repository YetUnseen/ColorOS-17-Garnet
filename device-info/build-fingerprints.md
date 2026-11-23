# Build fingerprints

Read from the running device (`getprop`). Active build type `user`, tags `release-keys`
(properties inherited from the donor build; the bootloader is unlocked).

| Property | Value |
|---|---|
| `ro.build.fingerprint` | `OPPO/PKJ110/OP5DD3L1:17/AP3A.240617.008/V.9f5ecc_1cf914d_1ce5d22:user/release-keys` |
| `ro.build.display.id` | `PKJ110_17.0.1.201(CN01)` |
| `ro.build.version.release` | `17` |
| `ro.build.version.sdk` | `37` |
| `ro.build.version.security_patch` | `2026-11-01` |
| `ro.build.version.incremental` | `V.9f5ecc_1cf914d_1ce5d22` |
| `ro.system.build.fingerprint` | `qti/qssi/qssi:17/CP2A.260605.016/1794234241212:user/release-keys` |
| `ro.product.build.fingerprint` | `qti/qssi/qssi:17/CP2A.260605.016/1794234241212:user/release-keys` |
| `ro.system_ext.build.fingerprint` | `oplus/ossi/ossi:17/CP2A.260605.016/1794234241212:user/release-keys` |
| `ro.vendor.build.fingerprint`, `ro.odm.build.fingerprint`, `ro.bootimage.build.fingerprint` | same as `ro.build.fingerprint` |

## Flashed project images

| Image | SHA-256 |
|---|---|
| `system-lhbm-type-test.img` | `ecc60e57da933c515e9d64c653ee9612904d8dfd9fcc216d81984a1ac04c13a3` |
| `system-applock-vibrator-test.img` | `d46100fbfd32fe0fc893ded09432444f4b2f6cf6feedf5200093989acac189cf` |
| `system-padding-fix-test.img` (current) | `3160913cd4a77477dc5c900818924e2f70d3cbd107e904e320a4ae45d2ea4a14` |

Island overlay APKs in the current image (`/my_product/overlay/`):

| APK | SHA-256 |
|---|---|
| `garnet-island_padding.apk` | `b31580fbac6efcdeaed71e52f45abe957ea421614f97fb9c707a9b23170d3f82` |
| `garnet-island_statusbar.apk` | `af0ba3532f4c59f60d10a48119deeb44ac803e30cb6d842e88b61ce214d49b7c` |
