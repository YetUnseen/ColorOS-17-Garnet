# Vibration

**Status: fix applied (in `system-applock-vibrator-test.img` and later), pending verification.**

## Symptom
No vibration / vibrate mode did nothing.

## Cause
The Garnet's vibrator HAL is Xiaomi's instance `android.hardware.vibrator.IVibrator/vibratorfeature`
(declared with override). The framework looked for `.../default`. A first attempt that patched only
the native `libvibratorservice.so` (`/default` → `/vibratorfeature`) failed because the Java layer
(`VintfHalVibratorManager` / `VintfHalVibrator`) decided first.

## Change
`services.jar` classes `VintfHalVibratorManager` and `VintfHalVibrator` now look up
`android.hardware.vibrator.IVibrator/vibratorfeature`.

## Files
- `src/garnet_vibrator/patch_vibrator_service.py`
- `src/garnet_vibrator/library_load_check.c` (library-load diagnostic)

## Limits
Oplus-specific haptic effect IDs may not all map to the Xiaomi HAL; some effects may feel wrong or
be missing. `VibratorManagerService` was confirmed running after boot; actual vibration awaits the
author's check.
