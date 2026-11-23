# Changelog

Reconstructed from the author's working session notes. Dates are 2026-11-22 to 2026-11-23.
"Confirmed" means the author verified it on device; otherwise the change is only applied.

## Unreleased / latest (2026-11-23)

### Changed
- **Dynamic Island resized to a modest size** (`output/system-padding-fix-test.img`, sha256
  `3160913c…a4a14`). The previous 165 px capsule / 168 px status bar made the island look far too
  thick. Now: `capsule_max_height_size` and `_high` = 120 px, `capsule_hole_safe_height_gap` = 5 dp,
  `status_bar_height_portrait/default` = 135 px (stock was 122 px). On device the container is
  125 px (y 10-135) and the visible capsule 120 px high. Awaiting the author's visual confirmation.
  See [fixes/05](fixes/05-island-cutout-overlays.md).
- Added project documentation (README, INSTALLATION, COMPATIBILITY, LICENSE, fixes/, documentation/).
- Prepared repository for initial GitHub publication: hardened `.gitignore` to exclude firmware, build outputs, backups, private signing material, compiled binaries/overlays, bundled third-party tools, and unverified reference device tree files; documented host toolchain acquisition in [tools/TOOLCHAIN_STATUS.md](tools/TOOLCHAIN_STATUS.md).

## 2026-11-23 (earlier)

### Fixed (applied, pending verification)
- **Vibration / vibrate mode:** `services.jar` now looks up
  `android.hardware.vibrator.IVibrator/vibratorfeature` instead of `/default`
  ([fixes/03](fixes/03-vibration.md)).
- **App lock (privacy password):** software `cryptoeng` stand-in registered in system server
  ([fixes/04](fixes/04-app-lock-cryptoeng.md)). Image `system-applock-vibrator-test.img`.

### Changed
- Smoothness properties applied (`persist.sys.oplus.anim_level=2`, render turbo, texture optimize,
  SurfaceFlinger idle timer 0, nandswap/hybridswap disabled) ([fixes/06](fixes/06-smoothness-props.md)).

### Fixed (confirmed)
- **Wake/AOD flicker:** the displaypanelfeature shim now returns `0x10` (local HBM) for feature
  `0xd3`, so SystemUI no longer draws `VRI-OnScreenFingerprintDimLayer`. Image
  `system-lhbm-type-test.img` (sha256 `ecc60e57…c13a3`). User: "flicker is gone solved"
  ([fixes/01](fixes/01-wake-aod-flicker.md)).

### Investigated
- Feature audit of what should work vs. what does not; face unlock found to have no HAL.
- Ruled out as flicker causes: refresh rate (tested at 60 Hz) and auto-brightness mode.

### Tried and failed
- Native-only patch of `libvibratorservice.so` (`system-vibrator-only-experimental.img`) was
  flashed but did not fix vibrate mode because the Java manager decided first.

## 2026-11-22

### Added / fixed
- Experimental **fingerprint press animation** patch for the awake lock screen, flashed together
  with the first island overlays (`system-fod-island-experimental.img`). Fingerprint unlock and
  press animation confirmed on the awake lock screen ([fixes/02](fixes/02-fod-press-animation.md)).
- **Island/cutout:** hole geometry enlarged from 84 to 110 px (centre unchanged,
  `ro.oplus.display.screenhole.positon=568,18:652,128`); static overlay
  `config_fillMainBuiltInDisplayCutout=false` removed the extra second punch-hole (confirmed).
  Island overlays 5 dp gap / 135 px status bar added. The author reported the island looked moved
  rather than thicker, and the physical camera interrupted its top edge. 175 px and 165 px
  candidates followed; 165 px ended up too big (the "bagel").
- **About device** branding set to `OPPO Find X8 Ultra by YetUnseen` via market-name properties.
- **Flicker (normal use):** SurfaceFlinger idle timer disabled early in init
  (`debug.sf.set_idle_timer_ms 0`) after logs showed 60→30→60 Hz switching about every 1.15 s.
  Normal-use flicker confirmed improved.
- Double-tap-to-wake was reported working without any change.

### Notes
- Combined image `system-all-staged-test.img` was the first flashed build with display fixes.
- Remaining wake flicker, brightness drops, dimmer AOD and face unlock were open at this point.
