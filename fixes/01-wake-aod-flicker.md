# Wake / AOD flicker

**Status: fixed, confirmed by the author. ** Image `system-lhbm-type-test.img`.

## Symptom
A visible brightness flash/flicker when waking the screen or coming from AOD.

## Cause
SystemUI queries the `displaypanelfeature` service for feature `0xd3` (local HBM / fingerprint
dim type). The project's shim returned no value, so SystemUI fell back to drawing a software
`VRI-OnScreenFingerprintDimLayer` overlay, which caused the flash. Earlier suspects (60 Hz refresh
switching, auto-brightness) were ruled out.

## Change
The shim now answers feature `0xd3` with `0x10` (local HBM), so SystemUI no longer draws the dim layer.

## Files
- `src/garnet_fod/GarnetFodHelper.java` (compiled into `oplus-services.jar`)
- `src/garnet_fod/garnet_lhbm_helper.c`

## Notes
A separate, earlier fix for 60→30→60 Hz switching (SurfaceFlinger idle timer set to 0) is in
[06-smoothness-props.md](06-smoothness-props.md).
