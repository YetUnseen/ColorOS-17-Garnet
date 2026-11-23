# FOD press animation / keyguard patch

**Status: working on the awake lock screen, confirmed by the author.**

## Symptom
Fingerprint unlock worked, but the ColorOS press animation did not play on the lock screen.

## Cause
The donor ColorOS keyguard expects hardware/feature states from an ultrasonic-fingerprint device;
the Garnet's optical in-display sensor does not report them, so the animation path was skipped.

## Change
A smali patch of the authentication-animation methods in the ColorOS keyguard/SystemUI code
enables the press animation for the ported fingerprint path.

## Files
- `src/garnet_fod/patch_auth_animation.py`
- `src/garnet_fod/auth_animation_methods.smali`

## Limits
AOD fingerprint behaviour is outside the confirmed scope. The patch is tied to this ColorOS
build and will need rework for other versions.
