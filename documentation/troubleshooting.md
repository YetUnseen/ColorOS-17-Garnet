# Troubleshooting

## Boot / flashing
- **`Invalid sparse file format` when flashing:** normal for a raw EROFS image; fastboot then chunks it (`-S 128M`).
- **fastbootd not entered:** `fastboot getvar is-userspace` must say `yes`; use `adb reboot fastboot`.
- **Bootloop after flashing:** boot fastbootd (hold volume keys or `fastboot reboot fastboot`) and flash the previous known-good image.
- **Partition too small:** fastbootd resizes logical partitions; if it fails, check free space in `super`.

## Build host
- **`mnt_workspace` missing / "No such file":** the sparseimage was detached; run `source scripts/00_mount_workspace.sh`.
- **Overlay not applied / wrong label:** reapply `chmod 0644` and the SELinux xattr; confirm with `cmd overlay list`.
- **Hard-coded paths:** scripts reference the project path; update after moving the folder.

## Display
- **Island too big or too thin:** adjust `capsule_max_height_size` (island_padding) and the status bar overlay; see [../fixes/05-island-cutout-overlays.md](../fixes/05-island-cutout-overlays.md). Check `dumpsys` of SystemUI for `statusBarHeight`.
- **Island only appears with media/timer:** the island is triggered by apps (e.g. media playback); there is no dedicated clock app here.
- **Refresh rate flipping 60/30:** check `debug.sf.set_idle_timer_ms` is 0.
- **Flash at wake/AOD:** see [../fixes/01-wake-aod-flicker.md](../fixes/01-wake-aod-flicker.md).

## Features
- **No vibration:** check `dumpsys vibrator_manager`; see [../fixes/03-vibration.md](../fixes/03-vibration.md).
- **App lock fails:** check `service list | grep -i crypto` and `/data/system/garnet_pms.dat`; see [../fixes/04-app-lock-cryptoeng.md](../fixes/04-app-lock-cryptoeng.md).
- **Face unlock missing:** expected; no face HAL exists.
- **Cellular unavailable:** untested on this build.

## Useful commands
```sh
adb -s <serial> logcat -b all -d | head
adb -s <serial> shell dumpsys display | grep -i cutout
adb -s <serial> shell cmd overlay list | grep -i garnet
adb -s <serial> exec-out screencap -p > shot.png   # review for personal info before sharing
```
